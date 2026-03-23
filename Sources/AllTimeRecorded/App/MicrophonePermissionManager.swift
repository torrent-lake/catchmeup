import AVFoundation
import Foundation

enum MicrophonePermissionManager {
    static func request(completion: @escaping @MainActor (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            Task { @MainActor in
                completion(true)
            }
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                Task { @MainActor in
                    completion(granted)
                }
            }
        case .denied, .restricted:
            Task { @MainActor in
                completion(false)
            }
        @unknown default:
            Task { @MainActor in
                completion(false)
            }
        }
    }
}
