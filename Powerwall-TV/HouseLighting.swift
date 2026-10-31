//
//  HouseLighting.swift
//  Powerwall-TV
//
//  SceneKit port of Tesla's Energy-view `Building.shader` (Godot 3, unshaded) plus
//  a WeatherKit → lighting mapping and rain/snow particles.
//
//  Building.shader recap (theme 0 = night/dark look, 1 = day/light look):
//    sun_dir      = mix((-0.5,0.8,2.5), (-0.5,0.3,2.5), theme)       // model space
//    ambient_str  = mix(0.35, 0.81, theme)
//    ambient      = (dot(N,sun)*0.5+0.5)*(1-ambient_str) + ambient_str + mix(0,0.06,theme)
//    mask         = texture(light_mask, uv)   R = environment/AO, G = tone, B = night window glow
//    tone         = pow(G,0.455)*2-1 ; darken = max(-tone,0) ; lighten = max(tone,0)
//    albedo       = mix(albedo_dark, albedo_light, theme) * (1-darken) + lighten
//    env_affect   = mix(1,0.5,theme) ; night_affect = mix(1,0,theme)
//    COLOR        = albedo * mix(1-env_affect,1,R) * ambient + night_light * night_affect * B * power
//
//  Unlike the original, the sun direction here is a free uniform so it can follow the real sun.
//

import Foundation
import SceneKit
import CoreLocation
import WeatherKit
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - Lighting parameters

struct HouseLightingParameters: Equatable {
    /// 0 = night/dark theme, 1 = full daylight theme (Building.shader `theme`).
    var theme: Float = 1
    /// Light direction in the house model's local space (Y up). Need not be normalised.
    var sunDirection: SIMD3<Float> = SIMD3(-0.5, 0.8, 2.5)
    /// Extra multiplier on the ambient term (cloud dimming; 1 = unchanged).
    var ambientScale: Float = 1
    /// Window/porch light glow strength, 0…1 (Building.shader `night_light_power`).
    var nightLightPower: Float = 1
    var albedoLight: SIMD3<Float> = SIMD3(1, 1, 1)
    var albedoDark: SIMD3<Float> = SIMD3(0.831, 0.831, 0.831)
    var nightLight: SIMD3<Float> = SIMD3(1.0, 0.894, 0.8)
    var rainIntensity: Float = 0   // 0…1, drives particle birth rate
    var snowIntensity: Float = 0   // 0…1
}

// MARK: - Shader modifiers

enum HouseShaderModifiers {

    /// Runs per vertex in model space, exactly like Building.shader's vertex().
    static let geometry = """
    #pragma arguments
    float geometryTheme;   // same value as `theme`; separate name avoids clashing with the fragment argument
    float ambientScale;
    float normalYSign;     // -1 flips a surface whose slats face the wrong way, such as the garage door
    float3 sunDirection;

    #pragma varyings
    float ambientLight;
    float doorRib;

    #pragma body
    float3 sunDir = normalize(sunDirection);
    float3 normal = normalize(_geometry.normal);
    normal.y *= normalYSign;
    float ambientStrength = mix(0.35, 0.81, geometryTheme);
    float sunLight = dot(normal, sunDir) * 0.5 + 0.5;
    out.ambientLight = ((sunLight * (1.0 - ambientStrength)) + ambientStrength + mix(0.0, 0.06, geometryTheme)) * ambientScale;
    // Garage slats are 4 cm apart and their normals point down, so the mask never
    // paints the bright lip home.png has along the top of each rib.
    out.doorRib = normalYSign < 0.0 ? fract(_geometry.position.y * 25.0) : 0.0;
    """

    /// Use with `lightingModel = .constant` so SceneKit lights don't double-light the house.
    static let fragment = """
    #pragma arguments
    float theme;
    float nightLightPower;
    float3 albedoLight;
    float3 albedoDark;
    float3 nightLight;
    texture2d<float, access::sample> lightMask;

    #pragma body
    constexpr sampler maskSampler(coord::normalized, filter::linear, address::repeat, mip_filter::linear);
    float4 mask = lightMask.sample(maskSampler, _surface.diffuseTexcoord);
    float environment = mask.r;
    float tone = mask.g;
    float night = mask.b;

    float environmentAffect = mix(1.0, 0.5, theme);
    float nightAffect = mix(1.0, 0.0, theme);
    // Atlas gutters are black. A linear sample on a seam would otherwise cut a dark line
    // along every hard edge of the shell.
    environment = max(environment, mix(0.45, 0.88, theme));

    // Day and night tints multiply the baked atlas. Replacing it with a flat colour
    // throws away the walls, door and trim and leaves the low-poly shell looking broken.
    float3 albedo = _surface.diffuse.rgb * mix(albedoDark, albedoLight, theme);
    tone = pow(max(tone, 0.0001), 0.455) * 2.0 - 1.0;
    float toneDarken = min(max(-tone, 0.0), 0.72);
    float toneLighten = max(tone, 0.0);
    float grade = mix(albedoDark.r, albedoLight.r, theme);
    albedo *= 1.0 - toneDarken;
    // The tone lift is an absolute add in Tesla's shader. Scale it with the grade
    // so it cannot wash the darkened walls back out.
    albedo += toneLighten * grade;

    float fadeEnv = mix(1.0 - environmentAffect, 1.0, environment);
    float3 colour = albedo * fadeEnv * in.ambientLight
                  + nightLight * nightAffect * night * nightLightPower;
    // Window panes are painted near-white in the atlas so they stay bright
    // while the walls take the dark grade. The reference art is lit glass.
    float glass = smoothstep(0.80, 0.84, _surface.diffuse.r);
    colour = mix(colour, _surface.diffuse.rgb, glass);
    float lip = smoothstep(0.55, 0.92, in.doorRib);
    colour += lip * float3(0.07, 0.07, 0.075);
    _output.color = float4(colour, 1.0);
    """

    /// Flat glass. The bundled glow mask is a radial blob, so sampling it
    /// lights only the middle of a window.
    static let windowFragment = """
    #pragma body
    _output.color = float4(float3(0.86, 0.87, 0.88), 1.0);
    """
}

extension HouseShaderModifiers {
    /// The baked panel art is a fine cell grid. On the roof it minifies into a few
    /// large octagons, and the UVs repeat that tile. Draw the grid from the roof's
    /// own surface instead: along the ridge (model Z) and down the slope.
    static let solarGeometry = """
    #pragma varyings
    float3 solarPos;

    #pragma body
    out.solarPos = _geometry.position.xyz;
    """

    static let solarFragment = """
    #pragma arguments
    float solarTheme;

    #pragma body
    float ridge = in.solarPos.z;
    float slope = in.solarPos.x * 0.8321 - in.solarPos.y * 0.5547;
    float2 g = float2(ridge * 5.0, slope * 4.2);
    float2 dist = min(fract(g), 1.0 - fract(g));
    float lx = 1.0 - smoothstep(0.012, 0.028, dist.x);
    float ly = 1.0 - smoothstep(0.012, 0.028, dist.y);
    float line = clamp(max(lx, ly), 0.0, 1.0);
    float3 cell = float3(0.055, 0.075, 0.12);
    float3 grid = float3(0.62, 0.67, 0.74);
    float3 colour = mix(cell, grid, line);
    float3 tint = mix(float3(0.55, 0.60, 0.70), float3(1.0, 1.0, 1.0), solarTheme);
    _output.color = float4(colour * tint, 1.0);
    """
}

// MARK: - Options

enum SolarOption: String, CaseIterable, Identifiable {
    case none, panels, solarRoof
    var id: String { rawValue }
}

/// Lightweight vehicle models in `vehicles/` (exported from the app's vehicle 3D view, interiors removed,
/// decimated to ~25–38k triangles). `generic` is the low-poly placeholder the Energy view itself uses.
enum VehicleModel: String, CaseIterable, Identifiable {
    case generic = "Generic"
    case model3 = "Model3"
    case model3Highland = "Model3Highland"
    case modelY = "ModelY"
    case modelYJuniper = "ModelYJuniper"
    case modelS = "ModelS"
    case modelX = "ModelX"
    case cybertruck = "Cybertruck"
    var id: String { rawValue }
}

// MARK: - Applying to the loaded scene

/// One roof slope, gathered from the round cell mesh so a single quad can cover it.
private struct SolarSlope {
    var points: [SIMD3<Float>] = []
    var normals: [SIMD3<Float>] = []

    mutating func add(_ point: SIMD3<Float>, normal n: SIMD3<Float>) {
        let length = simd_length(n)
        points.append(point)
        normals.append(length > 1e-5 ? n / length : SIMD3<Float>(0, 1, 0))
    }

    func fillNodes() -> [SCNNode] {
        guard points.count > 2 else { return [] }
        // The cell rims tilt. The sheet uses the flat face, where the normal
        // runs up the slope and has almost no ridge component.
        var sum = SIMD3<Float>.zero
        for normal in normals where abs(normal.z) < 0.08 && normal.y > 0.7 && normal.x > 0.3 {
            sum += normal
        }
        guard simd_length(sum) > 1e-5 else { return [] }
        let n = simd_normalize(sum)
        let axis = simd_normalize(cross(n, SIMD3<Float>(0, 0, 1)))
        let flat = points.indices.compactMap { index -> Float? in
            let normal = normals[index]
            guard abs(normal.z) < 0.08 && normal.y > 0.7 && normal.x > 0.3 else { return nil }
            return simd_dot(n, points[index])
        }.sorted()
        guard let first = flat.first, let last = flat.last else { return [] }
        var split = first
        var gap: Float = 0
        for index in 1..<flat.count {
            let step = flat[index] - flat[index - 1]
            if step > gap {
                gap = step
                split = (flat[index] + flat[index - 1]) * 0.5
            }
        }
        // The two roofs are parallel and about 0.7 m apart along the normal.
        let bands: [(Float, Float)] = gap > 0.05
            ? [(first - 0.05, split), (split, last + 0.05)]
            : [(first - 0.05, last + 0.05)]
        return bands.compactMap { band in
            sheet(normal: n, axis: axis, low: band.0, high: band.1)
        }
    }

    private func sheet(normal n: SIMD3<Float>, axis: SIMD3<Float>, low: Float, high: Float) -> SCNNode? {
        var height: Float = -.greatestFiniteMagnitude
        var alongMin: Float = .greatestFiniteMagnitude
        var alongMax: Float = -.greatestFiniteMagnitude
        var ridgeMin: Float = .greatestFiniteMagnitude
        var ridgeMax: Float = -.greatestFiniteMagnitude
        var used = 0
        for point in points {
            let distance = simd_dot(n, point)
            if distance < low || distance >= high { continue }
            used += 1
            height = max(height, distance)
            let along = simd_dot(axis, point)
            alongMin = min(alongMin, along)
            alongMax = max(alongMax, along)
            ridgeMin = min(ridgeMin, point.z)
            ridgeMax = max(ridgeMax, point.z)
        }
        guard used > 2 else { return nil }
        let ridge = SIMD3<Float>(0, 0, 1)
        // A millimetre proud of the cells, so the quad clears the roof underneath.
        let lift = height + 0.001
        func point(_ along: Float, _ ridgePos: Float) -> SCNVector3 {
            let p = n * lift + axis * along + ridge * ridgePos
            return SCNVector3(p.x, p.y, p.z)
        }
        let verts = [
            point(alongMin, ridgeMin),
            point(alongMax, ridgeMin),
            point(alongMax, ridgeMax),
            point(alongMin, ridgeMax),
        ]
        let indices: [UInt32] = [0, 1, 2, 0, 2, 3]
        let geometry = SCNGeometry(
            sources: [SCNGeometrySource(vertices: verts)],
            elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)]
        )
        geometry.firstMaterial = SCNMaterial()
        let node = SCNNode(geometry: geometry)
        node.name = "SolarFill"
        return node
    }
}

final class HouseLighting {
    let root: SCNNode
    private var buildingMaterials: [SCNMaterial] = []
    private var windowMaterials: [SCNMaterial] = []
    private var solarMaterials: [SCNMaterial] = []
    private var parkedVehicle: SCNNode?
    private(set) var solarOption: SolarOption = .panels
    private(set) var vehicleModel: VehicleModel = .generic
    private let rainNode = SCNNode()
    private let snowNode = SCNNode()
    private let sunLight = SCNNode()
    private let rain = HouseLighting.makeRain()
    private let snow = HouseLighting.makeSnow()
    private var parameters = HouseLightingParameters()
    /// Emitter volume relative to a 4,000 m³ reference, so a larger view stays the same density.
    private var coverageScale: CGFloat = 1

    /// - Parameters:
    ///   - root: the node loaded from ResidentialClassic.usdz (or .glb fallback).
    ///   - houseMask: Home_LightMask.png (R AO, G tone, B window glow). Loaded from the bundle if nil.
    ///   - garageMask: GarageDoor_LightMask.png.
    ///   - windowMask: Windows_GlowMask.png.
    init(root: SCNNode,
         houseMask: Any? = HouseLighting.bundleImage("Home_LightMask"),
         garageMask: Any? = HouseLighting.bundleImage("GarageDoor_LightMask"),
         windowMask: Any? = HouseLighting.bundleImage("Windows_GlowMask")) {
        self.root = root
        // The shell is missing a few hairline strips along walls and eaves. Cap those only.
        sealThinOpenings(named: "Home")

        // The baked day atlas is a light grey. home.png is charcoal, about a third of that,
        // with the glass left bright. These tints are that grade.
        _ = windowMask
        let dayGrade = SIMD3<Float>(0.27, 0.27, 0.28)
        let nightGrade = SIMD3<Float>(0.20, 0.21, 0.24)
        configureBuilding(named: "Home", mask: houseMask, albedoLight: dayGrade, albedoDark: nightGrade, normalYSign: 1)
        // The door slats' normals tilt downward, so overhead light catches them from below.
        configureBuilding(named: "GarageDoor", mask: garageMask, albedoLight: dayGrade, albedoDark: nightGrade, normalYSign: -1)
        squareWindowPanes(named: "Home")
        installFilledWindows()
        for material in materials(under: "Windows") {
            material.lightingModel = .constant
            material.isDoubleSided = true
            material.shaderModifiers = [.fragment: HouseShaderModifiers.windowFragment]
            windowMaterials.append(material)
        }

        // These cards are torn alpha planes. SceneKit draws their black RGB as solid
        // wedges, which reads as damage, so they stay out of the view.
        root.childNode(withName: "Shadow", recursively: true)?.isHidden = true
        root.childNode(withName: "GarageVehicleShadow", recursively: true)?.isHidden = true
        root.childNode(withName: "GroundReflection", recursively: true)?.isHidden = true

        // Powerwall, meter and connector have no shader. Left on the imported
        // physically based materials they render black, like holes in the wall.
        for name in ["Powerwall", "Meter", "WallConnector"] {
            for material in materials(under: name) {
                material.lightingModel = .constant
                material.isDoubleSided = true
            }
        }
        installFillLights()

        installSolidSolar(named: "SolarPanels")
        for name in ["SolarPanels", "SolarRoof"] {
            let isFill = name == "SolarPanels"
            for material in materials(under: name) {
                material.lightingModel = .constant
                // The cell mesh stays single-sided. The fill sheet is drawn from either side.
                material.isDoubleSided = isFill
                material.diffuse.wrapS = .repeat
                material.diffuse.wrapT = .repeat
                material.shaderModifiers = [
                    .geometry: HouseShaderModifiers.solarGeometry,
                    .fragment: HouseShaderModifiers.solarFragment,
                ]
                solarMaterials.append(material)
            }
        }
        setSolar(.panels)
        // Stay closed until live wall-connector state says a car is home.
        showVehicle(false)

        rainNode.name = "Rain"
        snowNode.name = "Snow"
        rainNode.position = SCNVector3(-1.6, 6, 0)
        snowNode.position = SCNVector3(-1.6, 6, 0)
        rainNode.addParticleSystem(rain)
        snowNode.addParticleSystem(snow)
        root.addChildNode(rainNode)
        root.addChildNode(snowNode)

        apply(HouseLightingParameters())
    }

    func apply(_ p: HouseLightingParameters, animated: Bool = true) {
        parameters = p
        SCNTransaction.begin()
        SCNTransaction.animationDuration = animated ? 1.5 : 0
        for material in buildingMaterials {
            material.setValue(NSNumber(value: p.theme), forKey: "theme")
            material.setValue(NSNumber(value: p.theme), forKey: "geometryTheme")
            material.setValue(NSNumber(value: p.ambientScale), forKey: "ambientScale")
            material.setValue(NSNumber(value: p.nightLightPower), forKey: "nightLightPower")
            material.setValue(NSValue(scnVector3: SCNVector3(p.sunDirection.x, p.sunDirection.y, p.sunDirection.z)),
                              forKey: "sunDirection")
            material.setValue(NSValue(scnVector3: SCNVector3(p.nightLight.x, p.nightLight.y, p.nightLight.z)),
                              forKey: "nightLight")
        }
        for material in solarMaterials {
            material.setValue(NSNumber(value: p.theme), forKey: "solarTheme")
        }
        // Windows glow when the house is dark.
        let windowBrightness = 0.25 + 0.75 * (1 - p.theme) * p.nightLightPower
        for material in windowMaterials {
            material.setValue(NSNumber(value: windowBrightness), forKey: "windowBrightness")
        }
        let sun = simd_normalize(p.sunDirection)
        sunLight.simdPosition = sun
        sunLight.look(at: SCNVector3(0, 0.4, 0))
        sunLight.light?.intensity = 350 + 650 * CGFloat(p.theme * p.ambientScale)
        SCNTransaction.commit()

        rain.birthRate = CGFloat(p.rainIntensity) * 90 * coverageScale
        snow.birthRate = CGFloat(p.snowIntensity) * 22 * coverageScale
    }

    /// Sizes the rain and snow volume to the camera frustum so precipitation covers the
    /// whole view, including the sky around the house, at a light density.
    func updateWeatherCoverage(camera: SCNNode, viewport: CGSize) {
        guard viewport.width > 1, viewport.height > 1 else { return }
        let holder = root.parent ?? root
        if rainNode.parent !== holder {
            holder.addChildNode(rainNode)
            holder.addChildNode(snowNode)
        }
        let vfov = Float((camera.camera?.fieldOfView ?? 30) * .pi / 180)
        let aspect = Float(viewport.width / viewport.height)
        let hfov = 2 * atan(tan(vfov / 2) * aspect)
        let transform = camera.simdWorldTransform
        let origin = SIMD3<Float>(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
        // SceneKit cameras look down their local −Z axis.
        let forward = -SIMD3<Float>(transform.columns.2.x, transform.columns.2.y, transform.columns.2.z)
        let up = SIMD3<Float>(transform.columns.1.x, transform.columns.1.y, transform.columns.1.z)
        let right = SIMD3<Float>(transform.columns.0.x, transform.columns.0.y, transform.columns.0.z)
        var minB = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
        var maxB = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
        for distance: Float in [0.8, 18] {
            let halfHeight = tan(vfov / 2) * distance
            let halfWidth = tan(hfov / 2) * distance
            for sx: Float in [-1, 1] {
                for sy: Float in [-1, 1] {
                    let corner = origin + forward * distance + right * (sx * halfWidth) + up * (sy * halfHeight)
                    minB = simd_min(minB, corner)
                    maxB = simd_max(maxB, corner)
                }
            }
        }
        maxB.y += 2.5
        let size = simd_max(maxB - minB, SIMD3<Float>(repeating: 2))
        let center = (minB + maxB) * 0.5
        let box = SCNBox(width: CGFloat(size.x), height: CGFloat(size.y), length: CGFloat(size.z), chamferRadius: 0)
        rain.emitterShape = box
        snow.emitterShape = box
        let local = holder.convertPosition(SCNVector3(center.x, center.y, center.z), from: nil)
        rainNode.position = local
        snowNode.position = local
        // 4,000 m³ ≈ the framed house view. Scale the count with volume and keep the spacing.
        coverageScale = CGFloat((size.x * size.y * size.z) / 4000)
        rain.birthRate = CGFloat(parameters.rainIntensity) * 90 * coverageScale
        snow.birthRate = CGFloat(parameters.snowIntensity) * 22 * coverageScale
    }

    // MARK: Solar & vehicle

    /// The app instances SolarPanel.tscn or SolarRoof.tscn under the identity-transform `Solar` node.
    /// The Solar Roof is a full shell ~1 cm above the normal roof; the app does NOT hide the normal roof.
    func setSolar(_ option: SolarOption) {
        solarOption = option
        root.childNode(withName: "SolarPanels", recursively: true)?.isHidden = option != .panels
        root.childNode(withName: "SolarRoof", recursively: true)?.isHidden = option != .solarRoof
    }

    /// Shows/hides the parked car. The app opens the garage door whenever the car is home (the parked car
    /// pokes through the closed door), so the door is hidden while the vehicle is visible.
    func showWallConnector(_ visible: Bool) {
        root.childNode(withName: "WallConnector", recursively: true)?.isHidden = !visible
    }

    func showVehicle(_ visible: Bool) {
        root.childNode(withName: "Vehicle", recursively: true)?.isHidden = !visible
        root.childNode(withName: "GarageVehicleShadow", recursively: true)?.isHidden = true
        root.childNode(withName: "GarageDoor", recursively: true)?.isHidden = visible
    }

    /// Swaps the parked car for one of the exported Tesla models, painted `paint`.
    /// Car files are in metres, nose towards −Z, origin on the ground at the car's centre, matching
    /// GenericVehicle; the app parks it at (−0.7, 0.02, 0.7) with scale 0.35.
    func setVehicleModel(_ model: VehicleModel, paint: HouseColor? = nil) {
        vehicleModel = model
        guard let vehicle = root.childNode(withName: "Vehicle", recursively: true) else { return }
        parkedVehicle?.removeFromParentNode()
        parkedVehicle = nil
        // The baked generic body (already positioned) is the "VehicleBody_0" child.
        let generic = vehicle.childNodes.filter { $0.name?.hasPrefix("VehicleBody") == true }
        if model == .generic {
            generic.forEach { $0.isHidden = false }
            return
        }
        guard let url = HouseLighting.resourceURL(name: model.rawValue, ext: "usdz"),
              let scene = try? SCNScene(url: url, options: nil) else {
            generic.forEach { $0.isHidden = false }
            return
        }
        generic.forEach { $0.isHidden = true }
        let car = SCNNode()
        car.name = "VehicleModel_\(model.rawValue)"
        scene.rootNode.childNodes.forEach { car.addChildNode($0) }
        car.position = SCNVector3(-0.7, 0.02, 0.7)
        car.scale = SCNVector3(0.35, 0.35, 0.35)
        vehicle.addChildNode(car)
        parkedVehicle = car
        // v2 shells are closed from the outside, but several cards are single-sided.
        // Draw both sides so a window or wheel well does not read as a hole.
        car.enumerateHierarchy { node, _ in
            node.geometry?.materials.forEach { $0.isDoubleSided = true }
        }
        if let paint { setVehiclePaint(paint) }
    }

    /// Paint is the material named "Paint" (for Cybertruck it is the stainless body, so use a grey or a wrap colour).
    /// Flat colour (kept for custom colours).
    func setVehiclePaint(_ colour: HouseColor) {
        parkedVehicle?.enumerateHierarchy { node, _ in
            node.geometry?.materials.filter { $0.name == "Paint" }.forEach { $0.diffuse.contents = colour }
        }
    }

    /// Paints the car with the Tesla app's own paint values (see TeslaPaint.swift).
    func setVehiclePaint(_ paint: TeslaPaint, displayBoost: CGFloat = 1, clearCoat: CGFloat = 0) {
        parkedVehicle?.enumerateHierarchy { node, _ in
            node.geometry?.materials.filter { $0.name == "Paint" }.forEach {
                paint.apply(to: $0, displayBoost: displayBoost, clearCoat: clearCoat)
            }
        }
    }

    /// Convenience for Fleet API `vehicle_data`: vehicle_config.exterior_color plus the optional
    /// vehicle_config.paint_color_override and vehicle_state.colorizer_paint_remap_enabled.
    func setVehiclePaint(exteriorColor: String?, paintColorOverride: String? = nil,
                         colorizerRemap: Bool = false, displayBoost: CGFloat = 1) {
        setVehiclePaint(TeslaPaint.resolve(exteriorColor: exteriorColor,
                                           paintColorOverride: paintColorOverride,
                                           colorizerRemap: colorizerRemap),
                        displayBoost: displayBoost)
    }

    // MARK: Helpers

    private func installFillLights() {
        let ambient = SCNNode()
        ambient.name = "HouseFill"
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 320
        ambient.light?.color = HouseColor(white: 0.9, alpha: 1)
        root.addChildNode(ambient)

        sunLight.name = "HouseSun"
        sunLight.light = SCNLight()
        sunLight.light?.type = .directional
        sunLight.light?.intensity = 700
        sunLight.light?.castsShadow = false
        root.addChildNode(sunLight)
    }

    private func configureBuilding(named name: String, mask: Any?, albedoLight: SIMD3<Float>, albedoDark: SIMD3<Float>, normalYSign: Float) {
        for material in materials(under: name) {
            // Keep the baked base colour as `diffuse` so SceneKit provides UVs (_surface.diffuseTexcoord)
            // and so the model still looks right if the modifier fails to compile.
            material.lightingModel = .constant
            material.isDoubleSided = true
            material.diffuse.mipFilter = .linear
            material.diffuse.maxAnisotropy = 8
            if let mask { material.setValue(SCNMaterialProperty(contents: mask), forKey: "lightMask") }
            material.setValue(NSValue(scnVector3: SCNVector3(albedoLight.x, albedoLight.y, albedoLight.z)), forKey: "albedoLight")
            material.setValue(NSValue(scnVector3: SCNVector3(albedoDark.x, albedoDark.y, albedoDark.z)), forKey: "albedoDark")
            material.setValue(NSNumber(value: normalYSign), forKey: "normalYSign")
            material.shaderModifiers = [
                .geometry: HouseShaderModifiers.geometry,
                .fragment: HouseShaderModifiers.fragment,
            ]
            buildingMaterials.append(material)
        }
    }

    /// The street windows are octagonal holes in the side wall, and the glass sits
    /// behind them, so the corners stay dark. A card on each pane covers the hole
    /// out to a rectangle. Bounds are the opening lips on the wall at x ≈ 0.
    private func installFilledWindows() {
        guard let windows = root.childNode(withName: "Windows", recursively: true) else { return }
        windows.enumerateHierarchy { child, _ in
            if child.geometry != nil { child.isHidden = true }
        }
        let x: Float = 0.014
        // A few millimetres past the lip, so the card covers the chamfered corners.
        let panes: [(Float, Float, Float, Float)] = [
            (0.221, 0.407, -1.100, -0.813),
            (0.432, 0.618, -1.100, -0.813),
            (0.221, 0.407, -0.787, -0.502),
            (0.432, 0.618, -0.787, -0.502),
        ]
        var verts: [SCNVector3] = []
        var indices: [UInt32] = []
        for pane in panes {
            let base = UInt32(verts.count)
            // +X faces the camera. This winding points the front at +X.
            verts += [
                SCNVector3(x, pane.0, pane.2),
                SCNVector3(x, pane.1, pane.2),
                SCNVector3(x, pane.1, pane.3),
                SCNVector3(x, pane.0, pane.3),
            ]
            indices += [base, base + 1, base + 2, base, base + 2, base + 3]
        }
        let geometry = SCNGeometry(
            sources: [SCNGeometrySource(vertices: verts)],
            elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)]
        )
        geometry.firstMaterial = SCNMaterial()
        let node = SCNNode(geometry: geometry)
        node.name = "WindowPanes"
        windows.addChildNode(node)
    }

    /// The panel mesh is a field of round cells, so the roof shows through between them.
    /// Replace each camera-facing slope with one quad across the cell footprint.
    private func installSolidSolar(named name: String) {
        guard let solar = root.childNode(withName: name, recursively: true) else { return }
        var slope = SolarSlope()
        solar.enumerateHierarchy { child, _ in
            guard let geometry = child.geometry,
                  let positions = geometry.sources(for: .vertex).first,
                  let normals = geometry.sources(for: .normal).first else { return }
            let pos = HouseLighting.components(positions)
            let nor = HouseLighting.components(normals)
            let count = min(pos.count, nor.count) / 3
            for i in 0..<count {
                let n = SIMD3(nor[i * 3], nor[i * 3 + 1], nor[i * 3 + 2])
                if n.y < 0.55 || n.x < 0.2 { continue }
                let p = SIMD3(pos[i * 3], pos[i * 3 + 1], pos[i * 3 + 2])
                slope.add(p, normal: n)
            }
            child.isHidden = true
        }
        for node in slope.fillNodes() {
            solar.addChildNode(node)
        }
    }

    /// The street windows are four rounded cutouts in the home atlas. Fill each one
    /// out to a rectangle of lit glass, which is how they read in home.png.
    /// Rects are top-left pixels of the 1024² day atlas.
    private func squareWindowPanes(named name: String) {
        // Cover the rounded frame as well as the dark glass, so each opening
        // reads as a rectangle. A gap is left for the mullion.
        let panes = [
            CGRect(x: 612, y: 588, width: 80, height: 124),
            CGRect(x: 700, y: 588, width: 80, height: 124),
            CGRect(x: 612, y: 712, width: 80, height: 116),
            CGRect(x: 700, y: 712, width: 80, height: 116),
        ]
        for material in materials(under: name) {
            guard let painted = HouseTexture.squarePanes(material.diffuse.contents, panes: panes) else { continue }
            material.diffuse.contents = painted
        }
    }

    /// Fans a cap across boundary loops that are long in one direction and only a few
    /// centimetres in the other two. Window holes, the garage mouth, the open underside
    /// and the solar rims are larger than that and stay open.
    private func sealThinOpenings(named name: String) {
        guard let node = root.childNode(withName: name, recursively: true) else { return }
        node.enumerateHierarchy { child, _ in
            guard let geometry = child.geometry,
                  let sealed = HouseMeshSeam.sealThinCracks(geometry) else { return }
            child.geometry = sealed
        }
    }

    /// Packed float components of a geometry source. Positions and normals are three floats.
    fileprivate static func components(_ source: SCNGeometrySource) -> [Float] {
        let count = source.vectorCount * source.componentsPerVector
        var out = [Float](repeating: 0, count: count)
        source.data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            for i in 0..<source.vectorCount {
                let start = base.advanced(by: i * source.dataStride + source.dataOffset)
                for c in 0..<source.componentsPerVector {
                    out[i * source.componentsPerVector + c] = start
                        .advanced(by: c * source.bytesPerComponent)
                        .assumingMemoryBound(to: Float.self)
                        .pointee
                }
            }
        }
        return out
    }

    private func materials(under name: String) -> [SCNMaterial] {
        guard let node = root.childNode(withName: name, recursively: true) else { return [] }
        var result: [SCNMaterial] = []
        node.enumerateHierarchy { child, _ in
            if let geometry = child.geometry { result.append(contentsOf: geometry.materials) }
        }
        return result
    }

    static func bundleImage(_ name: String) -> Any? {
        guard let url = resourceURL(name: name, ext: "png") else { return nil }
        #if canImport(UIKit)
        return UIImage(contentsOfFile: url.path)
        #elseif canImport(AppKit)
        return NSImage(contentsOfFile: url.path)
        #else
        return nil
        #endif
    }

    /// Synchronized Xcode groups may copy `TeslaAssets/` as a subdirectory or flatten it.
    static func resourceURL(name: String, ext: String) -> URL? {
        Bundle.main.url(forResource: name, withExtension: ext)
            ?? Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "TeslaAssets")
    }

    private static func makeRain() -> SCNParticleSystem {
        let p = SCNParticleSystem()
        p.birthRate = 0
        p.particleLifeSpan = 3.2
        p.warmupDuration = 1
        p.emitterShape = SCNBox(width: 28, height: 14, length: 28, chamferRadius: 0)
        p.birthLocation = .volume
        p.particleVelocity = 2.2
        p.particleVelocityVariation = 0.4
        p.emittingDirection = SCNVector3(0, -1, 0)
        p.spreadingAngle = 4
        p.particleSize = 0.012
        p.stretchFactor = 0.05
        p.particleColor = HouseColor(white: 0.85, alpha: 0.22)
        p.blendMode = .alpha
        p.isAffectedByGravity = false
        p.isLightingEnabled = false
        return p
    }

    private static func makeSnow() -> SCNParticleSystem {
        let p = SCNParticleSystem()
        p.birthRate = 0
        p.particleLifeSpan = 9
        p.warmupDuration = 1
        p.emitterShape = SCNBox(width: 28, height: 14, length: 28, chamferRadius: 0)
        p.birthLocation = .volume
        p.particleVelocity = 0.35
        p.particleVelocityVariation = 0.15
        p.emittingDirection = SCNVector3(0, -1, 0)
        p.spreadingAngle = 18
        p.particleSize = 0.014
        p.particleSizeVariation = 0.006
        p.particleColor = HouseColor(white: 1, alpha: 0.45)
        p.blendMode = .alpha
        p.isAffectedByGravity = false
        p.isLightingEnabled = false
        return p
    }
}

// MARK: - WeatherKit mapping

struct WeatherLighting {
    /// Rotation of the house model relative to true north, in degrees.
    /// 0 means the model's +Z axis (garage/street side) faces north; 180 faces south.
    var houseHeadingDegrees: Double = 180

    func parameters(for weather: CurrentWeather, location: CLLocation) -> HouseLightingParameters {
        let sun = SolarPosition.compute(date: weather.date, coordinate: location.coordinate)
        return parameters(sunAltitude: sun.altitude,
                          sunAzimuth: sun.azimuth,
                          isDaylight: weather.isDaylight,
                          cloudCover: weather.cloudCover,
                          condition: weather.condition,
                          precipitationMillimetresPerHour: weather.precipitationIntensity.converted(to: .metersPerSecond).value * 3_600_000)
    }

    func parameters(sunAltitude: Double, sunAzimuth: Double, isDaylight: Bool, cloudCover: Double,
                    condition: WeatherCondition, precipitationMillimetresPerHour: Double) -> HouseLightingParameters {
        var p = HouseLightingParameters()
        let clouds = min(max(cloudCover, 0), 1)

        // Theme: twilight ramp from civil dusk (−6°) to 10° sun altitude, darkened by cloud cover.
        var theme = smoothstep(-6, 10, sunAltitude)
        if !isDaylight { theme = min(theme, 0.2) }
        theme *= 1 - 0.35 * clouds
        p.theme = Float(theme)

        // Clouds flatten directional light and dim ambient.
        p.ambientScale = Float(1 - 0.25 * clouds)

        // Sun direction in house-local space (Y up). SceneKit/USD: −Z is "forward"; we treat +Z as the
        // heading direction, so rotate the world azimuth into model space.
        let alt = max(sunAltitude, 3) * .pi / 180   // keep a little top light even at night
        let az = (sunAzimuth - houseHeadingDegrees) * .pi / 180
        let world = SIMD3<Double>(sin(az) * cos(alt), sin(alt), cos(az) * cos(alt))
        // Under heavy cloud, bias light straight down (diffuse sky).
        let overcast = SIMD3<Double>(0, 1, 0.3)
        let d = world * (1 - 0.6 * clouds) + overcast * (0.6 * clouds)
        p.sunDirection = SIMD3(Float(d.x), Float(d.y), Float(d.z))

        p.nightLightPower = Float(1 - smoothstep(-2, 6, sunAltitude) * 0.9)

        let intensity = Float(min(max(precipitationMillimetresPerHour / 8, 0), 1))
        switch condition {
        case .drizzle, .freezingDrizzle, .sunShowers:
            p.rainIntensity = min(intensity, 0.35)
        case .rain, .heavyRain, .freezingRain, .isolatedThunderstorms, .scatteredThunderstorms,
             .thunderstorms, .strongStorms, .tropicalStorm, .hurricane, .hail:
            p.rainIntensity = max(intensity, condition == .heavyRain ? 0.8 : 0.4)
        case .flurries, .sunFlurries:
            p.snowIntensity = 0.25
        case .snow, .heavySnow, .blizzard, .blowingSnow:
            p.snowIntensity = condition == .snow ? 0.5 : 1
        case .sleet, .wintryMix:
            p.rainIntensity = 0.3
            p.snowIntensity = 0.3
        default:
            break
        }
        return p
    }

    private func smoothstep(_ e0: Double, _ e1: Double, _ x: Double) -> Double {
        let t = min(max((x - e0) / (e1 - e0), 0), 1)
        return t * t * (3 - 2 * t)
    }
}

// MARK: - Solar position (NOAA simplified algorithm, ~0.5° accuracy)

enum SolarPosition {
    /// - Returns: altitude above the horizon and azimuth clockwise from true north, both in degrees.
    static func compute(date: Date, coordinate: CLLocationCoordinate2D) -> (altitude: Double, azimuth: Double) {
        let rad = Double.pi / 180
        let jd = date.timeIntervalSince1970 / 86400 + 2440587.5
        let n = jd - 2451545.0
        let meanLongitude = (280.460 + 0.9856474 * n).truncatingRemainder(dividingBy: 360)
        let meanAnomaly = (357.528 + 0.9856003 * n).truncatingRemainder(dividingBy: 360) * rad
        let eclipticLongitude = (meanLongitude + 1.915 * sin(meanAnomaly) + 0.020 * sin(2 * meanAnomaly)) * rad
        let obliquity = (23.439 - 0.0000004 * n) * rad
        let rightAscension = atan2(cos(obliquity) * sin(eclipticLongitude), cos(eclipticLongitude))
        let declination = asin(sin(obliquity) * sin(eclipticLongitude))

        let gmstHours = (18.697374558 + 24.06570982441908 * n).truncatingRemainder(dividingBy: 24)
        let localSiderealDegrees = gmstHours * 15 + coordinate.longitude
        let hourAngle = localSiderealDegrees * rad - rightAscension

        let lat = coordinate.latitude * rad
        let sinAlt = sin(lat) * sin(declination) + cos(lat) * cos(declination) * cos(hourAngle)
        let altitude = asin(sinAlt)
        let azimuth = atan2(-sin(hourAngle),
                            tan(declination) * cos(lat) - sin(lat) * cos(hourAngle))
        var azDeg = azimuth / rad
        if azDeg < 0 { azDeg += 360 }
        return (altitude / rad, azDeg)
    }
}

// MARK: - Hairline caps

enum HouseMeshSeam {
    /// Returns a copy with thin boundary slits capped, or nil when there is nothing to add.
    static func sealThinCracks(_ geometry: SCNGeometry) -> SCNGeometry? {
        let sources = geometry.sources
        guard sources.allSatisfy({ [.vertex, .normal, .texcoord].contains($0.semantic) }),
              let vertex = geometry.sources(for: .vertex).first,
              let element = geometry.elements.first(where: { $0.primitiveType == .triangles }) else { return nil }
        let positions = vectors3(vertex)
        let indices = triangles(element)
        guard positions.count > 2, indices.count >= 3 else { return nil }
        let normals = geometry.sources(for: .normal).first.map(vectors3)
        let uvs = geometry.sources(for: .texcoord).first.map(vectors2)

        var weldOf: [SIMD3<Int>: Int] = [:]
        var weld = [Int](repeating: 0, count: positions.count)
        var representative: [Int] = []
        for index in positions.indices {
            let point = positions[index]
            let key = SIMD3(Int((point.x * 500).rounded()),
                            Int((point.y * 500).rounded()),
                            Int((point.z * 500).rounded()))
            if let existing = weldOf[key] {
                weld[index] = existing
            } else {
                let id = representative.count
                weldOf[key] = id
                weld[index] = id
                representative.append(index)
            }
        }

        struct Edge: Hashable { var a, b: Int }
        var edgeCount: [Edge: Int] = [:]
        for triangle in stride(from: 0, to: indices.count, by: 3) {
            let corners = [weld[indices[triangle]], weld[indices[triangle + 1]], weld[indices[triangle + 2]]]
            if Set(corners).count < 3 { continue }
            for corner in 0..<3 {
                let a = corners[corner]
                let b = corners[(corner + 1) % 3]
                let edge = Edge(a: min(a, b), b: max(a, b))
                edgeCount[edge, default: 0] += 1
            }
        }
        var neighbors: [Int: [Int]] = [:]
        for (edge, count) in edgeCount where count == 1 {
            neighbors[edge.a, default: []].append(edge.b)
            neighbors[edge.b, default: []].append(edge.a)
        }

        var used: Set<Edge> = []
        var addedPositions: [SIMD3<Float>] = []
        var addedNormals: [SIMD3<Float>] = []
        var addedUVs: [SIMD2<Float>] = []
        var addedIndices: [Int] = []
        for start in neighbors.keys.sorted() {
            for next in neighbors[start] ?? [] {
                let first = Edge(a: min(start, next), b: max(start, next))
                if used.contains(first) { continue }
                var loop = [start]
                var previous = -1
                var current = start
                var steps = 0
                var closed = false
                while steps < 32 {
                    steps += 1
                    let choices = (neighbors[current] ?? []).filter { $0 != previous }
                    guard let step = choices.first(where: { candidate in
                        !used.contains(Edge(a: min(current, candidate), b: max(current, candidate)))
                    }) else { break }
                    used.insert(Edge(a: min(current, step), b: max(current, step)))
                    if step == start {
                        closed = true
                        break
                    }
                    loop.append(step)
                    previous = current
                    current = step
                }
                guard closed, loop.count >= 3, loop.count <= 12 else { continue }
                let points = loop.map { positions[representative[$0]] }
                var minPoint = points[0]
                var maxPoint = points[0]
                for point in points {
                    minPoint = simd_min(minPoint, point)
                    maxPoint = simd_max(maxPoint, point)
                }
                let span = [maxPoint.x - minPoint.x, maxPoint.y - minPoint.y, maxPoint.z - minPoint.z].sorted()
                // Second-largest span: a slit is thin in two axes. A window is thin in only one.
                guard span[1] < 0.10 else { continue }
                let center = points.reduce(SIMD3<Float>.zero, +) / Float(points.count)
                let centerIndex = positions.count + addedPositions.count
                addedPositions.append(center)
                if normals != nil {
                    let normal = loop.reduce(SIMD3<Float>.zero) { $0 + normals![representative[$1]] }
                    let length = simd_length(normal)
                    addedNormals.append(length > 0.0001 ? normal / length : SIMD3(0, 1, 0))
                }
                if uvs != nil {
                    addedUVs.append(uvs![representative[loop[0]]])
                }
                for corner in loop.indices {
                    let a = representative[loop[corner]]
                    let b = representative[loop[(corner + 1) % loop.count]]
                    addedIndices.append(contentsOf: [centerIndex, a, b])
                }
            }
        }
        guard !addedIndices.isEmpty else { return nil }

        var newSources: [SCNGeometrySource] = []
        for source in sources {
            switch source.semantic {
            case .vertex:
                newSources.append(source3(positions + addedPositions, semantic: .vertex))
            case .normal:
                let base = normals ?? Array(repeating: SIMD3<Float>(0, 1, 0), count: positions.count)
                newSources.append(source3(base + addedNormals, semantic: .normal))
            case .texcoord:
                let base = uvs ?? Array(repeating: SIMD2<Float>.zero, count: positions.count)
                newSources.append(source2(base + addedUVs, semantic: .texcoord))
            default:
                return nil
            }
        }
        var indexValues = indices + addedIndices
        let bytesPerIndex = element.bytesPerIndex
        let indexData: Data
        if bytesPerIndex == 2 {
            indexData = indexValues.withUnsafeMutableBufferPointer { buffer in
                let words = buffer.map { UInt16(truncatingIfNeeded: $0) }
                return words.withUnsafeBytes { Data($0) }
            }
        } else {
            indexData = indexValues.withUnsafeMutableBufferPointer { buffer in
                let words = buffer.map { UInt32(truncatingIfNeeded: $0) }
                return words.withUnsafeBytes { Data($0) }
            }
        }
        let primitiveCount = (indices.count + addedIndices.count) / 3
        let rebuilt = SCNGeometryElement(data: indexData, primitiveType: .triangles, primitiveCount: primitiveCount, bytesPerIndex: bytesPerIndex)
        let sealed = SCNGeometry(sources: newSources, elements: [rebuilt])
        sealed.materials = geometry.materials
        sealed.name = geometry.name
        return sealed
    }

    private static func source3(_ values: [SIMD3<Float>], semantic: SCNGeometrySource.Semantic) -> SCNGeometrySource {
        var packed = [Float]()
        packed.reserveCapacity(values.count * 3)
        for value in values {
            packed.append(value.x)
            packed.append(value.y)
            packed.append(value.z)
        }
        let data = packed.withUnsafeBytes { Data($0) }
        return SCNGeometrySource(data: data, semantic: semantic, vectorCount: values.count, usesFloatComponents: true, componentsPerVector: 3, bytesPerComponent: 4, dataOffset: 0, dataStride: 12)
    }

    private static func source2(_ values: [SIMD2<Float>], semantic: SCNGeometrySource.Semantic) -> SCNGeometrySource {
        var packed = [Float]()
        packed.reserveCapacity(values.count * 2)
        for value in values {
            packed.append(value.x)
            packed.append(value.y)
        }
        let data = packed.withUnsafeBytes { Data($0) }
        return SCNGeometrySource(data: data, semantic: semantic, vectorCount: values.count, usesFloatComponents: true, componentsPerVector: 2, bytesPerComponent: 4, dataOffset: 0, dataStride: 8)
    }

    private static func vectors3(_ source: SCNGeometrySource) -> [SIMD3<Float>] {
        let count = source.vectorCount
        var values = [SIMD3<Float>]()
        values.reserveCapacity(count)
        source.data.withUnsafeBytes { raw in
            let base = raw.baseAddress!
            for index in 0..<count {
                var value = SIMD3<Float>.zero
                memcpy(&value, base.advanced(by: source.dataOffset + index * source.dataStride), 12)
                values.append(value)
            }
        }
        return values
    }

    private static func vectors2(_ source: SCNGeometrySource) -> [SIMD2<Float>] {
        let count = source.vectorCount
        var values = [SIMD2<Float>]()
        values.reserveCapacity(count)
        source.data.withUnsafeBytes { raw in
            let base = raw.baseAddress!
            for index in 0..<count {
                var value = SIMD2<Float>.zero
                memcpy(&value, base.advanced(by: source.dataOffset + index * source.dataStride), 8)
                values.append(value)
            }
        }
        return values
    }

    private static func triangles(_ element: SCNGeometryElement) -> [Int] {
        let count = element.primitiveCount * 3
        var values = [Int]()
        values.reserveCapacity(count)
        element.data.withUnsafeBytes { raw in
            if element.bytesPerIndex == 2 {
                let words = raw.bindMemory(to: UInt16.self)
                for index in 0..<count { values.append(Int(words[index])) }
            } else {
                let words = raw.bindMemory(to: UInt32.self)
                for index in 0..<count { values.append(Int(words[index])) }
            }
        }
        return values
    }
}

// MARK: - Textures matched to home.png

enum HouseTexture {
    /// `panes` are top-left rectangles in a 1024² atlas. They are scaled to the image.
    static func squarePanes(_ contents: Any?, panes: [CGRect]) -> Any? {
        guard let source = cgImage(from: contents) else { return nil }
        let width = source.width
        let height = source.height
        let scale = CGFloat(width) / 1024
        return image(width: width, height: height) { context in
            context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
            context.setFillColor(CGColor(red: 0.86, green: 0.87, blue: 0.88, alpha: 1))
            for pane in panes {
                let paneWidth = pane.width * scale
                let paneHeight = pane.height * scale
                let x = pane.origin.x * scale
                let y = CGFloat(height) - pane.origin.y * scale - paneHeight
                context.fill(CGRect(x: x, y: y, width: paneWidth, height: paneHeight))
            }
        }
    }

    private static func image(width: Int, height: Int, draw: (CGContext) -> Void) -> Any {
        let space = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return CGColor(gray: 0.2, alpha: 1) as Any }
        draw(context)
        guard let rendered = context.makeImage() else { return CGColor(gray: 0.2, alpha: 1) as Any }
        #if canImport(UIKit)
        return UIImage(cgImage: rendered)
        #elseif canImport(AppKit)
        return NSImage(cgImage: rendered, size: NSSize(width: width, height: height))
        #else
        return rendered
        #endif
    }

    private static func cgImage(from contents: Any?) -> CGImage? {
        #if canImport(AppKit)
        if let image = contents as? NSImage {
            var proposed = CGRect(origin: .zero, size: image.size)
            return image.cgImage(forProposedRect: &proposed, context: nil, hints: nil)
        }
        #endif
        #if canImport(UIKit)
        if let image = contents as? UIImage { return image.cgImage }
        #endif
        return nil
    }
}

// MARK: - Loading helper

enum ResidentialClassicScene {
    /// Loads ResidentialClassic.usdz (or .scn/.glb-converted fallback) from the app bundle.
    static func load() -> SCNScene? {
        for ext in ["usdz", "scn"] {
            if let url = HouseLighting.resourceURL(name: "ResidentialClassic", ext: ext),
               let scene = try? SCNScene(url: url, options: [.checkConsistency: true]) {
                return scene
            }
        }
        return nil
    }
}
