import NameCardsCore
import SwiftUI

/// Card list on the left, editor for the selected card on the right.
struct ReviewView: View {
    @Bindable var model: ReviewModel

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                Picker("Show", selection: $model.filter) {
                    ForEach(ReviewModel.Filter.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(10)
                Divider()
                if model.visibleCards.isEmpty {
                    ContentUnavailableView(emptyTitle, systemImage: "checkmark.circle")
                } else {
                    List(model.visibleCards, selection: $model.selection) { card in
                        ReviewRow(card: card).tag(card.id)
                            .contextMenu {
                                Button("Delete Card", role: .destructive) { model.session.remove(card.id) }
                            }
                    }
                    .listStyle(.inset)
                }
            }
            .frame(minWidth: 280, idealWidth: 320, maxWidth: 420)

            Group {
                if let id = model.selection, model.session.card(id) != nil {
                    ReviewDetail(model: model, cardID: id).id(id)
                } else {
                    ContentUnavailableView("Select a card", systemImage: "person.text.rectangle",
                                           description: Text("Check each card's details, fix any mistakes, then approve it."))
                }
            }
            .frame(minWidth: 480, maxWidth: .infinity, maxHeight: .infinity)
        }
        .toolbar {
            ToolbarItem {
                Button("Approve All Clean", systemImage: "checkmark.circle") { model.approveAllClean() }
                    .disabled(model.cleanCards.isEmpty)
                    .help(model.cleanCards.isEmpty
                          ? "No waiting cards are free of highlighted fields"
                          : "Approve the \(model.cleanCards.count) waiting card(s) with nothing highlighted (⌥⌘↩)")
            }
            ToolbarItem {
                Button("Save to Contacts", systemImage: "person.crop.circle.badge.plus") { model.startSaving() }
                    .disabled(!model.canSave)
                    .help(model.canSave
                          ? "Save \(model.session.approvedCards.count) approved card(s) to Contacts (⌘S)"
                          : "Approve cards first")
            }
        }
        .sheet(item: $model.saving) { SaveSheet(model: $0) }
        .onAppear { model.selectFirstIfNeeded() }
    }

    private var emptyTitle: String {
        switch model.filter {
        case .toReview: "All caught up"
        case .approved: "No approved cards"
        case .saved: "Nothing saved yet"
        case .skipped: "No skipped cards"
        case .all: "No cards scanned yet"
        }
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
