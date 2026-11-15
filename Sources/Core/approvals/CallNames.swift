import Foundation

/// What the person reads for a call, as the iPad's `KIFFMapping` (`KIFF/KIFFMapping.swift:37-86`):
/// its tool's title as KIFF gives it, else the action in words. Never a name made up here.
enum CallNames {
    /// An action's name for people, as the iPad's `KIFFMapping.name`: the title, else the action
    /// in words. The action's own name, a grant prefix included, stays out.
    static func name(_ action: String, title: String?) -> String {
        let t = (title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? toolWords(action) : t
    }

    /// A held call's name, which the person approves or refuses alone, as the iPad's
    /// `KIFFMapping.says`: its title, with its action in words unless the title names the
    /// action's last word. A vendor's shared label ("Write Stripe API data · refund payment")
    /// then still says which tool; "Refund a payment", for create_refund, stays alone.
    static func says(_ action: String, title: String?) -> String {
        let name = self.name(action, title: title)
        var words = toolWords(action)
        let titleWords = Set(name.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }))
        var parts = words.lowercased().split(separator: " ")
        // planque ends a tool's name with four letters or digits of its grant ("create_refund_repg"):
        // with a title, a last word of four the title doesn't have is that, and never shown.
        if title?.isEmpty == false, parts.count > 1, let last = parts.last, last.count == 4,
           !titleWords.contains(last), last.allSatisfy({ $0.isLetter || $0.isNumber }) {
            parts.removeLast()
            words = parts.joined(separator: " ")
        }
        guard let last = parts.last else { return name }
        return titleWords.contains(last) ? name : "\(name) · \(words)"
    }

    /// A tool's name in words, as the iPad's `KIFFMapping.toolWords`: past a server's prefix
    /// ("stripe.create_refund", "kiff__refund_order") and the grant's own
    /// ("bxkwf7vi_list_charges"), separators as spaces. "bxkwf7vi_list_charges" → "list charges".
    static func toolWords(_ tool: String) -> String {
        var name = tool.components(separatedBy: "__").last?.split(separator: ".").last.map(String.init) ?? tool
        if let r = name.range(of: #"^(?=[a-z]*[0-9])[a-z0-9]{6,}_"#, options: .regularExpression), r.upperBound < name.endIndex {
            name = String(name[r.upperBound...])
        }
        let words = name.split(whereSeparator: { $0 == "_" || $0 == "-" }).joined(separator: " ")
        return words.isEmpty ? tool : words
    }
}
