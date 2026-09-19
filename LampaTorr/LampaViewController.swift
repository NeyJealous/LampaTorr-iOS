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

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        restorePortraitOrientation()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        restorePortraitOrientation()
        UIApplication.shared.isIdleTimerDisabled = true
        TorrServerManager.shared.ensureRunning()
    }

    private func restorePortraitOrientation() {
        setNeedsUpdateOfSupportedInterfaceOrientations()

        guard let scene = view.window?.windowScene else { return }

        scene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait)) { error in
            print("[LampaTorr] Failed to restore portrait Lampa orientation: \(error.localizedDescription)")
        }
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

        configuration.userContentController.addScriptMessageHandler(
            torrProxy,
            contentWorld: .page,
            name: TorrProxyBridge.messageName
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

        if scheme == "vlc" || scheme == "vlc-x-callback" {
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
        guard let streamURL = extractEmbeddedVLCStreamURL(from: customURL) else {
            let raw = customURL.absoluteString
            let preview = String(raw.prefix(260))
            showError("Не удалось разобрать ссылку видео для встроенного VLC.\n\nСхема: \(customURL.scheme ?? "—")\nURL: \(preview)")
            return
        }

        let player = VLCPlayerViewController(streamURL: streamURL)
        player.modalPresentationStyle = .fullScreen
        present(player, animated: true)
    }

    private func extractEmbeddedVLCStreamURL(from customURL: URL) -> URL? {
        let raw = customURL.absoluteString
        let scheme = customURL.scheme?.lowercased() ?? ""

        if scheme == "vlc" {
            // Lampa emits: vlc://http://127.0.0.1:8090/stream/...
            // Foundation parses the nested "http" as the HOST of the outer vlc URL.
            // Rebuild the inner URL from parsed components before trying raw fallbacks.
            if let nestedScheme = customURL.host?.lowercased(),
               nestedScheme == "http" || nestedScheme == "https" {

                var rebuilt = nestedScheme + ":"
                let encodedPath = customURL.path(percentEncoded: true)

                if encodedPath.hasPrefix("//") {
                    rebuilt += encodedPath
                } else if encodedPath.hasPrefix("/") {
                    rebuilt += "/" + encodedPath
                } else {
                    rebuilt += "//" + encodedPath
                }

                if let components = URLComponents(url: customURL, resolvingAgainstBaseURL: false) {
                    if let query = components.percentEncodedQuery, !query.isEmpty {
                        rebuilt += "?" + query
                    }
                    if let fragment = components.percentEncodedFragment, !fragment.isEmpty {
                        rebuilt += "#" + fragment
                    }
                }

                if let url = makeEmbeddedMediaURL(rebuilt) {
                    return url
                }
            }

            if raw.lowercased().hasPrefix("vlc://") {
                let candidate = String(raw.dropFirst("vlc://".count))
                if let url = makeEmbeddedMediaURL(candidate) {
                    return url
                }
            }
        }

        if scheme == "vlc-x-callback",
           let components = URLComponents(url: customURL, resolvingAgainstBaseURL: false) {

            // Prefer percentEncodedQuery so an encoded stream URL keeps its own
            // ?, &, Unicode filename and other delimiters intact.
            if let query = components.percentEncodedQuery {
                for item in query.split(separator: "&", omittingEmptySubsequences: false) {
                    let pair = item.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                    guard pair.count == 2,
                          pair[0].lowercased() == "url" else { continue }

                    let encodedValue = String(pair[1])
                    if let url = makeEmbeddedMediaURL(encodedValue) {
                        return url
                    }
                }
            }

            if let value = components.queryItems?.first(where: { $0.name.lowercased() == "url" })?.value,
               let url = makeEmbeddedMediaURL(value) {
                return url
            }
        }

        return nil
    }

    private func makeEmbeddedMediaURL(_ source: String) -> URL? {
        guard !source.isEmpty else { return nil }

        var candidates: [String] = [source]
        var current = source

        // Some player schemes encode the whole media URL once or twice.
        for _ in 0..<3 {
            guard let decoded = current.removingPercentEncoding,
                  decoded != current else { break }
            candidates.append(decoded)
            current = decoded
        }

        for original in candidates {
            var value = original.trimmingCharacters(in: .whitespacesAndNewlines)

            if value.lowercased().hasPrefix("http//") {
                value = "http://" + String(value.dropFirst("http//".count))
            } else if value.lowercased().hasPrefix("https//") {
                value = "https://" + String(value.dropFirst("https//".count))
            }

            if !value.lowercased().hasPrefix("http://") &&
               !value.lowercased().hasPrefix("https://") {

                if let range = value.range(of: "http://", options: .caseInsensitive) {
                    value = String(value[range.lowerBound...])
                } else if let range = value.range(of: "https://", options: .caseInsensitive) {
                    value = String(value[range.lowerBound...])
                }
            }

            if let url = URL(string: value, encodingInvalidCharacters: true),
               let mediaScheme = url.scheme?.lowercased(),
               mediaScheme == "http" || mediaScheme == "https" {
                return url
            }
        }

        return nil
    }

    private func showError(_ message: String) {
        let alert = UIAlertController(title: "LampaTorr", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    override var shouldAutorotate: Bool { true }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .portrait }
    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation { .portrait }

    override var prefersHomeIndicatorAutoHidden: Bool { true }
    override var prefersStatusBarHidden: Bool { true }

    private static let bootstrapScript = #"""
    (function () {
        try {
            localStorage.setItem('torrserver_url', 'http://127.0.0.1:8090');
            localStorage.setItem('torrserver_use_link', 'one');

            // Use embedded VLCKit for both ordinary online video and torrents.
            localStorage.setItem('player', 'vlc');
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

        var target = /^http:\/\/127\.0\.0\.1:8090(?=\/|$)/i;
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

        // fetch() proxy
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
                    status: Number(result.status || 200),
                    statusText: result.statusText || '',
                    headers: result.headers || {}
                });
            });
        };

        // XMLHttpRequest proxy. This is installed at documentStart, before
        // Lampa/jQuery can make the first TorrServer connection test.
        var NativeXHR = window.XMLHttpRequest;

        function ProxyXHR() {
            this._native = new NativeXHR();
            this._proxy = false;
            this._method = 'GET';
            this._url = '';
            this._headers = {};
            this._responseHeaders = {};
            this._readyState = 0;
            this._status = 0;
            this._statusText = '';
            this._responseText = '';
            this._response = '';
            this._responseURL = '';
            this._aborted = false;
            this._listeners = {};
            this._timeout = 0;
            this._responseType = '';
            this._withCredentials = false;

            var self = this;
            ['loadstart','progress','abort','error','load','timeout','loadend','readystatechange'].forEach(function (type) {
                self['_on' + type] = null;
                self._native.addEventListener(type, function (event) {
                    if (!self._proxy) self._emit(type, event);
                });
            });
        }

        ProxyXHR.prototype._emit = function (type, event) {
            event = event || new Event(type);

            var handler = this['_on' + type];
            if (typeof handler === 'function') {
                try { handler.call(this, event); } catch (_) {}
            }

            var listeners = this._listeners[type] || [];
            listeners.slice().forEach(function (listener) {
                try { listener.call(this, event); } catch (_) {}
            }, this);
        };

        ProxyXHR.prototype.addEventListener = function (type, listener) {
            if (!this._listeners[type]) this._listeners[type] = [];
            this._listeners[type].push(listener);
        };

        ProxyXHR.prototype.removeEventListener = function (type, listener) {
            var list = this._listeners[type] || [];
            var index = list.indexOf(listener);
            if (index >= 0) list.splice(index, 1);
        };

        ProxyXHR.prototype.dispatchEvent = function (event) {
            this._emit(event.type, event);
            return true;
        };

        ProxyXHR.prototype.open = function (method, url, async, user, password) {
            var textURL = String(url);
            this._proxy = target.test(textURL);
            this._method = String(method || 'GET').toUpperCase();
            this._url = textURL;
            this._aborted = false;

            if (!this._proxy) {
                return this._native.open(method, url, async === undefined ? true : async, user, password);
            }

            if (async === false) {
                throw new Error('Synchronous TorrServer XHR is not supported by LampaTorr');
            }

            this._readyState = 1;
            this._emit('readystatechange');
        };

        ProxyXHR.prototype.setRequestHeader = function (name, value) {
            if (!this._proxy) return this._native.setRequestHeader(name, value);
            this._headers[String(name)] = String(value);
        };

        ProxyXHR.prototype.overrideMimeType = function (value) {
            if (!this._proxy && this._native.overrideMimeType) {
                return this._native.overrideMimeType(value);
            }
        };

        ProxyXHR.prototype.getResponseHeader = function (name) {
            if (!this._proxy) return this._native.getResponseHeader(name);

            var wanted = String(name).toLowerCase();
            var keys = Object.keys(this._responseHeaders || {});
            for (var i = 0; i < keys.length; i++) {
                if (keys[i].toLowerCase() === wanted) return this._responseHeaders[keys[i]];
            }
            return null;
        };

        ProxyXHR.prototype.getAllResponseHeaders = function () {
            if (!this._proxy) return this._native.getAllResponseHeaders();

            var headers = this._responseHeaders || {};
            return Object.keys(headers).map(function (key) {
                return key + ': ' + headers[key];
            }).join('\r\n');
        };

        ProxyXHR.prototype.abort = function () {
            if (!this._proxy) return this._native.abort();

            this._aborted = true;
            this._readyState = 0;
            this._emit('abort');
            this._emit('loadend');
        };

        ProxyXHR.prototype.send = function (body) {
            if (!this._proxy) return this._native.send(body);

            var self = this;
            var requestBody = null;

            if (body != null) {
                if (typeof body === 'string') requestBody = body;
                else if (body instanceof URLSearchParams) requestBody = body.toString();
                else {
                    try { requestBody = JSON.stringify(body); }
                    catch (_) { requestBody = String(body); }
                }
            }

            this._emit('loadstart');

            bridge({
                url: this._url,
                method: this._method,
                headers: this._headers,
                body: requestBody,
                timeout: Number(this._timeout || 30000)
            }).then(function (result) {
                if (self._aborted) return;

                self._responseHeaders = result.headers || {};
                self._status = Number(result.status || 0);
                self._statusText = result.statusText || '';
                self._responseText = result.body || '';
                self._responseURL = self._url;

                self._readyState = 2;
                self._emit('readystatechange');
                self._readyState = 3;
                self._emit('readystatechange');

                if (self._responseType === 'json') {
                    try { self._response = self._responseText ? JSON.parse(self._responseText) : null; }
                    catch (_) { self._response = null; }
                } else {
                    self._response = self._responseText;
                }

                self._readyState = 4;
                self._emit('readystatechange');

                if (self._status >= 200 && self._status < 400) {
                    self._emit('load');
                } else {
                    self._emit('error');
                }
                self._emit('loadend');
            }).catch(function (error) {
                if (self._aborted) return;

                self._status = 0;
                self._statusText = String(error && error.message ? error.message : error);
                self._readyState = 4;
                self._emit('readystatechange');
                self._emit('error');
                self._emit('loadend');
            });
        };

        Object.defineProperties(ProxyXHR.prototype, {
            readyState: { get: function () { return this._proxy ? this._readyState : this._native.readyState; } },
            status: { get: function () { return this._proxy ? this._status : this._native.status; } },
            statusText: { get: function () { return this._proxy ? this._statusText : this._native.statusText; } },
            responseText: { get: function () { return this._proxy ? this._responseText : this._native.responseText; } },
            response: { get: function () { return this._proxy ? this._response : this._native.response; } },
            responseURL: { get: function () { return this._proxy ? this._responseURL : this._native.responseURL; } },
            responseXML: { get: function () { return this._proxy ? null : this._native.responseXML; } },
            timeout: {
                get: function () { return this._proxy ? this._timeout : this._native.timeout; },
                set: function (value) { this._timeout = Number(value || 0); if (!this._proxy) this._native.timeout = value; }
            },
            responseType: {
                get: function () { return this._proxy ? this._responseType : this._native.responseType; },
                set: function (value) { this._responseType = value || ''; if (!this._proxy) this._native.responseType = value; }
            },
            withCredentials: {
                get: function () { return this._proxy ? this._withCredentials : this._native.withCredentials; },
                set: function (value) { this._withCredentials = !!value; if (!this._proxy) this._native.withCredentials = value; }
            },
            upload: { get: function () { return this._native.upload; } },

            onloadstart: { get: function () { return this._onloadstart; }, set: function (v) { this._onloadstart = v; } },
            onprogress: { get: function () { return this._onprogress; }, set: function (v) { this._onprogress = v; } },
            onabort: { get: function () { return this._onabort; }, set: function (v) { this._onabort = v; } },
            onerror: { get: function () { return this._onerror; }, set: function (v) { this._onerror = v; } },
            onload: { get: function () { return this._onload; }, set: function (v) { this._onload = v; } },
            ontimeout: { get: function () { return this._ontimeout; }, set: function (v) { this._ontimeout = v; } },
            onloadend: { get: function () { return this._onloadend; }, set: function (v) { this._onloadend = v; } },
            onreadystatechange: { get: function () { return this._onreadystatechange; }, set: function (v) { this._onreadystatechange = v; } }
        });

        ProxyXHR.UNSENT = 0;
        ProxyXHR.OPENED = 1;
        ProxyXHR.HEADERS_RECEIVED = 2;
        ProxyXHR.LOADING = 3;
        ProxyXHR.DONE = 4;
        ProxyXHR.prototype.UNSENT = 0;
        ProxyXHR.prototype.OPENED = 1;
        ProxyXHR.prototype.HEADERS_RECEIVED = 2;
        ProxyXHR.prototype.LOADING = 3;
        ProxyXHR.prototype.DONE = 4;

        window.XMLHttpRequest = ProxyXHR;
    })();
    """#
}
