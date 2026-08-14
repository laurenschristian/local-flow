import Foundation
import CoreAudio

struct AudioInputDevice: Equatable {
    let id: AudioDeviceID
    let uid: String
    let name: String
}

enum AudioDeviceManager {
    static func inputDevices() -> [AudioInputDevice] {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size
        ) == noErr else { return [] }

        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids
        ) == noErr else { return [] }

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
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id
        ) == noErr, id != 0,
              let uid = stringProperty(id, selector: kAudioDevicePropertyDeviceUID),
              let name = stringProperty(id, selector: kAudioObjectPropertyName) else {
            return nil
        }
        return AudioInputDevice(id: id, uid: uid, name: name)
    }

    /// Display name of the device recordings will actually use.
    static func activeInputDeviceName() -> String {
        if let uid = Settings.shared.selectedInputDeviceUID {
            if let name = deviceName(forUID: uid) { return name }
            return "Missing device (using default)"
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
