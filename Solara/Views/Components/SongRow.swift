import SwiftUI

struct SongRow: View {
    let song: Song
    var isCurrent: Bool = false
    var showCover: Bool = true
    var onAddToQueue: (() -> Void)? = nil
    var onTap: (() -> Void)?
    
    private let imageLoader = ImageLoader.shared

    var body: some View {
        Button(action: { 
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onTap?() 
        }) {
            HStack(spacing: 16) {
                // Artwork with loading state
                if showCover {
                    ZStack {
                        if let artworkId = song.artworkId, let url = URL(string: artworkId) {
                             RemoteImageView(
                                url: url,
                                placeholderImage: nil,
                                imageLoader: imageLoader,
                                contentMode: .fill
                             )
                             .frame(width: 48, height: 48)
                             .clipShape(RoundedRectangle(cornerRadius: 8))
                        } else if let url = URL(string: "https://music.163.com/api/v1/song/artwork/\(song.identity)?size=128") { // Fallback
                             RemoteImageView(
                                url: url,
                                placeholderImage: nil,
                                imageLoader: imageLoader,
                                contentMode: .fill
                             )
                             .frame(width: 48, height: 48)
                             .clipShape(RoundedRectangle(cornerRadius: 8))
                        } else {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.white.opacity(0.1))
                                .frame(width: 48, height: 48)
                                .overlay(
                                    Image(systemName: "music.note")
                                        .foregroundStyle(.white.opacity(0.4))
                                )
                        }
                        
                        if isCurrent {
                            Color.black.opacity(0.3)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            
                            NowPlayingAnimation()
                                .frame(width: 16, height: 16)
                        }
                    }
                    .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
                } else if isCurrent {
                     // If cover is hidden but song is playing, show a small indicator
                    NowPlayingAnimation()
                        .frame(width: 16, height: 16)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(song.name)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(isCurrent ? .pink : .white)
                        .lineLimit(1)
                    
                    HStack(spacing: 4) {
                        if song.source == .netease {
                            Image(systemName: "e.circle.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(.red.opacity(0.8))
                        }
                        
                        Text(song.artist)
                            .font(.system(size: 14))
                            .foregroundStyle(.white.opacity(0.6))
                            .lineLimit(1)
                    }
                }
                
                Spacer()
                
                if let onAddToQueue {
                    Button(action: onAddToQueue) {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 20))
                            .foregroundStyle(.white.opacity(0.6))
                            .padding(.horizontal, 4)
                    }
                }

                if !isCurrent {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.3))
                        .padding(8)
                }
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Animated Now Playing Bars
struct NowPlayingAnimation: View {
    @State private var drawingHeight = true

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<3) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.pink)
                    .frame(width: 3, height: drawingHeight ? CGFloat.random(in: 4...16) : CGFloat.random(in: 4...16))
                    .animation(Animation.easeInOut(duration: 0.5).repeatForever(autoreverses: true).delay(Double(i) * 0.1), value: drawingHeight)
            }
        }
        .onAppear {
            drawingHeight.toggle()
        }
    }
}
