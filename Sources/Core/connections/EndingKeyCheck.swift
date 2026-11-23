import Foundation

/// What sign-in does with the **ending key** (the app's `EndingKey`, docs/approvals.md › Ending
/// access with Touch ID): a second Secure Enclave key, usable only with Touch ID's fingers as
/// they were at sign-in. The app's sign-in calls it next to where it keeps the session, and where
/// it forgets the session; it never prompts and never throws, so sign-in never waits on it.
struct EndingKeyHook {
    /// A session was kept, with the device key whose `keyStore` it signed in with: any ending key
    /// before it is deleted, and one is made for this session when it can be.
    var kept: (Session, String) -> Void
    /// The session ended on this Mac: its ending key is deleted.
    var forgotten: () -> Void

    /// No ending key, ever: a test's sign-in, and any Mac that ends nothing itself.
    static let none = EndingKeyHook(kept: { _, _ in }, forgotten: {})
}

extension ConnectionEnding {
    /// The ending key is gone: none for this session, one that doesn't load, or one the system
    /// invalidated because Touch ID's fingers changed. Nothing is sent; the phone, until the next
    /// sign-in.
    struct KeyGone: Error {}

    /// What the ending key signs as the person's Touch ID, the iPad's own confirmation:
    /// `tafs.disconnect.v1|{tenant}|{ids joined by ,}`. As the iPad's, it is never sent.
    static func confirmation(tenant: String, ids: [String]) -> Data {
        Data("tafs.disconnect.v1|\(tenant)|\(ids.joined(separator: ","))".utf8)
    }

    /// What is kept for the ending key: the sign-in it was made for, a line break, then the key's
    /// handle (the Secure Enclave's wrapped reference, never the key itself).
    static func endingKeyRecord(session: String, handle: Data) -> Data {
        Data(session.utf8) + Data([0x0A]) + handle
    }

    /// The handle kept for `session`; nil for none, another sign-in's, or a record that doesn't read.
    static func endingKeyHandle(recorded: Data?, session: String) -> Data? {
        guard !session.isEmpty, !session.utf8.contains(0x0A), let recorded,
              let cut = recorded.firstIndex(of: 0x0A),
              recorded[recorded.startIndex..<cut] == Data(session.utf8) else { return nil }
        let handle = Data(recorded[recorded.index(after: cut)...])
        return handle.isEmpty ? nil : handle
    }

    /// At sign-in: the ending key before is deleted, then a new one is made (`create`, which never
    /// prompts) only when the session's device key is in the Secure Enclave and Touch ID can be
    /// checked, and kept for `session`. Any failure keeps none: that Mac ends nothing itself.
    static func keepEndingKey(session: String, enclave: Bool, biometrics: () -> Bool,
                              create: () throws -> Data, save: (Data) throws -> Void, remove: () -> Void) {
        remove()
        guard enclave, !session.isEmpty, !session.utf8.contains(0x0A), biometrics() else { return }
        guard let handle = try? create(), !handle.isEmpty else { return }
        do { try save(endingKeyRecord(session: session, handle: handle)) } catch { remove() }
    }

    /// Touch ID, through the ending key kept for this sign-in. Reads only: nothing here writes the
    /// record, and only a key the system invalidated is deleted (`confirm`).
    struct EndingKeyCheck {
        /// The sign-in it is for (the app's `EndingKey.binding`).
        let session: String
        /// The kept record, read.
        let read: () -> Data?
        /// Deletes the kept record.
        let remove: () -> Void
        /// Whether Touch ID can be checked now, with no prompt.
        let biometrics: () -> Bool
        /// Whether the handle loads as a Secure Enclave key, with no prompt.
        let loads: (Data) -> Bool
        /// Signs `message` with the handle's key, `reason` on the system's Touch ID prompt. A key the
        /// system invalidated throws `KeyGone`; a closed or failed prompt throws anything else.
        let sign: (_ handle: Data, _ reason: String, _ message: Data) async throws -> Void

        private var handle: Data? { ConnectionEnding.endingKeyHandle(recorded: read(), session: session) }

        /// True only with this session's key, loading, and Touch ID that can be checked now.
        func available() -> Bool {
            guard let handle = handle, biometrics() else { return false }
            return loads(handle)
        }

        /// Touch ID: the ending key signs `message`. Any failure throws, so nothing is sent. A key
        /// gone is deleted, when it is still the one kept, and the Mac goes to the phone.
        func confirm(_ reason: String, _ message: Data) async throws {
            guard let handle = handle else { throw KeyGone() }
            do {
                try await sign(handle, reason, message)
            } catch is KeyGone {
                if self.handle == handle { remove() }
                throw KeyGone()
            }
        }
    }
}
