import Foundation

/// Where a taf's work stands, as tafs cloud says it (`GET /v1/tafs/{id}/work`, docs/reliability.md), as the iPad's
/// `TafsCloud.TafWork`: its line, its recent requests and skipped firings, its health, its oldest waiting case and
/// the owner's promise. Every line and time is tafs cloud's, in the account's zone: the app formats none. A request,
/// its deliveries and a skipped firing read as a kept run's (`TafRuns`).
struct TafWork: Decodable, Equatable {
    /// Its oldest waiting case, in tafs cloud's words ("Oldest case waiting 5 h"), and whether it's past the owner's
    /// promise. Sent only while a case waits.
    struct OldestWaiting: Decodable, Equatable {
        var words = ""
        var late = false

        private enum CodingKeys: String, CodingKey { case words, late }
        init(words: String = "", late: Bool = false) { self.words = words; self.late = late }
        init(from decoder: Decoder) throws {
            guard let c = try? decoder.container(keyedBy: CodingKeys.self) else { return }
            words = (try? c.decode(String.self, forKey: .words)) ?? ""
            late = (try? c.decode(Bool.self, forKey: .late)) ?? false
        }
    }

    /// Its summary's line, as sent; nil when tafs cloud said none.
    var line: String?
    var requests: [TafRuns.Request] = []
    var skipped: [TafRuns.Skipped] = []
    /// Its health, when tafs cloud could read it in time.
    var health: Home.Taf.Health?
    var oldestWaiting: OldestWaiting?
    /// The owner's promise: how many whole hours a case may wait before the phones that answer its holds are told.
    /// Nil when none is set.
    var promiseHours: Int?

    private struct Summary: Decodable { let line: String? }
    private struct Promise: Decodable { let hours: Int }
    private enum CodingKeys: String, CodingKey { case summary, requests, skipped, health, oldestWaiting = "oldest_waiting", promise }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        line = ((try? c.decodeIfPresent(Summary.self, forKey: .summary)) ?? nil)?.line
            .flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
        requests = (try? c.decode([TafRuns.Request].self, forKey: .requests)) ?? []
        // An older tafs cloud sends none.
        skipped = (try? c.decode([TafRuns.Skipped].self, forKey: .skipped)) ?? []
        health = (try? c.decodeIfPresent(Home.Taf.Health.self, forKey: .health)) ?? nil
        // Neither ever fails the read: a line that isn't one is none.
        oldestWaiting = ((try? c.decodeIfPresent(OldestWaiting.self, forKey: .oldestWaiting)) ?? nil)
            .flatMap { $0.words.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
        promiseHours = ((try? c.decodeIfPresent(Promise.self, forKey: .promise)) ?? nil).map(\.hours).flatMap { $0 > 0 ? $0 : nil }
    }

    /// The requests and skipped firings, each in its own place by time, newest first.
    var rows: [TafRuns.Row] {
        (requests.map(TafRuns.Row.request) + skipped.map(TafRuns.Row.skipped)).sorted { $0.at > $1.at }
    }

    /// The requests whose reply was given up on after its tries (a delivery tafs cloud marks
    /// `send_again`), newest first: Results go to's Not sent, as the iPad's `notSent`.
    var unsent: [TafRuns.Request] {
        rows.compactMap { row in
            if case .request(let r) = row, r.deliveries.contains(where: \.sendAgain) { return r }
            return nil
        }
    }

    /// The line to draw above its health: none when it's the health's first reason, as tafs cloud says it on an idle
    /// taf ("…, so nothing ran"), so the page says it once.
    func shownLine(health: Home.Taf.Health?) -> String? {
        guard let line else { return nil }
        if let health, health.needsAttention, let first = health.lines.first, first.hasPrefix(line) { return nil }
        return line
    }

    /// The hours a case may wait, as the owner picks them; tafs cloud checks the range (1 to 168).
    static let promiseChoices = [1, 2, 4, 8, 24, 48, 168]

    /// A promise in words: whole days as days (24 h is "1 day", 168 h "7 days"), anything else in hours; none is
    /// "Not set". tafs cloud gets hours all the same.
    static func promise(_ hours: Int?, words: Words) -> String {
        guard let hours else { return words("work.answer_within_none") }
        return hours >= 24 && hours % 24 == 0
            ? words.count("work.answer_within_days", hours / 24)
            : words.count("work.answer_within_hours", hours)
    }
}

extension TafWork {
    /// What went wrong under the work, as the iPad's `workErrors`: its read, the promise, or a Send again, each with why.
    enum Failure: Equatable {
        case notRead(why: String)
        case promiseNotSet(why: String)
        case notSentAgain(why: String)

        func line(_ words: Words) -> String {
            switch self {
            case .notRead(let why): return words("work.not_read", ["why": why])
            case .promiseNotSet(let why): return words("work.answer_within_not_set", ["why": why])
            case .notSentAgain(let why): return words("work.not_sent_again", ["why": why])
            }
        }
    }
}

extension TafRuns.Delivery {
    /// What Send again names in its route (docs/api.md): the door's reply, or the place's own key.
    var sendPlace: String { place == "door_reply" ? "door_reply" : (key ?? "door_reply") }
}

extension CloudClient {
    /// Where the taf's work stands (docs/reliability.md, "The taf's view").
    func work(of taf: String) async throws -> TafWork {
        try await get("/v1/tafs/\(Self.escaped(taf))/work", saying: true)
    }

    /// The owner's promise (`PUT …/promise`, for whoever may change its Cards): whole hours, or nil to clear it, sent
    /// as `{"hours": null}`. tafs cloud checks the range and keeps it; the app keeps no copy.
    func setPromise(of taf: String, hours: Int?) async throws {
        struct Body: Encodable {
            let hours: Int?
            enum CodingKeys: String, CodingKey { case hours }
            func encode(to encoder: Encoder) throws {
                var c = encoder.container(keyedBy: CodingKeys.self)
                if let hours { try c.encode(hours, forKey: .hours) } else { try c.encodeNil(forKey: .hours) }
            }
        }
        _ = try await send("PUT", "/v1/tafs/\(Self.escaped(taf))/promise", body: Body(hours: hours))
    }

    /// Send again: a reply given up on after its tries, or a place of the taf's own not delivered, goes once more.
    /// It does no work and signs nothing.
    func sendAgain(of taf: String, run: String, place: String) async throws {
        _ = try await post("/v1/tafs/\(Self.escaped(taf))/requests/\(Self.escaped(run))/deliveries/\(Self.escaped(place))/send", [:])
    }
}
