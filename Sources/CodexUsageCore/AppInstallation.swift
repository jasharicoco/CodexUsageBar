import Darwin
import Foundation
import Security

public enum AppInstallation {
    public static let bundleIdentifier = "io.github.jasharicoco.CodexUsageBar"

    /// Run only on a background thread; output is drained before waiting to avoid pipe deadlocks.
    @discardableResult
    public static func run(_ executable: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw AppUpdateError.commandFailed(executable) }
        return String(decoding: output, as: UTF8.self)
    }

    public static func validateArchiveListing(_ listing: String) throws {
        let paths = listing.split(separator: "\n")
        guard !paths.isEmpty else { throw AppUpdateError.invalidArchive }
        for path in paths {
            let components = path.split(separator: "/", omittingEmptySubsequences: false)
            guard !path.hasPrefix("/"), !components.contains(".."),
                  components.first == "CodexUsageBar.app" || components.first == "__MACOSX" else {
                throw AppUpdateError.invalidArchive
            }
        }
    }

    public static func validateBundle(_ app: URL, version: AppVersion, installedApp: URL) throws {
        let manager = FileManager.default
        // Reject links before asking codesign or Bundle to traverse the extracted app.
        guard let enumerator = manager.enumerator(at: app, includingPropertiesForKeys: [.isSymbolicLinkKey]) else {
            throw AppUpdateError.invalidBundle
        }
        for case let item as URL in enumerator {
            if try item.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true {
                let resolved = item.resolvingSymlinksInPath().path
                guard resolved.hasPrefix(app.resolvingSymlinksInPath().path + "/") else {
                    throw AppUpdateError.invalidBundle
                }
            }
        }
        guard !(try app.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink ?? true),
              let bundle = Bundle(url: app), bundle.bundleIdentifier == bundleIdentifier,
              bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String == version.string,
              bundle.object(forInfoDictionaryKey: "CFBundleExecutable") as? String == "CodexUsageBar",
              let minimum = bundle.object(forInfoDictionaryKey: "LSMinimumSystemVersion") as? String,
              minimum.compare(ProcessInfo.processInfo.operatingSystemVersionStringForUpdate, options: .numeric) != .orderedDescending else {
            throw AppUpdateError.invalidBundle
        }
        try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path])
        let architectures = try run("/usr/bin/lipo", ["-archs", app.appendingPathComponent("Contents/MacOS/CodexUsageBar").path])
        #if arch(arm64)
        let architecture = "arm64"
        #else
        let architecture = "x86_64"
        #endif
        guard architectures.split(whereSeparator: \.isWhitespace).contains(Substring(architecture)) else {
            throw AppUpdateError.invalidBundle
        }
        // Once Developer ID signing is enabled, never allow a different team or an ad-hoc downgrade.
        if let team = try signingTeam(installedApp), try signingTeam(app) != team {
            throw AppUpdateError.invalidBundle
        }
    }

    public static func stage(archive: URL, version: AppVersion, installedApp: URL, helper: URL, in transaction: URL) throws {
        let manager = FileManager.default
        let listing = try run("/usr/bin/zipinfo", ["-1", archive.path])
        try validateArchiveListing(listing)
        // These release bundles have no symlinks. Reject links before extraction to prevent traversal.
        let details = try run("/usr/bin/zipinfo", ["-l", archive.path])
        guard !details.split(separator: "\n").contains(where: { $0.hasPrefix("l") }) else {
            throw AppUpdateError.invalidArchive
        }
        let extracted = transaction.appendingPathComponent("extracted", isDirectory: true)
        try run("/usr/bin/ditto", ["-x", "-k", archive.path, extracted.path])
        let app = extracted.appendingPathComponent("CodexUsageBar.app")
        try validateBundle(app, version: version, installedApp: installedApp)
        try manager.moveItem(at: app, to: transaction.appendingPathComponent("CodexUsageBar.app"))
        try manager.copyItem(at: helper, to: transaction.appendingPathComponent("UpdateInstaller"))
        try manager.removeItem(at: extracted)
    }

    private static func signingTeam(_ app: URL) throws -> String? {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code else {
            throw AppUpdateError.invalidBundle
        }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess else {
            throw AppUpdateError.invalidBundle
        }
        return (information as? [String: Any])?[kSecCodeInfoTeamIdentifier as String] as? String
    }

    /// Both bundles must be on the same volume. A failed swap leaves the installed app intact.
    public static func exchange(_ installed: URL, _ staged: URL) throws {
        let result = installed.path.withCString { installedPath in
            staged.path.withCString { stagedPath in
                renamex_np(installedPath, stagedPath, UInt32(RENAME_SWAP))
            }
        }
        guard result == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    }

    /// Keep the old app until Launch Services accepts the new one. Restore it on launch failure.
    public static func activate(installed: URL, staged: URL, launch: (URL) throws -> Void) throws {
        try exchange(installed, staged)
        do {
            try launch(installed)
        } catch {
            try exchange(installed, staged)
            throw error
        }
    }
}

private extension ProcessInfo {
    var operatingSystemVersionStringForUpdate: String {
        let version = operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }
}
