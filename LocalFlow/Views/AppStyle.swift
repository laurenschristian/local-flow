import SwiftUI

/// LocalFlow Design System
/// Centralized style definitions for consistent UI across the app
enum AppStyle {

    // MARK: - Colors

    enum Colors {
        /// Primary brand color - deep navy blue
        /// Hex: #001847 | RGB: 0, 24, 71
        static let brand = Color(red: 0, green: 0.094, blue: 0.278)

        /// Accent color for interactive elements and indicators
        /// Used for recording indicator, buttons, highlights
        static let accent = Color.red

        /// Text colors
        static let textPrimary = Color.white
        static let textSecondary = Color.white.opacity(0.85)
        static let textMuted = Color.white.opacity(0.6)

        /// Background variants
        static let backgroundSolid = brand
        static let backgroundGlass = brand.opacity(0.85)

        /// Border/stroke colors
        static let borderLight = Color.white.opacity(0.4)
        static let borderSubtle = Color.white.opacity(0.15)
    }

    // MARK: - Typography

    enum Typography {
        static let titleFont = Font.system(size: 16, weight: .semibold, design: .rounded)
        static let bodyFont = Font.system(size: 14, weight: .medium, design: .rounded)
        static let captionFont = Font.system(size: 12, weight: .regular, design: .rounded)

        static let overlayTitle = Font.system(size: 14, weight: .semibold, design: .rounded)
        static let overlayBody = Font.system(size: 15, weight: .medium, design: .rounded)
    }

    // MARK: - Layout

    enum Layout {
        /// Standard corner radius for cards and overlays
        static let cornerRadius: CGFloat = 20

        /// Smaller corner radius for buttons and inputs
        static let cornerRadiusSmall: CGFloat = 12

        /// Standard padding
        static let paddingSmall: CGFloat = 8
        static let paddingMedium: CGFloat = 16
        static let paddingLarge: CGFloat = 24

        /// Overlay dimensions
        static let overlayMinWidth: CGFloat = 340
        static let overlayMaxWidth: CGFloat = 400
        static let overlayMinTextHeight: CGFloat = 44
    }

    // MARK: - Shadows

    enum Shadows {
        /// Primary shadow for elevated elements
        static func primary(color: Color = Colors.brand) -> some View {
            EmptyView()
                .shadow(color: color.opacity(0.4), radius: 24, x: 0, y: 12)
                .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
        }

        /// Subtle shadow for smaller elements
        static let subtle = (color: Color.black.opacity(0.1), radius: CGFloat(8), y: CGFloat(4))
    }

    // MARK: - Animation

    enum Animation {
        static let quick = SwiftUI.Animation.easeOut(duration: 0.15)
        static let standard = SwiftUI.Animation.easeInOut(duration: 0.25)
        static let spring = SwiftUI.Animation.spring(response: 0.3, dampingFraction: 0.7)
    }
}

// MARK: - Reusable View Modifiers

extension View {
    /// Apply glass background with brand color
    func glassBackground() -> some View {
        self.background {
            RoundedRectangle(cornerRadius: AppStyle.Layout.cornerRadius, style: .continuous)
                .fill(AppStyle.Colors.backgroundGlass)
                .background {
                    RoundedRectangle(cornerRadius: AppStyle.Layout.cornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: AppStyle.Layout.cornerRadius, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    AppStyle.Colors.borderLight,
                                    AppStyle.Colors.borderSubtle,
                                    .clear,
                                    Color.white.opacity(0.1)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
                .shadow(color: AppStyle.Colors.brand.opacity(0.4), radius: 24, x: 0, y: 12)
                .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
        }
    }
}
