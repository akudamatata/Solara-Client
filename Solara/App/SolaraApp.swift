import SwiftUI

@main
struct SolaraApp: App {
    @StateObject private var playbackManager = PlaybackManager(apiClient: APIClient.shared)

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(playbackManager)
        }
    }
}
