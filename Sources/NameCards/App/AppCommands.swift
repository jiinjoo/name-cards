import SwiftUI

/// Menu bar commands. Shortcuts live here (not on buttons) so they're discoverable and work from anywhere.
struct AppCommands: Commands {
    let state: AppState

    var body: some Commands {
        CommandMenu("Go") {
            Button("Scan") { state.mode = .scan }
                .keyboardShortcut("1")
            Button("Review") { state.mode = .review }
                .keyboardShortcut("2")
        }
        CommandMenu("Card") {
            let review = state.review
            let reviewing = state.mode == .review
            Button("Approve") { review.approve() }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!reviewing || !review.canApproveSelected)
            Button("Skip") { review.skip() }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(!reviewing || review.selectedCard == nil)
            Button("Read Again") { review.readAgain() }
                .keyboardShortcut("r")
                .disabled(!reviewing || review.selectedCard == nil)
            // No shortcut: ⌘⌫ would fire while editing a text field.
            Button("Delete Card…") { review.confirmingDelete = true }
                .disabled(!reviewing || review.selectedCard == nil)
            Divider()
            Button("Next Card") { review.selectNext() }
                .keyboardShortcut("]")
                .disabled(!reviewing)
            Button("Previous Card") { review.selectPrevious() }
                .keyboardShortcut("[")
                .disabled(!reviewing)
            Divider()
            Button("Approve All Clean (\(review.cleanCards.count))") { review.approveAllClean() }
                .keyboardShortcut(.return, modifiers: [.command, .option])
                .disabled(!reviewing || review.cleanCards.isEmpty)
            Button("Save to Contacts…") { review.startSaving() }
                .keyboardShortcut("s")
                .disabled(!reviewing || !review.canSave)
        }
    }
}
