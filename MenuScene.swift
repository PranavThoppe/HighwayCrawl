//
//  MenuScene.swift
//  HighwayCrawl
//

import SpriteKit

/// The main menu. Its looping video background is drawn by `LoopingVideoView` above the `SKView`.
final class MenuScene: SKScene {

    var onPlay: (() -> Void)?

    override func didMove(to view: SKView) {
        backgroundColor = .black
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let onPlay else { return }
        self.onPlay = nil
        onPlay()
    }
}
