import SwiftUI

/// What Account changes besides the theme, each as the iPad's `AppModel` does it: Coach's
/// suggestions, the AI-data consent and the account's time zone.
extension AccountModel {
    /// The rows tafs cloud words: Coach's suggestions and the AI-data consent, as the iPad's
    /// `loadSuggestions()` and its consent read. A read that fails keeps what was read.
    func loadSettings() async {
        let cloud = self.cloud
        if let read = try? await cloud.suggestions() { suggestions = read }
        if let read = try? await cloud.aiConsent() { consent = read }
    }

    /// Turns the account's suggestions off for good, or on again, as the iPad's
    /// `setSuggestions(_:)`: a refusal is said in tafs cloud's words.
    func setSuggestions(_ show: Bool, words: Words) async {
        guard !suggestionsBusy else { return }
        suggestionsBusy = true
        suggestionsError = nil
        let cloud = self.cloud
        do {
            suggestions = try await cloud.setSuggestions(show)
        } catch {
            suggestionsError = words("settings.suggestions_not_changed", ["why": CoachStart.why(error, words: words)])
        }
        suggestionsBusy = false
    }

    /// The consent's screen, from the AI use row while it isn't given, as the iPad's
    /// `consentRequired(_:)`.
    func askConsent() {
        consentError = nil
        consentAsked = consent
    }

    /// Allow, on the consent's screen, as the iPad's `allowAI()`: sent with the version of the
    /// words read. Words changed meanwhile come back, to be read again.
    func allowAI(words: Words) async {
        guard let asked = consentAsked, !consentBusy else { return }
        consentBusy = true
        let version = asked.version
        let cloud = self.cloud
        do {
            var given = try await cloud.giveAIConsent(version: version)
            if given == nil { given = try? await cloud.aiConsent() }
            if let given { consent = given }
            consentError = nil
            consentAsked = nil
        } catch let refusal as CloudRefusal where refusal.status == 409 {
            consentError = refusal.why(words)
            var newer = refusal.consent
            if newer == nil { newer = try? await cloud.aiConsent() }
            if let newer {
                consent = newer
                consentAsked = newer
            }
        } catch {
            consentError = CoachStart.why(error, words: words)
        }
        consentBusy = false
    }

    /// Not now: the screen closes, and nothing is sent, as the iPad's `notNowAI()`.
    func notNowAI() {
        consentAsked = nil
        consentError = nil
    }

    /// Withdraw, from Account, as the iPad's `withdrawAI()`: from then on, nothing this person
    /// writes reaches the model.
    func withdrawAI(words: Words) async {
        guard !consentBusy else { return }
        consentBusy = true
        let cloud = self.cloud
        do {
            consent = try await cloud.withdrawAI()
            consentError = nil
        } catch {
            consentError = CoachStart.why(error, words: words)
        }
        consentBusy = false
    }

    /// The picker's zones for a search, as the iPad's `loadTimeZones(_:)`: only the newest
    /// search's answer is kept.
    func loadZones(_ query: String, words: Words) async {
        zoneQuery = query
        let cloud = self.cloud
        do {
            let read = try await cloud.timeZones(query)
            if zoneQuery == query { zones = read }
        } catch {
            zoneError = CoachStart.why(error, words: words)
        }
    }

    /// Saves the account's time zone, as the iPad's `setAccountTimeZone(_:)` (`AccountZone.save`):
    /// confirmed, signed by the device key, then read again.
    func saveZone(_ zone: String, words: Words) async {
        guard !savingZone else { return }
        savingZone = true
        zoneError = nil
        let account = self.account, cloud = self.cloud, confirm = self.confirm, approveWithKey = self.approveWithKey
        let saved = await AccountZone.save(zone, account: account, cloud: cloud, words: words, confirm: confirm, approveWithKey: approveWithKey)
        if let me = saved.me { took(me) }
        zoneError = saved.why
        savingZone = false
    }

    /// The account's zone, as KIFF holds it: UTC when it hasn't said.
    var zone: String { AccountZone.current(me) }
}
