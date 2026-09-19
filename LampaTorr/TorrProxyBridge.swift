import Foundation
import WebKit

/// Native bridge for TorrServer API calls originating from the HTTPS Lampa UI.
/// Only http://127.0.0.1:8090 is allowed.
final class TorrProxyBridge: NSObject, WKScriptMessageHandlerWithReply {
    static let messageName = "torrProxy"

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage,
        replyHandler: @escaping (Any?, String?) -> Void
    ) {
        guard message.frameInfo.isMainFrame else {
            replyHandler(nil, "TorrServer proxy is only available to the main frame.")
            return
        }

        let origin = message.frameInfo.securityOrigin
        guard origin.protocol == "https", origin.host == "cf.lampa.mx" else {
            replyHandler(nil, "TorrServer proxy rejected this origin.")
            return
        }

        guard let payload = message.body as? [String: Any],
              let rawURL = payload["url"] as? String,
              let url = URL(string: rawURL),
              url.scheme?.lowercased() == "http",
              url.host == "127.0.0.1",
              url.port == 8090 else {
            replyHandler(nil, "Invalid TorrServer proxy URL.")
            return
        }

        let method = (payload["method"] as? String ?? "GET").uppercased()
        guard ["GET", "POST", "PUT", "DELETE", "HEAD", "OPTIONS"].contains(method) else {
            replyHandler(nil, "Unsupported HTTP method.")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = max(1, min((payload["timeout"] as? Double ?? 30_000) / 1000, 120))
        request.cachePolicy = .reloadIgnoringLocalCacheData

        if let headers = payload["headers"] as? [String: Any] {
            for (name, value) in headers {
                request.setValue(String(describing: value), forHTTPHeaderField: name)
            }
        }

        if let body = payload["body"] as? String, method != "GET", method != "HEAD" {
            request.httpBody = Data(body.utf8)
        }

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                replyHandler(nil, error.localizedDescription)
                return
            }

            guard let http = response as? HTTPURLResponse else {
                replyHandler(nil, "TorrServer returned an invalid response.")
                return
            }

            var headers: [String: String] = [:]
            for (key, value) in http.allHeaderFields {
                headers[String(describing: key)] = String(describing: value)
            }

            let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""

            replyHandler([
                "status": http.statusCode,
                "statusText": HTTPURLResponse.localizedString(forStatusCode: http.statusCode),
                "headers": headers,
                "body": body
            ], nil)
        }.resume()
    }
}
