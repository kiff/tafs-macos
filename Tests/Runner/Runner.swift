import Foundation

/// One test: a name and what it checks. A part's tests are a list of these, `<part>Tests`
/// in `Tests/<part>/` and `<part>MacTests` in `Tests/<part>/mac/` (scripts/test.sh).
struct Test {
    let name: String
    let body: () throws -> Void
    init(_ name: String, _ body: @escaping () throws -> Void) { self.name = name; self.body = body }
}

struct Failure: Error, CustomStringConvertible {
    let description: String
}

func expect(_ condition: @autoclosure () throws -> Bool, _ what: @autoclosure () -> String = "",
            file: StaticString = #file, line: UInt = #line) throws {
    if try !condition() { throw Failure(description: "\(file):\(line): expected \(what())") }
}

func expectEqual<T: Equatable>(_ got: @autoclosure () throws -> T, _ want: @autoclosure () throws -> T,
                               file: StaticString = #file, line: UInt = #line) throws {
    let (g, w) = (try got(), try want())
    if g != w { throw Failure(description: "\(file):\(line): got \(g), want \(w)") }
}

/// Runs each suite and prints one line per test. Answers the number that failed.
func run(_ suites: [(name: String, tests: [Test])]) -> Int32 {
    var failed: Int32 = 0
    var count = 0
    for suite in suites {
        for test in suite.tests {
            count += 1
            do {
                try test.body()
                print("ok    \(suite.name): \(test.name)")
            } catch {
                failed += 1
                print("FAIL  \(suite.name): \(test.name)\n      \(error)")
            }
        }
    }
    print("\(count) tests, \(failed) failed")
    return failed
}
