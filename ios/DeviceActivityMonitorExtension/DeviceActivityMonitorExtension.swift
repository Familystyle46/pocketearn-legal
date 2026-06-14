//
//  DeviceActivityMonitorExtension.swift
//  Tiipee — mesure du temps d'écran iOS (additif, ne touche pas Android).
//
//  Apple interdit de lire le total d'usage directement depuis l'app. On pose
//  donc une série de seuils (DeviceActivityEvent) : chaque fois qu'un seuil de
//  N minutes d'usage est atteint, iOS réveille cette extension, qui écrit
//  "N minutes atteintes aujourd'hui" dans l'App Group partagé. Le plugin de
//  l'app lit ensuite la valeur max → temps d'écran du jour.
//

import DeviceActivity
import Foundation

class DeviceActivityMonitorExtension: DeviceActivityMonitor {

    /// Doit correspondre EXACTEMENT à l'App Group de l'app et de l'extension.
    static let appGroup = "group.com.tiipee.tiipee"

    private var defaults: UserDefaults? {
        UserDefaults(suiteName: Self.appGroup)
    }

    /// Clé "minutes_yyyy-MM-dd" pour le jour courant (référentiel local),
    /// identique à ce que lit ScreenTimePlugin côté app.
    private func todayKey() -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyy-MM-dd"
        return "minutes_\(fmt.string(from: Date()))"
    }

    // Le nom d'événement est "threshold_<minutes>" (cf. ScreenTimePlugin).
    private func minutes(from event: DeviceActivityEvent.Name) -> Int? {
        let raw = event.rawValue
        guard raw.hasPrefix("threshold_") else { return nil }
        return Int(raw.dropFirst("threshold_".count))
    }

    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        // Nouveau jour : on repart de zéro pour aujourd'hui.
        defaults?.set(0, forKey: todayKey())
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
    }

    override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name,
                                         activity: DeviceActivityName) {
        super.eventDidReachThreshold(event, activity: activity)
        guard let reached = minutes(from: event), let defaults = defaults else { return }
        let key = todayKey()
        // On ne garde que le maximum atteint (les seuils arrivent dans l'ordre).
        let current = defaults.integer(forKey: key)
        if reached > current {
            defaults.set(reached, forKey: key)
        }
    }
}
