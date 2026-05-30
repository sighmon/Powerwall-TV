//
//  PowerwallScheduleManager.swift
//  Powerwall-TV
//

import Foundation
#if canImport(BackgroundTasks) && !os(macOS)
import BackgroundTasks
#endif

@MainActor
final class PowerwallScheduleManager: ObservableObject {
    nonisolated static let backgroundTaskIdentifier = "com.sighmon.Powerwall-TV.schedule-refresh"
    static let shared = PowerwallScheduleManager()

    @Published var schedules: [PowerwallSchedule] {
        didSet {
            PowerwallScheduleStore.saveSchedules(schedules)
            scheduleBackgroundRefresh()
        }
    }
    @Published var isSchedulerEnabled: Bool = UserDefaults.standard.object(forKey: "powerwallSchedulerEnabled") as? Bool ?? false {
        didSet {
            UserDefaults.standard.set(isSchedulerEnabled, forKey: "powerwallSchedulerEnabled")
            scheduleBackgroundRefresh()
        }
    }
    @Published var lastRunStatus: String = UserDefaults.standard.string(forKey: "powerwallScheduleLastRunStatus") ?? "No schedule has run yet"
    @Published var isRunning = false

    private init() {
        schedules = PowerwallScheduleStore.loadSchedules()
    }

    func addSchedule() {
        schedules.append(PowerwallSchedule())
    }

    func deleteSchedules(at offsets: IndexSet) {
        schedules.remove(atOffsets: offsets)
    }

    func deleteSchedule(id: UUID) {
        schedules.removeAll { $0.id == id }
    }

    func update(_ schedule: PowerwallSchedule) {
        guard let index = schedules.firstIndex(where: { $0.id == schedule.id }) else { return }
        schedules[index] = schedule
    }

    func applyDueSchedules(using viewModel: PowerwallViewModel) {
        guard isSchedulerEnabled else { return }

        let dueSchedules = PowerwallScheduleStore.dueSchedules(from: schedules)
        guard !dueSchedules.isEmpty else {
            scheduleBackgroundRefresh()
            return
        }

        run(dueSchedules, index: 0, using: viewModel)
    }

    func scheduleBackgroundRefresh() {
#if canImport(BackgroundTasks) && !os(macOS)
        guard isSchedulerEnabled else {
            if #available(iOS 13.0, tvOS 13.0, *) {
                BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.backgroundTaskIdentifier)
            }
            return
        }

        guard let nextDueDate = PowerwallScheduleStore.nextDueDate(from: schedules) else { return }

        if #available(iOS 13.0, tvOS 13.0, *) {
            let request = BGAppRefreshTaskRequest(identifier: Self.backgroundTaskIdentifier)
            request.earliestBeginDate = nextDueDate
            try? BGTaskScheduler.shared.submit(request)
        }
#endif
    }

#if canImport(BackgroundTasks) && !os(macOS)
    nonisolated static func registerBackgroundTask(viewModel: PowerwallViewModel) {
        if #available(iOS 13.0, tvOS 13.0, *) {
            BGTaskScheduler.shared.register(forTaskWithIdentifier: backgroundTaskIdentifier, using: nil) { task in
                guard let refreshTask = task as? BGAppRefreshTask else {
                    task.setTaskCompleted(success: false)
                    return
                }
                Task { @MainActor in
                    shared.handleBackgroundTask(refreshTask, viewModel: viewModel)
                }
            }
        }
    }

    @available(iOS 13.0, tvOS 13.0, macOS 13.0, *)
    private func handleBackgroundTask(_ task: BGAppRefreshTask, viewModel: PowerwallViewModel) {
        scheduleBackgroundRefresh()
        guard isSchedulerEnabled else {
            task.setTaskCompleted(success: true)
            return
        }

        task.expirationHandler = {
            Task { @MainActor in
                self.isRunning = false
            }
        }

        let dueSchedules = PowerwallScheduleStore.dueSchedules(from: schedules)
        guard !dueSchedules.isEmpty else {
            task.setTaskCompleted(success: true)
            return
        }

        run(dueSchedules, index: 0, using: viewModel) { success in
            task.setTaskCompleted(success: success)
        }
    }
#endif

    private func run(
        _ dueSchedules: [DuePowerwallSchedule],
        index: Int,
        using viewModel: PowerwallViewModel,
        completion: ((Bool) -> Void)? = nil
    ) {
        guard index < dueSchedules.count else {
            isRunning = false
            scheduleBackgroundRefresh()
            completion?(true)
            return
        }

        isRunning = true
        let dueSchedule = dueSchedules[index]
        viewModel.setPowerwallOperationMode(dueSchedule.mode) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }

                switch result {
                case .success:
                    PowerwallScheduleStore.markApplied(dueSchedule)
                    self.setLastRunStatus("\(dueSchedule.schedule.name) \(dueSchedule.boundary.title): \(dueSchedule.mode.title)")
                    self.run(dueSchedules, index: index + 1, using: viewModel, completion: completion)
                case .failure(let error):
                    self.isRunning = false
                    self.setLastRunStatus("Failed \(dueSchedule.schedule.name): \(error.localizedDescription)")
                    self.scheduleBackgroundRefresh()
                    completion?(false)
                }
            }
        }
    }

    private func setLastRunStatus(_ status: String) {
        lastRunStatus = status
        UserDefaults.standard.set(status, forKey: "powerwallScheduleLastRunStatus")
    }
}
