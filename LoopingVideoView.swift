//
//  LoopingVideoView.swift
//  HighwayCrawl
//

import UIKit
import AVFoundation

/// Plays a bundled video on a muted loop, aspect-filling its bounds.
///
/// Uses two staggered `AVPlayerLooper` instances composited in separate layers. When one
/// layer briefly has no frame at the loop seam, the other (offset by half a cycle) still
/// shows video so the black flash from a single `AVPlayerLayer` does not appear.
final class LoopingVideoView: UIView {

    private let backPlayerLayer = AVPlayerLayer()
    private let frontPlayerLayer = AVPlayerLayer()

    private var frontLooper: AVPlayerLooper?
    private var backLooper: AVPlayerLooper?

    var isPlaying: Bool { frontLooper != nil }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        isUserInteractionEnabled = true
        for layer in [backPlayerLayer, frontPlayerLayer] {
            layer.videoGravity = .resizeAspectFill
        }
        self.layer.addSublayer(backPlayerLayer)
        self.layer.addSublayer(frontPlayerLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        backPlayerLayer.frame = bounds
        frontPlayerLayer.frame = bounds
    }

    /// Buttons and popups keep their touches; empty video area falls through to `MenuScene`.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        return hit === self ? nil : hit
    }

    func play(resource: String, withExtension ext: String) {
        guard frontLooper == nil else { return }
        guard let url = Bundle.main.url(forResource: resource, withExtension: ext) else {
            assertionFailure("\(resource).\(ext) missing from bundle")
            return
        }

        let itemA = makeLoopItem(url: url)
        let itemB = makeLoopItem(url: url)

        let (playerA, looperA) = makeLooperPlayer(templateItem: itemA)
        let (playerB, looperB) = makeLooperPlayer(templateItem: itemB)

        frontPlayerLayer.player = playerA
        backPlayerLayer.player = playerB
        frontLooper = looperA
        backLooper = looperB

        alpha = 1
        isHidden = false

        startStaggeredPlayback(primary: playerA, secondary: playerB, asset: itemA.asset)
    }

    func stop() {
        frontLooper?.disableLooping()
        backLooper?.disableLooping()
        frontPlayerLayer.player?.pause()
        backPlayerLayer.player?.pause()
        frontPlayerLayer.player = nil
        backPlayerLayer.player = nil
        frontLooper = nil
        backLooper = nil
        isHidden = true
    }

    private func makeLoopItem(url: URL) -> AVPlayerItem {
        let asset = AVURLAsset(
            url: url,
            options: [AVURLAssetPreferPreciseDurationAndTimingKey: true]
        )
        let item = AVPlayerItem(asset: asset)
        item.preferredForwardBufferDuration = 3
        return item
    }

    private func makeLooperPlayer(templateItem: AVPlayerItem) -> (AVQueuePlayer, AVPlayerLooper) {
        let player = AVQueuePlayer()
        player.isMuted = true
        player.preventsDisplaySleepDuringVideoPlayback = false
        player.automaticallyWaitsToMinimizeStalling = false
        let looper = AVPlayerLooper(player: player, templateItem: templateItem)
        return (player, looper)
    }

    private func startStaggeredPlayback(primary: AVQueuePlayer, secondary: AVQueuePlayer, asset: AVAsset) {
        let durationKey = "duration"
        asset.loadValuesAsynchronously(forKeys: [durationKey]) { [weak self] in
            DispatchQueue.main.async {
                guard let self, self.isPlaying else { return }

                var error: NSError?
                let status = asset.statusOfValue(forKey: durationKey, error: &error)
                guard status == .loaded else {
                    primary.play()
                    secondary.play()
                    return
                }

                let duration = asset.duration
                let half = CMTimeMultiplyByFloat64(duration, multiplier: 0.5)
                guard half.isNumeric, half.seconds.isFinite, half.seconds > 0.05 else {
                    primary.play()
                    secondary.play()
                    return
                }

                primary.play()
                secondary.seek(to: half, toleranceBefore: .zero, toleranceAfter: .zero) { finished in
                    guard finished else { return }
                    secondary.play()
                }
            }
        }
    }
}
