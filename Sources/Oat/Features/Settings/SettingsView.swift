import SwiftUI

struct SettingsView: View {
    @AppStorage("enhancementProvider") private var enhancementProvider = EnhancementProvider.cloud
    @AppStorage("privacyMode") private var privacyMode = false
    @AppStorage("keepAudio") private var keepAudio = true
    @State private var apiKey = ""

    var body: some View {
        TabView {
            Form {
                Section("Note enhancement") {
                    Picker("Provider", selection: $enhancementProvider) {
                        ForEach(EnhancementProvider.allCases) { provider in
                            Text(provider.label).tag(provider)
                        }
                    }
                    .disabled(privacyMode)

                    Toggle("Privacy mode (fully local, no network)", isOn: $privacyMode)
                    if privacyMode {
                        Text("All enhancement and chat run on-device. Nothing leaves your Mac.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Anthropic API key") {
                    SecureField("sk-ant-…", text: $apiKey)
                    Text("Stored in your Keychain. Used for cloud (Claude) note enhancement.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Recordings") {
                    Toggle("Keep audio recordings on device", isOn: $keepAudio)
                    Text("Audio stays local and is never uploaded unless you enable sync.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("General", systemImage: "gearshape") }
        }
        .frame(width: 480, height: 420)
        .onAppear {
            apiKey = KeychainStore.get(NoteEngineFactory.apiKeyKeychainKey) ?? ""
        }
        .onChange(of: apiKey) { _, newValue in
            KeychainStore.set(newValue, for: NoteEngineFactory.apiKeyKeychainKey)
        }
    }
}
