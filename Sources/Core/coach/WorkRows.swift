import Foundation

/// A run's steps as the iPad's `WorkLog.rows` lists them: what got done, with the tries of
/// one step folded into one row.
enum WorkRows {
    enum Status: Equatable {
        case done
        /// It failed.
        case error
        /// It was refused back unmade: not a failure, and not done.
        case notMade
    }

    struct Row: Equatable {
        let words: String
        let status: Status
        /// How many tries it took: more than one shows as "{n} tries".
        let tries: Int
    }

    /// Tries of the same step after a failed or unmade one are one row, with the last try's
    /// outcome: trying again until it works is normal. While the run works, every step that
    /// ended shows, a failed one in the failure colour: tafs cloud holds back a failure the taf
    /// goes on to fix, so one that reaches the app is one it chose to show (as on Android and
    /// the iPhone). Once the run ends, a failed step is left out once something worked; when
    /// nothing worked, the failures say why. A step not made and not tried again stays.
    static func rows(_ steps: [(words: String, status: Status)], running: Bool) -> [Row] {
        var groups: [[(words: String, status: Status)]] = []
        for step in steps {
            if let last = groups.last, last[0].words == step.words, [.error, .notMade].contains(last[last.count - 1].status) {
                groups[groups.count - 1].append(step)
            } else {
                groups.append([step])
            }
        }
        let rows = groups.map { Row(words: $0[0].words, status: $0[$0.count - 1].status, tries: $0.count) }
        return !running && rows.contains { $0.status == .done } ? rows.filter { $0.status != .error } : rows
    }
}

extension Thread.Work {
    /// The finished run's steps, folded.
    var rows: [WorkRows.Row] {
        WorkRows.rows(steps.map { ($0.words, $0.failed ? .error : $0.notMade ? .notMade : .done) }, running: false)
    }
}

extension LiveAnswer {
    /// The steps ended so far, folded. The step at work is the live line, never a row.
    var rows: [WorkRows.Row] {
        let ended = steps.filter { $0.done || $0.notMade }
        return WorkRows.rows(ended.map { ($0.words, $0.failed ? .error : $0.notMade ? .notMade : .done) }, running: true)
    }
}
