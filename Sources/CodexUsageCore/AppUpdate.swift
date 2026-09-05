import CryptoKit
import Foundation

/// Stable, three-component release versions. Prereleases are never installed.
public struct AppVersion: Comparable, Equatable {
    public let string: String
    private let components: [Int]

    public init?(_ value: String) {
        let value = value.hasPrefix("v") ? String(value.dropFirst()) : value
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isASCII && $0.isNumber }
                  && ($0.count == 1 || $0.first != "0") }),
              parts.compactMap({ Int($0) }).count == 3 else { return nil }
        string = value
        components = parts.compactMap { Int($0) }
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.components.lexicographicallyPrecedes(rhs.components)
    }
}

public enum AppUpdateError: Error, Equatable, LocalizedError {
    case invalidRelease, invalidChecksum, invalidArchive, invalidBundle, installLocation
    case http(Int)
    case commandFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidRelease:
            return CoreStrings.text(swedish: "Releasen saknar giltiga uppdateringsfiler.", english: "The release is missing valid update files.")
        case .invalidChecksum:
            return CoreStrings.text(swedish: "Den hämtade filen klarade inte integritetskontrollen. Försök igen.", english: "The downloaded file failed its integrity check. Please try again.")
        case .invalidArchive, .invalidBundle:
            return CoreStrings.text(swedish: "Uppdateringen innehåller inte en giltig, kompatibel app.", english: "The update does not contain a valid, compatible app.")
        case .installLocation:
            return CoreStrings.text(swedish: "Appen kan inte ersättas här. Flytta den till Program eller uppdatera manuellt via GitHub.", english: "The app cannot be replaced here. Move it to Applications or update manually through GitHub.")
        case .http(let status):
            return CoreStrings.text(swedish: "GitHub kunde inte nås (HTTP \(status)). Försök igen senare.", english: "GitHub could not be reached (HTTP \(status)). Try again later.")
        case .commandFailed:
            return CoreStrings.text(swedish: "Uppdateringen kunde inte förberedas. Den installerade appen har inte ändrats.", english: "The update could not be prepared. The installed app has not changed.")
        }
    }
}

public struct AppRelease: Equatable {
    public static let repositoryURL = URL(string: "https://github.com/jasharicoco/CodexUsageBar")!
    public static let releasesURL = repositoryURL.appendingPathComponent("releases/latest")
    public let version: AppVersion
    public let archiveURL: URL
    public let checksumURL: URL
    public var pageURL: URL { Self.repositoryURL.appendingPathComponent("releases/tag/v\(version.string)") }
    public var archiveName: String { "CodexUsageBar-v\(version.string)-macOS-universal.zip" }

    private struct Response: Decodable {
        let tag_name: String
        let draft: Bool
        let prerelease: Bool
        let assets: [Asset]
        struct Asset: Decodable {
            let name: String
            let browser_download_url: URL
        }
    }

    public static func newerRelease(from data: Data, currentVersion: AppVersion) throws -> Self? {
        let response = try JSONDecoder().decode(Response.self, from: data)
        guard !response.draft, !response.prerelease else { return nil }
        guard let version = AppVersion(response.tag_name) else { throw AppUpdateError.invalidRelease }
        guard version > currentVersion else { return nil }
        let name = "CodexUsageBar-v\(version.string)-macOS-universal.zip"
        let base = repositoryURL.appendingPathComponent("releases/download/\(response.tag_name)")
        // Only accept exact asset URLs in our own repository, never arbitrary feed URLs.
        func asset(_ name: String) throws -> URL {
            let expected = base.appendingPathComponent(name)
            guard response.assets.contains(where: { $0.name == name && $0.browser_download_url == expected }) else {
                throw AppUpdateError.invalidRelease
            }
            return expected
        }
        return try Self(version: version, archiveURL: asset(name), checksumURL: asset(name + ".sha256"))
    }

    public func verify(archive: Data, checksum: Data) throws {
        guard let text = String(data: checksum, encoding: .utf8) else { throw AppUpdateError.invalidChecksum }
        let fields = text.split(whereSeparator: \.isWhitespace)
        let digest = SHA256.hash(data: archive).map { String(format: "%02x", $0) }.joined()
        guard fields.count == 2, fields[0].lowercased() == digest,
              String(fields[1]) == archiveName else { throw AppUpdateError.invalidChecksum }
    }
}

public struct AppUpdateClient {
    private let session: URLSession
    public init(session: URLSession = .shared) { self.session = session }

    public func latest(after version: AppVersion) async throws -> AppRelease? {
        let url = URL(string: "https://api.github.com/repos/jasharicoco/CodexUsageBar/releases/latest")!
        let (data, response) = try await session.data(for: request(url))
        if (response as? HTTPURLResponse)?.statusCode == 404 { return nil }
        try validate(response)
        return try AppRelease.newerRelease(from: data, currentVersion: version)
    }

    public func download(_ release: AppRelease, to directory: URL) async throws -> URL {
        let (temporaryURL, response) = try await session.download(for: request(release.archiveURL))
        defer { try? FileManager.default.removeItem(at: temporaryURL) }
        try validate(response)
        let (checksum, checksumResponse) = try await session.data(for: request(release.checksumURL))
        try validate(checksumResponse)
        try Task.checkCancellation()
        try release.verify(archive: Data(contentsOf: temporaryURL, options: .mappedIfSafe), checksum: checksum)
        let archive = directory.appendingPathComponent(release.archiveName)
        try FileManager.default.moveItem(at: temporaryURL, to: archive)
        return archive
    }

    private func request(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 60)
        request.setValue("CodexUsageBar", forHTTPHeaderField: "User-Agent")
        if url.host == "api.github.com" {
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        }
        return request
    }

    private func validate(_ response: URLResponse) throws {
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200, response.url?.scheme == "https" else { throw AppUpdateError.http(status) }
    }
}
