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

  /// Seuils d'usage (minutes) surveillés. UN `DeviceActivityEvent` par seuil,
  /// et iOS limite fortement le nombre d'événements par activité (les grandes
  /// listes font échouer `startMonitoring`). On garde donc une liste courte :
  /// fine au début (retour rapide pour le test + faible usage), grossière
  /// ensuite. L'extension écrit le max de seuil atteint → minutes du jour.
  static let thresholdsMinutes: [Int] = [
    1, 2, 3, 4, 5, 10, 15, 20, 25, 30, 40, 50, 60,
    75, 90, 105, 120, 150, 180, 210, 240, 300, 360, 420, 480,
  ]

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
      result(hasValidSelection())
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

  // MARK: - Helpers sélection

  /// Charge la sélection enregistrée (ou nil).
  #if canImport(FamilyControls)
  @available(iOS 16.0, *)
  private func loadSelection() -> FamilyActivitySelection? {
    guard let data = defaults?.data(forKey: ScreenTimePlugin.selectionKey),
          let decoded = try? PropertyListDecoder().decode(FamilyActivitySelection.self, from: data)
    else { return nil }
    return decoded
  }

  @available(iOS 16.0, *)
  private func selectionHasTokens(_ s: FamilyActivitySelection) -> Bool {
    return !(s.applicationTokens.isEmpty
      && s.categoryTokens.isEmpty
      && s.webDomainTokens.isEmpty)
  }
  #endif

  /// Vrai seulement si une sélection AVEC jetons existe. La case « Toutes les
  /// apps » du picker ne renvoie aucun jeton → considérée comme vide.
  private func hasValidSelection() -> Bool {
    #if canImport(FamilyControls)
    if #available(iOS 16.0, *) {
      if let s = loadSelection() { return selectionHasTokens(s) }
    }
    #endif
    return false
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
        let initial = self.loadSelection() ?? FamilyActivitySelection()

        var responded = false
        func respondOnce(_ value: Int) {
          if responded { return }
          responded = true
          result(value)
        }

        let view = TiipeePickerView(
          initial: initial,
          // Sauvegarde À CHAQUE changement (et pas seulement au bouton) : on ne
          // perd jamais la sélection, quelle que soit la façon dont le picker
          // se ferme. On n'enregistre que si des jetons réels sont présents
          // (la case « Toutes les apps » du haut n'en renvoie aucun).
          onChange: { selection in
            let count = selection.applicationTokens.count
              + selection.categoryTokens.count
              + selection.webDomainTokens.count
            if count > 0, let encoded = try? PropertyListEncoder().encode(selection) {
              self.defaults?.set(encoded, forKey: ScreenTimePlugin.selectionKey)
              self.defaults?.removeObject(forKey: "lastError")
            }
          },
          onClose: { selection in
            root.dismiss(animated: true)
            // Persiste la sélection finale (autoritaire) si elle a des jetons,
            // sans dépendre de l'ordre des onChange SwiftUI.
            let count = selection.applicationTokens.count
              + selection.categoryTokens.count
              + selection.webDomainTokens.count
            if count > 0, let encoded = try? PropertyListEncoder().encode(selection) {
              self.defaults?.set(encoded, forKey: ScreenTimePlugin.selectionKey)
              self.defaults?.removeObject(forKey: "lastError")
            }
            if self.hasValidSelection() {
              _ = self.startMonitoring(forceRestart: true)
              respondOnce(1)
            } else {
              self.defaults?.set(
                "Sélection vide : ne coche pas « Toutes les apps » tout en haut, "
                  + "choisis les catégories une par une.",
                forKey: "lastError")
              respondOnce(-2)
            }
          }
        )
        let host = UIHostingController(rootView: view)
        host.modalPresentationStyle = .overFullScreen
        host.view.backgroundColor = .clear
        root.present(host, animated: false)
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

      guard let selection = loadSelection() else {
        defaults?.set("startMonitoring: aucune sélection enregistrée", forKey: "lastError")
        return false
      }

      // Aucun jeton (ex. case « Toutes les apps ») → rien à mesurer.
      if !selectionHasTokens(selection) {
        defaults?.set(
          "Sélection vide : choisis les catégories une par une (pas la case du haut).",
          forKey: "lastError")
        return false
      }

      let schedule = DeviceActivitySchedule(
        intervalStart: DateComponents(hour: 0, minute: 0),
        intervalEnd: DateComponents(hour: 23, minute: 59),
        repeats: true
      )

      var events: [DeviceActivityEvent.Name: DeviceActivityEvent] = [:]
      for m in ScreenTimePlugin.thresholdsMinutes {
        let name = DeviceActivityEvent.Name("threshold_\(m)")
        events[name] = DeviceActivityEvent(
          applications: selection.applicationTokens,
          categories: selection.categoryTokens,
          webDomains: selection.webDomainTokens,
          threshold: DateComponents(minute: m)
        )
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
      "hasSelection": hasValidSelection(),
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
  @State private var isPresented = false
  let onChange: (FamilyActivitySelection) -> Void
  let onClose: (FamilyActivitySelection) -> Void

  init(initial: FamilyActivitySelection,
       onChange: @escaping (FamilyActivitySelection) -> Void,
       onClose: @escaping (FamilyActivitySelection) -> Void) {
    _selection = State(initialValue: initial)
    self.onChange = onChange
    self.onClose = onClose
  }

  // Présentation via le MODIFIER officiel `.familyActivityPicker` (fiable pour
  // remonter la sélection), au lieu d'instancier `FamilyActivityPicker` à la
  // main (binding parfois non propagé en présentation impérative). La sélection
  // est persistée à chaque changement via `onChange`.
  var body: some View {
    Color.clear
      .familyActivityPicker(isPresented: $isPresented, selection: $selection)
      .onAppear { isPresented = true }
      .onChange(of: selection) { newValue in
        onChange(newValue)
      }
      .onChange(of: isPresented) { presented in
        if !presented { onClose(selection) }
      }
  }
}
#endif
