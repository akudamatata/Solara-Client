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
    @State private var showSettings = false

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
                        showSettings: $showSettings,
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
    @Binding var showLyrics: Bool
    var animation: Namespace.ID
    let imageLoader: ImageLoader
    @EnvironmentObject var playback: PlaybackManager
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button(action: {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                        showLyrics = false
                    }
                }) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(12)
                        .background(Color.white.opacity(0.1))
                        .clipShape(Circle())
                }
                Spacer()
                Text("歌词")
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.7))
                    .textCase(.uppercase)
                Spacer()
                // Placeholder for symmetry
                Color.clear.frame(width: 44, height: 44)
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 20)
            
            // 1. Artwork (Smaller, circular/rounded)
             RemoteImageView(
                url: playback.artworkURL,
                placeholderImage: playback.artwork,
                imageLoader: imageLoader
            )
            .matchedGeometryEffect(id: "artwork", in: animation)
            .frame(width: 60, height: 60)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(radius: 10)
            .padding(.bottom, 20)
            
            // 2. Lyrics List
            LyricsScrollView().environmentObject(playback)
        }
    }
}

struct StandardPlayerView: View {
    @EnvironmentObject var playback: PlaybackManager
    @Binding var showSearch: Bool
    @Binding var showSettings: Bool // Pass binding to trigger from subviews if needed, though gesture is localized
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
            let artworkSize = UIScreen.main.bounds.width - 48
            RemoteImageView(
                url: playback.artworkURL,
                placeholderImage: playback.artwork,
                imageLoader: imageLoader
            )
            .matchedGeometryEffect(id: "artwork", in: animation)
            .frame(width: artworkSize, height: artworkSize)
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .shadow(color: .black.opacity(0.5), radius: 30, x: 0, y: 15)
            .padding(.bottom, 40)
            
            // Song Info
            VStack(spacing: 8) {
                Text(playback.currentSong?.name ?? "Solara Music")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                Text(playback.currentSong?.artist ?? "选择一首歌曲播放")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 30)
        }
    }
}

struct PlayerControlsView: View {
    @EnvironmentObject var playback: PlaybackManager
    @Binding var showQueue: Bool
    @Binding var showFavorites: Bool
    @Binding var showLyrics: Bool
    
    private var isCurrentFavorite: Bool {
        guard let song = playback.currentSong else { return false }
        return playback.favoriteSongs().contains(where: { $0.identity == song.identity })
    }

    var body: some View {
        VStack(spacing: 20) {
            // Scrubbing Bar
            VStack(spacing: 8) {
                Slider(
                    value: Binding(
                        get: { playback.position },
                        set: { newVal in
                            Task { await playback.seek(to: newVal) }
                        }
                    ),
                    in: 0...(playback.duration > 0 ? playback.duration : 1)
                )
                .accentColor(.white)
                .onAppear {
                     let thumbImage = UIImage(systemName: "circle.fill")?
                         .withTintColor(.white, renderingMode: .alwaysOriginal)
                     UISlider.appearance().setThumbImage(thumbImage, for: .normal)
                }
                
                HStack {
                    Text(FormatTime(playback.position))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.5))
                    Spacer()
                    Text(FormatTime(playback.duration))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            .padding(.horizontal, 24)
            
            // Transport Controls
            HStack(spacing: 0) {
                 // Shuffle
                 Button(action: { playback.togglePlayMode() }) {
                     Image(systemName: playback.playMode.iconName)
                         .font(.system(size: 20)) // Smaller
                         .foregroundStyle(playback.playMode == .list ? .white.opacity(0.4) : .pink)
                 }
                 .frame(width: 50)
                 
                 Spacer()
                 
                 // Previous
                 Button(action: { playback.playPrevious() }) {
                     Image(systemName: "backward.fill")
                         .font(.system(size: 32))
                         .foregroundStyle(.white)
                 }
                 
                 Spacer()
                 
                 // Play/Pause
                 Button(action: {
                     if playback.currentSong == nil && !playback.queue.isEmpty {
                         playback.play(song: playback.queue[0])
                     } else {
                         playback.togglePlayPause()
                     }
                 }) {
                     ZStack {
                         Circle()
                             .fill(Color.white)
                             .frame(width: 72, height: 72)
                         Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                             .font(.system(size: 32))
                             .foregroundStyle(.black)
                     }
                 }
                 .scaleEffect(playback.isPlaying ? 0.95 : 1.0)
                 .animation(.spring(response: 0.3), value: playback.isPlaying)
                 
                 Spacer()
                 
                 // Next
                 Button(action: { playback.playNext() }) {
                     Image(systemName: "forward.fill")
                         .font(.system(size: 32))
                         .foregroundStyle(.white)
                 }
                 
                 Spacer()
                 
                 // Repeat -> AirPlay
                 // Replacing Repeat button with AirPlay based on new request
                 // Actually this button was requested to be Repeat in previous turn, but user might have changed mind or I should stick to design.
                 // Wait, check request history. Conversation bc41ef: "Replacing Repeat Button with AirPlay".
                 // So I should put AirPlay here.
                 AVRoutePickerViewWrapper()
                     .frame(width: 30, height: 30) // Adjusted size
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
            
            // Bottom Actions (Queue, Favorites, Lyrics)
            BottomActionsView(
                showQueue: $showQueue,
                showFavorites: $showFavorites,
                showLyrics: $showLyrics,
                isCurrentFavorite: isCurrentFavorite,
                toggleFavorite: {
                    if let song = playback.currentSong {
                        playback.toggleFavorite(song)
                    }
                }
            )
            .padding(.horizontal, 30)
            .padding(.bottom, 40)
        }
        .background(
            LinearGradient(
                colors: [Color.black.opacity(0.0), Color.black.opacity(0.9)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
}

struct BottomActionsView: View {
    @Binding var showQueue: Bool
    @Binding var showFavorites: Bool
    @Binding var showLyrics: Bool
    let isCurrentFavorite: Bool
    let toggleFavorite: () -> Void

    var body: some View {
        HStack {
            // Lyrics (Quote Bubble) - Left
            Button(action: {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                    showLyrics.toggle()
                }
            }) {
                Image(systemName: "quote.bubble")
                    .font(.system(size: 22))
                    .foregroundStyle(showLyrics ? .white : .white.opacity(0.5))
            }
            
            Spacer()
            
            // Favorites (Heart) - Center Left
             Button(action: toggleFavorite) {
                Image(systemName: isCurrentFavorite ? "heart.fill" : "heart")
                    .font(.system(size: 24))
                    .foregroundStyle(isCurrentFavorite ? .pink : .white.opacity(0.5))
                    .scaleEffect(isCurrentFavorite ? 1.1 : 1.0)
                    .animation(.spring(response: 0.3), value: isCurrentFavorite)
            }
            
            Spacer()
            
            // Queue (List) - Center Right
            Button(action: { showQueue.toggle() }) {
                Image(systemName: "list.bullet")
                    .font(.system(size: 22))
                    .foregroundStyle(showQueue ? .white : .white.opacity(0.5))
            }
            
            Spacer()
            
            // Favorites List (Star) -> Now Bookmarks/Favorites Sheet - Right
            Button(action: { showFavorites.toggle() }) {
                Image(systemName: "bookmark.fill") // iOS style for library/saved
                    .font(.system(size: 22))
                    .foregroundStyle(showFavorites ? .white : .white.opacity(0.5))
            }
        }
    }
}

// Wrapper for AVRoutePickerView (AirPlay)
struct AVRoutePickerViewWrapper: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.activeTintColor = .white
        view.tintColor = .white.withAlphaComponent(0.5)
        view.prioritizesVideoDevices = false
        return view
    }
    
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
