#if canImport(UIKit)
import Foundation

/// Renders the report and writes it to a temporary file for sharing.
/// Generated entirely on device; nothing is uploaded.
enum FinancialReportPDFExporter {
    static var exportDirectory: URL {
        FileManager.default.temporaryDirectory.appending(path: "LifeTrackerExports", directoryHint: .isDirectory)
    }

    static func export(_ content: FinancialReportPDFContent) throws -> URL {
        let data = FinancialReportPDFDocument(content: content).render()
        // Only the latest export is kept.
        try? FileManager.default.removeItem(at: exportDirectory)
        try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)
        let url = exportDirectory.appending(path: content.fileName)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        return url
    }

    static func discard(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}
#endif
