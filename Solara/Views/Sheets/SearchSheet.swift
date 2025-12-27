import SwiftUI

struct SearchSheet: View {
    @ObservedObject var viewModel: SearchViewModel
    @EnvironmentObject var playback: PlaybackManager
    @Environment(\.dismiss) var dismiss
    private let imageLoader = ImageLoader.shared

    let onAddToQueue: ([Song]) -> Void
    let onPlayNow: ([Song]) -> Void

    var body: some View {
        ZStack {
            // Dynamic Background (Synchronized with Main Interface)
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
                // Premium Floating Search Bar
                VStack(spacing: 16) {
                    HStack {
                        Text("搜索")
                            .font(.system(size: 34, weight: .bold))
                            .foregroundStyle(.white)
                        Spacer()
                        
                        // Select Button
                        Button {
                            withAnimation {
                                viewModel.isSelectionMode.toggle()
                            }
                        } label: {
                            Text(viewModel.isSelectionMode ? "完成" : "多选")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(viewModel.isSelectionMode ? .pink : .white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(viewModel.isSelectionMode ? Color.white : Color.white.opacity(0.1))
                                .clipShape(Capsule())
                        }
                        .padding(.trailing, 8)
                        
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 24))
                                .foregroundStyle(.white.opacity(0.3))
                                .symbolRenderingMode(.hierarchical)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 20)

                    // Custom Search Box
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.white.opacity(0.5))
                        
                        TextField("", text: $viewModel.keyword, prompt: Text("搜索歌曲、艺术家...").foregroundStyle(.white.opacity(0.3)))
                            .foregroundStyle(.white)
                            .tint(.pink)
                            .submitLabel(.search)
                            .onSubmit { viewModel.search() }
                        
                        if !viewModel.keyword.isEmpty {
                            Button {
                                viewModel.keyword = ""
                                viewModel.reset()
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.white.opacity(0.5))
                            }
                        }
                    }
                    .padding(12)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 20)
                    
                    // Source Selector (Floating Pills)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(SongSource.allCases) { source in
                                Button(action: {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                        viewModel.selectedSource = source
                                    }
                                    if !viewModel.keyword.isEmpty { viewModel.search() }
                                }) {
                                    Text(source.label)
                                        .font(.system(size: 14, weight: .medium))
                                        .padding(.horizontal, 20)
                                        .padding(.vertical, 8)
                                        .background(
                                            ZStack {
                                                if viewModel.selectedSource == source {
                                                    Capsule().fill(Color.pink)
                                                } else {
                                                    Capsule().fill(Color.white.opacity(0.1))
                                                }
                                            }
                                        )
                                        .foregroundStyle(.white)
                                }
                            }
                        }
                        .padding(.horizontal, 24)
                    }
                    .padding(.bottom, 16)
                }
                .background(
                    LinearGradient(
                        colors: [Color.black.opacity(0.6), Color.black.opacity(0.0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                // Results List
                // Results List
                List {
                    if viewModel.isSearching {
                        HStack {
                            Spacer()
                            ProgressView()
                                .tint(.white)
                            Spacer()
                        }
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .padding(.top, 40)
                    } else if let error = viewModel.lastError {
                        ContentUnavailableView(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.white.opacity(0.6))
                            .listRowBackground(Color.clear)
                    } else if viewModel.results.isEmpty && !viewModel.keyword.isEmpty {
                         VStack(spacing: 20) {
                            Image(systemName: "music.note.list")
                                .font(.system(size: 60))
                                .foregroundStyle(.white.opacity(0.2))
                            Text("未找到相关歌曲")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.4))
                         }
                         .frame(maxWidth: .infinity)
                         .padding(.top, 100)
                         .listRowBackground(Color.clear)
                         .listRowSeparator(.hidden)
                    } else {
                        ForEach(viewModel.results) { song in
                            HStack(spacing: 16) {
                                if viewModel.isSelectionMode {
                                    Image(systemName: viewModel.selectedSongs.contains(song.identity) ? "checkmark.circle.fill" : "circle")
                                        .font(.title2)
                                        .foregroundStyle(viewModel.selectedSongs.contains(song.identity) ? .pink : .white.opacity(0.3))
                                        .onTapGesture {
                                            withAnimation(.spring(response: 0.2)) {
                                                viewModel.toggleSelection(song)
                                            }
                                        }
                                }
                                
                                SongRow(song: song, isCurrent: playback.currentSong?.identity == song.identity, showCover: false) {
                                    // Row play action
                                    if viewModel.isSelectionMode {
                                        withAnimation(.spring(response: 0.2)) {
                                            viewModel.toggleSelection(song)
                                        }
                                    } else {
                                        onPlayNow([song])
                                        dismiss()
                                    }
                                }
                            }
                            .listRowBackground(Color.clear)
                            .listRowSeparatorTint(.white.opacity(0.1))
                            .listRowInsets(EdgeInsets(top: 4, leading: 24, bottom: 4, trailing: 24))
                            .onAppear {
                                if song.identity == viewModel.results.last?.identity {
                                    viewModel.loadMore()
                                }
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .environment(\.colorScheme, .dark)
                
                // Batch Actions Bar
                if viewModel.isSelectionMode && !viewModel.selectedSongs.isEmpty {
                    HStack(spacing: 20) {
                        Button {
                            // Add selected to queue
                            let selected = viewModel.results.filter { viewModel.selectedSongs.contains($0.identity) }
                            onAddToQueue(selected)
                            viewModel.isSelectionMode = false
                        } label: {
                            HStack {
                                Image(systemName: "text.badge.plus")
                                Text("添加到播放 (\(viewModel.selectedSongs.count))")
                            }
                            .font(.headline)
                            .foregroundStyle(.white)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.pink)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        
                        Button {
                            // Add selected to favorites
                             let selected = viewModel.results.filter { viewModel.selectedSongs.contains($0.identity) }
                             // Ideally PlaybackManager handles this, but we don't have a batch favorite method yet.
                             // We can just iterate or add one to PlaybackManager.
                             // For now, let's just toggle explicitly or assume PlaybackManager needs an update.
                             // Wait, playback.toggleFavorite is singular.
                             // I'll add `playback.addToFavorites(songs)` or just loop here.
                             // Accessing playback directly.
                             for song in selected {
                                 if !playback.favorites.contains(where: { $0.identity == song.identity }) {
                                     playback.toggleFavorite(song) // This toggles, so be careful.
                                     // Need strict "Add".
                                 }
                             }
                             viewModel.isSelectionMode = false
                        } label: {
                            Image(systemName: "heart.fill")
                                .font(.title2)
                                .foregroundStyle(.white)
                                .padding()
                                .background(Color.white.opacity(0.15))
                                .clipShape(Circle())
                        }
                    }
                    .padding(20)
                    .background(Color.black.opacity(0.8))
                    .transition(.move(edge: .bottom))
                }
            }
            .frame(maxWidth: .infinity) // Prevent horizontal overflow
            .animation(.spring(response: 0.3), value: viewModel.isSelectionMode)
        }
    }
}
