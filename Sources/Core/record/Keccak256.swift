import Foundation

/// Keccak-256 as Ethereum and KIFF use it (the original Keccak padding, not SHA3-256's): KIFF's
/// receipt digest is keccak256 of the chain's SHA-256 in hex, and a signer's address is the last 20
/// bytes of keccak256 of its public key. Plain arithmetic, so it runs on macOS 12 and on Linux alike.
enum Keccak {
    static func hash256(_ data: Data) -> Data {
        let rate = 136
        var state = [UInt64](repeating: 0, count: 25)
        var bytes = [UInt8](data)
        // The original Keccak's padding: 0x01, zeros, then 0x80 on the block's last byte.
        bytes.append(0x01)
        while bytes.count % rate != 0 { bytes.append(0) }
        bytes[bytes.count - 1] |= 0x80
        var block = 0
        while block < bytes.count {
            for lane in 0..<(rate / 8) {
                var value: UInt64 = 0
                for b in 0..<8 { value |= UInt64(bytes[block + lane * 8 + b]) << (8 * UInt64(b)) }
                state[lane] ^= value
            }
            permute(&state)
            block += rate
        }
        var out = [UInt8]()
        for lane in 0..<4 {
            for b in 0..<8 { out.append(UInt8(truncatingIfNeeded: state[lane] >> (8 * UInt64(b)))) }
        }
        return Data(out)
    }

    private static let roundConstants: [UInt64] = [
        0x0000000000000001, 0x0000000000008082, 0x800000000000808a, 0x8000000080008000,
        0x000000000000808b, 0x0000000080000001, 0x8000000080008081, 0x8000000000008009,
        0x000000000000008a, 0x0000000000000088, 0x0000000080008009, 0x000000008000000a,
        0x000000008000808b, 0x800000000000008b, 0x8000000000008089, 0x8000000000008003,
        0x8000000000008002, 0x8000000000000080, 0x000000000000800a, 0x800000008000000a,
        0x8000000080008081, 0x8000000000008080, 0x0000000080000001, 0x8000000080008008,
    ]
    private static let rotations: [UInt64] = [1, 3, 6, 10, 15, 21, 28, 36, 45, 55, 2, 14, 27, 41, 56, 8, 25, 43, 62, 18, 39, 61, 20, 44]
    private static let lanes = [10, 7, 11, 17, 18, 3, 5, 16, 8, 21, 24, 4, 15, 23, 19, 13, 12, 2, 20, 14, 22, 9, 6, 1]

    private static func rotl(_ x: UInt64, _ n: UInt64) -> UInt64 { (x << n) | (x >> (64 - n)) }

    /// Keccak-f[1600], 24 rounds.
    private static func permute(_ s: inout [UInt64]) {
        var c = [UInt64](repeating: 0, count: 5)
        for round in 0..<24 {
            for i in 0..<5 { c[i] = s[i] ^ s[i + 5] ^ s[i + 10] ^ s[i + 15] ^ s[i + 20] }
            for i in 0..<5 {
                let t = c[(i + 4) % 5] ^ rotl(c[(i + 1) % 5], 1)
                for j in stride(from: 0, to: 25, by: 5) { s[j + i] ^= t }
            }
            var t = s[1]
            for i in 0..<24 {
                let j = lanes[i]
                let next = s[j]
                s[j] = rotl(t, rotations[i])
                t = next
            }
            for j in stride(from: 0, to: 25, by: 5) {
                for i in 0..<5 { c[i] = s[j + i] }
                for i in 0..<5 { s[j + i] ^= ~c[(i + 1) % 5] & c[(i + 2) % 5] }
            }
            s[0] ^= roundConstants[round]
        }
    }
}
