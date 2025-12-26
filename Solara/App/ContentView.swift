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
            // Dark Background
            Color(red: 0.11, green: 0.13, blue: 0.18)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Top Bar
                HStack {
                    Button(action: { /* Dismiss or Minimize */ }) {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 20))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(playback.currentSong?.artist ?? "Solara")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    Spacer()
                    Button(action: { /* Timer or Options */ }) {
                        Image(systemName: "timer")
                            .font(.system(size: 20))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 10)

                Spacer()

                // Artwork
                RemoteImageView(
                    url: playback.artworkURL,
                    placeholderImage: playback.artwork,
                    imageLoader: imageLoader
                )
                .aspectRatio(1, contentMode: .fit)
                .cornerRadius(12)
                .shadow(color: .black.opacity(0.4), radius: 20, x: 0, y: 10)
                .padding(.horizontal, 32)

                Spacer()

                // Song Info
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(playback.currentSong?.name ?? "未播放")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        
                        Text(playback.currentSong?.artist ?? "请选择歌曲")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Button {
                        if let song = playback.currentSong {
                            playback.toggleFavorite(song)
                        } else {
                            showFavorites.toggle()
                        }
                    } label: {
                        Image(systemName: isCurrentFavorite ? "heart.fill" : "heart")
                            .font(.title2)
                            .foregroundStyle(isCurrentFavorite ? .red : .secondary)
                    }
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 24)

                // Progress Bar
                VStack(spacing: 8) {
                    Slider(
                        value: Binding(
                            get: { playback.duration == 0 ? 0 : playback.position / max(playback.duration, 0.1) },
                            set: { progress in playback.seek(to: progress) }
                        ),
                        in: 0...1
                    )
                    .tint(.white.opacity(0.4))
                    
                    HStack {
                        Text(TimeFormatting.string(from: playback.position))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(TimeFormatting.string(from: playback.duration))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 32)

                // Controls
                HStack(spacing: 0) {
                    // Loop Mode
                    Button(action: {
                        let modes: [PlayMode] = [.list, .single, .shuffle]
                        if let index = modes.firstIndex(of: playback.playMode) {
                            playback.setPlayMode(modes[(index + 1) % modes.count])
                        }
                    }) {
                        Image(systemName: symbol(for: playback.playMode))
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)

                    // Previous
                    Button(action: playback.previous) {
                        Image(systemName: "backward.fill")
                            .font(.title2)
                            .foregroundStyle(.white)
                    }
                    .frame(maxWidth: .infinity)

                    // Play/Pause
                    Button(action: playback.togglePlayPause) {
                        ZStack {
                            Circle()
                                .fill(Color(red: 1.0, green: 0.2, blue: 0.3)) // Pinkish Red
                                .frame(width: 72, height: 72)
                            Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                                .font(.largeTitle)
                                .foregroundStyle(.white)
                        }
                    }
                    .frame(maxWidth: .infinity)

                    // Next
                    Button(action: playback.next) {
                        Image(systemName: "forward.fill")
                            .font(.title2)
                            .foregroundStyle(.white)
                    }
                    .frame(maxWidth: .infinity)

                    // Queue/Menu
                    Button(action: { showSearch.toggle() }) {
                        Image(systemName: "list.bullet")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 48)
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showQueue) {
            QueueSheet().environmentObject(playback)
        }
        .sheet(isPresented: $showFavorites) {
            FavoritesSheet { song in
                playback.play(song: song)
            }
            .environmentObject(playback)
        }
        .sheet(isPresented: $showSearch) {
            SearchSheet(viewModel: searchViewModel) { songs in
                playback.enqueue(songs)
            } onPlayNow: { songs in
                playback.playImmediately(songs)
            }
            .environmentObject(playback)
        }
    }

    private var isCurrentFavorite: Bool {
        guard let song = playback.currentSong else { return false }
        return playback.favoriteSongs().contains(where: { $0.identity == song.identity })
    }

    private func symbol(for mode: PlayMode) -> String {
        switch mode {
        case .list: return "repeat"
        case .single: return "repeat.1"
        case .shuffle: return "shuffle"
        }
    }
}
