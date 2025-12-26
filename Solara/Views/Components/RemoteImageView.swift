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
                // Default Placeholder
                ZStack {
                    Color(red: 0.15, green: 0.15, blue: 0.16)
                    Image(systemName: "music.note")
                        .font(.system(size: 40))
                        .foregroundStyle(.white.opacity(0.2))
                }
            }
        }
        .task(id: url) { 
            image = nil // Reset when URL changes
            await loadImage() 
        }
        .animation(.easeInOut, value: image)
        .clipped()
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
