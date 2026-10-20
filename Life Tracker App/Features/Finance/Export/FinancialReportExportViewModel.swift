#if canImport(UIKit)
import Foundation
import Observation

/// Drives "Export PDF": builds the content for the selected cycle, renders it
/// and hands the file to the share sheet. Read-only on SwiftData.
@Observable
final class FinancialReportExportViewModel {
    struct ExportedFile: Identifiable {
        let url: URL
        var id: URL { url }
    }

    private(set) var isExporting = false
    var exportedFile: ExportedFile?
    var errorMessage: String?

    func export(_ makeContent: @escaping () -> FinancialReportPDFContent?) async {
        guard !isExporting else { return }
        isExporting = true
        defer { isExporting = false }
        // Let the progress indicator appear before the synchronous render.
        try? await Task.sleep(for: .milliseconds(50))

        guard let content = makeContent() else {
            errorMessage = AppLocalization.string("Report Unavailable")
            return
        }
        do {
            exportedFile = ExportedFile(url: try FinancialReportPDFExporter.export(content))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func finishSharing() {
        if let exportedFile {
            FinancialReportPDFExporter.discard(exportedFile.url)
        }
        exportedFile = nil
    }
}
#endif
