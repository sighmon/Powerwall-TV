//
//  ShowroomStage.swift
//  Powerwall-TV
//
//  The stage the Tesla app puts a car on, rebuilt in SceneKit. Values come from the
//  Tesla Android app 4.62.5 asset pack (decompiled with GDRE Tools):
//
//  - mobile.tscn, env/mobile.tres, mobile/scripts/EnvironmentManager.gd: dark theme
//    background #161718, a PanoramaSky of shared_misc_textures/New_Studio.png, and no lights.
//  - mobile/scripts/MobileEnvTest.gd and Snapshots.gd (PARKED pose): the sky turned by
//    (0, -11, 83) degrees, background energy 6, ambient 2.6, camera (-25°, -138°) at
//    (-4.13, 3.09, -4.73) with a 30° field of view.
//  - mobile/nodes/reflective_floor.tscn, mobile/materials/reflective_floor.shader,
//    mobile/scripts/ReflectiveFloor.gd, Ego/v2023/Poppyseed/Terrain/*: an unshaded floor in the
//    background colour, a half-resolution mirror at 10% strength, fading out between 5 m and 15 m,
//    and a paint-coloured glow plane 16.3 m behind the car at 26% opacity.
//  - Ego/*/Textures/Ground_AO*.png on each car's Floor quad: the baked contact shadow.
//
//  SceneKit has no rotation for `lightingEnvironment`, so ShowroomStudio.png is New_Studio.png
//  with the (0, -11, 83) sky rotation already baked in (Godot panorama convention).
//

import SceneKit
import simd
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

enum ShowroomStage {
    // MARK: Background and environment

    /// EnvironmentManager.dark_background_color.
    static let backgroundRGB = SIMD3<Float>(22, 23, 24) / 255
    static var backgroundColour: HouseColor {
        HouseColor(red: CGFloat(backgroundRGB.x), green: CGFloat(backgroundRGB.y), blue: CGFloat(backgroundRGB.z), alpha: 1)
    }

    static let environmentName = "ShowroomStudio"
    /// The app lights the car only with the studio panorama (radiance energy 6, ambient 2.6 on
    /// the app's very dark paint albedos). Our paint is lifted to display colours, so the same
    /// panorama runs at a lower SceneKit intensity. Raise it for shinier paint.
    static let environmentIntensity: CGFloat = 2.2

    // MARK: Floor

    static let floorName = "ShowroomFloor"
    static let mirrorName = "ShowroomMirror"
    /// reflective_floor.tres `reflection_strength`.
    static let reflectionStrength: CGFloat = 0.1
    /// reflective_floor.shader: `1 - smoothstep(5, 15, distance)`.
    static let floorFadeStart: Float = 5
    static let floorFadeEnd: Float = 15
    /// Terrain.tscn scales a 2 m PlaneMesh by 15.
    static let floorSize: CGFloat = 30

    // MARK: Glow

    static let glowName = "ShowroomGlow"
    static let glowHalfWidth: Float = 8.2
    static let glowHalfHeight: Float = 4.3
    /// Beyond the glow centre, away from the camera.
    static let glowDistance: Float = 16.3
    static let glowCentreHeight: Float = 1
    static let glowReferenceCameraDistance: Float = 15.8
    /// Terrain.tscn `night_mode_highlight_fade`.
    static let glowOpacity: Float = 0.26
    /// ReflectiveFloor.GLOW_ELEVATION_FADE, on the camera's downward look (sine of the elevation).
    static let glowElevationFade: (start: Float, end: Float) = (0.6, 0.85)

    // MARK: Contact shadow

    static let groundShadowName = "ShowroomGroundShadow"

    /// The car's Floor quad from its Godot scene, in model space (nose −Z), and the Ground_AO
    /// texture turned so that row 0 is the nose and column 0 is −X.
    struct GroundShadow: Equatable {
        var texture: String
        var minX: Float
        var maxX: Float
        var minZ: Float
        var maxZ: Float

        var width: Float { maxX - minX }
        var length: Float { maxZ - minZ }
        var centre: SIMD2<Float> { SIMD2((minX + maxX) / 2, (minZ + maxZ) / 2) }

        /// Floor quad shared by Model 3, Model 3 Highland, Model Y, Model S, and Model X.
        static func standard(_ texture: String) -> GroundShadow {
            GroundShadow(texture: texture, minX: -2.104, maxX: 2.104, minZ: -3.458, maxZ: 3.122)
        }
    }

    /// Juniper's exported ground texture is empty, so it borrows Highland's. Generic borrows Model 3's.
    static func groundShadow(for model: VehicleModel) -> GroundShadow {
        switch model {
        case .model3, .generic: return .standard("Model3_GroundAO")
        case .model3Highland, .modelYJuniper: return .standard("Model3Highland_GroundAO")
        case .modelY: return .standard("ModelY_GroundAO")
        case .modelS: return .standard("ModelS_GroundAO")
        case .modelX: return .standard("ModelX_GroundAO")
        case .cybertruck:
            return GroundShadow(texture: "Cybertruck_GroundAO", minX: -2.043, maxX: 2.157, minZ: -3.912, maxZ: 3.888)
        }
    }

    // MARK: Paint highlight

    /// Terrain.ColorToHighlightMap.
    static let highlightTable: [String: UInt32] = [
        "RedMulticoat": 0xf13d3d,
        "SolidBlack": 0x6d6d6d,
        "SilverMetallic": 0xc1c1c1,
        "MidnightSilver": 0x999ea9,
        "DeepBlue": 0x1667ee,
        "PearlWhite": 0xdadada,
        "MidnightCherryRed": 0xeb4b69,
        "Quicksilver": 0xd0d9f7,
        "UltraRed": 0xf03042,
        "StealthGrey": 0x929ba7,
        "GlacierBlue": 0x42599c,
        "DiamondBlack": 0x6d6d6d,
        "SilkroadSilver": 0xc1c1c1,
        "MarineBlue": 0x1f4b75,
    ]

    /// Closest table paint to the colour each exported file carries when no paint is applied.
    static func fileHighlightName(for model: VehicleModel) -> String {
        switch model {
        case .model3, .generic, .cybertruck: return "SilverMetallic"
        case .model3Highland: return "DeepBlue"
        case .modelY: return "PearlWhite"
        case .modelYJuniper: return "StealthGrey"
        case .modelS: return "RedMulticoat"
        case .modelX: return "SolidBlack"
        }
    }

    /// Glow colour for this car, as sRGB 0…1. Same order as ReflectiveFloor.get_paint_highlight_color:
    /// the table by paint name, then `calculate_highlight_for_paint_color` on the paint itself.
    static func highlight(for request: CarShowroomRequest) -> SIMD3<Float> {
        let wrap = request.paintColorOverride?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let keepsFileColour = request.model == .generic
            || (request.model == .cybertruck && wrap.isEmpty)
            || (request.browsesCatalogue && wrap.isEmpty)
        if keepsFileColour {
            return rgb(highlightTable[fileHighlightName(for: request.model)] ?? 0xc1c1c1)
        }
        if let name = request.exteriorColor, let paint = TeslaPaint(exteriorColor: name),
           let hex = highlightTable[paint.name] {
            return rgb(hex)
        }
        let paint = TeslaPaint.resolve(
            exteriorColor: request.exteriorColor,
            paintColorOverride: request.paintColorOverride,
            colorizerRemap: request.colorizerRemap
        )
        return highlight(forPaint: rgb(paint.hex))
    }

    /// Terrain.calculate_highlight_for_paint_color after Vehicle.remap_color (value × 0.325).
    static func highlight(forPaint paint: SIMD3<Float>) -> SIMD3<Float> {
        var (hue, saturation, value) = hsv(paint)
        value *= 0.325
        value = min(max(value * 5, 0), 0.7)
        let minimum: Float = 0.4
        if value < minimum {
            let share = (minimum - value) / minimum
            value += min(max(share * 0.5, 0), 0.5)
            saturation *= 1 - share
        }
        hue = hue.isFinite ? hue : 0
        return rgb(hue: hue, saturation: saturation, value: value)
    }

    // MARK: Install

    /// Background, studio lighting, floor, glow, and contact shadow around a car parked at `carPosition`.
    /// Add the car's reflection with `makeMirror(of:)` once the car is in place.
    static func install(in scene: SCNScene, carPosition: SIMD3<Float>, model: VehicleModel, highlight: SIMD3<Float>) {
        scene.background.contents = backgroundColour
        if let url = HouseLighting.resourceURL(name: environmentName, ext: "png") {
            scene.lightingEnvironment.contents = url
            scene.lightingEnvironment.intensity = environmentIntensity
        }

        let floorNode = makeFloor(centre: carPosition)
        scene.rootNode.addChildNode(floorNode)

        let glow = makeGlow(colour: highlight)
        scene.rootNode.addChildNode(glow)

        if let shadow = makeGroundShadow(groundShadow(for: model), carPosition: carPosition) {
            scene.rootNode.addChildNode(shadow)
        }
    }

    /// The mirror is an upside-down copy of the car under a floor that lets 10% of it through,
    /// like the app's reflection camera. It does not use SCNFloor reflections or a shader
    /// modifier. Neither showed on an older macOS, and a copy renders the same everywhere.
    /// The floor is the background colour, so only the mirror shows near the car. Far away the
    /// floor turns transparent and lets the glow behind the car through, like reflective_floor.shader.
    static func makeFloor(centre: SIMD3<Float>) -> SCNNode {
        let plane = SCNPlane(width: floorSize, height: floorSize)
        let material = SCNMaterial()
        material.name = floorName
        material.lightingModel = .constant
        material.diffuse.contents = floorImage()
        material.blendMode = .alpha
        material.transparencyMode = .aOne
        material.writesToDepthBuffer = true
        material.readsFromDepthBuffer = true
        plane.materials = [material]
        let node = SCNNode(geometry: plane)
        node.name = floorName
        node.eulerAngles.x = -.pi / 2
        node.simdPosition = SIMD3(centre.x, 0, centre.z)
        // After the glow and the mirror, before the car and the contact shadow.
        node.renderingOrder = -10
        node.castsShadow = false
        return node
    }

    /// How much of the floor covers what is under it, `distance` metres from the car centre.
    static func floorOpacity(atDistance distance: Float) -> Float {
        (1 - Float(reflectionStrength)) * (1 - HouseSky.smoothstep(floorFadeStart, floorFadeEnd, distance))
    }

    /// Background colour with `floorOpacity` in alpha, centred on the plane.
    static func floorImage(size: Int = 256) -> CGImage {
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        let last = Float(size - 1)
        let half = Float(floorSize) / 2
        let colour = backgroundRGB
        for y in 0..<size {
            for x in 0..<size {
                let u = Float(x) / last * 2 - 1
                let v = Float(y) / last * 2 - 1
                let alpha = floorOpacity(atDistance: sqrt(u * u + v * v) * half)
                let index = (y * size + x) * 4
                pixels[index] = UInt8(colour.x * 255 + 0.5)
                pixels[index + 1] = UInt8(colour.y * 255 + 0.5)
                pixels[index + 2] = UInt8(colour.z * 255 + 0.5)
                pixels[index + 3] = UInt8(min(max(alpha, 0), 1) * 255 + 0.5)
            }
        }
        let provider = CGDataProvider(data: Data(pixels) as CFData)!
        return CGImage(
            width: size,
            height: size,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: size * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )!
    }

    /// The car flipped through the floor (y = 0). The copy shares the car's geometry and
    /// materials, so paint changes show in both. Drawn before the floor, which blends over it.
    static func makeMirror(of vehicle: SCNNode) -> SCNNode {
        let mirror = vehicle.clone()
        mirror.name = mirrorName
        var position = vehicle.simdPosition
        position.y = -position.y
        mirror.simdPosition = position
        mirror.simdScale = vehicle.simdScale * SIMD3(1, -1, 1)
        mirror.enumerateHierarchy { node, _ in
            node.renderingOrder = -15
            node.castsShadow = false
            // The flip turns the faces inside out.
            guard let geometry = node.geometry else { return }
            if geometry.materials.contains(where: { $0.name == VehicleLamps.glassName }) {
                // The lamp lens draws one layer of smoke. Double-sided would add a second, so the
                // mirror gets its own lens copy that culls the (now flipped) front faces instead.
                // The copied geometry still shares the vertex data and every other material.
                let flipped = (geometry.copy() as? SCNGeometry) ?? geometry
                flipped.materials = geometry.materials.map { material in
                    guard material.name == VehicleLamps.glassName,
                          let lens = material.copy() as? SCNMaterial else { return material }
                    lens.isDoubleSided = false
                    lens.cullMode = .front
                    return lens
                }
                node.geometry = flipped
            }
            node.geometry?.materials.forEach { material in
                if material.name != VehicleLamps.glassName { material.isDoubleSided = true }
            }
        }
        return mirror
    }

    static func makeGlow(colour: SIMD3<Float>) -> SCNNode {
        let plane = SCNPlane(width: CGFloat(glowHalfWidth * 2), height: CGFloat(glowHalfHeight * 2))
        let material = SCNMaterial()
        material.name = glowName
        material.lightingModel = .constant
        material.diffuse.contents = glowImage(colour: colour)
        material.isDoubleSided = true
        material.blendMode = .alpha
        material.transparencyMode = .aOne
        material.writesToDepthBuffer = false
        material.readsFromDepthBuffer = true
        material.transparency = CGFloat(glowOpacity)
        plane.materials = [material]
        let node = SCNNode(geometry: plane)
        node.name = glowName
        node.renderingOrder = -20
        node.castsShadow = false
        return node
    }

    static func makeGroundShadow(_ shadow: GroundShadow, carPosition: SIMD3<Float>) -> SCNNode? {
        guard let url = HouseLighting.resourceURL(name: shadow.texture, ext: "png") else { return nil }
        let plane = SCNPlane(width: CGFloat(shadow.width), height: CGFloat(shadow.length))
        let material = SCNMaterial()
        material.name = groundShadowName
        material.lightingModel = .constant
        material.diffuse.contents = url
        material.blendMode = .alpha
        material.transparencyMode = .aOne
        material.writesToDepthBuffer = false
        material.readsFromDepthBuffer = true
        plane.materials = [material]
        let node = SCNNode(geometry: plane)
        node.name = groundShadowName
        // SCNPlane stands in XY with its image upright toward +Z. Lying flat puts the image top at −Z, the nose.
        node.eulerAngles.x = -.pi / 2
        let centre = shadow.centre
        node.simdPosition = SIMD3(carPosition.x + centre.x, carPosition.y + 0.003, carPosition.z + centre.y)
        node.renderingOrder = -5
        node.castsShadow = false
        return node
    }

    // MARK: Glow placement

    struct GlowPlacement {
        var transform: simd_float4x4
        var opacity: Float
    }

    /// ReflectiveFloor.update_glow_plane and update_glow_elevation_fade. The plane faces the
    /// camera from 16.3 m beyond a point 1 m above the floor centre, and grows with its distance
    /// so it covers the same share of the frame. Looking down more than ~37° fades it out.
    static func glowPlacement(eye: SIMD3<Float>, forward: SIMD3<Float>, centre: SIMD3<Float>) -> GlowPlacement? {
        let glowCentre = SIMD3(centre.x, glowCentreHeight, centre.z)
        let toCentre = glowCentre - eye
        let distance = max(simd_length(toCentre), 0.01)
        let direction = toCentre / distance
        let facing = -direction
        let worldUp = SIMD3<Float>(0, 1, 0)
        var up = worldUp - facing * simd_dot(facing, worldUp)
        guard simd_length_squared(up) > 0.0001 else { return nil }
        up = simd_normalize(up)
        let right = simd_normalize(simd_cross(up, facing))
        let scale = (distance + glowDistance) / distance
            * glowReferenceCameraDistance / (glowReferenceCameraDistance + glowDistance)
        let origin = eye + direction * (distance + glowDistance)
        var transform = matrix_identity_float4x4
        transform.columns.0 = SIMD4(right * scale, 0)
        transform.columns.1 = SIMD4(up * scale, 0)
        transform.columns.2 = SIMD4(facing, 0)
        transform.columns.3 = SIMD4(origin, 1)
        let lookingDown = -simd_normalize(forward).y
        let fade = 1 - HouseSky.smoothstep(glowElevationFade.start, glowElevationFade.end, lookingDown)
        return GlowPlacement(transform: transform, opacity: glowOpacity * fade)
    }

    /// Moves the glow for the current camera. Call after every orbit change.
    static func updateGlow(in scene: SCNScene, camera: SCNNode, centre: SIMD3<Float>) {
        guard let glow = scene.rootNode.childNode(withName: glowName, recursively: false),
              let placement = glowPlacement(eye: camera.simdWorldPosition, forward: camera.simdWorldFront, centre: centre) else { return }
        glow.simdTransform = placement.transform
        glow.geometry?.firstMaterial?.transparency = CGFloat(placement.opacity)
    }

    // MARK: Images and colour

    /// BackgroundPlane.shader: full colour inside half the radius, `1 - smoothstep(0.5, 1, r)` beyond.
    /// The plane's material transparency carries the 26% opacity.
    static func glowImage(colour: SIMD3<Float>, size: Int = 128) -> CGImage {
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        let last = Float(size - 1)
        let red = UInt8(min(max(colour.x, 0), 1) * 255)
        let green = UInt8(min(max(colour.y, 0), 1) * 255)
        let blue = UInt8(min(max(colour.z, 0), 1) * 255)
        for y in 0..<size {
            for x in 0..<size {
                let u = abs(Float(x) / last * 2 - 1)
                let v = abs(Float(y) / last * 2 - 1)
                let radius = sqrt(u * u + v * v)
                let alpha = 1 - HouseSky.smoothstep(0.5, 1, radius)
                let index = (y * size + x) * 4
                pixels[index] = red
                pixels[index + 1] = green
                pixels[index + 2] = blue
                pixels[index + 3] = UInt8(min(max(alpha, 0), 1) * 255)
            }
        }
        let provider = CGDataProvider(data: Data(pixels) as CFData)!
        return CGImage(
            width: size,
            height: size,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: size * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )!
    }

    static func rgb(_ hex: UInt32) -> SIMD3<Float> {
        SIMD3(Float((hex >> 16) & 0xff), Float((hex >> 8) & 0xff), Float(hex & 0xff)) / 255
    }

    static func hsv(_ colour: SIMD3<Float>) -> (hue: Float, saturation: Float, value: Float) {
        let maximum = max(colour.x, colour.y, colour.z)
        let minimum = min(colour.x, colour.y, colour.z)
        let delta = maximum - minimum
        var hue: Float = 0
        if delta > 0 {
            if maximum == colour.x {
                hue = (colour.y - colour.z) / delta
            } else if maximum == colour.y {
                hue = (colour.z - colour.x) / delta + 2
            } else {
                hue = (colour.x - colour.y) / delta + 4
            }
            hue /= 6
            if hue < 0 { hue += 1 }
        }
        let saturation = maximum > 0 ? delta / maximum : 0
        return (hue, saturation, maximum)
    }

    static func rgb(hue: Float, saturation: Float, value: Float) -> SIMD3<Float> {
        let sector = (hue - floor(hue)) * 6
        let index = Int(sector) % 6
        let fraction = sector - Float(Int(sector))
        let p = value * (1 - saturation)
        let q = value * (1 - saturation * fraction)
        let t = value * (1 - saturation * (1 - fraction))
        switch index {
        case 0: return SIMD3(value, t, p)
        case 1: return SIMD3(q, value, p)
        case 2: return SIMD3(p, value, t)
        case 3: return SIMD3(p, q, value)
        case 4: return SIMD3(t, p, value)
        default: return SIMD3(value, p, q)
        }
    }
}
