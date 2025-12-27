import SwiftUI

struct SettingsSheet: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var playback: PlaybackManager
    @State private var settings = PersistenceManager.shared.loadSettings()
    
    // Grid layout for genres
    let columns = [
        GridItem(.adaptive(minimum: 100))
    ]
    
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                // Background
                if let url = playback.artworkURL {
                    RemoteImageView(
                        url: url,
                        placeholderImage: playback.artwork,
                        imageLoader: ImageLoader.shared,
                        contentMode: .fill
                    )
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .ignoresSafeArea()
                    .clipped()
                    .blur(radius: 80)
                    .overlay(Color.black.opacity(0.7))
                } else {
                    Color(red: 0.05, green: 0.05, blue: 0.06).ignoresSafeArea()
                }
                
                VStack(spacing: 0) {
                // Header
                HStack {
                    Text("系统设置")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(.white)
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(.white.opacity(0.3))
                    }
                }
                .padding(24)
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 30) {
                        
                        // Radar Settings
                        VStack(alignment: .leading, spacing: 16) {
                            Text("探索雷达偏好")
                                .font(.headline)
                                .foregroundStyle(.white)
                            
                            Text("选择您喜欢的流派，雷达将根据您的选择自动发现新歌。")
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.6))
                            
                            LazyVGrid(columns: columns, spacing: 12) {
                                ForEach(RadarGenre.allCases) { genre in
                                    GenreToggle(
                                        genre: genre,
                                        isSelected: settings.radarGenres.contains(genre.rawValue)
                                    ) {
                                        toggleGenre(genre)
                                    }
                                }
                            }
                        }
                        .padding(20)
                        .background(Color.white.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        
                        // Storage Info
                        VStack(alignment: .leading, spacing: 16) {
                            Text("存储位置")
                                .font(.headline)
                                .foregroundStyle(.white)
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Text("播放列表、收藏和设置保存在：")
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.6))
                                
                                HStack {
                                    Image(systemName: "folder")
                                        .foregroundStyle(.pink)
                                    Text("iPhone / 文件 / Solara")
                                        .font(.system(.body, design: .monospaced))
                                        .foregroundStyle(.white)
                                }
                                .padding(12)
                                .background(Color.black.opacity(0.3))
                                .cornerRadius(8)
                            }
                        }
                        .padding(20)
                        .background(Color.white.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        
                    }
                    .padding(.horizontal, 20)
                }
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .onDisappear {
            saveSettings()
        }
    }
    
    private func toggleGenre(_ genre: RadarGenre) {
        if settings.radarGenres.contains(genre.rawValue) {
            settings.radarGenres.remove(genre.rawValue)
        } else {
            settings.radarGenres.insert(genre.rawValue)
        }
        saveSettings()
    }
    
    private func saveSettings() {
        PersistenceManager.shared.saveSettings(settings)
    }
}

struct GenreToggle: View {
    let genre: RadarGenre
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(genre.rawValue)
                .font(.system(size: 14, weight: .medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(isSelected ? Color.pink : Color.white.opacity(0.1))
                .foregroundStyle(.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isSelected ? Color.pink : Color.clear, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}
