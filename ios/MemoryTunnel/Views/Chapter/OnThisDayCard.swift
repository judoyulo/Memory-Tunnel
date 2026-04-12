import SwiftUI

// MARK: - On This Day Card
//
// Floating card shown at the top of the chapter timeline when
// a memory from the same calendar date in a prior year exists.

struct OnThisDayCard: View {
    let memory: Memory
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: Spacing.sm) {
            // Photo thumbnail
            if let url = memory.mediaURL {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    Color.mtSurface
                }
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.mtSurface)
                    .frame(width: 48, height: 48)
                    .overlay(
                        Image(systemName: "calendar")
                            .foregroundStyle(Color.mtTertiary)
                    )
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(headerText)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.mtLabel)
                if let loc = memory.locationName {
                    Text(L.atLocation(loc))
                        .font(.mtCaption)
                        .foregroundStyle(Color.mtSecondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.mtTertiary)
                    .frame(width: 28, height: 28)
                    .background(Color.mtBackground)
                    .clipShape(Circle())
            }
        }
        .padding(Spacing.sm)
        .background(Color.mtSurface)
        .clipShape(RoundedRectangle(cornerRadius: Radius.card))
        .padding(.horizontal, Spacing.md)
    }

    private var headerText: String {
        let date = memory.takenAt ?? memory.createdAt
        let years = Calendar.current.dateComponents([.year], from: date, to: Date()).year ?? 0
        return years == 1 ? "1 year ago today" : "\(years) years ago today"
    }

    /// Find a memory from the same month+day in a prior year
    static func findMatch(in memories: [Memory]) -> Memory? {
        let cal = Calendar.current
        let today = Date()
        let todayMonth = cal.component(.month, from: today)
        let todayDay = cal.component(.day, from: today)
        let todayYear = cal.component(.year, from: today)

        return memories.first { memory in
            let date = memory.takenAt ?? memory.createdAt
            let month = cal.component(.month, from: date)
            let day = cal.component(.day, from: date)
            let year = cal.component(.year, from: date)
            return month == todayMonth && day == todayDay && year != todayYear
        }
    }
}
