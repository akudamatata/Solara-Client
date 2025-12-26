import SwiftUI

struct FavoritesSheet: View {
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

                if playback.favorites.isEmpty {
                    ContentUnavailableView("暂无收藏", systemImage: "heart.slash", description: Text("点击播放器上的星号添加收藏"))
                } else {
                    List {
                        // Header Actions
                        Section {
                            HStack(spacing: 12) {
                                Button(action: {
                                    playback.playImmediately(playback.favorites)
                                }) {
                                    HStack {
                                        Image(systemName: "play.fill")
                                        Text("播放全部")
                                    }
                                    .font(.subheadline.bold())
                                    .foregroundStyle(.black)
                                    .padding(.vertical, 10)
                                    .frame(maxWidth: .infinity)
                                    .background(Color.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                }
                                .buttonStyle(.plain)

                                Button(action: {
                                    playback.playImmediately(playback.favorites.shuffled())
                                }) {
                                    HStack {
                                        Image(systemName: "shuffle")
                                        Text("随机播放")
                                    }
                                    .font(.subheadline.bold())
                                    .foregroundStyle(.white)
                                    .padding(.vertical, 10)
                                    .frame(maxWidth: .infinity)
                                    .background(Color.white.opacity(0.2))
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                }
                                .buttonStyle(.plain)
                            }
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 12, trailing: 20)) // Added horizontal inset
                            .listRowSeparator(.hidden)
                        }

                        // Song List
                        ForEach(playback.favorites) { song in
                            SongRow(song: song, isCurrent: playback.currentSong?.identity == song.identity, onAddToQueue: {
                                playback.enqueue(song)
                            }) {
                                playback.play(song: song)
                            }
                            .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                            .listRowBackground(Color.clear)
                            .listRowSeparatorTint(.white.opacity(0.2))
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    withAnimation {
                                        playback.toggleFavorite(song)
                                    }
                                } label: {
                                    Label("取消收藏", systemImage: "heart.slash")
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .frame(maxWidth: UIScreen.main.bounds.width) // Prevent horizontal overflow
            .navigationTitle("我的收藏")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        playback.clearFavorites()
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(.white)
                    }
                }
            }
            .environment(\.colorScheme, .dark)
        }
    }
}
