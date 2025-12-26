import AVFoundation
import MediaPlayer
import UIKit

@MainActor
final class PlaybackManager: ObservableObject {
    @Published private(set) var queue: [Song] = []
    @Published private(set) var favorites: [Song] = []
    @Published private(set) var playMode: PlayMode = .list
    @Published private(set) var quality: SongQuality = .extreme
    @Published private(set) var currentIndex: Int?
    @Published private(set) var isPlaying = false
    @Published private(set) var isBuffering = false
    @Published private(set) var position: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var lyrics: [LyricLine] = []
    @Published private(set) var artwork: UIImage?
    @Published private(set) var artworkURL: URL?
    @Published var errorMessage: String?

    var currentSong: Song? {
        guard let index = currentIndex, queue.indices.contains(index) else { return nil }
        return queue[index]
    }

    private let apiClient: APIClient
    private let imageLoader: ImageLoader
    private let player = AVPlayer()
    private let artworkCache = NSCache<NSString, UIImage>()
    private var lyricCache: [String: [LyricLine]] = [:]
    private var audioURLCache: [String: URL] = [:]
    private var timeObserver: Any?
    private var remoteCommandCenter: MPRemoteCommandCenter { .shared() }
    private let persistenceURL: URL

    init(apiClient: APIClient, imageLoader: ImageLoader = .shared) {
        self.apiClient = apiClient
        self.imageLoader = imageLoader
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        persistenceURL = support.appendingPathComponent("player_state.json")
        setupAudioSession()
        setupObservers()
        Task { await loadPersistedState() }
    }

    deinit {
        if let observer = timeObserver {
            player.removeTimeObserver(observer)
        }
        NotificationCenter.default.removeObserver(self)
    }

    func playImmediately(_ songs: [Song]) {
        queue = songs
        currentIndex = songs.isEmpty ? nil : 0
        Task { await startPlaybackFromCurrent() }
    }

    func enqueue(_ songs: [Song]) {
        let deduped = songs.filter { song in !queue.contains(where: { $0.identity == song.identity }) }
        queue.append(contentsOf: deduped)
        persistState()
    }

    func play(song: Song) {
        if let index = queue.firstIndex(where: { $0.identity == song.identity }) {
            currentIndex = index
        } else {
            queue.insert(song, at: min(queue.count, (currentIndex ?? 0) + 1))
            currentIndex = (currentIndex ?? -1) + 1
        }
        Task { await startPlaybackFromCurrent() }
    }

    func togglePlayPause() {
        guard player.currentItem != nil else {
            Task { await startPlaybackFromCurrent() }
            return
        }
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
        }
        updateNowPlayingInfo()
    }

    func pause() {
        player.pause()
        isPlaying = false
        updateNowPlayingInfo()
    }

    func next() {
        guard !queue.isEmpty else { return }
        switch playMode {
        case .list:
            let nextIndex = ((currentIndex ?? -1) + 1) % queue.count
            currentIndex = nextIndex
        case .single:
            break
        case .shuffle:
            currentIndex = Int.random(in: 0..<queue.count)
        }
        Task { await startPlaybackFromCurrent() }
    }

    func previous() {
        guard !queue.isEmpty else { return }
        switch playMode {
        case .list:
            let previousIndex = ((currentIndex ?? 0) - 1 + queue.count) % queue.count
            currentIndex = previousIndex
        case .single:
            break
        case .shuffle:
            currentIndex = Int.random(in: 0..<queue.count)
        }
        Task { await startPlaybackFromCurrent() }
    }

    func removeSong(at offsets: IndexSet) {
        queue.remove(atOffsets: offsets)
        if let currentIndex, offsets.contains(currentIndex) {
            self.currentIndex = queue.isEmpty ? nil : 0
            Task { await startPlaybackFromCurrent() }
        }
        persistState()
    }

    func moveSong(from source: IndexSet, to destination: Int) {
        queue.move(fromOffsets: source, toOffset: destination)
        if let index = currentIndex {
            self.currentIndex = min(index, queue.count - 1)
        }
        persistState()
    }

    func seek(to progress: Double) {
        guard duration > 0 else { return }
        let time = CMTime(seconds: progress * duration, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        player.seek(to: time)
    }

    func setQuality(_ value: SongQuality) {
        quality = value
        if currentSong != nil {
            Task { await startPlaybackFromCurrent() }
        }
        persistState()
    }

    func setPlayMode(_ mode: PlayMode) {
        playMode = mode
        persistState()
    }

    func toggleFavorite(_ song: Song) {
        if favorites.contains(where: { $0.identity == song.identity }) {
            favorites.removeAll { $0.identity == song.identity }
        } else {
            favorites.insert(song, at: 0)
        }
        persistState()
    }

    func favoriteSongs() -> [Song] { favorites }

    private func setupAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, policy: .longFormAudio, options: [.allowBluetooth, .mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            errorMessage = error.localizedDescription
        }
        configureRemoteCommands()
    }

    private func configureRemoteCommands() {
        remoteCommandCenter.playCommand.addTarget { [weak self] _ in
            Task { await self?.resumeFromRemote() }
            return .success
        }
        remoteCommandCenter.pauseCommand.addTarget { [weak self] _ in
            self?.pause()
            return .success
        }
        remoteCommandCenter.nextTrackCommand.addTarget { [weak self] _ in
            self?.next()
            return .success
        }
        remoteCommandCenter.previousTrackCommand.addTarget { [weak self] _ in
            self?.previous()
            return .success
        }
        remoteCommandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            Task { await self?.seekFromRemote(to: event.positionTime) }
            return .success
        }
    }

    private func setupObservers() {
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.4, preferredTimescale: CMTimeScale(NSEC_PER_SEC)), queue: .main) { [weak self] time in
            guard let self else { return }
            Task { @MainActor in
                self.position = time.seconds
                if let duration = self.player.currentItem?.duration.seconds, duration.isFinite {
                    self.duration = duration
                }
                self.updateNowPlayingInfo(playbackRate: self.player.rate)
            }
        }

        NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.handleItemFinished()
            }
        }
    }

    private func handleItemFinished() {
        switch playMode {
        case .single:
            Task { await startPlaybackFromCurrent() }
        case .list, .shuffle:
            next()
        }
    }

    private func startPlaybackFromCurrent() async {
        guard let song = currentSong else { return }
        isBuffering = true
        errorMessage = nil

        do {
            let audioURL: URL
            if let cached = audioURLCache[song.identity] {
                audioURL = cached
            } else {
                let audio = try await apiClient.resolveSongURL(for: song, quality: quality)
                audioURL = audio.url
                audioURLCache[song.identity] = audioURL
            }
            let item = AVPlayerItem(url: audioURL)
            player.replaceCurrentItem(with: item)
            player.play()
            isPlaying = true
            isBuffering = false
            await loadMetadata(for: song)
            persistState()
        } catch {
            errorMessage = error.localizedDescription
            isPlaying = false
            isBuffering = false
        }
    }

    private func loadMetadata(for song: Song) async {
        if let cached = artworkCache.object(forKey: song.identity as NSString) {
            artwork = cached
            artworkURL = nil
        } else if let url = try? await apiClient.resolveArtworkURL(for: song, size: 512) {
            artworkURL = url
            await loadArtwork(from: url, identity: song.identity)
        } else {
            artwork = nil
            artworkURL = nil
        }

        if let cachedLyrics = lyricCache[song.identity] {
            lyrics = cachedLyrics
        } else if let newLyrics = try? await apiClient.fetchLyrics(for: song) {
            lyricCache[song.identity] = newLyrics
            lyrics = newLyrics
        } else {
            lyrics = []
        }

        updateNowPlayingInfo()
    }

    private func loadArtwork(from url: URL, identity: String) async {
        do {
            let image = try await imageLoader.loadImage(from: url)
            artworkCache.setObject(image, forKey: identity as NSString)
            artwork = image
            artworkURL = url
        } catch {
            artwork = nil
            artworkURL = nil
        }
    }

    private func updateNowPlayingInfo(playbackRate: Float? = nil) {
        guard let song = currentSong else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: song.name,
            MPMediaItemPropertyArtist: song.artist,
            MPNowPlayingInfoPropertyPlaybackRate: playbackRate ?? player.rate,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: position,
            MPMediaItemPropertyPlaybackDuration: duration
        ]
        if let album = song.album { info[MPMediaItemPropertyAlbumTitle] = album }
        if let artwork = artwork {
            let itemArtwork = MPMediaItemArtwork(boundsSize: artwork.size) { _ in artwork }
            info[MPMediaItemPropertyArtwork] = itemArtwork
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func persistState() {
        let snapshot = PlaybackSnapshot(
            queue: queue,
            favorites: favorites,
            currentIdentity: currentSong?.identity,
            quality: quality,
            playMode: playMode,
            position: position,
            duration: duration,
            artwork: nil
        )
        do {
            let data = try JSONEncoder().encode(snapshot)
            try FileManager.default.createDirectory(at: persistenceURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: persistenceURL, options: .atomic)
        } catch {
            // Ignore persistence errors in production use.
        }
    }

    private func loadPersistedState() async {
        guard let data = try? Data(contentsOf: persistenceURL) else { return }
        do {
            let snapshot = try JSONDecoder().decode(PlaybackSnapshot.self, from: data)
            queue = snapshot.queue
            favorites = snapshot.favorites
            quality = snapshot.quality
            playMode = snapshot.playMode
            position = snapshot.position
            duration = snapshot.duration
            if let identity = snapshot.currentIdentity, let index = queue.firstIndex(where: { $0.identity == identity }) {
                currentIndex = index
                await startPlaybackFromCurrent()
            }
        } catch {
            // ignore corrupted state
        }
    }

    private func resumeFromRemote() async {
        if player.currentItem == nil {
            await startPlaybackFromCurrent()
        } else {
            player.play()
            isPlaying = true
            updateNowPlayingInfo()
        }
    }

    private func seekFromRemote(to time: TimeInterval) async {
        let cmTime = CMTime(seconds: time, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        await player.seek(to: cmTime)
        position = time
        updateNowPlayingInfo()
    }
}
