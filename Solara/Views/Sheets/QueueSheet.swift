import SwiftUI

struct QueueSheet: View {
    @EnvironmentObject var playback: PlaybackManager
    private let imageLoader = ImageLoader.shared

    var body: some View {
        NavigationStack {
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

                List {
                    ForEach(Array(playback.queue.enumerated()), id: \.element.identity) { index, song in
                        SongRow(song: song, isCurrent: index == playback.currentIndex) {
                            playback.play(song: song)
                        }
                        .listRowBackground(Color.clear) // Transparent row
                        .listRowSeparatorTint(.white.opacity(0.2))
                    }
                    .onDelete(perform: playback.removeSong)
                    .onMove(perform: playback.moveSong)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("播放队列")
            .navigationBarTitleDisplayMode(.inline) // Cleaner inline title
            .toolbar {
                EditButton()
            }
            .environment(\.colorScheme, .dark) // Force dark mode for text visibility
        }
    }
}
