import UIKit
import WebKit

final class LampaViewController: UIViewController, WKNavigationDelegate, WKUIDelegate {
    private var webView: WKWebView!
    private let storageBridge = LampaStorageBridge()
    private let lampaURL = URL(string: "https://cf.lampa.mx")!

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configureWebView()
        loadLampa()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        UIApplication.shared.isIdleTimerDisabled = true
        TorrServerManager.shared.ensureRunning()
    }

    override func viewWillDisappear(_ animated: Bool) {
        webView?.evaluateJavaScript(storageBridge.forceSnapshotScript())
        super.viewWillDisappear(animated)
    }

    deinit {
        webView?.configuration.userContentController.removeScriptMessageHandler(
            forName: LampaStorageBridge.messageName
        )
    }

    private func configureWebView() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.applicationNameForUserAgent = "lampatorr_ios"
        configuration.allowsInlineMediaPlayback = true
        configuration.allowsPictureInPictureMediaPlayback = true
        configuration.allowsAirPlayForMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true

        configuration.userContentController.add(
            storageBridge,
            name: LampaStorageBridge.messageName
        )
        configuration.userContentController.addUserScript(
            WKUserScript(
                source: storageBridge.bootstrapScript(),
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
        )

        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsLinkPreview = false
        webView.allowsBackForwardNavigationGestures = false

        let scrollView = webView.scrollView
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.bounces = false

        webView.isOpaque = false
        webView.backgroundColor = .black
        scrollView.backgroundColor = .black

        view.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func loadLampa() {
        var request = URLRequest(url: lampaURL)
        request.cachePolicy = .useProtocolCachePolicy
        webView.load(request)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        webView.evaluateJavaScript(storageBridge.forceSnapshotScript())
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }

        let scheme = url.scheme?.lowercased() ?? ""

        if scheme == "vlc" {
            decisionHandler(.cancel)
            openEmbeddedVLC(from: url)
            return
        }

        if !["http", "https", "about", "blob", "data"].contains(scheme) {
            if UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url)
            }
            decisionHandler(.cancel)
            return
        }

        decisionHandler(.allow)
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
            webView.load(URLRequest(url: url))
        }
        return nil
    }

    private func openEmbeddedVLC(from customURL: URL) {
        let raw = customURL.absoluteString
        guard raw.lowercased().hasPrefix("vlc://") else { return }

        let streamText = String(raw.dropFirst("vlc://".count))
        let decoded = streamText.removingPercentEncoding ?? streamText

        guard let streamURL = URL(string: decoded),
              ["http", "https"].contains(streamURL.scheme?.lowercased() ?? "") else {
            showError("Не удалось разобрать ссылку потока для встроенного VLC.")
            return
        }

        let player = VLCPlayerViewController(streamURL: streamURL)
        player.modalPresentationStyle = .fullScreen
        present(player, animated: true)
    }

    private func showError(_ message: String) {
        let alert = UIAlertController(title: "LampaTorr", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    override var prefersHomeIndicatorAutoHidden: Bool { true }
    override var prefersStatusBarHidden: Bool { true }
}
