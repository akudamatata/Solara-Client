import SwiftUI

struct RemoteImageView: View {
    let url: URL?
    let placeholderImage: UIImage?
    let imageLoader: ImageLoader
    var contentMode: ContentMode = .fit

    @State private var image: UIImage?
    @State private var isLoading = false

    var body: some View {
        ZStack {
            if let displayImage = image ?? placeholderImage {
                Image(uiImage: displayImage)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else if isLoading {
                ProgressView()
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.thinMaterial)
                    .overlay(Image(systemName: "music.note").foregroundStyle(.secondary))
            }
        }
        .task(id: url) { await loadImage() }
        .animation(.easeInOut, value: image)
    }

    private func loadImage() async {
        guard let url else { return }
        if image != nil { return }
        isLoading = true
        do {
            image = try await imageLoader.loadImage(from: url)
        } catch {
            image = nil
        }
        isLoading = false
    }
}
