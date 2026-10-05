import NameCardsCore
import SwiftUI

/// Cards captured this session, newest first.
struct CardTray: View {
    let model: ScanModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Scanned").font(.headline)
                Spacer()
                Text("\(model.cards.count)").foregroundStyle(.secondary).monospacedDigit()
            }
            .padding(12)
            Divider()
            if model.cards.isEmpty {
                ContentUnavailableView("No cards yet", systemImage: "person.text.rectangle",
                                       description: Text("Cards appear here as they're captured."))
            } else {
                List(model.cards) { card in
                    CardRow(card: card)
                        .contextMenu {
                            Button("Remove", role: .destructive) { model.remove(card) }
                        }
                }
                .listStyle(.inset)
            }
        }
    }
}

private struct CardRow: View {
    let card: ScannedCard

    var body: some View {
        HStack(spacing: 10) {
            Image(decorative: card.image, scale: 1)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 96, height: 58)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(.separator))
            VStack(alignment: .leading, spacing: 2) {
                switch card.status {
                case .reading:
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Reading…").foregroundStyle(.secondary)
                    }
                case .ready:
                    Text(title).font(.body.weight(.medium)).lineLimit(1)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                case .failed(let message):
                    Label("Couldn't read card", systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                    Text(message).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var title: String {
        guard let draft = card.draft else { return "" }
        if !draft.displayName.isEmpty { return draft.displayName }
        return draft.emails.first ?? "Unknown name"
    }

    private var subtitle: String {
        guard let draft = card.draft else { return "" }
        return [draft.jobTitle, draft.organization].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}
