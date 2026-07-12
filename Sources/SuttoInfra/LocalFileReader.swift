import Foundation
import SuttoOperations

/// ``SuttoOperations/FileReading`` over the local filesystem. Trivial, but
/// it keeps file I/O in the infra layer where the architecture puts it, and
/// gives tests a seam to fail reads deterministically.
public struct LocalFileReader: FileReading {
    public init() {}

    public func read(from url: URL) throws -> Data {
        try Data(contentsOf: url)
    }
}
