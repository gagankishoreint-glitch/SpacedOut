import AppKit
import SpacedOutCore
import SwiftUI

enum SpacedTheme {
    static func colorScheme(for mode: ThemeMode) -> ColorScheme? {
        switch mode {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
    static func nsAppearance(for mode: ThemeMode) -> NSAppearance? {
        switch mode {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }

    static func widgetTintWash(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.05, green: 0.12, blue: 0.09).opacity(0.45)
            : Color(red: 0.86, green: 0.98, blue: 0.91).opacity(0.44)
    }
    static func cardSurface(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.075) : Color.white.opacity(0.62)
    }
    static func chipSurface(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.09) : Color.white.opacity(0.76)
    }
    static func hairlineBorder(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.14) : Color.white.opacity(0.68)
    }
    static func subtleSeparator(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.10) : Color(red: 0.07, green: 0.20, blue: 0.14).opacity(0.10)
    }

    static func inkPrimary(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.93, green: 0.98, blue: 0.95) : Color(red: 0.06, green: 0.16, blue: 0.11)
    }
    static func inkSecondary(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.70, green: 0.82, blue: 0.76) : Color(red: 0.21, green: 0.36, blue: 0.29)
    }
    static func inkMuted(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.50, green: 0.63, blue: 0.57) : Color(red: 0.36, green: 0.49, blue: 0.43)
    }

    static func accent(_ preset: AccentPreset, scheme: ColorScheme) -> Color {
        switch (preset, scheme) {
        case (.mint, .light):  return Color(red: 0.05, green: 0.58, blue: 0.41)
        case (.mint, .dark):   return Color(red: 0.20, green: 0.83, blue: 0.60)
        case (.sky, .light):   return Color(red: 0.02, green: 0.51, blue: 0.78)
        case (.sky, .dark):    return Color(red: 0.22, green: 0.74, blue: 0.97)
        case (.amber, .light): return Color(red: 0.85, green: 0.47, blue: 0.03)
        case (.amber, .dark):  return Color(red: 0.98, green: 0.75, blue: 0.14)
        case (.coral, .light): return Color(red: 0.88, green: 0.12, blue: 0.28)
        case (.coral, .dark):  return Color(red: 0.98, green: 0.44, blue: 0.52)
        case (.slate, .light): return Color(red: 0.28, green: 0.34, blue: 0.41)
        case (.slate, .dark):  return Color(red: 0.58, green: 0.64, blue: 0.72)
        @unknown default:      return Color(red: 0.05, green: 0.58, blue: 0.41)
        }
    }

    static func urgencyAmber(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.98, green: 0.75, blue: 0.14)
            : Color(red: 0.83, green: 0.45, blue: 0.02)
    }

    static func overdueCoral(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.98, green: 0.44, blue: 0.52)
            : Color(red: 0.85, green: 0.14, blue: 0.25)
    }
}
