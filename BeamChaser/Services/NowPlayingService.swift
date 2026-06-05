import Foundation
import MediaPlayer
import UIKit

@MainActor
final class NowPlayingService: ObservableObject {
    @Published var artworkImage: UIImage?
    @Published var title: String = ""
    @Published var artist: String = ""
    @Published var albumTitle: String = ""
    @Published var isPlaying: Bool = false

    private let player = MPMusicPlayerController.systemMusicPlayer
    private let infoCenter = MPNowPlayingInfoCenter.default()
    private var notificationTokens: [NSObjectProtocol] = []
    private var isActivated = false

    init() {}

    /// Call this once the user has already granted media permission (e.g. from .onAppear).
    func activate() {
        guard !isActivated else { return }
        isActivated = true
        player.beginGeneratingPlaybackNotifications()
        observePlayer()
        refreshNowPlaying()
    }

    deinit {
        notificationTokens.forEach(NotificationCenter.default.removeObserver)
        player.endGeneratingPlaybackNotifications()
    }

    var hasNowPlaying: Bool {
        artworkImage != nil || !title.isEmpty || !artist.isEmpty || !albumTitle.isEmpty
    }

    func refreshNowPlaying() {
        guard isActivated else { return }

        let item = player.nowPlayingItem
        let info = infoCenter.nowPlayingInfo ?? [:]

        title = resolvedText(primary: item?.title, from: info[MPMediaItemPropertyTitle])
        artist = resolvedText(primary: item?.artist, from: info[MPMediaItemPropertyArtist])
        albumTitle = resolvedText(primary: item?.albumTitle, from: info[MPMediaItemPropertyAlbumTitle])
        artworkImage = resolvedArtwork(item: item, info: info)
        isPlaying = player.playbackState == .playing
    }

    func togglePlayback() {
        guard isActivated else { return }
        if player.playbackState == .playing {
            player.pause()
        } else {
            player.play()
        }
        scheduleRefresh()
    }

    func skipToNextTrack() {
        guard isActivated else { return }
        player.skipToNextItem()
        scheduleRefresh()
    }

    func skipToPreviousTrack() {
        guard isActivated else { return }
        player.skipToPreviousItem()
        scheduleRefresh()
    }

    private func scheduleRefresh() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.refreshNowPlaying()
        }
    }

    private func observePlayer() {
        let center = NotificationCenter.default
        let names: [Notification.Name] = [
            .MPMusicPlayerControllerNowPlayingItemDidChange,
            .MPMusicPlayerControllerPlaybackStateDidChange,
            UIApplication.willEnterForegroundNotification
        ]

        notificationTokens = names.map { name in
            center.addObserver(forName: name, object: player, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.refreshNowPlaying()
                }
            }
        }
    }

    private func resolvedText(primary: String?, from fallbackValue: Any?) -> String {
        if let primary, !primary.isEmpty {
            return primary
        }

        if let fallback = fallbackValue as? String {
            return fallback
        }

        return ""
    }

    private func resolvedArtwork(item: MPMediaItem?, info: [String: Any]) -> UIImage? {
        if let itemArtwork = item?.artwork?.image(at: CGSize(width: 900, height: 900)) {
            return itemArtwork
        }

        if let fallbackArtwork = info[MPMediaItemPropertyArtwork] as? MPMediaItemArtwork {
            return fallbackArtwork.image(at: CGSize(width: 900, height: 900))
        }

        return nil
    }
}
