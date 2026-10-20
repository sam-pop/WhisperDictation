import CoreAudio
import AVFoundation

struct AudioInputDevice: Identifiable, Hashable {
    let id: AudioDeviceID
    let uid: String
    let name: String
}

final class AudioDeviceManager: ObservableObject, @unchecked Sendable {
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

    /// Set the selected device on a specific AVAudioEngine's input node (per-engine, not system-wide)
    /// ALWAYS sets an explicit device, resolving "System Default" (or an unplugged
    /// selection) to the current default input. Left unset, AVAudioEngine starts
    /// input and output as one IO unit, so a stalled default output (a sleeping
    /// DisplayPort monitor) hung engine.start() ~10 s and failed it; the same mic
    /// set explicitly started in ~0.25 s.
    func applySelectedDevice(to engine: AVAudioEngine) {
        guard var deviceID = Self.resolveInputDevice(
            selectedUID: AppSettings.shared.selectedAudioDeviceUID,
            devices: inputDevices,
            systemDefault: Self.systemDefaultInputDevice()
        ) else { return }

        let inputNode = engine.inputNode
        guard let audioUnit = inputNode.audioUnit else {
            fputs("[AudioDeviceManager] AudioUnit not available yet\n", stderr)
            return
        }

        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &deviceID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        if status != noErr {
            fputs("[AudioDeviceManager] Failed to set input device \(deviceID): \(status)\n", stderr)
        }
    }

    /// The selected device if it's still present, otherwise the system default.
    static func resolveInputDevice(selectedUID: String?, devices: [AudioInputDevice], systemDefault: AudioDeviceID?) -> AudioDeviceID? {
        if let selectedUID, let device = devices.first(where: { $0.uid == selectedUID }) {
            return device.id
        }
        return systemDefault
    }

    private static func systemDefaultInputDevice() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID)
        return status == noErr && deviceID != kAudioObjectUnknown ? deviceID : nil
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

        // Core Audio returns these CFStrings at +1: receive them unmanaged and take
        // ownership, or each call leaks one.
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &value) == noErr,
              let value else {
            return nil
        }
        return value.takeRetainedValue() as String
    }
}
