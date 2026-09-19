import UIKit
import VLCKit

final class VLCPlayerViewController: UIViewController {
    private let streamURL: URL
    private let mediaPlayer = VLCMediaPlayer()

    private let videoView = UIView()
    private let closeButton = UIButton(type: .system)
    private let playPauseButton = UIButton(type: .system)

    init(streamURL: URL) {
        self.streamURL = streamURL
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configureUI()
        configurePlayer()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        UIApplication.shared.isIdleTimerDisabled = true
        mediaPlayer.play()
    }

    override func viewWillDisappear(_ animated: Bool) {
        mediaPlayer.stop()
        super.viewWillDisappear(animated)
    }

    private func configureUI() {
        videoView.translatesAutoresizingMaskIntoConstraints = false
        videoView.backgroundColor = .black

        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.setTitle("✕", for: .normal)
        closeButton.setTitleColor(.white, for: .normal)
        closeButton.titleLabel?.font = .systemFont(ofSize: 28, weight: .semibold)
        closeButton.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        closeButton.layer.cornerRadius = 22
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)

        playPauseButton.translatesAutoresizingMaskIntoConstraints = false
        playPauseButton.setTitle("⏯", for: .normal)
        playPauseButton.setTitleColor(.white, for: .normal)
        playPauseButton.titleLabel?.font = .systemFont(ofSize: 32)
        playPauseButton.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        playPauseButton.layer.cornerRadius = 28
        playPauseButton.addTarget(self, action: #selector(playPauseTapped), for: .touchUpInside)

        view.addSubview(videoView)
        view.addSubview(closeButton)
        view.addSubview(playPauseButton)

        NSLayoutConstraint.activate([
            videoView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            videoView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            videoView.topAnchor.constraint(equalTo: view.topAnchor),
            videoView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            closeButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            closeButton.widthAnchor.constraint(equalToConstant: 44),
            closeButton.heightAnchor.constraint(equalToConstant: 44),

            playPauseButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            playPauseButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -18),
            playPauseButton.widthAnchor.constraint(equalToConstant: 56),
            playPauseButton.heightAnchor.constraint(equalToConstant: 56)
        ])
    }

    private func configurePlayer() {
        mediaPlayer.drawable = videoView

        guard let media = VLCMedia(url: streamURL) else {
            showError("VLCKit не смог создать медиапоток.")
            return
        }

        media.addOption(":network-caching=2500")
        media.addOption(":clock-jitter=0")
        mediaPlayer.media = media
    }

    @objc private func closeTapped() {
        mediaPlayer.stop()
        dismiss(animated: true)
    }

    @objc private func playPauseTapped() {
        if mediaPlayer.isPlaying {
            mediaPlayer.pause()
        } else {
            mediaPlayer.play()
        }
    }

    private func showError(_ message: String) {
        let alert = UIAlertController(title: "VLC", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Закрыть", style: .default) { [weak self] _ in
            self?.dismiss(animated: true)
        })
        present(alert, animated: true)
    }

    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
}
