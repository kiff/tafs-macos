import SwiftUI

/// The window's two panes, to the iPad app's layout: the sidebar on the raised ground, and
/// what it opens beside it on the background. The sidebar's items and each screen arrive
/// with their words; until then the shell shows only the app's name.
struct ShellView: View {
    static let sidebarWidth: CGFloat = 300
    static let minimumSize = CGSize(width: 900, height: 600)

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: Self.sidebarWidth)
                .frame(maxHeight: .infinity, alignment: .top)
                .background(Theme.raised)
            Rectangle().fill(Theme.line).frame(width: 1)
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.background)
        }
        .frame(minWidth: Self.minimumSize.width, minHeight: Self.minimumSize.height)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: "tafs")
                .font(Theme.display(28))
                .foregroundColor(Theme.ink)
                .padding(.horizontal, 20)
                .padding(.top, 20)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var detail: some View {
        Circle().fill(Theme.brand).frame(width: 72, height: 72).accessibilityHidden(true)
    }
}
