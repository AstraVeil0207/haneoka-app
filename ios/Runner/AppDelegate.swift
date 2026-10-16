import Flutter
import UIKit
import CoreHaptics

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var teamEngines: [String: FlutterEngine] = [:]
  private var teamChannel: FlutterMethodChannel?
  private var hapticsChannel: FlutterMethodChannel?
  private var impacts: [Int: UIImpactFeedbackGenerator] = [:]
  private let notifications = UINotificationFeedbackGenerator()

  private func configureHaptics(_ messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "org.haneoka/haptics", binaryMessenger: messenger)
    hapticsChannel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { result(nil); return }
      switch call.method {
      case "supported":
        result(CHHapticEngine.capabilitiesForHardware().supportsHaptics)
      case "stop":
        // Preset impacts are transient, with no queued or continuous work.
        result(nil)
      case "emit":
        guard UIApplication.shared.applicationState == .active,
              let recipe = call.arguments as? [String: Any],
              (recipe["_iosPlayType"] as? Int) == 1,
              let preset = recipe["_iosPresetType"] as? Int else { result(nil); return }
        if preset == 5 {
          self.notifications.notificationOccurred(.success)
          self.notifications.prepare()
        } else {
          let style: UIImpactFeedbackGenerator.FeedbackStyle
          switch preset {
          case 1: style = .light
          case 2: style = .medium
          case 3: style = .heavy
          default: result(nil); return
          }
          let generator = self.impacts[preset] ?? UIImpactFeedbackGenerator(style: style)
          self.impacts[preset] = generator
          generator.impactOccurred(intensity: min(1, max(0, recipe["_iosIntensity"] as? Double ?? 1)))
          generator.prepare()
        }
        result(nil)
      default: result(FlutterMethodNotImplemented)
      }
    }
  }


  private func configureTeamEngine(_ messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "org.haneoka/team_engine", binaryMessenger: messenger)
    teamChannel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self, let args = call.arguments as? [String: Any], let key = args["key"] as? String else {
        result(FlutterError(code: "engine-key", message: "Missing engine key", details: nil)); return
      }
      if call.method == "dispose" {
        self.teamEngines.removeValue(forKey: key)?.destroyContext()
        result(nil); return
      }
      guard call.method == "start" else { result(FlutterMethodNotImplemented); return }
      if self.teamEngines[key] == nil {
        let engine = FlutterEngine(name: "haneoka-team-engine", project: nil, allowHeadlessExecution: true)
        guard engine.run(withEntrypoint: nil, libraryURI: nil, initialRoute: nil,
                         entrypointArgs: ["--haneoka-team-engine=\(key)"]) else {
          engine.destroyContext()
          result(FlutterError(code: "engine-start", message: "Could not start team engine", details: nil)); return
        }
        self.teamEngines[key] = engine
      }
      result(nil)
    }
  }

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "HaneokaTeamEngine") {
      configureTeamEngine(registrar.messenger())
      configureHaptics(registrar.messenger())
    }
  }
}
