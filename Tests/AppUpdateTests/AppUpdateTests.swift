import Foundation
import CryptoKit
import CodexUsageCore

final class AppUpdateChecks {
    private let current = AppVersion("1.0.0")!

    private func fixture(tag: String = "v1.1.0", draft: Bool = false, prerelease: Bool = false,
                         includeChecksum: Bool = true, host: String = "github.com") -> Data {
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        let archive = "CodexUsageBar-v\(version)-macOS-universal.zip"
        let names = includeChecksum ? [archive, archive + ".sha256"] : [archive]
        let assets = names.map { name in
            ["name": name, "browser_download_url": "https://\(host)/jasharicoco/CodexUsageBar/releases/download/\(tag)/\(name)"]
        }
        return try! JSONSerialization.data(withJSONObject: [
            "tag_name": tag, "draft": draft, "prerelease": prerelease, "assets": assets
        ])
    }

    func testVersionsCompareNumericallyAndRejectUnstableOrMalformedVersions() {
        expectGreaterThan(AppVersion("1.10.0")!, AppVersion("1.9.9")!)
        expectGreaterThan(AppVersion("2.0.0")!, AppVersion("1.99.99")!)
        expectEqual(AppVersion("v1.2.3"), AppVersion("1.2.3"))
        for value in ["", "1", "1.2", "01.2.3", "1.2.3.4", "1.2.-3", "1.2.3-beta", "1.2.3+build", "v../../app", "1.2.999999999999999999999999"] {
            expectNil(AppVersion(value), value)
        }
    }

    func testOnlyNewStableReleasesAreOffered() throws {
        expectEqual(try AppRelease.newerRelease(from: fixture(), currentVersion: current)?.version, AppVersion("1.1.0"))
        expectNil(try AppRelease.newerRelease(from: fixture(tag: "v1.0.0"), currentVersion: current))
        expectNil(try AppRelease.newerRelease(from: fixture(tag: "v0.9.0"), currentVersion: current))
        expectNil(try AppRelease.newerRelease(from: fixture(draft: true), currentVersion: current))
        expectNil(try AppRelease.newerRelease(from: fixture(prerelease: true), currentVersion: current))
        expectThrows(try AppRelease.newerRelease(from: fixture(tag: "v1.1.0-beta"), currentVersion: current))
    }

    func testMissingAssetsAndUntrustedAssetURLsAreRejected() {
        expectThrows(try AppRelease.newerRelease(from: fixture(includeChecksum: false), currentVersion: current))
        for host in ["example.com", "github.com.example.com", "github.com@evil.example"] {
            expectThrows(try AppRelease.newerRelease(from: fixture(host: host), currentVersion: current))
        }
        let insecure = Data(String(decoding: fixture(), as: UTF8.self).replacingOccurrences(of: "https:", with: "http:").utf8)
        expectThrows(try AppRelease.newerRelease(from: insecure, currentVersion: current))
    }

    func testChecksumMustMatchBothContentsAndFilename() throws {
        let release = try requireValue(AppRelease.newerRelease(from: fixture(), currentVersion: current))
        let archive = Data("release archive".utf8)
        let digest = SHA256.hash(data: archive).map { String(format: "%02x", $0) }.joined()
        let checksum = Data("\(digest)  \(release.archiveName)\n".utf8)
        expectNoThrow(try release.verify(archive: archive, checksum: checksum))
        expectThrows(try release.verify(archive: Data("corrupted".utf8), checksum: checksum))
        expectThrows(try release.verify(archive: archive, checksum: Data("\(digest)  wrong.zip".utf8)))
        expectThrows(try release.verify(archive: archive, checksum: Data(digest.utf8)))
    }

    func testArchiveTraversalAndUnexpectedRootsAreRejected() {
        expectNoThrow(try AppInstallation.validateArchiveListing("CodexUsageBar.app/Contents/Info.plist\n__MACOSX/CodexUsageBar.app/._Contents\n"))
        for listing in ["", "/Applications/Other.app", "../Other.app", "CodexUsageBar.app/../../Other.app", "Other.app/Contents/Info.plist"] {
            expectThrows(try AppInstallation.validateArchiveListing(listing), listing)
        }
    }

    func testAtomicInstallationAndRollbackIncludingPathsWithSpaces() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Update test \(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let installed = root.appendingPathComponent("Installed App.app")
        let staged = root.appendingPathComponent("New App.app")
        for (url, version) in [(installed, "old"), (staged, "new")] {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
            try Data(version.utf8).write(to: url.appendingPathComponent("version"))
        }
        func version(_ url: URL) throws -> String { try String(contentsOf: url.appendingPathComponent("version")) }
        expectThrows(try AppInstallation.activate(installed: installed, staged: staged) { app in
            expectEqual(try version(app), "new")
            throw AppUpdateError.invalidBundle
        })
        expectEqual(try version(installed), "old", "Launch failure must restore the original")
        expectEqual(try version(staged), "new", "Failed update must remain recoverable")

        try AppInstallation.activate(installed: installed, staged: staged) { app in
            expectEqual(app, installed)
            expectEqual(try version(app), "new")
        }
        expectEqual(try version(installed), "new")
        expectEqual(try version(staged), "old", "Keep backup until successful launch")
        expectThrows(try AppInstallation.exchange(installed, root.appendingPathComponent("missing.app")))
        expectEqual(try version(installed), "new", "Failed swap must leave the installed app intact")
    }

    func testHTTPResponsesAndRequestPrivacy() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [UpdateURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let client = AppUpdateClient(session: session)
        UpdateURLProtocol.handler = { request in
            expectEqual(request.url?.host, "api.github.com")
            expectEqual(request.url?.path, "/repos/jasharicoco/CodexUsageBar/releases/latest")
            expectNil(request.value(forHTTPHeaderField: "Authorization"))
            expectNil(request.httpBody)
            return (200, self.fixture())
        }
        let release = try await client.latest(after: current)
        expectEqual(release?.version.string, "1.1.0")
        UpdateURLProtocol.handler = { _ in (404, Data()) }
        let absent = try await client.latest(after: current)
        expectNil(absent)
        for status in [403, 429, 500] {
            UpdateURLProtocol.handler = { _ in (status, Data()) }
            do {
                _ = try await client.latest(after: current)
                fatalError("HTTP \(status) should fail")
            } catch {
                expectEqual(error as? AppUpdateError, .http(status))
            }
        }
        UpdateURLProtocol.handler = { _ in (200, Data("not json".utf8)) }
        do {
            _ = try await client.latest(after: current)
            fatalError("Malformed metadata should fail")
        } catch { }
    }

    func testPackagedApp(_ app: URL) throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent("Update package test \(UUID().uuidString)")
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: root) }
        let bundle = try requireValue(Bundle(url: app))
        let version = try requireValue(bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
        let release = try requireValue(AppRelease.newerRelease(from: fixture(tag: "v\(version)"), currentVersion: AppVersion("0.0.0")!))
        let archive = root.appendingPathComponent(release.archiveName)
        try AppInstallation.run("/usr/bin/ditto", ["-c", "-k", "--sequesterRsrc", "--keepParent", app.path, archive.path])
        let contents = try Data(contentsOf: archive)
        let digest = SHA256.hash(data: contents).map { String(format: "%02x", $0) }.joined()
        try release.verify(archive: contents, checksum: Data("\(digest)  \(release.archiveName)\n".utf8))
        let stage = root.appendingPathComponent("transaction")
        try manager.createDirectory(at: stage, withIntermediateDirectories: false)
        try AppInstallation.stage(archive: archive, version: release.version, installedApp: app,
                                  helper: app.appendingPathComponent("Contents/Helpers/UpdateInstaller"), in: stage)
        let staged = stage.appendingPathComponent("CodexUsageBar.app")
        expectEqual(manager.isExecutableFile(atPath: stage.appendingPathComponent("UpdateInstaller").path), true)
        expectThrows(try AppInstallation.validateBundle(staged, version: AppVersion("99.0.0")!, installedApp: app))
        let executable = staged.appendingPathComponent("Contents/MacOS/CodexUsageBar")
        try Data("corrupt binary".utf8).write(to: executable)
        expectThrows(try AppInstallation.validateBundle(staged, version: release.version, installedApp: app))
        // Stage validation must never modify the actual installed app.
        try AppInstallation.validateBundle(app, version: release.version, installedApp: app)
        print("Packaged app extraction, identity, signature, helper, and corruption checks passed.")
    }
}

private final class UpdateURLProtocol: URLProtocol {
    static var handler: ((URLRequest) -> (Int, Data))!
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let (status, data) = Self.handler(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private func expectEqual<T: Equatable>(_ actual: @autoclosure () throws -> T, _ expected: T, _ message: String = "Values differ") {
    do { guard try actual() == expected else { fatalError(message) } } catch { fatalError("Unexpected error: \(error)") }
}
private func expectGreaterThan<T: Comparable>(_ actual: T, _ expected: T) {
    guard actual > expected else { fatalError("Incorrect version order") }
}
private func expectNil<T>(_ value: @autoclosure () throws -> T?, _ message: String = "Expected nil") {
    do { guard try value() == nil else { fatalError(message) } } catch { fatalError("Unexpected error: \(error)") }
}
private func expectNoThrow<T>(_ expression: @autoclosure () throws -> T) {
    do { _ = try expression() } catch { fatalError("Unexpected error: \(error)") }
}
private func expectThrows<T>(_ expression: @autoclosure () throws -> T, _ message: String = "Expected an error") {
    do { _ = try expression() } catch { return }
    fatalError(message)
}
private func requireValue<T>(_ value: T?) throws -> T {
    guard let value else { throw AppUpdateError.invalidRelease }
    return value
}

@main
struct UpdateChecks {
    static func main() async throws {
        let checks = AppUpdateChecks()
        checks.testVersionsCompareNumericallyAndRejectUnstableOrMalformedVersions()
        try checks.testOnlyNewStableReleasesAreOffered()
        checks.testMissingAssetsAndUntrustedAssetURLsAreRejected()
        try checks.testChecksumMustMatchBothContentsAndFilename()
        checks.testArchiveTraversalAndUnexpectedRootsAreRejected()
        try checks.testAtomicInstallationAndRollbackIncludingPathsWithSpaces()
        try await checks.testHTTPResponsesAndRequestPrivacy()
        if let index = CommandLine.arguments.firstIndex(of: "--app"), CommandLine.arguments.count > index + 1 {
            try checks.testPackagedApp(URL(fileURLWithPath: CommandLine.arguments[index + 1]))
        }
        print("All app update checks passed.")
    }
}
