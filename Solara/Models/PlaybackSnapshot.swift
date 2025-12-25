import Foundation

struct PlaybackSnapshot: Codable {
    var queue: [Song]
    var favorites: [Song]
    var currentIdentity: String?
    var quality: SongQuality
    var playMode: PlayMode
    var position: TimeInterval
    var duration: TimeInterval
    var artwork: URL?

    static var empty: PlaybackSnapshot {
        PlaybackSnapshot(
            queue: [],
            favorites: [],
            currentIdentity: nil,
            quality: .extreme,
            playMode: .list,
            position: 0,
            duration: 0,
            artwork: nil
        )
    }
}
