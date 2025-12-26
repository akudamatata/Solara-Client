import Foundation

enum SongSource: String, Codable, CaseIterable, Identifiable {
    case netease
    case kuwo
    case joox

    var id: String { rawValue }

    var label: String {
        switch self {
        case .netease: return "网易云"
        case .kuwo: return "酷我"
        case .joox: return "JOOX"
        }
    }

    var parameter: String {
        switch self {
        case .netease: return "netease"
        case .kuwo: return "kuwo"
        case .joox: return "joox"
        }
    }
}

enum SongQuality: String, Codable, CaseIterable, Identifiable {
    case standard
    case high
    case extreme
    case lossless

    var id: String { rawValue }

    var label: String {
        switch self {
        case .standard: return "标准 (128k)"
        case .high: return "高品 (192k)"
        case .extreme: return "极高 (320k)"
        case .lossless: return "无损 (FLAC)"
        }
    }

    var bitrateParameter: String {
        switch self {
        case .standard: return "128"
        case .high: return "192"
        case .extreme: return "320"
        case .lossless: return "flac"
        }
    }
}

enum PlayMode: String, Codable, CaseIterable, Identifiable {
    case off
    case list
    case single
    case shuffle

    var id: String { rawValue }

    var label: String {
        switch self {
        case .off: return "不循环"
        case .list: return "列表循环"
        case .single: return "单曲循环"
        case .shuffle: return "随机播放"
        }
    }
}

struct SongAudio: Codable, Hashable {
    let url: URL
    let quality: SongQuality
}

struct LyricLine: Codable, Hashable, Identifiable {
    var id = UUID()
    let time: TimeInterval
    let text: String

    private static let pattern = try! NSRegularExpression(pattern: "\\[(\\d{2}):(\\d{2})\\.(\\d{2,3})]", options: [])

    static func parse(_ raw: String) -> [LyricLine] {
        var lines: [LyricLine] = []
        for entry in raw.components(separatedBy: "\n") {
            let range = NSRange(entry.startIndex..<entry.endIndex, in: entry)
            let matches = pattern.matches(in: entry, options: [], range: range)
            guard !matches.isEmpty else { continue }
            let text = pattern.stringByReplacingMatches(in: entry, options: [], range: range, withTemplate: "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            for match in matches {
                let minute = Int((entry as NSString).substring(with: match.range(at: 1))) ?? 0
                let second = Int((entry as NSString).substring(with: match.range(at: 2))) ?? 0
                let hundredth = (entry as NSString).substring(with: match.range(at: 3))
                let millisecond: Int
                if hundredth.count == 3 {
                    millisecond = Int(hundredth) ?? 0
                } else {
                    millisecond = (Int(hundredth) ?? 0) * 10
                }
                let time = TimeInterval(minute * 60 + second) + TimeInterval(millisecond) / 1000
                lines.append(LyricLine(time: time, text: text))
            }
        }
        return lines.sorted { $0.time < $1.time }
    }
}

struct Song: Codable, Identifiable, Hashable {
    let id: String
    let source: SongSource
    var name: String
    var artist: String
    var album: String?
    var artworkId: String?
    var urlId: String?
    var lyricId: String?
    var duration: TimeInterval?

    var identity: String { "\(source.parameter):\(id)" }

    static func fromSearchPayload(_ payload: [String: Any]) -> Song? {
        guard let idValue = payload["id"] ?? payload["sid"] ?? payload["rid"],
              let nameValue = payload["name"]
        else { return nil }
        let artistField = payload["artist"] ?? payload["singer"] ?? payload["artists"]
        let artist = normalizeArtist(artistField)
        let albumValue = payload["album"]
        let albumName: String?
        if let albumMap = albumValue as? [String: Any] {
            albumName = albumMap["name"] as? String ?? albumMap["title"] as? String
        } else {
            albumName = (albumValue as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let artwork = (payload["pic_id"] ?? payload["picId"] ?? payload["pic"] ?? payload["picStr"] ?? payload["picUrl"] ?? payload["cover"] ?? payload["coverImgId"] ?? payload["albummid"] ?? payload["image"]) as? String
        let urlId = (payload["url_id"] ?? payload["urlId"] ?? payload["rid"] ?? payload["sid"] ?? payload["hash"] ?? payload["songId"] ?? payload["mid"] ?? idValue) as? String
        let lyricId = (payload["lyric_id"] ?? payload["lyricId"] ?? payload["lrc"] ?? idValue) as? String
        let sourceRaw = (payload["source"] ?? payload["platform"] ?? payload["provider"] ?? payload["vendor"]) as? String
        let source = SongSource.allCases.first(where: { $0.parameter == sourceRaw }) ?? .netease
        return Song(
            id: String(describing: idValue),
            source: source,
            name: String(describing: nameValue),
            artist: artist.isEmpty ? "未知艺术家" : artist,
            album: albumName?.isEmpty == true ? nil : albumName,
            artworkId: artwork,
            urlId: urlId,
            lyricId: lyricId,
            duration: payload["duration"] as? TimeInterval
        )
    }

    static func fromPlaylistPayload(_ payload: [String: Any]) -> Song? {
        guard let idValue = payload["id"], let nameValue = payload["name"] else { return nil }
        let artists = (payload["ar"] as? [[String: Any]] ?? [])
            .compactMap { $0["name"] as? String }
            .joined(separator: " / ")
        let album = payload["al"] as? [String: Any]
        let picId = album?["pic_str"] ?? album?["pic"] ?? album?["picUrl"]
        return Song(
            id: String(describing: idValue),
            source: .netease,
            name: String(describing: nameValue),
            artist: artists.isEmpty ? "未知艺术家" : artists,
            album: album?["name"] as? String,
            artworkId: picId as? String,
            urlId: String(describing: idValue),
            lyricId: String(describing: idValue),
            duration: payload["dt"] as? TimeInterval
        )
    }

    private static func normalizeArtist(_ value: Any?) -> String {
        if let text = value as? String {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let array = value as? [Any] {
            return array.compactMap { entry in
                if let text = entry as? String { return text.trimmingCharacters(in: .whitespacesAndNewlines) }
                if let map = entry as? [String: Any], let name = map["name"] as? String { return name.trimmed }
                return nil
            }.filter { !$0.isEmpty }.joined(separator: " / ")
        }
        if let map = value as? [String: Any], let name = map["name"] as? String {
            return name.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return ""
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
