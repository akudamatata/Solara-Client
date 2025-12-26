import SwiftUI
import MediaPlayer
import UIKit

struct VolumeView: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView {
        let volumeView = MPVolumeView(frame: .zero)
        volumeView.showsVolumeSlider = true
        volumeView.setVolumeThumbImage(UIImage(systemName: "circle.fill")?.withTintColor(.white, renderingMode: .alwaysOriginal), for: .normal)
        
        // Customize slider appearance if possible, or rely on tint
        // Note: transforming the slider subview is sometimes necessary for height, 
        // but standard appearance is usually fine.
        // We will try to set tint color via the appearance proxy or standard properties if accessible,
        // but MPVolumeView is tricky. Basic customization:
        
        return volumeView
    }

    func updateUIView(_ uiView: MPVolumeView, context: Context) {
        // Traverse subviews to find the UISlider and customize it
        if let slider = uiView.subviews.first(where: { $0 is UISlider }) as? UISlider {
            slider.minimumTrackTintColor = .white
            slider.maximumTrackTintColor = UIColor.white.withAlphaComponent(0.2)
            slider.thumbTintColor = .white
            
            // Optional: Custom thumb image for a cleaner look (smaller circle)
            let config = UIImage.SymbolConfiguration(pointSize: 12, weight: .bold)
            let thumb = UIImage(systemName: "circle.fill", withConfiguration: config)?.withTintColor(.white, renderingMode: .alwaysOriginal)
            slider.setThumbImage(thumb, for: .normal)
        }
    }
}
