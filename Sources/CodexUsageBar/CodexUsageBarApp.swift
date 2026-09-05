import AppKit
import SwiftUI
import CodexUsageCore

@main
struct CodexUsageBarApp {
    @MainActor static func main() {
        let application = NSApplication.shared
        let controller = StatusBarController()
        application.delegate = controller
        application.setActivationPolicy(.accessory)
        application.run()
        withExtendedLifetime(controller) {}
    }
}

struct UsagePanel: View {
    static let width: CGFloat = 320
    @ObservedObject var model: UsageModel
    @ObservedObject var updater: AppUpdateModel
    let language: CodexUsageLanguage
    var onSizeChange: (CGSize) -> Void = { _ in }
    var onThemeChange: (Bool) -> Void = { _ in }
    @AppStorage("snackTheme") private var snackTheme = true
    @State private var isShowingResetConfirmation = false
    @State private var selectedResetCreditID: String?

    private var strings: AppStrings { AppStrings(language: language) }
    private var accent: Color {
        snackTheme ? Color(red: 0.65, green: 0.95, blue: 0.40) : .accentColor
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            if let snapshot = model.snapshot {
                usageContent(snapshot)
            } else if let connectionIssue = model.connectionIssue {
                issueContent(connectionIssue)
            } else {
                loadingContent
            }

            if let connectionIssue = model.connectionIssue, model.snapshot != nil {
                Label(strings.issueMessage(connectionIssue), systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()
            footer
        }
        .padding(20)
        .frame(width: Self.width)
        .fixedSize(horizontal: false, vertical: true)
        .background {
            if snackTheme {
                Color(red: 0.12, green: 0.08, blue: 0.20)
            } else {
                SystemMenuMaterial()
            }
        }
        .tint(accent)
        .background {
            GeometryReader { geometry in
                Color.clear.preference(key: PanelSizeKey.self, value: geometry.size)
            }
        }
        .onPreferenceChange(PanelSizeKey.self, perform: onSizeChange)
        .onAppear { onThemeChange(snackTheme) }
        .onChange(of: snackTheme, perform: onThemeChange)
        .alert(strings.confirmResetTitle, isPresented: $isShowingResetConfirmation) {
            Button(strings.cancel, role: .cancel) {}
            Button(strings.useReset, role: .destructive) {
                model.consumeReset(creditId: selectedResetCreditID)
            }
        } message: {
            Text(strings.confirmResetMessage)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            CodexMark().frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text("Codex").font(.system(size: 14, weight: .semibold))
                Text(strings.weeklyLimit)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Menu {
                Picker(strings.appearance, selection: $snackTheme) {
                    Text("Classic").tag(false)
                    Text("Monster").tag(true)
                }
            } label: {
                Image(systemName: "paintpalette")
                    .font(.system(size: 14))
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(strings.appearance)
            .accessibilityLabel(strings.appearance)
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            AppUpdateView(updater: updater, language: language)
            Spacer(minLength: 8)
            Button { model.refresh() } label: {
                Image(systemName: "arrow.clockwise")
                    .rotationEffect(.degrees(model.isLoading ? 180 : 0))
                    .animation(.easeInOut(duration: 0.4), value: model.isLoading)
            }
            .disabled(model.isBusy)
            .help(model.snapshot.map { strings.updated(updatedTime($0.fetchedAt)) + " · " + strings.minuteRefresh } ?? strings.refresh)
            .accessibilityLabel(strings.refresh)
            Button { NSApplication.shared.terminate(nil) } label: {
                Image(systemName: "power")
            }
            .help(strings.quit)
            .accessibilityLabel(strings.quit)
        }
        .font(.system(size: 13))
        .foregroundStyle(.secondary)
        .buttonStyle(PanelButtonStyle())
    }

    private func usageContent(_ snapshot: UsageSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if snackTheme {
                VStack(spacing: 4) {
                    SnackBuddy(remaining: snapshot.remainingPercent)
                        .frame(height: 138)
                    Text(strings.monsterMood(snapshot.remainingPercent))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.bottom, 2)
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(snapshot.remainingPercent)")
                    .font(.system(size: 44, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text(strings.remainingSuffix)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 8) {
                ProgressView(value: Double(snapshot.remainingPercent), total: 100)
                    .tint(accent)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(strings.used(snapshot.usedPercent))
                    Spacer(minLength: 0)
                    if let resetsAt = snapshot.resetsAt {
                        Label(resetDate(resetsAt), systemImage: "clock.arrow.circlepath")
                            .help(strings.resets(resetDate(resetsAt)))
                    }
                }
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
            }

            if let resetCredits = snapshot.resetCredits, resetCredits.availableCount > 0 {
                resetCreditsContent(resetCredits)
            }
            if let resetNotice = model.resetNotice {
                resetNoticeContent(resetNotice)
            }
        }
    }

    private func resetCreditsContent(_ resetCredits: UsageResetCredits) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.counterclockwise.circle.fill")
                .font(.title3)
                .foregroundStyle(.tint)

            VStack(alignment: .leading, spacing: 2) {
                Text(strings.resetAvailable(resetCredits.availableCount))
                    .font(.caption.weight(.semibold))

                if let expiresAt = resetCredits.nextCredit?.expiresAt {
                    Text(strings.resetExpires(expiresAt.formatted(.dateTime.day().month(.abbreviated).locale(language.locale)), count: resetCredits.availableCount))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .help(strings.resetExpires(expirationDate(expiresAt), count: resetCredits.availableCount))
                        .accessibilityLabel(strings.resetExpires(expirationDate(expiresAt), count: resetCredits.availableCount))
                }
            }

            Spacer(minLength: 6)

            Button {
                selectedResetCreditID = resetCredits.nextCredit?.id
                isShowingResetConfirmation = true
            } label: {
                if model.isConsumingReset {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text(strings.useReset)
                }
            }
            .disabled(model.isBusy)
            .controlSize(.small)
        }
        .padding(12)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func resetNoticeContent(_ notice: UsageResetNotice) -> some View {
        Label(strings.resetNotice(notice), systemImage: resetNoticeIcon(notice))
            .font(.caption)
            .foregroundStyle(resetNoticeColor(notice))
            .fixedSize(horizontal: false, vertical: true)
    }

    private func resetNoticeIcon(_ notice: UsageResetNotice) -> String {
        switch notice {
        case .reset, .alreadyRedeemed:
            return "checkmark.circle.fill"
        case .nothingToReset, .noCredit, .unknown:
            return "info.circle.fill"
        case .failure:
            return "exclamationmark.triangle.fill"
        }
    }

    private func resetNoticeColor(_ notice: UsageResetNotice) -> Color {
        switch notice {
        case .reset, .alreadyRedeemed:
            return .green
        case .nothingToReset, .noCredit, .unknown:
            return .secondary
        case .failure:
            return .orange
        }
    }

    @ViewBuilder
    private func issueContent(_ issue: UsageConnectionIssue) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(strings.issueTitle(issue), systemImage: issueIcon(issue))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)
            Text(strings.issueMessage(issue))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                switch issue {
                case .codexMissing:
                    Button(strings.getCodex) {
                        openCodexWebsite()
                    }
                case .signInRequired:
                    Button(strings.openCodex) {
                        openCodex()
                    }
                    Button(strings.copyCodexLogin) {
                        copyToPasteboard("codex login")
                    }
                case .chatGPTAccountRequired:
                    Button(strings.openCodex) {
                        openCodex()
                    }
                    Button(strings.copySignInSteps) {
                        copyToPasteboard("codex logout && codex login")
                    }
                case .unsupportedAccount, .generic:
                    Button(strings.tryAgain) {
                        model.refresh()
                    }
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .padding(.top, 4)
        }
    }

    private func issueIcon(_ issue: UsageConnectionIssue) -> String {
        switch issue {
        case .codexMissing:
            return "square.and.arrow.down"
        case .signInRequired, .chatGPTAccountRequired:
            return "person.crop.circle.badge.exclamationmark"
        case .unsupportedAccount, .generic:
            return "exclamationmark.triangle.fill"
        }
    }

    private var loadingContent: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text(strings.readingUsage)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12)
    }

    private func resetDate(_ date: Date) -> String {
        date.formatted(
            Date.FormatStyle()
                .weekday(.abbreviated)
                .day()
                .month(.abbreviated)
                .hour()
                .minute()
                .locale(language.locale)
        )
    }

    private func updatedTime(_ date: Date) -> String {
        date.formatted(
            Date.FormatStyle()
                .hour()
                .minute()
                .locale(language.locale)
        )
    }

    private func expirationDate(_ date: Date) -> String {
        date.formatted(
            Date.FormatStyle()
                .day()
                .month(.abbreviated)
                .hour()
                .minute()
                .locale(language.locale)
        )
    }

    private func openCodex() {
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.openai.codex") {
            NSWorkspace.shared.openApplication(
                at: appURL,
                configuration: NSWorkspace.OpenConfiguration()
            )
        } else {
            openCodexWebsite()
        }
    }

    private func openCodexWebsite() {
        if let webURL = URL(string: "https://chatgpt.com/codex") {
            NSWorkspace.shared.open(webURL)
        }
    }

    private func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

private struct PanelSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}

/// Let AppKit resolve menu colors, vibrancy, contrast, and transparency from system preferences.
private struct SystemMenuMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .menu
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

struct PanelButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(minWidth: 24, minHeight: 24)
            .contentShape(RoundedRectangle(cornerRadius: 6))
            .background(configuration.isPressed ? Color.primary.opacity(0.08) : .clear,
                        in: RoundedRectangle(cornerRadius: 6))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

private struct AppStrings {
    let language: CodexUsageLanguage

    var appearance: String { text("Utseende", "Appearance") }
    var minuteRefresh: String { text("Uppdateras varje minut", "Refreshes every minute") }

    func monsterMood(_ remaining: Int) -> String {
        switch remaining {
        case 50...: return text("Mmm. Mätt på tokens.", "Mmm. Stuffed with tokens.")
        case 20..<50: return text("Har du fler tokens?", "Got any more tokens?")
        case 1..<20: return text("Hungrig på tokens…", "Hungry for tokens…")
        default: return text("Drömmer om tokens…", "Dreaming of tokens…")
        }
    }

    var weeklyLimit: String {
        text("Veckogräns", "Weekly limit")
    }

    var refresh: String {
        text("Uppdatera", "Refresh")
    }

    var openCodex: String {
        text("Öppna Codex", "Open Codex")
    }

    var quit: String {
        text("Avsluta", "Quit")
    }

    var remainingSuffix: String {
        text("% kvar", "% left")
    }

    var getCodex: String {
        text("Hämta Codex", "Get Codex")
    }

    var copyCodexLogin: String {
        text("Kopiera codex login", "Copy codex login")
    }

    var copySignInSteps: String {
        text("Kopiera inloggningssteg", "Copy sign-in steps")
    }

    var tryAgain: String {
        text("Försök igen", "Try again")
    }

    var useReset: String {
        text("Använd", "Use")
    }

    var cancel: String {
        text("Avbryt", "Cancel")
    }

    var confirmResetTitle: String {
        text("Använd återställningen?", "Use this reset?")
    }

    var confirmResetMessage: String {
        text(
            "Detta förbrukar en återställning och återställer direkt de Codex-gränser som är berättigade. Åtgärden kan inte ångras.",
            "This consumes one reset and immediately resets the eligible Codex limits. This action cannot be undone."
        )
    }

    var readingUsage: String {
        text("Läser användning från Codex…", "Reading usage from Codex…")
    }

    func used(_ percent: Int) -> String {
        text("\(percent)% använt", "\(percent)% used")
    }

    func resets(_ date: String) -> String {
        text("Återställs \(date)", "Resets \(date)")
    }

    func updated(_ time: String) -> String {
        text("Uppdaterad \(time)", "Updated \(time)")
    }

    func resetAvailable(_ count: Int) -> String {
        if count == 1 {
            return text("1 återställning tillgänglig", "1 reset available")
        }
        return text("\(count) återställningar tillgängliga", "\(count) resets available")
    }

    func resetExpires(_ date: String, count: Int) -> String {
        if count == 1 {
            return text("Går ut \(date)", "Expires \(date)")
        }
        return text("Närmaste går ut \(date)", "Next expires \(date)")
    }

    func resetNotice(_ notice: UsageResetNotice) -> String {
        switch notice {
        case .reset:
            return text(
                "Återställningen användes. Gränserna är uppdaterade.",
                "The reset was used. Your limits are up to date."
            )
        case .alreadyRedeemed:
            return text(
                "Återställningen var redan använd. Gränserna är uppdaterade.",
                "The reset had already been used. Your limits are up to date."
            )
        case .nothingToReset:
            return text(
                "Ingen användningsgräns kan återställas just nu.",
                "No usage limit can be reset right now."
            )
        case .noCredit:
            return text(
                "Det finns ingen återställning kvar att använda.",
                "There are no resets left to use."
            )
        case .unknown(let value):
            return text(
                "Codex returnerade resultatet: \(value)",
                "Codex returned the result: \(value)"
            )
        case .failure(let message):
            return text(
                "Kunde inte använda återställningen: \(message)",
                "The reset could not be used: \(message)"
            )
        }
    }

    func issueTitle(_ issue: UsageConnectionIssue) -> String {
        switch issue {
        case .codexMissing:
            return text("Codex behöver installeras", "Codex needs to be installed")
        case .signInRequired:
            return text("Logga in med ChatGPT", "Sign in with ChatGPT")
        case .chatGPTAccountRequired:
            return text("ChatGPT-inloggning krävs", "ChatGPT sign-in required")
        case .unsupportedAccount:
            return text("Kontot stöds inte", "Account not supported")
        case .generic:
            return text("Kunde inte läsa användningen", "Could not read usage")
        }
    }

    func issueMessage(_ issue: UsageConnectionIssue) -> String {
        switch issue {
        case .codexMissing:
            return text(
                "Installera Codex Desktop eller Codex CLI på den här datorn.",
                "Install Codex Desktop or Codex CLI on this Mac."
            )
        case .signInRequired:
            return text(
                "Logga in med ChatGPT i Codex. Appen använder sedan samma lokala konto automatiskt.",
                "Sign in with ChatGPT in Codex. The app will then use the same local account automatically."
            )
        case .chatGPTAccountRequired:
            return text(
                "Du är inloggad med en API-nyckel. Byt till ChatGPT-inloggning för att läsa prenumerationens veckogräns.",
                "You are signed in with an API key. Switch to ChatGPT sign-in to read your subscription's weekly limit."
            )
        case .unsupportedAccount:
            return text(
                "Det aktiva Codex-kontot rapporterar ingen veckogräns som appen kan visa.",
                "The active Codex account does not report a weekly limit that the app can display."
            )
        case .generic(let message):
            return message
        }
    }

    private func text(_ swedish: String, _ english: String) -> String {
        language.text(swedish: swedish, english: english)
    }
}

private struct CodexMark: View {
    var body: some View {
        Image(nsImage: OfficialCodexMark.image)
            .resizable()
            .renderingMode(.template)
            .aspectRatio(contentMode: .fit)
            .accessibilityHidden(true)
    }
}

private enum OfficialCodexMark {
    static let image: NSImage = {
        let bundledURL = Bundle.main.url(
            forResource: "OpenAIBlossom@2x",
            withExtension: "png"
        )
        let installedURL = URL(
            fileURLWithPath: "/Applications/ChatGPT.app/Contents/Resources/chatgptTemplate@2x.png"
        )

        let image = [bundledURL, installedURL]
            .compactMap { $0 }
            .compactMap(NSImage.init(contentsOf:))
            .first
            ?? NSImage(systemSymbolName: "command", accessibilityDescription: "Codex")
            ?? NSImage(size: NSSize(width: 18, height: 18))

        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        return image
    }()
}
