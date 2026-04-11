import CoreAudio
import AVFoundation

struct AudioInputDevice: Identifiable, Hashable {
    let id: AudioDeviceID
    let uid: String
    let name: String
}

final class AudioDeviceManager: ObservableObject {
    static let shared = AudioDeviceManager()

    @Published var inputDevices: [AudioInputDevice] = []

    init() {
        refreshDevices()
    }

    func refreshDevices() {
        inputDevices = Self.listInputDevices()
    }

    var selectedDevice: AudioInputDevice? {
        guard let uid = AppSettings.shared.selectedAudioDeviceUID else { return nil }
        return inputDevices.first { $0.uid == uid }
    }

    var selectedOrDefault: AudioInputDevice? {
        selectedDevice ?? inputDevices.first
    }

    /// Set the selected device as the AVAudioSession input (via CoreAudio)
    func applySelectedDevice(to engine: AVAudioEngine) {
        guard let uid = AppSettings.shared.selectedAudioDeviceUID else { return }
        guard let device = inputDevices.first(where: { $0.uid == uid }) else { return }

        var deviceID = device.id
        let size = UInt32(MemoryLayout<AudioDeviceID>.size)

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        // Set as default input
        AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0, nil,
            size,
            &deviceID
        )
    }

    // MARK: - List Devices

    private static func listInputDevices() -> [AudioInputDevice] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else {
            return []
        }

        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceIDs) == noErr else {
            return []
        }

        return deviceIDs.compactMap { deviceID -> AudioInputDevice? in
            // Check if device has input channels
            var streamAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreamConfiguration,
                mScope: kAudioDevicePropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain
            )

            var streamSize: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(deviceID, &streamAddress, 0, nil, &streamSize) == noErr,
                  streamSize > 0 else { return nil }

            let bufferListPtr = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: Int(streamSize))
            defer { bufferListPtr.deallocate() }

            guard AudioObjectGetPropertyData(deviceID, &streamAddress, 0, nil, &streamSize, bufferListPtr) == noErr else {
                return nil
            }

            let bufferList = UnsafeMutableAudioBufferListPointer(bufferListPtr)
            let inputChannels = bufferList.reduce(0) { $0 + Int($1.mNumberChannels) }
            guard inputChannels > 0 else { return nil }

            // Get device name
            let name = getDeviceString(deviceID, selector: kAudioDevicePropertyDeviceNameCFString) ?? "Unknown"
            let uid = getDeviceString(deviceID, selector: kAudioDevicePropertyDeviceUID) ?? ""

            return AudioInputDevice(id: deviceID, uid: uid, name: name)
        }
    }

    private static func getDeviceString(_ deviceID: AudioDeviceID, selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var value: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &value) == noErr else {
            return nil
        }
        return value as String
    }
}
