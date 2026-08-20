import Foundation
import CoreAudio

struct AudioInputDevice: Equatable {
    let id: AudioDeviceID
    let uid: String
    let name: String
}

enum AudioDeviceManager {
    /// Generic CoreAudio property read, shared with MediaPauseController.
    static func property<T>(
        _ id: AudioObjectID,
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> T? {
        var addr = AudioObjectPropertyAddress(
            mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<T>.size)
        let value = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { value.deallocate() }
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, value) == noErr else { return nil }
        return value.pointee
    }

    /// Generic CoreAudio array-property read (device lists, process lists).
    static func propertyList<T>(
        _ id: AudioObjectID,
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> [T] {
        var addr = AudioObjectPropertyAddress(
            mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr, size > 0 else {
            return []
        }
        let buffer = UnsafeMutableBufferPointer<T>.allocate(
            capacity: Int(size) / MemoryLayout<T>.stride
        )
        defer { buffer.deallocate() }
        guard let base = buffer.baseAddress,
              AudioObjectGetPropertyData(id, &addr, 0, nil, &size, base) == noErr else { return [] }
        return Array(UnsafeBufferPointer(start: base, count: Int(size) / MemoryLayout<T>.stride))
    }

    static func inputDevices() -> [AudioInputDevice] {
        let ids: [AudioDeviceID] = propertyList(
            AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDevices
        )
        return ids.compactMap { id in
            guard hasInputChannels(id),
                  let uid = stringProperty(id, selector: kAudioDevicePropertyDeviceUID),
                  let name = stringProperty(id, selector: kAudioObjectPropertyName) else {
                return nil
            }
            return AudioInputDevice(id: id, uid: uid, name: name)
        }
    }

    static func deviceID(forUID uid: String) -> AudioDeviceID? {
        inputDevices().first { $0.uid == uid }?.id
    }

    static func deviceName(forUID uid: String) -> String? {
        inputDevices().first { $0.uid == uid }?.name
    }

    static func defaultInputDevice() -> AudioInputDevice? {
        guard let id: AudioDeviceID = property(
            AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultInputDevice
        ), id != 0,
              let uid = stringProperty(id, selector: kAudioDevicePropertyDeviceUID),
              let name = stringProperty(id, selector: kAudioObjectPropertyName) else {
            return nil
        }
        return AudioInputDevice(id: id, uid: uid, name: name)
    }

    /// Device the recorder should open. Defaults to the built-in mic when the
    /// system default is a Bluetooth headset: opening that mic forces the
    /// headset into call mode, which wrecks whatever is playing through it.
    static func recordingDeviceID() -> AudioDeviceID? {
        if let uid = Settings.shared.selectedInputDeviceUID { return deviceID(forUID: uid) }
        guard Settings.shared.avoidBluetoothMic,
              let current = defaultInputDevice(), isBluetooth(current.id),
              let builtIn = builtInInputDevice() else { return nil }
        return builtIn.id
    }

    static func builtInInputDevice() -> AudioInputDevice? {
        inputDevices().first { transportType($0.id) == kAudioDeviceTransportTypeBuiltIn }
    }

    static func isBluetooth(_ id: AudioDeviceID) -> Bool {
        let type = transportType(id)
        return type == kAudioDeviceTransportTypeBluetooth || type == kAudioDeviceTransportTypeBluetoothLE
    }

    static func transportType(_ id: AudioDeviceID) -> UInt32? {
        property(id, kAudioDevicePropertyTransportType)
    }

    static func defaultOutputSampleRate() -> Float64? {
        guard let device: AudioDeviceID = property(
            AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice
        ), device != 0 else { return nil }
        return property(device, kAudioDevicePropertyNominalSampleRate)
    }

    /// Display name of the device recordings will actually use.
    static func activeInputDeviceName() -> String {
        if let uid = Settings.shared.selectedInputDeviceUID {
            if let name = deviceName(forUID: uid) { return name }
            return "Missing device (using default)"
        }
        if let id = recordingDeviceID(), let device = inputDevices().first(where: { $0.id == id }) {
            return "\(device.name) (Bluetooth mic avoided)"
        }
        return defaultInputDevice()?.name ?? "System default"
    }

    private static func hasInputChannels(_ id: AudioDeviceID) -> Bool {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr, size > 0 else {
            return false
        }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: 16)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, raw) == noErr else {
            return false
        }
        let bufferList = UnsafeMutableAudioBufferListPointer(
            raw.bindMemory(to: AudioBufferList.self, capacity: 1)
        )
        return bufferList.contains { $0.mNumberChannels > 0 }
    }

    private static func stringProperty(
        _ id: AudioDeviceID, selector: AudioObjectPropertySelector
    ) -> String? {
        var addr = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<CFString?>.size)
        var value: CFString?
        let status = withUnsafeMutablePointer(to: &value) { ptr in
            AudioObjectGetPropertyData(id, &addr, 0, nil, &size, ptr)
        }
        guard status == noErr else { return nil }
        return value as String?
    }
}
