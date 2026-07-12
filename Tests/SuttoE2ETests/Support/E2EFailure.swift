/// A failure of the e2e harness itself (a precondition not met, a wait that
/// timed out, an AX call that errored). Thrown from test bodies so Swift
/// Testing records the message as the failure reason.
struct E2EFailure: Error, CustomStringConvertible {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var description: String { message }
}
