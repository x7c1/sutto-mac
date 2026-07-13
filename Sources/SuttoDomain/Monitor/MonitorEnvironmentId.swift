/// The identity key of a monitor environment: a hash of every monitor's
/// geometry, so that the same physical setup (same displays, same
/// resolutions, same relative positions) always maps to the same key and
/// any change — plugging a display in or out, rearranging, changing a
/// resolution — maps to a different one.
///
/// This is an exact port of `generateEnvironmentId` in the GNOME
/// `operations/monitor/monitor-environment-operations.ts`:
///
/// 1. Sort the monitors by index, so the key does not depend on the
///    enumeration order the monitors arrived in.
/// 2. Join each monitor's `x,y,width,height` with `|` into one string.
/// 3. Hash it with DJB2-xor (`hash = (hash * 33) ^ charCode`, seeded with
///    5381) over the UTF-16 code units — the JavaScript `charCodeAt`
///    semantics — and render the unsigned 32-bit result as 8 hex digits.
///
/// Only `geometry` participates, exactly like the GNOME version: work
/// areas shift with the Dock and menu bar without the physical setup
/// changing, and the primary flag is derivable from the arrangement.
public enum MonitorEnvironmentId {
    /// The identity key for `monitors`.
    public static func generate(for monitors: [Monitor]) -> String {
        let geometryString = monitors
            .sorted { $0.index < $1.index }
            .map { monitor in
                let g = monitor.geometry
                return "\(format(g.x)),\(format(g.y)),\(format(g.width)),\(format(g.height))"
            }
            .joined(separator: "|")

        // DJB2-xor with JavaScript number semantics: the multiply happens
        // exactly (a 32-bit value times 33 fits a 64-bit integer, as it
        // fits the float64 mantissa in JS), then the XOR truncates to a
        // signed 32-bit integer like the JS `^` operator.
        var hash: Int32 = 5381
        for unit in geometryString.utf16 {
            hash = Int32(truncatingIfNeeded: Int64(hash) * 33) ^ Int32(unit)
        }
        // `(hash >>> 0).toString(16).padStart(8, '0')` in the original.
        return String(format: "%08x", UInt32(bitPattern: hash))
    }

    /// Formats a coordinate the way JavaScript string interpolation
    /// renders a number: integral values without a decimal point. Screen
    /// geometry is integral in practice, so the hashed string matches the
    /// GNOME one character for character for equivalent geometry.
    private static func format(_ value: Double) -> String {
        if let integral = Int64(exactly: value.rounded()), value == value.rounded() {
            return String(integral)
        }
        return String(value)
    }
}
