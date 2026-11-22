import Foundation

/// The first run after one sign-in, as the iPad's `Onboarding` (kiff/tafs `ios/Tafs/Model/Onboarding.swift`,
/// `docs/onboarding.md`; docs/pairing.md here): the welcome with one tick for the Terms, KIFF's sign-in in the
/// system's own sheet, three cards on how tafs works, and the first Home. While it's off, the welcome and the sign-in
/// are as they ship.
enum Onboarding {
    /// On in every build, as the iPad's since tafs#1708 (PM, kiff/work#20, 20:18). The download isn't published, and a
    /// live Mac sign-in pass on the test account comes before any release.
    static let on = true

    /// The three cards were seen on this Mac (Get started or Skip): they show once, after the first sign-in here,
    /// and How tafs works opens them again any time.
    static let cardsSeenKey = "tafs.onboarding-cards-seen"

    /// Whether the three cards follow the celebration after signing in.
    static func showsCards(on: Bool = Onboarding.on, seen: Bool) -> Bool { on && !seen }

    /// Whether Home with no taf is the first Home (Ask Coach and How tafs works): with the new onboarding on, for
    /// someone who may use Coach, whatever tafs cloud says there.
    static func showsFirstHome(on: Bool = Onboarding.on, mayUseCoach: Bool) -> Bool { on && mayUseCoach }

    /// The first Home's words: tafs cloud's own empty line when it sends one (its words come first), else the app's
    /// "No tafs yet" and what Coach does.
    static func firstHomeLines(cloud: String?, words: Words) -> (title: String, lead: String?) {
        if let cloud, !cloud.isEmpty { return (cloud, nil) }
        return (words("home.no_tafs"), words("onboarding.home_lead"))
    }

    /// Today's sign-in (the switch off): the country's own age only where it's above the standard (India, Indonesia,
    /// Brazil…), so a country that asks for more is told before signing in; anywhere else, nothing new is shown.
    static func raisedAgeLine(region: String?, ages: MinimumAge, words: Words) -> String? {
        let age = ages.of(region)
        return age > ages.standard ? words("onboarding.age_n", ["age": words.number(age)]) : nil
    }

    /// The welcome's age line for the person's country (this Mac's region): its own age where the law asks for more
    /// than the standard, else the line every country reads.
    static func ageLine(region: String?, ages: MinimumAge, words: Words) -> String {
        raisedAgeLine(region: region, ages: ages, words: words) ?? words("onboarding.age")
    }
}

/// The minimum age to use the app, by country (ISO 3166-1): legal-i18n's table, `app/strings/ages.json` at the pin,
/// which the iPad's `MinimumAge.swift` is generated from. Any other country, or none known, is `standard`.
struct MinimumAge: Equatable {
    let standard: Int
    let byCountry: [String: Int]

    /// The table as `ages.json` writes it: `"default"` and one age per country code.
    init(json: Data) throws {
        var all = try JSONDecoder().decode([String: Int].self, from: json)
        guard let standard = all.removeValue(forKey: "default") else { throw KIFFError.unreadable }
        self.standard = standard
        byCountry = all
    }

    /// The table in the shared words' folder (`strings/ages.json` in the app; `.shared/app/strings` in a test).
    init(folder: URL) throws { try self.init(json: Data(contentsOf: folder.appendingPathComponent("ages.json"))) }

    /// The age for a country code as `Locale.regionCode` gives it ("IN"), or `standard`.
    func of(_ country: String?) -> Int {
        guard let country else { return standard }
        return byCountry[country.uppercased()] ?? standard
    }
}

/// The welcome's one tick: the person agrees to KIFF's Terms and the tafs Terms before Continue. Privacy is linked
/// beside it, never ticked, and the AI consent is its own screen.
struct ConsentTick: Equatable {
    private(set) var agreed = false

    mutating func toggle() { agreed.toggle() }

    /// Continue opens the sign-in, and the phone's way its code, only once the Terms are agreed to.
    var canContinue: Bool { agreed }
}
