import SwiftUI
import AppKit

// MARK: - Detto Color Tokens

extension Color {
    private static var dark: Bool { UserDefaults.standard.bool(forKey: "darkMode") }

    static var dBg: Color       { dark ? Color(red: 0.098, green: 0.098, blue: 0.098)   // #191919
                                       : Color(red: 0.992, green: 0.984, blue: 0.969) }  // #fdfbf7
    static var dSurface: Color  { dark ? Color(red: 0.137, green: 0.137, blue: 0.137)   // #232323
                                       : Color(red: 0.961, green: 0.941, blue: 0.910) }  // #f5f0e8
    static var dTitlebar: Color { dark ? Color(red: 0.059, green: 0.059, blue: 0.059)   // #0f0f0f
                                       : Color(red: 0.039, green: 0.039, blue: 0.039) }  // #0a0a0a
    static var dAmber: Color    { dark ? Color(red: 0.878, green: 0.573, blue: 0.200)   // #e09233
                                       : Color(red: 0.788, green: 0.490, blue: 0.114) }  // #c97d1d
    static var dGreen: Color    { dark ? Color(red: 0.180, green: 0.588, blue: 0.380)   // #2e9661
                                       : Color(red: 0.102, green: 0.478, blue: 0.290) }  // #1a7a4a
    static var dRed: Color      { dark ? Color(red: 0.850, green: 0.318, blue: 0.263)   // #d95143
                                       : Color(red: 0.753, green: 0.224, blue: 0.169) }  // #c0392b
    static var dText: Color     { dark ? Color(red: 0.878, green: 0.878, blue: 0.878)   // #e0e0e0
                                       : Color(red: 0.102, green: 0.102, blue: 0.102) }  // #1a1a1a
    static var dSecondary: Color{ dark ? Color(red: 0.550, green: 0.550, blue: 0.550)   // #8c8c8c
                                       : Color(red: 0.400, green: 0.400, blue: 0.400) }  // #666666
    static var dDim: Color      { dark ? Color(red: 0.440, green: 0.440, blue: 0.440)   // #707070
                                       : Color(red: 0.600, green: 0.600, blue: 0.600) }  // #999999
    static var dRule: Color     { dark ? Color(red: 0.200, green: 0.200, blue: 0.200)   // #333333
                                       : Color(red: 0.894, green: 0.894, blue: 0.878) }  // #e4e4e0
    static var dBubble: Color   { dark ? Color(red: 0.165, green: 0.165, blue: 0.165)   // #2a2a2a
                                       : Color.white }
    static var dTeal: Color     { dark ? Color(red: 0.180, green: 0.541, blue: 0.541)   // #2e8a8a
                                       : Color(red: 0.102, green: 0.420, blue: 0.420) }  // #1a6b6b
    static var dBlue: Color     { dark ? Color(red: 0.290, green: 0.498, blue: 0.749)   // #4a7fbf
                                       : Color(red: 0.180, green: 0.400, blue: 0.600) }  // #2e6699
}

// MARK: - Detto Fonts

extension Font {
    static func dMono(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        Font.custom("Azeret Mono", size: size).weight(weight)
    }

    static func dBody(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        Font.custom("Plus Jakarta Sans", size: size).weight(weight)
    }

    static func dDisplay(size: CGFloat) -> Font {
        Font.custom("Plus Jakarta Sans", size: size).weight(.heavy)
    }
}

// MARK: - Font Registration

@MainActor
enum DettoTheme {
    private static var fontsRegistered = false

    static func registerFonts() {
        guard !fontsRegistered else { return }
        fontsRegistered = true

        guard let resourceURL = Bundle.main.resourceURL else { return }
        let fontsURL = resourceURL.appendingPathComponent("Fonts")

        guard let enumerator = FileManager.default.enumerator(
            at: fontsURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return }

        for case let fileURL as URL in enumerator where fileURL.pathExtension == "ttf" {
            CTFontManagerRegisterFontsForURL(fileURL as CFURL, .process, nil)
        }
    }
}

// MARK: - Wordmark

struct DettoWordmark: View {
    var size: CGFloat = 14

    var body: some View {
        HStack(spacing: 0) {
            Text("DE")
                .foregroundStyle(Color.dText)
            Text("TT")
                .foregroundStyle(Color.dAmber)
            Text("O")
                .foregroundStyle(Color.dText)
        }
        .font(.dMono(size: size, weight: .black))
        .tracking(2)
    }
}

// MARK: - Card Modifier

struct DettoCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.dText, lineWidth: 2.5)
            )
    }
}

extension View {
    func dettoCard() -> some View {
        modifier(DettoCardModifier())
    }
}
