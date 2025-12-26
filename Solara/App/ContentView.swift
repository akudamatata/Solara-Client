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
                // Top Handle / Header
                Capsule()
                    .fill(Color.white.opacity(0.3))
                    .frame(width: 40, height: 4)
                    .padding(.top, 12)
                
                Spacer()

                // Artwork
                GeometryReader { geometry in
                    let size = geometry.size.width - 64
                    RemoteImageView(
                        url: playback.artworkURL,
                        placeholderImage: playback.artwork,
                        imageLoader: imageLoader
                    )
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(color: .black.opacity(0.4), radius: 24, x: 0, y: 12)
                    .scaleEffect(playback.isPlaying ? 1.0 : 0.85) // Breathing effect
                    .animation(.spring(response: 0.5, dampingFraction: 0.6), value: playback.isPlaying)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(height: UIScreen.main.bounds.width - 64)
                .padding(.bottom, 32)
                
                // Track Info & Main Actions
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(playback.currentSong?.name ?? "Not Playing")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .padding(.trailing, 8) // Marquee space if needed
                        
                        Text(playback.currentSong?.artist ?? "Solara Music")
                            .font(.title3)
                            .foregroundStyle(.white.opacity(0.7))
                            .lineLimit(1)
                    }
                    
                    Spacer()
                    
                    Button {
                        // TODO: Implement "More" menu or similar, currently Heart/Fav
                         if let song = playback.currentSong {
                            playback.toggleFavorite(song)
                        }
                    } label: {
                        Image(systemName: isCurrentFavorite ? "heart.fill" : "heart")
                            .font(.system(size: 24))
                            .foregroundStyle(isCurrentFavorite ? .red : .white.opacity(0.7))
                            .symbolEffect(.bounce, value: isCurrentFavorite)
                    }
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 24)

                // Seek Bar
                VStack(spacing: 8) {
                    Slider(
                        value: Binding(
                            get: { playback.duration == 0 ? 0 : playback.position / max(playback.duration, 0.1) },
                            set: { progress in playback.seek(to: progress) }
                        ),
                        in: 0...1
                    )
                    .tint(.white.opacity(0.8))
                    .onAppear {
                        // Custom styling usually requires UIKit appearance proxy or custom generic view
                        // For vanilla SwiftUI, default is decent but thin on iOS 17
                    }
                    
                    HStack {
                        Text(TimeFormatting.string(from: playback.position))
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.6))
                            .monospacedDigit()
                        Spacer()
                        Text(TimeFormatting.string(from: playback.duration))
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.6))
                            .monospacedDigit()
                    }
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 40)

                // Playback Controls
                HStack(spacing: 48) {
                    Button(action: playback.previous) {
                        Image(systemName: "backward.fill")
                            .font(.system(size: 36)) // SF Pro standard size
                            .foregroundStyle(.white)
                    }
                    
                    Button(action: playback.togglePlayPause) {
                        Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 54))
                            .foregroundStyle(.white)
                            .symbolEffect(.bounce, value: playback.isPlaying)
                    }
                    
                    Button(action: playback.next) {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(.white)
                    }
                }
                .padding(.bottom, 48)
                
                // Bottom Actions (Volume/Route/List) - Using as Feature Toggles
                HStack(spacing: 40) {
                     Button(action: { /* Radar/Explore */ }) {
                         Image(systemName: "quote.bubble") // Lyrics or Radar
                             .font(.system(size: 22))
                             .foregroundStyle(.white.opacity(0.6))
                     }
                     
                     Button(action: { /* AirPlay/Devices */ }) {
                         Image(systemName: "airplayaudio")
                             .font(.system(size: 22))
                             .foregroundStyle(.white.opacity(0.6))
                     }
                     
                     Button(action: { showQueue.toggle() }) {
                         Image(systemName: "list.bullet")
                             .font(.system(size: 22))
                             .foregroundStyle(.white.opacity(0.6))
                     }
                }
                .padding(.bottom, 32)
            }
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
        .overlay(alignment: .topTrailing) {
             // Search Button Overlay
             Button(action: { showSearch.toggle() }) {
                 Image(systemName: "magnifyingglass")
                     .font(.system(size: 20, weight: .semibold))
                     .foregroundStyle(.white.opacity(0.8))
                     .padding(20)
                     .background(.ultraThinMaterial, in: Circle())
                     .padding(.top, 40)
                     .padding(.trailing, 20)
             }
        }
    }

    private var isCurrentFavorite: Bool {
        guard let song = playback.currentSong else { return false }
        return playback.favoriteSongs().contains(where: { $0.identity == song.identity })
    }
}
