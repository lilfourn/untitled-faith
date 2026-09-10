import SwiftUI

struct ConversationHistoryView: View {
    let store: ChatStore
    let onOpen: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var deleting: ConversationSummary?

    var body: some View {
        NavigationStack {
            List {
                if store.history.isEmpty {
                    ContentUnavailableView("No saved conversations", systemImage: "bubble.left.and.bubble.right",
                        description: Text("Your conversations will be saved on this device."))
                }
                ForEach(store.history) { conversation in
                    Button {
                        store.openConversation(conversation.id)
                        onOpen()
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(conversation.title).foregroundStyle(.primary).lineLimit(2)
                            Text(conversation.updatedAt, style: .date).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .swipeActions {
                        Button("Delete", role: .destructive) { deleting = conversation }
                    }
                }
                if let error = store.storageError {
                    Text(error).font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Conversations")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .confirmationDialog("Delete this conversation from this device?", isPresented: Binding(
                get: { deleting != nil }, set: { if !$0 { deleting = nil } }
            ), titleVisibility: .visible) {
                Button("Delete conversation", role: .destructive) {
                    if let deleting { store.deleteConversation(deleting.id) }
                    deleting = nil
                }
            }
        }
    }
}
