/*
 * LampaTorr VLC-style player
 *
 * UI architecture and interaction model adapted from VLC for iOS:
 * https://github.com/videolan/vlc-ios
 * Reference commit: a96a4ecbdc86437a1a7ac559b60f4443bd4ad305
 *
 * VLC for iOS is distributed under GPL-2.0-or-later / MPL-2.0.
 */

import UIKit
import AVFoundation
import MediaPlayer
import VLCKit

final class VLCPlayerViewController: UIViewController, UIGestureRecognizerDelegate {
    private enum PanMode {
        case none, seek, brightness, volume
    }

    private enum AspectMode: Int, CaseIterable {
        case fit, fill, ratio16x9, ratio4x3

        var title: String {
            switch self {
            case .fit: return "По размеру"
            case .fill: return "Заполнить экран"
            case .ratio16x9: return "16:9"
            case .ratio4x3: return "4:3"
            }
        }
    }

    private let streamURL: URL
    private let mediaPlayer = VLCMediaPlayer()

    private let videoOutputView = UIView()
    private let gestureView = UIView()

    private let topGradientView = UIView()
    private let bottomGradientView = UIView()
    private let topGradient = CAGradientLayer()
    private let bottomGradient = CAGradientLayer()

    private let topBar = UIStackView()
    private let bottomControls = UIStackView()
    private let scrubContainer = UIView()

    private let closeButton = UIButton(type: .system)
    private let titleLabel = UILabel()
    private let rotationLockButton = UIButton(type: .system)

    private let tracksButton = UIButton(type: .system)
    private let backwardButton = UIButton(type: .system)
    private let playPauseButton = UIButton(type: .system)
    private let forwardButton = UIButton(type: .system)
    private let aspectButton = UIButton(type: .system)
    private let moreButton = UIButton(type: .system)

    private let progressSlider = UISlider()
    private let currentTimeLabel = UILabel()
    private let remainingTimeButton = UIButton(type: .system)

    private let statusContainer = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
    private let statusLabel = UILabel()

    private let volumeView = MPVolumeView(frame: .zero)
    private weak var systemVolumeSlider: UISlider?

    private var refreshTimer: Timer?
    private var idleTimer: Timer?
    private var controlsHidden = false
    private var isScrubbing = false
    private var orientationLocked = false
    private var lockedOrientationMask: UIInterfaceOrientationMask = .allButUpsideDown

    private var panMode: PanMode = .none
    private var panStartPosition: Float = 0
    private var panPreviewPosition: Float = 0
    private var panStartBrightness: CGFloat = 0
    private var panStartVolume: Float = 0

    private var aspectMode: AspectMode = .fit
    private var previousRate: Float = 1

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

        configureVideoOutput()
        configureGradients()
        configureTopBar()
        configureScrubBar()
        configureBottomControls()
        configureStatusHUD()
        configureVolumeBridge()
        configureGestures()
        configurePlayer()
        startRefreshTimer()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        topGradient.frame = topGradientView.bounds
        bottomGradient.frame = bottomGradientView.bounds
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        UIApplication.shared.isIdleTimerDisabled = true
        mediaPlayer.play()
        setControlsHidden(false, animated: false)
    }

    override func viewWillDisappear(_ animated: Bool) {
        idleTimer?.invalidate()
        refreshTimer?.invalidate()
        mediaPlayer.stop()
        UIApplication.shared.isIdleTimerDisabled = false
        super.viewWillDisappear(animated)
    }

    deinit {
        idleTimer?.invalidate()
        refreshTimer?.invalidate()
    }

    private func configureVideoOutput() {
        videoOutputView.translatesAutoresizingMaskIntoConstraints = false
        videoOutputView.backgroundColor = .black
        videoOutputView.isUserInteractionEnabled = false

        gestureView.translatesAutoresizingMaskIntoConstraints = false
        gestureView.backgroundColor = .clear
        gestureView.isUserInteractionEnabled = true

        view.addSubview(videoOutputView)
        view.addSubview(gestureView)

        NSLayoutConstraint.activate([
            videoOutputView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            videoOutputView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            videoOutputView.topAnchor.constraint(equalTo: view.topAnchor),
            videoOutputView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            gestureView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            gestureView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            gestureView.topAnchor.constraint(equalTo: view.topAnchor),
            gestureView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func configureGradients() {
        topGradientView.translatesAutoresizingMaskIntoConstraints = false
        topGradientView.isUserInteractionEnabled = false
        bottomGradientView.translatesAutoresizingMaskIntoConstraints = false
        bottomGradientView.isUserInteractionEnabled = false

        topGradient.colors = [
            UIColor.black.withAlphaComponent(0.72).cgColor,
            UIColor.clear.cgColor
        ]
        topGradient.startPoint = CGPoint(x: 0.5, y: 0)
        topGradient.endPoint = CGPoint(x: 0.5, y: 1)

        bottomGradient.colors = [
            UIColor.clear.cgColor,
            UIColor.black.withAlphaComponent(0.78).cgColor
        ]
        bottomGradient.startPoint = CGPoint(x: 0.5, y: 0)
        bottomGradient.endPoint = CGPoint(x: 0.5, y: 1)

        topGradientView.layer.addSublayer(topGradient)
        bottomGradientView.layer.addSublayer(bottomGradient)

        view.addSubview(topGradientView)
        view.addSubview(bottomGradientView)

        NSLayoutConstraint.activate([
            topGradientView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            topGradientView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            topGradientView.topAnchor.constraint(equalTo: view.topAnchor),
            topGradientView.heightAnchor.constraint(equalToConstant: 130),

            bottomGradientView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomGradientView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomGradientView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            bottomGradientView.heightAnchor.constraint(equalToConstant: 220)
        ])
    }

    private func configureTopBar() {
        topBar.translatesAutoresizingMaskIntoConstraints = false
        topBar.axis = .horizontal
        topBar.alignment = .center
        topBar.spacing = 12
        topBar.layoutMargins = UIEdgeInsets(top: 0, left: 14, bottom: 0, right: 14)
        topBar.isLayoutMarginsRelativeArrangement = true

        configureIconButton(closeButton, symbol: "xmark", size: 22)
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)

        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textColor = .white
        titleLabel.numberOfLines = 1
        titleLabel.lineBreakMode = .byTruncatingMiddle
        titleLabel.textAlignment = .center
        titleLabel.text = mediaTitle

        configureIconButton(rotationLockButton, symbol: "lock.rotation", size: 22)
        rotationLockButton.addTarget(self, action: #selector(rotationLockTapped), for: .touchUpInside)

        topBar.addArrangedSubview(closeButton)
        topBar.addArrangedSubview(titleLabel)
        topBar.addArrangedSubview(rotationLockButton)

        closeButton.widthAnchor.constraint(equalToConstant: 46).isActive = true
        closeButton.heightAnchor.constraint(equalToConstant: 46).isActive = true
        rotationLockButton.widthAnchor.constraint(equalToConstant: 46).isActive = true
        rotationLockButton.heightAnchor.constraint(equalToConstant: 46).isActive = true

        view.addSubview(topBar)

        NSLayoutConstraint.activate([
            topBar.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            topBar.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            topBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 4),
            topBar.heightAnchor.constraint(equalToConstant: 52)
        ])
    }

    private func configureScrubBar() {
        scrubContainer.translatesAutoresizingMaskIntoConstraints = false

        configureTimeLabel(currentTimeLabel)
        currentTimeLabel.text = "00:00"

        remainingTimeButton.translatesAutoresizingMaskIntoConstraints = false
        remainingTimeButton.setTitleColor(.white, for: .normal)
        remainingTimeButton.titleLabel?.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        remainingTimeButton.contentHorizontalAlignment = .right
        remainingTimeButton.setTitle("--:--", for: .normal)
        remainingTimeButton.addTarget(self, action: #selector(remainingTimeTapped), for: .touchUpInside)

        progressSlider.translatesAutoresizingMaskIntoConstraints = false
        progressSlider.minimumValue = 0
        progressSlider.maximumValue = 1
        progressSlider.minimumTrackTintColor = .white
        progressSlider.maximumTrackTintColor = UIColor.white.withAlphaComponent(0.28)
        progressSlider.addTarget(self, action: #selector(scrubTouchDown), for: .touchDown)
        progressSlider.addTarget(self, action: #selector(scrubChanged), for: .valueChanged)
        progressSlider.addTarget(self, action: #selector(scrubTouchUp), for: [.touchUpInside, .touchUpOutside, .touchCancel])

        scrubContainer.addSubview(currentTimeLabel)
        scrubContainer.addSubview(progressSlider)
        scrubContainer.addSubview(remainingTimeButton)
        view.addSubview(scrubContainer)

        NSLayoutConstraint.activate([
            scrubContainer.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 14),
            scrubContainer.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -14),
            scrubContainer.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -66),
            scrubContainer.heightAnchor.constraint(equalToConstant: 32),

            currentTimeLabel.leadingAnchor.constraint(equalTo: scrubContainer.leadingAnchor),
            currentTimeLabel.centerYAnchor.constraint(equalTo: scrubContainer.centerYAnchor),
            currentTimeLabel.widthAnchor.constraint(equalToConstant: 62),

            remainingTimeButton.trailingAnchor.constraint(equalTo: scrubContainer.trailingAnchor),
            remainingTimeButton.centerYAnchor.constraint(equalTo: scrubContainer.centerYAnchor),
            remainingTimeButton.widthAnchor.constraint(equalToConstant: 72),
            remainingTimeButton.heightAnchor.constraint(equalToConstant: 30),

            progressSlider.leadingAnchor.constraint(equalTo: currentTimeLabel.trailingAnchor, constant: 8),
            progressSlider.trailingAnchor.constraint(equalTo: remainingTimeButton.leadingAnchor, constant: -8),
            progressSlider.centerYAnchor.constraint(equalTo: scrubContainer.centerYAnchor)
        ])
    }

    private func configureBottomControls() {
        bottomControls.translatesAutoresizingMaskIntoConstraints = false
        bottomControls.axis = .horizontal
        bottomControls.alignment = .center
        bottomControls.distribution = .equalCentering
        bottomControls.spacing = 8

        configureIconButton(tracksButton, symbol: "captions.bubble", size: 22)
        tracksButton.addTarget(self, action: #selector(tracksTapped), for: .touchUpInside)

        configureIconButton(backwardButton, symbol: "gobackward.10", size: 28)
        backwardButton.addTarget(self, action: #selector(backwardTapped), for: .touchUpInside)

        configureIconButton(playPauseButton, symbol: "pause.circle.fill", size: 44)
        playPauseButton.addTarget(self, action: #selector(playPauseTapped), for: .touchUpInside)

        configureIconButton(forwardButton, symbol: "goforward.10", size: 28)
        forwardButton.addTarget(self, action: #selector(forwardTapped), for: .touchUpInside)

        configureIconButton(aspectButton, symbol: "rectangle.arrowtriangle.2.outward", size: 22)
        aspectButton.addTarget(self, action: #selector(aspectTapped), for: .touchUpInside)

        configureIconButton(moreButton, symbol: "ellipsis.circle", size: 23)
        moreButton.addTarget(self, action: #selector(moreTapped), for: .touchUpInside)

        [tracksButton, backwardButton, playPauseButton, forwardButton, aspectButton, moreButton].forEach {
            bottomControls.addArrangedSubview($0)
        }

        playPauseButton.widthAnchor.constraint(equalToConstant: 60).isActive = true
        playPauseButton.heightAnchor.constraint(equalToConstant: 60).isActive = true

        view.addSubview(bottomControls)

        NSLayoutConstraint.activate([
            bottomControls.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 18),
            bottomControls.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -18),
            bottomControls.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -4),
            bottomControls.heightAnchor.constraint(equalToConstant: 56)
        ])
    }

    private func configureStatusHUD() {
        statusContainer.translatesAutoresizingMaskIntoConstraints = false
        statusContainer.layer.cornerRadius = 12
        statusContainer.clipsToBounds = true
        statusContainer.alpha = 0

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.textColor = .white
        statusLabel.font = .monospacedDigitSystemFont(ofSize: 16, weight: .semibold)
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 2

        statusContainer.contentView.addSubview(statusLabel)
        view.addSubview(statusContainer)

        NSLayoutConstraint.activate([
            statusContainer.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            statusContainer.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            statusContainer.widthAnchor.constraint(greaterThanOrEqualToConstant: 130),
            statusContainer.heightAnchor.constraint(greaterThanOrEqualToConstant: 58),

            statusLabel.leadingAnchor.constraint(equalTo: statusContainer.contentView.leadingAnchor, constant: 16),
            statusLabel.trailingAnchor.constraint(equalTo: statusContainer.contentView.trailingAnchor, constant: -16),
            statusLabel.topAnchor.constraint(equalTo: statusContainer.contentView.topAnchor, constant: 10),
            statusLabel.bottomAnchor.constraint(equalTo: statusContainer.contentView.bottomAnchor, constant: -10)
        ])
    }

    private func configureVolumeBridge() {
        volumeView.frame = CGRect(x: -1000, y: -1000, width: 1, height: 1)
        volumeView.alpha = 0.0001
        view.addSubview(volumeView)

        DispatchQueue.main.async { [weak self] in
            self?.systemVolumeSlider = self?.volumeView.subviews.compactMap { $0 as? UISlider }.first
        }
    }

    private func configureGestures() {
        let singleTap = UITapGestureRecognizer(target: self, action: #selector(singleTap(_:)))
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(doubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        singleTap.require(toFail: doubleTap)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(panGesture(_:)))
        pan.maximumNumberOfTouches = 1
        pan.delegate = self

        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(longPressGesture(_:)))
        longPress.minimumPressDuration = 0.5

        gestureView.addGestureRecognizer(singleTap)
        gestureView.addGestureRecognizer(doubleTap)
        gestureView.addGestureRecognizer(pan)
        gestureView.addGestureRecognizer(longPress)
    }

    private func configurePlayer() {
        mediaPlayer.drawable = videoOutputView
        mediaPlayer.timeChangeUpdateInterval = 0.5
        applyAspectMode(.fit)

        guard let media = VLCMedia(url: streamURL) else {
            showError("VLCKit не смог создать медиапоток.")
            return
        }

        media.addOption(":network-caching=2500")
        media.addOption(":clock-jitter=0")
        mediaPlayer.media = media
    }

    private func configureIconButton(_ button: UIButton, symbol: String, size: CGFloat) {
        button.translatesAutoresizingMaskIntoConstraints = false
        button.tintColor = .white
        button.backgroundColor = .clear
        button.setImage(
            UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: size, weight: .regular)),
            for: .normal
        )
    }

    private func configureTimeLabel(_ label: UILabel) {
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        label.textColor = .white
    }

    private func startRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            self?.refreshUI()
        }
    }

    private func refreshUI() {
        let playing = mediaPlayer.isPlaying
        playPauseButton.setImage(
            UIImage(
                systemName: playing ? "pause.circle.fill" : "play.circle.fill",
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 44, weight: .regular)
            ),
            for: .normal
        )

        let currentMS = max(0, mediaPlayer.time.intValue)
        let durationMS = max(0, mediaPlayer.media?.length.intValue ?? 0)

        if !isScrubbing {
            currentTimeLabel.text = formatTime(milliseconds: currentMS)

            if durationMS > 0 {
                progressSlider.isEnabled = mediaPlayer.isSeekable
                progressSlider.value = Float(max(0, min(1, mediaPlayer.position)))
                updateRemainingTime(currentMS: currentMS, durationMS: durationMS)
            } else {
                progressSlider.isEnabled = false
                progressSlider.value = 0
                remainingTimeButton.setTitle("--:--", for: .normal)
            }
        }

        tracksButton.alpha = (!mediaPlayer.audioTracks.isEmpty || !mediaPlayer.textTracks.isEmpty) ? 1 : 0.45
    }

    private func setControlsHidden(_ hidden: Bool, animated: Bool) {
        controlsHidden = hidden
        idleTimer?.invalidate()
        idleTimer = nil

        let alpha: CGFloat = hidden ? 0 : 1
        let updates = {
            self.topBar.alpha = alpha
            self.scrubContainer.alpha = alpha
            self.bottomControls.alpha = alpha
            self.topGradientView.alpha = alpha
            self.bottomGradientView.alpha = alpha
        }

        let completion: (Bool) -> Void = { _ in
            let enabled = !hidden
            self.topBar.isUserInteractionEnabled = enabled
            self.scrubContainer.isUserInteractionEnabled = enabled
            self.bottomControls.isUserInteractionEnabled = enabled
            self.setNeedsStatusBarAppearanceUpdate()
        }

        if animated {
            UIView.animate(
                withDuration: 0.2,
                delay: 0,
                options: [.beginFromCurrentState, .allowUserInteraction],
                animations: updates,
                completion: completion
            )
        } else {
            updates()
            completion(true)
        }

        if !hidden {
            resetIdleTimer()
        }
    }

    private func resetIdleTimer() {
        idleTimer?.invalidate()
        guard !controlsHidden, !isScrubbing else { return }

        idleTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: false) { [weak self] _ in
            guard let self, !self.isScrubbing else { return }
            self.setControlsHidden(true, animated: true)
        }
    }

    @objc private func singleTap(_ recognizer: UITapGestureRecognizer) {
        setControlsHidden(!controlsHidden, animated: true)
    }

    @objc private func doubleTap(_ recognizer: UITapGestureRecognizer) {
        let point = recognizer.location(in: gestureView)
        let third = gestureView.bounds.width / 3

        if point.x < third {
            mediaPlayer.jumpBackward(10)
            showStatus("⇐ 10 сек")
        } else if point.x > third * 2 {
            mediaPlayer.jumpForward(10)
            showStatus("⇒ 10 сек")
        } else {
            cycleAspectMode()
        }

        resetIdleTimer()
    }

    @objc private func longPressGesture(_ recognizer: UILongPressGestureRecognizer) {
        switch recognizer.state {
        case .began:
            previousRate = mediaPlayer.rate
            mediaPlayer.rate = max(2.0, min(8.0, previousRate * 2))
            showStatus(String(format: "%.1f×", mediaPlayer.rate))
            setControlsHidden(true, animated: true)
            UISelectionFeedbackGenerator().selectionChanged()
        case .ended, .cancelled, .failed:
            mediaPlayer.rate = previousRate
            hideStatus()
        default:
            break
        }
    }

    @objc private func panGesture(_ recognizer: UIPanGestureRecognizer) {
        let translation = recognizer.translation(in: gestureView)
        let velocity = recognizer.velocity(in: gestureView)
        let location = recognizer.location(in: gestureView)

        switch recognizer.state {
        case .began:
            idleTimer?.invalidate()
            idleTimer = nil

            if abs(velocity.x) > abs(velocity.y) {
                panMode = .seek
                panStartPosition = Float(mediaPlayer.position)
                panPreviewPosition = panStartPosition
            } else if location.x < gestureView.bounds.midX {
                panMode = .brightness
                panStartBrightness = UIScreen.main.brightness
            } else {
                panMode = .volume
                panStartVolume = systemVolumeSlider?.value ?? AVAudioSession.sharedInstance().outputVolume
            }

        case .changed:
            switch panMode {
            case .seek:
                guard mediaPlayer.isSeekable else { return }
                let delta = Float(translation.x / max(1, gestureView.bounds.width)) * 0.35
                panPreviewPosition = max(0, min(1, panStartPosition + delta))
                showSeekPreview(position: panPreviewPosition)

            case .brightness:
                let delta = -translation.y / max(1, gestureView.bounds.height)
                let value = max(0, min(1, panStartBrightness + delta))
                UIScreen.main.brightness = value
                showStatus("Яркость  \(Int(value * 100))%")

            case .volume:
                let delta = Float(-translation.y / max(1, gestureView.bounds.height))
                let value = max(0, min(1, panStartVolume + delta))
                systemVolumeSlider?.setValue(value, animated: false)
                systemVolumeSlider?.sendActions(for: .valueChanged)
                showStatus("Громкость  \(Int(value * 100))%")

            case .none:
                break
            }

        case .ended, .cancelled, .failed:
            if panMode == .seek, mediaPlayer.isSeekable {
                mediaPlayer.position = Double(panPreviewPosition)
            }
            panMode = .none
            hideStatus(after: 0.45)
            resetIdleTimer()

        default:
            break
        }
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        true
    }

    @objc private func closeTapped() {
        mediaPlayer.stop()
        dismiss(animated: true)
    }

    @objc private func playPauseTapped() {
        if mediaPlayer.isPlaying {
            mediaPlayer.pause()
            setControlsHidden(false, animated: true)
        } else {
            mediaPlayer.play()
            resetIdleTimer()
        }
        refreshUI()
    }

    @objc private func backwardTapped() {
        mediaPlayer.jumpBackward(10)
        showStatus("⇐ 10 сек")
        resetIdleTimer()
    }

    @objc private func forwardTapped() {
        mediaPlayer.jumpForward(10)
        showStatus("⇒ 10 сек")
        resetIdleTimer()
    }

    @objc private func rotationLockTapped() {
        orientationLocked.toggle()

        if orientationLocked {
            lockedOrientationMask = currentOrientationMask
            rotationLockButton.tintColor = .systemOrange
        } else {
            lockedOrientationMask = .allButUpsideDown
            rotationLockButton.tintColor = .white
        }

        setNeedsUpdateOfSupportedInterfaceOrientations()
        resetIdleTimer()
    }

    @objc private func aspectTapped() {
        cycleAspectMode()
        resetIdleTimer()
    }

    @objc private func tracksTapped() {
        idleTimer?.invalidate()
        presentTracksSheet()
    }

    @objc private func moreTapped() {
        idleTimer?.invalidate()
        presentMoreSheet()
    }

    @objc private func remainingTimeTapped() {
        let currentMS = max(0, mediaPlayer.time.intValue)
        let durationMS = max(0, mediaPlayer.media?.length.intValue ?? 0)
        guard durationMS > 0 else { return }

        let remaining = max(0, durationMS - currentMS)
        let currentTitle = remainingTimeButton.title(for: .normal) ?? ""

        if currentTitle.hasPrefix("-") {
            remainingTimeButton.setTitle(formatTime(milliseconds: durationMS), for: .normal)
        } else {
            remainingTimeButton.setTitle("-" + formatTime(milliseconds: remaining), for: .normal)
        }

        resetIdleTimer()
    }

    @objc private func scrubTouchDown() {
        isScrubbing = true
        idleTimer?.invalidate()
    }

    @objc private func scrubChanged() {
        let durationMS = max(0, mediaPlayer.media?.length.intValue ?? 0)
        guard durationMS > 0 else { return }
        let targetMS = Int32(Float(durationMS) * progressSlider.value)
        currentTimeLabel.text = formatTime(milliseconds: targetMS)
    }

    @objc private func scrubTouchUp() {
        if mediaPlayer.isSeekable {
            mediaPlayer.position = Double(progressSlider.value)
        }
        isScrubbing = false
        resetIdleTimer()
    }

    private func presentTracksSheet() {
        let alert = UIAlertController(title: "Субтитры и аудиодорожки", message: nil, preferredStyle: .actionSheet)
        let audioTracks = mediaPlayer.audioTracks
        let textTracks = mediaPlayer.textTracks

        for track in audioTracks {
            var title = "Аудио: " + track.trackName
            if let language = track.language, !language.isEmpty,
               !title.localizedCaseInsensitiveContains(language) {
                title += " · " + language
            }
            if track.isSelected { title = "✓ " + title }

            alert.addAction(UIAlertAction(title: title, style: .default) { [weak self, track] _ in
                track.isSelectedExclusively = true
                self?.showStatus("Аудиодорожка: " + track.trackName)
                self?.resetIdleTimer()
            })
        }

        alert.addAction(UIAlertAction(
            title: textTracks.contains(where: { $0.isSelected }) ? "Субтитры: выключить" : "✓ Субтитры: выключены",
            style: .default
        ) { [weak self] _ in
            self?.mediaPlayer.deselectAllTextTracks()
            self?.resetIdleTimer()
        })

        for track in textTracks {
            var title = "Субтитры: " + track.trackName
            if let language = track.language, !language.isEmpty,
               !title.localizedCaseInsensitiveContains(language) {
                title += " · " + language
            }
            if track.isSelected { title = "✓ " + title }

            alert.addAction(UIAlertAction(title: title, style: .default) { [weak self, track] _ in
                track.isSelectedExclusively = true
                self?.showStatus("Субтитры: " + track.trackName)
                self?.resetIdleTimer()
            })
        }

        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel) { [weak self] _ in
            self?.resetIdleTimer()
        })

        preparePopover(alert, sourceView: tracksButton)
        present(alert, animated: true)
    }

    private func presentMoreSheet() {
        let alert = UIAlertController(title: "Параметры воспроизведения", message: nil, preferredStyle: .actionSheet)

        let rates: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]
        for rate in rates {
            let checked = abs(mediaPlayer.rate - rate) < 0.01
            let title = (checked ? "✓ " : "") + String(format: "Скорость %.2g×", rate)

            alert.addAction(UIAlertAction(title: title, style: .default) { [weak self] _ in
                self?.mediaPlayer.rate = rate
                self?.resetIdleTimer()
            })
        }

        alert.addAction(UIAlertAction(title: "Повернуть экран", style: .default) { [weak self] _ in
            self?.rotateScreen()
            self?.resetIdleTimer()
        })

        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel) { [weak self] _ in
            self?.resetIdleTimer()
        })

        preparePopover(alert, sourceView: moreButton)
        present(alert, animated: true)
    }

    private func cycleAspectMode() {
        let modes = AspectMode.allCases
        let nextIndex = (aspectMode.rawValue + 1) % modes.count
        applyAspectMode(modes[nextIndex])
        showStatus(aspectMode.title)
    }

    private func applyAspectMode(_ mode: AspectMode) {
        aspectMode = mode

        switch mode {
        case .fit:
            mediaPlayer.videoAspectRatio = nil
            mediaPlayer.videoFitMode = .smaller
        case .fill:
            mediaPlayer.videoAspectRatio = nil
            mediaPlayer.videoFitMode = .larger
        case .ratio16x9:
            mediaPlayer.videoAspectRatio = "16:9"
            mediaPlayer.videoFitMode = .smaller
        case .ratio4x3:
            mediaPlayer.videoAspectRatio = "4:3"
            mediaPlayer.videoFitMode = .smaller
        }
    }

    private func rotateScreen() {
        guard !orientationLocked, let scene = view.window?.windowScene else {
            showStatus("Ориентация заблокирована")
            return
        }

        let portrait = view.bounds.height >= view.bounds.width
        let mask: UIInterfaceOrientationMask = portrait ? .landscape : .portrait

        scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { [weak self] error in
            self?.showStatus(error.localizedDescription)
        }
    }

    private var currentOrientationMask: UIInterfaceOrientationMask {
        guard let orientation = view.window?.windowScene?.interfaceOrientation else {
            return .allButUpsideDown
        }

        switch orientation {
        case .portrait: return .portrait
        case .portraitUpsideDown: return .portraitUpsideDown
        case .landscapeLeft: return .landscapeLeft
        case .landscapeRight: return .landscapeRight
        default: return .allButUpsideDown
        }
    }

    private var mediaTitle: String {
        let decoded = streamURL.lastPathComponent.removingPercentEncoding ?? streamURL.lastPathComponent
        return decoded.isEmpty ? "VLC" : decoded
    }

    private func updateRemainingTime(currentMS: Int32, durationMS: Int32) {
        let remaining = max(0, durationMS - currentMS)
        remainingTimeButton.setTitle("-" + formatTime(milliseconds: remaining), for: .normal)
    }

    private func showSeekPreview(position: Float) {
        let durationMS = max(0, mediaPlayer.media?.length.intValue ?? 0)

        if durationMS > 0 {
            let targetMS = Int32(Float(durationMS) * position)
            showStatus(formatTime(milliseconds: targetMS))
        } else {
            showStatus(String(format: "%d%%", Int(position * 100)))
        }
    }

    private func formatTime(milliseconds: Int32) -> String {
        let totalSeconds = max(0, Int(milliseconds) / 1000)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func showStatus(_ text: String) {
        statusLabel.text = text
        statusContainer.layer.removeAllAnimations()

        UIView.animate(withDuration: 0.15) {
            self.statusContainer.alpha = 1
        }

        hideStatus(after: 0.8)
    }

    private func hideStatus(after delay: TimeInterval = 0) {
        statusContainer.layer.removeAllAnimations()

        UIView.animate(
            withDuration: 0.2,
            delay: delay,
            options: [.beginFromCurrentState],
            animations: {
                self.statusContainer.alpha = 0
            }
        )
    }

    private func preparePopover(_ alert: UIAlertController, sourceView: UIView) {
        if let popover = alert.popoverPresentationController {
            popover.sourceView = sourceView
            popover.sourceRect = sourceView.bounds
        }
    }

    private func showError(_ message: String) {
        let alert = UIAlertController(title: "VLC", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Закрыть", style: .default) { [weak self] _ in
            self?.dismiss(animated: true)
        })
        present(alert, animated: true)
    }

    override var prefersStatusBarHidden: Bool {
        controlsHidden || view.bounds.width > view.bounds.height
    }

    override var prefersHomeIndicatorAutoHidden: Bool { true }
    override var shouldAutorotate: Bool { !orientationLocked }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        orientationLocked ? lockedOrientationMask : .allButUpsideDown
    }
}
