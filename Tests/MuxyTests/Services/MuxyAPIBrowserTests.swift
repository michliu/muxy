import Foundation
import Testing

@testable import Muxy

@Suite("MuxyAPI.Browser permissions & URL")
@MainActor
struct MuxyAPIBrowserTests {
    @Test("every browser verb requires browser:embed")
    func browserVerbsRequirePermission() {
        for verb in MuxyAPI.Permissions.browserVerbs {
            #expect(MuxyAPI.Permissions.required(for: verb) == .browserEmbed)
        }
    }

    @Test("browser verbs are part of the known verb set")
    func browserVerbsRegistered() {
        for verb in MuxyAPI.Permissions.browserVerbs {
            #expect(MuxyAPI.Permissions.verbNames.contains(verb))
        }
    }

    @Test("browser:embed is classified as an action permission")
    func permissionKind() {
        #expect(ExtensionPermission.browserEmbed.kind == .action)
    }

    @Test("resolve accepts absolute http and https URLs")
    func resolveAbsolute() {
        #expect(ExtensionBrowserURL.resolve(from: "https://github.com")?.absoluteString == "https://github.com")
        #expect(ExtensionBrowserURL.resolve(from: "http://example.com/x")?.absoluteString == "http://example.com/x")
    }

    @Test("resolve upgrades bare hosts to https")
    func resolveBareHost() {
        #expect(ExtensionBrowserURL.resolve(from: "github.com")?.absoluteString == "https://github.com")
    }

    @Test("resolve rejects non-host text and empty input")
    func resolveRejects() {
        #expect(ExtensionBrowserURL.resolve(from: "not a url") == nil)
        #expect(ExtensionBrowserURL.resolve(from: "   ") == nil)
    }

    @Test("isAllowed only permits http, https and about")
    func isAllowed() {
        #expect(ExtensionBrowserURL.isAllowed(URL(string: "https://a.com")!))
        #expect(ExtensionBrowserURL.isAllowed(URL(string: "about:blank")!))
        #expect(!ExtensionBrowserURL.isAllowed(URL(string: "file:///etc/passwd")!))
        #expect(!ExtensionBrowserURL.isAllowed(URL(string: "javascript:alert(1)")!))
    }
}
