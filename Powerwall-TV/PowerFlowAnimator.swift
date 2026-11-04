// PowerFlowAnimator.swift
// Port of the Tesla app's animated power-flow wires (Godot: WireDisplay.gd, WireRemapper*.gd,
// PowerflowWire.shader) for the ResidentialClassic house. Renderer-independent core: the SceneKit
// renderer (tvOS 18.2) is in PowerFlowSceneKit.swift, the RealityKit one (tvOS 26+) in
// PowerFlowRealityKit.swift. See POWERFLOW.md.

import Foundation
import simd

// MARK: - Tesla enums (EnergySiteData.gd)

/// EnergySiteData.Component. Raw values are Tesla's.
enum PowerFlowComponent: Int, CaseIterable, Sendable {
    case load = 1, solar = 2, battery = 3, grid = 4, generator = 5
    case wallConnector1 = 6, vehicle1 = 7, meter = 8, wallConnector2 = 9, vehicle2 = 10
}

/// WireDisplay direction / shader `state`. Raw values are Tesla's.
enum PowerFlowDirection: Int, Sendable {
    case idle = 0, flowIn = 1, flowOut = -1, hidden = 2
}

// MARK: - Colours and constants

struct PowerFlowColor: Equatable, Hashable, Sendable {
    var r: Float, g: Float, b: Float, a: Float
    init(r: Float, g: Float, b: Float, a: Float = 1) { self.r = r; self.g = g; self.b = b; self.a = a }
    init(hex: UInt32) {
        self.init(r: Float((hex >> 16) & 0xFF) / 255, g: Float((hex >> 8) & 0xFF) / 255, b: Float(hex & 0xFF) / 255)
    }
}

enum PowerFlowStyle {
    /// Idle track behind the pulse. Tesla's #383838 disappears on this house.
    /// Graded walls render near RGB(52, 52, 55). Matching 75% of that was too dark.
    /// The track now shows near RGB(60, 60, 63). The pipe multiplies by the baked
    /// shade (0.5 on the home and Powerwall runs) and by `brightness` (2.2), so the
    /// stored colour is the shown grey divided by that gain.
    static let baseColor = PowerFlowColor(
        r: (60.0 / 255) / 1.1,
        g: (60.0 / 255) / 1.1,
        b: (63.0 / 255) / 1.1
    )
    /// WireDisplay.gd DEFAULT_WIRE_COLORS, keyed by the wire's *source* component.
    static let defaultWireColors: [PowerFlowComponent: PowerFlowColor] = [
        .solar: PowerFlowColor(hex: 0xFFC107),
        .battery: PowerFlowColor(hex: 0x00E286),
        .grid: PowerFlowColor(hex: 0xAAAAAA),
        .generator: PowerFlowColor(hex: 0xAAAAAA),
        .wallConnector1: PowerFlowColor(hex: 0xAAAAAA),
        .vehicle1: PowerFlowColor(hex: 0x00E286),
        .meter: PowerFlowColor(hex: 0x00E286),
        .wallConnector2: PowerFlowColor(hex: 0xAAAAAA),
    ]
    /// Not in Tesla's table (load is never a source there); used only if a caller emits one.
    static let fallbackColor = PowerFlowColor(hex: 0xAAAAAA)
}

/// PowerflowWire.shader uniforms (material defaults in the ResidentialClassic scene).
struct PowerFlowShaderParameters: Sendable {
    var pulseLength: Float = 9        // UV units per pulse
    var pulseFrequency: Float = 2     // seconds per pulse
    var snakeFraction: Float = 0.6
    var snakeExponent: Float = 2
    init() {}
}

// MARK: - Input data

/// One frame of site power, in watts, using Tesla's sign conventions (same as Fleet API live_status
/// and the powerwall-tv `PowerwallData` model).
struct PowerFlowSnapshot: Equatable, Sendable {
    /// Solar generation (>= 0).
    var solarW: Double
    /// Powerwall: > 0 discharging, < 0 charging.
    var batteryW: Double
    /// Grid / site meter: > 0 importing, < 0 exporting.
    var gridW: Double
    /// Home load, *including* any Wall Connector load (Tesla's load_power).
    var homeW: Double
    /// Wall Connector power: > 0 vehicle charging. (< 0 is treated as vehicle-to-home.)
    var vehicleW: Double
    var hasSolar: Bool
    var hasBattery: Bool
    var hasVehicle: Bool

    init(solarW: Double = 0, batteryW: Double = 0, gridW: Double = 0, homeW: Double = 0,
                vehicleW: Double = 0, hasSolar: Bool = true, hasBattery: Bool = true, hasVehicle: Bool = false) {
        self.solarW = solarW; self.batteryW = batteryW; self.gridW = gridW; self.homeW = homeW
        self.vehicleW = vehicleW; self.hasSolar = hasSolar; self.hasBattery = hasBattery; self.hasVehicle = hasVehicle
    }
}

/// EnergySiteData wire: what the Tesla native app hands to Godot.
struct PowerFlowWire: Equatable, Sendable {
    var source: PowerFlowComponent
    var destination: PowerFlowComponent
    var isFlowing: Bool
    var watts: Double
    /// EnergySiteData `wireColor` (overrides the default colour for the source).
    var colorOverride: PowerFlowColor?
}

// MARK: - Wire list (inferred; Tesla builds this natively, outside Godot)

enum PowerFlowSolver {
    /// Turns a snapshot into a Tesla-style wire list. Allocation order is an inference:
    /// solar -> home, vehicle, battery, grid; battery -> home, vehicle, grid;
    /// vehicle (V2H) -> home, grid; grid -> home, vehicle, battery.
    /// Vehicle charging is emitted as SRC->METER, METER->VEHICLE_1 and WALL_CONNECTOR_1->VEHICLE_1,
    /// which is what lets Tesla's own path pairs and default colours show it.
    static func wires(for s: PowerFlowSnapshot, thresholdW: Double = 10) -> [PowerFlowWire] {
        let vehicleCharge = max(s.vehicleW, 0)
        var sources: [(PowerFlowComponent, Double)] = [
            (.solar, max(s.solarW, 0)),
            (.battery, max(s.batteryW, 0)),
            (.vehicle1, max(-s.vehicleW, 0)),
            (.grid, max(s.gridW, 0)),
        ]
        var sinks: [PowerFlowComponent: Double] = [
            .load: max(s.homeW - vehicleCharge, 0),
            .vehicle1: vehicleCharge,
            .battery: max(-s.batteryW, 0),
            .grid: max(-s.gridW, 0),
        ]
        let order: [PowerFlowComponent: [PowerFlowComponent]] = [
            .solar: [.load, .vehicle1, .battery, .grid],
            .battery: [.load, .vehicle1, .grid],
            .vehicle1: [.load, .grid],
            .grid: [.load, .vehicle1, .battery],
        ]
        // (source, sink) -> watts, keeping insertion order for Tesla's "first wire per source" rule.
        var flows: [(PowerFlowComponent, PowerFlowComponent, Double)] = []
        for i in sources.indices {
            let src = sources[i].0
            for dst in order[src] ?? [] {
                let take = min(sources[i].1, sinks[dst] ?? 0)
                guard take > 0 else { continue }
                sources[i].1 -= take
                sinks[dst, default: 0] -= take
                flows.append((src, dst, take))
            }
        }

        var out: [PowerFlowWire] = []
        func add(_ a: PowerFlowComponent, _ b: PowerFlowComponent, _ w: Double, _ c: PowerFlowColor? = nil) {
            if let i = out.firstIndex(where: { $0.source == a && $0.destination == b }) {
                out[i].watts += w; out[i].isFlowing = out[i].watts > thresholdW
            } else {
                out.append(PowerFlowWire(source: a, destination: b, isFlowing: w > thresholdW, watts: w, colorOverride: c))
            }
        }
        var toVehicle = 0.0
        for (src, dst, w) in flows {
            if dst == .vehicle1 { add(src == .grid ? .grid : src, .meter, w); toVehicle += w }
            else if src == .vehicle1 { add(.vehicle1, dst == .load ? .load : .grid, w) }
            else { add(src, dst, w) }
        }
        if toVehicle > 0 {
            add(.meter, .vehicle1, toVehicle)
            add(.wallConnector1, .vehicle1, toVehicle)
        }
        // Idle wires so present-but-quiet components still show a wire (Tesla's IDLE state: base colour).
        func idle(_ c: PowerFlowComponent, _ a: PowerFlowComponent, _ b: PowerFlowComponent) {
            if !out.contains(where: { $0.source == c || $0.destination == c }) {
                out.append(PowerFlowWire(source: a, destination: b, isFlowing: false, watts: 0, colorOverride: nil))
            }
        }
        idle(.grid, .grid, .load)
        if s.hasSolar { idle(.solar, .solar, .load) }
        if s.hasBattery { idle(.battery, .battery, .load) }
        if s.hasVehicle { idle(.vehicle1, .wallConnector1, .vehicle1) }
        return out
    }
}

// MARK: - Paths and the remapper (WireRemapper*.gd)

/// One baked ribbon sample (see PowerFlowLayout.swift).
struct PowerFlowPathPoint: Sendable {
    let u: Float
    let position: SIMD3<Float>
    let side: SIMD3<Float>
    let shade: Float
    let alpha: Float
}

extension PowerFlowLayout {
    /// Point `fraction` of the way along a baked ribbon, from the house end to the far end.
    static func point(along name: String, fraction: Float) -> SIMD3<Float>? {
        let points = paths[name] ?? []
        guard let first = points.first?.position else { return nil }
        guard points.count >= 2 else { return first }
        var travelled: Float = 0
        var spans: [Float] = []
        spans.reserveCapacity(points.count - 1)
        for index in 1..<points.count {
            let span = simd_length(points[index].position - points[index - 1].position)
            spans.append(span)
            travelled += span
        }
        let target = travelled * min(max(fraction, 0), 1)
        var cursor: Float = 0
        for (index, span) in spans.enumerated() {
            if cursor + span >= target || index == spans.count - 1 {
                let t = span > 1e-5 ? min(max((target - cursor) / span, 0), 1) : 0
                return simd_mix(points[index].position, points[index + 1].position, SIMD3(repeating: t))
            }
            cursor += span
        }
        return points.last?.position ?? first
    }
}

struct PowerFlowPathGroup: Sendable {
    let name: String
    /// (path component, other component). A wire whose source is the first entry flows IN.
    let pairs: [(PowerFlowComponent, PowerFlowComponent)]
    /// Wire delegates by wire count: delegates[n-1] are the path names for n parallel wires.
    let delegates: [[String]]
    /// PowerflowWire.shader wire_terminate_at.
    let terminateAt: Float

    static let all: [PowerFlowPathGroup] = [
        PowerFlowPathGroup(name: "Grid",
                           pairs: [(.grid, .meter), (.grid, .solar), (.grid, .battery), (.grid, .load), (.grid, .vehicle1)],
                           delegates: [["Grid_1A"], ["Grid_2A", "Grid_2B"]], terminateAt: 1000),
        PowerFlowPathGroup(name: "Home",
                           pairs: [(.load, .battery), (.load, .solar), (.load, .grid), (.load, .meter), (.load, .vehicle1)],
                           delegates: [["Home_1A"], ["Home_2A", "Home_2B"], ["Home_3A", "Home_3B", "Home_3C"]], terminateAt: 1000),
        PowerFlowPathGroup(name: "Powerwall",
                           pairs: [(.battery, .meter), (.battery, .load), (.battery, .grid), (.battery, .solar)],
                           delegates: [["Powerwall_1A"], ["Powerwall_2A", "Powerwall_2B"]], terminateAt: 1000),
        PowerFlowPathGroup(name: "Solar",
                           pairs: [(.solar, .meter), (.solar, .grid), (.solar, .load), (.solar, .battery)],
                           delegates: [["Solar_1A"]], terminateAt: 2.2),   // 2.2 = panels; Solar Roof uses 1000
        PowerFlowPathGroup(name: "Vehicle",
                           pairs: [(.vehicle1, .wallConnector1), (.vehicle1, .load)],
                           delegates: [["Vehicle_1A"]], terminateAt: 1000),
    ]
}

/// What one visible ribbon should show.
struct PowerFlowPathState: Equatable, Sendable {
    var direction: PowerFlowDirection
    var flowColor: PowerFlowColor
    var phaseOffset: Float
    var watts: Double
}

enum PowerFlowRemapper {
    /// Returns the state of every visible path, keyed by path name ("Grid_2A", ...). Paths not in the
    /// result are hidden.
    static func remap(_ wires: [PowerFlowWire], groups: [PowerFlowPathGroup] = PowerFlowPathGroup.all,
                             phaseOffsets: [String: Float] = [:]) -> [String: PowerFlowPathState] {
        var result: [String: PowerFlowPathState] = [:]
        for g in groups {
            var drawn: [(PowerFlowWire, PowerFlowDirection)] = []
            var seenSources = Set<Int>()
            var firstMatch: (PowerFlowWire, PowerFlowComponent)?
            for w in wires {
                guard let pair = g.pairs.first(where: { (w.source == $0.0 && w.destination == $0.1) ||
                                                        (w.source == $0.1 && w.destination == $0.0) }) else { continue }
                if firstMatch == nil { firstMatch = (w, pair.0) }
                guard w.isFlowing, !seenSources.contains(w.source.rawValue) else { continue }
                seenSources.insert(w.source.rawValue)
                drawn.append((w, w.source == pair.0 ? .flowIn : .flowOut))
            }
            if drawn.isEmpty, let m = firstMatch { drawn = [(m.0, .idle)] }
            guard !drawn.isEmpty else { continue }
            // The Powerwall has one cable on the wall. A second source (solar and the
            // grid both charging, or the car's meter hop) used to add Powerwall_2B
            // beside it, so the two ribbons ran to and from the unit at once.
            if g.name == "Powerwall", drawn.count > 1,
               let strongest = drawn.max(by: { abs($0.0.watts) < abs($1.0.watts) }) {
                drawn = [strongest]
            }
            // Tesla prints an error and draws nothing when there is no delegate for the count; we clamp.
            let names = g.delegates[min(drawn.count, g.delegates.count) - 1]
            for (name, (w, dir)) in zip(names, drawn) {
                let colour = w.colorOverride ?? PowerFlowStyle.defaultWireColors[w.source] ?? PowerFlowStyle.fallbackColor
                let phase = phaseOffsets[name] ?? 0
                result[name] = PowerFlowPathState(direction: dir, flowColor: colour,
                                                  phaseOffset: dir == .flowOut ? phase : -phase, watts: w.watts)
            }
        }
        return result
    }
}

// MARK: - Shader (PowerflowWire.shader fragment, evaluated on the CPU)

enum PowerFlowShader {
    @inline(__always) static func fract(_ x: Float) -> Float { x - x.rounded(.down) }   // GLSL fract
    @inline(__always) static func smoothstep01(_ x: Float) -> Float { let t = min(max(x, 0), 1); return t * t * (3 - 2 * t) }

    /// `time` is WireDisplay's fmod(seconds, pulse_frequency).
    static func color(u: Float, shade: Float, alpha: Float, state: PowerFlowPathState, time: Float,
                             params: PowerFlowShaderParameters, base: PowerFlowColor = PowerFlowStyle.baseColor) -> PowerFlowColor {
        let s = Float(state.direction.rawValue)
        let phase = fract(time / params.pulseFrequency + s * (u / params.pulseLength + state.phaseOffset))
        let amount = pow(max(1 - phase / params.snakeFraction, 0), params.snakeExponent) * abs(s)
        let k = smoothstep01(amount)
        let f = state.flowColor
        return PowerFlowColor(r: (base.r + (f.r - base.r) * k) * shade,
                              g: (base.g + (f.g - base.g) * k) * shade,
                              b: (base.b + (f.b - base.b) * k) * shade,
                              a: alpha)
    }
}

// MARK: - Ribbon geometry (shared by both renderers)

/// Expanded box the pipes must stay outside. The Powerwall and the gateway use this.
struct PowerFlowClearance: Sendable {
    var lower: SIMD3<Float>
    var upper: SIMD3<Float>
    /// How far a trimmed end sits back from the face. The gateway uses 0 so the pipe meets it.
    var inset: Float = 0.002

    func contains(_ point: SIMD3<Float>) -> Bool {
        point.x >= lower.x && point.x <= upper.x
            && point.y >= lower.y && point.y <= upper.y
            && point.z >= lower.z && point.z <= upper.z
    }

    /// Moves a point on the top face out to the camera-side lip, so the solar
    /// cable meets the front of the meter. The bottom face stays on the baked
    /// drop: sliding it out hooks the grid cable sideways under the gateway.
    func frontLip(_ point: SIMD3<Float>, camera: SIMD3<Float>) -> SIMD3<Float> {
        guard inset == 0 else { return point }
        let eps: Float = 0.0015
        guard abs(point.y - upper.y) <= eps else { return point }
        var presented = point
        presented.x = camera.x >= point.x ? upper.x : lower.x
        return presented
    }

    /// Point where the segment from `outside` reaches this box, stepped back so it stays clear.
    func stop(before inside: SIMD3<Float>, from outside: SIMD3<Float>) -> SIMD3<Float> {
        let delta = inside - outside
        let length = simd_length(delta)
        guard length > 1e-5 else { return outside }
        var enter: Float = 0
        var exit: Float = 1
        for axis in 0..<3 {
            let direction = delta[axis]
            let origin = outside[axis]
            if abs(direction) < 1e-8 {
                if origin < lower[axis] || origin > upper[axis] { return outside }
                continue
            }
            var near = (lower[axis] - origin) / direction
            var far = (upper[axis] - origin) / direction
            if near > far { swap(&near, &far) }
            enter = Swift.max(enter, near)
            exit = Swift.min(exit, far)
        }
        guard enter <= exit else { return outside }
        let backed = enter - inset / length
        return outside + delta * Swift.min(Swift.max(backed, 0), 1)
    }

    /// Strictly inside the box. A point sitting on a face is not inside, so a pipe can end there.
    func encloses(_ point: SIMD3<Float>) -> Bool {
        let slack: Float = 0.0008
        return point.x > lower.x + slack && point.x < upper.x - slack
            && point.y > lower.y + slack && point.y < upper.y - slack
            && point.z > lower.z + slack && point.z < upper.z - slack
    }

    /// True when the segment enters this box, including a span whose ends both sit outside it.
    func intersectsSegment(_ start: SIMD3<Float>, _ end: SIMD3<Float>) -> Bool {
        if contains(start) || contains(end) { return true }
        let delta = end - start
        var enter: Float = 0
        var exit: Float = 1
        for axis in 0..<3 {
            let direction = delta[axis]
            let origin = start[axis]
            if abs(direction) < 1e-8 {
                if origin < lower[axis] || origin > upper[axis] { return false }
                continue
            }
            var near = (lower[axis] - origin) / direction
            var far = (upper[axis] - origin) / direction
            if near > far { swap(&near, &far) }
            enter = Swift.max(enter, near)
            exit = Swift.min(exit, far)
            if enter > exit { return false }
        }
        return exit >= 0 && enter <= 1
    }
}

/// A path resampled into short rectangular pipes. Each segment gets one colour per frame.
struct PowerFlowRibbon: Sendable {
    let name: String
    /// 8 corners per segment: a rectangular ring at each end. The inner face sits on the baked route.
    let corners: [SIMD3<Float>]
    let midU: [Float]
    let shade: [Float]
    let alpha: [Float]
    var quadCount: Int { midU.count }

    /// How far the pipe stands off the baked centreline, toward the camera.
    static let thickness: Float = 0.008

    init?(name: String, points: [PowerFlowPathPoint], terminateAt: Float, step: Float = 0.1, widthScale: Float = 1, camera: SIMD3<Float>? = nil, clearances: [PowerFlowClearance] = [], plug: SIMD3<Float>? = nil) {
        let routed = Self.meeting(Self.centreline(points), plug: plug)
        let points = plug == nil ? routed : Self.smoothed(routed)
        guard points.count >= 2 else { return nil }
        let uEnd = min(points[points.count - 1].u, terminateAt)
        func sample(_ u: Float) -> (SIMD3<Float>, SIMD3<Float>, Float, Float) {
            var i = 0
            while i < points.count - 2 && points[i + 1].u < u { i += 1 }
            let a = points[i], b = points[i + 1]
            let t = b.u > a.u ? min(max((u - a.u) / (b.u - a.u), 0), 1) : 0
            return (simd_mix(a.position, b.position, SIMD3(repeating: t)), simd_mix(a.side, b.side, SIMD3(repeating: t)),
                    a.shade + (b.shade - a.shade) * t, a.alpha + (b.alpha - a.alpha) * t)
        }
        /// Width lies in the wall, depth points at the camera. One ring is built per sample and
        /// shared by the segments on either side, so the inner and outer edges cannot part at a bend.
        func snappedNormal(_ travel: SIMD3<Float>, _ side: SIMD3<Float>, _ position: SIMD3<Float>) -> SIMD3<Float> {
            var axis = cross(travel, side)
            if simd_length(axis) < 1e-5 { axis = cross(travel, SIMD3<Float>(1, 0, 0)) }
            if simd_length(axis) < 1e-5 { axis = SIMD3<Float>(1, 0, 0) }
            let absolute = abs(axis)
            var normal = SIMD3<Float>.zero
            if absolute.x >= absolute.y && absolute.x >= absolute.z { normal.x = axis.x >= 0 ? 1 : -1 }
            else if absolute.y >= absolute.z { normal.y = axis.y >= 0 ? 1 : -1 }
            else { normal.z = axis.z >= 0 ? 1 : -1 }
            if let camera, dot(normal, camera - position) < 0 { normal = -normal }
            return normal
        }
        /// Smallest rotation that carries a cross-section from one tangent onto the next.
        func carriedForward(_ normal: SIMD3<Float>, from: SIMD3<Float>, to: SIMD3<Float>) -> SIMD3<Float>? {
            let axis = cross(from, to)
            let sinAngle = simd_length(axis)
            let cosAngle = dot(from, to)
            var turned = normal
            if sinAngle > 1e-5 {
                let k = axis / sinAngle
                turned = normal * cosAngle + cross(k, normal) * sinAngle + k * dot(k, normal) * (1 - cosAngle)
            } else if cosAngle < 0 {
                turned = -normal
            }
            let projected = turned - to * dot(turned, to)
            guard simd_length(projected) > 1e-4 else { return nil }
            return simd_normalize(projected)
        }
        func bisector(_ index: Int) -> SIMD3<Float> {
            func direction(_ from: Int, _ to: Int) -> SIMD3<Float>? {
                let delta = samples[to] - samples[from]
                guard simd_length(delta) > 1e-5 else { return nil }
                return simd_normalize(delta)
            }
            let back = index > 0 ? direction(index - 1, index) : nil
            let forward = index + 1 < samples.count ? direction(index, index + 1) : nil
            switch (back, forward) {
            case let (previous?, next?):
                let sum = previous + next
                return simd_length(sum) > 1e-5 ? simd_normalize(sum) : next
            case let (previous?, nil): return previous
            case let (nil, next?): return next
            default: return SIMD3<Float>(0, 1, 0)
            }
        }
        func ring(_ center: SIMD3<Float>, _ width: SIMD3<Float>, _ depth: SIMD3<Float>) -> [SIMD3<Float>] {
            [center - width, center + width, center + depth + width, center + depth - width]
        }
        let u0 = points[0].u
        let n = max(Int(((uEnd - u0) / step).rounded(.up)), 1)
        var samples: [SIMD3<Float>] = []
        var sides: [SIMD3<Float>] = []
        var shades: [Float] = []
        var alphas: [Float] = []
        var us: [Float] = []
        samples.reserveCapacity(n + 1)
        for i in 0...n {
            let u = u0 + (uEnd - u0) * Float(i) / Float(n)
            let (p, s, sh, a) = sample(u)
            samples.append(p)
            sides.append(s)
            shades.append(sh)
            alphas.append(a)
            us.append(u)
        }
        var frames: [(SIMD3<Float>, SIMD3<Float>)] = []
        frames.reserveCapacity(samples.count)
        var carriedNormal: SIMD3<Float>?
        var carriedWidth: SIMD3<Float>?
        var carriedTravel: SIMD3<Float>?
        for index in samples.indices {
            let travel = bisector(index)
            let snap = snappedNormal(travel, sides[index], samples[index])
            var normal = snap
            if let carriedNormal, let carriedTravel, let turned = carriedForward(carriedNormal, from: carriedTravel, to: travel) {
                // A straight run already agrees with the axis snap, which keeps the pipe rectangular.
                // Through a bend the snap would swap edges, so the carried frame wins.
                normal = dot(turned, snap) > 0.85 ? snap : turned
            }
            var width = cross(normal, travel)
            if simd_length(width) < 1e-5 { width = sides[index] - normal * dot(sides[index], normal) }
            if simd_length(width) < 1e-5 { width = cross(normal, SIMD3<Float>(0, 1, 0)) }
            width = simd_normalize(width) * max(simd_length(sides[index]), 0.01) * widthScale
            if let carriedWidth {
                if dot(width, carriedWidth) < 0 { width = -width }
            } else if dot(width, sides[index]) < 0 {
                width = -width
            }
            carriedNormal = normal
            carriedWidth = width
            carriedTravel = travel
            frames.append((width, normal * Self.thickness))
        }
        var corners: [SIMD3<Float>] = [], mid: [Float] = [], sh: [Float] = [], al: [Float] = []
        corners.reserveCapacity((samples.count - 1) * 8)
        for i in 0..<(samples.count - 1) {
            guard let clipped = Self.clip(samples[i], samples[i + 1], clearances, camera: camera) else { continue }
            let start = frames[i], end = frames[i + 1]
            corners += ring(clipped.0, start.0, start.1) + ring(clipped.1, end.0, end.1)
            mid.append((us[i] + us[i + 1]) / 2)
            sh.append((shades[i] + shades[i + 1]) / 2)
            al.append((alphas[i] + alphas[i + 1]) / 2)
        }
        guard !corners.isEmpty else { return nil }
        self.name = name; self.corners = corners; self.midU = mid; self.shade = sh; self.alpha = al
    }

    /// The baked charger run sits in front of the garage door, about 16 cm ahead of
    /// the wall connector. Ease that correction out along the drop, which stays left
    /// of the door, then leave the ground run on the baked path.
    private static func meeting(_ points: [PowerFlowPathPoint], plug: SIMD3<Float>?) -> [PowerFlowPathPoint] {
        guard let plug, let first = points.first else { return points }
        let delta = plug - first.position
        guard simd_length(delta) > 0.001 else { return points }
        var lowIndex = 0
        var lowY = points[0].position.y
        for (index, point) in points.enumerated() where point.position.y < lowY {
            lowY = point.position.y
            lowIndex = index
        }
        var lengthToLow: Float = 0
        if lowIndex > 0 {
            for index in 1...lowIndex {
                lengthToLow += simd_length(points[index].position - points[index - 1].position)
            }
        }
        lengthToLow = max(lengthToLow, 0.05)
        var travelled: Float = 0
        return points.enumerated().map { index, point in
            if index > 0 {
                travelled += simd_length(point.position - points[index - 1].position)
            }
            let t = index >= lowIndex ? 1 : min(max(travelled / lengthToLow, 0), 1)
            let fade = 1 - t * t * (3 - 2 * t)
            return PowerFlowPathPoint(
                u: point.u,
                position: point.position + delta * fade,
                side: point.side,
                shade: point.shade,
                alpha: point.alpha
            )
        }
    }

    /// Rounds interior bends. The ends stay put, so the cable still meets the connector and the car.
    private static func smoothed(_ points: [PowerFlowPathPoint], passes: Int = 3) -> [PowerFlowPathPoint] {
        guard points.count >= 4 else { return points }
        var current = points
        for _ in 0..<passes {
            var next = current
            for index in 1..<(current.count - 1) {
                let position = (current[index - 1].position + current[index].position * 2 + current[index + 1].position) * 0.25
                let side = (current[index - 1].side + current[index].side * 2 + current[index + 1].side) * 0.25
                next[index] = PowerFlowPathPoint(
                    u: current[index].u,
                    position: position,
                    side: side,
                    shade: current[index].shade,
                    alpha: current[index].alpha
                )
            }
            current = next
        }
        return current
    }

    /// The cable bake recorded both edges of the ribbon as well as its centre. Those
    /// extra samples have almost no width and sit a centimetre off the run, which
    /// pinches the pipe. Other paths already sit on the centreline.
    private static func centreline(_ points: [PowerFlowPathPoint]) -> [PowerFlowPathPoint] {
        guard points.count >= 3 else { return points }
        var kept: [PowerFlowPathPoint] = []
        kept.reserveCapacity(points.count)
        for (index, point) in points.enumerated() {
            let isEnd = index == 0 || index == points.count - 1
            if !isEnd && simd_length(point.side) < 0.01 { continue }
            if let previous = kept.last, !isEnd {
                let deltaU = point.u - previous.u
                let speed = deltaU > 1e-4 ? simd_length(point.position - previous.position) / deltaU : 0
                if speed > 1.2 { continue }
            }
            kept.append(point)
        }
        return kept.count >= 2 ? kept : points
    }

    /// Drops a segment that sits inside a clearance box, and trims one that only enters it.
    private static func clip(_ start: SIMD3<Float>, _ end: SIMD3<Float>, _ boxes: [PowerFlowClearance], camera: SIMD3<Float>?) -> (SIMD3<Float>, SIMD3<Float>)? {
        var start = start, end = end
        for box in boxes {
            let startInside = box.contains(start)
            let endInside = box.contains(end)
            if startInside && endInside { return nil }
            if !startInside && !endInside && box.intersectsSegment(start, end) { return nil }
            if startInside { start = box.stop(before: start, from: end) }
            if endInside { end = box.stop(before: end, from: start) }
            if let camera {
                if startInside { start = box.frontLip(start, camera: camera) }
                if endInside { end = box.frontLip(end, camera: camera) }
            }
            if box.encloses(start) || box.encloses(end) { return nil }
        }
        guard simd_length(end - start) > 1e-4 else { return nil }
        return (start, end)
    }

    /// Triangles for the four long faces of pipe segment `q`. Corners are two rings of four.
    static func indices(quad q: Int) -> [UInt32] {
        let b = UInt32(q * 8)
        var indices: [UInt32] = []
        func face(_ a: UInt32, _ c: UInt32, _ d: UInt32, _ e: UInt32) {
            indices += [a, c, d, a, d, e]
        }
        face(b + 3, b + 2, b + 6, b + 7)
        face(b + 0, b + 4, b + 5, b + 1)
        face(b + 1, b + 5, b + 6, b + 2)
        face(b + 4, b + 0, b + 3, b + 7)
        return indices
    }
}

// MARK: - Animator

/// Holds the current flow state and computes per-quad colours. Renderers call `colors(for:at:)`
/// every frame for each ribbon and apply the result.
final class PowerFlowAnimator {
    var params = PowerFlowShaderParameters()
    var thresholdW: Double = 10            // powerwall-tv uses 10 W for its battery animation
    /// Optional extension (not Tesla): scale pulse speed with kW. 0 = off (Tesla behaviour).
    var speedPerKW: Float = 0
    /// Tesla's per-vertex shade is about 0.5, which halves the pulse. 2.2 puts the
    /// moving colour back near the authored hex on this dark house.
    var brightness: Float = 2.2
    private(set) var snapshot = PowerFlowSnapshot()
    private(set) var wires: [PowerFlowWire] = []
    private(set) var states: [String: PowerFlowPathState] = [:]
    let ribbons: [PowerFlowRibbon]

    /// `solarTerminateAt` is 2.2 for rooftop panels and 1000 for a solar roof, matching Tesla's shader.
    /// `clearances` are the Powerwall and gateway, expanded so a pipe cannot enter them.
    init(layout: [String: [PowerFlowPathPoint]] = PowerFlowLayout.paths, step: Float = 0.1, solarTerminateAt: Float = 2.2, camera: SIMD3<Float>? = nil, clearances: [PowerFlowClearance] = [], connectorPlug: SIMD3<Float>? = nil) {
        var rs: [PowerFlowRibbon] = []
        for g in PowerFlowPathGroup.all {
            let terminateAt = g.name == "Solar" ? solarTerminateAt : g.terminateAt
            for name in Set(g.delegates.flatMap { $0 }).sorted() {
                let plug = name.hasPrefix("Vehicle") ? connectorPlug : nil
                if let pts = layout[name], let r = PowerFlowRibbon(name: name, points: pts, terminateAt: terminateAt, step: step, camera: camera, clearances: clearances, plug: plug) { rs.append(r) }
            }
        }
        ribbons = rs
    }

    func update(_ s: PowerFlowSnapshot) {
        snapshot = s
        wires = PowerFlowSolver.wires(for: s, thresholdW: thresholdW)
        states = PowerFlowRemapper.remap(wires)
    }

    /// Per-quad RGBA for `ribbon` at absolute time `seconds`, or nil if the path is hidden.
    func colors(for ribbon: PowerFlowRibbon, at seconds: TimeInterval) -> [PowerFlowColor]? {
        guard let state = states[ribbon.name], state.direction != .hidden else { return nil }
        let speed = speedPerKW > 0 ? 1 + speedPerKW * Float(state.watts / 1000) : 1
        let t = Float(fmod(seconds * Double(speed), Double(params.pulseFrequency)))
        return (0..<ribbon.quadCount).map { i in
            var c = PowerFlowShader.color(u: ribbon.midU[i], shade: ribbon.shade[i] * brightness, alpha: ribbon.alpha[i],
                                          state: state, time: t, params: params)
            c.r = min(c.r, 1); c.g = min(c.g, 1); c.b = min(c.b, 1)
            return c
        }
    }
}
