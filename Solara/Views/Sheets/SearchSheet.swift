import SwiftUI

struct SearchSheet: View {
    @ObservedObject var viewModel: SearchViewModel
    @EnvironmentObject var playback: PlaybackManager

    let onAddToQueue: ([Song]) -> Void
    let onPlayNow: ([Song]) -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                TextField("搜索歌曲/艺术家", text: $viewModel.keyword)
                    .textFieldStyle(.roundedBorder)
                // Source Selector
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach([SongSource.netease, .kuwo, .joox], id: \.self) { source in
                            Button(action: {
                                if viewModel.selectedSources.contains(source) {
                                    viewModel.selectedSources.remove(source)
                                } else {
                                    viewModel.selectedSources.insert(source)
                                }
                            }) {
                                Text(source.label)
                                    .font(.caption)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(viewModel.selectedSources.contains(source) ? Color.pink : Color.secondary.opacity(0.1))
                                    .foregroundStyle(viewModel.selectedSources.contains(source) ? .white : .primary)
                                    .clipShape(Capsule())
                            }
                        }
                    }
                }

                HStack {
                    Button("搜索") { viewModel.searchAllSources() }
                        .buttonStyle(.borderedProminent)
                    Spacer()
                    Menu {
                        Button("加入队列") {
                            let songs = selectedSongs()
                            onAddToQueue(songs)
                            viewModel.clearSelection()
                        }
                        Button("立即播放") {
                            let songs = selectedSongs()
                            onPlayNow(songs)
                            viewModel.clearSelection()
                        }
                    } label: {
                        Label("批量操作", systemImage: "plus.circle")
                    }
                    .disabled(viewModel.selected.isEmpty)
                }

                if viewModel.isSearching {
                    ProgressView("搜索中…")
                        .frame(maxWidth: .infinity, alignment: .center)
                }

                if let error = viewModel.lastError {
                    ContentUnavailableView(error, systemImage: "exclamationmark.triangle")
                }

                List(viewModel.aggregated, id: \.identity) { song in
                    SongRow(song: song, isCurrent: playback.currentSong?.identity == song.identity) {
                        playback.play(song: song)
                    }
                    .listRowBackground(viewModel.selected.contains(song.identity) ? Color.pink.opacity(0.08) : nil)
                    .contextMenu {
                        Button("加入队列") { onAddToQueue([song]) }
                        Button("立即播放") { onPlayNow([song]) }
                        Button(viewModel.selected.contains(song.identity) ? "取消选择" : "选择") {
                            viewModel.toggleSelection(for: song)
                        }
                    }
                    .onTapGesture {
                        viewModel.toggleSelection(for: song)
                    }
                }
                .listStyle(.insetGrouped)
            }
            .padding()
            .navigationTitle("搜索")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("清空") {
                        viewModel.reset()
                    }
                }
            }
        }
    }

    private func selectedSongs() -> [Song] {
        viewModel.aggregated.filter { viewModel.selected.contains($0.identity) }
    }
}
