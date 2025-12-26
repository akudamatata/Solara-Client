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

            VStack(spacing: 0) {
                // Top Bar
                ZStack {
                    // Title (Centered)
                    Text("SOLARA")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.8))
                        .textCase(.uppercase)
                        // Removed frame(maxWidth: .infinity) to prevent ZStack expansion issues
                    
                    // Buttons (Left & Right)
                    HStack {
                        Button(action: {
                            // Explore Radar Function
                            Task { playback.next() }
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "sparkles")
                                Text("探索")
                            }
                            .font(.subheadline.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.white.opacity(0.1))
                            .clipShape(Capsule())
                        }
                        
                        Spacer()
                        
                        Button(action: { showSearch.toggle() }) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 20))
                                .foregroundStyle(.white)
                                .padding(10)
                                .background(Color.white.opacity(0.1))
                                .clipShape(Circle())
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)

                Spacer()

                // Artwork
                let artworkSize = UIScreen.main.bounds.width - 48
                RemoteImageView(
                    url: playback.artworkURL,
                    placeholderImage: playback.artwork,
                    imageLoader: imageLoader
                )
                .frame(width: artworkSize, height: artworkSize)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.4), radius: 24, x: 0, y: 12)
                .scaleEffect(playback.isPlaying ? 1.0 : 0.82)
                .animation(.spring(response: 0.5, dampingFraction: 0.6), value: playback.isPlaying)
                .padding(.bottom, 32)
                
                // Track Info Row
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(playback.currentSong?.name ?? "Not Playing")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        
                        Text(playback.currentSong?.artist ?? "Solara Music")
                            .font(.title3)
                            .foregroundStyle(.white.opacity(0.7)) // Slightly lighter than secondary
                            .lineLimit(1)
                    }
                    
                    Spacer()
                    
                    HStack(spacing: 20) {
                        Button {
                             // More Action
                        } label: {
                             Image(systemName: "ellipsis.circle.fill") // Or just circle
                                 .font(.system(size: 24))
                                 .foregroundStyle(.white.opacity(0.4))
                        }

                        Button {
                             if let song = playback.currentSong {
                                playback.toggleFavorite(song)
                            }
                        } label: {
                            Image(systemName: isCurrentFavorite ? "star.fill" : "star")
                                .font(.system(size: 24))
                                .foregroundStyle(isCurrentFavorite ? .yellow : .white.opacity(0.4))
                                .symbolEffect(.bounce, value: isCurrentFavorite)
                        }
                    }
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 24)

                // Seek Bar with Quality Badge
                VStack(spacing: 12) {
                    Slider(
                        value: Binding(
                            get: { playback.duration == 0 ? 0 : playback.position / max(playback.duration, 0.1) },
                            set: { progress in playback.seek(to: progress) }
                        ),
                        in: 0...1
                    )
                    .tint(.white.opacity(0.5))
                    // .onAppear { ... customize slider appearance ... }
                    
                    HStack {
                        Text(TimeFormatting.string(from: playback.position))
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.5))
                            .monospacedDigit()
                        
                        
                        Spacer()
                        
                        // Quality Badge
                        Menu {
                            Picker("音质选择", selection: Binding(
                                get: { playback.quality },
                                set: { playback.setQuality($0) }
                            )) {
                                ForEach(SongQuality.allCases) { quality in
                                    Text(quality.label).tag(quality)
                                }
                            }
                        } label: {
                            HStack(spacing: 2) {
                                Image(systemName: "waveform")
                                Text(playback.quality.label.components(separatedBy: " ").first ?? "标准")
                            }
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.white.opacity(0.8))
                            .cornerRadius(4)
                        }
                        
                        Spacer()

                        Text(TimeFormatting.string(from: playback.duration))
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.5))
                            .monospacedDigit()
                    }
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 24)

                // Playback Controls
                HStack(spacing: 50) {
                    Button(action: playback.previous) {
                        Image(systemName: "backward.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(.white)
                    }
                    
                    Button(action: playback.togglePlayPause) {
                        Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 54)) // Fixed large size
                            .symbolRenderingMode(.hierarchical) 
                            .foregroundStyle(.white)
                            // Note: For a solid white filled circle background like Apple Music, 
                            // one might use a ZStack with Circle().fill(.white) if systemName isn't enough.
                            // But usually play.fill is solid enough.
                    }
                    
                    Button(action: playback.next) {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(.white)
                    }
                }
                .padding(.bottom, 32)
                
                // Volume Slider Section
                HStack(spacing: 12) {
                    Image(systemName: "speaker.fill")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                    
                    VolumeView()
                        .frame(height: 20) // MPVolumeView needs a frame, usually 20-40pt height
                        .tint(Color.white) // Fallback
                        
                    Image(systemName: "speaker.wave.3.fill")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 32)

                // Bottom Actions
                HStack(spacing: 50) {
                     Button(action: { showFavorites.toggle() }) {
                         Image(systemName: "heart.fill")
                             .font(.system(size: 24))
                             .foregroundStyle(showFavorites ? .pink : .white.opacity(0.6))
                             .symbolEffect(.bounce, value: showFavorites)
                     }

                     Button(action: { showLyrics.toggle() }) {
                         Image(systemName: "quote.bubble")
                             .font(.system(size: 24))
                             .foregroundStyle(showLyrics ? .white : .white.opacity(0.6))
                             .symbolEffect(.bounce, value: showLyrics)
                     }
                     
                     Button(action: { /* AirPlay */ }) {
                         Image(systemName: "airplayaudio")
                             .font(.system(size: 24))
                             .foregroundStyle(.white.opacity(0.6))
                     }
                     
                     Button(action: { showQueue.toggle() }) {
                         Image(systemName: "list.bullet")
                             .font(.system(size: 24))
                             .foregroundStyle(.white.opacity(0.6))
                     }
                }
                .padding(.bottom, 20)
            }
            .frame(maxWidth: .infinity) // Ensure content doesn't overflow screen width
        }
        .sheet(isPresented: $showFavorites) {
            FavoritesSheet().environmentObject(playback)
        }
        .sheet(isPresented: $showQueue) {
            QueueSheet().environmentObject(playback)
        }
        .sheet(isPresented: $showSearch) {
            SearchSheet(viewModel: searchViewModel) { songs in
                playback.enqueue(songs)
            } onPlayNow: { songs in
                playback.playImmediately(songs)
            }
            .environmentObject(playback)
        }
        .sheet(isPresented: $showLyrics) {
            LyricsView().environmentObject(playback)
        }
    }

    @State private var showLyrics = false

    private var isCurrentFavorite: Bool {
        guard let song = playback.currentSong else { return false }
        return playback.favoriteSongs().contains(where: { $0.identity == song.identity })
    }
}

import MediaPlayer

struct VolumeView: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView {
        let volumeView = MPVolumeView(frame: .zero)
        volumeView.showsVolumeSlider = true
        // Remove the route button if present (we have a separate AirPlay button)
        volumeView.showsRouteButton = false
        // Customize thumb
        let config = UIImage.SymbolConfiguration(pointSize: 12, weight: .bold)
        let thumb = UIImage(systemName: "circle.fill", withConfiguration: config)?.withTintColor(.white, renderingMode: .alwaysOriginal)
        volumeView.setVolumeThumbImage(thumb, for: .normal)
        return volumeView
    }

    func updateUIView(_ uiView: MPVolumeView, context: Context) {
        // Traverse subviews for styling if needed
        if let slider = uiView.subviews.first(where: { $0 is UISlider }) as? UISlider {
            slider.minimumTrackTintColor = .white
            slider.maximumTrackTintColor = UIColor.white.withAlphaComponent(0.2)
        }
    }
}
