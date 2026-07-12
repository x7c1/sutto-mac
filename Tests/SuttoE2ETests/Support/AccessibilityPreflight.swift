import ApplicationServices

/// Checks the TCC precondition of the whole suite up front, so a machine
/// without the grant fails immediately with instructions instead of timing
/// out somewhere in the middle of a scenario.
enum AccessibilityPreflight {
    static func requireTrusted() throws {
        guard !AXIsProcessTrusted() else { return }
        throw E2EFailure(
            """
            The e2e suite needs the Accessibility permission, and this test \
            runner process does not have it. Grant it to the application you \
            run `make e2e` from — your terminal app, or the editor hosting \
            the integrated terminal — under System Settings › Privacy & \
            Security › Accessibility, then rerun. One grant is enough: the \
            suite spawns Sutto with fork/exec, so the terminal stays the TCC \
            responsible process for every process the suite touches. See \
            "End-to-end tests" in docs/guides/testing.md.
            """)
    }
}
