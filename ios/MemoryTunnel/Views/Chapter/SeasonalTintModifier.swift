import SwiftUI

// MARK: - Seasonal Tint
//
// Derives a subtle background color overlay from a memory's date.
// Spring → warm green-gold, Summer → warm amber,
// Fall → burnt orange, Winter → cool blue-gray.
// Opacity is 4-5% — felt but not consciously noticed.

struct SeasonalTintModifier: ViewModifier {
    let date: Date?

    func body(content: Content) -> some View {
        content
            .background(
                seasonalColor
                    .ignoresSafeArea()
                    .animation(.easeInOut(duration: 0.8), value: seasonIndex)
            )
    }

    private var seasonIndex: Int {
        guard let date else { return -1 }
        let month = Calendar.current.component(.month, from: date)
        switch month {
        case 3...5:  return 0  // spring
        case 6...8:  return 1  // summer
        case 9...11: return 2  // autumn
        default:     return 3  // winter
        }
    }

    private var seasonalColor: Color {
        guard date != nil else { return .clear }
        switch seasonIndex {
        case 0:  return Color(red: 0.6, green: 0.7, blue: 0.4).opacity(0.04)
        case 1:  return Color(red: 0.8, green: 0.6, blue: 0.4).opacity(0.05)
        case 2:  return Color(red: 0.7, green: 0.5, blue: 0.3).opacity(0.04)
        case 3:  return Color(red: 0.4, green: 0.5, blue: 0.6).opacity(0.04)
        default: return .clear
        }
    }
}

extension View {
    func seasonalTint(for date: Date?) -> some View {
        modifier(SeasonalTintModifier(date: date))
    }
}
