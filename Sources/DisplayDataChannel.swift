/*
 * Copyright 2025 Hiroki Kawakami
 */

import Foundation
import IOKit
import StaticMemberIterable
import DisplayLayoutBridge

private func IOString(_ proc: (UnsafeMutablePointer<CChar>) -> Void) -> String {
    var buf = [CChar](repeating: 0, count: MemoryLayout<io_string_t>.size)
    proc(&buf)
    return String(cString: &buf)
}

class DisplayDataChannel {

    private let avService: IOAVService
    var readDelayMs: Int = 40
    var writeDelayMs: Int = 50

    init?(for ioLocation: String) {
        let ioRootEntry = IORegistryGetRootEntry(kIOMasterPortDefault)
        var ioIterator = io_iterator_t()
        defer {
            IOObjectRelease(ioRootEntry)
            IOObjectRelease(ioIterator)
        }
        guard IORegistryEntryCreateIterator(ioRootEntry, kIOServicePlane, IOOptionBits(kIORegistryIterateRecursively), &ioIterator) == KERN_SUCCESS else {
            print("IORegistryEntryCreateIterator failed!")
            return nil
        }

        // Seek to service entry
        while true {
            let service = IOIteratorNext(ioIterator)
            if service == MACH_PORT_NULL { return nil }

            let path = IOString({ buf in IORegistryEntryGetPath(service, kIOServicePlane, buf) })
            if path == ioLocation { break }
        }

        // Find AVService Proxy
        while true {
            let service = IOIteratorNext(ioIterator)
            if service == MACH_PORT_NULL { break }

            let name = IOString({ buf in IORegistryEntryGetName(service, buf)})
            if name == "DCPAVServiceProxy" {
                let avService = IOAVServiceCreateWithService(kCFAllocatorDefault, service)?.takeRetainedValue()
                let location = IORegistryEntrySearchCFProperty(service, kIOServicePlane, "Location" as CFString, kCFAllocatorDefault, IOOptionBits(kIORegistryIterateRecursively)) as! String?
                if let avService = avService, location == "External" {
                    self.avService = avService
                    return
                }
            }
        }
        return nil
    }

    struct Packet {
        var addr: UInt8
        var data: [UInt8]

        func length(offset: Int) -> Int {
            return Int(data[offset]) & ~0x80
        }

        init(addr: UInt8, data: [UInt8], addChecksum: Bool = false) {
            self.addr = addr
            self.data = [UInt8(data.count) | 0x80] + data
            if addChecksum { self.addChecksum() }
        }

        mutating func addChecksum() {
            var checksum = 0x6e ^ self.addr
            for i: Int in 0..<data.count { checksum ^= data[i] }
            data.append(checksum)
        }
    }

    struct IOError: Error, CustomStringConvertible {
        let message: String
        let rawValue: IOReturn
        var description: String {
            let errStr = String(cString: mach_error_string(self.rawValue))
            return "IOError: \(self.message), \(errStr) (\(self.rawValue))"
        }
    }

    func i2cRead(addr: UInt8, size: Int, waitMs: Int = 50) async throws -> Packet {
        var packet = Packet(addr: addr, data: [UInt8](repeating: 0, count: size))
        try await Task.sleep(nanoseconds: UInt64(waitMs) * 1000 * 1000)
        let err = IOAVServiceReadI2C(self.avService, 0x37, UInt32(addr), &packet.data, UInt32(packet.data.count))
        if err != 0 { throw IOError(message: "I2C Read Failed", rawValue: err) }
        return packet
    }
    func i2cWrite(packet: Packet, waitMs: Int = 50, retry: Int = 2) async throws {
        var err: IOReturn = 0
        for _ in 0..<retry {
            try await Task.sleep(nanoseconds: UInt64(waitMs) * 1000 * 1000)
            err = packet.data.withUnsafeBytes { ptr in
                IOAVServiceWriteI2C(self.avService, 0x37, UInt32(packet.addr), ptr.baseAddress, UInt32(ptr.count))
            }
            if err == 0 { return }
        }
        if err != 0 { throw IOError(message: "I2C Write Failed", rawValue: err) }
    }

    /*
     * DDC Capability
     */
    func getRawCapability() async throws -> String {
        var buffer: [UInt8] = [];
        while buffer.count < 512 {
            try await i2cWrite(packet: Packet(addr: 0x51, data: [0xf3, UInt8(buffer.count >> 8), UInt8(buffer.count & 0xff)], addChecksum: true))
            let packet = try await i2cRead(addr: 0x51, size: 38);
            let length = packet.length(offset: 1) - 3
            if length == 0 { break }
            buffer += packet.data[5..<(5 + length)]
        }
        return String(decoding: buffer, as: UTF8.self)
    }

    /*
     * MARK: Virtual Control Panel (VCP)
     */
    @StaticMemberIterable
    struct VCPAttribute: Copyable, Equatable {
        let name: String
        let id: UInt8
        let addr: uint8
        init(name: String, id: UInt8, addr: UInt8 = 0x51) {
            self.name = name
            self.id = id
            self.addr = addr
        }

        static let volume = VCPAttribute(name: "volume", id: 0x62)
        static let input = VCPAttribute(name: "input", id: 0x60)

        static func from(id: UInt8, addr: UInt8) -> VCPAttribute {
            for attr in allStaticMembers {
                if attr.id == id && attr.addr == addr { return attr }
            }
            return VCPAttribute(name: "unknown", id: id, addr: addr)
        }
        static func find(string: String) -> VCPAttribute? {
            for attr in allStaticMembers {
                if attr.name == string { return attr }
            }
            return nil
        }
    }
    enum VCPValueType: UInt8 {
        case continuous = 0x00
        case table = 0x01
        case momentary = 0x02
        case unknown = 0xff
    }
    enum VCPError: Error, CustomStringConvertible {
        case unsupportedVcpCode
        case unknownFeatureReply(rawValue: UInt8)

        static func fromVCPFeatureReplyResultCode(_ rawValue: UInt8) -> VCPError? {
            switch rawValue {
            case 0x00: return nil
            case 0x01: return .unsupportedVcpCode
            default: return .unknownFeatureReply(rawValue: rawValue)
            }
        }
        var description: String {
            switch self {
            case .unsupportedVcpCode: return "VCPError: Unsupported VCP Code"
            case .unknownFeatureReply(rawValue: let rawValue): return "VCPError: Unknown Error (\(rawValue)) for VCP Feature Reply"
            }
        }
    }
    struct VCPValue {
        let attribute: VCPAttribute
        let type: VCPValueType
        let maxHighByte: UInt8
        let maxLowByte: UInt8
        let currentHighByte: UInt8
        let currentLowByte: UInt8

        var maxU16: UInt16 { return (UInt16(maxHighByte) << 8) | UInt16(maxLowByte) }
        var currentU16: UInt16 { return (UInt16(maxHighByte) << 8) | UInt16(maxLowByte) }

        init(attribute: VCPAttribute, current: UInt16) {
            self.attribute = attribute
            self.type = .unknown
            self.maxHighByte = 0
            self.maxLowByte = 0
            self.currentHighByte = UInt8(current >> 8)
            self.currentLowByte = UInt8(current & 0xff)
        }
        init(packet: Packet) throws {
            if let err = VCPError.fromVCPFeatureReplyResultCode(packet.data[3]) { throw err }
            self.attribute = VCPAttribute.from(id: packet.data[4], addr: packet.addr)
            self.type = VCPValueType(rawValue: packet.data[5]) ?? .unknown
            self.maxHighByte = packet.data[6]
            self.maxLowByte = packet.data[7]
            self.currentHighByte = packet.data[8]
            self.currentLowByte = packet.data[9]
        }
    }

    func getVcpFeature(attribute: VCPAttribute) async throws -> VCPValue {
        try await i2cWrite(packet: Packet(addr: attribute.addr, data: [0x01, attribute.id], addChecksum: true))
        let readPacket = try await i2cRead(addr: attribute.addr, size: 12)
        return try VCPValue(packet: readPacket)
    }
    func setVcpFeature(value: VCPValue) async throws {
        try await i2cWrite(packet: Packet(addr: value.attribute.addr, data: [0x03, value.attribute.id, value.currentHighByte, value.currentLowByte], addChecksum: true))
    }

    struct InputSource: Equatable {
        let rawValue: UInt8
        static let displayport: DisplayDataChannel.InputSource = InputSource(rawValue: 0x0f)
        static let hdmi: DisplayDataChannel.InputSource = InputSource(rawValue: 0x11)
        static let usbc: DisplayDataChannel.InputSource = InputSource(rawValue: 0x1b)

        var name: String? {
            switch rawValue {
            case InputSource.displayport.rawValue: "DisplayPort"
            case InputSource.hdmi.rawValue: "HDMI"
            case InputSource.usbc.rawValue: "USB-C"
            default: nil
            }
        }

        static func from(_ str: String?) -> InputSource? {
            switch str {
            case "DisplayPort": .displayport
            case "HDMI": .hdmi
            case "USB-C": .usbc
            default: nil
            }
        }
    }
    var inputSource: InputSource {
        get async throws {
            InputSource(rawValue: (try await getVcpFeature(attribute: .input)).currentLowByte)
        }
    }
    func setInputSource(inputSource: InputSource) async throws -> Bool {
        if try await self.inputSource == inputSource { return false }
        try await setVcpFeature(value: VCPValue(attribute: .input, current: UInt16(inputSource.rawValue)))
        return true
    }
}
