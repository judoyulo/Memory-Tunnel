import WidgetKit
import SwiftUI

// MARK: - Timeline Entry

struct MemoryEntry: TimelineEntry {
    let date: Date
    let partnerName: String?
    let imageURL: URL?
    let chapterID: String?
}

// MARK: - Provider

struct MemoryProvider: TimelineProvider {
    typealias Entry = MemoryEntry

    func placeholder(in context: Context) -> MemoryEntry {
        MemoryEntry(date: .now, partnerName: "Alex", imageURL: nil, chapterID: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (MemoryEntry) -> Void) {
        completion(placeholder(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MemoryEntry>) -> Void) {
        // The widget shows today's card chapter + latest photo.
        // Data is shared with the app via App Group UserDefaults.
        let defaults = UserDefaults(suiteName: "group.com.memorytunnel.app")

        let entry = MemoryEntry(
            date:        .now,
            partnerName: defaults?.string(forKey: "widget.partnerName"),
            imageURL:    (defaults?.string(forKey: "widget.imageURL")).flatMap(URL.init),
            chapterID:   defaults?.string(forKey: "widget.chapterID")
        )

        // Refresh once per hour — the app updates shared defaults after loading daily card
        let nextUpdate = Calendar.current.date(byAdding: .hour, value: 1, to: .now)!
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }
}

// MARK: - Widget View

struct MemoryWidgetView: View {
    let entry: MemoryEntry

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let url = entry.imageURL {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Color(hex: "#EDE0CC")
                }
            } else {
                Color(hex: "#F5EAD8")
            }

            // Gradient
            LinearGradient(
                colors: [.clear, Color.black.opacity(0.50)],
                startPoint: UnitPoint(x: 0.5, y: 0.60),
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 2) {
                if let name = entry.partnerName {
                    Text(name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                Text("Tap to send a memory")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.75))
            }
            .padding(10)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .widgetURL(entry.chapterID.map { URL(string: "memorytunnel://chapter/\($0)")! })
    }
}

// MARK: - Widget Configuration

@main
struct MemoryTunnelWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MemoryTunnelWidget", provider: MemoryProvider()) { entry in
            MemoryWidgetView(entry: entry)
        }
        .configurationDisplayName("Memory Tunnel")
        .description("See your daily memory card at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Color hex extension (duplicated from main app — widgets can't import app modules)

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 6: (a,r,g,b) = (255, int>>16, int>>8&0xFF, int&0xFF)
        default:(a,r,g,b) = (255, 0, 0, 0)
        }
        self.init(.sRGB, red: Double(r)/255, green: Double(g)/255, blue: Double(b)/255, opacity: Double(a)/255)
    }
}
