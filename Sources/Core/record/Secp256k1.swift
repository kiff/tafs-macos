import Foundation

/// Recovering the signer of a secp256k1 signature, as libsecp256k1's `ecdsa_recover` does: KIFF signs
/// its receipts with a secp256k1 key (Ethereum-style, `secp256k1+keccak256`), which CryptoKit doesn't
/// have. Plain arithmetic (SEC 1 v2, §4.1.6), so it runs on macOS 12 and on Linux alike. Every input is
/// public (a signature and a digest), so it needn't run in constant time.
enum Secp256k1 {
    /// The Ethereum-style address that signed `digest`: "0x" and the last 20 bytes of keccak256 of the
    /// uncompressed public key. Nil when the signature can't be read or recovers no key.
    /// `signature` is r ‖ s ‖ v, 65 bytes; v is 0–3, or 27–30.
    static func recoverAddress(digest: Data, signature: Data) -> String? {
        guard let key = recoverKey(digest: digest, signature: signature) else { return nil }
        let hash = Keccak.hash256(key)
        return "0x" + hash.suffix(20).map { String(format: "%02x", $0) }.joined()
    }

    /// The public key's X ‖ Y (64 bytes) that signed `digest`, or nil.
    static func recoverKey(digest: Data, signature: Data) -> Data? {
        guard digest.count == 32, signature.count == 65 else { return nil }
        let sig = [UInt8](signature)
        var v = Int(sig[64])
        if v >= 27 { v -= 27 }
        guard (0...3).contains(v) else { return nil }
        let r = U256(sig[0..<32]), s = U256(sig[32..<64])
        // r and s in [1, n − 1]. A high s is taken, as libsecp256k1 takes it: the same key signs with s
        // or n − s.
        guard !r.isZero, r < n, !s.isZero, s < n else { return nil }
        // R's x: r, or r + n for v 2 and 3, and below p.
        var x = r
        if v >= 2 {
            let (sum, carry) = r.adding(n)
            guard !carry else { return nil }
            x = sum
        }
        guard x < p else { return nil }
        // R's y from y² = x³ + 7, its parity v's low bit.
        let alpha = Field.add(Field.mul(Field.mul(x, x), x), U256(7))
        let beta = Field.pow(alpha, sqrtExponent)
        guard Field.mul(beta, beta) == alpha else { return nil }
        let y = (beta.words[0] & 1) == UInt64(v & 1) ? beta : Field.sub(U256.zero, beta)
        let point = Point(x: x, y: y, z: U256(1))
        // Q = r⁻¹(sR − eG) = u1·G + u2·R, u1 = −e·r⁻¹, u2 = s·r⁻¹ (mod n).
        let e = Scalar.reduce(U256([UInt8](digest)))
        let rInverse = Scalar.inverse(r)
        let u1 = Scalar.sub(U256.zero, Scalar.mul(e, rInverse))
        let u2 = Scalar.mul(s, rInverse)
        let q = Point.add(Point.multiply(generator, u1), Point.multiply(point, u2))
        guard let (qx, qy) = q.affine else { return nil }
        return Data(qx.bytes + qy.bytes)
    }

    /// p = 2^256 − 2^32 − 977.
    static let p = U256(hex: "fffffffffffffffffffffffffffffffffffffffffffffffffffffffefffffc2f")
    /// The group's order.
    static let n = U256(hex: "fffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364141")
    /// (p + 1) / 4: p ≡ 3 (mod 4), so a square root is a power.
    static let sqrtExponent = U256(hex: "3fffffffffffffffffffffffffffffffffffffffffffffffffffffffbfffff0c")
    static let generator = Point(
        x: U256(hex: "79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798"),
        y: U256(hex: "483ada7726a3c4655da4fbfc0e1108a8fd17b448a68554199c47d08ffb10d4b8"),
        z: U256(1))

    /// A 256-bit number: four 64-bit words, least significant first.
    struct U256: Equatable, Comparable {
        var words: [UInt64]
        static let zero = U256(0)

        init(_ value: UInt64) { words = [value, 0, 0, 0] }
        init(words: [UInt64]) { self.words = words }

        /// 32 bytes, big-endian.
        init<C: Collection>(_ bytes: C) where C.Element == UInt8 {
            let b = Array(bytes)
            words = (0..<4).map { i in
                let at = 32 - 8 * (i + 1)
                return b[at..<at + 8].reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
            }
        }

        init(hex: String) {
            var bytes: [UInt8] = []
            var index = hex.startIndex
            while index < hex.endIndex {
                let next = hex.index(index, offsetBy: 2)
                bytes.append(UInt8(hex[index..<next], radix: 16)!)
                index = next
            }
            self.init(bytes)
        }

        /// 32 bytes, big-endian.
        var bytes: [UInt8] {
            (0..<4).reversed().flatMap { i in (0..<8).reversed().map { UInt8(truncatingIfNeeded: words[i] >> (8 * UInt64($0))) } }
        }

        var isZero: Bool { words.allSatisfy { $0 == 0 } }

        func bit(_ i: Int) -> Bool { (words[i / 64] >> UInt64(i % 64)) & 1 == 1 }

        static func < (a: U256, b: U256) -> Bool {
            for i in stride(from: 3, through: 0, by: -1) where a.words[i] != b.words[i] { return a.words[i] < b.words[i] }
            return false
        }

        func adding(_ b: U256) -> (U256, Bool) {
            var out = [UInt64](repeating: 0, count: 4)
            var carry = false
            for i in 0..<4 {
                let (s1, c1) = words[i].addingReportingOverflow(b.words[i])
                let (s2, c2) = s1.addingReportingOverflow(carry ? 1 : 0)
                out[i] = s2
                carry = c1 || c2
            }
            return (U256(words: out), carry)
        }

        func subtracting(_ b: U256) -> (U256, Bool) {
            var out = [UInt64](repeating: 0, count: 4)
            var borrow = false
            for i in 0..<4 {
                let (d1, b1) = words[i].subtractingReportingOverflow(b.words[i])
                let (d2, b2) = d1.subtractingReportingOverflow(borrow ? 1 : 0)
                out[i] = d2
                borrow = b1 || b2
            }
            return (U256(words: out), borrow)
        }

        /// The full 512-bit product, eight words, least significant first.
        func wide(_ b: U256) -> [UInt64] {
            var out = [UInt64](repeating: 0, count: 8)
            for i in 0..<4 {
                var carry: UInt64 = 0
                for j in 0..<4 {
                    let (hi, lo) = words[i].multipliedFullWidth(by: b.words[j])
                    let (s1, c1) = out[i + j].addingReportingOverflow(lo)
                    let (s2, c2) = s1.addingReportingOverflow(carry)
                    out[i + j] = s2
                    carry = hi &+ (c1 ? 1 : 0) &+ (c2 ? 1 : 0)
                }
                out[i + 4] = carry
            }
            return out
        }
    }

    /// Arithmetic mod a modulus below 2^256, for a, b already below it.
    private static func addMod(_ a: U256, _ b: U256, _ m: U256) -> U256 {
        let (sum, carry) = a.adding(b)
        if carry || !(sum < m) { return sum.subtracting(m).0 }
        return sum
    }

    private static func subMod(_ a: U256, _ b: U256, _ m: U256) -> U256 {
        let (difference, borrow) = a.subtracting(b)
        return borrow ? difference.adding(m).0 : difference
    }

    /// A 512-bit number mod m, by long division a bit at a time.
    private static func reduceWide(_ w: [UInt64], _ m: U256) -> U256 {
        var r = U256.zero
        for i in stride(from: 511, through: 0, by: -1) {
            let top = r.words[3] >> 63 == 1
            var shifted = [UInt64](repeating: 0, count: 4)
            for k in 0..<4 { shifted[k] = (r.words[k] << 1) | (k > 0 ? r.words[k - 1] >> 63 : 0) }
            shifted[0] |= (w[i / 64] >> UInt64(i % 64)) & 1
            r = U256(words: shifted)
            if top || !(r < m) { r = r.subtracting(m).0 }
        }
        return r
    }

    /// The field mod p, with p's special form for its reductions.
    enum Field {
        /// 2^256 mod p = 2^32 + 977.
        private static let fold: UInt64 = 0x1_0000_03D1

        static func add(_ a: U256, _ b: U256) -> U256 { addMod(a, b, p) }
        static func sub(_ a: U256, _ b: U256) -> U256 { subMod(a, b, p) }

        static func mul(_ a: U256, _ b: U256) -> U256 {
            let w = a.wide(b)
            // lo + hi·2^256 ≡ lo + hi·(2^32 + 977), folded until it fits.
            var acc = [UInt64](w[0..<4]) + [0]
            var carry: UInt64 = 0
            for i in 0..<4 {
                let (hi, lo) = w[i + 4].multipliedFullWidth(by: fold)
                let (s1, c1) = acc[i].addingReportingOverflow(lo)
                let (s2, c2) = s1.addingReportingOverflow(carry)
                acc[i] = s2
                carry = hi &+ (c1 ? 1 : 0) &+ (c2 ? 1 : 0)
            }
            acc[4] = carry
            while acc[4] != 0 {
                let (hi, lo) = acc[4].multipliedFullWidth(by: fold)
                acc[4] = 0
                var add: [UInt64] = [lo, hi, 0, 0]
                var c = false
                for i in 0..<4 {
                    let (s1, c1) = acc[i].addingReportingOverflow(add[i])
                    let (s2, c2) = s1.addingReportingOverflow(c ? 1 : 0)
                    acc[i] = s2
                    c = c1 || c2
                    add[i] = 0
                }
                if c { acc[4] = 1 }
            }
            var r = U256(words: Array(acc[0..<4]))
            while !(r < p) { r = r.subtracting(p).0 }
            return r
        }

        static func pow(_ a: U256, _ e: U256) -> U256 {
            var result = U256(1)
            for i in stride(from: 255, through: 0, by: -1) {
                result = mul(result, result)
                if e.bit(i) { result = mul(result, a) }
            }
            return result
        }

        /// a⁻¹ = a^(p − 2).
        static func inverse(_ a: U256) -> U256 { pow(a, p.subtracting(U256(2)).0) }
    }

    /// Scalars mod n.
    enum Scalar {
        static func reduce(_ a: U256) -> U256 { a < n ? a : a.subtracting(n).0 }
        static func sub(_ a: U256, _ b: U256) -> U256 { subMod(a, b, n) }
        static func mul(_ a: U256, _ b: U256) -> U256 { reduceWide(a.wide(b), n) }

        /// a⁻¹ = a^(n − 2), n being prime.
        static func inverse(_ a: U256) -> U256 {
            let e = n.subtracting(U256(2)).0
            var result = U256(1)
            for i in stride(from: 255, through: 0, by: -1) {
                result = mul(result, result)
                if e.bit(i) { result = mul(result, a) }
            }
            return result
        }
    }

    /// A point in Jacobian coordinates (X/Z², Y/Z³); Z = 0 is the point at infinity.
    struct Point {
        let x: U256, y: U256, z: U256

        static let infinity = Point(x: U256(1), y: U256(1), z: .zero)
        var isInfinity: Bool { z.isZero }

        var affine: (U256, U256)? {
            guard !isInfinity else { return nil }
            let zInverse = Field.inverse(z)
            let zz = Field.mul(zInverse, zInverse)
            return (Field.mul(x, zz), Field.mul(y, Field.mul(zz, zInverse)))
        }

        /// 2P (a = 0).
        static func double(_ p: Point) -> Point {
            guard !p.isInfinity, !p.y.isZero else { return .infinity }
            let a = Field.mul(p.x, p.x)
            let b = Field.mul(p.y, p.y)
            let c = Field.mul(b, b)
            let xb = Field.add(p.x, b)
            var d = Field.sub(Field.sub(Field.mul(xb, xb), a), c)
            d = Field.add(d, d)
            let e = Field.add(Field.add(a, a), a)
            let f = Field.mul(e, e)
            let x3 = Field.sub(f, Field.add(d, d))
            var c8 = Field.add(c, c)
            c8 = Field.add(c8, c8)
            c8 = Field.add(c8, c8)
            let y3 = Field.sub(Field.mul(e, Field.sub(d, x3)), c8)
            let yz = Field.mul(p.y, p.z)
            return Point(x: x3, y: y3, z: Field.add(yz, yz))
        }

        /// P + Q.
        static func add(_ p: Point, _ q: Point) -> Point {
            if p.isInfinity { return q }
            if q.isInfinity { return p }
            let z1z1 = Field.mul(p.z, p.z)
            let z2z2 = Field.mul(q.z, q.z)
            let u1 = Field.mul(p.x, z2z2)
            let u2 = Field.mul(q.x, z1z1)
            let s1 = Field.mul(Field.mul(p.y, q.z), z2z2)
            let s2 = Field.mul(Field.mul(q.y, p.z), z1z1)
            let h = Field.sub(u2, u1)
            let rr = Field.sub(s2, s1)
            if h.isZero { return rr.isZero ? double(p) : .infinity }
            let h2 = Field.add(h, h)
            let i = Field.mul(h2, h2)
            let j = Field.mul(h, i)
            let r = Field.add(rr, rr)
            let v = Field.mul(u1, i)
            let x3 = Field.sub(Field.sub(Field.mul(r, r), j), Field.add(v, v))
            let s1j = Field.mul(s1, j)
            let y3 = Field.sub(Field.mul(r, Field.sub(v, x3)), Field.add(s1j, s1j))
            let zs = Field.add(p.z, q.z)
            let z3 = Field.mul(Field.sub(Field.sub(Field.mul(zs, zs), z1z1), z2z2), h)
            return Point(x: x3, y: y3, z: z3)
        }

        /// kP, by double and add from the top bit.
        static func multiply(_ p: Point, _ k: U256) -> Point {
            var result = Point.infinity
            for i in stride(from: 255, through: 0, by: -1) {
                result = double(result)
                if k.bit(i) { result = add(result, p) }
            }
            return result
        }
    }
}
