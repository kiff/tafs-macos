import SwiftUI

/// What opens a taf's page on its chat, as the iPad's `model.requestedTaf` (HomeSplitView.swift:205-209):
/// the shell's own `open`, set on the screen it draws (`ShellView`), so the Record's sheets reach it
/// without the shell knowing them. Nil where no shell set it: nothing offers to open a taf there.
private struct OpenTafKey: EnvironmentKey {
    static let defaultValue: ((Home.Taf) -> Void)? = nil
}

extension EnvironmentValues {
    var openTaf: ((Home.Taf) -> Void)? {
        get { self[OpenTafKey.self] }
        set { self[OpenTafKey.self] = newValue }
    }
}
