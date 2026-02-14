import SwiftUI

struct ChatDetailView: View {
    let thread: FakeChatThread
    @ObservedObject var chatStore: FakeChatStore
    @State private var newMessageText: String = ""

    // Derive messages for this thread from the store
    private var messages: [FakeMessage] {
        chatStore.messagesByThreadID[thread.id] ?? []
    }

    // Infer a current user for demo purposes as the first participant
    private var currentUser: FakeUser? { thread.participants.first }

    var body: some View {
        VStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(messages) { message in
                            HStack {
                                if isFromCurrentUser(message) {
                                    Spacer()
                                    MessageBubble(text: message.content, isCurrentUser: true)
                                } else {
                                    MessageBubble(text: message.content, isCurrentUser: false)
                                    Spacer()
                                }
                            }
                            .id(message.id)
                        }
                    }
                    .padding()
                }
                .onChange(of: messages.count) { _ in
                    if let last = messages.last {
                        withAnimation {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
                .onAppear {
                    if let last = messages.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                    chatStore.activeThreadID = thread.id
                    chatStore.markThreadAsRead(threadID: thread.id)
                }
            }
            Divider()
            HStack {
                TextField("Message", text: $newMessageText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .onSubmit(sendMessage)
                Button(action: sendMessage) {
                    Text("Send")
                        .bold()
                }
                .disabled(newMessageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding()
        }
        .navigationTitle(titleForThread(thread))
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            // Clear active thread when leaving
            chatStore.activeThreadID = nil
        }
    }

    private func isFromCurrentUser(_ message: FakeMessage) -> Bool {
        guard let currentUser else { return false }
        return message.sender == currentUser
    }

    private func titleForThread(_ thread: FakeChatThread) -> String {
        // Show names of other participants (excluding current user) if possible
        let me = currentUser
        let others = thread.participants.filter { $0 != me }
        if others.isEmpty {
            return me?.name ?? "Chat"
        } else {
            return others.map { $0.name }.joined(separator: ", ")
        }
    }

    private func sendMessage() {
        let trimmed = newMessageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let sender = currentUser else { return }
        chatStore.sendMessage(threadID: thread.id, sender: sender, content: trimmed)
        newMessageText = ""
    }
}

private struct MessageBubble: View {
    let text: String
    let isCurrentUser: Bool

    var body: some View {
        Text(text)
            .padding(12)
            .background(isCurrentUser ? Color.blue : Color.gray.opacity(0.2))
            .foregroundColor(isCurrentUser ? .white : .primary)
            .cornerRadius(16)
            .frame(maxWidth: 250, alignment: isCurrentUser ? .trailing : .leading)
    }
}
