import AppKit
import SwiftUI
import CodexUsageCore

@main
struct CodexUsageBarApp: App {
    @StateObject private var model = UsageModel()
    @AppStorage("snackTheme") private var snackTheme = true
    private let language = CodexUsageLanguage.preferred()

    var body: some Scene {
        MenuBarExtra {
            Group {
                if snackTheme {
                    UsagePanel(model: model, language: language)
                } else {
                    ClassicUsagePanel(model: model, language: language)
                        .contextMenu {
                            Button("Monster theme") { snackTheme = true }
                        }
                }
            }
            .onChange(of: snackTheme) { enabled in
                model.setRefreshInterval(enabled ? 60 : 5 * 60)
            }
        } label: {
            Text(model.menuBarText)
                .monospacedDigit()
                .onAppear {
                    model.start(refreshInterval: snackTheme ? 60 : 5 * 60)
                }
        }
        .menuBarExtraStyle(.window)
    }
}

private struct UsagePanel: View {
    @Environment(\.colorScheme) private var systemColorScheme
    @ObservedObject var model: UsageModel
    let language: CodexUsageLanguage
    @AppStorage("snackTheme") private var snackTheme = true
    @State private var isShowingResetConfirmation = false
    @State private var selectedResetCreditID: String?

    private var strings: AppStrings {
        AppStrings(language: language)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 16) {
                CodexMark().frame(width: 18, height: 18)
                    .help("Codex weekly usage")
                Spacer()
                Button { model.refresh() } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(model.isBusy)
                .help("Refresh · automatically every minute")
                .accessibilityLabel(strings.refresh)
                Menu {
                    Picker("Theme", selection: $snackTheme) {
                        Text("Classic").tag(false)
                        Text("Monster").tag(true)
                    }
                } label: {
                    Image(systemName: "paintpalette")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Theme")
                .accessibilityLabel("Theme")
                Button { openCodex() } label: {
                    Image(systemName: "arrow.up.forward.app")
                }
                .help(strings.openCodex)
                .accessibilityLabel(strings.openCodex)
                Button { NSApplication.shared.terminate(nil) } label: {
                    Image(systemName: "power")
                }
                .help(strings.quit)
                .accessibilityLabel(strings.quit)
            }
            .buttonStyle(.borderless)
            .font(.system(size: 14))

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


        }
        .padding(snackTheme ? 20 : 16)
        .frame(width: 290)
        .background(snackTheme ? Color(red: 0.12, green: 0.08, blue: 0.20) : Color(nsColor: .windowBackgroundColor))
        .foregroundStyle(snackTheme ? Color(red: 0.95, green: 0.91, blue: 1) : Color.primary)
        .tint(snackTheme ? Color(red: 0.65, green: 0.95, blue: 0.40) : Color.accentColor)
        .environment(\.colorScheme, snackTheme ? .dark : systemColorScheme)
        .alert(strings.confirmResetTitle, isPresented: $isShowingResetConfirmation) {
            Button(strings.cancel, role: .cancel) {}
            Button(strings.useReset, role: .destructive) {
                model.consumeReset(creditId: selectedResetCreditID)
            }
        } message: {
            Text(strings.confirmResetMessage)
        }
    }

    @ViewBuilder
    private func usageContent(_ snapshot: UsageSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if snackTheme {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        SnackBuddy(remaining: snapshot.remainingPercent)
                            .frame(width: 230, height: 150)
                        Text(snapshot.remainingPercent >= 50 ? "Mmm. Stuffed with tokens." : snapshot.remainingPercent >= 20 ? "Got any more tokens?" : snapshot.remainingPercent > 0 ? "Hungry for tokens…" : "Dreaming of tokens…")
                            .font(.system(size: 12, weight: .medium))
                    }
                    Spacer()
                }
                .padding(.vertical, 4)
            }

            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text("\(snapshot.remainingPercent)")
                    .help("Weekly usage remaining")
                    .accessibilityLabel("\(snapshot.remainingPercent) percent weekly usage remaining")
                    .font(.system(size: 40, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text(snackTheme ? "%" : strings.remainingSuffix)
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: Double(snapshot.remainingPercent), total: 100)
                .tint(snackTheme ? Color(red: 0.65, green: 0.95, blue: 0.40) : progressColor(snapshot.remainingPercent))

            HStack {
                Image(systemName: "chart.pie")
                    .help(strings.used(snapshot.usedPercent))
                    .accessibilityLabel(strings.used(snapshot.usedPercent))
                Spacer()
                if let resetsAt = snapshot.resetsAt {
                    Label(resetDate(resetsAt), systemImage: "clock.arrow.circlepath")
                        .help(strings.resets(resetDate(resetsAt)))
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

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
                .foregroundStyle(.blue)

            VStack(alignment: .leading, spacing: 2) {
                Text(strings.resetAvailable(resetCredits.availableCount))
                    .font(.caption.weight(.semibold))

                if let expiresAt = resetCredits.nextCredit?.expiresAt {
                    Text(strings.resetExpires(expirationDate(expiresAt), count: resetCredits.availableCount))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
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
        .padding(10)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
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

    private func progressColor(_ remainingPercent: Int) -> Color {
        switch remainingPercent {
        case 50...:
            return .green
        case 20..<50:
            return .orange
        default:
            return .red
        }
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

private struct ClassicUsagePanel: View {
    @ObservedObject var model: UsageModel
    let language: CodexUsageLanguage
    @State private var isShowingResetConfirmation = false
    @State private var selectedResetCreditID: String?

    private var strings: AppStrings {
        AppStrings(language: language)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                CodexMark()
                    .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Codex")
                        .font(.headline)
                    Text(strings.weeklyLimit)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if model.isBusy {
                    ProgressView()
                        .controlSize(.small)
                }
            }

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

            HStack {
                Button {
                    model.refresh()
                } label: {
                    Label(strings.refresh, systemImage: "arrow.clockwise")
                }
                .disabled(model.isBusy)

                Spacer()

                Button(strings.openCodex) {
                    openCodex()
                }

                Button(strings.quit) {
                    NSApplication.shared.terminate(nil)
                }
            }
            .buttonStyle(.borderless)
            .font(.caption)
        }
        .padding(16)
        .frame(width: 340)
        .alert(strings.confirmResetTitle, isPresented: $isShowingResetConfirmation) {
            Button(strings.cancel, role: .cancel) {}
            Button(strings.useReset, role: .destructive) {
                model.consumeReset(creditId: selectedResetCreditID)
            }
        } message: {
            Text(strings.confirmResetMessage)
        }
    }

    @ViewBuilder
    private func usageContent(_ snapshot: UsageSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text("\(snapshot.remainingPercent)")
                    .font(.system(size: 40, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text(strings.remainingSuffix)
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: Double(snapshot.remainingPercent), total: 100)
                .tint(progressColor(snapshot.remainingPercent))

            HStack {
                Text(strings.used(snapshot.usedPercent))
                Spacer()
                if let resetsAt = snapshot.resetsAt {
                    Text(strings.resets(resetDate(resetsAt)))
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if let resetCredits = snapshot.resetCredits, resetCredits.availableCount > 0 {
                resetCreditsContent(resetCredits)
            }

            if let resetNotice = model.resetNotice {
                resetNoticeContent(resetNotice)
            }

            Text(strings.updated(updatedTime(snapshot.fetchedAt)))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private func resetCreditsContent(_ resetCredits: UsageResetCredits) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.counterclockwise.circle.fill")
                .font(.title3)
                .foregroundStyle(.blue)

            VStack(alignment: .leading, spacing: 2) {
                Text(strings.resetAvailable(resetCredits.availableCount))
                    .font(.caption.weight(.semibold))

                if let expiresAt = resetCredits.nextCredit?.expiresAt {
                    Text(strings.resetExpires(expirationDate(expiresAt), count: resetCredits.availableCount))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
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
        .padding(10)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
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

    private func progressColor(_ remainingPercent: Int) -> Color {
        switch remainingPercent {
        case 50...:
            return .green
        case 20..<50:
            return .orange
        default:
            return .red
        }
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

private struct AppStrings {
    let language: CodexUsageLanguage

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
