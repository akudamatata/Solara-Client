import SwiftUI

struct SearchSheet: View {
    @ObservedObject var viewModel: SearchViewModel
    @EnvironmentObject var playback: PlaybackManager
    @Environment(\.dismiss) var dismiss

    let onAddToQueue: ([Song]) -> Void
    let onPlayNow: ([Song]) -> Void

    var body: some View {
        ZStack {
            // Futuristic Mesh-like Background
            Color(red: 0.05, green: 0.05, blue: 0.07)
                .ignoresSafeArea()
            
            // Subtle ambient glows
            Circle()
                .fill(Color.pink.opacity(0.15))
                .frame(width: 400, height: 400)
                .blur(radius: 100)
                .offset(x: -150, y: -200)
            
            Circle()
                .fill(Color.blue.opacity(0.1))
                .frame(width: 300, height: 300)
                .blur(radius: 80)
                .offset(x: 150, y: 200)

            VStack(spacing: 0) {
                // Premium Floating Search Bar
                VStack(spacing: 16) {
                    HStack {
                        Text("搜索")
                            .font(.system(size: 34, weight: .bold))
                            .foregroundStyle(.white)
                        Spacer()
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
                .background(.ultraThinMaterial.opacity(0.8))

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
                                .font(.title3.semibold())
                                .foregroundStyle(.white.opacity(0.4))
                         }
                         .frame(maxWidth: .infinity)
                         .padding(.top, 100)
                         .listRowBackground(Color.clear)
                         .listRowSeparator(.hidden)
                    } else {
                        ForEach(viewModel.results) { song in
                            SongRow(song: song, isCurrent: playback.currentSong?.identity == song.identity) {
                                onPlayNow([song])
                                dismiss()
                            }
                            .listRowBackground(Color.clear)
                            .listRowSeparatorTint(.white.opacity(0.1))
                            .listRowInsets(EdgeInsets(top: 4, leading: 24, bottom: 4, trailing: 24))
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .environment(\.colorScheme, .dark)
            }
        }
    }
}
