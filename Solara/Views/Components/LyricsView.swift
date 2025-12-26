import SwiftUI

struct LyricsView: View {
    @EnvironmentObject var playback: PlaybackManager
    @Environment(\.dismiss) var dismiss
    @State private var dragOffset: CGFloat = 0
    @State private var isUserScrolling = false
    @State private var userScrollTimeoutTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            // Background Blur
            if let artworkURL = playback.artworkURL {
                RemoteImageView(url: artworkURL, placeholderImage: playback.artwork, imageLoader: ImageLoader.shared, contentMode: .fill)
                    .ignoresSafeArea()
                    .blur(radius: 60)
                    .overlay(Color.black.opacity(0.6))
            } else {
                Color(red: 0.1, green: 0.1, blue: 0.1)
                    .ignoresSafeArea()
            }

            VStack(spacing: 0) {
                // Header
                HStack {
                    Spacer()
                    Capsule()
                        .fill(Color.white.opacity(0.2))
                        .frame(width: 40, height: 4)
                        .padding(.top, 8)
                    Spacer()
                }
                .frame(height: 20)
                
                if playback.lyrics.isEmpty {
                    ContentUnavailableView("暂无歌词", systemImage: "music.mic")
                        .foregroundStyle(.white.opacity(0.6))
                } else {
                    ScrollViewReader { proxy in
                        ScrollView(showsIndicators: false) {
                            VStack(alignment: .leading, spacing: 24) {
                                ForEach(playback.lyrics) { line in
                                    Text(line.text)
                                        .font(.system(size: isCurrentLine(line) ? 28 : 20, weight: isCurrentLine(line) ? .bold : .medium))
                                        .foregroundStyle(isCurrentLine(line) ? .white : .white.opacity(0.5))
                                        .blur(radius: isCurrentLine(line) ? 0 : 0.5)
                                        .scaleEffect(isCurrentLine(line) ? 1.05 : 1.0)
                                        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: isCurrentLine(line))
                                        .id(line.id)
                                        .onTapGesture {
                                            guard playback.duration > 0 else { return }
                                            playback.seek(to: line.time / playback.duration) 
                                        }
                                }
                            }
                            .padding(.vertical, UIScreen.main.bounds.height / 2.5) // Large padding for center focus
                            .padding(.horizontal, 32)
                        }
                        // Detect user scroll start (Simultaneous gesture not easy on ScrollView directly in SwiftUI, use DragGesture on overlay or simplified timeout)
                        .simultaneousGesture(
                            DragGesture()
                                .onChanged { _ in
                                    isUserScrolling = true
                                    userScrollTimeoutTask?.cancel()
                                }
                                .onEnded { _ in
                                    startResumeAutoScrollTimer()
                                }
                        )
                        .onChange(of: playback.position) { newTime in
                             guard !isUserScrolling else { return }
                             if let currentLine = currentLine(at: newTime) {
                                 withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                                     proxy.scrollTo(currentLine.id, anchor: .center)
                                 }
                             }
                        }
                    }
                }
            }
        }
    }

    private func isCurrentLine(_ line: LyricLine) -> Bool {
        guard let current = currentLine(at: playback.position) else { return false }
        return current.id == line.id
    }

    private func currentLine(at position: TimeInterval) -> LyricLine? {
        // Find the last line that has time <= current position
        return playback.lyrics.last { $0.time <= position }
    }
    
    private func startResumeAutoScrollTimer() {
        userScrollTimeoutTask?.cancel()
        userScrollTimeoutTask = Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds delay
            await MainActor.run {
                isUserScrolling = false
            }
        }
    }
}
