// Live site watts for the power-flow ribbons.
// Signs match Fleet live status: battery > 0 is discharging, site > 0 is importing.
// Presence follows the garage scene: a listed connector does not draw the car cable
// unless the garage would show the car, and hidden solar drops the solar ribbon.

import Foundation

extension PowerFlowSnapshot {
    init(data: PowerwallData?, presentation: GaragePresentation, batteryCount: Double?) {
        let connectors = data?.wallConnectors ?? []
        let vehicleW = connectors.reduce(0.0) { $0 + Double($1.wallConnectorPower ?? 0) }
        let hasSolar = presentation.solar != .hidden
        let counted = batteryCount ?? data?.battery.count
        let hasBattery = counted.map { $0 > 0 } ?? true
        self.init(
            solarW: hasSolar ? Double(data?.solar.instantPower ?? 0) : 0,
            batteryW: hasBattery ? Double(data?.battery.instantPower ?? 0) : 0,
            gridW: Double(data?.site.instantPower ?? 0),
            homeW: Double(data?.load.instantPower ?? 0),
            vehicleW: vehicleW,
            hasSolar: hasSolar,
            hasBattery: hasBattery,
            hasVehicle: presentation.showVehicle
        )
    }
}
