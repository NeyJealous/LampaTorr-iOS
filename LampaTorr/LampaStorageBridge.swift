import Foundation
import WebKit

/// Mirrors Lampa localStorage into the native app sandbox so login/settings
/// survive WebView recreation. The actual UI is loaded from https://cf.lampa.mx.
final class LampaStorageBridge: NSObject, WKScriptMessageHandler {
    static let messageName = "lampaStorage"

    private let defaults: UserDefaults
    private let defaultsKey = "LampaTorr.localStorage.v1"
    private let queue = DispatchQueue(label: "dev.lampatorr.storage")

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        super.init()
    }

    func bootstrapScript() -> String {
        let stored = snapshot()
        let json: String

        if JSONSerialization.isValidJSONObject(stored),
           let data = try? JSONSerialization.data(withJSONObject: stored, options: []),
           let encoded = String(data: data, encoding: .utf8) {
            json = encoded
        } else {
            json = "{}"
        }

        return """
        (function () {
            if (window.__lampatorrStorageBridgeInstalled) return;
            window.__lampatorrStorageBridgeInstalled = true;

            const nativeSnapshot = (json);
            const post = (message) => {
                try {
                    window.webkit.messageHandlers.(Self.messageName).postMessage(message);
                } catch (e) {}
            };

            try {
                Object.keys(nativeSnapshot).forEach((key) => {
                    if (localStorage.getItem(key) === null && typeof nativeSnapshot[key] === 'string') {
                        localStorage.setItem(key, nativeSnapshot[key]);
                    }
                });

                // Native services provided by this iOS host.
                localStorage.setItem('torrserver_url', 'http://127.0.0.1:8090');
                localStorage.setItem('torrserver_use_link', 'one');

                // Route torrent playback through Lampa's normal iOS VLC path.
                // The host intercepts vlc:// and opens embedded VLCKit instead.
                localStorage.setItem('player_torrent', 'vlc');

                const nativeSetItem = Storage.prototype.setItem;
                const nativeRemoveItem = Storage.prototype.removeItem;
                const nativeClear = Storage.prototype.clear;

                Storage.prototype.setItem = function (key, value) {
                    nativeSetItem.call(this, key, value);
                    if (this === window.localStorage) {
                        post({ op: 'set', key: String(key), value: String(value) });
                    }
                };

                Storage.prototype.removeItem = function (key) {
                    nativeRemoveItem.call(this, key);
                    if (this === window.localStorage) {
                        post({ op: 'remove', key: String(key) });
                    }
                };

                Storage.prototype.clear = function () {
                    nativeClear.call(this);
                    if (this === window.localStorage) {
                        post({ op: 'clear' });
                    }
                };

                const current = {};
                for (let i = 0; i < localStorage.length; i++) {
                    const key = localStorage.key(i);
                    if (key !== null) current[key] = localStorage.getItem(key) ?? '';
                }
                post({ op: 'snapshot', data: current });
            } catch (e) {
                console.error('[LampaTorr] storage bootstrap failed', e);
            }

            window.LampaTorr = Object.assign(window.LampaTorr || {}, {
                embeddedTorrServer: true,
                embeddedVLC: true,
                torrServerURL: 'http://127.0.0.1:8090',
                sourceURL: 'https://cf.lampa.mx'
            });
        })();
        """
    }

    func forceSnapshotScript() -> String {
        """
        (function () {
            try {
                const current = {};
                for (let i = 0; i < localStorage.length; i++) {
                    const key = localStorage.key(i);
                    if (key !== null) current[key] = localStorage.getItem(key) ?? '';
                }
                window.webkit.messageHandlers.(Self.messageName).postMessage({op:'snapshot', data:current});
            } catch (e) {}
        })();
        """
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard message.name == Self.messageName,
              let body = message.body as? [String: Any],
              let operation = body["op"] as? String else {
            return
        }

        queue.async { [weak self] in
            guard let self else { return }
            var values = self.snapshot()

            switch operation {
            case "set":
                if let key = body["key"] as? String,
                   let value = body["value"] as? String {
                    values[key] = value
                }
            case "remove":
                if let key = body["key"] as? String {
                    values.removeValue(forKey: key)
                }
            case "clear":
                values.removeAll()
            case "snapshot":
                if let data = body["data"] as? [String: Any] {
                    values = data.reduce(into: [:]) { result, pair in
                        if let string = pair.value as? String {
                            result[pair.key] = string
                        }
                    }
                }
            default:
                return
            }

            self.defaults.set(values, forKey: self.defaultsKey)
        }
    }

    private func snapshot() -> [String: String] {
        (defaults.dictionary(forKey: defaultsKey) ?? [:]).reduce(into: [:]) { result, pair in
            if let value = pair.value as? String {
                result[pair.key] = value
            }
        }
    }
}
