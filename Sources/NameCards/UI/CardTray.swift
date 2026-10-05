import NameCardsCore
import SwiftUI

/// Cards captured this session, newest first.
struct CardTray: View {
    let session: CardSession

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Scanned").font(.headline)
                Spacer()
                Text("\(session.cards.count)").foregroundStyle(.secondary).monospacedDigit()
            }
            .padding(12)
            Divider()
            if session.cards.isEmpty {
                ContentUnavailableView("No cards yet", systemImage: "person.text.rectangle",
                                       description: Text("Cards appear here as they're captured."))
            } else {
                List(session.cards.reversed()) { card in
                    CardRow(card: card)
                        .contextMenu {
                            Button("Delete Card", role: .destructive) { session.remove(card.id) }
                        }
                }
                .listStyle(.inset)
            }
        }
    }
}

/// Thumbnail, name and company for a card; shared by the scan tray and the review list.
struct CardRow: View {
    let card: CardSession.Card

    var body: some View {
        HStack(spacing: 10) {
            CardThumbnail(image: card.image)
            VStack(alignment: .leading, spacing: 2) {
                switch card.record.status {
                case .reading:
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Reading…").foregroundStyle(.secondary)
                    }
                case .ready:
                    Text(card.record.draft?.reviewTitle ?? "").font(.body.weight(.medium)).lineLimit(1)
                    Text(card.record.draft?.reviewSubtitle ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(2)
                case .failed(let message):
                    Label("Couldn't read card", systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                    Text(message).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct CardThumbnail: View {
    let image: CGImage?

    var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: 1).resizable().aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "photo").foregroundStyle(.tertiary)
            }
        }
        .frame(width: 96, height: 58)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(.separator))
    }
}

extension DraftContact {
    var reviewTitle: String {
        if !displayName.isEmpty { return displayName }
        return emails.first ?? "Unknown name"
    }

    var reviewSubtitle: String {
        [jobTitle, organization].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}
