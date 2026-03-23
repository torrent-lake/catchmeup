import CoreAudio
import Foundation

final class DefaultInputDeviceMonitor {
    private let queue = DispatchQueue(label: "alltimerecorded.default-input-monitor")
    private var started = false
    private var onChanged: (@Sendable () -> Void)?
    private var listenerBlock: AudioObjectPropertyListenerBlock?
    private var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultInputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    func start(onChanged: @escaping @Sendable () -> Void) {
        self.onChanged = onChanged
        guard !started else { return }
        started = true

        let callback = onChanged
        let block: AudioObjectPropertyListenerBlock = { _, _ in
            callback()
        }
        listenerBlock = block
        let objectID = AudioObjectID(kAudioObjectSystemObject)
        let status = AudioObjectAddPropertyListenerBlock(objectID, &address, queue, block)
        if status != noErr {
            started = false
            listenerBlock = nil
        }
    }

    func stop() {
        guard started else { return }
        guard let listenerBlock else { return }
        let objectID = AudioObjectID(kAudioObjectSystemObject)
        _ = AudioObjectRemovePropertyListenerBlock(objectID, &address, queue, listenerBlock)
        started = false
        self.listenerBlock = nil
    }

    static func currentDefaultInputDeviceID() -> UInt32 {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let objectID = AudioObjectID(kAudioObjectSystemObject)
        let status = AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, &deviceID)
        return status == noErr ? UInt32(deviceID) : 0
    }
}
