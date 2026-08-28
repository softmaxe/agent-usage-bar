#if DEBUG
import SwiftUI

/// The panel a design study puts each candidate treatment on: one rounded, shadowed card per
/// variant, so what differs between two cards is the treatment and never the frame around it.
struct DemoCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor))
                    .shadow(color: .black.opacity(0.1), radius: 12, y: 5)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.8))
            }
    }
}

/// One candidate treatment in a study: what it is called, the thing being judged, and a line on
/// what the variant is arguing. Every study lays its variants out this way, so what a reader
/// compares between two cards is the treatment and nothing else.
struct DemoVariantCard<Content: View>: View {
    let title: String
    let blurb: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(self.title)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)

            self.content

            Text(self.blurb)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .demoCard()
    }
}

extension View {
    func demoCard() -> some View {
        self.modifier(DemoCard())
    }
}
#endif
