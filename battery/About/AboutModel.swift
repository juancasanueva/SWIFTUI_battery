import Foundation

/// One row of the About card: a label and a value, optionally a link.
nonisolated struct AboutRow: Sendable, Equatable, Identifiable {
    let label: String
    /// Visible text; for a link, the address without its scheme.
    let value: String
    var url: URL?

    var id: String { label }
}

/// Everything the About window shows, as plain values.
nonisolated struct AboutInfo: Sendable, Equatable {
    let appName: String
    let tagline: String
    /// Marketing version and build, for example `"1.0.0 (7)"`.
    let versionText: String
    let rows: [AboutRow]
    let footer: String
}

/// The About window's content. Identity, credits and links describe the project, so they are
/// constants; only the version comes from the bundle, through the Info.plist dictionary the caller
/// passes.
nonisolated enum AboutModel {
    static let appName = "PeriBattery"
    static let tagline = "Battery levels for your Logitech keyboard and mouse, in the menu bar."
    static let footer = "Personal project. Not affiliated with Logitech."

    static let unknownVersion = "Unknown"

    private static let rows = [
        AboutRow(label: "Devices",
                 value: "Logitech keyboards and mice on Unifying, Bolt and Lightspeed receivers, or by USB cable"),
        AboutRow(label: "Protocol", value: "Logitech HID++ 2.0"),
        AboutRow(label: "License", value: "MIT",
                 url: URL(string: "https://github.com/juancasanueva/SWIFTUI_battery/blob/main/LICENSE.md")),
        AboutRow(label: "Source", value: "github.com/juancasanueva/SWIFTUI_battery",
                 url: URL(string: "https://github.com/juancasanueva/SWIFTUI_battery")),
    ]

    /// Builds the content from an Info.plist dictionary, normally `Bundle.main.infoDictionary`.
    static func info(bundleInfo: [String: Any]) -> AboutInfo {
        AboutInfo(
            appName: appName,
            tagline: tagline,
            versionText: versionText(shortVersion: bundleInfo["CFBundleShortVersionString"] as? String,
                                     build: bundleInfo["CFBundleVersion"] as? String),
            rows: rows,
            footer: footer
        )
    }

    /// `"<version> (<build>)"`, the wording Finder's Get Info uses. A missing build leaves the bare
    /// version; a missing version reads "Unknown".
    static func versionText(shortVersion: String?, build: String?) -> String {
        guard let shortVersion, !shortVersion.isEmpty else { return unknownVersion }
        guard let build, !build.isEmpty else { return shortVersion }
        return "\(shortVersion) (\(build))"
    }
}
