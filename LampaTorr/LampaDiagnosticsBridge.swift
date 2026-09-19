import UIKit
import WebKit

final class LampaDiagnosticsBridge: NSObject, WKScriptMessageHandler {
    static let messageName = "lampaDiagnostics"

    private weak var presenter: UIViewController?

    init(presenter: UIViewController) {
        self.presenter = presenter
        super.init()
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard message.name == Self.messageName,
              let payload = message.body as? [String: Any] else {
            return
        }

        let report = Self.formatReport(payload)

        DispatchQueue.main.async { [weak self] in
            guard let presenter = self?.presenter else { return }

            let alert = UIAlertController(
                title: "Lampa · диагностика CUB",
                message: report,
                preferredStyle: .alert
            )

            alert.addAction(UIAlertAction(title: "Копировать", style: .default) { _ in
                UIPasteboard.general.string = report
            })

            alert.addAction(UIAlertAction(title: "Закрыть", style: .cancel))
            presenter.present(alert, animated: true)
        }
    }

    private static func formatReport(_ payload: [String: Any]) -> String {
        var lines: [String] = []

        lines.append("online: \((payload["online"] as? Bool) == true ? "yes" : "no")")

        let cubDomain = string(payload["cubDomain"])
        let cubAlive = string(payload["cubAlive"])
        if !cubDomain.isEmpty { lines.append("cub_domain: \(cubDomain)") }
        if !cubAlive.isEmpty { lines.append("cub_alive: \(cubAlive)") }

        let page = string(payload["page"])
        if !page.isEmpty { lines.append("page: \(page)") }

        lines.append("")

        let errors = payload["errors"] as? [[String: Any]] ?? []
        if errors.isEmpty {
            lines.append("Ошибок request_error пока не поймано.")
        } else {
            lines.append("Последние request_error:")
            for (index, error) in errors.prefix(10).enumerated() {
                lines.append(formatEntry(error, index: index + 1))
            }
        }

        let successes = payload["successes"] as? [[String: Any]] ?? []
        if !successes.isEmpty {
            lines.append("")
            lines.append("Последние успешные запросы:")
            for (index, success) in successes.prefix(5).enumerated() {
                lines.append(formatEntry(success, index: index + 1))
            }
        }

        return lines.joined(separator: "\n")
    }

    private static func formatEntry(_ item: [String: Any], index: Int) -> String {
        let method = string(item["method"])
        let url = string(item["url"])
        let status = int(item["status"])
        let statusText = string(item["statusText"])
        let readyState = int(item["readyState"])
        let exception = string(item["exception"])

        var line = "\(index). \(method.isEmpty ? "GET" : method) \(url)"
        line += "\n   status=\(status), readyState=\(readyState)"

        if !statusText.isEmpty {
            line += ", \(statusText)"
        }

        if !exception.isEmpty {
            line += "\n   exception=\(exception)"
        }

        return line
    }

    private static func string(_ value: Any?) -> String {
        if let value = value as? String { return value }
        if let value { return String(describing: value) }
        return ""
    }

    private static func int(_ value: Any?) -> Int {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? String, let int = Int(value) { return int }
        return 0
    }
}
