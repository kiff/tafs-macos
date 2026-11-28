import Foundation

/// A saved sign-in that needs the owner, as Home lists it for Needs you (`sign_ins` on `GET /v1/home`; tafs docs/api.md,
/// "Needs you, and the run that waits"): soon (`sign_in_soon`, with Later), or stopped, holding a run before it starts
/// (`sign_in_stopped`, with Skip this run). Every word is tafs cloud's; the app works out nothing, not "soon", not when a
/// run waits.
struct SignInNeed: Decodable, Equatable, Identifiable {
    /// `sign_in_soon` or `sign_in_stopped`.
    let kind: String
    let grant: String
    let site: String
    let taf: Taf
    let words: Words

    /// Per taf: two tafs held on one site are two items, each with its own run and its own Skip.
    var id: String { kind + "|" + grant + "|" + site + "|" + taf.id }
    var stopped: Bool { kind == "sign_in_stopped" }

    struct Taf: Decodable, Equatable {
        let id: String
        let name: String
    }

    struct Words: Equatable {
        let title: String
        let line: String
        /// Sign in again's words.
        let signIn: String
        /// Later (soon) or Skip this run (stopped): the other button's words.
        let other: String
        let why: String?

    }

    fileprivate enum WordKeys: String, CodingKey { case title, line, signIn = "sign_in", later, skip, why }

    enum CodingKeys: String, CodingKey { case kind, grant, site, taf, words }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decode(String.self, forKey: .kind)
        guard kind == "sign_in_soon" || kind == "sign_in_stopped" else {
            throw DecodingError.dataCorruptedError(forKey: .kind, in: c, debugDescription: "a kind this app doesn't draw")
        }
        func text(_ s: String?) -> String? { s.flatMap(BrowserWays.shown) }
        guard let grant = text(try c.decode(String.self, forKey: .grant)), let site = text(try c.decode(String.self, forKey: .site)) else {
            throw DecodingError.dataCorruptedError(forKey: .site, in: c, debugDescription: "no connection or site")
        }
        self.grant = grant
        self.site = site
        taf = try c.decode(Taf.self, forKey: .taf)
        // Without its taf there's no run to skip and no one to name: left out, as the Android app does.
        guard !taf.id.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw DecodingError.dataCorruptedError(forKey: .taf, in: c, debugDescription: "a sign-in item with no taf")
        }
        let w = try c.nestedContainer(keyedBy: WordKeys.self, forKey: .words)
        func word(_ key: WordKeys) -> String? { text((try? w.decodeIfPresent(String.self, forKey: key)) ?? nil) }
        // Without its title, its line and Sign in again, there's nothing to draw: it would have to be worded here.
        // Its other button (Later, or Skip this run) is half of what the item is: without it, it's left out, as on Android.
        guard let title = word(.title), let line = word(.line), let signIn = word(.signIn),
              let other = word(kind == "sign_in_stopped" ? .skip : .later) else {
            throw DecodingError.dataCorruptedError(forKey: .words, in: c, debugDescription: "a sign-in item with no words")
        }
        words = Words(title: title, line: line, signIn: signIn, other: other, why: word(.why))
    }

    /// Home's list, each read on its own: one that doesn't read is left out, never the rest.
    static func listed<K: CodingKey>(_ c: KeyedDecodingContainer<K>, _ key: K) -> [SignInNeed] {
        (((try? c.decodeIfPresent([LenientSignInNeed].self, forKey: key)) ?? nil) ?? []).compactMap(\.item)
    }
}

/// One of Home's sign-in items, read without failing the list.
private struct LenientSignInNeed: Decodable {
    let item: SignInNeed?
    init(from decoder: Decoder) throws { item = try? SignInNeed(from: decoder) }
}

extension CloudClient {
    /// Later, on a sign-in that needs the owner soon: it's hidden for everyone on the account until the next check
    /// (`POST /v1/needs-you/sign-in/{grant}/{site}/later`, the person's session).
    func laterSignIn(grant: String, site: String) async throws {
        _ = try await post("/v1/needs-you/sign-in/\(Self.escaped(grant))/\(Self.escaped(site))/later", [:])
    }

    /// Skip this run, on a sign-in that stopped and holds a run: that run is dropped, and the schedules come back from the
    /// next one (`POST /v1/tafs/{id}/held-sign-in/skip`, the person's session).
    func skipHeldSignIn(taf: String) async throws {
        _ = try await post("/v1/tafs/\(Self.escaped(taf))/held-sign-in/skip", [:])
    }
}
