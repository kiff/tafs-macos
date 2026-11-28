import AppKit
import SwiftUI
import WebKit

/// planque's live sign-in view for a cloud browser connection (Sign in again, browser batch 2), as Android's
/// `SiteSignInScreen`. The owner signs in to the site themselves; tafs keeps only what the site keeps, sealed at planque.
/// What holds here:
/// - it opens only a view on planque's own https origin (`SiteSignInView.opens`), asked for fresh each time;
/// - its web data lives in memory only (`.nonPersistent()`), so nothing reaches disk and nothing is left once it closes;
/// - it follows nothing off planque's origin, redirects included, opens no window, and downloads nothing;
/// - nothing of the app reaches the page: no message handler and no script of the app's own;
/// - over it are planque's words and Close, and nothing else. Closing leaves the view to lapse at planque.
struct SiteSignInSheet: View {
    @Environment(\.words) private var words
    let view: SiteSignInView
    let close: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text(verbatim: view.words ?? "").font(.system(size: 13)).foregroundColor(Theme.soft)
                    .lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                Button(words("common.close"), action: close)
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("site-sign-in.close")
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            Rectangle().fill(Theme.line).frame(height: 1)
            if view.opens {
                PlanqueWebView(url: view.view)
            } else {
                // Never opened: a view that isn't on planque's own origin.
                Spacer()
            }
        }
        .frame(minWidth: 760, idealWidth: 900, minHeight: 600, idealHeight: 720)
        .background(Theme.background)
    }
}

/// The web view under the sheet, held to planque's origin (`SiteSignInGuard`).
struct PlanqueWebView: NSViewRepresentable {
    let url: URL

    func makeCoordinator() -> SiteSignInGuard { SiteSignInGuard(origin: url) }

    func makeNSView(context: Context) -> WKWebView {
        let web = QuietWebView(frame: .zero, configuration: SiteSignInGuard.configuration())
        web.navigationDelegate = context.coordinator
        web.uiDelegate = context.coordinator
        web.allowsLinkPreview = false
        web.load(URLRequest(url: url))
        return web
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    static func dismantleNSView(_ nsView: WKWebView, coordinator: SiteSignInGuard) {
        nsView.stopLoading()
        nsView.navigationDelegate = nil
        nsView.uiDelegate = nil
    }
}

/// A web view with no context menu: no Open Link, Download or Open in browser.
final class QuietWebView: WKWebView {
    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        menu.removeAllItems()
    }
}

/// What the sign-in view may do: stay on planque's origin, open no window, download nothing.
final class SiteSignInGuard: NSObject, WKNavigationDelegate, WKUIDelegate {
    let origin: URL

    init(origin: URL) { self.origin = origin }

    /// A configuration whose web data lives in memory only, with no message handler and no script of the app's.
    static func configuration() -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController = WKUserContentController()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        return configuration
    }

    /// Whether a navigation may go: on planque's own https origin, and never a download.
    func allows(_ url: URL?, download: Bool = false) -> Bool {
        guard !download, let url else { return false }
        // `about:blank` frames the page itself makes stay inside the view; anything else must be planque's.
        if url.absoluteString == "about:blank" { return true }
        return SiteSignInView.sameHTTPSOrigin(url, origin)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        decisionHandler(allows(navigationAction.request.url, download: navigationAction.shouldPerformDownload) ? .allow : .cancel)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        // A response the view can't show is a download: refused.
        decisionHandler(navigationResponse.canShowMIMEType && allows(navigationResponse.response.url) ? .allow : .cancel)
    }

    func webView(_ webView: WKWebView, didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!) {
        // A redirect off planque's origin stops where it is.
        if !allows(webView.url) { webView.stopLoading() }
    }

    /// No pop-ups: a page that asks for a new window gets none.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        nil
    }
}
