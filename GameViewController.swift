//
//  GameViewController.swift
//  HighwayCrawl
//
//  Created by Pranav Thoppe on 10/17/26.
//

import UIKit
import SpriteKit
import GameplayKit

class GameViewController: UIViewController {

    private let skView = SKView()
    private let menuVideoView = LoopingVideoView()
    private let menuLogoView = UIImageView(image: UIImage(named: "menu.logo"))
    private let playButton = UIButton(type: .system)
    private let achievementsButton = UIButton(type: .system)
    private let settingsButton = UIButton(type: .system)
    private var menuButtonsRevealWork: DispatchWorkItem?
    private var menuPopupView: MenuPopupView?
    private let laneLeftButton = UIButton(type: .system)
    private let laneRightButton = UIButton(type: .system)
    private let actionButton = UIButton(type: .system)
    private let laneStack = UIStackView()
    private var hasPresentedScene = false
    private weak var gameScene: GameScene?

    override var canBecomeFirstResponder: Bool { true }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupGameView()
        setupControlButtons()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        becomeFirstResponder()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        presentGameSceneIfNeeded()
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if handleLaneKeys(presses) { return }
        super.pressesBegan(presses, with: event)
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .landscape
    }

    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation {
        return .landscapeRight
    }

    override var prefersStatusBarHidden: Bool {
        return true
    }

    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge {
        return [.left, .right, .bottom]
    }

    private func setupGameView() {
        skView.translatesAutoresizingMaskIntoConstraints = false
        skView.ignoresSiblingOrder = true
        skView.showsFPS = true
        skView.showsNodeCount = true
        view.addSubview(skView)

        menuVideoView.translatesAutoresizingMaskIntoConstraints = false
        menuVideoView.isHidden = true
        view.addSubview(menuVideoView)

        menuLogoView.translatesAutoresizingMaskIntoConstraints = false
        menuLogoView.contentMode = .scaleAspectFit
        menuLogoView.isUserInteractionEnabled = false
        menuVideoView.addSubview(menuLogoView)

        setupMenuButtons()

        let logoAspect = menuLogoView.image.map { $0.size.height / $0.size.width } ?? 0.45

        NSLayoutConstraint.activate([
            menuLogoView.topAnchor.constraint(equalTo: menuVideoView.safeAreaLayoutGuide.topAnchor, constant: 16),
            menuLogoView.trailingAnchor.constraint(equalTo: menuVideoView.trailingAnchor, constant: -12),
            menuLogoView.widthAnchor.constraint(equalTo: menuVideoView.widthAnchor, multiplier: 0.42),
            menuLogoView.heightAnchor.constraint(equalTo: menuLogoView.widthAnchor, multiplier: logoAspect),

            skView.topAnchor.constraint(equalTo: view.topAnchor),
            skView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            skView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            skView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            menuVideoView.topAnchor.constraint(equalTo: view.topAnchor),
            menuVideoView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            menuVideoView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            menuVideoView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func presentGameSceneIfNeeded() {
        guard !hasPresentedScene else { return }
        let size = skView.bounds.size
        guard size.width > 0, size.height > 0 else { return }

        hasPresentedScene = true
        showMenu(size: size)
    }

    private func showMenu(size: CGSize) {
        let menu = MenuScene(size: size)
        menu.scaleMode = .resizeFill
        menu.onPlay = { [weak self] in
            guard let self else { return }
            self.startNewGame(size: self.skView.bounds.size)
        }
        gameScene = nil
        setControlsHidden(true)
        skView.presentScene(menu)
        menuVideoView.play(resource: "MenuScreenBackground", withExtension: "mov")
        scheduleMenuButtonsReveal()
    }

    private func dismissMenuVideo() {
        guard menuVideoView.isPlaying else { return }
        UIView.animate(withDuration: 0.4, animations: {
            self.menuVideoView.alpha = 0
        }, completion: { _ in
            self.menuVideoView.stop()
        })
    }

    private func startNewGame(size: CGSize) {
        cancelMenuButtonsReveal()
        dismissMenuPopup()
        dismissMenuVideo()
        let scene = GameScene(size: size)
        scene.scaleMode = .resizeFill
        scene.onRetry = { [weak self] in
            guard let self else { return }
            self.startNewGame(size: self.skView.bounds.size)
        }
        scene.onGameOver = { [weak self] in
            self?.setControlsHidden(true)
        }
        scene.onJumpReadyChanged = { [weak self] ready in
            self?.setJumpReady(ready)
        }
        setControlsHidden(false)
        setJumpReady(true)
        gameScene = scene
        skView.presentScene(scene, transition: .fade(withDuration: 0.4))
    }

    private func setControlsHidden(_ hidden: Bool) {
        laneStack.isHidden = hidden
        actionButton.isHidden = hidden
    }

    private func setupMenuButtons() {
        configurePlayButton()
        configureMenuIconButton(achievementsButton, accessibilityLabel: "Achievements", systemImage: "trophy.fill")
        configureMenuIconButton(settingsButton, accessibilityLabel: "Settings", systemImage: "gearshape.fill")

        playButton.addTarget(self, action: #selector(didTapPlay), for: .touchUpInside)
        achievementsButton.addTarget(self, action: #selector(didTapAchievements), for: .touchUpInside)
        settingsButton.addTarget(self, action: #selector(didTapSettings), for: .touchUpInside)

        playButton.translatesAutoresizingMaskIntoConstraints = false
        achievementsButton.translatesAutoresizingMaskIntoConstraints = false
        settingsButton.translatesAutoresizingMaskIntoConstraints = false
        menuVideoView.addSubview(playButton)
        menuVideoView.addSubview(achievementsButton)
        menuVideoView.addSubview(settingsButton)

        let playSize: CGFloat = 88
        let iconSize: CGFloat = 56
        let cornerInset: CGFloat = 16

        NSLayoutConstraint.activate([
            playButton.centerXAnchor.constraint(equalTo: menuVideoView.centerXAnchor),
            playButton.centerYAnchor.constraint(equalTo: menuVideoView.centerYAnchor, constant: 36),
            playButton.widthAnchor.constraint(equalToConstant: playSize),
            playButton.heightAnchor.constraint(equalToConstant: playSize),

            achievementsButton.widthAnchor.constraint(equalToConstant: iconSize),
            achievementsButton.heightAnchor.constraint(equalToConstant: iconSize),
            achievementsButton.leadingAnchor.constraint(equalTo: menuVideoView.safeAreaLayoutGuide.leadingAnchor, constant: cornerInset),
            achievementsButton.bottomAnchor.constraint(equalTo: menuVideoView.safeAreaLayoutGuide.bottomAnchor, constant: -cornerInset),

            settingsButton.widthAnchor.constraint(equalToConstant: iconSize),
            settingsButton.heightAnchor.constraint(equalToConstant: iconSize),
            settingsButton.trailingAnchor.constraint(equalTo: menuVideoView.safeAreaLayoutGuide.trailingAnchor, constant: -cornerInset),
            settingsButton.bottomAnchor.constraint(equalTo: menuVideoView.safeAreaLayoutGuide.bottomAnchor, constant: -cornerInset)
        ])

        resetMenuButtonsHidden()
    }

    private func configurePlayButton() {
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: "play.fill")
        config.baseForegroundColor = .white
        config.baseBackgroundColor = .clear
        config.cornerStyle = .capsule
        config.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 32, weight: .bold)
        // Triangle glyphs sit optically left of center without a slight nudge.
        config.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 2, bottom: 0, trailing: 0)

        var background = UIBackgroundConfiguration.clear()
        background.strokeColor = .white
        background.strokeWidth = 2
        background.cornerRadius = 44
        config.background = background

        playButton.configuration = config
        playButton.accessibilityLabel = "Play"
        playButton.tintColor = .white
        playButton.layer.cornerRadius = 44
        playButton.layer.shadowColor = UIColor.black.cgColor
        playButton.layer.shadowOpacity = 0.9
        playButton.layer.shadowRadius = 4
        playButton.layer.shadowOffset = .zero
    }

    private func configureMenuIconButton(_ button: UIButton, accessibilityLabel: String, systemImage: String) {
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: systemImage)
        config.baseBackgroundColor = .clear
        config.baseForegroundColor = .white
        config.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 22, weight: .semibold)

        button.configuration = config
        button.backgroundColor = .clear
        button.tintColor = .white
        button.accessibilityLabel = accessibilityLabel
        button.layer.borderWidth = 2
        button.layer.borderColor = UIColor.white.cgColor
        button.layer.shadowColor = UIColor.black.cgColor
        button.layer.shadowOpacity = 0.9
        button.layer.shadowRadius = 4
        button.layer.shadowOffset = .zero
    }

    private func scheduleMenuButtonsReveal() {
        cancelMenuButtonsReveal()
        resetMenuButtonsHidden()
        let work = DispatchWorkItem { [weak self] in
            self?.revealMenuButtons()
        }
        menuButtonsRevealWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: work)
    }

    private func cancelMenuButtonsReveal() {
        menuButtonsRevealWork?.cancel()
        menuButtonsRevealWork = nil
    }

    private var menuChromeButtons: [UIButton] {
        [playButton, achievementsButton, settingsButton]
    }

    private func resetMenuButtonsHidden() {
        dismissMenuPopup()
        for chrome in menuChromeButtons {
            chrome.alpha = 0
            chrome.transform = CGAffineTransform(scaleX: 0.92, y: 0.92)
        }
    }

    private func revealMenuButtons() {
        guard menuVideoView.isPlaying else { return }
        UIView.animate(withDuration: 0.3, delay: 0, options: [.curveEaseOut]) {
            for chrome in self.menuChromeButtons {
                chrome.alpha = 1
                chrome.transform = .identity
            }
        }
    }

    @objc private func didTapPlay() {
        startNewGame(size: skView.bounds.size)
    }

    @objc private func didTapAchievements() {
        showMenuPopup(
            title: "Achievements",
            message: "Unlock trophies as you crawl the highway. This list will fill in later."
        )
    }

    @objc private func didTapSettings() {
        showMenuPopup(
            title: "Settings",
            message: "Audio, controls, and other options will live here."
        )
    }

    private func showMenuPopup(title: String, message: String) {
        dismissMenuPopup()

        let popup = MenuPopupView(title: title, message: message)
        popup.translatesAutoresizingMaskIntoConstraints = false
        popup.alpha = 0
        popup.onDismiss = { [weak self] in
            self?.dismissMenuPopup()
        }
        menuVideoView.addSubview(popup)
        NSLayoutConstraint.activate([
            popup.topAnchor.constraint(equalTo: menuVideoView.topAnchor),
            popup.leadingAnchor.constraint(equalTo: menuVideoView.leadingAnchor),
            popup.trailingAnchor.constraint(equalTo: menuVideoView.trailingAnchor),
            popup.bottomAnchor.constraint(equalTo: menuVideoView.bottomAnchor)
        ])
        menuPopupView = popup

        UIView.animate(withDuration: 0.2) {
            popup.alpha = 1
        }
    }

    private func dismissMenuPopup() {
        guard let popup = menuPopupView else { return }
        menuPopupView = nil
        UIView.animate(withDuration: 0.15, animations: {
            popup.alpha = 0
        }, completion: { _ in
            popup.removeFromSuperview()
        })
    }

    private func setupControlButtons() {
        configure(laneLeftButton, accessibilityLabel: "Left", systemImage: "chevron.left")
        configure(laneRightButton, accessibilityLabel: "Right", systemImage: "chevron.right")
        configure(actionButton, accessibilityLabel: "Action", systemImage: "circle.fill")

        laneLeftButton.addTarget(self, action: #selector(didTapLaneLeft), for: .touchUpInside)
        laneRightButton.addTarget(self, action: #selector(didTapLaneRight), for: .touchUpInside)
        actionButton.addTarget(self, action: #selector(didTapAction), for: .touchUpInside)

        laneStack.axis = .horizontal
        laneStack.spacing = 12
        laneStack.addArrangedSubview(laneLeftButton)
        laneStack.addArrangedSubview(laneRightButton)
        laneStack.translatesAutoresizingMaskIntoConstraints = false
        actionButton.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(laneStack)
        view.addSubview(actionButton)

        let buttonSize: CGFloat = 84
        NSLayoutConstraint.activate([
            laneLeftButton.widthAnchor.constraint(equalToConstant: buttonSize),
            laneLeftButton.heightAnchor.constraint(equalToConstant: buttonSize),
            laneRightButton.widthAnchor.constraint(equalToConstant: buttonSize),
            laneRightButton.heightAnchor.constraint(equalToConstant: buttonSize),

            laneStack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            laneStack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),

            actionButton.widthAnchor.constraint(equalToConstant: buttonSize),
            actionButton.heightAnchor.constraint(equalToConstant: buttonSize),
            actionButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            actionButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16)
        ])
    }

    private func configure(_ button: UIButton, accessibilityLabel: String, systemImage: String) {
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: systemImage)
        config.baseBackgroundColor = .clear
        config.baseForegroundColor = .white
        config.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 36, weight: .bold)

        button.configuration = config
        button.backgroundColor = .clear
        button.tintColor = .white
        button.accessibilityLabel = accessibilityLabel
        button.layer.shadowColor = UIColor.black.cgColor
        button.layer.shadowOpacity = 0.9
        button.layer.shadowRadius = 4
        button.layer.shadowOffset = .zero
    }

    @objc private func didTapLaneLeft() {
        gameScene?.changeLane(by: -1)
    }

    @objc private func didTapLaneRight() {
        gameScene?.changeLane(by: 1)
    }

    private func handleLaneKeys(_ presses: Set<UIPress>) -> Bool {
        var handled = false
        for press in presses {
            guard let key = press.key else { continue }
            switch key.keyCode {
            case .keyboardLeftArrow:
                gameScene?.changeLane(by: -1)
                handled = true
            case .keyboardRightArrow:
                gameScene?.changeLane(by: 1)
                handled = true
            case .keyboardSpacebar, .keyboardUpArrow:
                gameScene?.jump()
                handled = true
            default:
                break
            }
        }
        return handled
    }

    @objc private func didTapAction() {
        gameScene?.jump()
    }

    /// Dims the action button while the jump is on cooldown.
    private func setJumpReady(_ ready: Bool) {
        actionButton.alpha = ready ? 1 : 0.35
    }
}

/// Dimmed menu overlay. Taps on the backdrop or close button dismiss it so the game does not start.
private final class MenuPopupView: UIView, UIGestureRecognizerDelegate {

    var onDismiss: (() -> Void)?

    private let card = UIView()

    init(title: String, message: String) {
        super.init(frame: .zero)
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
        titleLabel.text = title
        titleLabel.textColor = .white
        titleLabel.font = .systemFont(ofSize: 24, weight: .bold)
        titleLabel.textAlignment = .center

        let messageLabel = UILabel()
        messageLabel.text = message
        messageLabel.textColor = UIColor(white: 0.85, alpha: 1)
        messageLabel.font = .systemFont(ofSize: 16, weight: .regular)
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0

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

        let stack = UIStackView(arrangedSubviews: [titleLabel, messageLabel, closeButton])
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 16
        stack.setCustomSpacing(24, after: messageLabel)
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)

        NSLayoutConstraint.activate([
            card.centerXAnchor.constraint(equalTo: centerXAnchor),
            card.centerYAnchor.constraint(equalTo: centerYAnchor),
            card.widthAnchor.constraint(equalTo: widthAnchor, multiplier: 0.5),
            card.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -48),

            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 24),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -24),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -24),

            closeButton.heightAnchor.constraint(equalToConstant: 44)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        !card.frame.contains(touch.location(in: self))
    }

    @objc private func didTapBackdrop() {
        onDismiss?()
    }

    @objc private func didTapClose() {
        onDismiss?()
    }
}
