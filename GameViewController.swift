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

        NSLayoutConstraint.activate([
            skView.topAnchor.constraint(equalTo: view.topAnchor),
            skView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            skView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            skView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func presentGameSceneIfNeeded() {
        guard !hasPresentedScene else { return }
        let size = skView.bounds.size
        guard size.width > 0, size.height > 0 else { return }

        hasPresentedScene = true
        startNewGame(size: size)
    }

    private func startNewGame(size: CGSize) {
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
        skView.presentScene(scene)
    }

    private func setControlsHidden(_ hidden: Bool) {
        laneStack.isHidden = hidden
        actionButton.isHidden = hidden
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
