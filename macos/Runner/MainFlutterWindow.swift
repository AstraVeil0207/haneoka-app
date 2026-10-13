import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
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
        self.teamEngines.removeValue(forKey: key)?.shutDownEngine()
        result(nil); return
      }
      guard call.method == "start" else { result(FlutterMethodNotImplemented); return }
      if self.teamEngines[key] == nil {
        let project = FlutterDartProject()
        project.dartEntrypointArguments = ["--haneoka-team-engine=\(key)"]
        let engine = FlutterEngine(name: "haneoka-team-engine", project: project, allowHeadlessExecution: true)
        guard engine.run(withEntrypoint: nil) else {
          engine.shutDownEngine()
          result(FlutterError(code: "engine-start", message: "Could not start team engine", details: nil)); return
        }
        self.teamEngines[key] = engine
      }
      result(nil)
    }
  }
  deinit {
    teamChannel?.setMethodCallHandler(nil)
    for engine in teamEngines.values { engine.shutDownEngine() }
  }

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    configureTeamEngine(flutterViewController.engine.binaryMessenger)

    super.awakeFromNib()
  }
}
