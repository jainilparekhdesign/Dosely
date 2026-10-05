import UIKit
import Vision

/// On-device OCR (Apple Vision). Returns text rows top-to-bottom, with cells in a row joined left-to-right,
/// so table-style prescriptions ("Name | Dose | Frequency") come out as one line per medicine.
enum TextRecognizer {
    struct Box {
        let text: String
        let rect: CGRect
    }

    static func recognizeLines(in image: UIImage) async throws -> [String] {
        guard let cgImage = image.normalizedForOCR().cgImage else { return [] }
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        // Language correction "fixes" drug names into dictionary words, so keep it off.
        request.usesLanguageCorrection = false
        let observations = try await request.perform(on: cgImage)
        let boxes = observations.compactMap { obs -> Box? in
            guard let text = obs.topCandidates(1).first?.string, !text.isEmpty else { return nil }
            return Box(text: text, rect: obs.boundingBox.cgRect)
        }
        return groupIntoRows(boxes)
    }

    /// Vision coordinates are normalised with origin at bottom-left.
    static func groupIntoRows(_ boxes: [Box]) -> [String] {
        let sorted = boxes.sorted { $0.rect.midY > $1.rect.midY }
        var rows: [[Box]] = []
        for box in sorted {
            if let last = rows.last, let ref = last.first,
               abs(ref.rect.midY - box.rect.midY) < min(ref.rect.height, box.rect.height) * 0.6 {
                rows[rows.count - 1].append(box)
            } else {
                rows.append([box])
            }
        }
        return rows.map { row in row.sorted { $0.rect.minX < $1.rect.minX }.map(\.text).joined(separator: "  ") }
    }
}

extension UIImage {
    /// Upright orientation and at most 3000 px on the long side.
    func normalizedForOCR(maxDimension: CGFloat = 3000) -> UIImage {
        let longest = max(size.width, size.height)
        let scale = longest > maxDimension ? maxDimension / longest : 1
        if scale == 1 && imageOrientation == .up { return self }
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
    }

    /// JPEG suitable for storing alongside a prescription or as a pill photo.
    func storageJPEG(maxDimension: CGFloat = 2000, quality: CGFloat = 0.75) -> Data? {
        normalizedForOCR(maxDimension: maxDimension).jpegData(compressionQuality: quality)
    }
}
