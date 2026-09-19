import UIKit
import WebKit

final class LampaViewController: UIViewController, WKNavigationDelegate, WKUIDelegate {
    private var webView: WKWebView!
    private let storageBridge = LampaStorageBridge()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.067, green: 0.067, blue: 0.067, alpha: 1)
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
        UIApplication.shared.isIdleTimerDisabled = false
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
        configuration.applicationNameForUserAgent = "lampa_client lampatorr_ios"
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

        // Capture uncaught JS errors into the Xcode/device log instead of only showing
        // Lampa's generic "Script error" notification.
        let diagnostics = #"""
        (function () {
            window.addEventListener('error', function (event) {
                try {
                    console.error('[LampaTorr JS]', event.message, event.filename, event.lineno + ':' + event.colno, event.error && event.error.stack ? event.error.stack : '');
                } catch (_) {}
            });
            window.addEventListener('unhandledrejection', function (event) {
                try {
                    console.error('[LampaTorr Promise]', event.reason && event.reason.stack ? event.reason.stack : String(event.reason));
                } catch (_) {}
            });
        })();
        """#
        configuration.userContentController.addUserScript(
            WKUserScript(source: diagnostics, injectionTime: .atDocumentStart, forMainFrameOnly: true)
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
        scrollView.alwaysBounceVertical = false
        scrollView.alwaysBounceHorizontal = false

        webView.isOpaque = false
        webView.backgroundColor = UIColor(red: 0.067, green: 0.067, blue: 0.067, alpha: 1)
        scrollView.backgroundColor = webView.backgroundColor

        view.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func loadLampa() {
        var request = URLRequest(url: LampaHTTPServer.baseURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData
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

        if let scheme = url.scheme?.lowercased(),
           !["http", "https", "about", "blob", "data"].contains(scheme) {
            if UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
                return
            }
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

    private func showFatalError(_ message: String) {
        let alert = UIAlertController(title: "LampaTorr", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    override var prefersHomeIndicatorAutoHidden: Bool { true }
    override var prefersStatusBarHidden: Bool { true }
}
