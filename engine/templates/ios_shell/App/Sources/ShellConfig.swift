import UIKit

/// appbuilder-shell.json written by AppBuilder Engine (same file as in the Android shell).
struct ShellConfig: Decodable {
    let startUrl: String
    let fullscreen: Bool
    let themeColor: String
    let backgroundColor: String
    let openLinksExternally: Bool

    static func load() -> ShellConfig {
        guard
            let url = Bundle.main.url(forResource: "appbuilder-shell", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let config = try? JSONDecoder().decode(ShellConfig.self, from: data)
        else {
            return ShellConfig(
                startUrl: "index.html",
                fullscreen: false,
                themeColor: "#1565C0",
                backgroundColor: "#FFFFFF",
                openLinksExternally: true
            )
        }
        return config
    }
}

extension UIColor {
    /// `#RRGGBB`.
    convenience init(hex: String) {
        var value: UInt64 = 0
        Scanner(string: hex.trimmingCharacters(in: CharacterSet(charactersIn: "# "))).scanHexInt64(&value)
        self.init(
            red: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }

    var isLight: Bool {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return 0.299 * red + 0.587 * green + 0.114 * blue > 0.6
    }
}
