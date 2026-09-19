import UIKit
import WebKit

final class LampaViewController: UIViewController, WKNavigationDelegate, WKUIDelegate {
    private var webView: WKWebView!
    private let torrProxy = TorrProxyBridge()
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

        configuration.userContentController.addScriptMessageHandlerWithReply(
            torrProxy,
            named: TorrProxyBridge.messageName,
            to: .page
        )

        configuration.userContentController.addUserScript(
            WKUserScript(
                source: Self.bootstrapScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
        )

        configuration.userContentController.addUserScript(
            WKUserScript(
                source: Self.torrProxyScript,
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
              streamURL.scheme?.lowercased() == "http",
              streamURL.host == "127.0.0.1",
              streamURL.port == 8090 else {
            showError("Не удалось разобрать локальную ссылку TorrServer для VLC.")
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

    private static let bootstrapScript = #"""
    (function () {
        try {
            localStorage.setItem('torrserver_url', 'http://127.0.0.1:8090');
            localStorage.setItem('torrserver_use_link', 'one');
            localStorage.setItem('player_torrent', 'vlc');

            window.LampaTorr = {
                embeddedTorrServer: true,
                embeddedVLC: true,
                nativeTorrProxy: true,
                torrServerURL: 'http://127.0.0.1:8090',
                sourceURL: 'https://cf.lampa.mx'
            };
        } catch (error) {
            console.error('[LampaTorr] bootstrap failed', error);
        }
    })();
    """#

    private static let torrProxyScript = #"""
    (function () {
        if (window.__lampatorrTorrProxyInstalled) return;
        window.__lampatorrTorrProxyInstalled = true;

        var target = /^http://127.0.0.1:8090(?=/|$)/i;
        var bridge = function (payload) {
            return window.webkit.messageHandlers.torrProxy.postMessage(payload);
        };

        function normalizeHeaders(input) {
            var result = {};
            if (!input) return result;

            try {
                var headers = new Headers(input);
                headers.forEach(function (value, key) {
                    result[key] = value;
                });
            } catch (_) {
                if (typeof input === 'object') {
                    Object.keys(input).forEach(function (key) {
                        result[key] = String(input[key]);
                    });
                }
            }

            return result;
        }

        var nativeFetch = window.fetch.bind(window);
        window.fetch = function (input, init) {
            var url = typeof input === 'string' ? input : (input && input.url ? input.url : '');

            if (!target.test(String(url))) {
                return nativeFetch(input, init);
            }

            init = init || {};
            var method = String(init.method || (input && input.method) || 'GET').toUpperCase();
            var headers = normalizeHeaders(init.headers || (input && input.headers));
            var body = init.body == null ? null : String(init.body);

            return bridge({
                url: String(url),
                method: method,
                headers: headers,
                body: body,
                timeout: 30000
            }).then(function (result) {
                return new Response(result.body || '', {
                    status: result.status || 200,
                    statusText: result.statusText || '',
                    headers: result.headers || {}
                });
            });
        };

        function installJQueryProxy() {
            var jq = window.jQuery || window.$;

            if (!jq || typeof jq.ajax !== 'function') {
                setTimeout(installJQueryProxy, 25);
                return;
            }

            if (jq.ajax.__lampatorrWrapped) return;

            var nativeAjax = jq.ajax.bind(jq);

            var wrappedAjax = function (options) {
                var originalArguments = arguments;
                var opts;

                if (typeof options === 'string') {
                    opts = Object.assign({}, arguments[1] || {}, { url: options });
                } else {
                    opts = Object.assign({}, options || {});
                }

                var url = String(opts.url || '');
                if (!target.test(url)) {
                    return nativeAjax.apply(jq, originalArguments);
                }

                var headers = normalizeHeaders(opts.headers);
                var aborted = false;

                var fakeXHR = {
                    readyState: 1,
                    status: 0,
                    statusText: '',
                    responseText: '',
                    response: '',
                    responseJSON: undefined,
                    setRequestHeader: function (name, value) {
                        headers[String(name)] = String(value);
                    },
                    getResponseHeader: function (name) {
                        var wanted = String(name).toLowerCase();
                        var keys = Object.keys(this.__headers || {});
                        for (var i = 0; i < keys.length; i++) {
                            if (keys[i].toLowerCase() === wanted) return this.__headers[keys[i]];
                        }
                        return null;
                    },
                    getAllResponseHeaders: function () {
                        var h = this.__headers || {};
                        return Object.keys(h).map(function (key) {
                            return key + ': ' + h[key];
                        }).join('\r\n');
                    },
                    abort: function () {
                        aborted = true;
                    }
                };

                if (typeof opts.beforeSend === 'function') {
                    try {
                        if (opts.beforeSend(fakeXHR, opts) === false) {
                            fakeXHR.abort();
                            return fakeXHR;
                        }
                    } catch (_) {}
                }

                var method = String(opts.type || opts.method || (opts.data != null ? 'POST' : 'GET')).toUpperCase();
                var body = opts.data == null
                    ? null
                    : (typeof opts.data === 'string' ? opts.data : JSON.stringify(opts.data));

                bridge({
                    url: url,
                    method: method,
                    headers: headers,
                    body: body,
                    timeout: Number(opts.timeout || 30000)
                }).then(function (result) {
                    if (aborted) return;

                    fakeXHR.readyState = 4;
                    fakeXHR.status = Number(result.status || 0);
                    fakeXHR.statusText = result.statusText || '';
                    fakeXHR.responseText = result.body || '';
                    fakeXHR.response = fakeXHR.responseText;
                    fakeXHR.__headers = result.headers || {};

                    var payload = fakeXHR.responseText;
                    var dataType = String(opts.dataType || 'json').toLowerCase();

                    if (dataType === 'json') {
                        try {
                            payload = payload ? JSON.parse(payload) : null;
                            fakeXHR.responseJSON = payload;
                        } catch (parseError) {
                            if (typeof opts.error === 'function') opts.error(fakeXHR, 'parsererror', parseError);
                            if (typeof opts.complete === 'function') opts.complete(fakeXHR, 'parsererror');
                            return;
                        }
                    }

                    if (fakeXHR.status >= 200 && fakeXHR.status < 300) {
                        if (typeof opts.success === 'function') opts.success(payload, 'success', fakeXHR);
                        if (typeof opts.complete === 'function') opts.complete(fakeXHR, 'success');
                    } else {
                        if (typeof opts.error === 'function') opts.error(fakeXHR, 'error', fakeXHR.statusText);
                        if (typeof opts.complete === 'function') opts.complete(fakeXHR, 'error');
                    }
                }).catch(function (error) {
                    if (aborted) return;

                    fakeXHR.readyState = 4;
                    fakeXHR.status = 0;
                    fakeXHR.statusText = String(error && error.message ? error.message : error);

                    if (typeof opts.error === 'function') opts.error(fakeXHR, 'error', fakeXHR.statusText);
                    if (typeof opts.complete === 'function') opts.complete(fakeXHR, 'error');
                });

                return fakeXHR;
            };

            wrappedAjax.__lampatorrWrapped = true;
            jq.ajax = wrappedAjax;
        }

        installJQueryProxy();
    })();
    """#
}
