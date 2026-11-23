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
import CoreGraphics
import WeatherKit
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - Ground plate

/// Black plate under the house. SceneKit mirrors the house into it and fades
/// that mirror out, the way the flat home image does.
/// Tesla's house Shadow card. CompactShadow.shader draws it black with
/// alpha = (1 − green) × 2 (ResidentialClassic.tscn: strength 2, exponent 1). The same
/// black-plus-alpha form as the showroom's Ground_AO contact shadow, baked into
/// Home_GroundShadow.png by docs/showroom/tools/bake_house_shadow.py.
enum HouseGroundShadow {
    static let nodeName = "Shadow"
    static let texture = "Home_GroundShadow"
    /// Above the plate and the sky wash (0), below the house (2).
    static let renderingOrder = 1
    /// Lifts the card off the plate so it does not z-fight. Metres.
    static let lift: Float = 0.003

    /// Shows the card with the baked texture. Leaves it hidden if the texture is missing,
    /// which is how it drew before (solid black wedges otherwise).
    static func dress(_ root: SCNNode) {
        guard let card = root.childNode(withName: nodeName, recursively: true) else { return }
        guard let url = HouseLighting.resourceURL(name: texture, ext: "png") else {
            card.isHidden = true
            return
        }
        card.isHidden = false
        card.simdPosition.y += lift
        card.castsShadow = false
        card.enumerateHierarchy { node, _ in
            guard let geometry = node.geometry else { return }
            node.castsShadow = false
            geometry.materials = [material(contents: url)]
        }
    }

    static func material(contents: Any) -> SCNMaterial {
        let material = SCNMaterial()
        material.name = "HouseGroundShadow"
        material.lightingModel = .constant
        material.diffuse.contents = contents
        material.blendMode = .alpha
        material.transparencyMode = .aOne
        material.writesToDepthBuffer = false
        material.readsFromDepthBuffer = true
        material.isDoubleSided = true
        return material
    }
}

/// The parked car is lit like the showroom: the studio panorama at a lower strength, dimmed with
/// the house theme at night, plus a weak sun. Light category bits keep this off the house, and the
/// house's ambient and sun off the car.
enum HouseCarLighting {
    /// Light category for the car. Bit 3 is the floor-reflection bit; bit 0 is SceneKit's default.
    static let lightBit = 1 << 4
    /// The house fill and sun: every category except the car's.
    static let houseLightMask = ~lightBit
    static let probeName = "HouseCarStudio"
    static let sunName = "HouseCarSun"
    /// Big enough to hold the garage and driveway. Parallax correction is off, so this only bounds it.
    static let probeExtent: Float = 30

    /// Studio strength by day, as a share of the showroom's `ShowroomStage.environmentIntensity` (2.2).
    static let dayStrength: CGFloat = 1.2
    /// Share of `dayStrength` left at night (theme 0).
    static let nightFraction: CGFloat = 0.25
    /// The car's sun as a share of the house sun (350 + 650 × theme lumens).
    static let sunFraction: CGFloat = 0.35

    /// SCNLight lumens: 1000 is an environment intensity of 1.
    static func environmentIntensity(theme: Float, ambientScale: Float) -> CGFloat {
        let t = CGFloat(min(max(theme, 0), 1))
        let dim = nightFraction + (1 - nightFraction) * t
        return 1000 * dayStrength * dim * CGFloat(max(ambientScale, 0))
    }

    static func sunIntensity(theme: Float, ambientScale: Float) -> CGFloat {
        (350 + 650 * CGFloat(min(max(theme, 0), 1) * max(ambientScale, 0))) * sunFraction
    }

    /// Puts every node under the car in the car's light category only. Clearing bit 0 takes it out
    /// of the house lights; the floor-reflection bit is already off for cars.
    static func mark(_ node: SCNNode) {
        node.enumerateHierarchy { child, _ in
            child.categoryBitMask = lightBit
        }
    }
}

enum HouseGroundPlate {
    static let name = "HouseGroundPlate"
    /// Nodes that keep this bit are drawn in the reflection.
    static let reflectionBit = 1 << 3

    /// The house shell, the Powerwall, and the windows. The garage door is part of the shell.
    private static let includedPrefixes = ["Home", "GarageDoor", "Powerwall", "Windows"]
    /// Solar, the gateway, ribbons, cars, and overlays stay out even when they sit under an included node.
    private static let excludedPrefixes = [
        "Solar", "Meter", "Gateway", "WallConnector", "Vehicle",
        "PowerFlow", "PowerwallLevel", "HouseSky", "Rain", "Snow",
        "Shadow", "GarageVehicleShadow", "GroundReflection", "HouseGroundPlate",
        "HouseFill", "HouseSun", "HouseCloud", "SunHalo", "SunDisc",
    ]

    static func install(on root: SCNNode) {
        guard root.childNode(withName: name, recursively: false) == nil else { return }
        let floor = SCNFloor()
        floor.reflectivity = 0.22
        // Height above the plate, in metres. The fade begins just up the wall and
        // is gone at the same 0.32 m height as before.
        floor.reflectionFalloffStart = 0.08
        floor.reflectionFalloffEnd = 0.32
        floor.reflectionCategoryBitMask = reflectionBit
        // A Core Image filter on this node skips the reflection pass entirely, so the
        // mirror stays full size. A smaller buffer only pixelates it.
        #if os(macOS)
        floor.reflectionResolutionScaleFactor = 1
        #endif
        let footprint = HouseCameraFraming.modelMax - HouseCameraFraming.modelMin
        let margin: Float = 2.4
        floor.width = CGFloat(footprint.x + margin * 2)
        floor.length = CGFloat(footprint.z + margin * 2)
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = HouseColor(red: 22 / 255, green: 23 / 255, blue: 24 / 255, alpha: 1)
        floor.materials = [material]
        let node = SCNNode(geometry: floor)
        node.name = name
        let centre = (HouseCameraFraming.modelMin + HouseCameraFraming.modelMax) * 0.5
        node.simdPosition = SIMD3(centre.x, -0.01, centre.z)
        root.addChildNode(node)
        assignReflection(on: root)
    }

    /// Clears the reflection bit on everything, then sets it on the house, Powerwall, and windows.
    static func assignReflection(on root: SCNNode) {
        func visit(_ node: SCNNode, ancestorIncluded: Bool) {
            let name = node.name ?? ""
            let excluded = excludedPrefixes.contains { name.hasPrefix($0) }
            let included = includedPrefixes.contains { name.hasPrefix($0) }
            let reflect = !excluded && (included || ancestorIncluded)
            if reflect {
                node.categoryBitMask |= reflectionBit
            } else {
                node.categoryBitMask &= ~reflectionBit
            }
            for child in node.childNodes {
                visit(child, ancestorIncluded: !excluded && (included || ancestorIncluded))
            }
        }
        visit(root, ancestorIncluded: false)
    }

    static func omitFromReflection(_ node: SCNNode) {
        node.categoryBitMask &= ~reflectionBit
        for child in node.childNodes {
            omitFromReflection(child)
        }
    }

    /// SceneKit's floor mirror uses a camera under the plate, so its view matrix
    /// has a negative determinant. The live camera does not. Discarding there
    /// removes the reflection without hiding the node on the house.
    static let reflectedFragment = """
    #pragma body
    float reflected = determinant(float3x3(scn_frame.viewTransform[0].xyz, scn_frame.viewTransform[1].xyz, scn_frame.viewTransform[2].xyz));
    if (reflected < 0.0) {
        discard_fragment();
    }
    """
}

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
    /// Degrees above the horizon. Negative is below it. The visible disc uses this;
    /// the fill light stays a little above the horizon so the house never goes unlit.
    var sunAltitude: Float = 35
    /// Clockwise from true north, degrees.
    var sunAzimuth: Float = 180
    /// Model +Z compass facing. 180 means the street side faces south.
    var houseHeading: Float = 180
    /// 0 clear … 1 overcast. Veils the sun disc and fills in the cloud wisps.
    /// Ambient dimming still uses the measured cover inside `WeatherLighting`.
    var cloudCover: Float = 0

    func interpolated(toward other: HouseLightingParameters, fraction: Float) -> HouseLightingParameters {
        let t = min(max(fraction, 0), 1)
        func mix(_ from: Float, _ to: Float) -> Float { from + (to - from) * t }
        func mix3(_ from: SIMD3<Float>, _ to: SIMD3<Float>) -> SIMD3<Float> { from + (to - from) * t }
        var copy = self
        copy.theme = mix(theme, other.theme)
        copy.sunDirection = mix3(sunDirection, other.sunDirection)
        copy.ambientScale = mix(ambientScale, other.ambientScale)
        copy.nightLightPower = mix(nightLightPower, other.nightLightPower)
        copy.albedoLight = mix3(albedoLight, other.albedoLight)
        copy.albedoDark = mix3(albedoDark, other.albedoDark)
        copy.nightLight = mix3(nightLight, other.nightLight)
        copy.rainIntensity = mix(rainIntensity, other.rainIntensity)
        copy.snowIntensity = mix(snowIntensity, other.snowIntensity)
        copy.sunAltitude = mix(sunAltitude, other.sunAltitude)
        copy.sunAzimuth = mix(sunAzimuth, other.sunAzimuth)
        copy.houseHeading = mix(houseHeading, other.houseHeading)
        copy.cloudCover = mix(cloudCover, other.cloudCover)
        return copy
    }
}

// MARK: - Visible sky

/// The house camera looks down a 30° frame, so the real sun is usually outside the picture.
/// The disc still follows the site's altitude and azimuth: east on the left, overhead at midday,
/// west on the right, gone at night, and faded by WeatherKit cloud cover.
enum HouseSky {
    struct Wisp: Equatable {
        var x: Float
        var y: Float
        var depth: Float
        var width: Float
        var height: Float
        /// Cloud cover at which this wisp is fully present.
        var threshold: Float
        var cirrus: Bool
    }

    struct Placement: Equatable {
        var sunPosition: SIMD3<Float>
        /// -1 is the left of the view, 1 is the right.
        var screenX: Float
        /// 0 is the look-at centre, 1 is the top of the frame.
        var screenY: Float
        var sunOpacity: Float
        var haloOpacity: Float
        var discRadius: Float
        var haloRadius: Float
        var sunColor: SIMD3<Float>
    }

    /// High wisps first, then lower puffs as the cover thickens.
    /// `y` is 0 at the view centre and 1 on the top edge, so 1 puts the middle of
    /// each card on that edge and leaves only the lower half on screen.
    /// Heights are metres on the sky card.
    static let wisps: [Wisp] = [
        Wisp(x: -0.62, y: 1, depth: -1.4, width: 11.0, height: 5.1, threshold: 0.34, cirrus: true),
        Wisp(x: 0.08, y: 1, depth: -2.2, width: 13.0, height: 4.7, threshold: 0.40, cirrus: true),
        Wisp(x: 0.60, y: 1, depth: -0.8, width: 9.5, height: 4.2, threshold: 0.48, cirrus: true),
        Wisp(x: -0.34, y: 1, depth: 0.3, width: 6.4, height: 5.1, threshold: 0.55, cirrus: false),
        Wisp(x: 0.40, y: 1, depth: -0.4, width: 7.2, height: 5.4, threshold: 0.64, cirrus: false),
        Wisp(x: -0.04, y: 1, depth: 0.7, width: 8.0, height: 6.0, threshold: 0.74, cirrus: false),
        Wisp(x: 0.70, y: 1, depth: 0.1, width: 5.2, height: 4.2, threshold: 0.82, cirrus: false),
        Wisp(x: -0.74, y: 1, depth: -0.9, width: 5.6, height: 3.9, threshold: 0.90, cirrus: false),
    ]

    struct SkyWash: Equatable {
        var top: SIMD3<Float>
        var bottom: SIMD3<Float>
        /// 0 at night, 1 once the sun is up. The plane peaks at `washPeak` opacity.
        var amount: Float
    }

    /// Deep purple higher in the wash and deep pink toward the horizon, blue
    /// once the sun is high. Colour fades across `washScreenFraction` of the
    /// screen and is clear before the plane ends.
    static func skyWash(altitude: Float) -> SkyWash {
        let amount = smoothstep(-4, 10, altitude)
        let day = smoothstep(16, 40, altitude)
        let sunsetTop = SIMD3<Float>(0.46, 0.14, 0.70)
        let sunsetBottom = SIMD3<Float>(0.88, 0.26, 0.58)
        let blueTop = SIMD3<Float>(0.26, 0.46, 0.86)
        let blueBottom = SIMD3<Float>(0.58, 0.76, 0.96)
        return SkyWash(
            top: sunsetTop + (blueTop - sunsetTop) * day,
            bottom: sunsetBottom + (blueBottom - sunsetBottom) * day,
            amount: amount
        )
    }

    static func placement(altitude: Float, azimuth: Float, heading: Float, cloudCover: Float,
                          eye: SIMD3<Float>, target: SIMD3<Float>, viewport: CGSize,
                          fieldOfView: Float = 30) -> Placement {
        let cover = min(max(cloudCover, 0), 1)
        let alt = altitude * .pi / 180
        let az = (azimuth - heading) * .pi / 180
        let world = SIMD3<Float>(sin(az) * cos(alt), sin(alt), cos(az) * cos(alt))
        let forward = simd_normalize(target - eye)
        let right = simd_normalize(cross(forward, SIMD3<Float>(0, 1, 0)))
        let up = simd_normalize(cross(right, forward))

        let side = min(max(world.x * 0.92, -0.82), 0.82)
        let rise = max(world.y, 0)
        let screenY = 0.30 + rise * 0.46
        let distance: Float = 22
        let halfHeight = tan(fieldOfView * .pi / 180 / 2) * distance
        let aspect = Float(viewport.width / max(viewport.height, 1))
        let halfWidth = halfHeight * max(aspect, 0.01)
        let position = eye + forward * distance + right * (side * halfWidth) + up * (screenY * halfHeight)

        let day = smoothstep(-5, 6, altitude)
        let veil = pow(1 - cover, 1.45)
        let warm = smoothstep(0, 26, altitude)
        let low = SIMD3<Float>(0.98, 0.34, 0.68)
        let high = SIMD3<Float>(1, 0.97, 0.90)
        let tint = low + (high - low) * warm
        let grey = SIMD3<Float>(0.86, 0.89, 0.93)
        return Placement(
            sunPosition: position,
            screenX: side,
            screenY: screenY,
            sunOpacity: day * veil,
            haloOpacity: day * (0.42 * veil + 0.08 * cover),
            discRadius: 1.35 + 1.2 * cover,
            haloRadius: 3.6 + 2.0 * cover,
            sunColor: tint + (grey - tint) * (cover * 0.65)
        )
    }

    static func wispOpacity(threshold: Float, cloudCover: Float, cirrus: Bool) -> Float {
        let cover = min(max(cloudCover, 0), 1)
        let t = smoothstep(threshold, threshold + 0.12, cover)
        return t * (cirrus ? 0.34 : 0.44)
    }

    /// Site-less preview. The arc crosses the camera's sky: east in the morning, overhead at noon, west in the evening.
    static func clockSun(at date: Date, heading: Double, calendar: Calendar = .current) -> (altitude: Double, azimuth: Double) {
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        let t = (Double(hour * 60 + minute) - 6 * 60) / (12 * 60)
        let altitude = (0...1).contains(t) ? sin(t * .pi) * 58 : -8
        var azimuth = (heading - 90 + t * 180).truncatingRemainder(dividingBy: 360)
        if azimuth < 0 { azimuth += 360 }
        return (altitude, azimuth)
    }

    static func smoothstep(_ edge0: Float, _ edge1: Float, _ value: Float) -> Float {
        let t = min(max((value - edge0) / (edge1 - edge0), 0), 1)
        return t * t * (3 - 2 * t)
    }

    /// Share of the screen, from the top, that still has colour.
    static let washScreenFraction: Float = 0.48
    /// Extra plane below that band. It stays clear so the fade ends before the quad edge.
    static let washFeatherFraction: Float = 0.2
    /// Peak opacity at the top edge.
    static let washPeak: Float = 0.25

    /// Full-precision blend. The window is 8-bit, so a peak of 0.25 only has a few dozen
    /// steps and they draw as lines toward the clear end. The colour is computed here,
    /// then dithered by half a step per screen pixel, which is what hides those lines.
    static func washShader(openGL: Bool) -> String {
        let span = washScreenFraction / (washScreenFraction + washFeatherFraction)
        let vec2 = openGL ? "vec2" : "float2"
        let vec3 = openGL ? "vec3" : "float3"
        let vec4 = openGL ? "vec4" : "float4"
        let noise = """
        float washNoise(\(vec2) pixel) {
            return fract(52.9829189 * fract(dot(pixel, \(vec2)(0.06711056, 0.00583715))));
        }
        """
        let uniforms = openGL ? """
        uniform \(vec3) washTop;
        uniform \(vec3) washBottom;
        uniform float washAmount;
        uniform float washPeak;
        uniform \(vec2) washPixels;
        \(noise)
        """ : """
        #pragma arguments
        \(vec3) washTop;
        \(vec3) washBottom;
        float washAmount;
        float washPeak;
        \(vec2) washPixels;

        #pragma declaration
        \(noise)
        """
        let body = """
        #pragma transparent
        #pragma body
        float down = clamp(_surface.diffuseTexcoord.y, 0.0, 1.0);
        float t = clamp(down / \(span), 0.0, 1.0);
        float fade = 1.0 - t;
        fade = fade * fade * (3.0 - 2.0 * fade);
        float alpha = clamp(washPeak * fade * washAmount, 0.0, 1.0);
        if (alpha <= 0.0) {
            _output.color = \(vec4)(0.0);
        } else {
            \(vec3) color = mix(washBottom, washTop, fade);
            \(vec2) pixel = floor(_surface.diffuseTexcoord * washPixels);
            alpha = clamp(alpha + (washNoise(pixel) - 0.5) / 255.0, 0.0, 1.0);
            _output.color = \(vec4)(color * alpha, alpha);
        }
        """
        return uniforms + "\n" + body
    }

    /// Picks the shader for the view that is actually drawing. OpenGL SceneKit ignores Metal.
    /// `washPixels` is the plane's size in screen pixels, so the dither stays one pixel wide.
    static func useWashShader(in view: SCNView) {
        guard let material = view.scene?.rootNode.childNode(withName: "HouseSkyWash", recursively: true)?.geometry?.firstMaterial else { return }
        #if os(macOS)
        let source = washShader(openGL: view.renderingAPI != .metal)
        let scale = view.window?.backingScaleFactor ?? view.layer?.contentsScale ?? 2
        #else
        let source = washShader(openGL: false)
        let scale = view.contentScaleFactor
        #endif
        if material.shaderModifiers?[.fragment] != source {
            material.shaderModifiers = [.fragment: source]
        }
        guard view.bounds.width > 1, view.bounds.height > 1 else { return }
        let band = CGFloat(washScreenFraction + washFeatherFraction)
        material.setValue(
            CGPoint(x: view.bounds.width * scale * 1.025, y: view.bounds.height * scale * band),
            forKey: "washPixels"
        )
    }
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
    float doorHeight;

    #pragma body
    float3 sunDir = normalize(sunDirection);
    float3 normal = normalize(_geometry.normal);
    if (normalYSign < 0.0) {
        // Each slat's face tilts up toward the street, so the high camera sees a few
        // open shelves. A shut door presents one face to the street, tipped down.
        normal = normalize(float3(0.0, -0.35, 1.0));
    }
    float ambientStrength = mix(0.35, 0.81, geometryTheme);
    float sunLight = dot(normal, sunDir) * 0.5 + 0.5;
    out.ambientLight = ((sunLight * (1.0 - ambientStrength)) + ambientStrength + mix(0.0, 0.06, geometryTheme)) * ambientScale;
    // Raw height. The rib is folded in the fragment: doing it here collapses every
    // slat to the same value, because both of its edges land on the same fraction.
    out.doorHeight = normalYSign < 0.0 ? _geometry.position.y : -1.0;
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
    // Window glass in the atlas stays bright while the walls take the dark grade.
    float glass = smoothstep(0.80, 0.84, _surface.diffuse.r);
    colour = mix(colour, _surface.diffuse.rgb, glass);
    if (in.doorHeight >= 0.0) {
        // Eighteen slats, 4 cm apart. The baked ribs sit in a UV band this mesh
        // never samples, and the grade crushes what's left to a black opening
        // with only the top few shelves still visible. Paint the same closed rib
        // on every slat: dark in the groove, light along the top edge.
        float rib = fract(in.doorHeight * 25.0);
        float band = rib * rib * (3.0 - 2.0 * rib);
        float luma = max(dot(colour, float3(0.333333)), 0.02);
        float level = mix(0.055, 0.095, theme);
        float3 flat = colour * (level / luma);
        colour = mix(flat * 0.70, flat * 2.10, band);
    }
    _output.color = float4(colour, 1.0);
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

/// UsdPreviewSurface stores glass opacity on `transparent.contents` (0.85) and a
/// near-black albedo. On the dark plate the Cybertruck roof then reads as a hole.
enum VehicleGlass {
    static let transparency: CGFloat = 0.62

    static func reveal(_ material: SCNMaterial) {
        guard material.name == "Glass" else { return }
        material.lightingModel = .physicallyBased
        material.isDoubleSided = true
        material.diffuse.contents = HouseColor(red: 0.16, green: 0.20, blue: 0.24, alpha: 1)
        material.metalness.contents = 0.9
        material.roughness.contents = 0.08
        material.transparent.contents = HouseColor.white
        material.transparency = transparency
        material.transparencyMode = .dualLayer
        material.blendMode = .alpha
    }
}

/// The Tesla app parks the car with its lamps off. What makes them read as lamps is the
/// housing's own material: a texture atlas of chrome reflectors, red and amber lenses, and
/// LED strips (Lights_BC), with metallic, roughness, and occlusion packed in Lights_MRA,
/// under a thin smoked lens (Glass_Lights). The converter keeps the housing ("Lamps", with
/// texture coordinates) apart from the lens ("LampGlass"). The values below are the app's
/// SpatialMaterial values for each car. The glowing "on" overlays (Illumination, Lights_E)
/// are hidden until the car is driving, so they are not exported.
enum VehicleLamps {
    static let housingName = "Lamps"
    static let glassName = "LampGlass"

    /// The lamp housing material. `texture` is the asset prefix for `<texture>_Lamps_BC.png`
    /// and `<texture>_Lamps_MRA.png`. `albedo`, `metallic`, and `roughness` multiply the maps,
    /// as SpatialMaterial does. Without a texture they are flat values.
    struct Housing: Equatable {
        let texture: String?
        let albedo: CGFloat
        let metallic: CGFloat
        let roughness: CGFloat
    }

    /// The smoked lens over the lamps (Glass_Lights).
    struct Lens: Equatable {
        let albedo: CGFloat
        let opacity: CGFloat
        let roughness: CGFloat
    }

    static func housing(for model: VehicleModel) -> Housing? {
        switch model {
        case .model3: return Housing(texture: "Model3", albedo: 0.102, metallic: 0.7, roughness: 0)
        case .model3Highland: return Housing(texture: "Model3Highland", albedo: 0.137, metallic: 1, roughness: 1)
        case .modelY: return Housing(texture: "ModelY", albedo: 0.102, metallic: 0.7, roughness: 0.5)
        case .modelYJuniper: return Housing(texture: nil, albedo: 0.0196, metallic: 0, roughness: 0.45)
        case .modelS: return Housing(texture: "ModelS", albedo: 0.098, metallic: 0.75, roughness: 0.5)
        case .modelX: return Housing(texture: "ModelX", albedo: 0.098, metallic: 1, roughness: 1)
        case .cybertruck: return Housing(texture: "Cybertruck", albedo: 0.349, metallic: 0, roughness: 1)
        case .generic: return nil
        }
    }

    static func lens(for model: VehicleModel) -> Lens? {
        switch model {
        case .model3: return Lens(albedo: 0.0118, opacity: 0.51, roughness: 0.05)
        case .model3Highland, .modelY, .modelYJuniper: return Lens(albedo: 0.0118, opacity: 0.39, roughness: 0.05)
        case .modelS: return Lens(albedo: 0.0118, opacity: 0.43, roughness: 0.1)
        case .modelX: return Lens(albedo: 0.0118, opacity: 0.51, roughness: 0.1)
        case .cybertruck: return Lens(albedo: 0, opacity: 0.51, roughness: 0.01)
        case .generic: return nil
        }
    }

    /// Applies the Tesla app's lamp materials to every lamp material under `node`.
    static func dress(_ node: SCNNode, model: VehicleModel) {
        node.enumerateHierarchy { child, _ in
            child.geometry?.materials.forEach { dress($0, model: model) }
        }
    }

    static func dress(_ material: SCNMaterial, model: VehicleModel) {
        if material.name == housingName, let housing = housing(for: model) {
            apply(housing, to: material)
        } else if material.name == glassName, let lens = lens(for: model) {
            apply(lens, to: material)
        }
    }

    private static func apply(_ housing: Housing, to material: SCNMaterial) {
        material.lightingModel = .physicallyBased
        material.isDoubleSided = true
        material.emission.contents = HouseColor.black
        let colour = housing.texture.flatMap { HouseLighting.resourceURL(name: "\($0)_Lamps_BC", ext: "png") }
        let packed = housing.texture.flatMap { HouseLighting.resourceURL(name: "\($0)_Lamps_MRA", ext: "png") }
        if let colour, let packed {
            material.diffuse.contents = colour
            material.diffuse.intensity = housing.albedo
            material.metalness.contents = packed
            material.metalness.textureComponents = .red
            material.metalness.intensity = housing.metallic
            material.roughness.contents = packed
            material.roughness.textureComponents = .green
            material.roughness.intensity = housing.roughness
            material.ambientOcclusion.contents = packed
            material.ambientOcclusion.textureComponents = .blue
            for property in [material.diffuse, material.metalness, material.roughness, material.ambientOcclusion] {
                property.wrapS = .repeat
                property.wrapT = .repeat
                property.mappingChannel = 0
            }
        } else {
            material.diffuse.contents = HouseColor(white: housing.albedo, alpha: 1)
            material.metalness.contents = housing.metallic
            material.roughness.contents = housing.roughness
        }
    }

    private static func apply(_ lens: Lens, to material: SCNMaterial) {
        material.lightingModel = .physicallyBased
        material.isDoubleSided = true
        material.diffuse.contents = HouseColor(white: lens.albedo, alpha: 1)
        material.metalness.contents = 0
        material.roughness.contents = lens.roughness
        material.transparent.contents = HouseColor.white
        material.transparency = lens.opacity
        material.transparencyMode = .dualLayer
        material.blendMode = .alpha
        material.writesToDepthBuffer = false
    }
}

final class HouseLighting {
    let root: SCNNode
    private var buildingMaterials: [SCNMaterial] = []
    private var windowMaterials: [SCNMaterial] = []
    private var interiorLight: Float = -1
    private var parkedVehicle: SCNNode?
    private(set) var solarOption: SolarOption = .panels
    private(set) var vehicleModel: VehicleModel = .generic
    private let rainNode = SCNNode()
    private let snowNode = SCNNode()
    private let sunLight = SCNNode()
    /// Studio panorama and a dim sun that only reach the parked car (`HouseCarLighting`).
    private let carStudio = SCNNode()
    private let carSun = SCNNode()
    private let skyRig = SCNNode()
    private let sunDisc = SCNNode()
    private let sunHalo = SCNNode()
    private let skyWash = SCNNode()
    private var cloudCards: [SCNNode] = []
    private let rain = HouseLighting.makeRain()
    private let snow = HouseLighting.makeSnow()
    private var parameters = HouseLightingParameters()
    private var skyEye = HouseCameraFraming.position
    private var skyAim = HouseCameraFraming.subject
    private var skyViewport = CGSize(width: 1280, height: 720)
    private var skyFieldOfView: Float = HouseCameraFraming.verticalFOVDegrees
    /// Last sky-card half-width. Camera moves reuse it so the wisps are not repositioned.
    private var skyHalfWidth: Float = -1
    /// Last baked wash colours. A blend that does not change the sun reuses the image.
    private var bakedWashTop: SIMD3<Float>?
    private var bakedWashBottom: SIMD3<Float>?
    /// Emitter volume relative to a 4,000 m³ reference, so a larger view stays the same density.
    private var coverageScale: CGFloat = 1
    private var coverageCenter = SIMD3<Float>.zero
    private var coverageSize = SIMD3<Float>.zero

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
        // The slats already overlap with the bottom edge toward the street. Subdivision
        // pulled them apart into a few open horizontal boards, so it is turned off below.
        configureBuilding(named: "GarageDoor", mask: garageMask, albedoLight: dayGrade, albedoDark: nightGrade, normalYSign: -1)
        // Windows and solar keep the imported meshes. Flat cards and a constant
        // grid shader hid the cell rims and the recessed window openings.
        // The glass stays dark until the house load passes the idle deadband.
        configureWindowLights()
        // The USD cage is Catmull-Clark. One tessellation level chamfers every
        // separate cell and pane into an octagon and pulls the corners apart.
        keepLitCellsRectangular()

        // These cards are torn alpha planes. SceneKit draws their black RGB as solid
        // wedges, which reads as damage, so they stay out of the view.
        // The house's own Shadow card comes back with Tesla's CompactShadow look (see HouseGroundShadow).
        // The car's garage shadow stays hidden: its texture does not match the one Tesla draws.
        HouseGroundShadow.dress(root)
        root.childNode(withName: "GarageVehicleShadow", recursively: true)?.isHidden = true
        root.childNode(withName: "GroundReflection", recursively: true)?.isHidden = true

        // Left on the imported physically based materials these render black,
        // like holes in the wall. The gateway then gets its own material copy.
        for name in ["Powerwall", "Meter", "WallConnector"] {
            for material in materials(under: name) {
                material.lightingModel = .constant
                material.isDoubleSided = true
            }
        }
        // The gateway's grey material is also on the wall connector. Copy it first
        // so only the gateway drops out of the floor mirror.
        dropFromReflection(named: "Meter")
        installFillLights()
        installCarLighting()
        setSolar(.panels)
        if let vehicle = root.childNode(withName: "Vehicle", recursively: true) {
            repairVehicleShell(vehicle)
            centreVehicleInTheGarageDoor(vehicle)
            HouseCarLighting.mark(vehicle)
        }
        // Stay closed until live wall-connector state says a car is home.
        showVehicle(false)

        rainNode.name = "Rain"
        snowNode.name = "Snow"
        rainNode.renderingOrder = 7
        snowNode.renderingOrder = 7
        rainNode.position = SCNVector3(-1.6, 6, 0)
        snowNode.position = SCNVector3(-1.6, 6, 0)
        rainNode.addParticleSystem(rain)
        snowNode.addParticleSystem(snow)
        root.addChildNode(rainNode)
        root.addChildNode(snowNode)
        installSky()
        HouseGroundPlate.install(on: root)
        showAboveTheSkyWash(root)
        // After the plate and the sky wash, before the house.
        root.childNode(withName: HouseGroundShadow.nodeName, recursively: true)?.enumerateHierarchy { node, _ in
            node.renderingOrder = HouseGroundShadow.renderingOrder
        }

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
        let sun = simd_normalize(p.sunDirection)
        sunLight.simdPosition = sun
        sunLight.look(at: SCNVector3(0, 0.4, 0))
        sunLight.light?.intensity = 350 + 650 * CGFloat(p.theme * p.ambientScale)
        carStudio.light?.intensity = HouseCarLighting.environmentIntensity(theme: p.theme, ambientScale: p.ambientScale)
        carSun.simdPosition = sun
        carSun.look(at: SCNVector3(0, 0.4, 0))
        carSun.light?.intensity = HouseCarLighting.sunIntensity(theme: p.theme, ambientScale: p.ambientScale)
        SCNTransaction.commit()

        layoutSky(animated: animated)
        applyWeatherMotionPause()
    }

    /// Cloud drift and precipitation. SceneKit keeps a display link awake while a
    /// particle system is emitting, including after the view itself is paused.
    private var weatherMotionPaused = false

    func setWeatherMotionPaused(_ paused: Bool) {
        weatherMotionPaused = paused
        applyWeatherMotionPause()
    }

    private func applyWeatherMotionPause() {
        if weatherMotionPaused {
            rain.birthRate = 0
            snow.birthRate = 0
            rain.speedFactor = 0
            snow.speedFactor = 0
        } else {
            rain.birthRate = CGFloat(parameters.rainIntensity) * 90 * coverageScale
            snow.birthRate = CGFloat(parameters.snowIntensity) * 22 * coverageScale
            rain.speedFactor = 1
            snow.speedFactor = 1
        }
        rainNode.isPaused = weatherMotionPaused
        snowNode.isPaused = weatherMotionPaused
        rainNode.isHidden = weatherMotionPaused || parameters.rainIntensity <= 0
        snowNode.isHidden = weatherMotionPaused || parameters.snowIntensity <= 0
        for holder in cloudCards {
            holder.childNodes.first?.isPaused = weatherMotionPaused
        }
    }

    var rainIntensity: Float { parameters.rainIntensity }
    var snowIntensity: Float { parameters.snowIntensity }
    var currentParameters: HouseLightingParameters { parameters }

    /// Sizes the rain and snow volume to the camera frustum so precipitation covers the
    /// whole view, including the sky around the house, at a light density.
    func updateWeatherCoverage(camera: SCNNode, viewport: CGSize) {
        guard viewport.width > 1, viewport.height > 1 else { return }
        let transform = camera.simdWorldTransform
        skyEye = SIMD3<Float>(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
        let forward = -SIMD3<Float>(transform.columns.2.x, transform.columns.2.y, transform.columns.2.z)
        skyAim = skyEye + forward
        skyViewport = viewport
        skyFieldOfView = Float(camera.camera?.fieldOfView ?? CGFloat(HouseCameraFraming.verticalFOVDegrees))
        // Orbit and pan only move the sky card with the camera. Rewriting wisp
        // opacity here restarts the clouds and they flash.
        followSky(placeCards: false)
        let holder = root.parent ?? root
        if rainNode.parent !== holder {
            holder.addChildNode(rainNode)
            holder.addChildNode(snowNode)
        }
        let vfov = Float((camera.camera?.fieldOfView ?? 30) * .pi / 180)
        let aspect = Float(viewport.width / viewport.height)
        let hfov = 2 * atan(tan(vfov / 2) * aspect)
        let origin = skyEye
        // SceneKit cameras look down their local −Z axis.
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
        let moved = simd_length(center - coverageCenter) > 0.4 || simd_length(size - coverageSize) > 0.4
        if moved || coverageSize == .zero {
            coverageCenter = center
            coverageSize = size
            let box = SCNBox(width: CGFloat(size.x), height: CGFloat(size.y), length: CGFloat(size.z), chamferRadius: 0)
            rain.emitterShape = box
            snow.emitterShape = box
            let local = holder.convertPosition(SCNVector3(center.x, center.y, center.z), from: nil)
            rainNode.position = local
            snowNode.position = local
            // 4,000 m³ ≈ the framed house view. Scale the count with volume and keep the spacing.
            coverageScale = CGFloat((size.x * size.y * size.z) / 4000)
            applyWeatherMotionPause()
        }
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

    /// House load, excluding the wall connector, that turns the window glow on.
    /// The 40 W readout deadband stays on for ordinary standby, so the panes use a higher bar.
    static let interiorLightThresholdWatts: Double = 200

    static func interiorLightsOn(homeW: Double, vehicleW: Double) -> Bool {
        homeW - vehicleW > interiorLightThresholdWatts
    }

    /// White glow on the window panes while the home is drawing power.
    func setInteriorLights(homeW: Double, vehicleW: Double) {
        let on: Float = Self.interiorLightsOn(homeW: homeW, vehicleW: vehicleW) ? 1 : 0
        guard on != interiorLight else { return }
        interiorLight = on
        for material in windowMaterials {
            material.setValue(NSNumber(value: on), forKey: "interiorLight")
        }
    }

    func showVehicle(_ visible: Bool) {
        root.childNode(withName: "Vehicle", recursively: true)?.isHidden = !visible
        root.childNode(withName: "GarageVehicleShadow", recursively: true)?.isHidden = true
        root.childNode(withName: "GarageDoor", recursively: true)?.isHidden = visible
    }

    /// Swaps the parked car for one of the exported Tesla models, painted `paint`.
    /// Car files are in metres, nose towards −Z, origin on the ground at the car's centre, matching
    /// GenericVehicle. The local park point is (−0.7, 0.02, 0.7) at scale 0.35. The vehicle
    /// node is shifted so that point sits in the middle of the garage door.
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
        repairVehicleShell(car, model: model)
        showAboveTheSkyWash(car)
        HouseGroundPlate.omitFromReflection(car)
        HouseCarLighting.mark(car)
        if let paint { setVehiclePaint(paint) }
    }

    /// The baked body is centred right of the opening. Slide the vehicle node so
    /// the car's centre matches the door. Exported models use the same local origin.
    /// Mesh bounds are read from the geometry. The node box is still empty here.
    private func centreVehicleInTheGarageDoor(_ vehicle: SCNNode) {
        guard let door = root.childNode(withName: "GarageDoor", recursively: true),
              let doorMid = localCentreX(door),
              let vehicleMid = localCentreX(vehicle) else { return }
        vehicle.simdPosition.x += doorMid - vehicleMid
    }

    /// Horizontal centre of this node's meshes, in the node's own space.
    /// simd keeps this independent of whether SceneKit's vector components are Float or CGFloat.
    private func localCentreX(_ node: SCNNode) -> Float? {
        var minX = Float.greatestFiniteMagnitude
        var maxX = -Float.greatestFiniteMagnitude
        func consider(_ owner: SCNNode) {
            guard let geometry = owner.geometry else { return }
            let box = geometry.boundingBox
            for x in [box.min.x, box.max.x] {
                for y in [box.min.y, box.max.y] {
                    for z in [box.min.z, box.max.z] {
                        let local = node.simdConvertPosition(
                            SIMD3(Float(x), Float(y), Float(z)),
                            from: owner
                        )
                        minX = min(minX, local.x)
                        maxX = max(maxX, local.x)
                    }
                }
            }
        }
        consider(node)
        node.enumerateChildNodes { child, _ in consider(child) }
        guard minX < maxX else { return nil }
        return (minX + maxX) * 0.5
    }

    /// The baked body uses an occlusion atlas as its colour, so the windows and panel
    /// gaps render black. Exported shells leave openings where the glass does not meet
    /// the frame. Solid paint plus caps across the cabin openings close both.
    private func repairVehicleShell(_ vehicle: SCNNode, model: VehicleModel? = nil) {
        vehicle.enumerateHierarchy { node, _ in
            guard let geometry = node.geometry else { return }
            for material in geometry.materials {
                material.isDoubleSided = true
                VehicleGlass.reveal(material)
                if material.name == "vehicle" {
                    material.lightingModel = .physicallyBased
                    material.diffuse.contents = HouseColor(white: 0.78, alpha: 1)
                    material.metalness.contents = 0.35
                    material.roughness.contents = 0.25
                }
            }
            if let model {
                geometry.materials.forEach { VehicleLamps.dress($0, model: model) }
            }
            let name = geometry.materials.first?.name ?? ""
            guard name == "Paint" || name == "Glass" || name == "vehicle",
                  node.childNode(withName: "CabinCaps", recursively: false) == nil,
                  let caps = HouseMeshSeam.cabinCaps(for: geometry) else { return }
            let capNode = SCNNode(geometry: caps)
            capNode.name = "CabinCaps"
            node.addChildNode(capNode)
        }
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

    private func installSky() {
        skyRig.name = "HouseSky"
        let halo = SCNPlane(width: 1, height: 1)
        halo.materials = [HouseSkyArt.material(HouseSkyArt.sunGlow, additive: true)]
        sunHalo.geometry = halo
        sunHalo.name = "SunHalo"
        sunHalo.renderingOrder = 5
        let disc = SCNPlane(width: 1, height: 1)
        disc.materials = [HouseSkyArt.material(HouseSkyArt.sunCore, additive: true)]
        sunDisc.geometry = disc
        sunDisc.name = "SunDisc"
        sunDisc.renderingOrder = 6
        skyRig.addChildNode(sunHalo)
        skyRig.addChildNode(sunDisc)

        let wash = SCNPlane(width: 1, height: 1)
        let washMaterial = SCNMaterial()
        washMaterial.lightingModel = .constant
        washMaterial.isDoubleSided = true
        washMaterial.diffuse.contents = HouseSkyArt.washContents(
            top: SIMD3(0.26, 0.46, 0.86), bottom: SIMD3(0.58, 0.76, 0.96))
        smoothWash(washMaterial)
        washMaterial.transparencyMode = .aOne
        washMaterial.blendMode = .alpha
        let washBand = HouseSky.washScreenFraction + HouseSky.washFeatherFraction
        washMaterial.setValue(CGPoint(x: 1920 * 1.025, y: 1080 * CGFloat(washBand)), forKey: "washPixels")
        washMaterial.writesToDepthBuffer = false
        // The ground plate would otherwise cut a hard edge through the fade.
        // The house is drawn after this plane, so it still covers the wash.
        washMaterial.readsFromDepthBuffer = false
        wash.materials = [washMaterial]
        skyWash.geometry = wash
        skyWash.name = "HouseSkyWash"
        // Behind the house (order 2) and the clouds (order 4).
        skyWash.renderingOrder = 0
        skyRig.addChildNode(skyWash)

        for (index, wisp) in HouseSky.wisps.enumerated() {
            let plane = SCNPlane(width: CGFloat(wisp.width), height: CGFloat(wisp.height))
            // The house and the ground plate write a depth mask. A low wisp crosses
            // both, so it ignores that mask and stays whole above the roof.
            plane.materials = [HouseSkyArt.material(wisp.cirrus ? HouseSkyArt.cirrus : HouseSkyArt.puff, additive: false, readsDepth: false)]
            let card = SCNNode(geometry: plane)
            card.name = "HouseCloud\(index)"
            card.renderingOrder = 4
            let holder = SCNNode()
            // The holder's opacity makes SceneKit draw the card in the parent's pass.
            // That pass has to stay after the wash, or the band covers the clouds.
            holder.renderingOrder = 4
            holder.opacity = 0
            holder.isHidden = true
            holder.addChildNode(card)
            skyRig.addChildNode(holder)
            cloudCards.append(holder)
        }
        sunDisc.opacity = 0
        sunHalo.opacity = 0
        sunDisc.isHidden = true
        sunHalo.isHidden = true
        root.addChildNode(skyRig)
    }

    private static let cloudDriftKey = "cloudDrift"

    private static func cloudDrift(index: Int) -> SCNAction {
        let drift = SCNAction.sequence([
            SCNAction.moveBy(x: 0.7, y: 0.05, z: 0, duration: 42 + Double(index) * 5),
            SCNAction.moveBy(x: -0.7, y: -0.05, z: 0, duration: 42 + Double(index) * 5),
        ])
        return .repeatForever(drift)
    }

    /// Keeps the sky card in front of the camera. Card layout is left alone while
    /// the view is only orbiting or panning, so the wisps keep their drift.
    private func followSky(placeCards: Bool) {
        guard skyViewport.width > 1, skyViewport.height > 1 else { return }
        let holder = root.parent ?? root
        if skyRig.parent !== holder {
            holder.addChildNode(skyRig)
        }
        let forward = simd_normalize(skyAim - skyEye)
        let right = simd_normalize(cross(forward, SIMD3<Float>(0, 1, 0)))
        let up = simd_normalize(cross(right, forward))
        let distance: Float = 22
        let center = skyEye + forward * distance + up * (0.52 * tan(skyFieldOfView * .pi / 180 / 2) * distance)
        let halfHeight = tan(skyFieldOfView * .pi / 180 / 2) * distance
        let aspect = Float(skyViewport.width / max(skyViewport.height, 1))
        let halfWidth = halfHeight * max(aspect, 0.01)
        SCNTransaction.begin()
        SCNTransaction.disableActions = true
        var basis = matrix_identity_float4x4
        basis.columns.0 = SIMD4<Float>(right.x, right.y, right.z, 0)
        basis.columns.1 = SIMD4<Float>(up.x, up.y, up.z, 0)
        // Plane faces +Z. Point that axis back at the camera.
        basis.columns.2 = SIMD4<Float>(-forward.x, -forward.y, -forward.z, 0)
        basis.columns.3 = SIMD4<Float>(center.x, center.y, center.z, 1)
        skyRig.simdWorldTransform = basis
        if let plane = skyWash.geometry as? SCNPlane {
            // The rig sits 0.52 of a screen above the view centre. Colour occupies
            // the top washScreenFraction. The plane continues below that, already clear.
            let band = HouseSky.washScreenFraction + HouseSky.washFeatherFraction
            plane.width = CGFloat(halfWidth * 2.05)
            plane.height = CGFloat(halfHeight * 2 * band)
            let top = (1 - 0.52) * halfHeight
            skyWash.simdPosition = SIMD3(0, top - Float(plane.height) / 2, 0)
        }
        if placeCards || abs(halfWidth - skyHalfWidth) > 0.01 {
            skyHalfWidth = halfWidth
            let sky = HouseSky.placement(
                altitude: parameters.sunAltitude,
                azimuth: parameters.sunAzimuth,
                heading: parameters.houseHeading,
                cloudCover: parameters.cloudCover,
                eye: skyEye,
                target: skyAim,
                viewport: skyViewport,
                fieldOfView: skyFieldOfView
            )
            // +Z points at the camera. Keep the sun closest, then the clouds, then the wash,
            // so an older SceneKit that sorts transparent nodes by depth still stacks them.
            let localSun = SIMD3<Float>(sky.screenX * halfWidth, (sky.screenY - 0.52) * halfHeight, 4)
            sunDisc.simdPosition = localSun
            sunHalo.simdPosition = localSun
            sunDisc.scale = SCNVector3(sky.discRadius, sky.discRadius, 1)
            sunHalo.scale = SCNVector3(sky.haloRadius, sky.haloRadius, 1)
            for (card, wisp) in zip(cloudCards, HouseSky.wisps) {
                card.simdPosition = SIMD3<Float>(wisp.x * halfWidth * 0.92, (wisp.y - 0.52) * halfHeight, wisp.depth + 2.5)
            }
        }
        SCNTransaction.commit()
    }

    /// Moves the sun along the visible arc and shows the wisps for the current cover.
    /// Positions are applied without the lighting fade so a viewport change does not slide the sky.
    private func layoutSky(animated: Bool) {
        let p = parameters
        let sky = HouseSky.placement(
            altitude: p.sunAltitude,
            azimuth: p.sunAzimuth,
            heading: p.houseHeading,
            cloudCover: p.cloudCover,
            eye: skyEye,
            target: skyAim,
            viewport: skyViewport,
            fieldOfView: skyFieldOfView
        )
        followSky(placeCards: true)

        SCNTransaction.begin()
        SCNTransaction.animationDuration = animated ? 1.5 : 0
        SCNTransaction.disableActions = !animated
        if !animated {
            // Cloud drift is a forever action. Clearing the cards here restarted
            // it on every forecast blend step, so the wisps never actually moved.
            sunDisc.removeAllAnimations()
            sunHalo.removeAllAnimations()
        }
        let tint = HouseColor(red: CGFloat(sky.sunColor.x), green: CGFloat(sky.sunColor.y), blue: CGFloat(sky.sunColor.z), alpha: 1)
        sunDisc.geometry?.firstMaterial?.multiply.contents = tint
        sunHalo.geometry?.firstMaterial?.multiply.contents = tint
        sunDisc.opacity = CGFloat(sky.sunOpacity)
        sunHalo.opacity = CGFloat(sky.haloOpacity)
        sunDisc.isHidden = sky.sunOpacity < 0.02
        sunHalo.isHidden = sky.haloOpacity < 0.02
        let wash = HouseSky.skyWash(altitude: p.sunAltitude)
        if let material = skyWash.geometry?.firstMaterial {
            // The bitmap is the expensive part. A forecast blend steps every frame
            // while the sun colour stays put, so keep the image already on the material.
            if bakedWashTop != wash.top || bakedWashBottom != wash.bottom {
                material.diffuse.contents = HouseSkyArt.washContents(top: wash.top, bottom: wash.bottom)
                smoothWash(material)
                bakedWashTop = wash.top
                bakedWashBottom = wash.bottom
            }
            material.setValue(NSValue(scnVector3: SCNVector3(wash.top.x, wash.top.y, wash.top.z)), forKey: "washTop")
            material.setValue(NSValue(scnVector3: SCNVector3(wash.bottom.x, wash.bottom.y, wash.bottom.z)), forKey: "washBottom")
            material.setValue(NSNumber(value: wash.amount), forKey: "washAmount")
            material.setValue(NSNumber(value: HouseSky.washPeak), forKey: "washPeak")
        }
        // The shader multiplies by washAmount. Leave the node opaque so it is not applied twice.
        skyWash.opacity = 1
        skyWash.isHidden = wash.amount < 0.02
        for (holder, wisp) in zip(cloudCards, HouseSky.wisps) {
            let opacity = HouseSky.wispOpacity(threshold: wisp.threshold, cloudCover: p.cloudCover, cirrus: wisp.cirrus)
            holder.opacity = CGFloat(opacity)
            holder.isHidden = opacity < 0.02
        }
        SCNTransaction.commit()
        // runAction inside a transaction with actions disabled never attaches.
        // A hidden or fully transparent card must not keep a forever action.
        for (index, (holder, wisp)) in zip(cloudCards, HouseSky.wisps).enumerated() {
            let opacity = HouseSky.wispOpacity(threshold: wisp.threshold, cloudCover: p.cloudCover, cirrus: wisp.cirrus)
            let card = holder.childNodes.first
            if opacity >= 0.02 {
                if card?.action(forKey: Self.cloudDriftKey) == nil {
                    card?.runAction(Self.cloudDrift(index: index), forKey: Self.cloudDriftKey)
                }
            } else {
                card?.removeAction(forKey: Self.cloudDriftKey)
            }
        }
    }

    private func installFillLights() {
        let ambient = SCNNode()
        ambient.name = "HouseFill"
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 320
        ambient.light?.color = HouseColor(white: 0.9, alpha: 1)
        // The parked car has its own studio lights. These keep lighting everything else as before.
        ambient.light?.categoryBitMask = HouseCarLighting.houseLightMask
        root.addChildNode(ambient)

        sunLight.name = "HouseSun"
        sunLight.light = SCNLight()
        sunLight.light?.type = .directional
        sunLight.light?.intensity = 700
        sunLight.light?.castsShadow = false
        sunLight.light?.categoryBitMask = HouseCarLighting.houseLightMask
        root.addChildNode(sunLight)
    }

    /// The showroom's studio panorama as a radiance probe, plus a dim directional sun that follows
    /// the house sun. Both use `HouseCarLighting.lightBit`, so only the car sees them. The house
    /// shell is `.constant`, and the windows, solar and gateway keep the fill lights above.
    private func installCarLighting() {
        carStudio.name = HouseCarLighting.probeName
        let probe = SCNLight()
        probe.type = .probe
        probe.probeType = .radiance
        probe.probeUpdateType = .never
        probe.parallaxCorrectionEnabled = false
        probe.probeExtents = simd_float3(repeating: HouseCarLighting.probeExtent)
        // Typed as optional so this reads the same whichever nullability the SDK declares.
        let environment: SCNMaterialProperty? = probe.probeEnvironment
        if let url = HouseLighting.resourceURL(name: ShowroomStage.environmentName, ext: "png") {
            environment?.contents = url
        }
        probe.categoryBitMask = HouseCarLighting.lightBit
        probe.intensity = HouseCarLighting.environmentIntensity(theme: 1, ambientScale: 1)
        carStudio.light = probe
        root.addChildNode(carStudio)

        carSun.name = HouseCarLighting.sunName
        let sun = SCNLight()
        sun.type = .directional
        sun.castsShadow = false
        sun.categoryBitMask = HouseCarLighting.lightBit
        sun.intensity = HouseCarLighting.sunIntensity(theme: 1, ambientScale: 1)
        carSun.light = sun
        root.addChildNode(carSun)
    }

    /// Adds a warm interior glow to the imported window glass. `interiorLight` is 0 or 1.
    private func configureWindowLights() {
        let surface = """
        #pragma arguments
        float interiorLight;

        #pragma body
        float3 glow = float3(1.0, 1.0, 1.0);
        float lit = clamp(interiorLight, 0.0, 1.0);
        _surface.diffuse.rgb = mix(_surface.diffuse.rgb, glow, lit * 0.42);
        _surface.emission.rgb = glow * lit * 0.35;
        _surface.metalness *= (1.0 - lit);
        """
        for material in materials(under: "Windows") {
            material.shaderModifiers = [.surface: surface]
            material.setValue(NSNumber(value: 0), forKey: "interiorLight")
            windowMaterials.append(material)
        }
        interiorLight = 0
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

    /// Leaves the authored quads in place. SceneKit otherwise tessellates the imported
    /// cage, and each lit solar cell and window pane renders as an octagon.
    private func keepLitCellsRectangular() {
        root.enumerateHierarchy { child, _ in
            guard let name = child.name else { return }
            let lit = name.hasPrefix("SolarPanel") || name.hasPrefix("SolarRoof")
                || name.hasPrefix("Windows") || name.hasPrefix("Home") || name.hasPrefix("GarageDoor")
            guard lit, let geometry = child.geometry else { return }
            geometry.subdivisionLevel = 0
            // SceneKit keeps the tessellator object. Level 0 stops the Catmull-Clark
            // pass; a smoothing mode would still pull the corners in.
            geometry.tessellator?.smoothingMode = .none
            geometry.tessellator?.edgeTessellationFactor = 1
            geometry.tessellator?.insideTessellationFactor = 1
            geometry.tessellator?.isAdaptive = false
        }
    }

    /// SceneKit drops these when the diffuse image is replaced. Nearest filtering turns the ramp into stripes.
    private func smoothWash(_ material: SCNMaterial) {
        material.diffuse.magnificationFilter = .linear
        material.diffuse.minificationFilter = .linear
        material.diffuse.mipFilter = .none
        material.diffuse.wrapS = .clamp
        material.diffuse.wrapT = .clamp
    }

    /// Draws the model after the sky wash. The plate stays earlier so the fade can cover it.
    private func showAboveTheSkyWash(_ node: SCNNode) {
        let name = node.name ?? ""
        if name == HouseGroundPlate.name || name == "HouseSky" || name == "Rain" || name == "Snow" {
            return
        }
        if node.renderingOrder < 2 {
            node.renderingOrder = 2
        }
        for child in node.childNodes {
            showAboveTheSkyWash(child)
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

    /// Copies the node's materials and discards them in the floor's mirrored camera.
    private func dropFromReflection(named name: String) {
        guard let node = root.childNode(withName: name, recursively: true) else { return }
        node.enumerateHierarchy { child, _ in
            guard let geometry = child.geometry, !geometry.materials.isEmpty else { return }
            geometry.materials = geometry.materials.map { source in
                let material = (source.copy() as? SCNMaterial) ?? source
                var modifiers = material.shaderModifiers ?? [:]
                modifiers[.fragment] = HouseGroundPlate.reflectedFragment
                material.shaderModifiers = modifiers
                return material
            }
        }
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
        // A little larger than the old hard square so the soft rim is visible.
        // No stretch: a streak reads as a dash instead of a round drop.
        p.particleSize = 0.028
        p.stretchFactor = 0
        p.particleImage = HouseSkyArt.precipitationContents
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
        p.particleSize = 0.04
        p.particleSizeVariation = 0.016
        p.particleImage = HouseSkyArt.precipitationContents
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
        p.sunAltitude = Float(sunAltitude)
        p.sunAzimuth = Float(sunAzimuth)
        p.houseHeading = Float(houseHeadingDegrees)
        p.cloudCover = Float(min(max(deckCover(reported: clouds, condition: condition), 0), 1))

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

    /// The visible deck can read fuller than the cover used to dim the house.
    private func deckCover(reported: Double, condition: WeatherCondition) -> Double {
        switch condition {
        case .partlyCloudy:
            return max(reported, 0.42)
        case .mostlyCloudy:
            return max(reported, 0.68)
        case .cloudy, .foggy, .haze, .smoky, .blowingDust:
            return max(reported, 0.88)
        case .thunderstorms, .isolatedThunderstorms, .scatteredThunderstorms, .strongStorms,
             .heavyRain, .blizzard, .tropicalStorm, .hurricane:
            return max(reported, 0.92)
        default:
            return reported
        }
    }
}

// MARK: - Sky sprites

enum HouseSkyArt {
    static let sunCore = radialImage(size: 128, inner: 0.16, outer: 0.62, peak: 1)
    static let sunGlow = radialImage(size: 128, inner: 0.0, outer: 0.92, peak: 0.45)
    /// Round falloff for rain and snow. `radius` is 0 at the centre and 1 at the rim.
    static let precipitation = precipitationImage(size: 64)
    static var precipitationContents: Any { platformImage(precipitation) }

    /// Flat at the middle, zero at the rim, so a square billboard still reads as a soft disc.
    static func precipitationFade(_ radius: Float) -> Float {
        let t = min(max(radius, 0), 1)
        let bell = 1 - t * t
        return bell * bell * bell
    }
    static let cirrus = cloudImage(
        width: 512, height: 256,
        blobs: [
            Blob(x: -0.55, y: 0.18, rx: 0.34, ry: 0.30, amp: 0.55),
            Blob(x: -0.22, y: -0.10, rx: 0.30, ry: 0.26, amp: 0.48),
            Blob(x: 0.12, y: 0.22, rx: 0.32, ry: 0.28, amp: 0.52),
            Blob(x: 0.48, y: -0.16, rx: 0.30, ry: 0.24, amp: 0.42),
            Blob(x: 0.02, y: 0.00, rx: 0.46, ry: 0.20, amp: 0.28),
        ],
        shred: 9
    )
    static let puff = cloudImage(
        width: 384, height: 256,
        blobs: [
            Blob(x: -0.28, y: 0.12, rx: 0.38, ry: 0.32, amp: 0.55),
            Blob(x: 0.08, y: 0.20, rx: 0.32, ry: 0.28, amp: 0.48),
            Blob(x: 0.34, y: -0.06, rx: 0.34, ry: 0.30, amp: 0.42),
            Blob(x: -0.04, y: -0.18, rx: 0.28, ry: 0.24, amp: 0.36),
            Blob(x: 0.16, y: 0.02, rx: 0.22, ry: 0.18, amp: 0.28),
        ],
        shred: 5
    )

    static func material(_ image: CGImage, additive: Bool, readsDepth: Bool = true) -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.isDoubleSided = true
        material.diffuse.contents = platformImage(image)
        material.blendMode = additive ? .add : .alpha
        material.writesToDepthBuffer = false
        material.readsFromDepthBuffer = readsDepth
        material.transparencyMode = additive ? .rgbZero : .aOne
        return material
    }

    /// Thin edges stay as drawn. Past a light shoulder the core keeps gaining
    /// density slowly, instead of slamming into a flat opaque middle.
    static func cloudThickness(_ body: Float) -> Float {
        let clamped = max(body, 0)
        let shoulder: Float = 0.22
        guard clamped > shoulder else { return clamped }
        let excess = clamped - shoulder
        let core = shoulder + excess / (1 + excess * 5)
        return min(core, 0.62)
    }

    private struct Blob {
        var x, y, rx, ry, amp: Float
    }

    private static func radialImage(size: Int, inner: Float, outer: Float, peak: Float) -> CGImage {
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        let last = Float(size - 1)
        for y in 0..<size {
            for x in 0..<size {
                let u = Float(x) / last * 2 - 1
                let v = Float(y) / last * 2 - 1
                let radius = sqrt(u * u + v * v)
                let t = min(max((radius - inner) / max(outer - inner, 0.001), 0), 1)
                let fade = (1 - t) * (1 - t) * peak
                // Premultiplied white. Additive glow falls off before it lifts the dark sky.
                let channel = UInt8(min(max(fade, 0), 1) * 255)
                let index = (y * size + x) * 4
                pixels[index] = channel
                pixels[index + 1] = channel
                pixels[index + 2] = channel
                pixels[index + 3] = channel
            }
        }
        return image(pixels, width: size, height: size)
    }

    /// Row 0 is the top. The peak is only a quarter opaque, so an 8-bit ramp has a few
    /// dozen steps and they read as stripes. Bayer dither breaks those steps up, and
    /// the lower feather is already clear so the quad edge is not a line.
    static func washContents(top: SIMD3<Float>, bottom: SIMD3<Float>) -> Any {
        let width = 1024
        let height = 512
        let span = HouseSky.washScreenFraction / (HouseSky.washScreenFraction + HouseSky.washFeatherFraction)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let last = Float(height - 1)
        for y in 0..<height {
            let down = Float(y) / last
            let t = min(max(down / span, 0), 1)
            let fade = 1 - t
            let eased = fade * fade * (3 - 2 * fade)
            let color = bottom + (top - bottom) * eased
            for x in 0..<width {
                let index = (y * width + x) * 4
                pixels[index] = ditheredByte(color.x, x: x, y: y)
                pixels[index + 1] = ditheredByte(color.y, x: x, y: y &+ 3)
                pixels[index + 2] = ditheredByte(color.z, x: x, y: y &+ 5)
                pixels[index + 3] = ditheredByte(HouseSky.washPeak * eased, x: x &+ 2, y: y &+ 1)
            }
        }
        return platformImage(image(pixels, width: width, height: height))
    }

    /// 8×8 Bayer thresholds, 0…1. Spreads a fractional 8-bit step across neighbouring pixels.
    private static let bayer8: [Float] = [
        0, 32, 8, 40, 2, 34, 10, 42,
        48, 16, 56, 24, 50, 18, 58, 26,
        12, 44, 4, 36, 14, 46, 6, 38,
        60, 28, 52, 20, 62, 30, 54, 22,
        3, 35, 11, 43, 1, 33, 9, 41,
        51, 19, 59, 27, 49, 17, 57, 25,
        15, 47, 7, 39, 13, 45, 5, 37,
        63, 31, 55, 23, 61, 29, 53, 21,
    ].map { ($0 + 0.5) / 64 }

    private static func ditheredByte(_ value: Float, x: Int, y: Int) -> UInt8 {
        let exact = min(max(value, 0), 1) * 255
        let threshold = bayer8[(y & 7) * 8 + (x & 7)]
        return UInt8(min(max(exact + threshold - 0.5, 0), 255))
    }

    private static func precipitationImage(size: Int) -> CGImage {
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        let last = Float(size - 1)
        for y in 0..<size {
            for x in 0..<size {
                let u = Float(x) / last * 2 - 1
                let v = Float(y) / last * 2 - 1
                let radius = sqrt(u * u + v * v)
                let alpha = UInt8(min(max(precipitationFade(radius), 0), 1) * 255)
                let index = (y * size + x) * 4
                pixels[index] = 255
                pixels[index + 1] = 255
                pixels[index + 2] = 255
                pixels[index + 3] = alpha
            }
        }
        return image(pixels, width: size, height: size)
    }

    private static func cloudImage(width: Int, height: Int, blobs: [Blob], shred: Float) -> CGImage {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let u = Float(x) / Float(width - 1) * 2 - 1
                let v = Float(y) / Float(height - 1) * 2 - 1
                var amount: Float = 0
                for blob in blobs {
                    let dx = (u - blob.x) / blob.rx
                    let dy = (v - blob.y) / blob.ry
                    amount += blob.amp * exp(-(dx * dx + dy * dy))
                }
                let strands = 0.55 + 0.45 * sin(u * shred + v * 2.5) * sin(u * shred * 0.37 - 1.3)
                let edge = max(abs(u) / 0.98, abs(v) / 0.9)
                let window = 1 - HouseSky.smoothstep(0.45, 1, edge)
                let alpha = cloudThickness(amount * strands * window)
                let index = (y * width + x) * 4
                // Cool white. Alpha carries the wisp so stacked clouds stay soft.
                pixels[index] = 226
                pixels[index + 1] = 234
                pixels[index + 2] = 242
                pixels[index + 3] = UInt8(alpha * 255)
            }
        }
        return image(pixels, width: width, height: height)
    }

    private static func image(_ pixels: [UInt8], width: Int, height: Int) -> CGImage {
        let data = Data(pixels) as CFData
        let provider = CGDataProvider(data: data)!
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )!
    }

    private static func platformImage(_ image: CGImage) -> Any {
        #if canImport(UIKit)
        return UIImage(cgImage: image)
        #elseif canImport(AppKit)
        return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        #else
        return image
        #endif
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

    /// Fans across closed openings in the upper body. The underside, wheel rings, and the
    /// outer shell of the glass stay open. Returns nil when there is nothing to add.
    static func cabinCaps(for geometry: SCNGeometry) -> SCNGeometry? {
        guard let vertex = geometry.sources(for: .vertex).first,
              let element = geometry.elements.first(where: { $0.primitiveType == .triangles }) else { return nil }
        let positions = vectors3(vertex)
        guard positions.count > 3 else { return nil }
        var minPoint = positions[0]
        var maxPoint = positions[0]
        for point in positions {
            minPoint = simd_min(minPoint, point)
            maxPoint = simd_max(maxPoint, point)
        }
        let bounds = maxPoint - minPoint
        let longest = max(bounds.x, max(bounds.y, bounds.z))
        guard longest > 0.01 else { return nil }
        let indices = triangles(element)
        let weldScale: Float = longest > 2.5 ? 400 : 800
        var weldOf: [SIMD3<Int>: Int] = [:]
        var weld = [Int](repeating: 0, count: positions.count)
        var representative: [Int] = []
        for index in positions.indices {
            let point = positions[index]
            let key = SIMD3(Int((point.x * weldScale).rounded()),
                            Int((point.y * weldScale).rounded()),
                            Int((point.z * weldScale).rounded()))
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
                edgeCount[Edge(a: min(a, b), b: max(a, b)), default: 0] += 1
            }
        }
        var neighbors: [Int: [Int]] = [:]
        var unused: Set<Edge> = []
        for (edge, count) in edgeCount where count == 1 {
            neighbors[edge.a, default: []].append(edge.b)
            neighbors[edge.b, default: []].append(edge.a)
            unused.insert(edge)
        }
        var capPoints: [SCNVector3] = []
        var capIndices: [UInt32] = []
        while let seed = unused.first {
            var loop = [seed.a]
            var current = seed.a
            var previous = -1
            var closed = false
            var steps = 0
            while steps < 6000 {
                steps += 1
                let options = (neighbors[current] ?? []).filter {
                    unused.contains(Edge(a: min(current, $0), b: max(current, $0))) && $0 != previous
                }
                guard let step = options.min(by: { lhs, rhs in
                    let here = positions[representative[current]]
                    func score(_ next: Int) -> Float {
                        guard previous >= 0 else { return 0 }
                        let direction = here - positions[representative[previous]]
                        let onward = positions[representative[next]] - here
                        let directionLength = simd_length(direction)
                        let onwardLength = simd_length(onward)
                        if directionLength < 1e-6 || onwardLength < 1e-6 { return 0 }
                        return -simd_dot(direction / directionLength, onward / onwardLength)
                    }
                    return score(lhs) < score(rhs)
                }) else { break }
                unused.remove(Edge(a: min(current, step), b: max(current, step)))
                if step == loop[0] {
                    closed = true
                    break
                }
                loop.append(step)
                previous = current
                current = step
            }
            let points = loop.map { positions[representative[$0]] }
            guard closed, points.count >= 3 else { continue }
            var low = points[0]
            var high = points[0]
            for point in points {
                low = simd_min(low, point)
                high = simd_max(high, point)
            }
            let span = high - low
            let ordered = [span.x, span.y, span.z].sorted()
            let center = points.reduce(SIMD3<Float>.zero, +) / Float(points.count)
            let underside = span.y == ordered[0]
                && span.y < max(span.x, span.z) * 0.25
                && high.y < minPoint.y + bounds.y * 0.35
            let circular = ordered[1] > ordered[2] * 0.75 && ordered[0] < ordered[2] * 0.08
            let wheel = circular && ordered[2] < longest * 0.22 && center.y < minPoint.y + bounds.y * 0.6
            let shell = ordered[2] > longest * 0.55 && ordered[0] > ordered[2] * 0.12
            let cabin = center.y > minPoint.y + bounds.y * 0.42
            if underside || wheel || shell || points.count > 80 || !cabin { continue }
            let centerIndex = UInt32(capPoints.count)
            capPoints.append(SCNVector3(center.x, center.y, center.z))
            for corner in points.indices {
                let start = UInt32(capPoints.count)
                let point = points[corner]
                capPoints.append(SCNVector3(point.x, point.y, point.z))
                let end = corner + 1 == points.count ? centerIndex + 1 : start + 1
                capIndices.append(centerIndex)
                capIndices.append(start)
                capIndices.append(end)
            }
        }
        guard !capIndices.isEmpty else { return nil }
        let source = SCNGeometrySource(vertices: capPoints)
        let capped = SCNGeometryElement(indices: capIndices, primitiveType: .triangles)
        let caps = SCNGeometry(sources: [source], elements: [capped])
        let material = SCNMaterial()
        material.name = "CabinCap"
        material.diffuse.contents = HouseColor(red: 0.15, green: 0.18, blue: 0.22, alpha: 1)
        material.lightingModel = .constant
        material.isDoubleSided = true
        caps.materials = [material]
        caps.name = "CabinCaps"
        return caps
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

// MARK: - Loading helper

enum ResidentialClassicScene {
    /// How many times the house file was opened. A view refresh must not reload it.
    static var loadCount = 0

    /// Loads ResidentialClassic.usdz (or .scn/.glb-converted fallback) from the app bundle.
    static func load() -> SCNScene? {
        loadCount += 1
        for ext in ["usdz", "scn"] {
            if let url = HouseLighting.resourceURL(name: "ResidentialClassic", ext: ext),
               let scene = try? SCNScene(url: url, options: [.checkConsistency: true]) {
                return scene
            }
        }
        return nil
    }
}
