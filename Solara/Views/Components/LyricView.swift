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
