import SwiftUI

struct PlayerView: View {
    @EnvironmentObject var playback: PlaybackManager
    let imageLoader: ImageLoader

    var body: some View {
        VStack(spacing: 16) {
            RemoteImageView(
                url: playback.artworkURL,
                placeholderImage: playback.artwork,
                imageLoader: imageLoader
            )
                .frame(maxWidth: .infinity)
                .frame(height: 280)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .shadow(radius: 12)

            VStack(alignment: .leading, spacing: 6) {
                Text(playback.currentSong?.name ?? "未播放")
                    .font(.title2.bold())
                Text(playback.currentSong?.artist ?? "请选择歌曲")
                    .foregroundStyle(.secondary)
                if let album = playback.currentSong?.album {
                    Text(album)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if !playback.lyrics.isEmpty {
                LyricView(lyrics: playback.lyrics, position: playback.position)
                    .frame(maxWidth: .infinity, maxHeight: 200)
                    .padding(.vertical, 4)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            }

            HStack(spacing: 12) {
                Button {
                    if let song = playback.currentSong {
                        playback.toggleFavorite(song)
                    }
                } label: {
                    Image(systemName: isCurrentFavorite ? "heart.fill" : "heart")
                        .foregroundStyle(.pink)
                }
                Button {
                    playback.playImmediately(playback.queue)
                } label: {
                    Label("重新加载队列", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .tint(.white.opacity(0.12))
                Spacer()
                Text(playback.currentSong?.source.label ?? "")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.white.opacity(0.08), in: Capsule())
            }
        }
        .padding()
        .background(
            LinearGradient(colors: [Color.white.opacity(0.04), Color.white.opacity(0.01)], startPoint: .top, endPoint: .bottom)
                .blur(radius: 18)
        )
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }

    private var isCurrentFavorite: Bool {
        guard let song = playback.currentSong else { return false }
        return playback.favoriteSongs().contains(where: { $0.identity == song.identity })
    }
}
