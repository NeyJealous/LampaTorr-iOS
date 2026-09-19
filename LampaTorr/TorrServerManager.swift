import Foundation
import TorrServerKit

final class TorrServerManager {
    static let shared = TorrServerManager()

    private let queue = DispatchQueue(label: "dev.lampatorr.torrserver", qos: .userInitiated)

    private init() {}

    var isRunning: Bool {
        TorrserverkitIsRunning()
    }

    func start(completion: @escaping (Result<Void, Error>) -> Void) {
        queue.async { [weak self] in
            guard let self else { return }

            do {
                if TorrserverkitIsRunning() {
                    guard self.waitForServer() else {
                        throw TorrServerError.healthCheckTimedOut
                    }
                    DispatchQueue.main.async { completion(.success(())) }
                    return
                }

                let dataDirectory = try self.makeDataDirectory()
                let errorMessage = TorrserverkitStartServer(8090, dataDirectory.path)

                if !errorMessage.isEmpty {
                    throw TorrServerError.startFailed(errorMessage)
                }

                guard self.waitForServer() else {
                    throw TorrServerError.healthCheckTimedOut
                }

                DispatchQueue.main.async { completion(.success(())) }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    func ensureRunning() {
        start { result in
            if case .failure(let error) = result {
                print("[LampaTorr] TorrServer foreground recovery failed: \(error.localizedDescription)")
            }
        }
    }

    func stop() {
        guard TorrserverkitIsRunning() else { return }
        let errorMessage = TorrserverkitStopServer()
        if !errorMessage.isEmpty {
            print("[LampaTorr] TorrServer stop error: \(errorMessage)")
        }
    }

    private func makeDataDirectory() throws -> URL {
        let fm = FileManager.default
        let base = try fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = base.appendingPathComponent("TorrServer", isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func waitForServer() -> Bool {
        guard let url = URL(string: "http://127.0.0.1:8090/echo") else { return false }

        for _ in 0..<40 {
            let semaphore = DispatchSemaphore(value: 0)
            var healthy = false
            var request = URLRequest(url: url)
            request.timeoutInterval = 0.5
            request.cachePolicy = .reloadIgnoringLocalCacheData

            URLSession.shared.dataTask(with: request) { data, response, _ in
                if let http = response as? HTTPURLResponse,
                   (200..<300).contains(http.statusCode),
                   let data,
                   !data.isEmpty {
                    healthy = true
                }
                semaphore.signal()
            }.resume()

            _ = semaphore.wait(timeout: .now() + 0.8)
            if healthy { return true }
            Thread.sleep(forTimeInterval: 0.15)
        }

        return false
    }
}

enum TorrServerError: LocalizedError {
    case startFailed(String)
    case healthCheckTimedOut

    var errorDescription: String? {
        switch self {
        case .startFailed(let message):
            return "TorrServer не запустился: \(message)"
        case .healthCheckTimedOut:
            return "TorrServer запущен, но локальный API 127.0.0.1:8090 не ответил вовремя."
        }
    }
}
