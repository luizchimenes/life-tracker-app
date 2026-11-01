import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Replaces all app data from a backup. Provided by `ContentView`, which owns
/// the screens and takes them down while the data is swapped.
struct RestoreAppDataAction: Equatable {
    private let action: (LifeTrackerBackup) async throws -> BackupRestorer.Result

    init(_ action: @escaping (LifeTrackerBackup) async throws -> BackupRestorer.Result) {
        self.action = action
    }

    func callAsFunction(_ backup: LifeTrackerBackup) async throws -> BackupRestorer.Result {
        try await action(backup)
    }

    // Always the same root action.
    static func == (lhs: Self, rhs: Self) -> Bool { true }
}

extension EnvironmentValues {
    @Entry var restoreAppData = RestoreAppDataAction { _ in throw BackupError.applyFailed }
}

/// "Data & Backup" in App Settings.
struct BackupSettingsSection: View {
    @Environment(\.modelContext) private var modelContext

    @State private var isExporting = false
    @State private var exportedFile: ExportedFile?
    @State private var showsImporter = false
    @State private var pendingBackup: PendingBackup?
    @State private var errorMessage: String?

    struct ExportedFile: Identifiable {
        let url: URL
        var id: URL { url }
    }

    struct PendingBackup: Identifiable {
        let backup: LifeTrackerBackup
        let fileName: String
        var id: String { backup.createdAt + fileName }
    }

    var body: some View {
        Section {
            Button {
                exportBackup()
            } label: {
                HStack {
                    Label("Export Backup", systemImage: "square.and.arrow.up")
                    if isExporting {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .disabled(isExporting)

            Button {
                showsImporter = true
            } label: {
                Label("Restore Backup", systemImage: "arrow.counterclockwise")
            }
        } header: {
            Text("Data & Backup")
        } footer: {
            Text("A backup contains all your Finance and Habits data. It is a plain JSON file that anyone with access to it can read, so keep it somewhere private, like your iCloud Drive or Files.")
        }
#if canImport(UIKit)
        .sheet(item: $exportedFile, onDismiss: discardExport) { file in
            ShareSheet(url: file.url, onComplete: discardExport)
                .ignoresSafeArea()
        }
#endif
        .fileImporter(isPresented: $showsImporter, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url): open(url)
            case .failure: errorMessage = BackupError.unreadableFile.localizedDescription
            }
        }
        .sheet(item: $pendingBackup) { pending in
            BackupRestorePreviewView(backup: pending.backup, fileName: pending.fileName)
        }
        .alert("Backup", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func exportBackup() {
        isExporting = true
        Task {
            // Let the progress indicator appear before the synchronous export.
            try? await Task.sleep(for: .milliseconds(50))
            defer { isExporting = false }
            do {
                exportedFile = ExportedFile(url: try BackupFileExporter.export(from: modelContext))
            } catch {
                errorMessage = (error as? BackupError)?.localizedDescription ?? BackupError.corrupted.localizedDescription
            }
        }
    }

    private func discardExport() {
        if let exportedFile {
            BackupFileExporter.discard(exportedFile.url)
        }
        exportedFile = nil
    }

    /// Reads and validates the file; nothing is changed yet.
    private func open(_ url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        do {
            guard let data = try? Data(contentsOf: url) else { throw BackupError.unreadableFile }
            let backup = try BackupValidator.load(data)
            pendingBackup = PendingBackup(backup: backup, fileName: url.lastPathComponent)
        } catch {
            errorMessage = (error as? BackupError)?.localizedDescription ?? BackupError.corrupted.localizedDescription
        }
    }
}

/// What the backup contains, the replace-all warning, and the result.
struct BackupRestorePreviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.restoreAppData) private var restoreAppData

    let backup: LifeTrackerBackup
    let fileName: String

    @State private var showsConfirmation = false
    @State private var isRestoring = false
    @State private var result: BackupRestorer.Result?
    @State private var errorMessage: String?
    @State private var safetyCopy: BackupSettingsSection.ExportedFile?

    private var createdAt: Date? {
        ISO8601DateFormatter().date(from: backup.createdAt)
    }

    var body: some View {
        NavigationStack {
            List {
                if let result {
                    Section {
                        Label("Backup restored successfully", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.headline)
                    }
                    countsSection(result.counts, title: "Restored")
                    if let url = result.safetyCopyURL {
                        Section {
                            Button("Export Previous Data", systemImage: "square.and.arrow.up") {
                                safetyCopy = .init(url: url)
                            }
                        } footer: {
                            Text("A copy of the data you had before restoring was kept on this iPhone.")
                        }
                    }
                } else {
                    Section {
                        LabeledContent("File", value: fileName)
                        if let createdAt {
                            LabeledContent("Created") {
                                Text(createdAt, format: .dateTime.day().month(.wide).year().hour().minute().locale(AppLocalization.selectedLocale))
                            }
                        }
                        LabeledContent("Data Version", value: backup.appSchemaVersion)
                    }
                    countsSection(backup.data.counts, title: "Contents")
                    Section {
                        Label("This will replace the current LifeTracker data on this iPhone with the contents of this backup. Nothing is merged.", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    } footer: {
                        Text("A copy of your current data is saved on this iPhone before restoring. If anything fails, your current data stays as it is.")
                    }
                    Section {
                        Button(role: .destructive) {
                            showsConfirmation = true
                        } label: {
                            HStack {
                                Text("Replace All Data")
                                if isRestoring {
                                    Spacer()
                                    ProgressView()
                                        .accessibilityLabel("Restoring backup")
                                }
                            }
                        }
                        .disabled(isRestoring)
                    }
                }
            }
            .navigationTitle(result == nil ? "Restore Backup" : "Restore Complete")
            .toolbar {
                ToolbarItem(placement: result == nil ? .cancellationAction : .confirmationAction) {
                    Button(result == nil ? "Cancel" : "Done") { dismiss() }
                        .disabled(isRestoring)
                }
            }
            .interactiveDismissDisabled(isRestoring)
            .confirmationDialog("Replace all data?", isPresented: $showsConfirmation, titleVisibility: .visible) {
                Button("Replace All Data", role: .destructive) { restore() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Your current Finance and Habits data will be replaced by this backup.")
            }
            .alert("Restore Failed", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
#if canImport(UIKit)
            .sheet(item: $safetyCopy) { file in
                ShareSheet(url: file.url) { safetyCopy = nil }
                    .ignoresSafeArea()
            }
#endif
        }
    }

    private func countsSection(_ counts: BackupCounts, title: LocalizedStringKey) -> some View {
        Section(title) {
            LabeledContent("Transactions", value: "\(counts.transactions)")
            LabeledContent("Categories", value: "\(counts.categories)")
            LabeledContent("Credit Cards", value: "\(counts.creditCards)")
            LabeledContent("Card Invoices", value: "\(counts.creditCardInvoices)")
            LabeledContent("Recurring Transactions", value: "\(counts.recurringTransactions)")
            LabeledContent("Fixed Expenses", value: "\(counts.fixedBills)")
            LabeledContent("Fixed Bill Payments", value: "\(counts.fixedBillOccurrences)")
            LabeledContent("Budgets", value: "\(counts.categoryBudgets + counts.financeSettings)")
            LabeledContent("Habits", value: "\(counts.habits)")
            LabeledContent("Habit Completions", value: "\(counts.habitCompletions)")
        }
    }

    private func restore() {
        isRestoring = true
        Task {
            defer { isRestoring = false }
            do {
                result = try await restoreAppData(backup)
            } catch {
                errorMessage = (error as? BackupError)?.localizedDescription ?? BackupError.applyFailed.localizedDescription
            }
        }
    }
}
