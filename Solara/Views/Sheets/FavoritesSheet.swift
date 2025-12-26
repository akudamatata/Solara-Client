import SwiftUI

struct FavoritesSheet: View {
    @EnvironmentObject var playback: PlaybackManager
    let onPlay: (Song) -> Void

    var body: some View {
        NavigationStack {
            Group {
                if playback.favoriteSongs().isEmpty {
                    ContentUnavailableView("暂无收藏", systemImage: "heart")
                } else {
                    List(playback.favoriteSongs(), id: \.identity) { song in
                        SongRow(song: song) {
                            onPlay(song)
                        }
                        .contextMenu {
                            Button(role: .destructive) {
                                playback.toggleFavorite(song)
                            } label: {
                                Label("移除收藏", systemImage: "trash")
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("收藏")
        }
    }
}
