import SwiftUI
import AVKit

struct AirPlayView: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let routePickerView = AVRoutePickerView()
        routePickerView.activeTintColor = .white
        routePickerView.tintColor = .white.withAlphaComponent(0.6)
        routePickerView.prioritizesVideoDevices = false // Audio only preference
        return routePickerView
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {
        // No updates needed typically
    }
}
