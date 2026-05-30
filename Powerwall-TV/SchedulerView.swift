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
        Group {
#if os(macOS)
            macOSBody
#else
            navigationBody
#endif
        }
        .onAppear {
            scheduleManager.scheduleBackgroundRefresh()
        }
    }

    private var navigationBody: some View {
        NavigationStack {
            List {
                Section {
                    schedulerControls
                }

                Section {
                    if scheduleManager.schedules.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("No schedules")
                                .foregroundStyle(.secondary)
                            Button {
                                scheduleManager.addSchedule()
                            } label: {
                                Label("Create Schedule", systemImage: "calendar.badge.plus")
                            }
                        }
                        .padding(.vertical, 6)
                    } else {
                        ForEach($scheduleManager.schedules) { $schedule in
                            PowerwallScheduleRow(schedule: $schedule)
                        }
                        .onDelete(perform: scheduleManager.deleteSchedules)
                    }
                } header: {
                    Text("Schedules")
                }

                Section {
                    if let warning = viewModel.fleetCommandPermissionWarning {
                        Text(warning)
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
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Powerwall Scheduler")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        scheduleManager.addSchedule()
                    } label: {
                        Label("Add Schedule", systemImage: "plus")
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

#if os(macOS)
    private var macOSBody: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Powerwall Scheduler")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Button {
                    scheduleManager.addSchedule()
                } label: {
                    Label("Add Schedule", systemImage: "plus")
                }
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 10) {
                            schedulerControls
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    GroupBox("Schedules") {
                        VStack(alignment: .leading, spacing: 14) {
                            if scheduleManager.schedules.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("No schedules")
                                        .foregroundStyle(.secondary)
                                    Button {
                                        scheduleManager.addSchedule()
                                    } label: {
                                        Label("Create Schedule", systemImage: "calendar.badge.plus")
                                    }
                                }
                            } else {
                                ForEach($scheduleManager.schedules) { $schedule in
                                    VStack(alignment: .leading, spacing: 8) {
                                        HStack(alignment: .top) {
                                            PowerwallScheduleRow(schedule: $schedule)
                                            Button {
                                                scheduleManager.deleteSchedule(id: schedule.id)
                                            } label: {
                                                Image(systemName: "trash")
                                            }
                                            .buttonStyle(.borderless)
                                            .accessibilityLabel("Delete Schedule")
                                        }
                                        if schedule.id != scheduleManager.schedules.last?.id {
                                            Divider()
                                        }
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    GroupBox {
                        VStack(alignment: .leading, spacing: 10) {
                            runControls
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding()
            }
        }
        .frame(minWidth: 680, idealWidth: 760, minHeight: 560, idealHeight: 680)
    }
#endif

    private var schedulerControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Scheduler Active", isOn: $scheduleManager.isSchedulerEnabled)
            Text(scheduleManager.isSchedulerEnabled ? "Schedules will run automatically." : "Schedules are saved but will not run.")
                .foregroundStyle(.secondary)
            Button {
                scheduleManager.addSchedule()
            } label: {
                Label("Add Schedule", systemImage: "plus")
            }
        }
    }

    private var runControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let warning = viewModel.fleetCommandPermissionWarning {
                Text(warning)
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
                .foregroundStyle(.secondary)
        }
    }
}

private struct PowerwallScheduleRow: View {
    @Binding var schedule: PowerwallSchedule

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                TextField("Name", text: $schedule.name)
                Toggle("Schedule Enabled", isOn: $schedule.isEnabled)
            }

            Picker("Start Mode", selection: $schedule.startMode) {
                ForEach(PowerwallOperationMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }

            ScheduleTimePicker(title: "Start", minutes: $schedule.startMinutes)

            Picker("End Mode", selection: $schedule.endMode) {
                ForEach(PowerwallOperationMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }

            ScheduleTimePicker(title: "End", minutes: $schedule.endMinutes)
        }
        .padding(.vertical, 6)
    }
}

private struct ScheduleTimePicker: View {
    let title: String
    @Binding var minutes: Int

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Picker("Hour", selection: hourBinding) {
                ForEach(0..<24, id: \.self) { hour in
                    Text(String(format: "%02d", hour)).tag(hour)
                }
            }
#if os(tvOS)
            .pickerStyle(.navigationLink)
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
#else
            .frame(minWidth: 110)
#endif
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
