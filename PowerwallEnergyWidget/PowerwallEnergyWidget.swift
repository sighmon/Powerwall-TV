#if os(iOS) || os(macOS)
import SwiftUI
import WidgetKit
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct EnergyWidgetEntry: TimelineEntry {
    var date: Date
    var snapshot: EnergyWidgetSnapshot
}

struct EnergyWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> EnergyWidgetEntry {
        let snapshot = EnergyWidgetTimeline.entry(
            solarWatts: 4200,
            homeWatts: 1800,
            batteryWatts: -600,
            gridWatts: 900,
            siteName: "Home",
            batteryPercent: 72
        )
        return EnergyWidgetEntry(date: snapshot.date, snapshot: snapshot)
    }

    func getSnapshot(in context: Context, completion: @escaping (EnergyWidgetEntry) -> Void) {
        completion(currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<EnergyWidgetEntry>) -> Void) {
        let entry = currentEntry()
        let next = Date().addingTimeInterval(15 * 60)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func currentEntry() -> EnergyWidgetEntry {
        let reading = EnergyWidgetStore.load() ?? .empty
        let snapshot = EnergyWidgetTimeline.entry(for: reading)
        return EnergyWidgetEntry(date: snapshot.date, snapshot: snapshot)
    }
}

struct EnergyWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: EnergyWidgetEntry

    private var compact: Bool { family == .systemSmall }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 10) {
            Text(entry.snapshot.siteName)
                .font(compact ? .title3.weight(.bold) : .title2.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if compact {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                    GridRow {
                        rowLabel("SOLAR")
                        rowValue(Text(power(entry.snapshot.solarWatts, formatted: entry.snapshot.solar)))
                    }
                    GridRow {
                        rowLabel("HOME")
                        rowValue(Text(power(entry.snapshot.homeWatts, formatted: entry.snapshot.home)))
                    }
                    GridRow {
                        rowLabel("BATTERY")
                        smallBatteryValue
                    }
                    GridRow {
                        rowLabel("GRID")
                        rowValue(Text(power(entry.snapshot.gridWatts, formatted: entry.snapshot.grid)))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(alignment: .top, spacing: 16) {
                    metric(power(entry.snapshot.solarWatts, formatted: entry.snapshot.solar), label: "SOLAR", alignment: .leading)
                    metric(power(entry.snapshot.homeWatts, formatted: entry.snapshot.home), label: "HOME", alignment: .trailing)
                }
                HStack(alignment: .top, spacing: 16) {
                    batteryMetric
                    metric(power(entry.snapshot.gridWatts, formatted: entry.snapshot.grid), label: "GRID", alignment: .trailing)
                }
            }
        }
        .foregroundStyle(Color.white)
        .compositingGroup()
        .shadow(color: .black.opacity(0.9), radius: 1, y: 1)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .environment(\.colorScheme, .dark)
        .containerBackground(for: .widget) {
            EnergyWidgetHomeBackground(opacity: compact ? 0.8 : 1)
        }
    }

    /// The small widget always uses one decimal place. Medium follows the Display setting.
    private func power(_ watts: Double?, formatted: String) -> String {
        compact ? EnergyWidgetSnapshot.oneDecimalPowerText(watts) : formatted
    }

    private func rowLabel(_ label: String) -> some View {
        Text(label)
            .font(.caption2.weight(.bold))
            .opacity(0.6)
            .lineLimit(1)
    }

    private func rowValue(_ value: Text) -> some View {
        value
            .font(.caption.weight(.bold))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }

    private var batteryValue: Text {
        let mark = entry.snapshot.batteryMark
        var value = Text(power(entry.snapshot.batteryWatts, formatted: entry.snapshot.battery))
        if !mark.isEmpty {
            value = value + Text(" \(mark)")
                .foregroundColor(mark == "·" ? Color.white : Color.green)
        }
        if let percent = entry.snapshot.batteryPercent {
            value = value + Text(" \(percent)")
        }
        return value
    }

    /// The kilowatts and trend mark stay at full size. Only the percentage shrinks to fit the row.
    private var smallBatteryValue: some View {
        let mark = entry.snapshot.batteryMark
        return HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(power(entry.snapshot.batteryWatts, formatted: entry.snapshot.battery))
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(1)
            if !mark.isEmpty {
                Text(" \(mark)")
                    .foregroundColor(mark == "·" ? Color.white : Color.green)
                    .fixedSize(horizontal: true, vertical: false)
                    .layoutPriority(1)
            }
            if let percent = entry.snapshot.batteryPercent {
                Text(" \(percent)")
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
        .font(.caption.weight(.bold))
        .monospacedDigit()
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Bold figure over a dim label, matching the menu bar dropdown.
    private func metric(_ value: String, label: String, alignment: HorizontalAlignment) -> some View {
        metricStack(value: Text(value), label: label, alignment: alignment)
    }

    private var batteryMetric: some View {
        metricStack(value: batteryValue, label: "BATTERY", alignment: .leading)
    }

    private func metricStack(value: Text, label: String, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 0) {
            value
                .font(compact ? .caption.weight(.bold) : .title3.weight(.bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity, alignment: Alignment(horizontal: alignment, vertical: .center))
            Text(label)
                .font(compact ? .caption2.weight(.bold) : .subheadline.weight(.bold))
                .opacity(0.6)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: Alignment(horizontal: alignment, vertical: .center))
        }
    }
}

/// The flat home picture. White labels stay white after a refresh; the system label color turns black on this dark art.
struct EnergyWidgetHomeBackground: View {
    var opacity: Double = 1
    private static let fallback = Color(red: 22.0 / 255, green: 23.0 / 255, blue: 24.0 / 255)

    var body: some View {
        GeometryReader { geometry in
            if let picture = EnergyWidgetHomeImage.image() {
                EnergyWidgetHomeImage.filled(picture)
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
                    .opacity(opacity)
            }
        }
        .background(Self.fallback)
    }
}

enum EnergyWidgetHomeImage {
    static func image() -> Image? {
        guard let url = Bundle.main.url(forResource: "home-background", withExtension: "jpg") else { return nil }
        #if os(macOS)
        return NSImage(contentsOf: url).map { Image(nsImage: $0) }
        #else
        return UIImage(contentsOfFile: url.path).map { Image(uiImage: $0) }
        #endif
    }

    @ViewBuilder
    static func filled(_ image: Image) -> some View {
        if #available(iOS 18.0, macOS 15.0, *) {
            image.resizable().widgetAccentedRenderingMode(.fullColor)
        } else {
            image.resizable()
        }
    }
}

struct PowerwallEnergyWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "PowerwallEnergy", provider: EnergyWidgetProvider()) { entry in
            EnergyWidgetView(entry: entry)
        }
        .configurationDisplayName("Powerwall")
        .description("Solar, home, battery, and grid, without the live scene.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct PowerwallEnergyWidgetBundle: WidgetBundle {
    var body: some Widget {
        PowerwallEnergyWidget()
    }
}
#endif
