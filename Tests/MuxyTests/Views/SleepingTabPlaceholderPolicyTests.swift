import Testing

@testable import Muxy

@Suite("SleepingTabPlaceholderPolicy")
struct SleepingTabPlaceholderPolicyTests {
    @Test("presents when a visible local pane is offline")
    func presentsWhenVisibleOfflineLocal() {
        #expect(SleepingTabPlaceholderPolicy.shouldPresent(
            isVisible: true,
            isOffline: true,
            isAttachedByRemote: false
        ))
    }

    @Test("hides while the pane is not visible")
    func hidesWhenNotVisible() {
        #expect(!SleepingTabPlaceholderPolicy.shouldPresent(
            isVisible: false,
            isOffline: true,
            isAttachedByRemote: false
        ))
    }

    @Test("hides while the pane is online")
    func hidesWhenOnline() {
        #expect(!SleepingTabPlaceholderPolicy.shouldPresent(
            isVisible: true,
            isOffline: false,
            isAttachedByRemote: false
        ))
    }

    @Test("hides while a remote device is attached")
    func hidesWhenAttachedByRemote() {
        #expect(!SleepingTabPlaceholderPolicy.shouldPresent(
            isVisible: true,
            isOffline: true,
            isAttachedByRemote: true
        ))
    }
}
