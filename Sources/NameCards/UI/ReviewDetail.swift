import NameCardsCore
import SwiftUI

/// Editor for one card: the card image beside its extracted fields, with uncertain fields highlighted.
struct ReviewDetail: View {
    let session: CardSession
    let cardID: UUID
    /// Called after the card is approved or skipped.
    let onDone: () -> Void

    @State private var enlarged = false

    private var card: CardSession.Card? { session.card(cardID) }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    cardImage
                    switch card?.record.status {
                    case .reading:
                        ProgressView("Reading card…").frame(maxWidth: .infinity)
                    case .failed(let message):
                        failed(message)
                    default:
                        DraftEditor(draft: draftBinding, region: session.region(for: cardID))
                    }
                }
                .padding(20)
            }
            Divider()
            actionBar
        }
    }

    private var draftBinding: Binding<DraftContact> {
        Binding(get: { card?.record.draft ?? DraftContact() }, set: { session.updateDraft(cardID, $0) })
    }

    @ViewBuilder private var cardImage: some View {
        if let image = card?.image {
            Image(decorative: image, scale: 1)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: enlarged ? 640 : 240)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .shadow(radius: 2, y: 1)
                .onTapGesture { withAnimation(.snappy) { enlarged.toggle() } }
                .help(enlarged ? "Click to shrink" : "Click to enlarge")
        }
    }

    private func failed(_ message: String) -> some View {
        VStack(spacing: 12) {
            Label("Couldn't read this card", systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
            Text(message).foregroundStyle(.secondary)
            Button("Try Again") { session.retry(cardID) }
        }
        .frame(maxWidth: .infinity)
    }

    private var actionBar: some View {
        HStack {
            if card?.record.review == .saved {
                Label("Saved to Contacts", systemImage: "person.crop.circle.badge.checkmark").foregroundStyle(.blue)
                Spacer()
                if let id = card?.record.contactIdentifier, let url = URL(string: "addressbook://\(id)") {
                    Button("Open in Contacts") { NSWorkspace.shared.open(url) }
                }
            } else if let review = card?.record.review, review != .pending {
                Label(review == .approved ? "Approved" : "Skipped",
                      systemImage: review == .approved ? "checkmark.circle.fill" : "minus.circle")
                    .foregroundStyle(review == .approved ? .green : .secondary)
                Spacer()
                Button("Move Back to Review") { session.setReview(cardID, .pending) }
            } else {
                if let count = card?.record.draft?.fieldsNeedingAttention.count, count > 0 {
                    Label("\(count) highlighted field\(count == 1 ? "" : "s") to check", systemImage: "exclamationmark.circle")
                        .foregroundStyle(.orange)
                }
                Spacer()
                Button("Read Again") { session.retry(cardID) }
                    .help("Re-read this card with the current settings, e.g. after turning on Claude. Replaces your edits.")
                    .disabled(card?.record.status == .reading)
                Button("Skip") {
                    session.setReview(cardID, .skipped)
                    onDone()
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .help("Don't add this card to Contacts (⇧⌘S)")
                Button("Approve") {
                    session.setReview(cardID, .approved)
                    onDone()
                }
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.borderedProminent)
                .disabled(card?.record.status != .ready)
                .help("The details are correct; queue this contact for saving (⌘↩)")
            }
        }
        .padding(12)
    }
}

/// Form for every contact field, plus the raw OCR lines for quick re-assignment.
private struct DraftEditor: View {
    @Binding var draft: DraftContact
    let region: String

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            section("Name") {
                FieldRow("Name", needsCheck: draft.needsAttention(.name)) {
                    HStack {
                        TextField("Prefix", text: text(\.namePrefix, .name)).frame(width: 60)
                        TextField("First / given", text: text(\.givenName, .name))
                        TextField("Last / family", text: text(\.familyName, .name))
                        TextField("Suffix", text: text(\.nameSuffix, .name)).frame(width: 70)
                    }
                }
                FieldRow("Phonetic", needsCheck: draft.needsAttention(.phoneticName)) {
                    HStack {
                        TextField("Phonetic given", text: text(\.phoneticGivenName, .phoneticName))
                        TextField("Phonetic family", text: text(\.phoneticFamilyName, .phoneticName))
                    }
                }
                FieldRow("Nickname", needsCheck: draft.needsAttention(.nickname)) {
                    TextField("Nickname", text: text(\.nickname, .nickname))
                }
            }
            section("Work") {
                FieldRow("Job title", needsCheck: draft.needsAttention(.jobTitle)) {
                    TextField("Job title", text: text(\.jobTitle, .jobTitle))
                }
                FieldRow("Department", needsCheck: draft.needsAttention(.department)) {
                    TextField("Department", text: text(\.department, .department))
                }
                FieldRow("Company", needsCheck: draft.needsAttention(.organization)) {
                    TextField("Company", text: text(\.organization, .organization))
                }
            }
            section("Contact") {
                FieldRow("Phones", needsCheck: draft.needsAttention(.phones)) { phones }
                FieldRow("Emails", needsCheck: draft.needsAttention(.emails)) {
                    StringList(values: list(\.emails, .emails), placeholder: "name@example.com", addLabel: "Add Email")
                }
                FieldRow("Websites", needsCheck: draft.needsAttention(.urls)) {
                    StringList(values: list(\.urls, .urls), placeholder: "www.example.com", addLabel: "Add Website")
                }
                FieldRow("Address", needsCheck: draft.needsAttention(.address)) {
                    TextField("Address", text: text(\.address, .address), axis: .vertical).lineLimit(1...5)
                }
            }
            if !draft.rawLines.isEmpty {
                section("Text read from the card") { rawLines }
            }
        }
        .textFieldStyle(.roundedBorder)
    }

    // MARK: Phones

    private var phones: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(draft.phones.indices), id: \.self) { index in
                HStack {
                    Picker("Kind", selection: phoneKind(index)) {
                        ForEach(Phone.Kind.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 100)
                    TextField("Number", text: phoneNumber(index))
                    if index < draft.phones.count, !draft.phones[index].isNormalized {
                        Image(systemName: "globe.badge.chevron.backward")
                            .foregroundStyle(.orange)
                            .help("No country code. Add one, e.g. +65, so it dials correctly from anywhere.")
                    }
                    removeButton { draft.phones.remove(at: index); draft.markReviewed(.phones) }
                }
            }
            Button("Add Phone", systemImage: "plus") {
                draft.phones.append(Phone(number: "", raw: "", kind: .mobile))
            }
            .buttonStyle(.borderless)
        }
    }

    private func phoneKind(_ index: Int) -> Binding<Phone.Kind> {
        Binding(get: { index < draft.phones.count ? draft.phones[index].kind : .other },
                set: { guard index < draft.phones.count else { return }
                       draft.phones[index].kind = $0
                       draft.markReviewed(.phones) })
    }

    private func phoneNumber(_ index: Int) -> Binding<String> {
        Binding(get: { index < draft.phones.count ? draft.phones[index].number : "" },
                set: { guard index < draft.phones.count else { return }
                       draft.phones[index].number = $0
                       draft.markReviewed(.phones) })
    }

    // MARK: Raw lines

    private var rawLines: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("If something landed in the wrong field, use a line from the card instead.")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(Array(draft.rawLines.enumerated()), id: \.offset) { _, line in
                HStack {
                    Text(line).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                    Menu("Use as") {
                        ForEach(LineAssignment.allCases) { assignment in
                            Button(assignment.title) { draft.assign(line, as: assignment, region: region) }
                        }
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: Helpers

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            content()
        }
    }

    /// Binding that also marks the field as reviewed when the user edits it.
    private func text(_ keyPath: WritableKeyPath<DraftContact, String>, _ field: DraftContact.Field) -> Binding<String> {
        Binding(get: { draft[keyPath: keyPath] }, set: {
            draft[keyPath: keyPath] = $0
            draft.markReviewed(field)
        })
    }

    private func list(_ keyPath: WritableKeyPath<DraftContact, [String]>, _ field: DraftContact.Field) -> Binding<[String]> {
        Binding(get: { draft[keyPath: keyPath] }, set: {
            draft[keyPath: keyPath] = $0
            draft.markReviewed(field)
        })
    }
}

/// Label column plus content, with an orange highlight when the parser was unsure.
private struct FieldRow<Content: View>: View {
    let label: String
    let needsCheck: Bool
    let content: Content

    init(_ label: String, needsCheck: Bool, @ViewBuilder content: () -> Content) {
        self.label = label
        self.needsCheck = needsCheck
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            HStack(spacing: 4) {
                if needsCheck {
                    Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
                        .help("Not sure about this one. Please check it against the card.")
                }
                Text(label).foregroundStyle(.secondary)
            }
            .frame(width: 100, alignment: .trailing)
            content
        }
        .padding(6)
        .background(needsCheck ? Color.orange.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 6))
    }
}

/// Editable list of strings (emails, websites).
private struct StringList: View {
    @Binding var values: [String]
    let placeholder: String
    let addLabel: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(values.indices), id: \.self) { index in
                HStack {
                    TextField(placeholder, text: Binding(
                        get: { index < values.count ? values[index] : "" },
                        set: { if index < values.count { values[index] = $0 } }))
                    removeButton { values.remove(at: index) }
                }
            }
            Button(addLabel, systemImage: "plus") { values.append("") }
                .buttonStyle(.borderless)
        }
    }
}

@MainActor private func removeButton(_ action: @escaping () -> Void) -> some View {
    Button(action: action) {
        Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
    }
    .buttonStyle(.borderless)
    .help("Remove")
}
