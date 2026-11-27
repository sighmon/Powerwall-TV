//
//  VehicleWheels.swift
//  Powerwall-TV
//
//  The car usdz files carry no wheels. Each has four empty `WheelAnchor_LF/RF/LR/RR` nodes at the hub
//  centres, and this mounts one wheel usdz (`Wheel_*.usdz`, see TeslaWheel.swift) on each. The wheel
//  file is drawn for the right side, +X forward and +Z out; the left anchors are turned 180° about Y in
//  the file, so the same wheel faces out on both sides. Mounting drops each wheel so its tyre touches
//  the floor, since a 20" tyre is taller than an 18" one on the same hub.
//

import SceneKit
import simd

extension WheelChoice {
    /// Owned cars wear their `wheel_type`. Catalogue cars wear the model's standard wheels until
    /// edit mode sets `wearsChosenWheel`.
    static func resolve(for request: CarShowroomRequest) -> WheelChoice? {
        let type = request.browsesCatalogue && !request.wearsChosenWheel ? nil : request.wheelType
        return resolve(wheelType: type, model: request.model)
    }
}

enum VehicleWheels {
    static let anchorPrefix = "WheelAnchor_"
    static let anchorNames = ["LF", "RF", "LR", "RR"].map { anchorPrefix + $0 }
    /// Mounted wheels are named this plus their usdz name, so a report or test can read what is on.
    static let mountPrefix = "VehicleWheel_"
    /// How far the tyre sits into the floor, in metres, so it reads as carrying weight.
    static let contact: Float = 0.005

    enum Look: String {
        /// Tesla's metal and roughness, for the showroom's studio reflections.
        case showroom
        /// No metal: the home has no environment for metal to reflect, so it would draw black.
        case home
    }

    private struct Template {
        let node: SCNNode
        /// Tyre radius in the wheel file, metres.
        let radius: Float
    }

    private static var templates: [String: Template] = [:]
    private static let lock = NSLock()

    /// Puts this choice's wheel on every anchor under `vehicle`, replacing whatever was mounted. Nil, or
    /// a usdz that fails to load, leaves the car with none. Returns how many wheels went on.
    @discardableResult
    static func mount(_ choice: WheelChoice?, on vehicle: SCNNode, look: Look) -> Int {
        unmount(from: vehicle)
        guard let choice else { return 0 }
        guard let template = template(asset: choice.asset, look: look) else {
            PaintDebug.log("wheels: \(choice.asset).usdz did not load")
            return 0
        }
        var mounted = 0
        for name in anchorNames {
            guard let anchor = vehicle.childNode(withName: name, recursively: true) else { continue }
            let wheel = template.node.clone()
            wheel.name = mountPrefix + choice.asset
            // The anchor's own scale (Model Y files are 1.05 wide) applies to the wheel, so the drop
            // is worked out in the car's space and handed back in the anchor's.
            let scaleY = max(simd_length(anchor.simdConvertVector(SIMD3(0, 1, 0), to: vehicle)), 0.0001)
            let hubY = anchor.simdConvertPosition(.zero, to: vehicle).y
            wheel.simdPosition = SIMD3(0, (template.radius * scaleY - contact - hubY) / scaleY, 0)
            anchor.addChildNode(wheel)
            mounted += 1
        }
        if mounted == 0 {
            PaintDebug.log("wheels: no \(anchorPrefix)* nodes under \(vehicle.name ?? "car")")
        }
        return mounted
    }

    static func unmount(from vehicle: SCNNode) {
        var mounted: [SCNNode] = []
        vehicle.enumerateHierarchy { node, _ in
            if node.name?.hasPrefix(mountPrefix) == true { mounted.append(node) }
        }
        mounted.forEach { $0.removeFromParentNode() }
    }

    /// The usdz names mounted under `vehicle`, one per wheel.
    static func mountedAssets(on vehicle: SCNNode) -> [String] {
        var assets: [String] = []
        vehicle.enumerateHierarchy { node, _ in
            guard let name = node.name, name.hasPrefix(mountPrefix) else { return }
            assets.append(String(name.dropFirst(mountPrefix.count)))
        }
        return assets
    }

    /// One wheel per usdz and look, loaded once. Clones share its geometry and materials.
    private static func template(asset: String, look: Look) -> Template? {
        let key = asset + "|" + look.rawValue
        lock.lock()
        defer { lock.unlock() }
        if let cached = templates[key] { return cached }
        guard let url = HouseLighting.resourceURL(name: asset, ext: "usdz"),
              let scene = try? SCNScene(url: url, options: nil) else { return nil }
        let node = SCNNode()
        scene.rootNode.childNodes.forEach { node.addChildNode($0) }
        var radius: Float = 0
        node.enumerateHierarchy { child, _ in
            guard let geometry = child.geometry else { return }
            dress(geometry, look: look)
            let box = geometry.boundingBox
            for y in [box.min.y, box.max.y] {
                for x in [box.min.x, box.max.x] {
                    let point = child.simdConvertPosition(SIMD3(Float(x), Float(y), 0), to: node)
                    radius = max(radius, abs(point.y))
                }
            }
        }
        guard radius > 0 else { return nil }
        let template = Template(node: node, radius: radius)
        templates[key] = template
        return template
    }

    private static func dress(_ geometry: SCNGeometry, look: Look) {
        // Each look gets its own materials, so the home's flat metal never reaches the showroom.
        geometry.materials = geometry.materials.map { original in
            let material = (original.copy() as? SCNMaterial) ?? original
            material.lightingModel = .physicallyBased
            if look == .home {
                material.metalness.contents = 0.0
            }
            return material
        }
    }
}
