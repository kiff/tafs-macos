import Foundation
import WebKit

/// Sign in again's live view (browser batch 2): held to planque's own origin, with nothing kept and nothing of the app's
/// in the page (the security read's six points).
let siteSignInMacTests: [Test] = [
    Test("the view keeps nothing: its web data lives in memory only, with no message handler and no script of the app's", awaiting: { @MainActor in
        let configuration = SiteSignInGuard.configuration()
        try expect(!configuration.websiteDataStore.isPersistent, "non-persistent data store")
        try expect(configuration.userContentController.userScripts.isEmpty, "no script of the app's")
        try expect(!configuration.preferences.javaScriptCanOpenWindowsAutomatically, "no window opened by script")
    }),
    Test("navigation stays on planque's own https origin: anywhere else, a redirect included, and any download is cancelled", awaiting: { @MainActor in
        let guardian = SiteSignInGuard(origin: URL(string: "https://planque.kiff.dev/v/abc")!)
        try expect(guardian.allows(URL(string: "https://planque.kiff.dev/v/abc/next")), "planque")
        try expect(guardian.allows(URL(string: "about:blank")), "the page's own blank frame")
        try expect(!guardian.allows(URL(string: "https://supplier-portal.example/login")), "the site itself, outside the view's frame")
        try expect(!guardian.allows(URL(string: "https://planque.kiff.dev.evil.example/")), "a suffix")
        try expect(!guardian.allows(URL(string: "http://planque.kiff.dev/v/abc")), "not https")
        try expect(!guardian.allows(nil), "no URL")
        try expect(!guardian.allows(URL(string: "https://planque.kiff.dev/file.pdf"), download: true), "a download, even from planque")
    }),
    Test("a page that asks for a new window gets none", awaiting: { @MainActor in
        let guardian = SiteSignInGuard(origin: URL(string: "https://planque.kiff.dev/v/abc")!)
        let web = WKWebView(frame: .zero, configuration: SiteSignInGuard.configuration())
        let popup = guardian.webView(web, createWebViewWith: WKWebViewConfiguration(), for: WKNavigationAction(), windowFeatures: WKWindowFeatures())
        try expect(popup == nil, "no pop-up")
    }),
    Test("a view that isn't on planque's own origin is never opened", awaiting: { @MainActor in
        let off = try JSONDecoder().decode(SiteSignInView.self, from: Data(#"{"view":"https://evil.example/v/1","words":"Sign in"}"#.utf8))
        try expect(!off.opens, "not opened")
        let model = ConnectAppsModel(cloud: CloudClient(transport: CannedTransport([]), session: Session(accessToken: "t", expiresIn: 60, tenant: "t1", subject: "u1", deviceID: nil)))
        model.siteSignIn = { _ in off }
        let json = #"{"grant":"g_web","site":"s.example","sign_in":{"title":"Sign in again"}}"#
        let item = try AccountClient.decoder.decode(BrowserWays.SavedSignIn.self, from: Data(json.utf8))
        await model.signIn(item)
        try expect(model.signInView == nil, "no sheet")
        try expect(model.signInProblem[item.id] != nil, "it says so")
    }),
]
