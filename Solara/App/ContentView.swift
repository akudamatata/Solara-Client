import SwiftUI
import UIKit
import AVKit
import AVFoundation

struct ContentView: View {
    @EnvironmentObject var playback: PlaybackManager
    @StateObject private var searchViewModel = SearchViewModel(apiClient: APIClient.shared)
    private let imageLoader = ImageLoader.shared
    @Namespace private var animation // Animation Namespace for transitions

    @State private var showQueue = false
    @State private var showFavorites = false
    @State private var showSearch = false
    @State private var showLyrics = false
    @State private var showSettings = false

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                // Background
                PlayerBackgroundView(playback: playback, imageLoader: imageLoader)
                    .frame(width: proxy.size.width, height: proxy.size.height)

                VStack(spacing: 0) {
                    if showLyrics {
                        // MARK: - LYRICS MODE
                        LyricsModeView(
                            showLyrics: $showLyrics,
                            animation: animation,
                            imageLoader: imageLoader,
                            availableSize: proxy.size
                        )
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .zIndex(1)
                        .environmentObject(playback)
                    } else {
                        // MARK: - STANDARD MODE
                        StandardPlayerView(
                            showSearch: $showSearch,
                            showSettings: $showSettings,
                            animation: animation,
                            imageLoader: imageLoader,
                            availableWidth: proxy.size.width
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
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
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
                playback.enqueue(songs)
                playback.play(song: songs[0])
            }
            .environmentObject(playback)
        }
        .sheet(isPresented: $showSettings) {
            SettingsSheet().environmentObject(playback)
        }
    }
}

// MARK: - Subviews

struct PlayerBackgroundView: View {
    @ObservedObject var playback: PlaybackManager
    let imageLoader: ImageLoader

    var body: some View {
        GeometryReader { proxy in
            let insets = proxy.safeAreaInsets
            let extendedWidth = proxy.size.width + insets.leading + insets.trailing
            let extendedHeight = proxy.size.height + insets.top + insets.bottom

            if let url = playback.artworkURL {
                RemoteImageView(
                    url: url,
                    placeholderImage: playback.artwork,
                    imageLoader: imageLoader,
                    contentMode: .fill
                )
                .frame(width: extendedWidth, height: extendedHeight)
                .offset(x: -insets.leading, y: -insets.top)
                .blur(radius: 60)
                .overlay(Color.black.opacity(0.5))
                .ignoresSafeArea()
            } else {
                Color(red: 0.11, green: 0.11, blue: 0.12)
                    .ignoresSafeArea()
            }
        }
    }
}

struct LyricsModeView: View {
    @EnvironmentObject var playback: PlaybackManager
    @Binding var showLyrics: Bool
    var animation: Namespace.ID
    let imageLoader: ImageLoader
    let availableSize: CGSize
    
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
            LyricsScrollView(availableHeight: availableSize.height)
                .environmentObject(playback)
        }
        .frame(maxWidth: .infinity)
    }
}

struct StandardPlayerView: View {
    @EnvironmentObject var playback: PlaybackManager
    @Binding var showSearch: Bool
    @Binding var showSettings: Bool // Pass binding to trigger from subviews if needed, though gesture is localized
    var animation: Namespace.ID
    let imageLoader: ImageLoader
    let availableWidth: CGFloat
    
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
                    .contentShape(Rectangle()) // Make tappable
                    .onTapGesture(count: 2) {
                        showSettings.toggle()
                    }
                
                HStack {
                    Button(action: { playback.startRadar() }) {
                        HStack(spacing: 4) {
                            if playback.isRadarLoading {
                                ProgressView()
                                    .tint(.white)
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "sparkles")
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
            let artworkSize = availableWidth - 48
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
    @State private var isDragging = false
    @State private var dragStarted = false
    @State private var scrubbedPosition: TimeInterval?

    var body: some View {
        let duration = playback.duration
        let displayedPosition = scrubbedPosition ?? playback.position
        let progress = duration > 0 ? min(max(displayedPosition / duration, 0), 1) : 0
        let trackHeight: CGFloat = isDragging ? 8 : 4.5
        let hitSlop: CGFloat = 24
        let trackFrameHeight: CGFloat = 14

        VStack(spacing: 12) {
            GeometryReader { proxy in
                let width = max(proxy.size.width, 1)
                let currentX = width * progress

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.25))
                        .frame(height: trackHeight)

                    Capsule()
                        .fill(Color.white.opacity(0.85))
                        .frame(width: width * progress, height: trackHeight)
                }
                .animation(.none, value: progress)
                .animation(.spring(response: 0.22, dampingFraction: 0.8), value: isDragging)
                .frame(height: trackFrameHeight)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if !dragStarted {
                                guard abs(value.location.x - currentX) <= hitSlop else {
                                    return
                                }
                                dragStarted = true
                                isDragging = true
                                playback.beginScrubbing()
                            }
                            guard dragStarted else { return }
                            let clampedX = min(max(0, value.location.x), width)
                            scrubbedPosition = duration * (clampedX / width)
                        }
                        .onEnded { value in
                            guard dragStarted else {
                                dragStarted = false
                                isDragging = false
                                return
                            }
                            let clampedX = min(max(0, value.location.x), width)
                            playback.seek(to: clampedX / width)
                            playback.endScrubbing()
                            scrubbedPosition = nil
                            isDragging = false
                            dragStarted = false
                        }
                )
            }
            .frame(height: trackFrameHeight)
            
            HStack {
                Text(TimeFormatting.string(from: displayedPosition))
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
        }
        .padding(.bottom, 32)
    }
}

struct VolumeControlView: View {
    @State private var isVolumePressed = false
    @State private var volume: Float = AVAudioSession.sharedInstance().outputVolume

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "speaker.fill")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.5))
                .scaleEffect(isVolumePressed ? 1.2 : 1.0)
            
            VolumeSliderView(value: $volume, isPressed: $isVolumePressed)
                .frame(height: 20)
                
            Image(systemName: "speaker.wave.3.fill")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.5))
                .scaleEffect(isVolumePressed ? 1.2 : 1.0)
        }
        .animation(.spring(response: 0.22, dampingFraction: 0.75), value: isVolumePressed)
        .background(
            VolumeView(volume: $volume)
                .frame(width: 1, height: 1)
                .opacity(0.01)
        )
        .padding(.horizontal, 32)
        .padding(.bottom, 32)
    }
}

struct BottomActionsView: View {
    @EnvironmentObject var playback: PlaybackManager
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
                             if showLyrics {
                                 Circle()
                                     .fill(Color.white.opacity(0.2))
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
             
             Button(action: { 
                 withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                     playback.togglePlayMode()
                 }
             }) {
                 Image(systemName: playback.playMode.iconName)
                     .font(.system(size: 24))
                     .foregroundStyle(.white.opacity(0.6))
                     .contentTransition(.symbolEffect(.replace))
             }

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
    @Binding var volume: Float

    func makeCoordinator() -> Coordinator {
        Coordinator(volume: $volume)
    }

    func makeUIView(context: Context) -> MPVolumeView {
        let volumeView = MPVolumeView(frame: .zero)
        volumeView.showsVolumeSlider = true
        context.coordinator.configure(in: volumeView)
        return volumeView
    }

    func updateUIView(_ uiView: MPVolumeView, context: Context) {
        context.coordinator.configure(in: uiView)
        context.coordinator.updateVolume(volume)
    }
}

extension VolumeView {
    final class Coordinator: NSObject {
        @Binding private var volume: Float
        private weak var slider: UISlider?
        private var volumeObservation: NSKeyValueObservation?

        init(volume: Binding<Float>) {
            _volume = volume
        }

        func configure(in volumeView: MPVolumeView) {
            guard let slider = volumeView.subviews.first(where: { $0 is UISlider }) as? UISlider else {
                return
            }

            if self.slider !== slider {
                self.slider = slider
                slider.isUserInteractionEnabled = false
                slider.isContinuous = true
                volumeObservation = AVAudioSession.sharedInstance().observe(\.outputVolume, options: [.new]) { [weak self] session, _ in
                    guard let self else { return }
                    let newValue = session.outputVolume
                    if abs(self.volume - newValue) > 0.001 {
                        DispatchQueue.main.async {
                            self.volume = newValue
                        }
                    }
                }
            }
        }

        func updateVolume(_ volume: Float) {
            guard let slider else { return }
            if abs(slider.value - volume) > 0.001 {
                slider.value = volume
                slider.sendActions(for: .valueChanged)
            }
        }
    }
}

struct VolumeSliderView: View {
    @Binding var value: Float
    @Binding var isPressed: Bool
    @State private var dragStarted = false
    private let normalTrackHeight: CGFloat = 4.5
    private let pressedTrackHeight: CGFloat = 8
    private let trackFrameHeight: CGFloat = 14
    private let hitSlop: CGFloat = 24
    private let feedbackGenerator = UIImpactFeedbackGenerator(style: .soft)

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let progress = CGFloat(value)
            let currentX = width * progress
            let trackHeight = isPressed ? pressedTrackHeight : normalTrackHeight

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.25))
                    .frame(height: trackHeight)

                Capsule()
                    .fill(Color.white.opacity(0.85))
                    .frame(width: width * progress, height: trackHeight)
            }
            .animation(.none, value: value)
            .animation(.spring(response: 0.22, dampingFraction: 0.8), value: isPressed)
            .frame(height: trackFrameHeight)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        if !dragStarted {
                            guard abs(gesture.location.x - currentX) <= hitSlop else {
                                return
                            }
                            dragStarted = true
                            isPressed = true
                            feedbackGenerator.prepare()
                            feedbackGenerator.impactOccurred()
                        }
                        guard dragStarted else { return }
                        let clampedX = min(max(0, gesture.location.x), width)
                        value = Float(clampedX / width)
                    }
                    .onEnded { gesture in
                        defer {
                            dragStarted = false
                            isPressed = false
                        }
                        guard dragStarted else { return }
                        let clampedX = min(max(0, gesture.location.x), width)
                        value = Float(clampedX / width)
                    }
            )
        }
        .frame(height: trackFrameHeight)
    }
}

// MARK: - Lyrics Scroll Component
struct LyricsScrollView: View {
    @EnvironmentObject var playback: PlaybackManager
    @State private var isUserScrolling = false
    @State private var userScrollTimeoutTask: Task<Void, Never>?
    let availableHeight: CGFloat

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
                    .padding(.vertical, availableHeight / 3)
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
