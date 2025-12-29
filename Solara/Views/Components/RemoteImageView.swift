import SwiftUI

struct RemoteImageView: View {
    let url: URL?
    let placeholderImage: UIImage?
    let imageLoader: ImageLoader
    var contentMode: ContentMode = .fit

    @State private var image: UIImage?
    @State private var isLoading = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if let displayImage = image ?? placeholderImage {
                    Image(uiImage: displayImage)
                        .resizable()
                        .aspectRatio(contentMode: contentMode)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                } else if isLoading {
                    ProgressView()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                } else {
                    // Default Placeholder
                    ZStack {
                        Color(red: 0.15, green: 0.15, blue: 0.16)
                        Image(systemName: "music.note")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: geometry.size.width * 0.4, height: geometry.size.height * 0.4)
                            .foregroundStyle(.white.opacity(0.2))
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .task(id: url) { 
            image = nil // Reset when URL changes
            await loadImage() 
        }
        .animation(.easeInOut, value: image != nil)
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
