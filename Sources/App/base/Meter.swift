import SwiftUI

/// The iPad's meter: a 5-high capsule of ink at 10%, filled in its colour to its fraction,
/// kept within 0 to 1.
struct Meter: View {
    let fraction: Double
    var color: Color = Theme.ok

    var body: some View {
        GeometryReader { space in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.ink.opacity(0.1))
                Capsule().fill(color).frame(width: space.size.width * CGFloat(min(max(fraction, 0), 1)))
            }
        }
        .frame(height: 5)
    }
}
