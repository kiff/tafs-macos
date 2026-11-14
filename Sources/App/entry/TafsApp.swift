import SwiftUI

@main
struct TafsApp: App {
    var body: some Scene {
        WindowGroup {
            ShellView().environment(\.words, Words.load())
        }
    }
}
