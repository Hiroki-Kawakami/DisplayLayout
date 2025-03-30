/*
 * Copyright 2025 Hiroki Kawakami
 */

import Foundation

final class SidecarDisplayManager: Sendable {

    static let shared = SidecarDisplayManager()
    private init() {
        // load SidecarCore Framework
        guard let _ = dlopen("/System/Library/PrivateFrameworks/SidecarCore.framework/SidecarCore", RTLD_LAZY) else {
            fatalError("SidecarCore framework failed to open")
        }
    }

    private var manager: NSObject {
        get {
            let sidecarDisplayManagerClass = NSClassFromString("SidecarDisplayManager") as! NSObject.Type
            return sidecarDisplayManagerClass.perform(Selector(("sharedManager"))).takeUnretainedValue() as! NSObject
        }
    }

    func devices() -> [SidecarDisplay] {
        let devices = manager.perform(Selector(("devices"))).takeUnretainedValue() as! [NSObject];
        return devices.map { d in SidecarDisplay(rawObject: d) }
    }

    func connectedDevices() -> [SidecarDisplay] {
        let devices = manager.perform(Selector(("connectedDevices"))).takeUnretainedValue() as! [NSObject];
        return devices.map { d in SidecarDisplay(rawObject: d) }
    }

    func connect(device: SidecarDisplay) async {
        await withCheckedContinuation { continuation in
            let closure: @convention(block) (_ e: NSError?) -> Void = { error in
                print("Connected!");
                continuation.resume()
            }
            manager.perform(Selector(("connectToDevice:completion:")), with: device.rawObject, with: closure)
        }
    }

    func disconnect(device: SidecarDisplay) async {
        await withCheckedContinuation { continuation in
            let closure: @convention(block) (_ e: NSError?) -> Void = { error in
                print("Disconnected!");
                continuation.resume()
            }
            manager.perform(Selector(("disconnectFromDevice:completion:")), with: device.rawObject, with: closure)
        }
    }

    func isConnected(device: SidecarDisplay) -> Bool {
        for connectedDevice in connectedDevices() {
            if connectedDevice.identifier == device.identifier {
                return true
            }
        }
        return false
    }
}

struct SidecarDisplay: Equatable {
    init(rawObject: NSObject) {
        self.rawObject = rawObject
        self.identifier = rawObject.perform(Selector(("identifier"))).takeUnretainedValue() as! UUID
        self.name = rawObject.perform(Selector(("name"))).takeUnretainedValue() as! String
        self.model = rawObject.perform(Selector(("model"))).takeUnretainedValue() as! String
    }

    let rawObject: NSObject
    let identifier: UUID
    let name: String
    let model: String

    static func == (lhs: SidecarDisplay, rhs: SidecarDisplay) -> Bool {
        return lhs.identifier == rhs.identifier
    }
}
