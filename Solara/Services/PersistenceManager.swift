import Foundation

final class PersistenceManager {
    static let shared = PersistenceManager()
    
    private let fileManager = FileManager.default
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    
    private var solaraDirectory: URL {
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = documents.appendingPathComponent("Solara")
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }
    
    private var queueURL: URL { solaraDirectory.appendingPathComponent("queue.json") }
    private var favoritesURL: URL { solaraDirectory.appendingPathComponent("favorites.json") }
    private var settingsURL: URL { solaraDirectory.appendingPathComponent("settings.json") }
    private var historyURL: URL { solaraDirectory.appendingPathComponent("history.json") }
    
    // MARK: - Generic Helpers
    
    private func save<T: Encodable>(_ object: T, to url: URL) {
        Task { // Save on background to avoid blocking UI
            do {
                let data = try encoder.encode(object)
                try data.write(to: url)
            } catch {
                print("Persistence Error (Save): \(error.localizedDescription)")
            }
        }
    }
    
    private func load<T: Decodable>(from url: URL, as type: T.Type) -> T? {
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            return try decoder.decode(type, from: data)
        } catch {
            print("Persistence Error (Load): \(error.localizedDescription)")
            return nil
        }
    }
    
    // MARK: - Queue
    
    func saveQueue(_ songs: [Song]) {
        save(songs, to: queueURL)
    }
    
    func loadQueue() -> [Song] {
        return load(from: queueURL, as: [Song].self) ?? []
    }
    
    // MARK: - Favorites
    
    func saveFavorites(_ songs: [Song]) {
        save(songs, to: favoritesURL)
    }
    
    func loadFavorites() -> [Song] {
        return load(from: favoritesURL, as: [Song].self) ?? []
    }
    
    // MARK: - Settings
    
    struct AppSettings: Codable {
        var radarGenres: Set<String>
    }
    
    func saveSettings(_ settings: AppSettings) {
        save(settings, to: settingsURL)
    }
    
    func loadSettings() -> AppSettings {
        return load(from: settingsURL, as: AppSettings.self) ?? AppSettings(radarGenres: Set(RadarGenre.allCases.map { $0.rawValue }))
    }
    
    // MARK: - Search History
    
    struct SearchHistory: Codable {
        var lastQuery: String?
        var recentQueries: [String]
    }
    
    func saveHistory(lastQuery: String?, recentQueries: [String]) {
        let history = SearchHistory(lastQuery: lastQuery, recentQueries: recentQueries)
        save(history, to: historyURL)
    }
    
    func loadHistory() -> SearchHistory {
        return load(from: historyURL, as: SearchHistory.self) ?? SearchHistory(lastQuery: nil, recentQueries: [])
    }
    
    // MARK: - Playback Metadata
    
    struct PlaybackMetadata: Codable {
        var currentIdentity: String?
        var playMode: PlayMode
        var quality: SongQuality
        var position: TimeInterval
        var duration: TimeInterval
    }
    
    private var metadataURL: URL { solaraDirectory.appendingPathComponent("playback_metadata.json") }
    
    func savePlaybackMetadata(_ metadata: PlaybackMetadata) {
        save(metadata, to: metadataURL)
    }
    
    func loadPlaybackMetadata() -> PlaybackMetadata? {
        return load(from: metadataURL, as: PlaybackMetadata.self)
    }
}

enum RadarGenre: String, CaseIterable, Codable, Identifiable {
    case pop = "流行"
    case rock = "摇滚"
    case classical = "古典音乐"
    case folk = "民谣"
    case electronic = "电子"
    case jazz = "爵士"
    case rap = "说唱"
    case country = "乡村"
    case blues = "蓝调"
    case rnb = "R&B"
    case metal = "金属"
    case hiphop = "嘻哈"
    case easyListening = "轻音乐"
    
    var id: String { rawValue }
}
