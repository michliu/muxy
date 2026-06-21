import AppKit
import WebKit

struct ExtensionBrowserState {
    var url: String?
    var title: String?
    var canGoBack: Bool
    var canGoForward: Bool
    var isLoading: Bool
    var progress: Double

    static let empty = ExtensionBrowserState(
        url: nil,
        title: nil,
        canGoBack: false,
        canGoForward: false,
        isLoading: false,
        progress: 0
    )
}

@MainActor
final class ExtensionBrowserOverlay: NSObject {
    let viewID: String
    let extensionID: String
    let wrapper: NSView
    private let webView: WKWebView
    private var observations: [NSKeyValueObservation] = []

    var onStateChange: ((ExtensionBrowserState) -> Void)?
    private(set) var state = ExtensionBrowserState.empty

    init(viewID: String, extensionID: String, profileID: UUID?) {
        self.viewID = viewID
        self.extensionID = extensionID

        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.websiteDataStore = BrowserDataStoreCache.shared.store(for: profileID)

        webView = WKWebView(frame: .zero, configuration: config)
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsMagnification = true

        wrapper = NSView(frame: .zero)
        wrapper.wantsLayer = true
        wrapper.layer?.masksToBounds = true

        super.init()

        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.autoresizingMask = [.width, .height]
        wrapper.addSubview(webView)
        observeWebView()
    }

    func setFrame(_ frame: NSRect, visible: Bool) {
        wrapper.isHidden = !visible || frame.width <= 0 || frame.height <= 0
        wrapper.frame = frame
        webView.frame = wrapper.bounds
    }

    func setVisible(_ visible: Bool) {
        wrapper.isHidden = !visible
    }

    func load(_ urlString: String) {
        guard let url = ExtensionBrowserURL.resolve(from: urlString) else { return }
        webView.load(URLRequest(url: url))
    }

    func back() {
        webView.goBack()
    }

    func forward() {
        webView.goForward()
    }

    func reload() {
        webView.reload()
    }

    func stop() {
        webView.stopLoading()
    }

    func find(_ text: String) {
        let configuration = WKFindConfiguration()
        Task { _ = try? await webView.find(text, configuration: configuration) }
    }

    func executeJS(_ source: String) async throws -> Any? {
        try await webView.evaluateJavaScript(source)
    }

    func teardown() {
        observations.forEach { $0.invalidate() }
        observations.removeAll()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        webView.stopLoading()
        webView.removeFromSuperview()
        wrapper.removeFromSuperview()
    }

    private func observeWebView() {
        observations = [
            webView.observe(\.estimatedProgress, options: [.new]) { [weak self] view, _ in
                MainActor.assumeIsolated { self?.update { $0.progress = view.estimatedProgress } }
            },
            webView.observe(\.isLoading, options: [.new]) { [weak self] view, _ in
                MainActor.assumeIsolated { self?.update { $0.isLoading = view.isLoading } }
            },
            webView.observe(\.canGoBack, options: [.new]) { [weak self] view, _ in
                MainActor.assumeIsolated { self?.update { $0.canGoBack = view.canGoBack } }
            },
            webView.observe(\.canGoForward, options: [.new]) { [weak self] view, _ in
                MainActor.assumeIsolated { self?.update { $0.canGoForward = view.canGoForward } }
            },
            webView.observe(\.title, options: [.new]) { [weak self] view, _ in
                MainActor.assumeIsolated { self?.update { $0.title = view.title } }
            },
            webView.observe(\.url, options: [.new]) { [weak self] view, _ in
                MainActor.assumeIsolated { self?.update { $0.url = view.url?.absoluteString } }
            },
        ]
    }

    private func update(_ mutate: (inout ExtensionBrowserState) -> Void) {
        mutate(&state)
        onStateChange?(state)
    }
}

extension ExtensionBrowserOverlay: WKNavigationDelegate, WKUIDelegate {
    func webView(
        _: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }
        decisionHandler(ExtensionBrowserURL.isAllowed(url) ? .allow : .cancel)
    }

    func webView(
        _: WKWebView,
        createWebViewWith _: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures _: WKWindowFeatures
    ) -> WKWebView? {
        if let url = navigationAction.request.url, ExtensionBrowserURL.isAllowed(url) {
            webView.load(URLRequest(url: url))
        }
        return nil
    }
}
