import Foundation
import IOKit.pwr_mgt

final class IOKitPowerAssertionService: PowerAssertionService {
    private var assertionID: IOPMAssertionID = 0
    private var hasAssertion = false

    func acquireNoIdleSleepAssertion() {
        guard !hasAssertion else { return }
        let reason = "\(AppConstants.appName) active recording" as CFString
        let status = IOPMAssertionCreateWithName(
            kIOPMAssertionTypeNoIdleSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason,
            &assertionID
        )
        hasAssertion = status == kIOReturnSuccess
    }

    func releaseAssertion() {
        guard hasAssertion else { return }
        _ = IOPMAssertionRelease(assertionID)
        hasAssertion = false
    }

    deinit {
        releaseAssertion()
    }
}

