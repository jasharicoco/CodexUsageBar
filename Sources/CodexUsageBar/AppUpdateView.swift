import AppKit
import CodexUsageCore
import SwiftUI

struct AppUpdateView: View {
    @ObservedObject var updater: AppUpdateModel
    let language: CodexUsageLanguage

    private func text(_ swedish: String, _ english: String) -> String {
        language.text(swedish: swedish, english: english)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let release = updater.release {
                Label(text("Version \(release.version.string) finns", "Version \(release.version.string) available"),
                      systemImage: "arrow.down.circle.fill")
                    .font(.caption.weight(.semibold))
                HStack {
                    Button(text("Uppdatera och starta om", "Update and restart")) { updater.install() }
                        .buttonStyle(.borderedProminent)
                        .disabled(updater.isInstalling || updater.isChecking)
                    Spacer(minLength: 0)
                    Link(text("Nyheter", "What’s new"), destination: release.pageURL)
                }
                .controlSize(.small)
            }

            if updater.isInstalling {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(text("Hämtar och förbereder uppdatering…", "Downloading and preparing update…"))
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                HStack {
                    Text("v\(updater.currentVersion)")
                        .foregroundStyle(.secondary)
                    Spacer()
                    if updater.isChecking {
                        ProgressView().controlSize(.small)
                        Text(text("Söker…", "Checking…"))
                    } else {
                        Button(text("Sök appuppdatering", "Check for app updates")) { updater.check() }
                            .buttonStyle(.borderless)
                    }
                    Menu {
                        Toggle(text("Sök automatiskt", "Check automatically"), isOn: $updater.automaticChecks)
                        Link(text("Releaser på GitHub", "Releases on GitHub"), destination: AppRelease.releasesURL)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .accessibilityLabel(text("Inställningar för appuppdateringar", "App update settings"))
                }
            }

            if let error = updater.errorMessage {
                Text(error)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                Link(text("Uppdatera manuellt via GitHub", "Update manually through GitHub"),
                     destination: updater.release?.pageURL ?? AppRelease.releasesURL)
            } else if updater.hasChecked && updater.release == nil && !updater.isChecking {
                Text(text("Du har den senaste versionen", "You’re up to date"))
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption2)
    }
}
