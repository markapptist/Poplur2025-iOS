import SwiftUI

struct MessagesRootView: View {
    @StateObject private var store = FakeDMStore()

    var body: some View {
        NavigationStack {
            DMsListView()
                .navigationTitle("Messages")
                .navigationBarTitleDisplayMode(.inline)
                .navigationDestination(for: UUID.self) { threadID in
                    DMThreadView(store: store, threadID: threadID)
                }
        }
    }
}

// MARK: - DMs List
struct DMsListView: View {
    @StateObject private var store = FakeDMStore()
    @State private var showingNewThreadSheet = false

    var body: some View {
        List {
            Section(header: Text("Recent").font(.headline)) {
                if store.threads.isEmpty {
                    VStack(alignment: .center, spacing: 8) {
                        HStack { Spacer() }
                        Image(systemName: "message.badge.filled.fill")
                            .font(.system(size: 36, weight: .semibold))
                            .foregroundColor(.secondary)
                        Text("Your conversations will appear here")
                            .foregroundColor(.secondary)
                        HStack { Spacer() }
                    }
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(store.threads) { thread in
                        NavigationLink(value: thread.id) {
                            DMThreadRow(thread: thread, store: store)
                        }
                    }
                }
            }
        }
        .navigationTitle("Messages")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingNewThreadSheet = true
                } label: {
                    Image(systemName: "square.and.pencil")
                }
            }
        }
        .sheet(isPresented: $showingNewThreadSheet) {
            NewThreadPickerView(store: store) { users in
                let thread = store.createThread(with: users)
                // New thread appears at top; tap to open
            }
        }
    }
}

private struct DMThreadRow: View {
    let thread: DMThread
    @ObservedObject var store: FakeDMStore

    var body: some View {
        HStack(spacing: 12) {
            AvatarCircle(initials: initials, systemImage: "person.circle.fill")

            VStack(alignment: .leading, spacing: 2) {
                Text(store.displayNameForParticipants(thread.participantIDs))
                    .font(.system(size: 16, weight: .semibold))
                Text(thread.lastMessage?.text ?? "Start the conversation")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if hasUnread {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 10, height: 10)
            }
        }
        .contentShape(Rectangle())
    }

    private var initials: String {
        let name = store.displayNameForParticipants(thread.participantIDs)
        let comps = name.split(separator: " ")
        let first = comps.first?.first.map(String.init) ?? "?"
        let last = comps.dropFirst().first?.first.map(String.init) ?? ""
        return (first + last).uppercased()
    }

    private var hasUnread: Bool {
        thread.messages.contains { !$0.isRead && $0.senderID != store.currentUser.id }
    }
}

// MARK: - Thread View
struct DMThreadView: View {
    @ObservedObject var store: FakeDMStore
    let threadID: UUID

    @State private var draft: String = ""
    @State private var scrollProxy: ScrollViewProxy?

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(messages) { msg in
                            DMMessageBubble(message: msg, isMe: msg.senderID == store.currentUser.id, user: store.user(for: msg.senderID))
                                .id(msg.id)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .onAppear {
                    scrollProxy = proxy
                    scrollToBottom(proxy)
                    store.markThreadRead(threadID)
                }
                .onChange(of: messages.count) { _ in
                    scrollToBottom(proxy)
                }
            }

            Divider()

            HStack(spacing: 8) {
                TextField("Message...", text: $draft, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                Button {
                    send()
                } label: {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 18, weight: .semibold))
                }
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(8)
        }
        .navigationTitle(store.displayNameForParticipants(thread?.participantIDs ?? []))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var thread: DMThread? {
        store.threads.first(where: { $0.id == threadID })
    }

    private var messages: [DMMessage] {
        thread?.messages ?? []
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let thread else { return }
        draft = ""
        store.send(message: text, in: thread.id)
        // Simulate an auto-reply from one of the other participants after a short delay
        if let otherID = thread.participantIDs.first(where: { $0 != store.currentUser.id }) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                let replies = [
                    "Nice!",
                    "Sounds good",
                    "Got it",
                    "Let’s do it",
                    "Haha 😂",
                    "👍"
                ]
                _ = store.send(message: replies.randomElement() ?? "👍", in: thread.id, from: otherID)
            }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        if let last = messages.last {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }
}

private struct DMMessageBubble: View {
    let message: DMMessage
    let isMe: Bool
    let user: DMUser?

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if !isMe { AvatarCircle(initials: initials, systemImage: user?.avatarSystemImage ?? "person.circle") }
            Text(message.text)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .foregroundColor(isMe ? .white : .primary)
                .background(isMe ? Color.blue : Color(.systemGray5))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .frame(maxWidth: UIScreen.main.bounds.width * 0.7, alignment: isMe ? .trailing : .leading)
            if isMe { Spacer(minLength: 0) }
        }
        .frame(maxWidth: .infinity, alignment: isMe ? .trailing : .leading)
        .padding(.horizontal, isMe ? 0 : 4)
    }

    private var initials: String {
        let name = user?.displayName ?? "?"
        let comps = name.split(separator: " ")
        let first = comps.first?.first.map(String.init) ?? "?"
        let last = comps.dropFirst().first?.first.map(String.init) ?? ""
        return (first + last).uppercased()
    }
}

private struct AvatarCircle: View {
    let initials: String
    let systemImage: String

    var body: some View {
        ZStack {
            Circle().fill(Color(.systemGray5))
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
        }
        .frame(width: 34, height: 34)
    }
}

// MARK: - New Thread Picker
private struct NewThreadPickerView: View {
    @ObservedObject var store: FakeDMStore
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<UUID> = []

    var onCreate: ([DMUser]) -> Void

    var body: some View {
        NavigationStack {
            List {
                ForEach(store.users) { user in
                    Button {
                        if selected.contains(user.id) {
                            selected.remove(user.id)
                        } else {
                            selected.insert(user.id)
                        }
                    } label: {
                        HStack(spacing: 12) {
                            AvatarCircle(initials: initials(for: user), systemImage: user.avatarSystemImage)
                            VStack(alignment: .leading) {
                                Text(user.displayName)
                                Text("@\(user.handle)")
                                    .foregroundColor(.secondary)
                                    .font(.footnote)
                            }
                            Spacer()
                            if selected.contains(user.id) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.tint)
                            } else {
                                Image(systemName: "circle")
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Create") {
                        let chosen = store.users.filter { selected.contains($0.id) }
                        onCreate(chosen)
                        dismiss()
                    }
                    .disabled(selected.isEmpty)
                }
            }
            .navigationTitle("New Message")
        }
    }

    private func initials(for user: DMUser) -> String {
        let comps = user.displayName.split(separator: " ")
        let first = comps.first?.first.map(String.init) ?? "?"
        let last = comps.dropFirst().first?.first.map(String.init) ?? ""
        return (first + last).uppercased()
    }
}

// MARK: - Previews
#Preview("DMs List") {
    NavigationStack {
        DMsListView()
    }
}

#Preview("Thread") {
    NavigationStack {
        let store = FakeDMStore()
        let thread = store.createThread(with: [store.users[0], store.users[1]])
        DMThreadView(store: store, threadID: thread.id)
    }
}

