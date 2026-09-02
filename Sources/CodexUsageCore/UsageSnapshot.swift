import Foundation

public struct UsageSnapshot: Equatable {
    public let usedPercent: Int
    public let windowDurationMinutes: Int?
    public let resetsAt: Date?
    public let planType: String?
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
            fetchedAt: fetchedAt
        )
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
