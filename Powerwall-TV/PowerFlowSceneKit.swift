// Draws PowerFlowAnimator ribbons in SceneKit. Works on macOS, iOS, and tvOS 18.2.
// Call `tick` from SCNSceneRendererDelegate. `HousePowerFlowDriver` is that delegate
// and keeps `update` (main thread) off the same ribbons `tick` paints.

import SceneKit
import simd

final class PowerFlowSceneKitRenderer {
    let animator: PowerFlowAnimator
    private var nodes: [String: (node: SCNNode, materials: [SCNMaterial])] = [:]

    /// `house` is the ResidentialClassic node. Ribbons hang under a PowerFlow child when the
    /// USD has one, otherwise under the house. Geometry is in that node's local space.
    init(house: SCNNode, animator: PowerFlowAnimator = PowerFlowAnimator()) {
        self.animator = animator
        let parent = house.childNode(withName: "PowerFlow", recursively: true) ?? house
        for ribbon in animator.ribbons {
            let verts = ribbon.corners.map { SCNVector3($0.x, $0.y, $0.z) }
            let source = SCNGeometrySource(vertices: verts)
            var elements: [SCNGeometryElement] = []
            var materials: [SCNMaterial] = []
            // The solar centreline stays where Tesla baked it, including where it
            // runs under the roof mesh. Draw that wire over the roof. The other
            // wires still depth-test so they stay on the wall.
            let overRoof = ribbon.name.hasPrefix("Solar")
            for q in 0..<ribbon.quadCount {
                elements.append(SCNGeometryElement(indices: PowerFlowRibbon.indices(quad: q), primitiveType: .triangles))
                let material = SCNMaterial()
                material.lightingModel = .constant
                material.isDoubleSided = true
                material.writesToDepthBuffer = false
                material.readsFromDepthBuffer = !overRoof
                material.blendMode = .alpha
                material.diffuse.contents = HouseColor.clear
                // The floor's category mask does not drop these ribbons. The grid
                // runs along the ground, so discard it only in the mirrored pass.
                if ribbon.name.hasPrefix("Grid") {
                    material.shaderModifiers = [.fragment: HouseGroundPlate.reflectedFragment]
                }
                materials.append(material)
            }
            let geometry = SCNGeometry(sources: [source], elements: elements)
            geometry.materials = materials
            let node = SCNNode(geometry: geometry)
            node.name = "PowerFlowWire_\(ribbon.name)"
            // Above the house (0) and the other wires (10), under the Powerwall and gateway (20).
            node.renderingOrder = overRoof ? 15 : 10
            node.castsShadow = false
            node.isHidden = true
            parent.addChildNode(node)
            HouseGroundPlate.omitFromReflection(node)
            nodes[ribbon.name] = (node, materials)
        }
    }

    func removeFromScene() {
        for entry in nodes.values {
            entry.node.removeFromParentNode()
        }
        nodes.removeAll()
    }

    func update(_ snapshot: PowerFlowSnapshot) { animator.update(snapshot) }

    /// Once per frame, with the renderer's time in seconds.
    func tick(at time: TimeInterval) {
        for ribbon in animator.ribbons {
            guard let entry = nodes[ribbon.name] else { continue }
            guard let colors = animator.colors(for: ribbon, at: time) else {
                entry.node.isHidden = true
                continue
            }
            entry.node.isHidden = false
            for (material, color) in zip(entry.materials, colors) {
                material.diffuse.contents = HouseColor(
                    red: CGFloat(color.r),
                    green: CGFloat(color.g),
                    blue: CGFloat(color.b),
                    alpha: CGFloat(color.a)
                )
            }
        }
    }
}

/// SceneKit render delegate for the house. Not main-actor isolated: `tick` runs on the render thread.
final class HousePowerFlowDriver: NSObject, SCNSceneRendererDelegate {
    private let lock = NSLock()
    private var house: SCNNode?
    private var renderer: PowerFlowSceneKitRenderer?
    private var solarTerminate: Float = 2.2
    private var snapshot: PowerFlowSnapshot?
    /// False until the house view says it is rendering continuously. Install and
    /// snapshot updates paint immediately while this stays false, because a paused
    /// view never calls `renderer(_:updateAtTime:)`.
    private var playbackContinuous = false
    private var camera = SIMD3<Float>(7.55, 5.7, 9.75)
    private var clearances: [PowerFlowClearance] = []
    private var connectorPlug: SIMD3<Float>?

    func attach(house: SCNNode, cameraPosition: SIMD3<Float>) {
        // Measure before taking `lock`. `boundingBox` needs the scene lock, and the
        // display-link thread holds that lock while it waits for `lock` in `renderer`.
        let measuredClearances = PowerFlowObstacles.clearances(house: house)
        let plug = PowerFlowObstacles.wallConnectorPlug(house: house)
        lock.lock()
        defer { lock.unlock() }
        guard self.house == nil else { return }
        self.house = house
        camera = cameraPosition
        clearances = measuredClearances
        connectorPlug = plug
        installLocked()
    }

    /// Panels stop the solar ribbon at u = 2.2. A solar roof continues up the roof (1000).
    func setSolarTerminate(_ terminate: Float) {
        lock.lock()
        defer { lock.unlock() }
        guard terminate != solarTerminate else { return }
        solarTerminate = terminate
        guard house != nil else { return }
        renderer?.removeFromScene()
        renderer = nil
        installLocked()
    }

    /// The house view sets this before pushing a snapshot. While it is false, `update`
    /// paints the ribbons itself.
    func setPlaybackContinuous(_ continuous: Bool) {
        lock.lock()
        playbackContinuous = continuous
        lock.unlock()
    }

    func update(_ snapshot: PowerFlowSnapshot) {
        lock.lock()
        defer { lock.unlock() }
        self.snapshot = snapshot
        renderer?.update(snapshot)
        // The view may already be paused. `applyPlayback` runs before the house
        // attaches, and `setSolarTerminate` rebuilds hidden ribbons afterwards.
        paintLockedIfPaused()
    }

    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        // The display link calls this while it holds the scene lock. Waiting here
        // deadlocks if the main thread holds `lock` and then reads a bounding box.
        guard lock.try() else { return }
        self.renderer?.tick(at: time)
        lock.unlock()
    }

    private func installLocked() {
        guard let house else { return }
        let next = PowerFlowSceneKitRenderer(
            house: house,
            animator: PowerFlowAnimator(solarTerminateAt: solarTerminate, camera: camera, clearances: clearances, connectorPlug: connectorPlug)
        )
        if let snapshot { next.update(snapshot) }
        renderer = next
        paintLockedIfPaused()
    }

    /// New ribbon nodes start hidden. A paused view will not tick them later.
    private func paintLockedIfPaused() {
        guard !playbackContinuous, snapshot != nil else { return }
        renderer?.tick(at: 0)
    }
}

/// Gateway box. Cables keep Tesla's path into the Powerwall; that unit is drawn over the lines.
enum PowerFlowObstacles {
    static func clearances(house: SCNNode, margin _: Float = 0.025) -> [PowerFlowClearance] {
        ["Meter", "Gateway"].compactMap { name in
            guard let node = house.childNode(withName: name, recursively: true) else { return nil }
            let box = node.boundingBox
            let lo = SIMD3<Float>(Float(box.min.x), Float(box.min.y), Float(box.min.z))
            let hi = SIMD3<Float>(Float(box.max.x), Float(box.max.y), Float(box.max.z))
            let intoHouse = house.simdWorldTransform.inverse * node.simdWorldTransform
            var minBound = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
            var maxBound = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
            for x in [lo.x, hi.x] {
                for y in [lo.y, hi.y] {
                    for z in [lo.z, hi.z] {
                        let point = intoHouse * SIMD4<Float>(x, y, z, 1)
                        let corner = SIMD3<Float>(point.x, point.y, point.z)
                        minBound = min(minBound, corner)
                        maxBound = max(maxBound, corner)
                    }
                }
            }
            // No pad. Solar meets the top face and the grid meets the bottom face.
            return PowerFlowClearance(lower: minBound, upper: maxBound, inset: 0)
        }
    }

    /// Centre of the wall connector's underside, in the house's ribbon space.
    /// The charger cable leaves that point.
    static func wallConnectorPlug(house: SCNNode) -> SIMD3<Float>? {
        guard let node = house.childNode(withName: "WallConnector", recursively: true) else { return nil }
        let box = node.boundingBox
        let lo = SIMD3<Float>(Float(box.min.x), Float(box.min.y), Float(box.min.z))
        let hi = SIMD3<Float>(Float(box.max.x), Float(box.max.y), Float(box.max.z))
        let intoHouse = house.simdWorldTransform.inverse * node.simdWorldTransform
        var minBound = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
        var maxBound = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
        for x in [lo.x, hi.x] {
            for y in [lo.y, hi.y] {
                for z in [lo.z, hi.z] {
                    let point = intoHouse * SIMD4<Float>(x, y, z, 1)
                    let corner = SIMD3<Float>(point.x, point.y, point.z)
                    minBound = min(minBound, corner)
                    maxBound = max(maxBound, corner)
                }
            }
        }
        return SIMD3(
            (minBound.x + maxBound.x) * 0.5,
            minBound.y,
            (minBound.z + maxBound.z) * 0.5
        )
    }

    /// Drawn after the ribbons so the units cover the cables that run through them.
    static func coverFlows(house: SCNNode) {
        for name in ["Powerwall", "Meter", "Gateway"] {
            guard let node = house.childNode(withName: name, recursively: true) else { continue }
            node.renderingOrder = 20
            node.enumerateChildNodes { child, _ in
                child.renderingOrder = 20
            }
        }
    }
}

/// The thin end of the Powerwall nearest the camera, filled from the bottom with the state of charge.
final class PowerwallLevelBar {
    private let face: PowerwallLevelFace
    private let root = SCNNode()
    private let trackNode = SCNNode()
    private let fillNode = SCNNode()
    private let fillMaterial = SCNMaterial()

    init?(house: SCNNode, cameraPosition: SIMD3<Float>) {
        guard let powerwall = house.childNode(withName: "Powerwall", recursively: true) else { return nil }
        let box = powerwall.boundingBox
        let minBound = SIMD3<Float>(Float(box.min.x), Float(box.min.y), Float(box.min.z))
        let maxBound = SIMD3<Float>(Float(box.max.x), Float(box.max.y), Float(box.max.z))
        let worldCamera = SIMD4<Float>(cameraPosition.x, cameraPosition.y, cameraPosition.z, 1)
        let localCamera4 = powerwall.simdWorldTransform.inverse * worldCamera
        let localCamera = SIMD3<Float>(localCamera4.x, localCamera4.y, localCamera4.z)
        guard let face = PowerwallLevelFace.nearest(minBound: minBound, maxBound: maxBound, camera: localCamera) else { return nil }
        self.face = face
        let track = SCNMaterial()
        track.lightingModel = .constant
        track.isDoubleSided = true
        track.diffuse.contents = HouseColor(white: 0.08, alpha: 1)
        trackNode.geometry = PowerwallLevelFace.quad(face: face, fraction: 1, material: track)
        fillMaterial.lightingModel = .constant
        fillMaterial.isDoubleSided = true
        fillMaterial.diffuse.contents = HouseColor(red: 0, green: 226 / 255, blue: 134 / 255, alpha: 1)
        fillNode.simdPosition = face.normal * 0.001
        fillNode.geometry = PowerwallLevelFace.quad(face: face, fraction: 0, material: fillMaterial)
        fillNode.isHidden = true
        root.name = "PowerwallLevel"
        root.renderingOrder = 30
        trackNode.renderingOrder = 30
        fillNode.renderingOrder = 30
        root.addChildNode(trackNode)
        root.addChildNode(fillNode)
        powerwall.addChildNode(root)
        HouseGroundPlate.omitFromReflection(root)
        root.isHidden = true
    }

    /// `fraction` is nil until a percentage has arrived, then 0...1.
    func setFraction(_ fraction: Float?) {
        guard let fraction else {
            root.isHidden = true
            return
        }
        let clamped = min(max(fraction, 0), 1)
        root.isHidden = false
        fillNode.isHidden = clamped < 0.005
        fillNode.geometry = PowerwallLevelFace.quad(face: face, fraction: clamped, material: fillMaterial)
    }
}

struct PowerwallLevelFace {
    var normal: SIMD3<Float>
    var center: SIMD3<Float>
    var side: SIMD3<Float>
    var up: SIMD3<Float>

    /// The narrow vertical end closer to the camera. The broad faces of the unit are left alone.
    static func nearest(minBound: SIMD3<Float>, maxBound: SIMD3<Float>, camera: SIMD3<Float>) -> PowerwallLevelFace? {
        let extents = maxBound - minBound
        guard extents.min() > 0 else { return nil }
        let thin = extents.x <= extents.y && extents.x <= extents.z ? 0 : (extents.y <= extents.z ? 1 : 2)
        let end = [0, 2].filter { $0 != thin }.max(by: { extents[$0] < extents[$1] }) ?? (thin == 2 ? 0 : 2)
        let center = (minBound + maxBound) * 0.5
        var plus = center
        var minus = center
        plus[end] = maxBound[end]
        minus[end] = minBound[end]
        let sign: Float = simd_length(camera - plus) <= simd_length(camera - minus) ? 1 : -1
        var faceCenter = center
        faceCenter[end] = sign > 0 ? maxBound[end] : minBound[end]
        var normal = SIMD3<Float>.zero
        normal[end] = sign
        let upAxis = end == 1 ? 2 : 1
        let sideAxis = 3 - end - upAxis
        // The bar runs the full height of the unit. A little is held in from
        // the sides so it stays on the flat end instead of the rounded corners.
        let sideInset: Float = 0.86
        var side = SIMD3<Float>.zero
        side[sideAxis] = (maxBound[sideAxis] - minBound[sideAxis]) * 0.5 * sideInset
        var up = SIMD3<Float>.zero
        up[upAxis] = (maxBound[upAxis] - minBound[upAxis]) * 0.5
        faceCenter += normal * 0.003
        return PowerwallLevelFace(normal: normal, center: faceCenter, side: side, up: up)
    }

    /// `fraction` grows the quad up from the bottom of the face. 1 is the full inset face.
    static func quad(face: PowerwallLevelFace, fraction: Float, material: SCNMaterial) -> SCNGeometry {
        let clamped = min(max(fraction, 0), 1)
        let bottom = face.center - face.up
        let top = bottom + face.up * (2 * clamped)
        let span = face.side
        let corners = [bottom - span, bottom + span, top + span, top - span].map { SCNVector3($0.x, $0.y, $0.z) }
        let source = SCNGeometrySource(vertices: corners)
        let element = SCNGeometryElement(indices: [UInt32(0), 1, 2, 0, 2, 3], primitiveType: .triangles)
        let geometry = SCNGeometry(sources: [source], elements: [element])
        geometry.materials = [material]
        return geometry
    }
}
