// The Swift Programming Language
// https://docs.swift.org/swift-book
//
// Swift Argument Parser
// https://swiftpackageindex.com/apple/swift-argument-parser/documentation

import Foundation
import ArgumentParser

@main
struct DisplayLayout: AsyncParsableCommand {

    static let configuration = CommandConfiguration(
        commandName: "dilay",
        abstract: "Manage Display Settings",
        subcommands: [
            Displays.self,
            Modes.self,
            Setmode.self,
            Capabilities.self,
            Getvcp.self,
            Setvcp.self,
            Sidecar.self,
            Currentconfig.self,
            Setconfig.self,
        ]
    )

    struct CommandError: Error, CustomStringConvertible {
        let message: String

        var description: String {
            return message
        }
    }

    struct Displays: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Check Display Informations"
        )

        mutating func run() async throws {
            for (i, display) in DisplayInfo.onlineDisplays.enumerated() {
                print("[\(i)] \(display.name) (\(display.uuid))")
            }
        }
    }

    struct DisplaySelectorOption: ParsableArguments {
        @Option(name: [.customShort("d"), .long],  help: "Display Selector")
        var display: String?

        func info() throws -> DisplayInfo {
            let displays = DisplayInfo.onlineDisplays
            for display in displays {
                if display.uuid.uuidString == self.display {
                    return display
                }
            }
            for display in displays {
                if display.name == self.display {
                    return display
                }
            }
            if let index = Int(self.display ?? "0") {
                if index >= displays.count {
                    throw CommandError(message: "Display index (\(index)) is out of range (0-\(displays.count - 1)).")
                }
                return displays[index]
            }
            throw CommandError(message: "Display \"\(self.display ?? "")\" not found.")
        }
        func ddc() throws -> DisplayDataChannel {
            let info = try self.info()
            guard let ioLocation = info.ioLocation else {
                throw CommandError(message: "Cannot access IORegistry for \"\(info.name)\"")
            }
            guard let ddc = DisplayDataChannel(for: ioLocation) else {
                throw CommandError(message: "Cannot find DDC/CI Service for \"\(info.name)\"")
            }
            return ddc
        }
    }

    struct Modes: AsyncParsableCommand {
        @OptionGroup var displayOption: DisplaySelectorOption

        mutating func run() async throws {
            let info = try displayOption.info()
            for (i, config) in info.modes.enumerated() {
                var refreshRate = ""
                if let hz = config.refreshRate { refreshRate = "@\(hz)Hz" }
                print("[\(i)] \(config.resolution)\(refreshRate) colorDepth=\(config.colorDepth) \(config.hidpi ? "HiDPI" : "")")
            }
        }
    }

    struct Setmode: AsyncParsableCommand {
        @OptionGroup var displayOption: DisplaySelectorOption
        @Argument var mode: String

        mutating func run() async throws {
            let info = try displayOption.info()
            let ref = try DisplayInfo.beginDisplayConfiguration()
            if let index = Int(mode) {
                let modes = info.modes
                info.setMode(ref: ref, mode: modes[index].mode)
            } else {

            }
            DisplayInfo.endDisplayConfiguration(configRef: ref)
        }
    }

    struct Capabilities: AsyncParsableCommand {
        @OptionGroup var displayOption: DisplaySelectorOption

        mutating func run() async throws {
            let ddc = try displayOption.ddc()
            let raw = try await ddc.getRawCapability()
            print(raw)
        }
    }

    struct Getvcp: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Get DDC/CI VCP Value")
        @OptionGroup var displayOption: DisplaySelectorOption
        @Argument var attribute: String

        mutating func run() async throws {
            let ddc = try displayOption.ddc()
            guard let attribute = DisplayDataChannel.VCPAttribute.find(string: self.attribute) else {
                throw CommandError(message: "Invalid VCP Attribute: \"\(self.attribute)\"")
            }
            let value = try await ddc.getVcpFeature(attribute: attribute)
            print("\(value.currentLowByte)")
        }
    }
    struct Setvcp: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Set DDC/CI VCP Value")
        @OptionGroup var displayOption: DisplaySelectorOption
        @Argument var attribute: String
        @Argument var value: UInt16

        mutating func run() async throws {
            let ddc = try displayOption.ddc()
            guard let attribute = DisplayDataChannel.VCPAttribute.find(string: self.attribute) else {
                throw CommandError(message: "Invalid VCP Attribute: \"\(self.attribute)\"")
            }
            try await ddc.setVcpFeature(value: DisplayDataChannel.VCPValue(attribute: attribute, current: self.value))
        }
    }

    struct Sidecar: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Manage iPad Sidecar Settings",
            subcommands: [
                List.self,
                Connect.self,
                Disconnect.self,
            ]
        )

        struct List: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                abstract: "List Sidecar Devices"
            )

            mutating func run() async throws {
                let manager = SidecarDisplayManager.shared
                let connectedDevices = manager.connectedDevices()
                for (i, device) in manager.devices().enumerated() {
                    let prefix = connectedDevices.contains(device) ? "*" : " "
                    print("\(prefix) [\(i)] \(device.name) (\(device.identifier))")
                }
            }
        }

        struct DeviceOption: ParsableArguments {
            @Argument(help: "Device Selector")
            var device: String

            func find(manager: SidecarDisplayManager) throws -> SidecarDisplay {
                let devices = manager.devices()
                for device in devices {
                    if device.identifier.uuidString == self.device {
                        return device
                    }
                }
                for device in devices {
                    if device.name == self.device {
                        return device
                    }
                }
                if let index = Int(self.device) {
                    if index >= devices.count {
                        throw CommandError(message: "Sidecar Device index (\(index)) is out of range (0-\(devices.count - 1)).")
                    }
                    return devices[index]
                }
                throw CommandError(message: "Sidecar Device \"\(self.device)\" not found.")
            }
        }

        struct Connect: AsyncParsableCommand {
            static let configuration: CommandConfiguration = CommandConfiguration(abstract: "Disonnect Sidecar Device")

            @OptionGroup var deviceOption: DeviceOption

            mutating func run() async throws{
                let manager = SidecarDisplayManager.shared
                let device = try deviceOption.find(manager: manager)
                await manager.connect(device: device)
            }
        }

        struct Disconnect: AsyncParsableCommand {
            static let configuration: CommandConfiguration = CommandConfiguration(abstract: "Disonnect Sidecar Device")

            @OptionGroup var deviceOption: DeviceOption

            mutating func run() async throws{
                let manager = SidecarDisplayManager.shared
                let device = try deviceOption.find(manager: manager)
                await manager.disconnect(device: device)
            }
        }
    }

    struct Currentconfig: AsyncParsableCommand {
        mutating func run() async throws{
            let str = try await DisplayConfig.dump()
            return print(str)
        }
    }

    struct Setconfig: AsyncParsableCommand {
        @Argument(help: "Device Configuration")
        var config: String

        mutating func run() async throws{
            try await DisplayConfig.restore(json: config)
        }
    }
}
