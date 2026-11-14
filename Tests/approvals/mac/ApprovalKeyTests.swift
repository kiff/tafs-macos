import CryptoKit
import Foundation
import Security

let approvalsKeyTests: [Test] = [
    Test("a Mac that can't hold an approval key has none, and nothing is kept for one") {
        let store = MemoryStore()
        try expect(ApprovalKey.load(from: store, available: false, domain: nil) == nil, "no key")
        try expectEqual(store.load(ApprovalKey.account), nil)
        try expectEqual(store.load(ApprovalKey.domainAccount), nil)
    },
    Test("this Mac's own answer is the system's: a key only with a Secure Enclave and a fingerprint") {
        if !SecureEnclave.isAvailable { try expectEqual(ApprovalKey.available, false) }
        if !ApprovalKey.available { try expect(ApprovalKey.load(from: MemoryStore()) == nil, "no key on this Mac") }
    },
    Test("the key's access is private-key use by the enrolled fingerprints, and nothing else") {
        try expectEqual(ApprovalKey.flags, [.privateKeyUsage, .biometryCurrentSet])
        try expect(!ApprovalKey.flags.contains(.devicePasscode), "never the password")
        try expect(!ApprovalKey.flags.contains(.userPresence), "never the password through user presence")
        try expect(!ApprovalKey.flags.contains(.biometryAny), "never a fingerprint enrolled later")
    },
    Test("changed fingerprints end the key, and only two known values that differ say so") {
        try expectEqual(ApprovalKey.changed(made: Data([1]), now: Data([2])), true)
        try expectEqual(ApprovalKey.changed(made: Data([1]), now: Data([1])), false)
        try expectEqual(ApprovalKey.changed(made: Data([1]), now: nil), false)
        try expectEqual(ApprovalKey.changed(made: nil, now: Data([2])), false)
        // A kept key whose fingerprints changed is forgotten, and none takes its place by itself.
        let store = MemoryStore()
        store.save(Data([9, 9]), for: ApprovalKey.account)
        store.save(Data([1]), for: ApprovalKey.domainAccount)
        try expect(ApprovalKey.load(from: store, available: true, domain: Data([2])) == nil, "no key after a change")
        try expectEqual(store.load(ApprovalKey.account), nil)
        try expectEqual(store.load(ApprovalKey.domainAccount), nil)
    },
    Test("a software device key never approves, with or without an approval key beside it") {
        let software = try DeviceKey.load(from: MemoryStore(), enclave: false)
        try expectEqual(ApprovalMeans.of(deviceKey: software, approvalKey: nil), .passkey)
        try expectEqual(ApprovalRoute.of(ApprovalMeans.of(deviceKey: software, approvalKey: nil)), .phoneOrPasskey)
    },
]
