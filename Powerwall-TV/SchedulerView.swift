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
        NavigationStack {
            List {
                Section {
                    Toggle("Scheduler Active", isOn: $scheduleManager.isSchedulerEnabled)
                    Text(scheduleManager.isSchedulerEnabled ? "Schedules will run automatically." : "Schedules are saved but will not run.")
                        .foregroundStyle(.secondary)
                    Button {
                        scheduleManager.addSchedule()
                    } label: {
                        Label("Add Schedule", systemImage: "plus")
                    }
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
            .onAppear {
                scheduleManager.scheduleBackgroundRefresh()
            }
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
            .frame(width: 90)
#endif
            Picker("Minute", selection: minuteBinding) {
                ForEach(stride(from: 0, through: 55, by: 5).map { $0 }, id: \.self) { minute in
                    Text(String(format: "%02d", minute)).tag(minute)
                }
            }
#if os(tvOS)
            .pickerStyle(.navigationLink)
#else
            .frame(width: 90)
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
