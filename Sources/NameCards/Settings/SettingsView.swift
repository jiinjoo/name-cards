import NameCardsCore
import SwiftUI

struct SettingsView: View {
    let session: CardSession

    var body: some View {
        TabView {
            GeneralSettings(session: session)
                .tabItem { Label("General", systemImage: "gearshape") }
            ClaudeSettings()
                .tabItem { Label("Claude", systemImage: "sparkles") }
        }
        .frame(width: 520)
        .padding(20)
    }
}

private struct GeneralSettings: View {
    let session: CardSession
    @AppStorage(AppSettings.Key.defaultRegion) private var region = Locale.current.region?.identifier ?? "US"
    @AppStorage(AppSettings.Key.addToEventGroup) private var addToEventGroup = true
    @AppStorage(AppSettings.Key.useCardAsPhoto) private var useCardAsPhoto = false

    var body: some View {
        Form {
            Section {
                Picker("Default country for phone numbers", selection: $region) {
                    ForEach(PhoneNumbers.supportedRegions, id: \.self) { code in
                        Text("\(Locale.current.localizedString(forRegionCode: code) ?? code) (+\(PhoneNumbers.callingCode(for: code) ?? ""))")
                            .tag(code)
                    }
                }
                Text("Used when a card doesn't show its country through its address, email or website.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("When saving to Contacts") {
                Toggle("Add contacts to a group named after the event", isOn: $addToEventGroup)
                Toggle("Use the card image as the contact photo if there isn't one", isOn: $useCardAsPhoto)
            }
            Section("Scanned cards") {
                LabeledContent("Saved to Contacts") {
                    Button("Remove \(session.savedCount) Saved Card\(session.savedCount == 1 ? "" : "s")") {
                        session.clearSaved()
                    }
                    .disabled(session.savedCount == 0)
                }
                LabeledContent("Card images and session") {
                    Button("Show in Finder") { NSWorkspace.shared.open(session.directory) }
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct ClaudeSettings: View {
    @AppStorage(AppSettings.Key.useClaude) private var useClaude = false
    @State private var apiKey = APIKeyStore.load() ?? ""
    @State private var savedKey = APIKeyStore.load() ?? ""
    @State private var testResult: String?
    @State private var testing = false

    var body: some View {
        Form {
            Section {
                Toggle("Improve field detection with Claude", isOn: $useClaude)
                Text("After each card is read on this Mac, the text read from it, and nothing else, is sent to Claude (\(ClaudeParser.model)) to label the fields. Card images never leave this Mac. Requests are billed to your Anthropic API account.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Anthropic API key") {
                SecureField("sk-ant-…", text: $apiKey)
                HStack {
                    if !savedKey.isEmpty && apiKey == savedKey {
                        Label("Saved in your Keychain", systemImage: "lock.fill").foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Save Key") {
                        if APIKeyStore.save(apiKey) { savedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines) }
                    }
                    .disabled(apiKey == savedKey)
                    Button(testing ? "Testing…" : "Test") { Task { await test() } }
                        .disabled(savedKey.isEmpty || testing)
                }
                if let testResult {
                    Text(testResult).font(.caption).foregroundStyle(testResult.hasPrefix("✓") ? .green : .orange)
                }
                Link("Get an API key in the Claude Console", destination: URL(string: "https://platform.claude.com/")!)
                    .font(.caption)
            }
            .disabled(!useClaude)
        }
        .formStyle(.grouped)
    }

    /// Sends a tiny made-up card to check the key works.
    private func test() async {
        testing = true
        defer { testing = false }
        let sample = [OCRLine(text: "Jane Example", box: CGRect(x: 0, y: 0.8, width: 0.5, height: 0.08)),
                      OCRLine(text: "jane@example.com", box: CGRect(x: 0, y: 0.6, width: 0.5, height: 0.04))]
        do {
            let draft = try await ClaudeParser(apiKey: savedKey).parse(sample, region: AppSettings.defaultRegion)
            testResult = "✓ Connected. Claude read the sample as “\(draft.displayName)”."
        } catch {
            testResult = error.localizedDescription
        }
    }
}
