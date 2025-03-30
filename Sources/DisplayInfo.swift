/*
 * Copyright 2025 Hiroki Kawakami
 */

import Foundation
import CoreGraphics
import DisplayLayoutBridge

struct DisplayError: Error, CustomStringConvertible {
    let message: String
    var description: String {
        return "DisplayError: \(self.message)"
    }
}

struct DisplayInfo {

    let id: CGDirectDisplayID
    let name: String
    let uuid: UUID
    let serialNumber: UInt32
    let ioLocation: String?

    static var onlineDisplayCount: Int {
        var displayCount: UInt32 = 0;
        CGGetOnlineDisplayList(UInt32.max, nil, &displayCount);
        return Int(displayCount)
    }
    static var onlineDisplays: [DisplayInfo] {
        var onlineDisplays = [CGDirectDisplayID](repeating: 0, count: self.onlineDisplayCount);
        var displayCount: UInt32 = 0;
        CGGetOnlineDisplayList(UInt32(onlineDisplays.count), &onlineDisplays, &displayCount);
        return onlineDisplays[0..<Int(displayCount)].compactMap({ id in DisplayInfo(id: id) })
    }

    static var activeDisplayCount: Int {
        var displayCount: UInt32 = 0;
        CGGetActiveDisplayList(UInt32.max, nil, &displayCount);
        return Int(displayCount)
    }
    static var activeDisplays: [DisplayInfo] {
        var activeDisplays = [CGDirectDisplayID](repeating: 0, count: self.activeDisplayCount);
        var displayCount: UInt32 = 0;
        CGGetActiveDisplayList(UInt32(onlineDisplays.count), &activeDisplays, &displayCount);
        return activeDisplays[0..<Int(displayCount)].compactMap({ id in DisplayInfo(id: id) })
    }

    private init?(id: CGDirectDisplayID) {
        guard let info = CoreDisplay_DisplayCreateInfoDictionary(id)?.takeUnretainedValue() as NSDictionary? else {
            return nil
        }
        self.id = id

        let size = CGDisplayScreenSize(id)
        let diagonal = round(sqrt((size.width * size.width) + (size.height * size.height)) / 25.4)
        if let nameDict = info["DisplayProductName"] as? NSDictionary, let name = nameDict["en_US"] as? String {
            self.name = name
        } else {
            self.name = CGDisplayIsBuiltin(id) != 0 ? "Built-in Display" : "\(Int(diagonal)) inch External Display"
        }

        guard let uuidString = info["kCGDisplayUUID"] as? String, let uuid = UUID(uuidString: uuidString) else {
            return nil
        }
        self.uuid = uuid

        self.serialNumber = CGDisplaySerialNumber(id)
        self.ioLocation = info["IODisplayLocation"] as? String
    }

    var isActive: Bool { CGDisplayIsActive(self.id) != 0 }
    var isInMirrorSet: Bool { CGDisplayIsInMirrorSet(self.id) != 0 }
    var displayDataChannel: DisplayDataChannel? {
        if let ioLocation = self.ioLocation {
            DisplayDataChannel(for: ioLocation)
        } else {
            nil
        }
    }

    static func beginDisplayConfiguration() throws -> CGDisplayConfigRef {
        var ref: CGDisplayConfigRef?
        CGBeginDisplayConfiguration(&ref)
        if let ref = ref { return ref }
        throw DisplayError(message: "Failed to begin display configuration!")
    }
    static func endDisplayConfiguration(configRef: CGDisplayConfigRef) {
        CGCompleteDisplayConfiguration(configRef, .permanently)
    }

    var modes: [DisplayMode] {
        var nModes: Int32 = 0
        CGSGetNumberOfDisplayModes(id, &nModes)
        if nModes <= 0 { return [] }

        var result: [DisplayMode] = []
        for i in 0..<nModes {
            var modeD4 = modes_D4()
            CGSGetDisplayModeDescriptionOfLength(id, i, &modeD4, Int32(MemoryLayout<modes_D4>.size))

            result.append(DisplayMode(
                mode: Int32(modeD4.derived.mode),
                resolution: DisplayMode.Resolution(width: Int(modeD4.derived.width), height: Int(modeD4.derived.height)),
                refreshRate: modeD4.derived.freq != 0 ? Int(modeD4.derived.freq) : nil,
                colorDepth: Int(modeD4.derived.depth),
                hidpi: modeD4.derived.density == 2.0
            ))
        }

        return result
    }

    var currentMode: DisplayMode? {
        if !isActive { return nil }
        var modeId: Int32 = 0;
        CGSGetCurrentDisplayMode(self.id, &modeId)
        var modeD4 = modes_D4()
        CGSGetDisplayModeDescriptionOfLength(self.id, modeId, &modeD4, 0xd4)

        return DisplayMode(
            mode: Int32(modeD4.derived.mode),
            resolution: DisplayMode.Resolution(width: Int(modeD4.derived.width), height: Int(modeD4.derived.height)),
            refreshRate: modeD4.derived.freq != 0 ? Int(modeD4.derived.freq) : nil,
            colorDepth: Int(modeD4.derived.depth),
            hidpi: modeD4.derived.density == 2.0
        )
    }

    var location: DisplayLocation {
        let mirrorDisplayId = CGDisplayMirrorsDisplay(self.id)
        if isInMirrorSet && mirrorDisplayId != 0 {
            return .mirror(primary: DisplayInfo(id: mirrorDisplayId)!)
        } else if isActive {
            let bounds = CGDisplayBounds(self.id)
            return .primary(x: bounds.origin.x, y: bounds.origin.y, isMain: CGDisplayIsMain(self.id) != 0)
        } else {
            return .disable
        }
    }

    func findMode(resolution: DisplayMode.Resolution?, refreshRate: Int?, hidpi: Bool?) -> DisplayMode? {
        guard let resolution = resolution ?? currentMode?.resolution else { return nil }
        let modes = self.modes.filter {
            $0.resolution == resolution &&
            (refreshRate == nil || $0.refreshRate == refreshRate) &&
            (hidpi == nil || $0.hidpi == hidpi)
        }
        return modes.first
    }

    func setMode(ref: CGDisplayConfigRef, mode: Int32) {
        CGSConfigureDisplayMode(ref, id, mode)
    }
    func setMode(ref: CGDisplayConfigRef, mode: DisplayMode) {
        setMode(ref: ref, mode: mode.mode)
    }
    func setMirror(ref: CGDisplayConfigRef, mirrors: DisplayInfo?) {
        CGConfigureDisplayMirrorOfDisplay(ref, id, mirrors?.id ?? kCGNullDirectDisplay)
    }
    func setPosition(ref: CGDisplayConfigRef, origin: DisplayLocation.Origin) {
        CGConfigureDisplayOrigin(ref, id, Int32(origin.x), Int32(origin.y))
    }
}

struct DisplayMode {

    struct Resolution: CustomStringConvertible, Codable, Equatable {
        let width: Int
        let height: Int
        var description: String { "\(width)x\(height)" }
    }

    let mode: Int32
    let resolution: Resolution
    let refreshRate: Int?
    let colorDepth: Int
    let hidpi: Bool
}

enum DisplayLocation {
    case primary(x: Double, y: Double, isMain: Bool)
    case mirror(primary: DisplayInfo)
    case disable

    struct Origin: CustomStringConvertible, Codable, Equatable {
        let x: Int
        let y: Int
        var description: String { "(\(x),\(y))" }
    }

    var origin: Origin? {
        if case .primary(let x, let y, _) = self {
            Origin(x: Int(x), y: Int(y))
        } else {
            nil
        }
    }

    var mirrors: String? {
        if case .mirror(let primary) = self {
            "uuid:\(primary.uuid)"
        } else {
            nil
        }
    }

    var isMain: Bool {
        if case .primary(_, _, let isMain) = self {
            isMain
        } else {
            false
        }
    }
}
