import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var teamEngines: [String: FlutterEngine] = [:]
  private var teamChannel: FlutterMethodChannel?

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
    }
  }
}
