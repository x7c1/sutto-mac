/// How this device identifies itself to the backend when activating a
/// license: a stable id and a human-readable label.
///
/// The port of the GNOME `DeviceInfoProvider`'s two outputs
/// (`getDeviceId` / `getDeviceLabel`). How the id is derived (an
/// `IOPlatformUUID` versus a generated-and-persisted UUID) and what the label
/// says are deliberately not decided here — they depend on the backend's
/// activation contract, which is a later slice (design "未確定" notes). This
/// type is only the shape the API client and gate agree on; the concrete
/// values are injected from the composition root.
public struct DeviceIdentity: Equatable, Sendable {
    /// The stable per-device identifier the backend counts against the
    /// device limit.
    public let id: String

    /// A human-readable name for the device, shown in the account's device
    /// list (e.g. the computer's local name).
    public let label: String

    public init(id: String, label: String) {
        self.id = id
        self.label = label
    }
}
