import PDFKit
import SwiftUI

struct ReportView: View {
    let profile: Profile?
    let meds: [Medication]
    @Environment(\.dismiss) private var dismiss
    @State private var days = 30
    @State private var url: URL?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Period", selection: $days) {
                    Text("7 days").tag(7)
                    Text("30 days").tag(30)
                    Text("90 days").tag(90)
                }
                .pickerStyle(.segmented)
                .padding()

                if let url {
                    PDFPreview(url: url)
                        .background(Color(.secondarySystemBackground))
                } else {
                    ProgressView().frame(maxHeight: .infinity)
                }
            }
            .navigationTitle("Adherence report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    if let url {
                        ShareLink(item: url, preview: SharePreview("Medication report", image: Image(systemName: "doc.richtext"))) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                    }
                }
            }
            .task(id: days) {
                url = ReportGenerator.makePDF(profileName: profile?.name ?? "Me", meds: meds, days: days)
            }
        }
    }
}

private struct PDFPreview: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.backgroundColor = .secondarySystemBackground
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        view.document = PDFDocument(url: url)
    }
}
