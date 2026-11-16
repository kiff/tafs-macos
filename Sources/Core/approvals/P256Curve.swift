import Foundation

/// Whether a point is on P-256 (NIST P-256, secp256r1), by its curve equation
/// `y² ≡ x³ − 3x + b (mod p)` with both coordinates below `p`. Plain arithmetic, no framework: it
/// works on macOS 12 and on Linux alike. The inputs are a public key's, so it needn't run in
/// constant time.
enum P256Curve {
    /// x and y, each 32 bytes big-endian, as a COSE key or a raw P-256 key carries them.
    static func contains(_ x: Data, _ y: Data) -> Bool {
        guard x.count == 32, y.count == 32 else { return false }
        let x = limbs(x), y = limbs(y)
        guard less(x, p), less(y, p) else { return false }
        let left = mul(y, y)
        let x3 = mul(mul(x, x), x)
        let threeX = add(add(x, x), x)
        let right = add(sub(x3, threeX), b)
        return left == right
    }

    /// p = 2^256 − 2^224 + 2^192 + 2^96 − 1.
    static let p = limbs(hex: "ffffffff00000001000000000000000000000000ffffffffffffffffffffffff")
    /// The curve's b.
    static let b = limbs(hex: "5ac635d8aa3a93e7b3ebbd55769886bc651d06b0cc53b0f63bce3c3e27d2604b")

    /// Eight 32-bit limbs, least significant first.
    typealias Limbs = [UInt32]

    static func limbs(_ data: Data) -> Limbs {
        let bytes = [UInt8](data)
        return (0..<8).map { i in
            let at = 32 - 4 * (i + 1)
            return bytes[at..<at + 4].reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
        }
    }

    static func limbs(hex: String) -> Limbs {
        var bytes: [UInt8] = []
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            bytes.append(UInt8(hex[index..<next], radix: 16)!)
            index = next
        }
        return limbs(Data(bytes))
    }

    /// a < b, for numbers of the same number of limbs.
    static func less(_ a: Limbs, _ b: Limbs) -> Bool {
        for i in stride(from: a.count - 1, through: 0, by: -1) where a[i] != b[i] { return a[i] < b[i] }
        return false
    }

    /// (a + b) mod p, for a, b < p.
    static func add(_ a: Limbs, _ b: Limbs) -> Limbs {
        var out = Limbs(repeating: 0, count: 8)
        var carry: UInt64 = 0
        for i in 0..<8 {
            let sum = UInt64(a[i]) + UInt64(b[i]) + carry
            out[i] = UInt32(truncatingIfNeeded: sum)
            carry = sum >> 32
        }
        if carry != 0 || !less(out, p) { out = rawSub(out, p) }
        return out
    }

    /// (a − b) mod p, for a, b < p.
    static func sub(_ a: Limbs, _ b: Limbs) -> Limbs {
        less(a, b) ? add(a, rawSub(p, b)) : rawSub(a, b)
    }

    /// (a × b) mod p: the full product, then its remainder by long division.
    static func mul(_ a: Limbs, _ b: Limbs) -> Limbs {
        var product = [UInt32](repeating: 0, count: 16)
        for i in 0..<8 {
            var carry: UInt64 = 0
            for j in 0..<8 {
                let t = UInt64(a[i]) * UInt64(b[j]) + UInt64(product[i + j]) + carry
                product[i + j] = UInt32(truncatingIfNeeded: t)
                carry = t >> 32
            }
            product[i + 8] = UInt32(truncatingIfNeeded: carry)
        }
        // Bit by bit from the top: the remainder stays below p, kept in nine limbs so the doubling
        // never overflows.
        var r = [UInt32](repeating: 0, count: 9)
        let wide = p + [0]
        for bit in stride(from: 511, through: 0, by: -1) {
            var carry: UInt32 = (product[bit / 32] >> UInt32(bit % 32)) & 1
            for i in 0..<9 {
                let next = r[i] >> 31
                r[i] = r[i] << 1 | carry
                carry = next
            }
            if !less(r, wide) { r = rawSub(r, wide) }
        }
        return Array(r[0..<8])
    }

    /// a − b, for a ≥ b, with no reduction.
    static func rawSub(_ a: Limbs, _ b: Limbs) -> Limbs {
        var out = Limbs(repeating: 0, count: a.count)
        var borrow: Int64 = 0
        for i in 0..<a.count {
            var d = Int64(a[i]) - Int64(b[i]) - borrow
            borrow = 0
            if d < 0 { d += 1 << 32; borrow = 1 }
            out[i] = UInt32(d)
        }
        return out
    }
}
