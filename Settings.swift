import AVFoundation
import UIKit

/// Player preferences. Values persist in `UserDefaults` and are read live, so a menu
/// change is already in effect on the next run.
enum GameSettings {
    private static let defaults = UserDefaults.standard

    private enum Key {
        static let music = "HighwayCrawl.musicEnabled"
        static let soundEffects = "HighwayCrawl.soundEffectsEnabled"
        static let haptics = "HighwayCrawl.hapticsEnabled"
        static let onScreenButtons = "HighwayCrawl.showOnScreenButtons"
        static let reduceFlashing = "HighwayCrawl.reduceFlashing"
    }

    static var musicEnabled: Bool {
        get { bool(forKey: Key.music, default: true) }
        set { defaults.set(newValue, forKey: Key.music) }
    }

    static var soundEffectsEnabled: Bool {
        get { bool(forKey: Key.soundEffects, default: true) }
        set { defaults.set(newValue, forKey: Key.soundEffects) }
    }

    static var hapticsEnabled: Bool {
        get { bool(forKey: Key.haptics, default: true) }
        set { defaults.set(newValue, forKey: Key.haptics) }
    }

    static var showOnScreenButtons: Bool {
        get { bool(forKey: Key.onScreenButtons, default: true) }
        set { defaults.set(newValue, forKey: Key.onScreenButtons) }
    }

    static var reduceFlashing: Bool {
        get { bool(forKey: Key.reduceFlashing, default: false) }
        set { defaults.set(newValue, forKey: Key.reduceFlashing) }
    }

    private static func bool(forKey key: String, default defaultValue: Bool) -> Bool {
        if defaults.object(forKey: key) == nil { return defaultValue }
        return defaults.bool(forKey: key)
    }
}

enum GameHaptics {
    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let medium = UIImpactFeedbackGenerator(style: .medium)
    private static let heavy = UIImpactFeedbackGenerator(style: .heavy)
    private static let notify = UINotificationFeedbackGenerator()

    static func laneChange() {
        guard GameSettings.hapticsEnabled else { return }
        light.impactOccurred()
    }

    static func jump() {
        guard GameSettings.hapticsEnabled else { return }
        medium.impactOccurred()
    }

    static func bounce() {
        guard GameSettings.hapticsEnabled else { return }
        medium.impactOccurred(intensity: 0.85)
    }

    static func ambulanceWarning() {
        guard GameSettings.hapticsEnabled else { return }
        notify.notificationOccurred(.warning)
    }

    static func crash() {
        guard GameSettings.hapticsEnabled else { return }
        heavy.impactOccurred()
    }

    /// Confirmation tap when the player turns haptics back on.
    static func preview() {
        light.impactOccurred()
    }
}

enum GameSounds {
    /// Roof bounces chain faster than the clip length, so a few players let them overlap.
    private static let bouncePlayers: [AVAudioPlayer] = {
        try? AVAudioSession.sharedInstance().setCategory(.ambient)
        guard let url = Bundle.main.url(forResource: "bounce", withExtension: "caf") else { return [] }
        return (0..<3).compactMap { _ in
            let player = try? AVAudioPlayer(contentsOf: url)
            player?.volume = 0.4
            player?.prepareToPlay()
            return player
        }
    }()
    private static var nextBouncePlayer = 0

    /// Loads the clips ahead of time so the first bounce doesn't stall.
    static func preload() {
        _ = bouncePlayers
    }

    static func bounce() {
        guard GameSettings.soundEffectsEnabled, !bouncePlayers.isEmpty else { return }
        let player = bouncePlayers[nextBouncePlayer]
        nextBouncePlayer = (nextBouncePlayer + 1) % bouncePlayers.count
        player.currentTime = 0
        player.play()
    }
}

/// Background music. Plays the tracks in order and wraps back to the first,
/// so Waves opens the app and the playlist then alternates.
final class GameMusic: NSObject, AVAudioPlayerDelegate {
    static let shared = GameMusic()

    private let tracks = ["waves", "feel-the-earth-spinning"]
    private var trackIndex = 0
    private var player: AVAudioPlayer?

    private override init() {
        super.init()
        try? AVAudioSession.sharedInstance().setCategory(.ambient)
        try? AVAudioSession.sharedInstance().setActive(true)
        NotificationCenter.default.addObserver(
            self, selector: #selector(appDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification, object: nil)
    }

    func start() {
        guard GameSettings.musicEnabled else { return }
        if player == nil { loadTrack(at: trackIndex) }
        player?.play()
    }

    func stop() {
        player?.pause()
    }

    func refresh() {
        GameSettings.musicEnabled ? start() : stop()
    }

    private func loadTrack(at index: Int) {
        trackIndex = index % tracks.count
        guard let url = Bundle.main.url(forResource: tracks[trackIndex], withExtension: "mp3") else {
            player = nil
            return
        }
        player = try? AVAudioPlayer(contentsOf: url)
        player?.delegate = self
        player?.volume = 0.5
        player?.prepareToPlay()
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        loadTrack(at: trackIndex + 1)
        start()
    }

    /// Playback is suspended while the app is backgrounded.
    @objc private func appDidBecomeActive() {
        refresh()
    }
}

/// Settings card with persisted toggles. Backdrop or Close dismisses it.
final class SettingsPopupView: UIView, UIGestureRecognizerDelegate {

    var onDismiss: (() -> Void)?

    private let card = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor.black.withAlphaComponent(0.5)
        isUserInteractionEnabled = true

        let backdropTap = UITapGestureRecognizer(target: self, action: #selector(didTapBackdrop))
        backdropTap.delegate = self
        addGestureRecognizer(backdropTap)

        card.backgroundColor = UIColor(white: 0.1, alpha: 0.96)
        card.layer.cornerRadius = 16
        card.layer.borderWidth = 2
        card.layer.borderColor = UIColor.white.cgColor
        card.translatesAutoresizingMaskIntoConstraints = false
        addSubview(card)

        let titleLabel = UILabel()
        titleLabel.text = "Settings"
        titleLabel.textColor = .white
        titleLabel.font = .systemFont(ofSize: 24, weight: .bold)
        titleLabel.textAlignment = .center

        let rows = UIStackView(arrangedSubviews: [
            makeRow(title: "Music", isOn: GameSettings.musicEnabled, action: #selector(didToggleMusic)),
            makeRow(title: "Sound Effects", isOn: GameSettings.soundEffectsEnabled, action: #selector(didToggleSoundEffects)),
            makeRow(title: "Haptics", isOn: GameSettings.hapticsEnabled, action: #selector(didToggleHaptics)),
            makeRow(title: "On-Screen Buttons", isOn: GameSettings.showOnScreenButtons, action: #selector(didToggleOnScreenButtons)),
            makeRow(title: "Reduce Flashing", isOn: GameSettings.reduceFlashing, action: #selector(didToggleReduceFlashing))
        ])
        rows.axis = .vertical
        rows.alignment = .fill
        rows.spacing = 4

        let closeButton = makeCloseButton()

        let stack = UIStackView(arrangedSubviews: [titleLabel, rows, closeButton])
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 16
        stack.setCustomSpacing(20, after: rows)
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)

        NSLayoutConstraint.activate([
            card.centerXAnchor.constraint(equalTo: centerXAnchor),
            card.centerYAnchor.constraint(equalTo: centerYAnchor),
            card.widthAnchor.constraint(equalTo: widthAnchor, multiplier: 0.55),
            card.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -48),
            card.topAnchor.constraint(greaterThanOrEqualTo: safeAreaLayoutGuide.topAnchor, constant: 12),
            card.bottomAnchor.constraint(lessThanOrEqualTo: safeAreaLayoutGuide.bottomAnchor, constant: -12),

            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -24),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -20),

            closeButton.heightAnchor.constraint(equalToConstant: 44)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func makeRow(title: String, isOn: Bool, action: Selector) -> UIView {
        let label = UILabel()
        label.text = title
        label.textColor = .white
        label.font = .systemFont(ofSize: 16, weight: .semibold)
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let toggle = UISwitch()
        toggle.isOn = isOn
        toggle.onTintColor = UIColor(red: 0.3, green: 0.9, blue: 0.4, alpha: 1)
        toggle.addTarget(self, action: action, for: .valueChanged)
        toggle.setContentHuggingPriority(.required, for: .horizontal)

        let row = UIStackView(arrangedSubviews: [label, toggle])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 12
        row.isLayoutMarginsRelativeArrangement = true
        row.layoutMargins = UIEdgeInsets(top: 6, left: 0, bottom: 6, right: 0)
        row.accessibilityLabel = title
        return row
    }

    private func makeCloseButton() -> UIButton {
        var closeConfig = UIButton.Configuration.plain()
        closeConfig.title = "Close"
        closeConfig.baseForegroundColor = .white
        closeConfig.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = .systemFont(ofSize: 16, weight: .semibold)
            outgoing.foregroundColor = .white
            return outgoing
        }
        let closeButton = UIButton(type: .system)
        closeButton.configuration = closeConfig
        closeButton.layer.borderWidth = 2
        closeButton.layer.borderColor = UIColor.white.cgColor
        closeButton.addTarget(self, action: #selector(didTapClose), for: .touchUpInside)
        return closeButton
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        !card.frame.contains(touch.location(in: self))
    }

    @objc private func didToggleMusic(_ sender: UISwitch) {
        GameSettings.musicEnabled = sender.isOn
        GameMusic.shared.refresh()
    }

    @objc private func didToggleSoundEffects(_ sender: UISwitch) {
        GameSettings.soundEffectsEnabled = sender.isOn
    }

    @objc private func didToggleHaptics(_ sender: UISwitch) {
        GameSettings.hapticsEnabled = sender.isOn
        if sender.isOn { GameHaptics.preview() }
    }

    @objc private func didToggleOnScreenButtons(_ sender: UISwitch) {
        GameSettings.showOnScreenButtons = sender.isOn
    }

    @objc private func didToggleReduceFlashing(_ sender: UISwitch) {
        GameSettings.reduceFlashing = sender.isOn
    }

    @objc private func didTapBackdrop() {
        onDismiss?()
    }

    @objc private func didTapClose() {
        onDismiss?()
    }
}
