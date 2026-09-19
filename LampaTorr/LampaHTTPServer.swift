import Foundation
import Network

/// Tiny loopback HTTP server for the bundled Lampa web application.
/// Serving Lampa over http://127.0.0.1 instead of file:// gives WebKit a normal
/// origin, which is important for Web Workers, CUB requests and account startup.
final class LampaHTTPServer {
    static let shared = LampaHTTPServer()

    static let port: UInt16 = 8091
    static let baseURL = URL(string: "http://127.0.0.1:\(port)")!

    private let queue = DispatchQueue(label: "dev.lampatorr.webserver", qos: .userInitiated)
    private var listener: NWListener?
    private(set) var isRunning = false

    private init() {}

    func start(completion: @escaping (Result<Void, Error>) -> Void) {
        queue.async { [weak self] in
            guard let self else { return }

            if self.isRunning {
                DispatchQueue.main.async { completion(.success(())) }
                return
            }

            guard let root = Bundle.main.resourceURL?.appendingPathComponent("Lampa", isDirectory: true),
                  FileManager.default.fileExists(atPath: root.appendingPathComponent("index.html").path) else {
                DispatchQueue.main.async { completion(.failure(ServerError.missingWebRoot)) }
                return
            }

            do {
                guard let port = NWEndpoint.Port(rawValue: Self.port) else {
                    throw ServerError.invalidPort
                }

                let parameters = NWParameters.tcp
                parameters.allowLocalEndpointReuse = true

                let listener = try NWListener(using: parameters, on: port)
                self.listener = listener

                listener.stateUpdateHandler = { [weak self] state in
                    guard let self else { return }

                    switch state {
                    case .ready:
                        self.isRunning = true
                        DispatchQueue.main.async { completion(.success(())) }

                    case .failed(let error):
                        self.isRunning = false
                        self.listener?.cancel()
                        self.listener = nil
                        DispatchQueue.main.async { completion(.failure(error)) }

                    case .cancelled:
                        self.isRunning = false

                    default:
                        break
                    }
                }

                listener.newConnectionHandler = { [weak self] connection in
                    self?.handle(connection: connection, root: root)
                }

                listener.start(queue: self.queue)
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    func stop() {
        queue.async { [weak self] in
            self?.listener?.cancel()
            self?.listener = nil
            self?.isRunning = false
        }
    }

    private func handle(connection: NWConnection, root: URL) {
        connection.start(queue: queue)
        receiveRequest(on: connection, root: root, buffer: Data())
    }

    private func receiveRequest(on connection: NWConnection, root: URL, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }

            var request = buffer
            if let data {
                request.append(data)
            }

            if request.range(of: Data("\r\n\r\n".utf8)) != nil {
                self.respond(to: request, on: connection, root: root)
                return
            }

            if request.count > 128 * 1024 || isComplete || error != nil {
                self.sendStatus(400, text: "Bad Request", on: connection)
                return
            }

            self.receiveRequest(on: connection, root: root, buffer: request)
        }
    }

    private func respond(to request: Data, on connection: NWConnection, root: URL) {
        guard let text = String(data: request, encoding: .utf8),
              let firstLine = text.components(separatedBy: "\r\n").first else {
            sendStatus(400, text: "Bad Request", on: connection)
            return
        }

        let parts = firstLine.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count >= 2 else {
            sendStatus(400, text: "Bad Request", on: connection)
            return
        }

        let method = String(parts[0]).uppercased()
        guard method == "GET" || method == "HEAD" else {
            sendStatus(405, text: "Method Not Allowed", on: connection)
            return
        }

        var rawPath = String(parts[1])
        if let queryIndex = rawPath.firstIndex(of: "?") {
            rawPath = String(rawPath[..<queryIndex])
        }

        rawPath = rawPath.removingPercentEncoding ?? rawPath
        if rawPath == "/" || rawPath.isEmpty {
            rawPath = "/index.html"
        }

        let components = rawPath
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)

        guard !components.contains("..") else {
            sendStatus(403, text: "Forbidden", on: connection)
            return
        }

        var fileURL = root
        for component in components {
            fileURL.appendPathComponent(component)
        }

        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDirectory),
           isDirectory.boolValue {
            fileURL.appendPathComponent("index.html")
        }

        guard let fileData = try? Data(contentsOf: fileURL) else {
            sendStatus(404, text: "Not Found", on: connection)
            return
        }

        let headers = [
            "HTTP/1.1 200 OK",
            "Content-Length: \(fileData.count)",
            "Content-Type: \(mimeType(for: fileURL))",
            "Cache-Control: no-cache",
            "Access-Control-Allow-Origin: *",
            "Connection: close",
            "",
            ""
        ].joined(separator: "\r\n")

        var response = Data(headers.utf8)
        if method != "HEAD" {
            response.append(fileData)
        }

        connection.send(content: response, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func sendStatus(_ code: Int, text: String, on connection: NWConnection) {
        let body = Data(text.utf8)
        let headers = [
            "HTTP/1.1 \(code) \(text)",
            "Content-Length: \(body.count)",
            "Content-Type: text/plain; charset=utf-8",
            "Connection: close",
            "",
            ""
        ].joined(separator: "\r\n")

        var response = Data(headers.utf8)
        response.append(body)

        connection.send(content: response, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func mimeType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "html", "htm": return "text/html; charset=utf-8"
        case "js", "mjs": return "application/javascript; charset=utf-8"
        case "css": return "text/css; charset=utf-8"
        case "json": return "application/json; charset=utf-8"
        case "svg": return "image/svg+xml"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "ico": return "image/x-icon"
        case "woff": return "font/woff"
        case "woff2": return "font/woff2"
        case "ttf": return "font/ttf"
        case "mp4": return "video/mp4"
        case "webm": return "video/webm"
        default: return "application/octet-stream"
        }
    }

    enum ServerError: LocalizedError {
        case missingWebRoot
        case invalidPort

        var errorDescription: String? {
            switch self {
            case .missingWebRoot:
                return "В приложении отсутствуют web-файлы Lampa."
            case .invalidPort:
                return "Некорректный порт локального web-сервера Lampa."
            }
        }
    }
}
