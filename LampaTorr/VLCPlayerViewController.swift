import UIKit
import VLCKit

final class VLCPlayerViewController: UIViewController, UIGestureRecognizerDelegate {
    private let streamURL: URL
    private let mediaPlayer = VLCMediaPlayer()

    private let videoView = UIView()
    private let touchCatcherView = UIView()
    private let controlsView = UIView()
    private let topBar = UIView()
    private let bottomBar = UIView()

    private let closeButton = UIButton(type: .system)
    private let rotateButton = UIButton(type: .system)
    private let fitButton = UIButton(type: .system)

    private let rewindButton = UIButton(type: .system)
    private let playPauseButton = UIButton(type: .system)
    private let forwardButton = UIButton(type: .system)

    private let progressSlider = UISlider()
    private let currentTimeLabel = UILabel()
    private let durationLabel = UILabel()

    private let audioButton = UIButton(type: .system)
    private let subtitlesButton = UIButton(type: .system)

    private var progressTimer: Timer?
    private var hideControlsWorkItem: DispatchWorkItem?
    private var controlsVisible = true
    private var isSeeking = false
    private var fillMode = false
    private var forceLandscape = false

    init(streamURL: URL) {
        self.streamURL = streamURL
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configureUI()
        configurePlayer()
        installGestures()
        startProgressTimer()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        UIApplication.shared.isIdleTimerDisabled = true
        mediaPlayer.play()
        scheduleControlsHide()
    }

    override func viewWillDisappear(_ animated: Bool) {
        hideControlsWorkItem?.cancel()
        progressTimer?.invalidate()
        mediaPlayer.stop()
        UIApplication.shared.isIdleTimerDisabled = false
        super.viewWillDisappear(animated)
    }

    deinit {
        progressTimer?.invalidate()
    }

    private func configureUI() {
        videoView.translatesAutoresizingMaskIntoConstraints = false
        videoView.backgroundColor = .black
        videoView.isUserInteractionEnabled = true

        touchCatcherView.translatesAutoresizingMaskIntoConstraints = false
        touchCatcherView.backgroundColor = .clear
        touchCatcherView.isUserInteractionEnabled = true

        controlsView.translatesAutoresizingMaskIntoConstraints = false
        controlsView.backgroundColor = .clear

        topBar.translatesAutoresizingMaskIntoConstraints = false
        topBar.backgroundColor = UIColor.black.withAlphaComponent(0.42)

        bottomBar.translatesAutoresizingMaskIntoConstraints = false
        bottomBar.backgroundColor = UIColor.black.withAlphaComponent(0.56)

        configureIconButton(closeButton, symbol: "xmark", pointSize: 24)
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)

        configureIconButton(rotateButton, symbol: "rectangle.landscape.rotate", pointSize: 22)
        rotateButton.addTarget(self, action: #selector(rotateTapped), for: .touchUpInside)

        configureIconButton(fitButton, symbol: "arrow.up.left.and.arrow.down.right", pointSize: 21)
        fitButton.addTarget(self, action: #selector(fitTapped), for: .touchUpInside)

        configureIconButton(rewindButton, symbol: "gobackward.10", pointSize: 36)
        rewindButton.addTarget(self, action: #selector(rewindTapped), for: .touchUpInside)

        configureIconButton(playPauseButton, symbol: "pause.fill", pointSize: 42)
        playPauseButton.addTarget(self, action: #selector(playPauseTapped), for: .touchUpInside)

        configureIconButton(forwardButton, symbol: "goforward.10", pointSize: 36)
        forwardButton.addTarget(self, action: #selector(forwardTapped), for: .touchUpInside)

        progressSlider.translatesAutoresizingMaskIntoConstraints = false
        progressSlider.minimumValue = 0
        progressSlider.maximumValue = 1
        progressSlider.value = 0
        progressSlider.addTarget(self, action: #selector(sliderTouchDown), for: .touchDown)
        progressSlider.addTarget(self, action: #selector(sliderValueChanged), for: .valueChanged)
        progressSlider.addTarget(self, action: #selector(sliderTouchEnded), for: [.touchUpInside, .touchUpOutside, .touchCancel])

        configureTimeLabel(currentTimeLabel)
        configureTimeLabel(durationLabel)
        currentTimeLabel.text = "00:00"
        durationLabel.text = "--:--"
        durationLabel.textAlignment = .right

        configureTextButton(audioButton, title: "Аудио", symbol: "waveform")
        audioButton.addTarget(self, action: #selector(audioTapped), for: .touchUpInside)

        configureTextButton(subtitlesButton, title: "Субтитры", symbol: "captions.bubble")
        subtitlesButton.addTarget(self, action: #selector(subtitlesTapped), for: .touchUpInside)

        view.addSubview(videoView)
        view.addSubview(touchCatcherView)
        view.addSubview(controlsView)
        controlsView.addSubview(topBar)
        controlsView.addSubview(bottomBar)

        topBar.addSubview(closeButton)
        topBar.addSubview(rotateButton)
        topBar.addSubview(fitButton)

        let centerControls = UIStackView(arrangedSubviews: [rewindButton, playPauseButton, forwardButton])
        centerControls.translatesAutoresizingMaskIntoConstraints = false
        centerControls.axis = .horizontal
        centerControls.alignment = .center
        centerControls.spacing = 34
        centerControls.distribution = .equalCentering
        controlsView.addSubview(centerControls)

        let trackStack = UIStackView(arrangedSubviews: [audioButton, subtitlesButton])
        trackStack.translatesAutoresizingMaskIntoConstraints = false
        trackStack.axis = .horizontal
        trackStack.spacing = 12
        trackStack.alignment = .center
        bottomBar.addSubview(trackStack)

        bottomBar.addSubview(progressSlider)
        bottomBar.addSubview(currentTimeLabel)
        bottomBar.addSubview(durationLabel)

        NSLayoutConstraint.activate([
            videoView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            videoView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            videoView.topAnchor.constraint(equalTo: view.topAnchor),
            videoView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            touchCatcherView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            touchCatcherView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            touchCatcherView.topAnchor.constraint(equalTo: view.topAnchor),
            touchCatcherView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            controlsView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            controlsView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            controlsView.topAnchor.constraint(equalTo: view.topAnchor),
            controlsView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            topBar.leadingAnchor.constraint(equalTo: controlsView.leadingAnchor),
            topBar.trailingAnchor.constraint(equalTo: controlsView.trailingAnchor),
            topBar.topAnchor.constraint(equalTo: controlsView.topAnchor),
            topBar.heightAnchor.constraint(equalToConstant: 88),

            closeButton.leadingAnchor.constraint(equalTo: topBar.safeAreaLayoutGuide.leadingAnchor, constant: 12),
            closeButton.bottomAnchor.constraint(equalTo: topBar.bottomAnchor, constant: -10),
            closeButton.widthAnchor.constraint(equalToConstant: 50),
            closeButton.heightAnchor.constraint(equalToConstant: 50),

            rotateButton.trailingAnchor.constraint(equalTo: topBar.safeAreaLayoutGuide.trailingAnchor, constant: -12),
            rotateButton.bottomAnchor.constraint(equalTo: topBar.bottomAnchor, constant: -10),
            rotateButton.widthAnchor.constraint(equalToConstant: 50),
            rotateButton.heightAnchor.constraint(equalToConstant: 50),

            fitButton.trailingAnchor.constraint(equalTo: rotateButton.leadingAnchor, constant: -10),
            fitButton.bottomAnchor.constraint(equalTo: rotateButton.bottomAnchor),
            fitButton.widthAnchor.constraint(equalToConstant: 50),
            fitButton.heightAnchor.constraint(equalToConstant: 50),

            centerControls.centerXAnchor.constraint(equalTo: controlsView.centerXAnchor),
            centerControls.centerYAnchor.constraint(equalTo: controlsView.centerYAnchor),
            rewindButton.widthAnchor.constraint(equalToConstant: 68),
            rewindButton.heightAnchor.constraint(equalToConstant: 68),
            playPauseButton.widthAnchor.constraint(equalToConstant: 82),
            playPauseButton.heightAnchor.constraint(equalToConstant: 82),
            forwardButton.widthAnchor.constraint(equalToConstant: 68),
            forwardButton.heightAnchor.constraint(equalToConstant: 68),

            bottomBar.leadingAnchor.constraint(equalTo: controlsView.leadingAnchor),
            bottomBar.trailingAnchor.constraint(equalTo: controlsView.trailingAnchor),
            bottomBar.bottomAnchor.constraint(equalTo: controlsView.bottomAnchor),
            bottomBar.heightAnchor.constraint(equalToConstant: 154),

            currentTimeLabel.leadingAnchor.constraint(equalTo: bottomBar.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            currentTimeLabel.topAnchor.constraint(equalTo: bottomBar.topAnchor, constant: 16),
            currentTimeLabel.widthAnchor.constraint(equalToConstant: 60),

            durationLabel.trailingAnchor.constraint(equalTo: bottomBar.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            durationLabel.topAnchor.constraint(equalTo: currentTimeLabel.topAnchor),
            durationLabel.widthAnchor.constraint(equalToConstant: 70),

            progressSlider.leadingAnchor.constraint(equalTo: currentTimeLabel.trailingAnchor, constant: 10),
            progressSlider.trailingAnchor.constraint(equalTo: durationLabel.leadingAnchor, constant: -10),
            progressSlider.centerYAnchor.constraint(equalTo: currentTimeLabel.centerYAnchor),

            trackStack.leadingAnchor.constraint(equalTo: bottomBar.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            trackStack.bottomAnchor.constraint(equalTo: bottomBar.safeAreaLayoutGuide.bottomAnchor, constant: -12),

            audioButton.heightAnchor.constraint(equalToConstant: 42),
            subtitlesButton.heightAnchor.constraint(equalToConstant: 42)
        ])
    }

    private func configureIconButton(_ button: UIButton, symbol: String, pointSize: CGFloat) {
        button.translatesAutoresizingMaskIntoConstraints = false
        button.tintColor = .white
        button.backgroundColor = UIColor.black.withAlphaComponent(0.34)
        button.layer.cornerRadius = 16
        button.setImage(
            UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: pointSize, weight: .medium)),
            for: .normal
        )
    }

    private func configureTextButton(_ button: UIButton, title: String, symbol: String) {
        button.translatesAutoresizingMaskIntoConstraints = false
        var configuration = UIButton.Configuration.filled()
        configuration.title = title
        configuration.image = UIImage(systemName: symbol)
        configuration.imagePadding = 7
        configuration.baseForegroundColor = .white
        configuration.baseBackgroundColor = UIColor.white.withAlphaComponent(0.14)
        configuration.cornerStyle = .capsule
        button.configuration = configuration
    }

    private func configureTimeLabel(_ label: UILabel) {
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        label.textColor = .white
    }

    private func configurePlayer() {
        mediaPlayer.drawable = videoView
        mediaPlayer.timeChangeUpdateInterval = 0.5
        mediaPlayer.videoFitMode = .smaller

        guard let media = VLCMedia(url: streamURL) else {
            showError("VLCKit не смог создать медиапоток.")
            return
        }

        media.addOption(":network-caching=2500")
        media.addOption(":clock-jitter=0")
        mediaPlayer.media = media
    }

    private func installGestures() {
        // This layer sits above the VLC drawable and below the controls.
        // Once controlsView is hidden, it becomes the topmost interactive layer
        // and reliably receives the tap even if VLCKit inserts its own render view.
        let showTap = UITapGestureRecognizer(target: self, action: #selector(showControlsTapped))
        showTap.cancelsTouchesInView = false
        touchCatcherView.addGestureRecognizer(showTap)

        // While controls are visible, the overlay itself receives taps on free
        // space. UIControls are excluded by the gesture delegate below.
        let hideTap = UITapGestureRecognizer(target: self, action: #selector(hideControlsTapped))
        hideTap.delegate = self
        hideTap.cancelsTouchesInView = false
        controlsView.addGestureRecognizer(hideTap)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        // Taps on controls must operate the control itself and must not also
        // toggle the whole overlay. Walk up the touched view hierarchy because
        // UIButton/UISlider can contain internal UIKit subviews.
        var touchedView: UIView? = touch.view

        while let current = touchedView {
            if current is UIControl {
                return false
            }

            if current === view {
                break
            }

            touchedView = current.superview
        }

        return true
    }

    private func startProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.refreshPlaybackUI()
        }
    }

    private func refreshPlaybackUI() {
        let playing = mediaPlayer.isPlaying
        let symbol = playing ? "pause.fill" : "play.fill"
        playPauseButton.setImage(
            UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 42, weight: .medium)),
            for: .normal
        )

        let currentMS = max(0, mediaPlayer.time.intValue)
        let durationMS = max(0, mediaPlayer.media?.length.intValue ?? 0)

        if !isSeeking {
            currentTimeLabel.text = formatTime(milliseconds: currentMS)
            durationLabel.text = durationMS > 0 ? formatTime(milliseconds: durationMS) : "--:--"

            if mediaPlayer.isSeekable, durationMS > 0 {
                progressSlider.isEnabled = true
                progressSlider.value = Float(max(0, min(1, mediaPlayer.position)))
            } else {
                progressSlider.isEnabled = false
                progressSlider.value = 0
            }
        }

        audioButton.isEnabled = !mediaPlayer.audioTracks.isEmpty
        subtitlesButton.isEnabled = !mediaPlayer.textTracks.isEmpty
        audioButton.alpha = audioButton.isEnabled ? 1 : 0.45
        subtitlesButton.alpha = subtitlesButton.isEnabled ? 1 : 0.45
    }

    private func formatTime(milliseconds: Int32) -> String {
        let seconds = max(0, Int(milliseconds) / 1000)
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%02d:%02d", minutes, secs)
    }

    @objc private func showControlsTapped() {
        guard !controlsVisible else { return }
        setControlsVisible(true, animated: true)
        scheduleControlsHide()
    }

    @objc private func hideControlsTapped() {
        guard controlsVisible else { return }
        setControlsVisible(false, animated: true)
    }

    private func setControlsVisible(_ visible: Bool, animated: Bool) {
        controlsVisible = visible
        hideControlsWorkItem?.cancel()

        if visible {
            controlsView.isHidden = false
            controlsView.isUserInteractionEnabled = true

            if animated {
                controlsView.alpha = 0
                UIView.animate(withDuration: 0.2) {
                    self.controlsView.alpha = 1
                }
            } else {
                controlsView.alpha = 1
            }
        } else {
            let finishHide = {
                // Only hide if no newer action has shown the controls again.
                guard !self.controlsVisible else { return }
                self.controlsView.alpha = 0
                self.controlsView.isUserInteractionEnabled = false
                self.controlsView.isHidden = true
            }

            if animated {
                UIView.animate(withDuration: 0.2, animations: {
                    self.controlsView.alpha = 0
                }) { _ in
                    finishHide()
                }
            } else {
                finishHide()
            }
        }
    }

    private func scheduleControlsHide() {
        hideControlsWorkItem?.cancel()
        guard controlsVisible, !isSeeking else { return }

        let item = DispatchWorkItem { [weak self] in
            guard let self, self.controlsVisible, !self.isSeeking else { return }
            self.setControlsVisible(false, animated: true)
        }
        hideControlsWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5, execute: item)
    }

    private func userInteracted() {
        if !controlsVisible {
            setControlsVisible(true, animated: true)
        }
        scheduleControlsHide()
    }

    @objc private func closeTapped() {
        restorePortraitIfNeeded()
        mediaPlayer.stop()
        dismiss(animated: true)
    }

    @objc private func playPauseTapped() {
        if mediaPlayer.isPlaying {
            mediaPlayer.pause()
            hideControlsWorkItem?.cancel()
        } else {
            mediaPlayer.play()
            scheduleControlsHide()
        }
        refreshPlaybackUI()
    }

    @objc private func rewindTapped() {
        mediaPlayer.jumpBackward(10)
        userInteracted()
    }

    @objc private func forwardTapped() {
        mediaPlayer.jumpForward(10)
        userInteracted()
    }

    @objc private func sliderTouchDown() {
        isSeeking = true
        hideControlsWorkItem?.cancel()
    }

    @objc private func sliderValueChanged() {
        let durationMS = max(0, mediaPlayer.media?.length.intValue ?? 0)
        if durationMS > 0 {
            let previewMS = Int32(Float(durationMS) * progressSlider.value)
            currentTimeLabel.text = formatTime(milliseconds: previewMS)
        }
    }

    @objc private func sliderTouchEnded() {
        if mediaPlayer.isSeekable {
            mediaPlayer.position = Double(progressSlider.value)
        }
        isSeeking = false
        userInteracted()
    }

    @objc private func fitTapped() {
        fillMode.toggle()
        mediaPlayer.videoFitMode = fillMode ? .larger : .smaller

        let symbol = fillMode ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right"
        fitButton.setImage(
            UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 21, weight: .medium)),
            for: .normal
        )
        userInteracted()
    }

    @objc private func rotateTapped() {
        forceLandscape.toggle()
        setNeedsUpdateOfSupportedInterfaceOrientations()

        if let scene = view.window?.windowScene {
            let mask: UIInterfaceOrientationMask = forceLandscape ? .landscape : .portrait
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { error in
                print("[LampaTorr] Orientation update failed: \(error.localizedDescription)")
            }
        }

        userInteracted()
    }

    @objc private func audioTapped() {
        hideControlsWorkItem?.cancel()
        let tracks = mediaPlayer.audioTracks

        guard !tracks.isEmpty else {
            showSimpleMessage(title: "Аудио", message: "Дополнительные аудиодорожки не найдены.")
            return
        }

        let alert = UIAlertController(title: "Аудиодорожка", message: nil, preferredStyle: .actionSheet)

        for track in tracks {
            var title = track.trackName
            if let language = track.language, !language.isEmpty, !title.localizedCaseInsensitiveContains(language) {
                title += " · " + language
            }
            if track.isSelected {
                title = "✓ " + title
            }

            alert.addAction(UIAlertAction(title: title, style: .default) { [weak self, weak track] _ in
                guard let self, let track else { return }
                track.isSelectedExclusively = true
                self.scheduleControlsHide()
            })
        }

        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel) { [weak self] _ in
            self?.scheduleControlsHide()
        })

        preparePopover(alert, sourceView: audioButton)
        present(alert, animated: true)
    }

    @objc private func subtitlesTapped() {
        hideControlsWorkItem?.cancel()
        let tracks = mediaPlayer.textTracks

        let alert = UIAlertController(title: "Субтитры", message: nil, preferredStyle: .actionSheet)

        alert.addAction(UIAlertAction(
            title: tracks.contains(where: { $0.isSelected }) ? "Выключить субтитры" : "✓ Выключены",
            style: .default
        ) { [weak self] _ in
            self?.mediaPlayer.deselectAllTextTracks()
            self?.scheduleControlsHide()
        })

        for track in tracks {
            var title = track.trackName
            if let language = track.language, !language.isEmpty, !title.localizedCaseInsensitiveContains(language) {
                title += " · " + language
            }
            if track.isSelected {
                title = "✓ " + title
            }

            alert.addAction(UIAlertAction(title: title, style: .default) { [weak self, weak track] _ in
                guard let self, let track else { return }
                track.isSelectedExclusively = true
                self.scheduleControlsHide()
            })
        }

        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel) { [weak self] _ in
            self?.scheduleControlsHide()
        })

        preparePopover(alert, sourceView: subtitlesButton)
        present(alert, animated: true)
    }

    private func preparePopover(_ alert: UIAlertController, sourceView: UIView) {
        if let popover = alert.popoverPresentationController {
            popover.sourceView = sourceView
            popover.sourceRect = sourceView.bounds
        }
    }

    private func restorePortraitIfNeeded() {
        guard forceLandscape else { return }
        forceLandscape = false
        setNeedsUpdateOfSupportedInterfaceOrientations()

        if let scene = view.window?.windowScene {
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait), errorHandler: nil)
        }
    }

    private func showSimpleMessage(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in
            self?.scheduleControlsHide()
        })
        present(alert, animated: true)
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
    override var shouldAutorotate: Bool { true }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        forceLandscape ? .landscape : .portrait
    }
}
