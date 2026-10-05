import Testing

@testable import SuttoDomain

/// The checkbox and hint derived from each OS login item status: registered
/// states (including one awaiting approval) show the checkbox on, and only
/// the approval case explains itself with a hint.
@Suite struct LaunchAtLoginStatusTests {
    @Test(arguments: [
        (LaunchAtLoginStatus.enabled, true, false),
        (.notRegistered, false, false),
        (.requiresApproval, true, true),
        (.notFound, false, false),
    ])
    func mapsEachStatusToCheckboxAndApproval(
        status: LaunchAtLoginStatus, isEnabled: Bool, needsApproval: Bool
    ) {
        #expect(status.isEnabled == isEnabled)
        #expect(status.needsApproval == needsApproval)
    }

    @Test func onlyTheApprovalCaseHasAHint() {
        #expect(LaunchAtLoginStatus.requiresApproval.hint?.isEmpty == false)
        #expect(LaunchAtLoginStatus.enabled.hint == nil)
        #expect(LaunchAtLoginStatus.notRegistered.hint == nil)
        #expect(LaunchAtLoginStatus.notFound.hint == nil)
    }

    @Test func approvalHintPointsAtLoginItemsSettings() {
        let hint = LaunchAtLoginStatus.requiresApproval.hint ?? ""
        #expect(hint.contains("Login Items"))
    }
}
