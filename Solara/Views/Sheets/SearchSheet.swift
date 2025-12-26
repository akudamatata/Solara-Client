import SwiftUI

struct SearchSheet: View {
    @ObservedObject var viewModel: SearchViewModel
    @EnvironmentObject var playback: PlaybackManager

    let onAddToQueue: ([Song]) -> Void
    let onPlayNow: ([Song]) -> Void

    // Simplified Search Sheet matching Apple Music Design
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Source Selector (Pills)
                // Source Selector (Pills)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        Spacer(minLength: 0)
                        ForEach(SongSource.allCases) { source in
                            Button(action: {
                                withAnimation {
                                    viewModel.selectedSource = source
                                }
                            }) {
                                Text(source.label)
                                    .font(.subheadline)
                                    .fontWeight(viewModel.selectedSource == source ? .semibold : .regular)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(viewModel.selectedSource == source ? Color.pink : Color(.secondarySystemFill))
                                    .foregroundStyle(viewModel.selectedSource == source ? .white : .primary)
                                    .clipShape(Capsule())
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .frame(minWidth: UIScreen.main.bounds.width) // Ensure full width for centering
                }
                .background(Color(.systemBackground))
                
                // Results List
                List {
                    if viewModel.isSearching {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                        .listRowSeparator(.hidden)
                    } else if let error = viewModel.lastError {
                        ContentUnavailableView(error, systemImage: "exclamationmark.triangle")
                    } else if viewModel.results.isEmpty && !viewModel.keyword.isEmpty {
                        ContentUnavailableView("无结果", systemImage: "magnifyingglass")
                    } else {
                        ForEach(viewModel.results) { song in
                            Button {
                                onPlayNow([song])
                            } label: {
                                SongRow(song: song, isCurrent: playback.currentSong?.identity == song.identity) {
                                    onPlayNow([song])
                                }
                            }
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        }
                    }
                }
                .listStyle(.plain)
            }
            .navigationTitle("搜索")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $viewModel.keyword, placement: .navigationBarDrawer(displayMode: .always), prompt: "搜索歌曲或艺术家")
            .onSubmit(of: .search) {
                viewModel.search()
            }
            .onChange(of: viewModel.keyword) { newValue in
                if newValue.isEmpty {
                    viewModel.reset()
                }
            }
        }
    }

    private func selectedSongs() -> [Song] {
        [] // Deprecated
    }
}
