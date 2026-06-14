import Flutter
import UIKit

#if canImport(FamilyControls)
import FamilyControls
import DeviceActivity
import SwiftUI
#endif

/// Module natif iOS pour le temps d'écran via l'API Screen Time d'Apple
/// (Family Controls). Purement additif : miroir iOS du MethodChannel
/// `com.tiipee/screen_time` déjà utilisé côté Android. Aucune incidence sur
/// le code Android (la couche Dart branche déjà sur `Platform`).
///
/// Gardé `@available(iOS 16.0, *)` pour les API Family Controls : la cible de
/// déploiement reste 13.0, les anciens iOS reçoivent des réponses neutres.
public class ScreenTimePlugin: NSObject, FlutterPlugin {

  /// Suite App Group partagée avec l'extension DeviceActivityMonitor.
  /// ⚠️ Doit correspondre EXACTEMENT à l'App Group activé dans Xcode
  /// (Signing & Capabilities) pour l'app ET l'extension.
  static let appGroup = "group.com.tiipee.tiipee"
  static let selectionKey = "familySelection"
  static let activityName = "tiipee.daily"

  /// Pas (en minutes) entre deux seuils, et plafond de mesure.
  /// 5 min × 144 = 12 h couvertes. Ajustable après tests sur device.
  static let thresholdStep = 5
  static let thresholdMaxMinutes = 12 * 60

  private var defaults: UserDefaults? { UserDefaults(suiteName: ScreenTimePlugin.appGroup) }

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "com.tiipee/screen_time",
      binaryMessenger: registrar.messenger()
    )
    let instance = ScreenTimePlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "hasPermission":
      result(authorizationApproved())

    case "requestPermission":
      requestAuthorization(result: result)

    case "getDailyScreenOnMinutes":
      let days = (call.arguments as? [String: Any])?["days"] as? Int ?? 7
      result(dailyScreenOnMinutes(days: days))

    // ── Spécifique iOS (sélection des apps + monitoring Screen Time) ──
    case "presentAppPicker":
      presentAppPicker(result: result)
    case "hasAppSelection":
      result(defaults?.data(forKey: ScreenTimePlugin.selectionKey) != nil)
    case "startMonitoring":
      result(startMonitoring())
    case "stopMonitoring":
      stopMonitoring()
      result(nil)

    // Méthodes Android sans équivalent iOS pertinent → réponses neutres,
    // pour que la couche Dart reste agnostique de la plateforme.
    case "isIgnoringBatteryOptimizations":
      result(true)
    case "requestIgnoreBatteryOptimizations":
      result(nil)
    case "getAndClearPendingSessions":
      result([])
    case "getScreenOffMinutes":
      result(0)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - Autorisation Family Controls

  private func authorizationApproved() -> Bool {
    #if canImport(FamilyControls)
    if #available(iOS 16.0, *) {
      return AuthorizationCenter.shared.authorizationStatus == .approved
    }
    #endif
    return false
  }

  private func requestAuthorization(result: @escaping FlutterResult) {
    #if canImport(FamilyControls)
    if #available(iOS 16.0, *) {
      Task {
        do {
          // `.individual` : autorise CET appareil (l'enfant), sans imposer
          // le partage familial Apple.
          try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
          DispatchQueue.main.async { result(true) }
        } catch {
          DispatchQueue.main.async { result(false) }
        }
      }
      return
    }
    #endif
    result(false)
  }

  // MARK: - Sélection des apps à suivre (FamilyActivityPicker)

  private func presentAppPicker(result: @escaping FlutterResult) {
    #if canImport(FamilyControls)
    if #available(iOS 16.0, *) {
      DispatchQueue.main.async {
        guard let root = Self.topViewController() else {
          result(false); return
        }
        // Recharge la sélection existante pour la pré-cocher.
        var initial = FamilyActivitySelection()
        if let data = self.defaults?.data(forKey: ScreenTimePlugin.selectionKey),
           let decoded = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) {
          initial = decoded
        }
        let view = TiipeePickerView(initial: initial) { selection in
          if let encoded = try? JSONEncoder().encode(selection) {
            self.defaults?.set(encoded, forKey: ScreenTimePlugin.selectionKey)
          }
          root.dismiss(animated: true)
          // Redémarre le monitoring avec la nouvelle sélection.
          _ = self.startMonitoring()
          let count = selection.applicationTokens.count
            + selection.categoryTokens.count
            + selection.webDomainTokens.count
          result(count)
        } onCancel: {
          root.dismiss(animated: true)
          result(-1)
        }
        let host = UIHostingController(rootView: view)
        root.present(host, animated: true)
      }
      return
    }
    #endif
    result(false)
  }

  // MARK: - Monitoring Screen Time (seuils)

  private func startMonitoring() -> Bool {
    #if canImport(FamilyControls)
    if #available(iOS 16.0, *) {
      guard let data = defaults?.data(forKey: ScreenTimePlugin.selectionKey),
            let selection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data)
      else { return false }

      // Aucune cible sélectionnée → rien à mesurer.
      if selection.applicationTokens.isEmpty
        && selection.categoryTokens.isEmpty
        && selection.webDomainTokens.isEmpty {
        return false
      }

      let schedule = DeviceActivitySchedule(
        intervalStart: DateComponents(hour: 0, minute: 0),
        intervalEnd: DateComponents(hour: 23, minute: 59),
        repeats: true
      )

      var events: [DeviceActivityEvent.Name: DeviceActivityEvent] = [:]
      var m = ScreenTimePlugin.thresholdStep
      while m <= ScreenTimePlugin.thresholdMaxMinutes {
        let name = DeviceActivityEvent.Name("threshold_\(m)")
        events[name] = DeviceActivityEvent(
          applications: selection.applicationTokens,
          categories: selection.categoryTokens,
          webDomains: selection.webDomainTokens,
          threshold: DateComponents(minute: m)
        )
        m += ScreenTimePlugin.thresholdStep
      }

      let center = DeviceActivityCenter()
      let activity = DeviceActivityName(ScreenTimePlugin.activityName)
      center.stopMonitoring([activity])
      do {
        try center.startMonitoring(activity, during: schedule, events: events)
        return true
      } catch {
        return false
      }
    }
    #endif
    return false
  }

  private func stopMonitoring() {
    #if canImport(FamilyControls)
    if #available(iOS 16.0, *) {
      DeviceActivityCenter().stopMonitoring([DeviceActivityName(ScreenTimePlugin.activityName)])
    }
    #endif
  }

  // MARK: - Minutes d'écran par jour

  /// Lit les minutes d'usage écrites par l'extension DeviceActivityMonitor
  /// dans l'App Group partagé. Tant que l'extension n'a rien écrit, renvoie 0.
  ///
  /// Format identique à Android : [{ "day": "yyyy-MM-dd", "minutes": Int }, …]
  private func dailyScreenOnMinutes(days: Int) -> [[String: Any]] {
    guard let defaults = defaults else { return [] }

    let cal = Calendar.current
    let fmt = DateFormatter()
    fmt.locale = Locale(identifier: "en_US_POSIX")
    fmt.dateFormat = "yyyy-MM-dd"

    var out: [[String: Any]] = []
    var offset = days - 1
    while offset >= 0 {
      if let date = cal.date(byAdding: .day, value: -offset, to: Date()) {
        let key = fmt.string(from: date)
        let minutes = defaults.integer(forKey: "minutes_\(key)")
        out.append(["day": key, "minutes": minutes])
      }
      offset -= 1
    }
    return out
  }

  // MARK: - Utilitaire UI

  private static func topViewController() -> UIViewController? {
    let scenes = UIApplication.shared.connectedScenes
    let windowScene = scenes.first { $0.activationState == .foregroundActive } as? UIWindowScene
      ?? scenes.first as? UIWindowScene
    guard var top = windowScene?.windows.first(where: { $0.isKeyWindow })?.rootViewController
      ?? windowScene?.windows.first?.rootViewController else { return nil }
    while let presented = top.presentedViewController { top = presented }
    return top
  }
}

#if canImport(FamilyControls)
@available(iOS 16.0, *)
private struct TiipeePickerView: View {
  @State private var selection: FamilyActivitySelection
  let onDone: (FamilyActivitySelection) -> Void
  let onCancel: () -> Void

  init(initial: FamilyActivitySelection,
       onDone: @escaping (FamilyActivitySelection) -> Void,
       onCancel: @escaping () -> Void) {
    _selection = State(initialValue: initial)
    self.onDone = onDone
    self.onCancel = onCancel
  }

  var body: some View {
    NavigationView {
      FamilyActivityPicker(selection: $selection)
        .navigationTitle("Apps à suivre")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button("Annuler") { onCancel() }
          }
          ToolbarItem(placement: .confirmationAction) {
            Button("Terminé") { onDone(selection) }
          }
        }
    }
  }
}
#endif
