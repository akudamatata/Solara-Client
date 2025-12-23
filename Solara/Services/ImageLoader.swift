import Foundation
import UIKit

final class ImageLoader {
    static let shared = ImageLoader()

    private let cache = NSCache<NSURL, UIImage>()
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func loadImage(from url: URL) async throws -> UIImage {
        if let cached = cache.object(forKey: url as NSURL) {
            return cached
        }
        var request = URLRequest(url: url)
        for (key, value) in APIClient.defaultHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }
        let (data, _) = try await session.data(for: request)
        guard let image = UIImage(data: data) else { throw APIError.malformedData }
        cache.setObject(image, forKey: url as NSURL)
        return image
    }
}
