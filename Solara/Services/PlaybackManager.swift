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
    @Published private(set) var isRadarLoading = false
    @Published var errorMessage: String?
    @Published var isScrubbing = false

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
    private var wasPlayingBeforeScrub = false

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

    func enqueue(_ song: Song) {
        if !queue.contains(where: { $0.identity == song.identity }) {
            queue.append(song)
            persistState()
        }
    }

    func enqueue(_ songs: [Song]) {
        let deduped = songs.filter { song in !queue.contains(where: { $0.identity == song.identity }) }
        queue.append(contentsOf: deduped)
        persistState()
    }
    
    func clearQueue() {
        queue.removeAll()
        currentIndex = nil
        pause() // Stop playback if queue is cleared
        persistState()
    }

    func clearFavorites() {
        favorites.removeAll()
        persistState()
    }

    func startRadar() {
        guard !isRadarLoading else { return }
        isRadarLoading = true
        
        let settings = PersistenceManager.shared.loadSettings()
        let genres = Array(settings.radarGenres)
        // If genres empty (shouldn't happen due to default), fallback to "Pop"
        let keyword = genres.randomElement() ?? "Pop"
        
        Task {
            do {
                // Use search instead of fixed playlist to respect genres
                // Source: .netease (default usually best for general search) or random? 
                // Let's use .netease for consistency
                let songs = try await APIClient.shared.search(
                    keyword: keyword,
                    source: .netease,
                    limit: 50, // Fetch more to shuffle
                    page: 1
                )
                
                let shuffled = Array(songs.shuffled().prefix(20))
                
                await MainActor.run {
                    self.enqueue(shuffled)
                    self.isRadarLoading = false
                }
            } catch {
                print("Radar failed: \(error.localizedDescription)")
                await MainActor.run { self.isRadarLoading = false }
            }
        }
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
        case .off:
            if let current = currentIndex, current < queue.count - 1 {
                currentIndex = current + 1
            } else {
                // Stop playback if at end
                pause()
                return 
            }
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

    func playNext() {
        next()
    }

    func previous() {
        guard !queue.isEmpty else { return }
        switch playMode {
        case .off:
            if let current = currentIndex, current > 0 {
                currentIndex = current - 1
            }
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

    func playPrevious() {
        previous()
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
        let tolerance = CMTime(seconds: 0.1, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        player.seek(to: time, toleranceBefore: tolerance, toleranceAfter: tolerance)
        position = time.seconds
        updateNowPlayingInfo()
    }

    func beginScrubbing() {
        guard !isScrubbing else { return }
        wasPlayingBeforeScrub = isPlaying
        isScrubbing = true
    }

    func endScrubbing() {
        guard isScrubbing else { return }
        isScrubbing = false
        wasPlayingBeforeScrub = false
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

    func togglePlayMode() {
        switch playMode {
        case .list:
            setPlayMode(.single)
        case .single:
            setPlayMode(.shuffle)
        case .shuffle, .off:
            setPlayMode(.list)
        }
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
            // Strictly enforce playback category to ignore Silent Switch
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.allowBluetooth])
            try session.setActive(true)
        } catch {
            errorMessage = "Audio Session Error: \(error.localizedDescription)"
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
                if !self.isScrubbing {
                    self.position = time.seconds
                }
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
        case .list, .shuffle, .off:
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
        let currentIdentity = song.identity
        
        // 1. Artwork
        if let cached = artworkCache.object(forKey: currentIdentity as NSString) {
            if self.currentSong?.identity == currentIdentity {
                artwork = cached
            }
            artworkURL = try? await apiClient.resolveArtworkURL(for: song, size: 512)
        } else if let url = try? await apiClient.resolveArtworkURL(for: song, size: 512) {
            // Check race condition AGAIN before starting load
            if self.currentSong?.identity == currentIdentity {
                 artworkURL = url
            }
            await loadArtwork(from: url, identity: currentIdentity)
        } else {
             if self.currentSong?.identity == currentIdentity {
                artwork = nil
                artworkURL = nil
             }
        }

        // 2. Lyrics
        if let cachedLyrics = lyricCache[currentIdentity] {
             if self.currentSong?.identity == currentIdentity {
                lyrics = cachedLyrics
             }
        } else if let newLyrics = try? await apiClient.fetchLyrics(for: song) {
             lyricCache[currentIdentity] = newLyrics
             // Check race condition AGAIN after fetch
             if self.currentSong?.identity == currentIdentity {
                lyrics = newLyrics
             }
        } else {
             if self.currentSong?.identity == currentIdentity {
                lyrics = []
             }
        }

        if self.currentSong?.identity == currentIdentity {
            updateNowPlayingInfo()
        }
    }

    private func loadArtwork(from url: URL, identity: String) async {
        do {
            let image = try await imageLoader.loadImage(from: url)
            artworkCache.setObject(image, forKey: identity as NSString)
            // Final race check
            if self.currentSong?.identity == identity {
                artwork = image
                artworkURL = url
            }
        } catch {
            if self.currentSong?.identity == identity {
                artwork = nil
                artworkURL = nil
            }
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

    // ... (Existing methods)

    private func persistState() {
        let metadata = PersistenceManager.PlaybackMetadata(
            currentIdentity: currentSong?.identity,
            playMode: playMode,
            quality: quality,
            position: position,
            duration: duration
        )
        let pm = PersistenceManager.shared
        pm.saveQueue(queue)
        pm.saveFavorites(favorites)
        pm.savePlaybackMetadata(metadata)
    }

    private func loadPersistedState() async {
        let pm = PersistenceManager.shared
        let loadedQueue = pm.loadQueue()
        let loadedFavorites = pm.loadFavorites()
        let metadata = pm.loadPlaybackMetadata()
        
        await MainActor.run {
            self.queue = loadedQueue
            self.favorites = loadedFavorites
            if let meta = metadata {
                self.playMode = meta.playMode
                self.quality = meta.quality
                self.position = meta.position
                self.duration = meta.duration
                
                if let identity = meta.currentIdentity, 
                   let index = self.queue.firstIndex(where: { $0.identity == identity }) {
                    self.currentIndex = index
                    // Don't auto-start playback, just restore state
                    // self.play() // Uncomment if auto-play desired, but usually annoying
                }
            }
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
