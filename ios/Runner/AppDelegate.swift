import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // Module natif iOS additif : temps d'écran via Family Controls.
    // N'a aucune incidence sur Android (couche Dart branchée sur Platform).
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "ScreenTimePlugin") {
      ScreenTimePlugin.register(with: registrar)
    }
  }
}
