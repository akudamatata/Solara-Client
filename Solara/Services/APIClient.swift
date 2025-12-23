import Foundation

enum APIError: LocalizedError {
    case invalidResponse
    case statusCode(Int)
    case malformedData
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "无法解析服务器响应"
        case .statusCode(let code): return "请求失败 (\(code))"
        case .malformedData: return "数据格式不正确"
        case .requestFailed(let message): return message
        }
    }
}

final class APIClient {
    static let shared = APIClient()

    private let baseURL = URL(string: "https://music-api.gdstudio.xyz/api.php")!
    private let session: URLSession
    private let decoder = JSONDecoder()
    private let charset = Array("abcdefghijklmnopqrstuvwxyz0123456789")

    static var defaultHeaders: [String: String] {
        [
            "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)",
            "Referer": "https://music-api.gdstudio.xyz/",
            "Origin": "https://music-api.gdstudio.xyz",
            "Accept": "application/json"
        ]
    }

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchPlaylist(id: String = "3778678", limit: Int = 50) async throws -> [Song] {
        let payload = try await get(parameters: [
            "types": "playlist",
            "id": id,
            "limit": String(limit)
        ])
        guard let map = payload as? [String: Any],
              let playlist = map["playlist"] as? [String: Any],
              let tracks = playlist["tracks"] as? [[String: Any]]
        else { throw APIError.malformedData }
        let songs = tracks.compactMap(Song.fromPlaylistPayload)
        guard !songs.isEmpty else { throw APIError.malformedData }
        return Array(songs.prefix(limit))
    }

    func search(keyword: String, source: SongSource, limit: Int = 20, page: Int = 1) async throws -> [Song] {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let payload = try await get(parameters: [
            "types": "search",
            "source": source.parameter,
            "name": trimmed,
            "count": String(limit),
            "pages": String(page)
        ])
        guard let list = payload as? [[String: Any]] else { throw APIError.malformedData }
        return list.compactMap(Song.fromSearchPayload)
    }

    func resolveSongURL(for song: Song, quality: SongQuality) async throws -> SongAudio {
        let payload = try await get(parameters: [
            "types": "url",
            "id": song.urlId ?? song.id,
            "source": song.source.parameter,
            "br": quality.bitrateParameter
        ])
        guard let map = payload as? [String: Any],
              let urlString = map["url"] as? String,
              let url = URL(string: urlString)
        else { throw APIError.malformedData }
        return SongAudio(url: url, quality: quality)
    }

    func resolveArtworkURL(for song: Song, size: Int = 320) async throws -> URL? {
        guard let picId = song.artworkId, !picId.isEmpty else { return nil }
        let payload = try await get(parameters: [
            "types": "pic",
            "id": picId,
            "source": song.source.parameter,
            "size": String(size)
        ])
        guard let map = payload as? [String: Any], let urlString = map["url"] as? String else {
            return nil
        }
        return URL(string: urlString)
    }

    func fetchLyrics(for song: Song) async throws -> [LyricLine] {
        let payload = try await get(parameters: [
            "types": "lyric",
            "id": song.lyricId ?? song.id,
            "source": song.source.parameter
        ])
        let raw: String?
        if let map = payload as? [String: Any] {
            raw = (map["lyric"] as? String) ?? (map["lrc"] as? String)
        } else {
            raw = payload as? String
        }
        guard let value = raw, !value.isEmpty else { return [] }
        return LyricLine.parse(value)
    }

    private func get(parameters: [String: String]) async throws -> Any {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        var query = parameters
        query["s"] = query["s"] ?? signature()
        components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = components.url else { throw APIError.invalidResponse }

        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        for (key, value) in APIClient.defaultHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.requestFailed(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw APIError.statusCode(http.statusCode) }
        do {
            return try JSONSerialization.jsonObject(with: data, options: [])
        } catch {
            if let text = String(data: data, encoding: .utf8) {
                return text
            }
            throw APIError.malformedData
        }
    }

    private func signature() -> String {
        String((0..<16).compactMap { _ in charset.randomElement() })
    }
}
