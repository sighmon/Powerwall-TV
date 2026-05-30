//
//  PowerwallSchedule.swift
//  Powerwall-TV
//

import Foundation

enum PowerwallOperationMode: String, Codable, CaseIterable, Identifiable {
    case selfPowered
    case timeBasedControl
    case offGrid
    case onGrid

    var id: String { rawValue }

    var title: String {
        switch self {
        case .selfPowered:
            return "Self-Powered"
        case .timeBasedControl:
            return "Time-Based Control"
        case .offGrid:
            return "Off-Grid"
        case .onGrid:
            return "On-Grid"
        }
    }

    var fleetOperationValue: String? {
        switch self {
        case .selfPowered:
            return "self_consumption"
        case .timeBasedControl:
            return "autonomous"
        case .offGrid, .onGrid:
            return nil
        }
    }

    var islandModeValue: String? {
        switch self {
        case .offGrid:
            return "intentional_reconnect_failsafe"
        case .onGrid:
            return "backup"
        case .selfPowered, .timeBasedControl:
            return nil
        }
    }
}

struct PowerwallSchedule: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var isEnabled: Bool
    var startMinutes: Int
    var endMinutes: Int
    var startMode: PowerwallOperationMode
    var endMode: PowerwallOperationMode

    init(
        id: UUID = UUID(),
        name: String = "Peak export",
        isEnabled: Bool = true,
        startMinutes: Int = 15 * 60,
        endMinutes: Int = 21 * 60,
        startMode: PowerwallOperationMode = .timeBasedControl,
        endMode: PowerwallOperationMode = .selfPowered
    ) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.startMinutes = startMinutes
        self.endMinutes = endMinutes
        self.startMode = startMode
        self.endMode = endMode
    }
}

enum PowerwallScheduleBoundary: String {
    case start
    case end

    var title: String {
        switch self {
        case .start:
            return "start"
        case .end:
            return "end"
        }
    }
}

struct DuePowerwallSchedule {
    let schedule: PowerwallSchedule
    let boundary: PowerwallScheduleBoundary
    let mode: PowerwallOperationMode
    let dueDate: Date
    let key: String
}

enum PowerwallScheduleStore {
    static let schedulesKey = "powerwallModeSchedules"
    static let lastAppliedPrefix = "powerwallModeScheduleLastApplied."

    static func loadSchedules() -> [PowerwallSchedule] {
        guard let data = UserDefaults.standard.data(forKey: schedulesKey),
              let schedules = try? JSONDecoder().decode([PowerwallSchedule].self, from: data) else {
            return []
        }
        return schedules
    }

    static func saveSchedules(_ schedules: [PowerwallSchedule]) {
        guard let data = try? JSONEncoder().encode(schedules) else { return }
        UserDefaults.standard.set(data, forKey: schedulesKey)
    }

    static func dueSchedules(
        from schedules: [PowerwallSchedule],
        now: Date = Date(),
        calendar: Calendar = .current,
        userDefaults: UserDefaults = .standard
    ) -> [DuePowerwallSchedule] {
        schedules
            .filter(\.isEnabled)
            .flatMap { schedule in
                dueBoundaries(for: schedule, now: now, calendar: calendar, userDefaults: userDefaults)
            }
            .sorted { $0.dueDate < $1.dueDate }
    }

    static func markApplied(_ dueSchedule: DuePowerwallSchedule, userDefaults: UserDefaults = .standard) {
        userDefaults.set(dueSchedule.key, forKey: lastAppliedKey(for: dueSchedule.schedule, boundary: dueSchedule.boundary))
    }

    static func nextDueDate(
        from schedules: [PowerwallSchedule],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Date? {
        let enabled = schedules.filter(\.isEnabled)
        guard !enabled.isEmpty else { return nil }

        return enabled
            .flatMap { schedule in
                [
                    nextDate(forMinutes: schedule.startMinutes, after: now, calendar: calendar),
                    nextDate(forMinutes: schedule.endMinutes, after: now, calendar: calendar)
                ]
            }
            .compactMap { $0 }
            .min()
    }

    private static func dueBoundaries(
        for schedule: PowerwallSchedule,
        now: Date,
        calendar: Calendar,
        userDefaults: UserDefaults
    ) -> [DuePowerwallSchedule] {
        let candidates: [(PowerwallScheduleBoundary, Int, PowerwallOperationMode)] = [
            (.start, schedule.startMinutes, schedule.startMode),
            (.end, schedule.endMinutes, schedule.endMode)
        ]

        return candidates.compactMap { boundary, minutes, mode in
            guard let dueDate = mostRecentDate(forMinutes: minutes, beforeOrEqualTo: now, calendar: calendar) else {
                return nil
            }

            let key = appliedKey(schedule: schedule, boundary: boundary, dueDate: dueDate, calendar: calendar)
            let storedKey = userDefaults.string(forKey: lastAppliedKey(for: schedule, boundary: boundary))
            guard storedKey != key else { return nil }

            return DuePowerwallSchedule(
                schedule: schedule,
                boundary: boundary,
                mode: mode,
                dueDate: dueDate,
                key: key
            )
        }
    }

    private static func mostRecentDate(forMinutes minutes: Int, beforeOrEqualTo now: Date, calendar: Calendar) -> Date? {
        let today = date(forMinutes: minutes, on: now, calendar: calendar)
        if let today, today <= now {
            return today
        }

        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: now) else { return nil }
        return date(forMinutes: minutes, on: yesterday, calendar: calendar)
    }

    private static func nextDate(forMinutes minutes: Int, after now: Date, calendar: Calendar) -> Date? {
        guard let today = date(forMinutes: minutes, on: now, calendar: calendar) else { return nil }
        if today > now {
            return today
        }
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) else { return nil }
        return date(forMinutes: minutes, on: tomorrow, calendar: calendar)
    }

    private static func date(forMinutes minutes: Int, on date: Date, calendar: Calendar) -> Date? {
        let startOfDay = calendar.startOfDay(for: date)
        return calendar.date(byAdding: .minute, value: minutes, to: startOfDay)
    }

    private static func appliedKey(schedule: PowerwallSchedule, boundary: PowerwallScheduleBoundary, dueDate: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: dueDate)
        let year = components.year ?? 0
        let month = components.month ?? 0
        let day = components.day ?? 0
        return "\(schedule.id.uuidString).\(boundary.rawValue).\(year)-\(month)-\(day)"
    }

    private static func lastAppliedKey(for schedule: PowerwallSchedule, boundary: PowerwallScheduleBoundary) -> String {
        "\(lastAppliedPrefix)\(schedule.id.uuidString).\(boundary.rawValue)"
    }
}
