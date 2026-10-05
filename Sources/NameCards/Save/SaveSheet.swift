import NameCardsCore
import SwiftUI

/// Confirms where each approved card goes (new contact or merge) and which changes to apply, then saves.
struct SaveSheet: View {
    @Bindable var model: SaveModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            footer
        }
        .frame(minWidth: 680, idealWidth: 760, minHeight: 540, idealHeight: 680)
        .task { await model.load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Save to Contacts").font(.title2.weight(.semibold))
            if let account = model.account {
                if account.isICloud {
                    Label("New contacts go to your iCloud account and sync to your other devices.", systemImage: "icloud")
                        .foregroundStyle(.secondary)
                } else {
                    Label("No iCloud contacts account on this Mac. New contacts will be saved to “\(account.name)” and won't sync to your iPhone. Sign in to iCloud Contacts in System Settings to fix this.",
                          systemImage: "exclamationmark.icloud")
                        .foregroundStyle(.orange)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .loading:
            ProgressView("Checking your contacts for matches…")
        case .denied:
            ContentUnavailableView {
                Label("Contacts access needed", systemImage: "person.crop.circle.badge.exclamationmark")
            } description: {
                Text("Allow NameCards in System Settings › Privacy & Security › Contacts, then try again.")
            } actions: {
                Button("Open Privacy Settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Contacts")!)
                }
            }
        case .failed(let message):
            ContentUnavailableView("Couldn't read Contacts", systemImage: "exclamationmark.triangle",
                                   description: Text(message))
        case .ready:
            List {
                ForEach($model.items) { $item in
                    SaveItemView(item: $item, image: model.session.card(item.id)?.image)
                }
                Section {
                    Toggle("Add each contact to a group named after its event", isOn: $model.addToEventGroup)
                    Toggle("Use the card image as the contact photo (only where there's no photo yet)",
                           isOn: $model.useCardAsPhoto)
                }
            }
        case .saving(let done, let total):
            ProgressView("Saving \(done + 1) of \(total)…", value: Double(done), total: Double(total))
                .padding(40)
        case .finished(let summary):
            finished(summary)
        }
    }

    private func finished(_ summary: SaveModel.Summary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(summaryLine(summary), systemImage: summary.failures.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.title3)
                .foregroundStyle(summary.failures.isEmpty ? .green : .orange)
            ForEach(summary.failures, id: \.self) { Text($0).foregroundStyle(.red) }
            ForEach(summary.warnings, id: \.self) { Text($0).foregroundStyle(.orange) }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func summaryLine(_ summary: SaveModel.Summary) -> String {
        var parts: [String] = []
        if summary.created > 0 { parts.append("Added \(summary.created) new contact\(summary.created == 1 ? "" : "s")") }
        if summary.updated > 0 { parts.append("updated \(summary.updated) existing") }
        if !summary.failures.isEmpty { parts.append("\(summary.failures.count) failed") }
        return parts.isEmpty ? "Nothing to save" : parts.joined(separator: ", ") + "."
    }

    private var footer: some View {
        HStack {
            if case .ready = model.phase, model.mergeCount > 0 {
                Text("\(model.mergeCount) card\(model.mergeCount == 1 ? "" : "s") will be merged into existing contacts.")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            switch model.phase {
            case .finished:
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            case .saving:
                EmptyView()
            default:
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                if case .ready = model.phase {
                    Button("Save \(model.items.count) Contact\(model.items.count == 1 ? "" : "s")") {
                        Task { await model.saveAll() }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.items.isEmpty)
                }
            }
        }
        .padding(16)
    }
}

/// One card: destination picker plus tickable changes.
private struct SaveItemView: View {
    @Binding var item: SaveItem
    let image: CGImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                CardThumbnail(image: image)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.draft.reviewTitle).font(.headline)
                    Text(item.draft.reviewSubtitle).foregroundStyle(.secondary)
                }
                Spacer()
                Picker("Save as", selection: destination) {
                    Text("New contact").tag(SaveItem.Destination.newContact)
                    ForEach(item.candidates) { match in
                        Text("Merge into \(match.contact.displayName)\(match.contact.organization.isEmpty ? "" : " · \(match.contact.organization)")")
                            .tag(SaveItem.Destination.existing(match.contact))
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 300)
            }
            if let match = item.candidates.first(where: { $0.contact == item.destination.contact }) {
                Label(match.reasons.joined(separator: " · "), systemImage: "link")
                    .font(.caption).foregroundStyle(.secondary)
            } else if !item.candidates.isEmpty {
                Label("Possibly already in your contacts: \(item.candidates.map(\.contact.displayName).joined(separator: ", "))",
                      systemImage: "questionmark.circle")
                    .font(.caption).foregroundStyle(.orange)
            }

            VStack(alignment: .leading, spacing: 4) {
                ForEach(item.plan.changes) { change in
                    Toggle(isOn: selected(change.id)) { ChangeLabel(change: change) }
                }
                if item.plan.changes.isEmpty {
                    Text("Nothing new on this card. The contact already has these details.")
                        .foregroundStyle(.secondary)
                }
                if !item.plan.unchanged.isEmpty {
                    Text("Already in contact: \(item.plan.unchanged.joined(separator: ", "))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.leading, 108)
        }
        .padding(.vertical, 8)
    }

    private var destination: Binding<SaveItem.Destination> {
        Binding(get: { item.destination }, set: { item.setDestination($0) })
    }

    private func selected(_ id: String) -> Binding<Bool> {
        Binding(get: { item.selection.contains(id) }, set: { on in
            if on { item.selection.insert(id) } else { item.selection.remove(id) }
        })
    }
}

private struct ChangeLabel: View {
    let change: FieldChange

    var body: some View {
        switch change.kind {
        case .add:
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("Add").foregroundStyle(.green)
                Text(change.label).foregroundStyle(.secondary)
                Text(change.value.replacingOccurrences(of: "\n", with: ", "))
            }
        case .replace(let old):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("Replace").foregroundStyle(.orange)
                Text(change.label).foregroundStyle(.secondary)
                Text(old).strikethrough().foregroundStyle(.secondary)
                Image(systemName: "arrow.right").font(.caption)
                Text(change.value)
            }
        }
    }
}
