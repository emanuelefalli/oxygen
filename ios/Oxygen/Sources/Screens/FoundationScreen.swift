import SwiftUI

struct FoundationScreen: View {
    let runner: SyncRunner
    let store: RawStoring
    let keyStore: StrapKeyStoring
    let lastSync: LastSyncRecord
    let profileExpiration: Date?

    @State private var keyText = ""
    @State private var keyMessage: String?
    @State private var summaryRows: [RecordSummaryRow] = []
    @State private var archiveURL: URL?
    @State private var exportMessage: String?

    private static let rangeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "d MMM HH:mm"
        return formatter
    }()

    var body: some View {
        List {
            statusSection
            strapSection
            keySection
            dataSection
            syncSection
            exportSection
            resignSection
        }
        .onAppear(perform: refreshSummary)
        .onChange(of: runner.state) { _, newState in
            guard newState.phase == .idle else { return }
            refreshSummary()
        }
    }

    private var resignStatus: ResignStatus {
        ResignStatus.evaluate(expiration: profileExpiration, now: Date())
    }

    // MARK: Sections

    private var statusSection: some View {
        Section("Status") {
            Text(SyncStatusText.make(state: runner.state, lastSyncCompletedAt: lastSync.load(), now: Date(),
                                     timeZone: .current))
            if let banner = ResignStatusText.banner(resignStatus) {
                Text(banner)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var strapSection: some View {
        Section("Strap") {
            Text(batteryText)
        }
    }

    private var keySection: some View {
        Section("Auth key") {
            SecureField("Auth key", text: $keyText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Save key", action: saveKey)
            if let keyMessage {
                Text(keyMessage)
                    .foregroundStyle(.red)
            }
        }
    }

    private var dataSection: some View {
        Section("Data") {
            ForEach(summaryRows) { row in
                HStack {
                    VStack(alignment: .leading) {
                        Text(row.fetchType.displayName)
                        Text(rangeText(row))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(row.count)")
                        .monospacedDigit()
                }
            }
        }
    }

    private var syncSection: some View {
        Section("Sync") {
            Button("Sync") {
                runner.receive(.syncRequested)
            }
        }
    }

    private var exportSection: some View {
        Section("Export") {
            Button("Export", action: export)
            if let archiveURL {
                ShareLink(item: archiveURL)
            }
            if let exportMessage {
                Text(exportMessage)
                    .foregroundStyle(.red)
            }
        }
    }

    private var resignSection: some View {
        Section("Re-sign") {
            Text(ResignStatusText.line(resignStatus))
        }
    }

    // MARK: Text

    private var batteryText: String {
        guard let percent = runner.deviceSummary?.batteryPercent else { return "Battery unknown" }
        return "Battery \(percent)%"
    }

    private func rangeText(_ row: RecordSummaryRow) -> String {
        guard let oldest = row.oldest, let newest = row.newest else { return "No records" }
        return Self.rangeFormatter.string(from: oldest) + " to " + Self.rangeFormatter.string(from: newest)
    }

    // MARK: Actions

    private func saveKey() {
        guard let key = StrapAuthKey.parse(keyText) else {
            keyMessage = "The key must be 32 hexadecimal characters."
            return
        }
        do {
            try keyStore.save(key)
        } catch {
            keyMessage = "The key could not be saved to the Keychain."
            return
        }
        keyMessage = nil
        runner.receive(.authKeyEntered)
        keyText = ""
    }

    private func refreshSummary() {
        let rounds = (try? store.allRounds()) ?? []
        let records = rounds.flatMap { (try? StrapRecordDecoder.decode($0)) ?? [] }
        summaryRows = RecordSummary.make(records: RecordDeduplicator.merge(records))
    }

    private func export() {
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        do {
            archiveURL = try ExportBundleWriter.makeArchive(
                store: store,
                transitionLogText: TransitionLog(lines: runner.transitionLogLines).renderedText(),
                appVersion: appVersion,
                upstreamKitCommit: BuildConstants.upstreamKitCommit,
                exportTime: Date(),
                timeZone: .current,
                into: FileManager.default.temporaryDirectory)
            exportMessage = nil
        } catch {
            archiveURL = nil
            exportMessage = "Export failed."
        }
    }
}
