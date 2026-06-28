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
    case "getDiagnostics":
      result(diagnostics())

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
          // Nouvelle sélection → on force le redémarrage du monitoring.
          _ = self.startMonitoring(forceRestart: true)
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

  /// Démarre le monitoring. IDEMPOTENT par défaut : si l'activité tourne déjà,
  /// on ne fait RIEN (sinon `stopMonitoring`+`startMonitoring` relancent
  /// l'intervalle → `intervalDidStart` remet les minutes du jour à 0 et le
  /// comptage des seuils repart de zéro). Comme `startMonitoring` est appelé à
  /// chaque ouverture de l'app, sans cette garde le simple fait d'ouvrir Tiipee
  /// effaçait la mesure. On ne force le redémarrage (`forceRestart`) que lorsque
  /// l'utilisateur choisit une nouvelle sélection d'apps.
  private func startMonitoring(forceRestart: Bool = false) -> Bool {
    #if canImport(FamilyControls)
    if #available(iOS 16.0, *) {
      let center = DeviceActivityCenter()
      let activity = DeviceActivityName(ScreenTimePlugin.activityName)

      // Déjà en cours et pas de nouvelle sélection → ne rien réinitialiser.
      if !forceRestart && center.activities.contains(activity) {
        defaults?.removeObject(forKey: "lastError")
        return true
      }

      guard let data = defaults?.data(forKey: ScreenTimePlugin.selectionKey),
            let selection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data)
      else {
        defaults?.set("startMonitoring: aucune sélection enregistrée", forKey: "lastError")
        return false
      }

      // Aucune cible sélectionnée → rien à mesurer.
      if selection.applicationTokens.isEmpty
        && selection.categoryTokens.isEmpty
        && selection.webDomainTokens.isEmpty {
        defaults?.set("startMonitoring: sélection vide", forKey: "lastError")
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

      center.stopMonitoring([activity])
      do {
        try center.startMonitoring(activity, during: schedule, events: events)
        defaults?.removeObject(forKey: "lastError")
        return true
      } catch {
        // Surfacé dans le panneau de diagnostic côté app.
        defaults?.set("startMonitoring: \(error)", forKey: "lastError")
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

  // MARK: - Diagnostic (panneau côté app)

  /// Renvoie l'état réel du pipeline Family Controls pour affichage/diagnostic.
  /// { authorized, authStatus, hasSelection, monitoring, todayMinutes, lastError }
  private func diagnostics() -> [String: Any] {
    var monitoring = false
    var authStatus = "unavailable"
    #if canImport(FamilyControls)
    if #available(iOS 16.0, *) {
      monitoring = DeviceActivityCenter().activities
        .contains(DeviceActivityName(ScreenTimePlugin.activityName))
      switch AuthorizationCenter.shared.authorizationStatus {
      case .approved:      authStatus = "approved"
      case .denied:        authStatus = "denied"
      case .notDetermined: authStatus = "notDetermined"
      @unknown default:    authStatus = "unknown"
      }
    }
    #endif
    let todayMinutes = defaults?.integer(forKey: todayMinutesKey()) ?? 0
    return [
      "authorized": authorizationApproved(),
      "authStatus": authStatus,
      "hasSelection": defaults?.data(forKey: ScreenTimePlugin.selectionKey) != nil,
      "monitoring": monitoring,
      "todayMinutes": todayMinutes,
      "lastError": defaults?.string(forKey: "lastError") ?? "",
    ]
  }

  /// Clé "minutes_yyyy-MM-dd" du jour courant (identique à l'extension).
  private func todayMinutesKey() -> String {
    let fmt = DateFormatter()
    fmt.locale = Locale(identifier: "en_US_POSIX")
    fmt.dateFormat = "yyyy-MM-dd"
    return "minutes_\(fmt.string(from: Date()))"
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
