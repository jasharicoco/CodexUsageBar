import Foundation

public enum CodexUsageLanguage: Equatable {
    case swedish
    case english

    public static func preferred(
        from preferredLanguages: [String] = Locale.preferredLanguages
    ) -> CodexUsageLanguage {
        guard let identifier = preferredLanguages.first?.lowercased() else {
            return .english
        }

        let normalized = identifier.replacingOccurrences(of: "_", with: "-")
        return normalized == "sv" || normalized.hasPrefix("sv-") ? .swedish : .english
    }

    public var locale: Locale {
        let languageCode = self == .swedish ? "sv" : "en"
        let fallbackRegion = self == .swedish ? "SE" : "US"
        let region = Locale.current.region?.identifier ?? fallbackRegion
        return Locale(identifier: "\(languageCode)_\(region)")
    }

    public func text(swedish: String, english: String) -> String {
        self == .swedish ? swedish : english
    }
}

enum CoreStrings {
    static let language = CodexUsageLanguage.preferred()

    static func text(swedish: String, english: String) -> String {
        language.text(swedish: swedish, english: english)
    }
}
