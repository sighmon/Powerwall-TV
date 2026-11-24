// TeslaPaint.swift
// Paint table copied from the Tesla app (4.61.6, build 4647):
// assets_pack/assets/godot/mobile/scripts/VehicleOptions.gdc → `ExteriorColorValue`
// (decompiled with GDRE Tools for GDScript bytecode 3.2.2). The application logic is in
// mobile/scripts/Vehicle.gdc: set_paint_color_with_override / set_paint_color_override / remap_color.
//
// In the app the colours are a SpatialMaterial albedo (sRGB hex) plus metallic and roughness.
// They are deliberately very dark because the app gets most of the paint's look from
// skybox reflections. Under plain SceneKit lighting, give the scene a lightingEnvironment
// (HDRI) or raise `displayBoost`. That boost is our own addition, not an app value.
//
// The app has no clearcoat parameter. SceneKit supports clearCoat (tvOS 13+), but it is opt-in
// here and defaults to 0, matching the app.

import SceneKit
#if canImport(UIKit)
import UIKit
typealias HouseColor = UIColor
#elseif canImport(AppKit)
import AppKit
typealias HouseColor = NSColor
#endif

struct TeslaPaint: Equatable {
    let name: String
    let hex: UInt32          // sRGB albedo as stored in the app
    let metallic: CGFloat
    let roughness: CGFloat

    /// The app's BASE_ROUGHNESS constant.
    static let baseRoughness: CGFloat = 0.04
    /// The app's FALLBACK_EXTERIOR_COLOR, used for any unknown exterior_color.
    static let fallback = TeslaPaint(name: "Fallback", hex: 0x161616, metallic: 0.6, roughness: 0.04)

    /// Every entry in VehicleOptions.ExteriorColorValue, keyed exactly as the Fleet API
    /// `vehicle_config.exterior_color` sends it.
    static let table: [String: TeslaPaint] = [
        "RedMulticoat": .init(name: "RedMulticoat", hex: 0x0a0101, metallic: 0.1, roughness: 0.04),
        "SolidBlack": .init(name: "SolidBlack", hex: 0x0e0e0e, metallic: 1.0, roughness: 0.04),
        "SilverMetallic": .init(name: "SilverMetallic", hex: 0x161616, metallic: 0.6, roughness: 0.04),
        "MidnightSilver": .init(name: "MidnightSilver", hex: 0x131416, metallic: 0.8, roughness: 0.04),
        "DeepBlue": .init(name: "DeepBlue", hex: 0x000919, metallic: 0.7, roughness: 0.04),
        "PearlWhite": .init(name: "PearlWhite", hex: 0x181818, metallic: 0.25, roughness: 0.2),
        "TitaniumCopper": .init(name: "TitaniumCopper", hex: 0x181510, metallic: 0.8, roughness: 0.04),
        "Red": .init(name: "Red", hex: 0x0a0101, metallic: 0.1, roughness: 0.04),
        "Black": .init(name: "Black", hex: 0x0e0e0e, metallic: 1.0, roughness: 0.04),
        "Silver": .init(name: "Silver", hex: 0x161616, metallic: 0.6, roughness: 0.04),
        "Grey": .init(name: "Grey", hex: 0x131416, metallic: 0.8, roughness: 0.04),
        "SignatureBlue": .init(name: "SignatureBlue", hex: 0x000206, metallic: 0.2, roughness: 0.04),
        "White": .init(name: "White", hex: 0x141414, metallic: 0.2, roughness: 0.3),
        "Titanium": .init(name: "Titanium", hex: 0x181510, metallic: 0.8, roughness: 0.04),
        "Pearl": .init(name: "Pearl", hex: 0x131313, metallic: 0.01, roughness: 0.04),
        "MetallicBlack": .init(name: "MetallicBlack", hex: 0x0e0e0e, metallic: 1.0, roughness: 0.04),
        "SteelGrey": .init(name: "SteelGrey", hex: 0x131416, metallic: 0.8, roughness: 0.04),
        "Green": .init(name: "Green", hex: 0x060a0a, metallic: 0.8, roughness: 0.04),
        "Brown": .init(name: "Brown", hex: 0x181514, metallic: 0.8, roughness: 0.04),
        "SigRed": .init(name: "SigRed", hex: 0x110305, metallic: 0.7, roughness: 0.04),
        "Blue": .init(name: "Blue", hex: 0x000104, metallic: 0.6, roughness: 0.04),
        "MidnightCherryRed": .init(name: "MidnightCherryRed", hex: 0x200006, metallic: 0.8, roughness: 0.01),
        "Quicksilver": .init(name: "Quicksilver", hex: 0x2b2d35, metallic: 0.85, roughness: 0.2),
        "UltraRed": .init(name: "UltraRed", hex: 0x250006, metallic: 0.7, roughness: 0.05),
        "StealthGrey": .init(name: "StealthGrey", hex: 0x121417, metallic: 0.88, roughness: 0.1),
        "LunarSilver": .init(name: "LunarSilver", hex: 0x343438, metallic: 0.898, roughness: 0.28),
        "GlacierBlue": .init(name: "GlacierBlue", hex: 0x12161f, metallic: 0.7, roughness: 0.1),
        "DiamondBlack": .init(name: "DiamondBlack", hex: 0x040404, metallic: 0.75, roughness: 0.02),
        "FrostBlue": .init(name: "FrostBlue", hex: 0x111317, metallic: 0.716, roughness: 0.05),
        "SilkroadSilver": .init(name: "SilkroadSilver", hex: 0x2d2c2d, metallic: 0.826, roughness: 0.204),
        "MarineBlue": .init(name: "MarineBlue", hex: 0x01050a, metallic: 0.85, roughness: 0.02),
        "GarnetRed": .init(name: "GarnetRed", hex: 0x1d0305, metallic: 0.8, roughness: 0.05),
        "CoastalBlue": .init(name: "CoastalBlue", hex: 0x040710, metallic: 0.5, roughness: 0.04),
    ]

    /// Distinct paints in Fleet-table order. Later aliases that share the same look are left out.
    static let catalogueNames: [String] = [
        "RedMulticoat", "SolidBlack", "SilverMetallic", "MidnightSilver", "DeepBlue",
        "PearlWhite", "TitaniumCopper", "SignatureBlue", "White", "Pearl", "Green",
        "Brown", "SigRed", "Blue", "MidnightCherryRed", "Quicksilver", "UltraRed",
        "StealthGrey", "LunarSilver", "GlacierBlue", "DiamondBlack", "FrostBlue",
        "SilkroadSilver", "MarineBlue", "GarnetRed", "CoastalBlue",
    ]

    static var catalogue: [TeslaPaint] {
        catalogueNames.compactMap { table[$0] }
    }

    /// `vehicle_config.paint_color_override`, rgb in 0–255. Decimal point stays a dot.
    var fleetOverride: String {
        overrideString(hex: hex)
    }

    /// Readable stand-ins for the demo. The Fleet hexes are reflection albedos:
    /// White is `0x141414` and Pearl White is `0x181818`, so both paint as dark grey
    /// once `displayBoost` is applied, and Silver lands on top of them.
    static let demoDisplayHex: [String: UInt32] = [
        "RedMulticoat": 0x8E1B1B,
        "SolidBlack": 0x1A1A1A,
        "SilverMetallic": 0xC5C8CE,
        "MidnightSilver": 0x5A5E66,
        "DeepBlue": 0x1A3F8F,
        "PearlWhite": 0xF3F0E8,
        "TitaniumCopper": 0xB08D6A,
        "SignatureBlue": 0x3B6FB6,
        "White": 0xF7F7F7,
        "Pearl": 0xE6E0D4,
        "Green": 0x2F6B45,
        "Brown": 0x6B4A32,
        "SigRed": 0x9A2430,
        "Blue": 0x2451A3,
        "MidnightCherryRed": 0x6A1A2A,
        "Quicksilver": 0xD5D7DE,
        "UltraRed": 0xD01020,
        "StealthGrey": 0x6A6E74,
        "LunarSilver": 0xE4E5E8,
        "GlacierBlue": 0xA9C0D4,
        "DiamondBlack": 0x101014,
        "FrostBlue": 0x7F9AAD,
        "SilkroadSilver": 0xCFCDD0,
        "MarineBlue": 0x163A5F,
        "GarnetRed": 0x8A2A32,
        "CoastalBlue": 0x4E78A8,
        // Older aliases in the Fleet table, so a live car with one of these names still reads right.
        "Red": 0x8E1B1B,
        "Black": 0x1A1A1A,
        "MetallicBlack": 0x15151A,
        "Silver": 0xC5C8CE,
        "Grey": 0x6E7176,
        "SteelGrey": 0x6E7176,
        "Titanium": 0xB08D6A,
    ]

    /// The paint in display space: the readable colour above with the app's metal and roughness.
    /// Apply it with `displayBoost` 1. The showroom uses this for every named paint, live or demo.
    var display: TeslaPaint {
        TeslaPaint(name: name, hex: TeslaPaint.demoDisplayHex[name] ?? hex, metallic: metallic, roughness: roughness)
    }

    /// Paint option codes (`option_codes` on products and `/vehicles`, and the B-pillar label), from
    /// Tesla's service manual paint tables. Codes with no paint in the app's table are left out.
    static let optionCodes: [String: String] = [
        "PPSW": "PearlWhite",        // Pearl White Multi-Coat
        "PM00": "PearlWhite",        // Pearl White Pro Multi-Coat
        "PBCW": "White",             // Solid / Base White
        "PMNG": "MidnightSilver",    // Midnight Silver Metallic
        "PMSS": "SilverMetallic",    // Silver Metallic
        "PBSB": "SolidBlack",        // Solid Black
        "PMBL": "MetallicBlack",     // Obsidian Black Metallic
        "PPSB": "DeepBlue",          // Deep Blue Metallic
        "PPMR": "RedMulticoat",      // Red Multi-Coat
        "PPSR": "SigRed",            // Signature Red
        "PPTI": "Titanium",          // Titanium Metallic
        "PMTG": "SteelGrey",         // Dolphin Grey
        "PMSG": "Green",             // Green Metallic
        "PMAB": "Brown",             // Anza Brown
        "PMMB": "Blue",              // Blue Metallic
        "PN00": "Quicksilver",
        "PN01": "StealthGrey",
        "PN02": "LunarSilver",
        "PR00": "MidnightCherryRed",
        "PR01": "UltraRed",
        "PX02": "DiamondBlack",
        "PB00": "FrostBlue",
        "PB01": "GlacierBlue",
        "PB02": "MarineBlue",
        "PB03": "CoastalBlue",
    ]

    /// Marketing names and spellings Fleet or the order site use for a table paint.
    private static let aliases: [String: String] = [
        "stealthgray": "StealthGrey",
        "obsidianblack": "MetallicBlack",
        "solidwhite": "White",
        "basewhite": "White",
        "signaturered": "SigRed",
        "dolphingrey": "SteelGrey",
        "dolphingray": "SteelGrey",
        "midnightsilvergray": "MidnightSilver",
        "eclipseblack": "SolidBlack",
        "oceanblue": "DeepBlue",
        "redmulticoat": "RedMulticoat",
        "pearlwhitepro": "PearlWhite",
        "anzabrown": "Brown",
    ]

    /// Table name for a paint option code list such as "AD15,MDL3,PPSW,W40B". Nil when no code is a paint.
    static func exteriorColor(optionCodes: String?) -> String? {
        guard let optionCodes else { return nil }
        for code in optionCodes.split(whereSeparator: { $0 == "," || $0 == " " || $0 == ";" }) {
            let key = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            if let name = Self.optionCodes[key] { return name }
        }
        return nil
    }

    /// Products' `color` (often null) can be a paint name or a paint code. Then `option_codes`.
    static func exteriorColor(productColor: String?, optionCodes: String?) -> String? {
        if let color = productColor?.trimmingCharacters(in: .whitespacesAndNewlines), !color.isEmpty {
            if let paint = TeslaPaint(exteriorColor: color) { return paint.name }
            if let name = exteriorColor(optionCodes: color) { return name }
        }
        return exteriorColor(optionCodes: optionCodes)
    }

    /// Demo paint in display space. Apply it with `displayBoost` 1, not the live lift of 4.
    var demoOverride: String {
        overrideString(hex: TeslaPaint.demoDisplayHex[name] ?? hex)
    }

    /// "PearlWhite" → "Pearl White".
    static func spacedName(_ name: String) -> String {
        var words = ""
        for character in name {
            if character.isUppercase, !words.isEmpty { words.append(" ") }
            words.append(character)
        }
        return words
    }

    private func overrideString(hex displayHex: UInt32) -> String {
        let red = Int((displayHex >> 16) & 0xff)
        let green = Int((displayHex >> 8) & 0xff)
        let blue = Int(displayHex & 0xff)
        let metal = String(format: "%.4f", locale: Locale(identifier: "en_US_POSIX"), Double(metallic))
        let rough = String(format: "%.4f", locale: Locale(identifier: "en_US_POSIX"), Double(roughness))
        return "\(red),\(green),\(blue),\(metal),\(rough)"
    }

    private static func normalise(_ s: String) -> String {
        s.lowercased().filter { $0.isLetter || $0.isNumber }
    }
    private static let normalisedTable: [String: TeslaPaint] =
        Dictionary(uniqueKeysWithValues: table.map { (normalise($0.key), $0.value) })

    init(name: String, hex: UInt32, metallic: CGFloat, roughness: CGFloat) {
        self.name = name; self.hex = hex; self.metallic = metallic; self.roughness = roughness
    }

    /// Accepts "PearlWhite", "pearl white", "PEARL_WHITE", and so on. Returns nil if the colour is
    /// not in the app's table. The app itself would then use `TeslaPaint.fallback`:
    /// `TeslaPaint(exteriorColor: c) ?? .fallback`.
    /// Marketing spellings ("Stealth Gray", "Pearl White Multi-Coat", "Deep Blue Metallic") resolve too.
    init?(exteriorColor: String) {
        let key = TeslaPaint.normalise(exteriorColor)
        guard !key.isEmpty else { return nil }
        var candidates = [key]
        for suffix in ["multicoat", "metallic", "paint"] where key.hasSuffix(suffix) && key.count > suffix.count {
            candidates.append(String(key.dropLast(suffix.count)))
        }
        for candidate in candidates {
            if let p = TeslaPaint.normalisedTable[candidate] {
                self = p
                return
            }
            if let name = TeslaPaint.aliases[candidate], let p = TeslaPaint.table[name] {
                self = p
                return
            }
        }
        return nil
    }

    /// `vehicle_config.paint_color_override`: "r,g,b,metallic,roughness" with rgb in 0–255.
    /// The app prefers this over exterior_color whenever it has exactly 5 fields. If
    /// `vehicle_state.colorizer_paint_remap_enabled` is true, the app multiplies HSV value by 0.325.
    init?(paintColorOverride: String, colorizerRemap: Bool = false) {
        let f = paintColorOverride.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard f.count == 5 else { return nil }
        var c = HouseColor(red: f[0] / 255, green: f[1] / 255, blue: f[2] / 255, alpha: 1)
        if colorizerRemap {
            var h: CGFloat = 0, s: CGFloat = 0, v: CGFloat = 0, a: CGFloat = 0
            c.getHue(&h, saturation: &s, brightness: &v, alpha: &a)
            c = HouseColor(hue: h, saturation: s, brightness: v * 0.325, alpha: 1)
        }
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getRed(&r, green: &g, blue: &b, alpha: &a)
        let hex = (UInt32(r * 255) << 16) | (UInt32(g * 255) << 8) | UInt32(b * 255)
        self.init(name: "Override", hex: hex, metallic: CGFloat(f[3]), roughness: CGFloat(f[4]))
    }

    /// The app's own priority: override first, then exterior_color, then fallback.
    static func resolve(exteriorColor: String?, paintColorOverride: String?, colorizerRemap: Bool = false) -> TeslaPaint {
        if let o = paintColorOverride, let p = TeslaPaint(paintColorOverride: o, colorizerRemap: colorizerRemap) { return p }
        if let e = exteriorColor, let p = TeslaPaint(exteriorColor: e) { return p }
        return .fallback
    }

    func colour(displayBoost: CGFloat = 1) -> HouseColor {
        func ch(_ shift: UInt32) -> CGFloat { min(1, CGFloat((hex >> shift) & 0xff) / 255 * displayBoost) }
        return HouseColor(red: ch(16), green: ch(8), blue: ch(0), alpha: 1)
    }

    func apply(to material: SCNMaterial, displayBoost: CGFloat = 1, clearCoat: CGFloat = 0) {
        material.lightingModel = .physicallyBased
        material.diffuse.contents = colour(displayBoost: displayBoost)
        material.metalness.contents = metallic
        material.roughness.contents = roughness
        if #available(tvOS 13.0, iOS 13.0, macOS 10.15, *) {
            material.clearCoat.contents = clearCoat
            material.clearCoatRoughness.contents = roughness
        }
    }
}
