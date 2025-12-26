import SwiftUI

struct LyricView: View {
    let lyrics: [LyricLine]
    let position: TimeInterval

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(lyrics) { line in
                        Text(line.text)
                            .fontWeight(isActive(line) ? .semibold : .regular)
                            .foregroundStyle(isActive(line) ? .primary : .secondary)
                            .id(line.id)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
            }
            .onChange(of: position) { _ in
                if let active = activeLine()?.id {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        proxy.scrollTo(active, anchor: .center)
                    }
                }
            }
        }
    }

    private func isActive(_ line: LyricLine) -> Bool {
        guard let next = lyrics.drop { $0.id != line.id }.dropFirst().first else {
            return position >= line.time
        }
        return position >= line.time && position < next.time
    }

    private func activeLine() -> LyricLine? {
        lyrics.last(where: { $0.time <= position }) ?? lyrics.first
    }
}

struct LyricsScrollView: View {
    @EnvironmentObject var playback: PlaybackManager

    var body: some View {
        if playback.lyrics.isEmpty {
            VStack(spacing: 8) {
                Text("暂无歌词")
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.8))
                Text("正在为你加载歌词…")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.6))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            LyricView(lyrics: playback.lyrics, position: playback.position)
        }
    }
}
