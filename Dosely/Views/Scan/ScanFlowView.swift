import PhotosUI
import SwiftData
import SwiftUI
import VisionKit

/// Scan → read → review → save. Nothing is written to the database until the user taps Save.
struct ScanFlowView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(Prefs.useOnDeviceAI) private var useAI = true
    @AppStorage(Prefs.verifyWithRxNorm) private var verifyOnline = false

    enum Stage {
        case choose
        case reading(UIImage)
        case review(UIImage, ScanPipeline.Output)
        case failed(UIImage?, String)
    }

    @State private var stage: Stage = .choose
    @State private var showDocumentCamera = false
    @State private var photoItem: PhotosPickerItem?

    var body: some View {
        NavigationStack {
            Group {
                switch stage {
                case .choose:
                    chooseView
                case .reading(let image):
                    ReadingView(image: image)
                        .task { await read(image) }
                case .review(let image, let output):
                    ScanReviewView(image: image, output: output, onSaved: { dismiss() })
                case .failed(let image, let message):
                    failedView(image: image, message: message)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        .interactiveDismissDisabled(isReviewing)
        #if DEBUG
        .onAppear { if let image = DebugSupport.sampleScanImage, case .choose = stage { stage = .reading(image) } }
        #endif
        .fullScreenCover(isPresented: $showDocumentCamera) {
            DocumentCamera { image in
                showDocumentCamera = false
                if let image { stage = .reading(image) }
            }
            .ignoresSafeArea()
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    stage = .reading(image)
                } else {
                    stage = .failed(nil, "Couldn't open that photo. Try another one.")
                }
                photoItem = nil
            }
        }
    }

    private var isReviewing: Bool {
        if case .review = stage { return true }
        return false
    }

    private var chooseView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Image(systemName: "doc.text.viewfinder")
                    .font(.system(size: 56)).foregroundStyle(.tint).symbolRenderingMode(.hierarchical)
                    .padding(.top, 12)
                Text("Scan a prescription").font(.largeTitle.bold())
                Text("Lay the prescription flat in good light. Dosely reads it on your iPhone and shows you everything to check before saving.")
                    .foregroundStyle(.secondary)

                VStack(spacing: 12) {
                    if VNDocumentCameraViewController.isSupported {
                        Button { showDocumentCamera = true } label: {
                            Label("Use camera", systemImage: "camera.fill")
                        }
                        .primaryButton()
                    }
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Label("Choose a photo", systemImage: "photo.on.rectangle")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .buttonBorderShape(.roundedRectangle(radius: 14))
                }
                .padding(.top, 8)

                VStack(alignment: .leading, spacing: 14) {
                    FeatureRow(icon: "character.book.closed", title: "Understands shorthand",
                               text: "OD, BD, TDS, QID, HS, SOS, PRN, q8h, 1-0-1, 5/7 and Indian brand names.")
                    FeatureRow(icon: "checkmark.shield", title: "You stay in control",
                               text: "Anything we're unsure about is highlighted for you to check.")
                    FeatureRow(icon: "iphone", title: "Read on-device",
                               text: AIExtractor.isAvailable && useAI ? "Text recognition and Apple Intelligence run privately on this iPhone."
                                                                     : "Text recognition runs privately on this iPhone.")
                }
                .padding(.top, 12)
            }
            .padding(24)
        }
    }

    private func failedView(image: UIImage?, message: String) -> some View {
        VStack(spacing: 16) {
            ContentUnavailableView("Couldn't read that", systemImage: "exclamationmark.magnifyingglass", description: Text(message))
            Button("Try again") { stage = .choose }.primaryButton().padding(.horizontal, 24)
            if let image {
                Button("Enter medicines by hand") {
                    stage = .review(image, ScanPipeline.Output(parsed: ParsedPrescription(), lines: [], usedAI: false))
                }
            }
        }
        .padding(.bottom, 32)
    }

    private func read(_ image: UIImage) async {
        do {
            let output = try await ScanPipeline.run(image: image, useAI: useAI, verifyOnline: verifyOnline)
            if output.lines.isEmpty {
                stage = .failed(image, "We couldn't find any text. Try again with more light and the whole page in view.")
            } else {
                withAnimation { stage = .review(image, output) }
            }
        } catch {
            stage = .failed(image, error.localizedDescription)
        }
    }
}

private struct ReadingView: View {
    let image: UIImage
    @State private var phase = 0
    private let messages = ["Reading the text…", "Finding medicines…", "Decoding doses and timings…", "Almost there…"]

    var body: some View {
        VStack(spacing: 24) {
            Image(uiImage: image)
                .resizable().scaledToFit()
                .frame(maxHeight: 340)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(ScanLine())
                .shadow(radius: 8, y: 4)
            ProgressView()
            Text(messages[phase % messages.count])
                .font(.headline)
                .contentTransition(.opacity)
                .animation(.easeInOut, value: phase)
        }
        .padding(24)
        .frame(maxHeight: .infinity)
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1.6))
                phase += 1
            }
        }
    }
}

private struct ScanLine: View {
    @State private var down = false
    var body: some View {
        GeometryReader { geo in
            LinearGradient(colors: [.clear, Color.accentColor.opacity(0.5), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 40)
                .offset(y: down ? geo.size.height - 40 : 0)
                .animation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true), value: down)
                .onAppear { down = true }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .allowsHitTesting(false)
    }
}

/// VisionKit document camera: auto edge detection, perspective correction.
struct DocumentCamera: UIViewControllerRepresentable {
    var onFinish: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let vc = VNDocumentCameraViewController()
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let onFinish: (UIImage?) -> Void
        init(onFinish: @escaping (UIImage?) -> Void) { self.onFinish = onFinish }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            onFinish(scan.pageCount > 0 ? scan.imageOfPage(at: 0) : nil)
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) { onFinish(nil) }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) { onFinish(nil) }
    }
}
