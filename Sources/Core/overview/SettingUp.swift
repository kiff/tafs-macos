import Foundation

/// A taf being set up, as Home lists it (`setting_up`, tafs cloud's `home.ts`): its name and KIFF agent, and, for the
/// person who started it, Discard (`discard`): the Cards in force on its agent, which are revoked first, and its words.
/// The iPad's `DiscardSettingUpButton` (`DiscardSettingUp.swift`) and `discardSettingUp` (AppModel).
struct SettingUp: Decodable, Equatable, Identifiable {
    struct Discard: Decodable, Equatable {
        struct Words: Decodable, Equatable {
            var button = ""
            var title = ""
            var text = ""
            var yes = ""
            var no = ""
            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: Keys.self)
                func text(_ key: Keys) -> String { ((try? c.decodeIfPresent(String.self, forKey: key)) ?? nil)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" }
                button = text(.button); title = text(.title); self.text = text(.text); yes = text(.yes); no = text(.no)
            }
            enum Keys: String, CodingKey { case button, title, text, yes, no }
        }
        /// The Cards in force on its agent, revoked in KIFF before tafs cloud is asked.
        var cards: [String]
        var words: Words
    }

    let name: String
    let kiffAgent: String
    /// Its colour, by its index in the palette, as Home gives it.
    let color: Int
    /// "Finish setting up", in tafs cloud's words, for the person who started it while Coach's chat for it waits.
    let finishWords: String?
    /// Only for the person who started it, with tafs cloud's words: nil draws no Discard.
    let discard: Discard?
    var id: String { kiffAgent }

    enum CodingKeys: String, CodingKey { case name, kiffAgent = "kiff_agent", color, finish, discard }
    private struct Finish: Decodable { let words: String? }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        kiffAgent = try c.decode(String.self, forKey: .kiffAgent)
        color = ((try? c.decodeIfPresent(Int.self, forKey: .color)) ?? nil) ?? 0
        let finish = ((try? c.decodeIfPresent(Finish.self, forKey: .finish)) ?? nil)?.words?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        finishWords = finish.isEmpty ? nil : finish
        // A Discard without its button's words can't be drawn: none.
        discard = ((try? c.decodeIfPresent(Discard.self, forKey: .discard)) ?? nil).flatMap { $0.words.button.isEmpty ? nil : $0 }
    }

    /// Home's `setting_up`, each read on its own: one that doesn't read is left out, never the page.
    static func listed<K: CodingKey>(_ c: KeyedDecodingContainer<K>, _ key: K) -> [SettingUp] {
        (((try? c.decodeIfPresent([One].self, forKey: key)) ?? nil) ?? []).compactMap(\.one)
    }

    /// One taf being set up, read on its own.
    private struct One: Decodable { let one: SettingUp?; init(from decoder: Decoder) throws { one = try? SettingUp(from: decoder) } }
}

/// Discarding a taf being set up, as the iPad's `discardSettingUp`, on this Mac's security key: tafs cloud takes the
/// key's assertion in place of the phone's signature (`discardSigned`, `checkSigned`, the same as a removal). The approval
/// first, before anything changes; then KIFF revokes its Cards, so it can't act; then tafs cloud ends the Coach chat that
/// drafted it and forgets its name. What to tell the person; nil when it was discarded, or the sheet was closed.
enum SettingUpDiscard {
    /// What tafs cloud said when KIFF still holds some of its Cards in force (409 `cards_in_force`): which, so Discard
    /// again revokes them too.
    struct CardsInForce: Error, Equatable { let cards: [String] }

    static func discard(_ taf: SettingUp, cardsLeftBefore: [String] = [], words: Words,
                        sign: (KeyAct, String) async throws -> String,
                        revoke: (String) async throws -> Void,
                        send: (String) async throws -> Void) async -> (said: String?, cardsLeft: [String]) {
        guard let discard = taf.discard else { return (nil, []) }
        let act = KeyAct.discardSettingUp(taf.kiffAgent)
        let assertion: String
        do { assertion = try await sign(act, discard.words.title.isEmpty ? discard.words.button : discard.words.title) } catch is CancellationError {
            return (nil, cardsLeftBefore)
        } catch is ApproveOnPhone {
            return (words("approval.device_can_not_approve_approve"), cardsLeftBefore)
        } catch {
            return (words("setup.discard_not_confirmed"), cardsLeftBefore)
        }
        // Home's Cards, and any a refused Discard named that Home didn't.
        var cardIDs = discard.cards
        for id in cardsLeftBefore where !cardIDs.contains(id) { cardIDs.append(id) }
        var notRevoked = 0
        for id in cardIDs {
            do { try await revoke(id) } catch { notRevoked += 1 }
        }
        do {
            try await send(assertion)
        } catch let left as CardsInForce {
            // KIFF still holds some of its Cards in force, so nothing ended: how many, and they're kept for the next try.
            let count = max(left.cards.count, notRevoked, 1)
            return (words("card.kiff_did_not_revoke_cards", ["cards_left": words.number(count)]), left.cards)
        } catch {
            return (CoachStart.why(error, words: words), cardsLeftBefore)
        }
        return (nil, [])
    }
}

extension CloudClient {
    /// Discards a taf being set up (`POST /v1/home/setting-up/{agent}/discard`, no body), with the security key's
    /// assertion over this exact request (`KeyAct.discardSettingUp`). KIFF still holding its Cards is `CardsInForce`.
    func discardSettingUp(_ agent: String, assertion: String) async throws {
        let headers = ["Authorization": "Bearer \(session.accessToken)", "Accept": "application/json",
                       "Accept-Language": language, "User-Agent": "tafs-macos", Passkeys.headerName: assertion]
        let (status, body) = try await transport.send(HTTPRequest(method: "POST", path: KeyAct.discardSettingUp(agent).path, headers: headers))
        if status == 409 {
            struct Refused: Decodable { let code: String?; let error: String?; let cards: [String]? }
            let refused = try? JSONDecoder().decode(Refused.self, from: body)
            if refused?.code == "cards_in_force" || refused?.error == "cards_in_force" { throw SettingUpDiscard.CardsInForce(cards: refused?.cards ?? []) }
        }
        guard (200..<300).contains(status) else { throw CloudRefusal(status: status, body: body) }
    }
}
