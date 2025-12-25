import SwiftUI

struct QueueSheet: View {
    @EnvironmentObject var playback: PlaybackManager
    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(playback.queue.enumerated()), id: \.element.identity) { index, song in
                    SongRow(song: song, isCurrent: index == playback.currentIndex) {
                        playback.play(song: song)
                    }
                }
                .onDelete(perform: playback.removeSong)
                .onMove(perform: playback.moveSong)
            }
            .listStyle(.insetGrouped)
            .navigationTitle("播放队列")
            .toolbar {
                EditButton()
            }
        }
    }
}
