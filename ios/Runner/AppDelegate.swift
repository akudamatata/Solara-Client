import UIKit
import Flutter
import AVFoundation
import MediaPlayer

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {
  private var remoteChannel: FlutterMethodChannel?
  private var previousCommandTarget: Any?
  private var nextCommandTarget: Any?
  private var playCommandTarget: Any?
  private var pauseCommandTarget: Any?
  private var toggleCommandTarget: Any?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    do {
      try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
      try AVAudioSession.sharedInstance().setActive(true)
    } catch {
      NSLog("[Solara] Failed to configure audio session: \(error)")
    }
    application.beginReceivingRemoteControlEvents()
    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(name: "solara/remote_controls", binaryMessenger: controller.binaryMessenger)
      remoteChannel = channel
      channel.setMethodCallHandler(handleRemoteCall)
      configureRemoteCommands()
    }
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func handleRemoteCall(_ call: FlutterMethodCall, result: FlutterResult) {
    switch call.method {
    case "configure":
      configureRemoteCommands()
      result(nil)
    case "updateState":
      if let args = call.arguments as? [String: Any] {
        let hasPrevious = args["hasPrevious"] as? Bool ?? false
        let hasNext = args["hasNext"] as? Bool ?? false
        let isPlaying = args["isPlaying"] as? Bool ?? false
        updateRemoteAvailability(hasPrevious: hasPrevious, hasNext: hasNext, isPlaying: isPlaying)
      }
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func configureRemoteCommands() {
    let commandCenter = MPRemoteCommandCenter.shared()
    updateRemoteAvailability(hasPrevious: false, hasNext: false, isPlaying: false)
    if previousCommandTarget == nil {
      previousCommandTarget = commandCenter.previousTrackCommand.addTarget { [weak self] _ in
        self?.remoteChannel?.invokeMethod("skipPrevious", arguments: nil)
        return .success
      }
    }
    if nextCommandTarget == nil {
      nextCommandTarget = commandCenter.nextTrackCommand.addTarget { [weak self] _ in
        self?.remoteChannel?.invokeMethod("skipNext", arguments: nil)
        return .success
      }
    }
    if playCommandTarget == nil {
      playCommandTarget = commandCenter.playCommand.addTarget { [weak self] _ in
        self?.remoteChannel?.invokeMethod("play", arguments: nil)
        return .success
      }
    }
    if pauseCommandTarget == nil {
      pauseCommandTarget = commandCenter.pauseCommand.addTarget { [weak self] _ in
        self?.remoteChannel?.invokeMethod("pause", arguments: nil)
        return .success
      }
    }
    if toggleCommandTarget == nil {
      toggleCommandTarget = commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
        self?.remoteChannel?.invokeMethod("toggle", arguments: nil)
        return .success
      }
    }
  }

  private func updateRemoteAvailability(hasPrevious: Bool, hasNext: Bool, isPlaying: Bool) {
    let commandCenter = MPRemoteCommandCenter.shared()
    commandCenter.previousTrackCommand.isEnabled = hasPrevious
    commandCenter.nextTrackCommand.isEnabled = hasNext
    commandCenter.playCommand.isEnabled = !isPlaying
    commandCenter.pauseCommand.isEnabled = isPlaying
    commandCenter.togglePlayPauseCommand.isEnabled = true
  }
}
