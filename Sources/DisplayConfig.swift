/*
 * Copyright 2025 Hiroki Kawakami
 */

import Foundation
import Collections

struct DisplayConfigError: Error, CustomStringConvertible {
    let message: String
    var description: String {
        return "DisplayConfigError: \(self.message)"
    }
}

class DisplayConfig {

    static func dump() async throws -> String {
        var result: [String: Device] = [:]
        for info in DisplayInfo.onlineDisplays {
            let location = info.location
            let ddc = info.displayDataChannel
            if let mode = info.currentMode {
                result["uuid:\(info.uuid)"] = Device(
                    resolution: mode.resolution,
                    refreshRate: mode.refreshRate,
                    hidpi: mode.hidpi,
                    origin: location.origin,
                    mirrors: location.mirrors,
                    isMain: location.isMain,
                    inputSource: try await ddc?.inputSource.name
                )
            } else {
                result["uuid:\(info.uuid)"] = Device(enable: false)
            }
        }
        let jsonData = try JSONEncoder().encode(result)
        return String(data: jsonData, encoding: .utf8)!
    }

    static func restore(json: String) async throws {
        guard let data = json.data(using: .utf8) else {
            throw DisplayConfigError(message: "Failed to convert json data")
        }
        let config = try JSONDecoder().decode([String: Device].self, from: data)

        func displayInfo(for key: String) -> DisplayInfo? {
            if key.starts(with: "uuid:") {
                let uuid = UUID(uuidString: key.replacingOccurrences(of: "uuid:", with: ""))
                for info in DisplayInfo.onlineDisplays {
                    if info.uuid == uuid {
                        return info
                    }
                }
            } else if key.starts(with: "sidecar:") {
                let name = key.replacingOccurrences(of: "sidecar:", with: "")
                let devices = SidecarDisplayManager.shared.connectedDevices()
                if devices.first?.name == name {
                    for info in DisplayInfo.onlineDisplays {
                        if info.name == "Sidecar Display" {
                            return info
                        }
                    }
                }
            }
            return nil
        }
        func sidecarDevice(for key: String) -> SidecarDisplay? {
            if key.starts(with: "sidecar:") {
                let name = key.replacingOccurrences(of: "sidecar:", with: "")
                for device in SidecarDisplayManager.shared.devices() {
                    if device.name == name { return device }
                }
            }
            return nil
        }

        // Set DDC/CI Display Input Source & Sidecar Device Connection
        await withThrowingTaskGroup(of: Void.self) { group in
            for (key, value) in config {
                group.addTask {
                    if let inputSource = DisplayDataChannel.InputSource.from(value.inputSource) {
                        let res = try await displayInfo(for: key)?.displayDataChannel?.setInputSource(inputSource: inputSource)
                        if res == true { try await Task.sleep(nanoseconds: 1000 * 1000 * 1000) }
                    }
                    if let sidecarDevice = sidecarDevice(for: key) {
                        let connected = SidecarDisplayManager.shared.isConnected(device: sidecarDevice)
                        if value.enable == true && !connected {
                            await SidecarDisplayManager.shared.connect(device: sidecarDevice)
                        } else if value.enable == false && connected {
                            await SidecarDisplayManager.shared.disconnect(device: sidecarDevice)
                            try await Task.sleep(nanoseconds: 1000 * 1000 * 1000)
                        }
                    }
                }
            }
        }

        // Set Display Mode
        let ref = try DisplayInfo.beginDisplayConfiguration()
        for (key, value) in config {
            let info = displayInfo(for: key)
            if !(value.resolution == nil && value.refreshRate == nil && value.hidpi == nil) {
                if let mode = info?.findMode(resolution: value.resolution, refreshRate: value.refreshRate, hidpi: value.hidpi) {
                    info?.setMode(ref: ref, mode: mode)
                }
            }
            if let mirrors = value.mirrors {
                info?.setMirror(ref: ref, mirrors: displayInfo(for: mirrors))
            }
        }
        DisplayInfo.endDisplayConfiguration(configRef: ref)
    }

    struct Device: Codable {
        let enable: Bool?
        let resolution: DisplayMode.Resolution?
        let refreshRate: Int?
        let hidpi: Bool?
        let origin: DisplayLocation.Origin?
        let mirrors: String?
        let isMain: Bool?
        let inputSource: String?

        init(
            enable: Bool? = nil,
            resolution: DisplayMode.Resolution? = nil,
            refreshRate: Int? = nil,
            hidpi: Bool? = nil,
            origin: DisplayLocation.Origin? = nil,
            mirrors: String? = nil,
            isMain: Bool? = nil,
            inputSource: String? = nil
        ) {
            self.enable = enable
            self.resolution = resolution
            self.refreshRate = refreshRate
            self.hidpi = hidpi
            self.origin = origin
            self.mirrors = mirrors
            self.isMain = isMain
            self.inputSource = inputSource
        }
    }
}

