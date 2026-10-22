import Foundation
import Testing
@testable import battery

@Suite("About model")
struct AboutModelTests {
    @Test func readsVersionAndBuildFromTheBundle() {
        let info = AboutModel.info(bundleInfo: [
            "CFBundleShortVersionString": "1.2.0",
            "CFBundleVersion": "42",
        ])
        #expect(info.appName == "PeriBattery")
        #expect(info.tagline == "Battery levels for your Logitech keyboard and mouse, in the menu bar.")
        #expect(info.versionText == "1.2.0 (42)")
    }

    @Test func aMissingBuildLeavesTheBareVersion() {
        #expect(AboutModel.versionText(shortVersion: "1.0.0", build: nil) == "1.0.0")
        #expect(AboutModel.versionText(shortVersion: "1.0.0", build: "") == "1.0.0")
    }

    @Test func aMissingVersionReadsUnknown() {
        #expect(AboutModel.info(bundleInfo: [:]).versionText == "Unknown")
        #expect(AboutModel.versionText(shortVersion: nil, build: "7") == "Unknown")
        #expect(AboutModel.versionText(shortVersion: "", build: "7") == "Unknown")
    }

    @Test func listsTheRowsInOrder() {
        let rows = AboutModel.info(bundleInfo: [:]).rows
        #expect(rows.map(\.label) == ["Devices", "Protocol", "License", "Source"])
        #expect(rows[0].value == "Logitech keyboards and mice on Unifying, Bolt and Lightspeed receivers, or by USB cable")
        #expect(rows[1].value == "Logitech HID++ 2.0")
        #expect(rows[2].value == "MIT")
        #expect(rows[0].url == nil)
        #expect(rows[1].url == nil)
    }

    @Test func licenseLinksToTheLicenseFile() {
        let license = AboutModel.info(bundleInfo: [:]).rows[2]
        #expect(license.url == URL(string: "https://github.com/juancasanueva/SWIFTUI_battery/blob/main/LICENSE.md"))
    }

    @Test func sourceLinksToTheRepository() throws {
        let source = try #require(AboutModel.info(bundleInfo: [:]).rows.last)
        #expect(source.url == URL(string: "https://github.com/juancasanueva/SWIFTUI_battery"))
        #expect(source.value == "github.com/juancasanueva/SWIFTUI_battery")
    }

    @Test func everyLinkIsHTTPSWithAHost() {
        let links = AboutModel.info(bundleInfo: [:]).rows.compactMap(\.url)
        #expect(links.count == 2)
        for link in links {
            #expect(link.scheme == "https")
            #expect(link.host() != nil)
        }
    }

    @Test func footerDisclaimsAffiliation() {
        #expect(AboutModel.info(bundleInfo: [:]).footer == "Personal project. Not affiliated with Logitech.")
    }
}
