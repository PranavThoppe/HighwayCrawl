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

    private let laneLeftButton = UIButton(type: .system)
    private let laneRightButton = UIButton(type: .system)
    private let actionButton = UIButton(type: .system)

    override func viewDidLoad() {
        super.viewDidLoad()
        
        if let view = self.view as! SKView? {
            // Load the SKScene from 'GameScene.sks'
            if let scene = SKScene(fileNamed: "GameScene") {
                // Set the scale mode to scale to fit the window
                scene.scaleMode = .aspectFill
                
                // Present the scene
                view.presentScene(scene)
            }
            
            view.ignoresSiblingOrder = true
            
            view.showsFPS = true
            view.showsNodeCount = true
        }

        setupControlButtons()
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

    private func setupControlButtons() {
        configure(laneLeftButton, accessibilityLabel: "Left", systemImage: "chevron.left")
        configure(laneRightButton, accessibilityLabel: "Right", systemImage: "chevron.right")
        configure(actionButton, accessibilityLabel: "Action", systemImage: "circle.fill")

        laneLeftButton.addTarget(self, action: #selector(didTapLaneLeft), for: .touchUpInside)
        laneRightButton.addTarget(self, action: #selector(didTapLaneRight), for: .touchUpInside)
        actionButton.addTarget(self, action: #selector(didTapAction), for: .touchUpInside)

        let laneStack = UIStackView(arrangedSubviews: [laneLeftButton, laneRightButton])
        laneStack.axis = .horizontal
        laneStack.spacing = 12
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
        config.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 28, weight: .semibold)

        button.configuration = config
        button.backgroundColor = .clear
        button.accessibilityLabel = accessibilityLabel
    }

    @objc private func didTapLaneLeft() {
        // Lane-change left will be wired up later.
    }

    @objc private func didTapLaneRight() {
        // Lane-change right will be wired up later.
    }

    @objc private func didTapAction() {
        // Action button will be wired up later.
    }
}
