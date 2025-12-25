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
            LinearGradient(
                colors: [Color(red: 0.06, green: 0.07, blue: 0.1), Color(red: 0.16, green: 0.17, blue: 0.23)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 24) {
                header
                PlayerView(imageLoader: imageLoader)
                playbackControls
            }
            .padding()
        }
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

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Solara")
                    .font(.largeTitle.bold())
                Text("原生 iOS 播放体验")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 12) {
                Button {
                    showFavorites.toggle()
                } label: {
                    Label("收藏", systemImage: "heart.fill")
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.pink)
                }
                Button {
                    showQueue.toggle()
                } label: {
                    Label("队列", systemImage: "music.note.list")
                        .labelStyle(.iconOnly)
                }
                Button {
                    showSearch.toggle()
                } label: {
                    Label("搜索", systemImage: "magnifyingglass")
                        .labelStyle(.iconOnly)
                }
            }
            .buttonStyle(.bordered)
            .tint(.white.opacity(0.14))
        }
    }

    private var playbackControls: some View {
        VStack(spacing: 16) {
            VStack {
                Slider(
                    value: Binding(
                        get: { playback.duration == 0 ? 0 : playback.position / max(playback.duration, 0.1) },
                        set: { progress in playback.seek(to: progress) }
                    ),
                    in: 0...1
                )
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

            HStack(spacing: 16) {
                Picker("音质", selection: Binding(
                    get: { playback.quality },
                    set: { playback.setQuality($0) }
                )) {
                    ForEach(SongQuality.allCases) { quality in
                        Text(quality.label).tag(quality)
                    }
                }
                .pickerStyle(.menu)
                .tint(.pink)

                Spacer()

                Button(action: playback.previous) {
                    Image(systemName: "backward.fill")
                        .font(.title2)
                }
                Button(action: playback.togglePlayPause) {
                    Image(systemName: playback.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.pink)
                }
                Button(action: playback.next) {
                    Image(systemName: "forward.fill")
                        .font(.title2)
                }
                Menu {
                    ForEach(PlayMode.allCases) { mode in
                        Button(action: { playback.setPlayMode(mode) }) {
                            Label(mode.label, systemImage: playback.playMode == mode ? "checkmark" : "")
                        }
                    }
                } label: {
                    Image(systemName: symbol(for: playback.playMode))
                }
            }
        }
        .foregroundStyle(.white)
    }

    private func symbol(for mode: PlayMode) -> String {
        switch mode {
        case .list: return "repeat"
        case .single: return "repeat.1"
        case .shuffle: return "shuffle"
        }
    }
}
