import AppKit
import SwiftUI

/// The security key's PIN sheet, for each approval this Mac makes with its key, and for adding
/// the key while this Mac pairs (`SecurityKeySheetPurpose`; kiff/tafs `docs/computer-passkeys.md`): its title, what it asks, the tries left when the key says, the
/// PIN field, then "Touch your security key." while the key waits; each failure in its own
/// shared line (`SecurityKeyWords`), and the sheet stays open to try again, but for a locked key.
///
/// **The PIN** is read from the field's own storage straight into UTF-8 bytes (`PINReader`), never
/// into a Swift `String`, and the field is emptied at once. The bytes become one `SecurityKeyPIN`,
/// which clears them, is handed to the key once, then is cleared and freed.
@MainActor
final class PINSheetModel: ObservableObject, Identifiable {
    enum Phase: Equatable {
        /// The PIN is asked.
        case entering
        /// The PIN went to the key, which waits for its touch.
        case touching
    }

    let id = UUID()
    @Published var phase: Phase = .entering
    /// Why the last try gave no approval, in the shared words.
    @Published var message: String?
    /// The tries left before the key locks, when the key says, read before the PIN is asked.
    @Published var triesLine: String?
    /// The key is locked: nothing more is asked of it here.
    @Published var locked = false
    let reader = PINReader()
    /// Approving a request, or adding the key while this Mac pairs: only the sheet's words differ.
    let purpose: SecurityKeySheetPurpose
    private let words: Words
    private let attempt: (SecurityKeyPIN) async throws -> Void
    private let readTries: () async throws -> Int
    private var done: ((Error?) -> Void)?

    /// - `attempt` asks the key with the PIN; it returns once the key approved.
    /// - `readTries` reads the PIN tries left, before the PIN is asked.
    /// - `done` hears once: nil once approved, or the error that closed the sheet.
    init(words: Words, purpose: SecurityKeySheetPurpose = .approve, attempt: @escaping (SecurityKeyPIN) async throws -> Void,
         readTries: @escaping () async throws -> Int, done: @escaping (Error?) -> Void) {
        self.words = words
        self.purpose = purpose
        self.attempt = attempt
        self.readTries = readTries
        self.done = done
    }

    /// Reads the tries left, as the key says them; a key that can't be read now says nothing yet.
    func appeared() async {
        do {
            triesLine = SecurityKeyWords.triesLeft(try await readTries(), words: words)
        } catch SecurityKeyFailure.pinBlocked {
            show(SecurityKeyFailure.pinBlocked)
        } catch {}
    }

    /// Takes the typed PIN and asks the key with it.
    func approve() async {
        guard phase == .entering, !locked, done != nil else { return }
        var bytes = reader.takeBytes()
        let pin: SecurityKeyPIN
        do { pin = try SecurityKeyPIN(utf8: &bytes) } catch { return show(error) }
        message = nil
        phase = .touching
        // Handed to the key once; cleared and freed whatever the key answered.
        defer { pin.release() }
        do {
            try await attempt(pin)
            finish(nil)
        } catch {
            phase = .entering
            show(error)
        }
    }

    /// Closes the sheet: nothing is approved, and the field is emptied. While pairing, that pairs
    /// this Mac without the key (`pair_without`).
    func cancel() {
        reader.clear()
        finish(CancellationError())
    }

    private func show(_ error: Error) {
        message = SecurityKeyWords.line(error, words: words)
        if !SecurityKeyWords.mayTryAgain(error) { locked = true }
    }

    private func finish(_ error: Error?) {
        let heard = done
        done = nil
        heard?(error)
    }
}

/// Reads a secure field's text as UTF-8 bytes without making a Swift `String` of it, then empties
/// the field. What's left: AppKit's own field editor held the characters while they were typed,
/// and this app can't zero that memory; it's emptied here, never copied elsewhere.
final class PINReader {
    weak var field: NSSecureTextField?

    /// The typed PIN's UTF-8 bytes; the field is emptied.
    func takeBytes() -> [UInt8] {
        guard let field else { return [] }
        let bytes: [UInt8]
        if let storage = (field.currentEditor() as? NSTextView)?.textStorage {
            bytes = Self.utf8((storage.mutableString as NSString) as CFString)
        } else {
            bytes = Self.utf8(CFAttributedStringGetString(field.attributedStringValue as CFAttributedString))
        }
        clear()
        return bytes
    }

    /// Empties the field and its editor.
    func clear() {
        guard let field else { return }
        (field.currentEditor() as? NSTextView)?.textStorage?.mutableString.setString("")
        field.stringValue = ""
    }

    /// A CoreFoundation string's UTF-8, straight into bytes.
    static func utf8(_ text: CFString) -> [UInt8] {
        let range = CFRange(location: 0, length: CFStringGetLength(text))
        let encoding = CFStringBuiltInEncodings.UTF8.rawValue
        var used: CFIndex = 0
        _ = CFStringGetBytes(text, range, encoding, 0, false, nil, 0, &used)
        var bytes = [UInt8](repeating: 0, count: used)
        _ = CFStringGetBytes(text, range, encoding, 0, false, &bytes, used, nil)
        return bytes
    }
}

/// The PIN field: AppKit's secure field, read only through `PINReader`.
struct SecurePINField: NSViewRepresentable {
    let reader: PINReader
    let placeholder: String

    func makeNSView(context: Context) -> NSSecureTextField {
        let field = NSSecureTextField()
        field.placeholderString = placeholder
        field.bezelStyle = .roundedBezel
        field.usesSingleLineMode = true
        reader.field = field
        return field
    }

    func updateNSView(_ field: NSSecureTextField, context: Context) {
        reader.field = field
    }
}

struct PINSheet: View {
    @Environment(\.words) private var words
    @ObservedObject var model: PINSheetModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(words(model.purpose.titleKey)).font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.ink)
                .frame(maxWidth: .infinity).accessibilityAddTraits(.isHeader)
            Text(words(model.purpose.leadKey)).font(.system(size: 14)).foregroundColor(Theme.soft)
                .fixedSize(horizontal: false, vertical: true)
            if let tries = model.triesLine {
                Text(verbatim: tries).font(.system(size: 13)).foregroundColor(Theme.dim).fixedSize(horizontal: false, vertical: true)
            }
            Eyebrow(text: words("approval.security_key.pin"))
            SecurePINField(reader: model.reader, placeholder: words("approval.security_key.pin"))
                .frame(height: 24)
                .disabled(model.phase == .touching || model.locked)
            if model.phase == .touching {
                Text(words("approval.security_key.touch")).font(.system(size: 14, weight: .semibold)).foregroundColor(Theme.amberText)
            }
            if let message = model.message {
                Text(verbatim: message).font(.system(size: 13)).foregroundColor(Theme.no).fixedSize(horizontal: false, vertical: true)
            }
            buttons
        }
        .padding(20)
        .frame(width: 440)
        .background(Theme.background)
        .task { await model.appeared() }
        .onDisappear { model.cancel() }
    }

    private var buttons: some View {
        HStack {
            Spacer()
            Button(words(model.purpose.closeKey)) { model.cancel() }.keyboardShortcut(.cancelAction)
            Button(words(model.purpose.actionKey)) { Task { await model.approve() } }
                .keyboardShortcut(.defaultAction)
                .disabled(model.phase == .touching || model.locked)
        }
    }
}
