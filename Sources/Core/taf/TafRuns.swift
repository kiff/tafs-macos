import Foundation

/// The runs a taf kept (`GET /v1/tafs/{id}/work/runs`), as the iPad's `RunsPage` with
/// `TafWork.Request`, `Delivery`, `Skipped` and `Row`: each run in tafs cloud's words, and on
/// the first page the firings that started no run. The app words nothing here.
enum TafRuns {
    /// One run: done, working, retrying, needs_you, waiting, stopped or failed, in tafs cloud's
    /// words, with where its result went.
    struct Request: Decodable, Equatable, Identifiable {
        let id: String
        let at: Date
        var state = ""
        var line = ""
        var deliveries: [Delivery] = []
        /// A step the taf handed its owner, which this request waits on (`your_step`, the iPad's
        /// `TafWork.Request.yourStep`): its card stands in place of the line. One that doesn't read
        /// is none, never the request.
        var yourStep: YourStep? = nil
        /// What the run used, from KIFF's usage record, in tafs cloud's words. Nil until KIFF
        /// has counted the run. The app counts nothing.
        var credits: Credits? = nil

        struct Credits: Decodable, Equatable {
            var credits: Int64?
            var counted: Bool?
            var words: String?
        }

        /// The line under the run's own: tafs cloud's words for what it used, as sent; none for
        /// a run not counted yet, or with no words.
        var creditsLine: String? {
            guard let words = credits?.words?.trimmingCharacters(in: .whitespacesAndNewlines), !words.isEmpty else { return nil }
            return words
        }

        enum CodingKeys: String, CodingKey { case id, at, state, line, deliveries, credits, yourStep = "your_step" }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            at = try c.decode(Date.self, forKey: .at)
            state = (try? c.decode(String.self, forKey: .state)) ?? ""
            line = (try? c.decode(String.self, forKey: .line)) ?? ""
            deliveries = (try? c.decode([Delivery].self, forKey: .deliveries)) ?? []
            // A figure KIFF hasn't counted, or one the app can't read, is no line: never a guess.
            credits = try? c.decodeIfPresent(Credits.self, forKey: .credits)
            yourStep = (try? c.decodeIfPresent(YourStep.self, forKey: .yourStep)) ?? nil
        }
    }

    /// Where a run's result went, in tafs cloud's words.
    struct Delivery: Decodable, Equatable {
        var place = "door_reply"
        /// A place of the taf's own, as tafs cloud names it; none for a door's reply.
        var key: String?
        var state = ""
        var line = ""
        var sendAgain = false

        enum CodingKeys: String, CodingKey { case place, key, state, line, sendAgain = "send_again" }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            place = (try? c.decode(String.self, forKey: .place)) ?? "door_reply"
            key = try? c.decode(String.self, forKey: .key)
            state = (try? c.decode(String.self, forKey: .state)) ?? ""
            line = (try? c.decode(String.self, forKey: .line)) ?? ""
            sendAgain = (try? c.decode(Bool.self, forKey: .sendAgain)) ?? false
        }
    }

    /// A scheduled run that was skipped: when it was due, why (missed or busy), and tafs
    /// cloud's words for it. Not a failure: nothing ran. Each field is needed, as the iPad's
    /// synthesized reader needs it.
    struct Skipped: Decodable, Equatable {
        let due: Date
        var why = ""
        var words = ""

        enum CodingKeys: String, CodingKey { case due, why, words }
        init(due: Date, why: String = "", words: String = "") { self.due = due; self.why = why; self.words = words }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            due = try c.decode(Date.self, forKey: .due)
            why = try c.decode(String.self, forKey: .why)
            words = try c.decode(String.self, forKey: .words)
        }
    }

    /// A row: a run, or a scheduled run that was skipped.
    enum Row: Equatable, Identifiable {
        case request(Request)
        case skipped(Skipped)

        var at: Date {
            switch self {
            case .request(let r): return r.at
            case .skipped(let s): return s.due
            }
        }

        var id: String {
            switch self {
            case .request(let r): return "r|" + r.id
            case .skipped(let s): return "s|\(s.due.timeIntervalSince1970)"
            }
        }
    }

    /// One page, as the iPad's synthesized `RunsPage`: its runs, its cursor, tafs cloud's
    /// heading and its "see all" line are needed; its end and its skipped firings aren't.
    struct Page: Decodable, Equatable {
        let requests: [Request]
        let nextCursor: String?
        let title: String
        let moreTitle: String
        var endWords: String? = nil
        /// On the first page: recent firings that started no run.
        var skipped: [Skipped]? = nil

        enum CodingKeys: String, CodingKey {
            case requests, title, skipped
            case nextCursor = "next_cursor", moreTitle = "more_title", endWords = "end_words"
        }

        /// The page's rows, newest first: its runs and, on the first page, the firings that
        /// started no run, each in its place by time; at the same time, in the order sent.
        func rows(first: Bool) -> [Row] {
            let runs = requests.map(Row.request)
            guard first, let skipped, !skipped.isEmpty else { return runs }
            return (runs + skipped.map(Row.skipped)).enumerated()
                .sorted { $0.element.at != $1.element.at ? $0.element.at > $1.element.at : $0.offset < $1.offset }
                .map(\.element)
        }
    }

    /// The pages read for one list, as the iPad's `SourcePages`.
    struct Pages: Equatable {
        var pages: [Page] = []
        var etag: String?
        var loading = false
        var moreWhenReady = false
        var error: String?
    }

    /// What Run now answered, as the iPad's `RunNow`: the run it started, or tafs cloud's
    /// words for why it started none.
    struct RunNow: Equatable {
        let session: String?
        let words: String?
    }

    /// How many runs the panel shows, and how many a page of all of them holds.
    static func limit(all: Bool) -> Int { all ? 20 : 3 }
}

extension CloudClient {
    /// A page of the runs a taf kept. Read again with the last `etag`, a 304 answers no page:
    /// nothing changed. A refusal throws tafs cloud's, for its words.
    func runsPage(of taf: String, cursor: String?, etag: String?, limit: Int) async throws -> (TafRuns.Page?, String?) {
        let path = "/v1/tafs/\(Self.escaped(taf))/work/runs?limit=\(limit)" + (cursor.map { "&cursor=\(Self.query($0))" } ?? "")
        var headers = ["Authorization": "Bearer \(session.accessToken)", "Accept": "application/json",
                       "Accept-Language": language, "User-Agent": "tafs-macos"]
        if let etag { headers["If-None-Match"] = etag }
        let (status, body, sent) = try await transport.exchange(HTTPRequest(method: "GET", path: path, headers: headers))
        let tag = sent ?? etag
        if status == 304 { return (nil, tag) }
        guard (200..<300).contains(status) else { throw CloudRefusal(status: status, body: body) }
        guard let page = try? AccountClient.decoder.decode(TafRuns.Page.self, from: body) else { throw KIFFError.unreadable }
        return (page, tag)
    }

    /// Runs the taf now (`POST /v1/tafs/{id}/run`). Nothing is signed: it acts within the taf's
    /// Card. tafs cloud's words come only when it started no run.
    func runNow(_ taf: String) async throws -> TafRuns.RunNow {
        struct Answer: Decodable { let session: String?; let words: String? }
        let body = try await post("/v1/tafs/\(Self.escaped(taf))/run", [:])
        guard let answer = try? JSONDecoder().decode(Answer.self, from: body) else { throw KIFFError.unreadable }
        let words = answer.session == nil ? answer.words.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 } : nil
        return TafRuns.RunNow(session: answer.session, words: words)
    }
}
