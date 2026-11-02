//
//  SchedulerView.swift
//  Powerwall-TV
//

import SwiftUI

struct SchedulerView: View {
    @ObservedObject var viewModel: PowerwallViewModel
    @ObservedObject private var scheduleManager = PowerwallScheduleManager.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
#if !os(tvOS)
            Rectangle().fill(.background)
                .ignoresSafeArea()
            LinearGradient(colors: [.blue.opacity(0.12), .cyan.opacity(0.06), .purple.opacity(0.10)], startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()
#endif
            VStack(spacing: 20) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Scheduler").font(.title2.weight(.semibold))
                        Text("Change modes while you're away.").font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        scheduleManager.addSchedule()
                    } label: {
                        Label("Add Schedule", systemImage: "plus")
                    }
                    .buttonStyle(.bordered)
                    Button("Done") { dismiss() }
                        .buttonStyle(.borderedProminent)
#if !os(tvOS)
                        .keyboardShortcut(.defaultAction)
#endif
                }
                .padding(.horizontal, 24)
                formContent
            }
            .padding(.top, 24)
#if os(tvOS)
            .frame(maxWidth: 1400)
#endif
        }
#if os(iOS)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
#endif
#if os(macOS)
        .frame(minWidth: 580, idealWidth: 660, minHeight: 580, idealHeight: 740)
#endif
        .onAppear {
            scheduleManager.scheduleBackgroundRefresh()
        }
    }

    private func settingsCard<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title).font(.headline)
            VStack(alignment: .leading, spacing: 16, content: content)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(22)
        .modifier(AdvisorGlassCard(cornerRadius: 24))
    }

    private var formContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                settingsCard("Scheduler") {
                    schedulerControls
                }

                if scheduleManager.schedules.isEmpty {
                    settingsCard("Schedules") {
                        Text("No schedules")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Button {
                            scheduleManager.addSchedule()
                        } label: {
                            Label("Create Schedule", systemImage: "calendar.badge.plus")
                        }
                    }
                } else {
                    ForEach(scheduleManager.schedules) { schedule in
                        settingsCard(schedule.name.isEmpty ? "Schedule" : schedule.name) {
                            PowerwallScheduleRow(schedule: binding(for: schedule), sites: scheduleSites)
                            Button(role: .destructive) {
                                scheduleManager.deleteSchedule(id: schedule.id)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            .accessibilityLabel("Delete Schedule")
                        }
                    }
                }

                settingsCard("Run") {
                    runControls
                }
            }
#if !os(tvOS)
            .textFieldStyle(.roundedBorder)
#endif
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
#if os(tvOS)
            .frame(maxWidth: 1400)
#else
            .frame(maxWidth: 800)
#endif
            .frame(maxWidth: .infinity)
        }
    }

    private func binding(for schedule: PowerwallSchedule) -> Binding<PowerwallSchedule> {
        Binding {
            scheduleManager.schedules.first { $0.id == schedule.id } ?? schedule
        } set: { updatedSchedule in
            scheduleManager.update(updatedSchedule)
        }
    }

    private var scheduleSites: [ScheduleSiteOption] {
        viewModel.energySites.compactMap { product in
            guard let id = product.energySiteId.map(String.init) else { return nil }
            return ScheduleSiteOption(
                id: id,
                name: product.energySiteDisplayName
                    ?? (id == viewModel.energySiteId ? viewModel.siteName : nil)
                    ?? "Energy Site \(id)"
            )
        }
    }

    private var schedulerControls: some View {
        VStack(alignment: .leading, spacing: 16) {
            Toggle("Scheduler Active", isOn: $scheduleManager.isSchedulerEnabled)
            Text(scheduleManager.isSchedulerEnabled ? "Schedules will run automatically." : "Schedules are saved but will not run.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var runControls: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let warning = viewModel.fleetCommandPermissionWarning {
                Text(warning)
                    .font(.footnote)
                    .foregroundStyle(.orange)
                Button {
                    _ = viewModel.startFleetLoginManually()
                } label: {
                    Label("Re-login with Tesla", systemImage: "person.crop.circle.badge.exclamationmark")
                }
            }
            Button {
                scheduleManager.applyDueSchedules(using: viewModel)
            } label: {
                if scheduleManager.isRunning {
                    ProgressView()
                } else {
                    Label("Run Due Schedules", systemImage: "bolt.badge.clock")
                }
            }
            Text(scheduleManager.lastRunStatus)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

private struct PowerwallScheduleRow: View {
    @Binding var schedule: PowerwallSchedule
    let sites: [ScheduleSiteOption]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Name").font(.caption.weight(.medium)).foregroundStyle(.secondary)
            TextField("Name", text: $schedule.name)
            Toggle("Schedule Enabled", isOn: enabledBinding)
                .disabled(schedule.energySiteId == nil)

            ScheduleSitePicker(schedule: $schedule, sites: sites)

            if schedule.energySiteId == nil {
                Text("Select a home before enabling this schedule.")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }

            ScheduleModePicker(title: "Start Mode", mode: $schedule.startMode)

            ScheduleTimePicker(title: "Start", minutes: $schedule.startMinutes)

            ScheduleModePicker(title: "End Mode", mode: $schedule.endMode)

            ScheduleTimePicker(title: "End", minutes: $schedule.endMinutes)

            Text(scheduleSummary)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var scheduleSummary: String {
        let site = schedule.energySiteName.map { " at \($0)" } ?? ""
        return "Schedule\(site): \(schedule.startMode.title) for \(durationSummary) then \(schedule.endMode.title)"
    }

    private var enabledBinding: Binding<Bool> {
        Binding {
            schedule.energySiteId != nil && schedule.isEnabled
        } set: { isEnabled in
            schedule.isEnabled = isEnabled && schedule.energySiteId != nil
        }
    }

    private var durationSummary: String {
        let minutesPerDay = 24 * 60
        let rawDuration = (schedule.endMinutes - schedule.startMinutes + minutesPerDay) % minutesPerDay
        let duration = rawDuration == 0 ? minutesPerDay : rawDuration
        let hours = duration / 60
        let minutes = duration % 60

        if hours == 0 {
            return pluralized(minutes, singular: "minute")
        }

        if minutes == 0 {
            return pluralized(hours, singular: "hour")
        }

        return "\(pluralized(hours, singular: "hour")) \(pluralized(minutes, singular: "minute"))"
    }

    private func pluralized(_ value: Int, singular: String) -> String {
        "\(value) \(singular)\(value == 1 ? "" : "s")"
    }
}

private struct ScheduleSiteOption: Identifiable, Hashable {
    let id: String
    let name: String

    var title: String { "\(name) (\(id))" }
}

private struct ScheduleSitePicker: View {
    @Binding var schedule: PowerwallSchedule
    let sites: [ScheduleSiteOption]

    var body: some View {
        Picker("Home", selection: selection) {
                Text("Select Home").tag(String?.none)
                ForEach(availableSites) { site in
                    Text(site.title).tag(Optional(site.id))
                }
            }
#if os(tvOS)
            .pickerStyle(.navigationLink)
#else
            .pickerStyle(.menu)
#endif
    }

    private var selection: Binding<String?> {
        Binding {
            schedule.energySiteId
        } set: { selectedId in
            schedule.energySiteId = selectedId
            schedule.energySiteName = availableSites.first { $0.id == selectedId }?.name
            if selectedId == nil {
                schedule.isEnabled = false
            }
        }
    }

    private var availableSites: [ScheduleSiteOption] {
        guard let selectedId = schedule.energySiteId,
              !sites.contains(where: { $0.id == selectedId }) else {
            return sites
        }

        return sites + [ScheduleSiteOption(
            id: selectedId,
            name: schedule.energySiteName ?? "Energy Site \(selectedId)"
        )]
    }
}

private struct ScheduleModePicker: View {
    let title: String
    @Binding var mode: PowerwallOperationMode

    var body: some View {
        Picker(title, selection: $mode) {
                ForEach(PowerwallOperationMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
#if os(tvOS)
            .pickerStyle(.navigationLink)
#else
            .pickerStyle(.menu)
#endif
    }
}

private struct ScheduleTimePicker: View {
    let title: String
    @Binding var minutes: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption.weight(.medium)).foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Picker("Hour", selection: hourBinding) {
                    ForEach(0..<24, id: \.self) { hour in
                        Text(String(format: "%02d", hour)).tag(hour)
                    }
                }
#if os(tvOS)
                .pickerStyle(.navigationLink)
#elseif os(iOS)
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 70)
#else
                .frame(minWidth: 110)
#endif
                Picker("Minute", selection: minuteBinding) {
                    ForEach(stride(from: 0, through: 55, by: 5).map { $0 }, id: \.self) { minute in
                        Text(String(format: "%02d", minute)).tag(minute)
                    }
                }
#if os(tvOS)
                .pickerStyle(.navigationLink)
#elseif os(iOS)
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 70)
#else
                .frame(minWidth: 110)
#endif
            }
        }
    }

    private var hourBinding: Binding<Int> {
        Binding {
            minutes / 60
        } set: { newHour in
            minutes = (newHour * 60) + (minutes % 60)
        }
    }

    private var minuteBinding: Binding<Int> {
        Binding {
            (minutes % 60) / 5 * 5
        } set: { newMinute in
            minutes = ((minutes / 60) * 60) + newMinute
        }
    }
}

#Preview {
    SchedulerView(viewModel: PowerwallViewModel())
}
