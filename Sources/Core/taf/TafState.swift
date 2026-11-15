import Foundation

/// A taf's state as the iPad's chip says it, beside its name on its page: tafs cloud's word
/// for where it stands, through the shared lines, and the chip's tone.
enum TafState {
    enum Tone: Equatable { case ok, amber, no, soft }

    /// The chip for tafs cloud's `state`, or none: for a word this app doesn't know, and for a
    /// working taf that needs the person, whose Activity says what went wrong instead.
    static func chip(state: String, attention: Bool) -> (key: String, tone: Tone)? {
        switch state {
        case "working": return attention ? nil : ("taf.state.working", .ok)
        case "waiting": return ("taf.state.waiting", .amber)
        case "idle": return ("taf.state.ready", .soft)
        case "paused": return ("taf.state.paused", .soft)
        case "stopped", "revoked": return ("taf.state.stopped", .no)
        case "halted": return ("taf.state.halted", .no)
        default: return nil
        }
    }
}
