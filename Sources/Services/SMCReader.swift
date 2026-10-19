import Foundation
import IOKit

/// Errors that can occur while talking to the System Management Controller.
enum SMCError: Error {
    case serviceNotFound
    case openFailed(kern_return_t)
    case callFailed(kern_return_t)
    case keyNotFound(String)
    case unsupportedType(String)
}

/// Minimal read-only client for the AppleSMC IOKit service.
/// All SMC key access lives here so failures are handled in one place.
struct SMCReader {
    private let connection: io_connect_t

    // Layout of the kernel's SMCKeyData_t struct (80 bytes), addressed by byte offset.
    private static let structSize = 80
    private static let offKey = 0, offDataSize = 28, offDataType = 32
    private static let offResult = 40, offCommand = 42, offBytes = 48
    private static let selectorHandleEvent: UInt32 = 2
    private static let cmdReadBytes: UInt8 = 5, cmdReadKeyInfo: UInt8 = 9

    /// Opens a connection to AppleSMC. Throws if the service is missing or cannot be opened.
    init() throws {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { throw SMCError.serviceNotFound }
        defer { IOObjectRelease(service) }
        var conn: io_connect_t = 0
        let kr = IOServiceOpen(service, mach_task_self_, 0, &conn)
        guard kr == kIOReturnSuccess else { throw SMCError.openFailed(kr) }
        connection = conn
    }

    /// Closes the underlying IOKit connection.
    func close() { IOServiceClose(connection) }

    /// Reads a numeric SMC key, decoding it according to the type string the SMC reports.
    func readNumber(_ key: String) throws -> Double {
        let code = Self.fourCC(key)
        var input = [UInt8](repeating: 0, count: Self.structSize)
        Self.put(code, into: &input, at: Self.offKey)
        input[Self.offCommand] = Self.cmdReadKeyInfo
        let info = try call(input)
        guard info[Self.offResult] == 0 else { throw SMCError.keyNotFound(key) }
        let size = Self.get(info, at: Self.offDataSize)
        let type = Self.string(from: Self.get(info, at: Self.offDataType))

        input[Self.offCommand] = Self.cmdReadBytes
        Self.put(size, into: &input, at: Self.offDataSize)
        let out = try call(input)
        guard out[Self.offResult] == 0 else { throw SMCError.keyNotFound(key) }
        let bytes = Array(out[Self.offBytes..<(Self.offBytes + Int(min(size, 32)))])
        return try Self.decode(bytes, type: type)
    }

    private func call(_ input: [UInt8]) throws -> [UInt8] {
        var output = [UInt8](repeating: 0, count: Self.structSize)
        var outSize = Self.structSize
        let kr = input.withUnsafeBytes { inPtr in
            output.withUnsafeMutableBytes { outPtr in
                IOConnectCallStructMethod(connection, Self.selectorHandleEvent,
                                          inPtr.baseAddress, Self.structSize,
                                          outPtr.baseAddress, &outSize)
            }
        }
        guard kr == kIOReturnSuccess else { throw SMCError.callFailed(kr) }
        return output
    }

    private static func decode(_ b: [UInt8], type: String) throws -> Double {
        switch type {
        case "flt " where b.count >= 4:
            let raw = UInt32(b[0]) | UInt32(b[1]) << 8 | UInt32(b[2]) << 16 | UInt32(b[3]) << 24
            return Double(Float(bitPattern: raw))
        case "fpe2" where b.count >= 2:
            return Double(UInt16(b[0]) << 8 | UInt16(b[1])) / 4.0
        case "ui8 " where b.count >= 1:
            return Double(b[0])
        case "ui16" where b.count >= 2:
            return Double(UInt16(b[0]) << 8 | UInt16(b[1]))
        case "ui32" where b.count >= 4:
            return Double(UInt32(b[0]) << 24 | UInt32(b[1]) << 16 | UInt32(b[2]) << 8 | UInt32(b[3]))
        default:
            throw SMCError.unsupportedType(type)
        }
    }

    private static func fourCC(_ s: String) -> UInt32 {
        s.utf8.prefix(4).reduce(0) { $0 << 8 | UInt32($1) }
    }

    private static func string(from code: UInt32) -> String {
        let chars = [24, 16, 8, 0].map { UInt8((code >> $0) & 0xFF) }
        return String(decoding: chars, as: UTF8.self)
    }

    private static func put(_ v: UInt32, into buf: inout [UInt8], at off: Int) {
        withUnsafeBytes(of: v.littleEndian) { for i in 0..<4 { buf[off + i] = $0[i] } }
    }

    private static func get(_ buf: [UInt8], at off: Int) -> UInt32 {
        (0..<4).reduce(UInt32(0)) { $0 | UInt32(buf[off + $1]) << (8 * UInt32($1)) }
    }
}
