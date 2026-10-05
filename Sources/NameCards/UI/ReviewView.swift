import NameCardsCore
import SwiftUI

/// Card list on the left, editor for the selected card on the right.
struct ReviewView: View {
    enum Filter: String, CaseIterable, Identifiable {
        case toReview = "To Review", approved = "Approved", saved = "Saved", skipped = "Skipped", all = "All"
        var id: Self { self }
    }

    let session: CardSession
    @State private var filter = Filter.toReview
    @State private var selection: UUID?
    @State private var saving: SaveModel?

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                Picker("Show", selection: $filter) {
                    ForEach(Filter.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(10)
                Divider()
                if visibleCards.isEmpty {
                    ContentUnavailableView(emptyTitle, systemImage: "checkmark.circle")
                } else {
                    List(visibleCards, selection: $selection) { card in
                        ReviewRow(card: card).tag(card.id)
                            .contextMenu {
                                Button("Delete Card", role: .destructive) { session.remove(card.id) }
                            }
                    }
                    .listStyle(.inset)
                }
            }
            .frame(minWidth: 280, idealWidth: 320, maxWidth: 420)

            Group {
                if let id = selection, session.card(id) != nil {
                    ReviewDetail(session: session, cardID: id, onDone: { advance(from: id) })
                        .id(id)
                } else {
                    ContentUnavailableView("Select a card", systemImage: "person.text.rectangle",
                                           description: Text("Check each card's details, fix any mistakes, then approve it."))
                }
            }
            .frame(minWidth: 480, maxWidth: .infinity, maxHeight: .infinity)
        }
        .toolbar {
            ToolbarItem {
                Button("Save to Contacts", systemImage: "person.crop.circle.badge.plus") {
                    saving = SaveModel(session: session)
                }
                .disabled(session.approvedCards.isEmpty)
                .help(session.approvedCards.isEmpty
                      ? "Approve cards first"
                      : "Save \(session.approvedCards.count) approved card(s) to Contacts")
            }
        }
        .sheet(item: $saving) { model in
            SaveSheet(model: model)
        }
        .onAppear { if selection == nil { selection = visibleCards.first?.id } }
        .onChange(of: filter) { selection = visibleCards.first?.id }
    }

    private var visibleCards: [CardSession.Card] {
        session.cards.filter { card in
            switch filter {
            case .toReview: card.record.review == .pending
            case .approved: card.record.review == .approved
            case .saved: card.record.review == .saved
            case .skipped: card.record.review == .skipped
            case .all: true
            }
        }
    }

    private var emptyTitle: String {
        switch filter {
        case .toReview: "All caught up"
        case .approved: "No approved cards"
        case .saved: "Nothing saved yet"
        case .skipped: "No skipped cards"
        case .all: "No cards scanned yet"
        }
    }

    /// After approving or skipping, move to the next card still waiting for review.
    private func advance(from id: UUID) {
        let pending = session.cards.filter { $0.record.review == .pending }
        let currentIndex = session.cards.firstIndex { $0.id == id } ?? 0
        let next = pending.first { card in (session.cards.firstIndex { $0.id == card.id } ?? 0) > currentIndex }
            ?? pending.first
        if filter == .toReview || next != nil { selection = next?.id }
    }
}

private struct ReviewRow: View {
    let card: CardSession.Card

    var body: some View {
        HStack {
            CardRow(card: card)
            Spacer(minLength: 4)
            switch card.record.review {
            case .approved:
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).help("Approved")
            case .skipped:
                Image(systemName: "minus.circle").foregroundStyle(.secondary).help("Skipped")
            case .saved:
                Image(systemName: "person.crop.circle.badge.checkmark").foregroundStyle(.blue).help("Saved to Contacts")
            case .pending:
                if let count = card.record.draft?.fieldsNeedingAttention.count, count > 0 {
                    Text("\(count)")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(.orange.opacity(0.2), in: Capsule())
                        .foregroundStyle(.orange)
                        .help("\(count) field\(count == 1 ? "" : "s") to check")
                }
            }
        }
    }
}
