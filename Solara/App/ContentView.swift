import SwiftUI

struct ContentView: View {
    @EnvironmentObject var playback: PlaybackManager
    @StateObject private var searchViewModel = SearchViewModel(apiClient: APIClient.shared)
    private let imageLoader = ImageLoader.shared

    @State private var showQueue = false
    @State private var showFavorites = false
    @State private var showSearch = false

    var body: some View {
        ZStack {
            // Dynamic Background
            if let url = playback.artworkURL {
                RemoteImageView(
                    url: url,
                    placeholderImage: playback.artwork,
                    imageLoader: imageLoader,
                    contentMode: .fill
                )
                .ignoresSafeArea()
                .blur(radius: 60)
                .overlay(Color.black.opacity(0.5))
            } else {
                Color(red: 0.11, green: 0.11, blue: 0.12)
                    .ignoresSafeArea()
            }

            VStack(spacing: 0) {
                // Top Bar
                ZStack {
                    // Title (Centered)
                    Text("SOLARA")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.8))
                        .textCase(.uppercase)
                        // Removed frame(maxWidth: .infinity) to prevent ZStack expansion issues
                    
                    // Buttons (Left & Right)
                    HStack {
                        Button(action: {
                            // Explore Radar Function
                            Task { playback.next() }
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "sparkles")
                                Text("探索")
                            }
                            .font(.subheadline.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.white.opacity(0.1))
                            .clipShape(Capsule())
                        }
                        
                        Spacer()
                        
                        Button(action: { showSearch.toggle() }) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 20))
                                .foregroundStyle(.white)
                                .padding(10)
                                .background(Color.white.opacity(0.1))
                                .clipShape(Circle())
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)

                Spacer()

                // Artwork
                let artworkSize = UIScreen.main.bounds.width - 48
                RemoteImageView(
                    url: playback.artworkURL,
                    placeholderImage: playback.artwork,
                    imageLoader: imageLoader
                )
                .frame(width: artworkSize, height: artworkSize)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.4), radius: 24, x: 0, y: 12)
                .scaleEffect(playback.isPlaying ? 1.0 : 0.82)
                .animation(.spring(response: 0.5, dampingFraction: 0.6), value: playback.isPlaying)
                .padding(.bottom, 32)
                
                // Track Info Row
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(playback.currentSong?.name ?? "Not Playing")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        
                        Text(playback.currentSong?.artist ?? "Solara Music")
                            .font(.title3)
                            .foregroundStyle(.white.opacity(0.7)) // Slightly lighter than secondary
                            .lineLimit(1)
                    }
                    
                    Spacer()
                    
                    HStack(spacing: 20) {
                        Button {
                             // More Action
                        } label: {
                             Image(systemName: "ellipsis.circle.fill") // Or just circle
                                 .font(.system(size: 24))
                                 .foregroundStyle(.white.opacity(0.4))
                        }

                        Button {
                             if let song = playback.currentSong {
                                playback.toggleFavorite(song)
                            }
                        } label: {
                            Image(systemName: isCurrentFavorite ? "star.fill" : "star")
                                .font(.system(size: 24))
                                .foregroundStyle(isCurrentFavorite ? .yellow : .white.opacity(0.4))
                                .symbolEffect(.bounce, value: isCurrentFavorite)
                        }
                    }
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 24)

                // Seek Bar with Quality Badge
                VStack(spacing: 12) {
                    Slider(
                        value: Binding(
                            get: { playback.duration == 0 ? 0 : playback.position / max(playback.duration, 0.1) },
                            set: { progress in playback.seek(to: progress) }
                        ),
                        in: 0...1
                    )
                    .tint(.white.opacity(0.5))
                    // .onAppear { ... customize slider appearance ... }
                    
                    HStack {
                        Text(TimeFormatting.string(from: playback.position))
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.5))
                            .monospacedDigit()
                        
                        
                        Spacer()
                        
                        // Quality Badge
                        Menu {
                            Picker("音质选择", selection: Binding(
                                get: { playback.quality },
                                set: { playback.setQuality($0) }
                            )) {
                                ForEach(SongQuality.allCases) { quality in
                                    Text(quality.label).tag(quality)
                                }
                            }
                        } label: {
                            HStack(spacing: 2) {
                                Image(systemName: "waveform")
                                Text(playback.quality.label.components(separatedBy: " ").first ?? "标准")
                            }
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.white.opacity(0.8))
                            .cornerRadius(4)
                        }
                        
                        Spacer()

                        Text(TimeFormatting.string(from: playback.duration))
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.5))
                            .monospacedDigit()
                    }
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 24)

                // Playback Controls
                HStack(spacing: 50) {
                    Button(action: playback.previous) {
                        Image(systemName: "backward.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(.white)
                    }
                    
                    Button(action: playback.togglePlayPause) {
                        Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 54)) // Fixed large size
                            .symbolRenderingMode(.hierarchical) 
                            .foregroundStyle(.white)
                            // Note: For a solid white filled circle background like Apple Music, 
                            // one might use a ZStack with Circle().fill(.white) if systemName isn't enough.
                            // But usually play.fill is solid enough.
                    }
                    
                    Button(action: playback.next) {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(.white)
                    }
                }
                .padding(.bottom, 32)
                
                // Volume Slider Section
                HStack(spacing: 12) {
                    Image(systemName: "speaker.fill")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                    
                    VolumeView()
                        .frame(height: 20) // MPVolumeView needs a frame, usually 20-40pt height
                        .tint(Color.white) // Fallback
                        
                    Image(systemName: "speaker.wave.3.fill")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 32)

                // Bottom Actions
                HStack(spacing: 50) {
                     Button(action: { showFavorites.toggle() }) {
                         Image(systemName: "heart.fill")
                             .font(.system(size: 24))
                             .foregroundStyle(showFavorites ? .pink : .white.opacity(0.6))
                             .symbolEffect(.bounce, value: showFavorites)
                     }

                     Button(action: { showLyrics.toggle() }) {
                         Image(systemName: "quote.bubble")
                             .font(.system(size: 24))
                             .foregroundStyle(showLyrics ? .white : .white.opacity(0.6))
                             .symbolEffect(.bounce, value: showLyrics)
                     }
                     
                     Button(action: { /* AirPlay */ }) {
                         Image(systemName: "airplayaudio")
                             .font(.system(size: 24))
                             .foregroundStyle(.white.opacity(0.6))
                     }
                     
                     Button(action: { showQueue.toggle() }) {
                         Image(systemName: "list.bullet")
                             .font(.system(size: 24))
                             .foregroundStyle(.white.opacity(0.6))
                     }
                }
                .padding(.bottom, 20)
            }
            .frame(width: UIScreen.main.bounds.width) // Strictly enforce screen width to prevent overflow bug
        }
        .sheet(isPresented: $showFavorites) {
            FavoritesSheet().environmentObject(playback)
        }
        .sheet(isPresented: $showQueue) {
            QueueSheet().environmentObject(playback)
        }
        .sheet(isPresented: $showSearch) {
            SearchSheet(viewModel: searchViewModel) { songs in
                playback.enqueue(songs)
            } onPlayNow: { songs in
                playback.playImmediately(songs)
            }
            .environmentObject(playback)
        }
        .sheet(isPresented: $showLyrics) {
            LyricsView().environmentObject(playback)
        }
    }

    @State private var showLyrics = false

    private var isCurrentFavorite: Bool {
        guard let song = playback.currentSong else { return false }
        return playback.favoriteSongs().contains(where: { $0.identity == song.identity })
    }
}

import MediaPlayer

struct VolumeView: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView {
        let volumeView = MPVolumeView(frame: .zero)
        volumeView.showsVolumeSlider = true
        // showsRouteButton is deprecated and we have a custom button, it's usually hidden by default if we restrict frame or use overlay
        // volumeView.showsRouteButton = false // Deprecated
        
        // Customize thumb
        let config = UIImage.SymbolConfiguration(pointSize: 12, weight: .bold)
        let thumb = UIImage(systemName: "circle.fill", withConfiguration: config)?.withTintColor(.white, renderingMode: .alwaysOriginal)
        volumeView.setVolumeThumbImage(thumb, for: .normal)
        return volumeView
    }

    func updateUIView(_ uiView: MPVolumeView, context: Context) {
        // Traverse subviews for styling if needed
        if let slider = uiView.subviews.first(where: { $0 is UISlider }) as? UISlider {
            slider.minimumTrackTintColor = .white
            slider.maximumTrackTintColor = UIColor.white.withAlphaComponent(0.2)
        }
    }
}

// MARK: - LyricsView (Moved here because new file not added to project)
struct LyricsView: View {
    @EnvironmentObject var playback: PlaybackManager
    @Environment(\.dismiss) var dismiss
    @State private var dragOffset: CGFloat = 0
    @State private var isUserScrolling = false
    @State private var userScrollTimeoutTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            // Background Blur
            if let artworkURL = playback.artworkURL {
                RemoteImageView(url: artworkURL, placeholderImage: playback.artwork, imageLoader: ImageLoader.shared, contentMode: .fill)
                    .ignoresSafeArea()
                    .blur(radius: 60)
                    .overlay(Color.black.opacity(0.6))
            } else {
                Color(red: 0.1, green: 0.1, blue: 0.1)
                    .ignoresSafeArea()
            }

            VStack(spacing: 0) {
                // Header
                HStack {
                    Spacer()
                    Capsule()
                        .fill(Color.white.opacity(0.2))
                        .frame(width: 40, height: 4)
                        .padding(.top, 8)
                    Spacer()
                }
                .frame(height: 20)
                
                if playback.lyrics.isEmpty {
                    ContentUnavailableView("暂无歌词", systemImage: "music.mic")
                        .foregroundStyle(.white.opacity(0.6))
                } else {
                    ScrollViewReader { proxy in
                        ScrollView(showsIndicators: false) {
                            VStack(alignment: .leading, spacing: 24) {
                                ForEach(playback.lyrics) { line in
                                    Text(line.text)
                                        .font(.system(size: isCurrentLine(line) ? 28 : 20, weight: isCurrentLine(line) ? .bold : .medium))
                                        .foregroundStyle(isCurrentLine(line) ? .white : .white.opacity(0.5))
                                        .blur(radius: isCurrentLine(line) ? 0 : 0.5)
                                        .scaleEffect(isCurrentLine(line) ? 1.05 : 1.0)
                                        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: isCurrentLine(line))
                                        .id(line.id)
                                        .onTapGesture {
                                            guard playback.duration > 0 else { return }
                                            playback.seek(to: line.time / playback.duration) 
                                        }
                                }
                            }
                            .padding(.vertical, UIScreen.main.bounds.height / 2.5) // Large padding for center focus
                            .padding(.horizontal, 32)
                        }
                        // Detect user scroll start (Simultaneous gesture not easy on ScrollView directly in SwiftUI, use DragGesture on overlay or simplified timeout)
                        .simultaneousGesture(
                            DragGesture()
                                .onChanged { _ in
                                    isUserScrolling = true
                                    userScrollTimeoutTask?.cancel()
                                }
                                .onEnded { _ in
                                    startResumeAutoScrollTimer()
                                }
                        )
                        .onChange(of: playback.position) { newTime in
                             guard !isUserScrolling else { return }
                             if let currentLine = currentLine(at: newTime) {
                                 withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                                     proxy.scrollTo(currentLine.id, anchor: .center)
                                 }
                             }
                        }
                    }
                }
            }
        }
    }

    private func isCurrentLine(_ line: LyricLine) -> Bool {
        guard let current = currentLine(at: playback.position) else { return false }
        return current.id == line.id
    }

    private func currentLine(at position: TimeInterval) -> LyricLine? {
        // Find the last line that has time <= current position
        return playback.lyrics.last { $0.time <= position }
    }
    
    private func startResumeAutoScrollTimer() {
        userScrollTimeoutTask?.cancel()
        userScrollTimeoutTask = Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds delay
            await MainActor.run {
                isUserScrolling = false
            }
        }
    }
}


