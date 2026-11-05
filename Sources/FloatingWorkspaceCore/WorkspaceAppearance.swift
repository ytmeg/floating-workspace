import AppKit

public struct WorkspacePalette {
    public let gradientColors: [NSColor]
    public let solidBackgroundColor: NSColor
    public let contentBackgroundColor: NSColor
    public let railBackgroundColor: NSColor
    public let accentColor: NSColor
    public let borderColor: NSColor
    public let usesTransparency: Bool
}

public enum WorkspaceAppearance {
    @MainActor public static var acceptanceReduceTransparency: Bool?
    @MainActor public static var acceptanceIncreaseContrast: Bool?

    public static func make(
        appearance: NSAppearance,
        reduceTransparency: Bool,
        increaseContrast: Bool
    ) -> WorkspacePalette {
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua

        if isDark {
            let background = color(0x121926, alpha: 0.64)
            return WorkspacePalette(
                gradientColors: reduceTransparency ? [] : [background, background],
                solidBackgroundColor: color(0x121926, alpha: 1),
                contentBackgroundColor: color(0x1D2635, alpha: reduceTransparency ? 1 : 0.94),
                railBackgroundColor: color(0x121926, alpha: reduceTransparency ? 1 : 0.72),
                accentColor: color(0x8BD0FF, alpha: 1),
                borderColor: color(0xFFFFFF, alpha: increaseContrast ? 0.55 : 0.20),
                usesTransparency: !reduceTransparency
            )
        }

        return WorkspacePalette(
            gradientColors: reduceTransparency ? [] : [
                color(0xE0F4FF, alpha: 0.68),
                color(0xEEE4FF, alpha: 0.60)
            ],
            solidBackgroundColor: color(0xE0F4FF, alpha: 1),
            contentBackgroundColor: color(0xFFFFFF, alpha: reduceTransparency ? 1 : 0.92),
            railBackgroundColor: color(0xFFFFFF, alpha: reduceTransparency ? 1 : 0.36),
            accentColor: color(0x4C5FD5, alpha: 1),
            borderColor: increaseContrast
                ? color(0x121926, alpha: 0.45)
                : color(0xFFFFFF, alpha: 0.55),
            usesTransparency: !reduceTransparency
        )
    }

    @MainActor
    public static func current(appearance: NSAppearance) -> WorkspacePalette {
        let workspace = NSWorkspace.shared
        return make(
            appearance: appearance,
            reduceTransparency: acceptanceReduceTransparency
                ?? workspace.accessibilityDisplayShouldReduceTransparency,
            increaseContrast: acceptanceIncreaseContrast
                ?? workspace.accessibilityDisplayShouldIncreaseContrast
        )
    }

    private static func color(_ rgb: UInt32, alpha: Double) -> NSColor {
        NSColor(
            srgbRed: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255,
            alpha: alpha
        )
    }
}
