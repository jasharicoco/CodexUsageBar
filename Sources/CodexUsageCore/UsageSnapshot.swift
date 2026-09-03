import Foundation

public struct UsageResetCredit: Equatable, Identifiable {
    public let id: String
    public let resetType: String?
    public let status: String?
    public let grantedAt: Date?
    public let expiresAt: Date?
    public let title: String?
    public let description: String?
}

public struct UsageResetCredits: Equatable {
    public let availableCount: Int
    public let credits: [UsageResetCredit]?

    public var nextCredit: UsageResetCredit? {
        credits?
            .filter { $0.status == nil || $0.status == "available" }
            .min { first, second in
                switch (first.expiresAt, second.expiresAt) {
                case let (firstDate?, secondDate?):
                    return firstDate < secondDate
                case (.some, .none):
                    return true
                case (.none, .some):
                    return false
                case (.none, .none):
                    return false
                }
            }
    }
}

public enum UsageResetOutcome: Equatable {
    case reset
    case alreadyRedeemed
    case nothingToReset
    case noCredit
    case unknown(String)
}

public struct UsageSnapshot: Equatable {
    public let usedPercent: Int
    public let windowDurationMinutes: Int?
    public let resetsAt: Date?
    public let planType: String?
    public let resetCredits: UsageResetCredits?
    public let fetchedAt: Date

    public var remainingPercent: Int {
        min(100, max(0, 100 - usedPercent))
    }
}

enum UsageParsingError: LocalizedError {
    case invalidResponse
    case server(String)
    case missingCodexLimit

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return CoreStrings.text(
                swedish: "Codex svarade med data som inte kunde tolkas.",
                english: "Codex returned data that could not be interpreted."
            )
        case .server(let message):
            return message
        case .missingCodexLimit:
            return CoreStrings.text(
                swedish: "Ingen veckogräns för Codex hittades för kontot.",
                english: "No weekly Codex limit was found for the account."
            )
        }
    }
}

enum UsageResetParsingError: LocalizedError {
    case invalidResponse
    case server(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return CoreStrings.text(
                swedish: "Codex svarade med ett ogiltigt resultat för återställningen.",
                english: "Codex returned an invalid reset result."
            )
        case .server(let message):
            return message
        }
    }
}

public enum UsageResponseParser {
    public static func parse(_ data: Data, fetchedAt: Date = Date()) throws -> UsageSnapshot {
        guard
            let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw UsageParsingError.invalidResponse
        }

        if let error = payload["error"] as? [String: Any] {
            let message = error["message"] as? String ?? CoreStrings.text(
                swedish: "Codex kunde inte läsa användningsgränsen.",
                english: "Codex could not read the usage limit."
            )
            throw UsageParsingError.server(message)
        }

        guard let result = payload["result"] as? [String: Any] else {
            throw UsageParsingError.invalidResponse
        }

        let bucket: [String: Any]?
        if
            let buckets = result["rateLimitsByLimitId"] as? [String: Any],
            let codex = buckets["codex"] as? [String: Any]
        {
            bucket = codex
        } else {
            bucket = result["rateLimits"] as? [String: Any]
        }

        guard let bucket else {
            throw UsageParsingError.missingCodexLimit
        }

        let windows = ["primary", "secondary"].compactMap { key -> [String: Any]? in
            bucket[key] as? [String: Any]
        }

        // Weekly windows are normally 10,080 minutes. Prefer the longest
        // reported window so this remains correct if Codex also returns a
        // shorter rolling window in the same bucket.
        let weeklyWindow = windows.max {
            integer($0["windowDurationMins"]) ?? 0 < integer($1["windowDurationMins"]) ?? 0
        }

        guard
            let weeklyWindow,
            let usedPercent = integer(weeklyWindow["usedPercent"])
        else {
            throw UsageParsingError.missingCodexLimit
        }

        let resetTimestamp = integer(weeklyWindow["resetsAt"])
        let resetsAt = resetTimestamp.map { Date(timeIntervalSince1970: TimeInterval($0)) }

        return UsageSnapshot(
            usedPercent: min(100, max(0, usedPercent)),
            windowDurationMinutes: integer(weeklyWindow["windowDurationMins"]),
            resetsAt: resetsAt,
            planType: bucket["planType"] as? String,
            resetCredits: resetCredits(result["rateLimitResetCredits"]),
            fetchedAt: fetchedAt
        )
    }

    private static func resetCredits(_ value: Any?) -> UsageResetCredits? {
        guard
            let payload = value as? [String: Any],
            let availableCount = integer(payload["availableCount"])
        else {
            return nil
        }

        let credits = (payload["credits"] as? [[String: Any]])?.compactMap { credit -> UsageResetCredit? in
            guard let id = credit["id"] as? String, !id.isEmpty else {
                return nil
            }

            return UsageResetCredit(
                id: id,
                resetType: credit["resetType"] as? String,
                status: credit["status"] as? String,
                grantedAt: integer(credit["grantedAt"])
                    .map { Date(timeIntervalSince1970: TimeInterval($0)) },
                expiresAt: integer(credit["expiresAt"])
                    .map { Date(timeIntervalSince1970: TimeInterval($0)) },
                title: credit["title"] as? String,
                description: credit["description"] as? String
            )
        }

        return UsageResetCredits(
            availableCount: max(0, availableCount),
            credits: credits
        )
    }

    public static func parseResetOutcome(_ data: Data) throws -> UsageResetOutcome {
        guard
            let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw UsageResetParsingError.invalidResponse
        }

        if let error = payload["error"] as? [String: Any] {
            let message = error["message"] as? String ?? CoreStrings.text(
                swedish: "Återställningen kunde inte användas.",
                english: "The reset could not be used."
            )
            throw UsageResetParsingError.server(message)
        }

        guard
            let result = payload["result"] as? [String: Any],
            let outcome = result["outcome"] as? String
        else {
            throw UsageResetParsingError.invalidResponse
        }

        switch outcome {
        case "reset":
            return .reset
        case "alreadyRedeemed":
            return .alreadyRedeemed
        case "nothingToReset":
            return .nothingToReset
        case "noCredit":
            return .noCredit
        default:
            return .unknown(outcome)
        }
    }

    private static func integer(_ value: Any?) -> Int? {
        if let value = value as? Int {
            return value
        }
        if let value = value as? NSNumber {
            return value.intValue
        }
        return nil
    }
}
