//
//  LoopingVideoView.swift
//  HighwayCrawl
//

import UIKit
import AVFoundation

/// Plays a bundled video on a gapless, muted loop, aspect-filling its bounds.
final class LoopingVideoView: UIView {

    override class var layerClass: AnyClass { AVPlayerLayer.self }

    private var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    private var looper: AVPlayerLooper?

    var isPlaying: Bool { looper != nil }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        isUserInteractionEnabled = false
        playerLayer.videoGravity = .resizeAspectFill
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func play(resource: String, withExtension ext: String) {
        guard looper == nil else { return }
        guard let url = Bundle.main.url(forResource: resource, withExtension: ext) else {
            assertionFailure("\(resource).\(ext) missing from bundle")
            return
        }
        let player = AVQueuePlayer()
        player.isMuted = true
        player.preventsDisplaySleepDuringVideoPlayback = false
        looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
        playerLayer.player = player
        alpha = 1
        isHidden = false
        player.play()
    }

    func stop() {
        looper?.disableLooping()
        playerLayer.player?.pause()
        playerLayer.player = nil
        looper = nil
        isHidden = true
    }
}
