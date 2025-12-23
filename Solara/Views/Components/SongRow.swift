import SwiftUI

struct SongRow: View {
    let song: Song
    var isCurrent: Bool = false
    var onTap: (() -> Void)?

    var body: some View {
        Button(action: { onTap?() }) {
            HStack(spacing: 12) {
                Image(systemName: isCurrent ? "play.circle.fill" : "music.note")
                    .foregroundStyle(isCurrent ? .pink : .secondary)
                VStack(alignment: .leading, spacing: 4) {
                    Text(song.name)
                        .font(.body)
                        .foregroundStyle(.primary)
                    Text(song.artist)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(song.source.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }
}
