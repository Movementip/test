import SwiftUI
import UIKit

/// PostScript names read from the original APK font files; UIKit registers
/// these through UIAppFonts. Named roles follow Android TypeKt, not a blanket
/// replacement of every iOS navigation/accessibility font.
enum LaneTypography {
    static let allNames = ["Inter-Light", "Benzin-Regular", "Benzin-Semibold", "Manrope-Medium",
        "Archivo-Regular", "Benzin-ExtraBold", "NotoSerifDisplay-Regular", "FeatureMono-Medium",
        "RadioCanada-Medium", "DeathMohawkPERSONALUSE-Regular", "Montserrat-ExtraBold",
        "Roboto-Medium", "Manrope-Light", "Inter-Bold"]
    static func benzin(_ size: CGFloat) -> Font { .custom("Benzin-Regular", size: size, relativeTo: .headline) }
    static func title(_ size: CGFloat) -> Font { .custom("Inter-Bold", size: size, relativeTo: .headline) }
    static func manrope(_ size: CGFloat) -> Font { .custom("Manrope-Medium", size: size, relativeTo: .body) }
    static func light(_ size: CGFloat) -> Font { .custom("Manrope-Light", size: size, relativeTo: .body) }
    static func memorial(_ size: CGFloat) -> Font { .custom("NotoSerifDisplay-Regular", size: size, relativeTo: .title) }
}
