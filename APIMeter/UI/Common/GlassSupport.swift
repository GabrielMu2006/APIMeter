import SwiftUI

/// macOS 26 Liquid Glass touches (spec 64): applied to buttons/filter/popover
/// only - data cards stay native. No-op on macOS 15.
extension View {
    @ViewBuilder
    func glassButtonStyle() -> some View {
        if #available(macOS 26.0, *) {
            self.buttonStyle(.glass)
        } else {
            self
        }
    }

    @ViewBuilder
    func glassProminentButtonStyle() -> some View {
        if #available(macOS 26.0, *) {
            self.buttonStyle(.glassProminent)
        } else {
            self
        }
    }
}

extension AppearanceMode {
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// Applies the user's appearance choice (spec 65) to any root view.
extension View {
    func apiMeterAppearance(_ appearance: AppearanceMode) -> some View {
        self.preferredColorScheme(appearance.colorScheme)
    }
}
