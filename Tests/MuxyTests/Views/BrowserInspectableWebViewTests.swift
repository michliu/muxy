import AppKit
import Testing
import WebKit

@testable import Muxy

@Suite("BrowserInspectableWebView")
@MainActor
struct BrowserInspectableWebViewTests {
    @Test("enables WebKit developer extras on browser configuration")
    func enablesDeveloperExtras() {
        let configuration = WKWebViewConfiguration()

        BrowserInspectableWebView.enableInspection(in: configuration)

        #expect(BrowserInspectableWebView.inspectionEnabled(in: configuration))
    }

    @Test("adds an enabled inspect element item to the web view menu")
    func addsInspectElementItem() {
        let webView = BrowserInspectableWebView(frame: .zero)
        webView.isInspectable = true
        let menu = NSMenu(title: "Browser")
        menu.addItem(withTitle: "Reload", action: nil, keyEquivalent: "")

        webView.addInspectElementItem(to: menu)
        webView.addInspectElementItem(to: menu)

        let inspectItems = menu.items.filter { $0.title == "Inspect Element" }
        #expect(inspectItems.count == 1)
        #expect(inspectItems.first?.isEnabled == true)
    }

    @Test("does not add inspect element when web view is not inspectable")
    func omitsInspectElementWhenNotInspectable() {
        let webView = BrowserInspectableWebView(frame: .zero)
        let menu = NSMenu(title: "Browser")

        webView.addInspectElementItem(to: menu)

        #expect(menu.items.isEmpty)
    }
}
