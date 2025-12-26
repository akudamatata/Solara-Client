import SwiftUI
import UIKit
import AVKit

struct ContentView: View {
    @EnvironmentObject var playback: PlaybackManager
    @StateObject private var searchViewModel = SearchViewModel(apiClient: APIClient.shared)
    private let imageLoader = ImageLoader.shared
    @Namespace private var animation // Animation Namespace for transitions

    @State private var showQueue = false
    @State private var showFavorites = false
    @State private var showSearch = false
    @State private var showLyrics = false

    var body: some View {
        ZStack {
            // Background
            PlayerBackgroundView(playback: playback, imageLoader: imageLoader)

            VStack(spacing: 0) {
                if showLyrics {
                    // MARK: - LYRICS MODE
                    LyricsModeView(
                        showLyrics: $showLyrics,
                        animation: animation,
                        imageLoader: imageLoader
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(1)
                    .environmentObject(playback)
                } else {
                    // MARK: - STANDARD MODE
                    StandardPlayerView(
                        showSearch: $showSearch,
                        animation: animation,
                        imageLoader: imageLoader
                    )
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(0)
                    .environmentObject(playback)
                }

                // MARK: - SHARED CONTROLS
                PlayerControlsView(
                    showQueue: $showQueue,
                    showFavorites: $showFavorites,
                    showLyrics: $showLyrics
                )
                .environmentObject(playback)
            }
            .frame(width: UIScreen.main.bounds.width)
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
        // Removed separate Lyrics sheet
    }
}

// MARK: - Subviews

struct PlayerBackgroundView: View {
    @ObservedObject var playback: PlaybackManager
    let imageLoader: ImageLoader

    var body: some View {
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
    }
}

struct LyricsModeView: View {
    @EnvironmentObject var playback: PlaybackManager
    @Binding var showLyrics: Bool
    var animation: Namespace.ID
    let imageLoader: ImageLoader
    
    // Derived property for favorite status to keep view simple
    private var isCurrentFavorite: Bool {
        guard let song = playback.currentSong else { return false }
        return playback.favoriteSongs().contains(where: { $0.identity == song.identity })
    }

    var body: some View {
        VStack(spacing: 0) {
            // 1. Header Section
            HStack(spacing: 12) {
                // Small Artwork
                if let artworkURL = playback.artworkURL {
                     RemoteImageView(url: artworkURL, placeholderImage: playback.artwork, imageLoader: imageLoader, contentMode: .fill)
                        .matchedGeometryEffect(id: "artwork", in: animation)
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .shadow(radius: 8)
                } else {
                    Image(systemName: "music.note")
                        .matchedGeometryEffect(id: "artwork", in: animation)
                        .frame(width: 56, height: 56)
                        .background(Color.white.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                
                // Info
                VStack(alignment: .leading, spacing: 2) {
                    Text(playback.currentSong?.name ?? "未知歌曲")
                        .font(.title3.bold())
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .matchedGeometryEffect(id: "title", in: animation)
                    
                    Text(playback.currentSong?.artist ?? "未知艺术家")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                        .matchedGeometryEffect(id: "artist", in: animation)
                }
                
                Spacer()
                
                // Actions
                HStack(spacing: 20) {
                    Button {
                         if let song = playback.currentSong {
                            playback.toggleFavorite(song)
                        }
                    } label: {
                        Image(systemName: isCurrentFavorite ? "heart.fill" : "heart")
                            .font(.system(size: 20))
                            .foregroundStyle(isCurrentFavorite ? .red : .white.opacity(0.4))
                            .symbolEffect(.bounce, value: isCurrentFavorite)
                    }
                    
                    Button {
                        // More
                    } label: {
                        Image(systemName: "ellipsis.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 48)
            .padding(.bottom, 20)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.spring(response: 0.4, dampingFraction: 1.0)) {
                    showLyrics = false
                }
            }
            
            // 2. Lyrics List
            LyricsScrollView().environmentObject(playback)
        }
    }
}

struct StandardPlayerView: View {
    @EnvironmentObject var playback: PlaybackManager
    @Binding var showSearch: Bool
    var animation: Namespace.ID
    let imageLoader: ImageLoader
    
    private var isCurrentFavorite: Bool {
        guard let song = playback.currentSong else { return false }
        return playback.favoriteSongs().contains(where: { $0.identity == song.identity })
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top Bar
            ZStack {
                Text("SOLARA")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.8))
                    .textCase(.uppercase)
                
                HStack {
                    Button(action: { playback.startRadar() }) {
                        HStack(spacing: 4) {
                            ForEach(playback.favorites) { song in
                            SongRow(
                                song: song,
                                isCurrent: playback.currentSong?.identity == song.identity,
                                artworkOverrideURL: (playback.currentSong?.identity == song.identity) ? playback.artworkURL : nil,
                                onAddToQueue: {
                                    playback.enqueue(song)
                                }
                            ) {
                                playback.play(song: song)
                            }
                            Text(playback.isRadarLoading ? "加载中" : "探索")
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
            
            // Large Artwork
            let artworkSize = UIScreen.main.bounds.width - 48
            RemoteImageView(
                url: playback.artworkURL,
                placeholderImage: playback.artwork,
                imageLoader: imageLoader
            )
            .matchedGeometryEffect(id: "artwork", in: animation)
            .frame(width: artworkSize, height: artworkSize)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.4), radius: 24, x: 0, y: 12)
            .padding(.bottom, 32)
            
            // Track Info
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(playback.currentSong?.name ?? "Not Playing")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .matchedGeometryEffect(id: "title", in: animation)
                    
                    Text(playback.currentSong?.artist ?? "Solara Music")
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                        .matchedGeometryEffect(id: "artist", in: animation)
                }
                
                Spacer()
                
                HStack(spacing: 20) {
                    Button {} label: {
                         Image(systemName: "ellipsis.circle.fill")
                             .font(.system(size: 24))
                             .foregroundStyle(.white.opacity(0.4))
                    }
                    Button {
                         if let song = playback.currentSong {
                            playback.toggleFavorite(song)
                        }
                    } label: {
                        Image(systemName: isCurrentFavorite ? "heart.fill" : "heart")
                            .font(.system(size: 24))
                            .foregroundStyle(isCurrentFavorite ? .red : .white.opacity(0.4))
                            .symbolEffect(.bounce, value: isCurrentFavorite)
                    }
                }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 24)
        }
    }
}

struct PlayerControlsView: View {
    @EnvironmentObject var playback: PlaybackManager
    @Binding var showQueue: Bool
    @Binding var showFavorites: Bool
    @Binding var showLyrics: Bool

    var body: some View {
        VStack(spacing: 0) {
            SeekBarView(playback: playback)
            TransportControlsView(playback: playback)
            VolumeControlView()
            BottomActionsView(
                showQueue: $showQueue,
                showFavorites: $showFavorites,
                showLyrics: $showLyrics
            )
        }
    }
}

struct SeekBarView: View {
    @ObservedObject var playback: PlaybackManager

    var body: some View {
        VStack(spacing: 12) {
            Slider(
                value: Binding(
                    get: { playback.duration == 0 ? 0 : playback.position / max(playback.duration, 0.1) },
                    set: { progress in playback.seek(to: progress) }
                ),
                in: 0...1
            )
            .tint(.white.opacity(0.5))
            
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
    }
}

struct TransportControlsView: View {
    @ObservedObject var playback: PlaybackManager

    var body: some View {
        HStack(spacing: 40) {
            // Shuffle
            Button(action: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    if playback.playMode == .shuffle {
                        playback.setPlayMode(.list)
                    } else {
                        playback.setPlayMode(.shuffle)
                    }
                }
            }) {
                Image(systemName: "shuffle")
                    .font(.system(size: 20)) // Reduced from 22
                    .foregroundStyle(playback.playMode == .shuffle ? .white : .white.opacity(0.4))
                    .symbolEffect(.bounce, value: playback.playMode == .shuffle)
                    .frame(height: 20) // Ensure vertical alignment
            }

            Button(action: playback.previous) {
                Image(systemName: "backward.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.white)
            }
            
            Button(action: playback.togglePlayPause) {
                Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 54))
                    .symbolRenderingMode(.hierarchical) 
                    .foregroundStyle(.white)
            }
            
            Button(action: playback.next) {
                Image(systemName: "forward.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.white)
            }

            // Repeat
            Button(action: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    switch playback.playMode {
                    case .off: playback.setPlayMode(.list)
                    case .list: playback.setPlayMode(.single)
                    case .single: playback.setPlayMode(.off)
                    case .shuffle: playback.setPlayMode(.single)
                    }
                }
            }) {
                Image(systemName: playback.playMode == .single ? "repeat.1" : "repeat")
                    .font(.system(size: 20)) // Reduced from 22
                    .foregroundStyle(playback.playMode == .off || playback.playMode == .shuffle ? .white.opacity(0.4) : .white)
                    .symbolEffect(.bounce, value: playback.playMode)
                    .frame(height: 20) // Ensure vertical alignment
            }
        }
        .padding(.bottom, 32)
    }
}

struct VolumeControlView: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "speaker.fill")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.5))
            
            VolumeView()
                .frame(height: 20)
                .tint(Color.white)
                
            Image(systemName: "speaker.wave.3.fill")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.5))
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 32)
    }
}

struct BottomActionsView: View {
    @Binding var showQueue: Bool
    @Binding var showFavorites: Bool
    @Binding var showLyrics: Bool

    var body: some View {
        HStack(spacing: 40) { 
             Button(action: { 
                 withAnimation(.spring(response: 0.4, dampingFraction: 1.0)) {
                     showLyrics.toggle() 
                 }
             }) {
                 Image(systemName: "quote.bubble.fill")
                     .font(.system(size: 24))
                     .foregroundStyle(showLyrics ? .white : .white.opacity(0.4))
                     .background(
                         Group {
                             SongRow(song: current, isCurrent: true, artworkOverrideURL: playback.artworkURL) {
                                // Already playing
                            }         .fill(Color.white.opacity(0.2))
                                     .blur(radius: 6)
                                     .frame(width: 40, height: 40)
                             }
                         }
                     )
                     .symbolEffect(.bounce, value: showLyrics)
             }

             Button(action: { showFavorites.toggle() }) {
                 Image(systemName: "heart.fill")
                     .font(.system(size: 24))
                     .foregroundStyle(showFavorites ? .pink : .white.opacity(0.4)) 
                     .symbolEffect(.bounce, value: showFavorites)
             }
             
             AirPlayView()
                 .frame(width: 30, height: 30) // Smaller than buttons (usually 44)

             Button(action: { showQueue.toggle() }) {
                 Image(systemName: "list.bullet")
                     .font(.system(size: 24))
                     .foregroundStyle(.white.opacity(0.6))
             }
        }
        .padding(.bottom, 20)
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

// MARK: - Lyrics Scroll Component
struct LyricsScrollView: View {
    @EnvironmentObject var playback: PlaybackManager
    @State private var isUserScrolling = false
    @State private var userScrollTimeoutTask: Task<Void, Never>?

    var body: some View {
        if playback.lyrics.isEmpty {
            ContentUnavailableView("暂无歌词", systemImage: "music.mic")
                .foregroundStyle(.white.opacity(0.6))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 30) {
                        ForEach(playback.lyrics) { line in
                            Text(line.text)
                                .font(.system(size: isCurrentLine(line) ? 32 : 24, weight: isCurrentLine(line) ? .bold : .semibold))
                                .foregroundStyle(isCurrentLine(line) ? .white : .white.opacity(0.4))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .blur(radius: isCurrentLine(line) ? 0 : 0.8)
                                .scaleEffect(isCurrentLine(line) ? 1.05 : 1.0)
                                .animation(.spring(response: 0.4, dampingFraction: 0.7), value: isCurrentLine(line))
                                .id(line.id)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    guard playback.duration > 0 else { return }
                                    playback.seek(to: line.time / playback.duration) 
                                }
                        }
                    }
                    .padding(.vertical, UIScreen.main.bounds.height / 3)
                    .padding(.horizontal, 32)
                }
                .scrollDisabled(false)
                .simultaneousGesture(
                    DragGesture().onChanged { _ in
                        isUserScrolling = true
                        userScrollTimeoutTask?.cancel()
                    }.onEnded { _ in startResumeAutoScrollTimer() }
                )
                .onChange(of: playback.position) { _, newTime in
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

    private func isCurrentLine(_ line: LyricLine) -> Bool {
        guard let current = currentLine(at: playback.position) else { return false }
        return current.id == line.id
    }

    private func currentLine(at position: TimeInterval) -> LyricLine? {
        return playback.lyrics.last { $0.time <= position }
    }
    
    private func startResumeAutoScrollTimer() {
        userScrollTimeoutTask?.cancel()
        userScrollTimeoutTask = Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await MainActor.run { isUserScrolling = false }
        }
    }
}


struct AirPlayView: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let routePickerView = AVRoutePickerView()
        routePickerView.activeTintColor = .white
        routePickerView.tintColor = .white.withAlphaComponent(0.6)
        routePickerView.prioritizesVideoDevices = false // Audio only preference
        return routePickerView
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {
        // No updates needed typically
    }
}
