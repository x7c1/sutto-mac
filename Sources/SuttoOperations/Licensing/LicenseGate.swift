import Foundation
import SuttoDomain
import os

/// The operations half of licensing: it owns the ``LicenseState`` aggregate,
/// answers whether the gated features are unlocked, and drives the three
/// backend-touching transitions (activate, launch validate, trial day count).
///
/// This folds the GNOME `LicenseStateHandler` + `LicenseOperations` into one
/// use case, wrapping the pure ``SuttoDomain/LicenseGatePolicy`` and
/// ``SuttoDomain/ValidationOutcome`` mapping with the things the domain
/// deliberately does not own: persistence (``LicenseRepository``), the network
/// (``LicenseApiClient``), and clocks (`now` / `today`) — injected the way
/// ``LayoutHistoryUseCase`` injects its `now`.
///
/// The state is *lazily loaded* on first use and then held in memory as the
/// source of truth for the run, mirroring ``LayoutHistoryUseCase``: every
/// transition folds into the in-memory aggregate and writes it straight back.
///
/// The fail-open policy lives entirely in the pieces this composes, so it
/// needs no live network signal here: ``isOpen()`` reads only the cached
/// verdict and the trial, and ``validateOnLaunch()`` downgrades only on an
/// authoritative NO. A backend that is unreachable — or has vanished
/// (404 / 410) — never closes the gate.
@MainActor
public final class LicenseGate {
    private let repository: any LicenseRepository
    private let apiClient: any LicenseApiClient
    private let device: DeviceIdentity
    private let now: () -> Date
    private let today: () -> String
    private let logger = Logger(subsystem: "io.github.x7c1.SuttoMac", category: "licensing")

    /// The loaded aggregate, or `nil` until the first access forces a lazy
    /// load. Held after that so every transition mutates one in-memory value.
    private var cachedState: LicenseState?

    /// - Parameters:
    ///   - repository: persistence for the aggregate;
    ///     ``LicenseRepository/load()`` degrades to a fresh trial, so a first
    ///     run or a corrupt file simply starts the trial over rather than
    ///     locking the user out (design decision #8).
    ///   - apiClient: the backend; returns already-classified outcomes so this
    ///     use case never sees an HTTP status code.
    ///   - device: how this device identifies itself when activating.
    ///   - now: injected so tests control the `lastValidated` timestamp,
    ///     matching ``LayoutHistoryUseCase``.
    ///   - today: injected so tests control the trial's day-of-use string,
    ///     matching the GNOME `DateProvider.today()`.
    public init(
        repository: any LicenseRepository,
        apiClient: any LicenseApiClient,
        device: DeviceIdentity,
        now: @escaping () -> Date = Date.init,
        today: @escaping () -> String = licenseGateDefaultToday
    ) {
        self.repository = repository
        self.apiClient = apiClient
        self.device = device
        self.now = now
        self.today = today
    }

    /// Whether the gated features (panel display) are unlocked right now.
    ///
    /// Reads only the cached status and the trial through the pure
    /// ``SuttoDomain/LicenseGatePolicy`` — never the network — which is what
    /// makes "the API can disappear and a valid device keeps working" hold.
    public func isOpen() -> Bool {
        loadedState().isGateOpen
    }

    /// The current licensing aggregate (loading it on first use). Read-only;
    /// callers use it to render status text.
    public func state() -> LicenseState {
        loadedState()
    }

    /// Activates `key` for this device and, on success, stores the returned
    /// record as `valid`.
    ///
    /// The port of the GNOME `LicenseOperations.activate`, but only its
    /// success path changes state: an authoritative rejection is reported to
    /// the caller through the returned ``ActivationOutcome`` and never touches
    /// the stored status, and a no-answer is retryable and changes nothing.
    @discardableResult
    public func activate(key: String) async -> ActivationOutcome {
        let outcome = await apiClient.activate(key: key, device: device)

        switch outcome {
        case .activated(let record):
            var state = loadedState()
            state.record = record
            state.updateStatus(.valid)
            persist(state)
        case .rejected:
            // A failed activation attempt reports a bad/ineligible key to the
            // UI via the returned outcome; it must NOT downgrade an existing
            // entitlement. A trial in progress or a prior valid license stays
            // intact — only validateOnLaunch (guarded to a currently-valid
            // device) downgrades. (Diverges from GNOME handleActivationError's
            // setStatus('invalid'), a latent trial-destruction bug; consistent
            // with design decision #8.)
            logger.info("activation rejected; leaving existing status unchanged")
        case .noResponse:
            logger.info("activation had no authoritative answer; leaving status unchanged")
        }

        return outcome
    }

    /// Validates a `valid` license once at launch, downgrading only on an
    /// authoritative NO.
    ///
    /// The port of the GNOME `initialize()` + `handleValidationError`: it runs
    /// only when the cached status is `valid` and a record exists, and it maps
    /// the outcome through ``SuttoDomain/ValidationOutcome/resolvedStatus(from:)``.
    /// A `.noResponse` (offline / timeout / 5xx / 404 / 410) leaves the status
    /// untouched — the heart of fail-open — so nothing is written in that case.
    /// There is no periodic re-validation (design decision #9).
    public func validateOnLaunch() async {
        var state = loadedState()
        guard state.status == .valid, let record = state.record else { return }

        let outcome = await apiClient.validate(
            key: record.licenseKey, activationId: record.activationId)

        switch outcome {
        case .valid(let validUntil):
            state.record?.validUntil = validUntil
            state.record?.lastValidated = now()
            state.updateStatus(.valid)
            persist(state)
        case .rejected(let rejection):
            state.updateStatus(rejection.resultingStatus)
            persist(state)
        case .noResponse:
            // Fail-open: an unreachable or vanished backend never downgrades a
            // valid device, so the cached status stands and nothing is saved.
            logger.info("launch validate had no authoritative answer; keeping cached status")
        }
    }

    /// Counts today as a trial day of use when in trial mode, closing the gate
    /// once the 30-day trial is spent.
    ///
    /// The port of the GNOME `recordTrialUsage`: it runs only when the status
    /// is `trial`, counts at most one day per calendar day
    /// (``SuttoDomain/TrialState/canRecordUsage(today:)``), and flips the
    /// status to `expired` the moment the trial is used up. The GNOME
    /// `backend_unreachable` guard is intentionally not ported — the trial is
    /// fully local (design decision #10).
    public func recordTrialUsageOnLaunch() {
        var state = loadedState()
        guard state.status == .trial else { return }

        let day = today()
        guard state.trial.canRecordUsage(today: day) else { return }

        state.trial = state.trial.recordUsage(today: day)
        if state.trial.isExpired {
            state.updateStatus(.expired)
        }
        persist(state)
    }

    /// Clears the activated license from *local* storage, returning the device
    /// to its trial (or to `expired` if the trial is already spent).
    ///
    /// This is the local half of "Deactivate": it drops the stored
    /// ``LicenseState/record`` and recomputes the status from the trial —
    /// `trial` while days remain, `expired` once the 30 days are used up — then
    /// persists. It never fabricates a worse verdict than the trial supports
    /// (design decision #8): a user who clears a license mid-trial keeps the
    /// days they had left.
    ///
    /// TODO(sub-PR B1): also release this device's activation on the backend so
    /// the seat is freed toward the device limit. Until the real API is wired
    /// that call has no endpoint, so this stays a local-only clear.
    public func clearLicense() {
        var state = loadedState()
        state.record = nil
        state.updateStatus(state.trial.isExpired ? .expired : .trial)
        persist(state)
    }

    /// The in-memory aggregate, loading it from the repository on first use.
    private func loadedState() -> LicenseState {
        if let cachedState {
            return cachedState
        }
        let loaded = repository.load()
        cachedState = loaded
        return loaded
    }

    /// Caches `state` and writes it back. A save failure is non-fatal: the
    /// in-memory aggregate stays correct for this run and the next successful
    /// save catches up, matching ``LayoutHistoryUseCase``.
    private func persist(_ state: LicenseState) {
        cachedState = state
        do {
            try repository.save(state)
        } catch {
            logger.error(
                "failed to save license state: \(String(describing: error), privacy: .public)")
        }
    }
}

/// The default `today` string: the current local calendar day as `yyyy-MM-dd`.
///
/// Only equality of these strings matters (has today already been counted?),
/// so the exact format is an internal detail; a POSIX-fixed component read
/// keeps it stable and locale-independent. Tests inject their own `today`
/// instead.
public func licenseGateDefaultToday() -> String {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .current
    let parts = calendar.dateComponents([.year, .month, .day], from: Date())
    return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
}
