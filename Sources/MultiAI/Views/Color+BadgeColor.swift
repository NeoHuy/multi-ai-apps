import MultiAICore
import SwiftUI

extension BadgeColor {
    var swiftUIColor: Color {
        let c = rgb
        return Color(red: c.r, green: c.g, blue: c.b)
    }
}
