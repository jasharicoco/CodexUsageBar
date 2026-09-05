import AppKit
import CodexUsageCore
import SwiftUI

struct AppUpdateView: View {
    @ObservedObject var updater: AppUpdateModel
    let language: CodexUsageLanguage
    var onInstall: () -> Void = {}

    private func text(_ swedish: String, _ english: String) -> String {
        language.text(swedish: swedish, english: english)
    }

    var body: some View {
        HStack(spacing: 4) {
            Text("v\(updater.currentVersion)")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.tertiary)
                .help(text("Appversion · högerklicka för uppdateringsalternativ", "App version · right-click for update options"))
                .contextMenu {
                    Button(text("Sök appuppdatering", "Check for app updates")) { updater.check() }
                        .disabled(updater.isChecking || updater.isInstalling)
                    Toggle(text("Sök automatiskt", "Check automatically"), isOn: $updater.automaticChecks)
                    Link(text("Releaser på GitHub", "Releases on GitHub"), destination: AppRelease.releasesURL)
                    if let error = updater.errorMessage { Text(error) }
                }

            if updater.isInstalling {
                ProgressView()
                    .controlSize(.mini)
                    .frame(width: 24, height: 24)
                    .help(text("Hämtar och installerar uppdatering…", "Downloading and installing update…"))
                    .accessibilityLabel(text("Installerar uppdatering", "Installing update"))
            } else if let release = updater.release {
                Button(action: onInstall) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.tint)
                }
                .disabled(updater.isChecking)
                .help(text("Installera \(release.version.string) och starta om", "Install \(release.version.string) and restart"))
                .accessibilityLabel(text("Uppdatera till \(release.version.string) och starta om", "Update to \(release.version.string) and restart"))
            }
        }
        .buttonStyle(PanelButtonStyle())
    }
}
