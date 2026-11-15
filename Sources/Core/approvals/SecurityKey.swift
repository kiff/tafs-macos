import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// The USB security key's side of an approval that needs no Mac: what is asked of the key, its
/// PIN, its answers' failures, and the attestation object of a new credential. The app's
/// `FidoKey` asks the key through libfido2 with exactly these, and nothing else.

/// A CTAP2 option as libfido2 takes it: left out, false or true (`fido_opt_t`).
enum FidoOption: Equatable {
    case omit, no, yes
}

/// The key is always asked with its PIN, and the PIN is what verifies the person: so the `uv`
/// option is left out, as some CTAP2.0 keys refuse it alongside a PIN token. Core still refuses
/// authenticator data without the UV flag. Without a PIN, the key isn't asked at all
/// (`SecurityKeyFailure.pinMissing`).
enum SecurityKeyVerification {
    static let uvOption = FidoOption.omit
}

/// One assertion asked of the key: kiff.dev, the hash of the `clientDataJSON` this app built, and
/// the one credential this Mac approves with. The person must be present, and verified by the PIN.
struct SecurityKeyAssertionAsk: Equatable {
    let clientDataHash: Data
    let credentialID: Data
    /// User presence is asked for; `uv` is left out, as the PIN verifies.
    let userPresence = FidoOption.yes
    let userVerification = SecurityKeyVerification.uvOption

    /// Refuses a hash that isn't SHA-256's 32 bytes, and an empty or oversized credential id
    /// (CTAP2 takes at most 1023 bytes), before the key is asked.
    init(clientDataHash: Data, credentialID: Data) throws {
        guard clientDataHash.count == 32, !credentialID.isEmpty, credentialID.count <= 1023 else {
            throw PasskeyRefusal.unreadable
        }
        self.clientDataHash = clientDataHash
        self.credentialID = credentialID
    }
}

/// One new credential asked of the key, as Windows' `WindowsHello.CreateAsync`: kiff.dev ("KIFF"),
/// ES256 only, the person verified by the PIN, kept on the key's side as a credential id this Mac
/// holds (not a discoverable one).
struct SecurityKeyCredentialAsk: Equatable {
    /// The relying party's name, as Windows gives it.
    static let rpName = "KIFF"
    /// COSE's ES256, the only algorithm KIFF takes.
    static let es256: Int32 = -7

    let clientDataHash: Data
    let userID: Data
    let userName: String
    /// Not discoverable; `uv` is left out, as the PIN verifies.
    let residentKey = FidoOption.no
    let userVerification = SecurityKeyVerification.uvOption

    /// Refuses a hash that isn't 32 bytes, and a user id outside CTAP2's 1 to 64 bytes.
    init(clientDataHash: Data, userID: Data, userName: String) throws {
        guard clientDataHash.count == 32, (1...64).contains(userID.count) else { throw PasskeyRefusal.unreadable }
        self.clientDataHash = clientDataHash
        self.userID = userID
        self.userName = userName
    }
}

/// How long the key waits for its touch, as Windows' two minutes for Windows Hello.
enum SecurityKeyWait {
    static let milliseconds: Int32 = 120_000
}

/// Why the key gave no answer. The PIN sheet says each in its own words.
enum SecurityKeyFailure: Error, Equatable {
    /// No security key is plugged in.
    case noKey
    /// More than one is plugged in: the app asks none of them.
    case severalKeys
    /// A key that only speaks U2F: it has no PIN, so it can't verify the person.
    case notFIDO2
    /// No PIN was given: the key is asked only with its PIN, each time.
    case pinMissing
    /// A PIN shorter than 4 characters, which no key takes.
    case pinTooShort
    /// A PIN longer than 63 bytes, or with a NUL in it, which no key takes.
    case pinTooLong
    /// The PIN was already handed to the key once, and cleared.
    case pinUsed
    /// The key has no PIN set, so it can't verify the person.
    case pinNotSet
    /// The PIN was wrong; the key says how many tries are left, when it says.
    case wrongPIN(triesLeft: Int?)
    /// No PIN tries are left: the key is blocked until it's reset.
    case pinBlocked
    /// Three wrong PINs in a row: the key takes no more until it's unplugged and plugged in again.
    case pinPaused
    /// The key doesn't hold this Mac's credential: it's another key.
    case notThisKey
    /// The key wasn't touched in time.
    case timedOut
    /// The key refused, or the request was cancelled at the key.
    case denied
    /// The key was unplugged, or stopped answering.
    case removed
    /// Anything else, by libfido2's code.
    case failed(code: Int32)

    /// The failure for libfido2's code, or nil for `FIDO_OK`. A wrong PIN with no tries left is
    /// a blocked key.
    static func of(_ code: Int32, triesLeft: Int? = nil) -> SecurityKeyFailure? {
        switch code {
        case FidoCode.ok: return nil
        case FidoCode.pinInvalid:
            if let left = triesLeft, left <= 0 { return .pinBlocked }
            return .wrongPIN(triesLeft: triesLeft)
        case FidoCode.pinBlocked: return .pinBlocked
        case FidoCode.pinAuthBlocked: return .pinPaused
        case FidoCode.pinNotSet: return .pinNotSet
        case FidoCode.noCredentials, FidoCode.invalidCredential: return .notThisKey
        case FidoCode.actionTimeout, FidoCode.userActionTimeout: return .timedOut
        case FidoCode.operationDenied, FidoCode.keepaliveCancel: return .denied
        case FidoCode.tx, FidoCode.rx: return .removed
        default: return .failed(code: code)
        }
    }
}

/// libfido2's codes this app tells apart (`fido/err.h`, 1.17.0).
enum FidoCode {
    static let ok: Int32 = 0x00
    static let invalidCredential: Int32 = 0x22
    static let operationDenied: Int32 = 0x27
    static let keepaliveCancel: Int32 = 0x2d
    static let noCredentials: Int32 = 0x2e
    static let userActionTimeout: Int32 = 0x2f
    static let pinInvalid: Int32 = 0x31
    static let pinBlocked: Int32 = 0x32
    static let pinAuthBlocked: Int32 = 0x34
    static let pinNotSet: Int32 = 0x35
    static let actionTimeout: Int32 = 0x3a
    static let tx: Int32 = -1
    static let rx: Int32 = -2
    static let `internal`: Int32 = -9
}

/// The security key's PIN for one approval, in one buffer the app owns: made from the bytes typed,
/// which it clears, handed to the key once as a C string, then cleared and freed. It's never kept
/// past that, written anywhere, logged or sent to a server. A PIN that isn't handed over is
/// cleared when it's let go.
final class SecurityKeyPIN {
    /// CTAP2: at least 4 Unicode code points, at most 63 bytes of UTF-8.
    static let fewestCharacters = 4
    static let mostBytes = 63

    private var buffer: UnsafeMutablePointer<CChar>?
    private let size: Int

    /// The PIN from its UTF-8 bytes. The bytes given are cleared in place, whether the PIN is
    /// taken or refused.
    init(utf8 bytes: inout [UInt8]) throws {
        defer { bytes.withUnsafeMutableBytes { SecurityKeyPIN.clear($0.baseAddress, $0.count) } }
        guard bytes.count <= Self.mostBytes, !bytes.contains(0) else { throw SecurityKeyFailure.pinTooLong }
        var characters = 0
        var decoder = UTF8()
        var iterator = bytes.makeIterator()
        decoding: while true {
            switch decoder.decode(&iterator) {
            case .scalarValue: characters += 1
            case .emptyInput: break decoding
            case .error: throw SecurityKeyFailure.pinTooShort
            }
        }
        guard characters >= Self.fewestCharacters else { throw SecurityKeyFailure.pinTooShort }
        size = bytes.count + 1
        let buffer = UnsafeMutablePointer<CChar>.allocate(capacity: size)
        for (i, byte) in bytes.enumerated() { buffer[i] = CChar(bitPattern: byte) }
        buffer[bytes.count] = 0
        self.buffer = buffer
    }

    /// Whether the PIN can still be handed over.
    var isHeld: Bool { buffer != nil }

    /// Hands the PIN to `body` as a C string, once; then clears and frees it, whatever `body` does.
    func use<T>(_ body: (UnsafePointer<CChar>) throws -> T) throws -> T {
        guard let buffer else { throw SecurityKeyFailure.pinUsed }
        defer { release() }
        return try body(buffer)
    }

    /// Clears and frees the PIN now, if it's still held.
    func release() {
        guard let held = buffer else { return }
        Self.clear(held, size)
        held.deallocate()
        buffer = nil
    }

    deinit { release() }

    /// Zeroes memory in a way the compiler keeps.
    static func clear(_ pointer: UnsafeMutableRawPointer?, _ count: Int) {
        guard let pointer, count > 0 else { return }
        #if canImport(Darwin)
        _ = memset_s(pointer, count, 0, count)
        #else
        explicit_bzero(pointer, count)
        #endif
    }

    /// For tests only: the bytes still held, without the terminating NUL.
    func heldBytesForTests() -> [UInt8]? {
        guard let buffer else { return nil }
        return (0..<(size - 1)).map { UInt8(bitPattern: buffer[$0]) }
    }
}

/// A new credential's attestation object, as WebAuthn writes it: a CBOR map of `fmt`, `attStmt`
/// and `authData`, in CTAP2's canonical order. libfido2 gives the three apart: the format, the
/// statement as CBOR, and the raw authenticator data.
enum AttestationObject {
    static func make(format: String, statement: Data, authenticatorData: Data) -> Data {
        var out = Data([0xa3])
        out += text("fmt") + text(format)
        out += text("attStmt") + statement
        out += text("authData") + head(major: 2, count: authenticatorData.count) + authenticatorData
        return out
    }

    private static func text(_ string: String) -> Data {
        let bytes = Data(string.utf8)
        return head(major: 3, count: bytes.count) + bytes
    }

    /// A CBOR head: the major type and a length, in the shortest form.
    static func head(major: UInt8, count: Int) -> Data {
        let type = major << 5
        switch count {
        case 0..<24: return Data([type | UInt8(count)])
        case 24..<0x100: return Data([type | 24, UInt8(count)])
        case 0x100..<0x10000: return Data([type | 25, UInt8(count >> 8), UInt8(count & 0xff)])
        default:
            return Data([type | 26, UInt8((count >> 24) & 0xff), UInt8((count >> 16) & 0xff),
                         UInt8((count >> 8) & 0xff), UInt8(count & 0xff)])
        }
    }
}
