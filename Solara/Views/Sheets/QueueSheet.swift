import SwiftUI

struct QueueSheet: View {
    @EnvironmentObject var playback: PlaybackManager
    @Environment(\.dismiss) var dismiss
    private let imageLoader = ImageLoader.shared

    var body: some View {
        ZStack {
            // Immersive Dynamic Background
            if let url = playback.artworkURL {
                RemoteImageView(
                    url: url,
                    placeholderImage: playback.artwork,
                    imageLoader: imageLoader,
                    contentMode: .fill
                )
                .ignoresSafeArea()
                .blur(radius: 80)
                .overlay(Color.black.opacity(0.6))
            } else {
                Color(red: 0.05, green: 0.05, blue: 0.06)
                    .ignoresSafeArea()
            }

            VStack(spacing: 0) {
                // Premium Header
                VStack(spacing: 8) {
                    Capsule()
                        .fill(Color.white.opacity(0.2))
                        .frame(width: 36, height: 5)
                        .padding(.top, 8)
                    
                    HStack {
                        Text("待播清单")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(.white)
                        
                        Spacer()
                        
                        Button {
                            playback.clearQueue()
                        } label: {
                            Image(systemName: "trash.circle.fill")
                                .font(.system(size: 24))
                                .foregroundStyle(.white.opacity(0.3))
                                .symbolRenderingMode(.hierarchical)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
                    .padding(.bottom, 8)
                }
                .background(
                    LinearGradient(
                        colors: [Color.black.opacity(0.6), Color.black.opacity(0.0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                // Queue List
                List {
                    // Now Playing Section
                    if let current = playback.currentSong {
                        Section {
                            SongRow(song: current, isCurrent: true, artworkOverrideURL: playback.artworkURL) {
                                // Already playing
                            }
                        } header: {
                            Text("正在播放")
                                .font(.footnote.bold())
                                .foregroundStyle(.white.opacity(0.5))
                                .textCase(.uppercase)
                        }
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }

                     // Up Next Section
                     if !playback.queue.isEmpty {
                        Section {
                             ForEach(Array(playback.queue.enumerated()), id: \.element.identity) { index, song in
                                // Filter out current song
                                if index != playback.currentIndex {
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
                                    .listRowBackground(Color.clear)
                                    .listRowSeparatorTint(.white.opacity(0.1))
                                }
                            }
                            .onDelete(perform: playback.removeSong)
                            .onMove(perform: playback.moveSong)
                        } header: {
                            Text("稍后播放")
                                .font(.footnote.bold())
                                .foregroundStyle(.white.opacity(0.5))
                                .textCase(.uppercase)
                        }
                    }
                }
                .listStyle(.grouped)
                .scrollContentBackground(.hidden)
                .frame(maxWidth: .infinity) 
        }
    }
}
