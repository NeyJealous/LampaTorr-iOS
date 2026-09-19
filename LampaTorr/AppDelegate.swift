import UIKit
import AVFoundation

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        configureAudioSession()

        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = StartupViewController()
        window.makeKeyAndVisible()
        self.window = window
        return true
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        if window?.rootViewController is LampaViewController {
            TorrServerManager.shared.ensureRunning()
        }
    }

    func applicationWillTerminate(_ application: UIApplication) {
        TorrServerManager.shared.stop()
    }

    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .moviePlayback, options: [])
            try session.setActive(true)
        } catch {
            print("[LampaTorr] AVAudioSession error: \(error)")
        }
    }
}
