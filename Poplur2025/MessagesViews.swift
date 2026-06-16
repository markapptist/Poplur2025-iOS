import Foundation
import SwiftUI

struct MessagesRootView: View {
    @StateObject private var store = FakeDMStore()

    var body: some View {
        DMsListView(store: store)
    }
}

// MARK: - DMs List

struct DMsListView: View {
    @ObservedObject var store: FakeDMStore
    @Environment(\.dismiss) private var dismiss
    @State private var showingNewThreadSheet = false
    @State private var selectedThreadID: UUID?
    @State private var callingUser: FakeUser?
    @State private var searchText = ""

    init(store: FakeDMStore) {
        self.store = store
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let selectedThreadID {
                DMThreadView(
                    store: store,
                    threadID: selectedThreadID,
                    onCall: { user in callingUser = user }
                )
                .transition(.opacity)
            } else {
                listContent
                    .transition(.opacity)
            }

            if let callingUser {
                PopularPhone(user: callingUser)
                    .transition(.opacity)
                    .zIndex(30)
            }

            if showingNewThreadSheet {
                NewThreadPickerView(
                    store: store,
                    onCancel: { showingNewThreadSheet = false },
                    onCreate: { users in
                        let thread = store.createThread(with: users)
                        selectedThreadID = thread.id
                        showingNewThreadSheet = false
                    }
                )
                .transition(.opacity)
                .zIndex(40)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var listContent: some View {
        VStack(spacing: 0) {
            DMTopBar(
                title: "Messages",
                onEdit: { showingNewThreadSheet = true }
            )
            .padding(.horizontal, 20)
            .padding(.top, 12)

            Spacer()
                .frame(height: 48)

            Text("Recent")
                .font(.system(size: 28, weight: .black))
                .foregroundStyle(Color(red: 0.6, green: 0.6, blue: 0.63))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 40)

            Spacer()
                .frame(height: 14)

            DMSearchField(text: $searchText)
                .padding(.horizontal, 20)
                .padding(.bottom, 14)

            VStack(spacing: 12) {
                ForEach(filteredThreads) { thread in
                    DMThreadRow(thread: thread, store: store) {
                        selectedThreadID = thread.id
                    } onCall: { user in
                        callingUser = user
                    }
                }
            }
            .padding(.horizontal, 20)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }

    private var filteredThreads: [DMThread] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return store.threads }
        return store.threads.filter { thread in
            store.displayNameForParticipants(thread.participantIDs).localizedCaseInsensitiveContains(query)
            || (thread.lastMessage?.text.localizedCaseInsensitiveContains(query) ?? false)
        }
    }
}

private struct DMSearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 17, weight: .black))
                .foregroundStyle(Color(red: 0.58, green: 0.58, blue: 0.62))

            TextField("Search", text: $text)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.white)
                .tint(.white)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
        }
        .padding(.horizontal, 18)
        .frame(height: 48)
        .background(Color(red: 0.09, green: 0.09, blue: 0.1), in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.08), lineWidth: 1))
    }
}

private struct DMTopBar: View {
    let title: String
    let onEdit: () -> Void

    var body: some View {
        ZStack {
            Text(title)
                .font(.system(size: 33, weight: .black))
                .foregroundStyle(.white)

            HStack {
                Spacer()
                DMCircleIconButton(systemName: "square.and.pencil", size: 58, iconSize: 31, action: onEdit)
            }
        }
        .frame(height: 112)
    }
}

private struct DMThreadRow: View {
    let thread: DMThread
    @ObservedObject var store: FakeDMStore
    let onOpen: () -> Void
    let onCall: (FakeUser) -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 0) {
                DMAvatarCircle(name: displayName, isOnline: true)
                    .frame(width: 52, height: 52)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(displayName)
                            .font(.system(size: 21, weight: .black))
                            .foregroundStyle(.white)
                            .lineLimit(1)

                        Spacer(minLength: 6)

                        Text(lastTime)
                            .font(.system(size: 12, weight: .black))
                            .foregroundStyle(unreadCount > 0 ? Color(red: 0.38, green: 1.0, blue: 0.47) : Color(red: 0.56, green: 0.56, blue: 0.59))
                    }

                    HStack(spacing: 8) {
                        Text(thread.lastMessage?.text ?? "Start the conversation")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(Color(red: 0.66, green: 0.66, blue: 0.7))
                            .lineLimit(1)

                        Spacer(minLength: 6)

                        if unreadCount > 0 {
                            Text("\(unreadCount)")
                                .font(.system(size: 11, weight: .black))
                                .foregroundStyle(.black)
                                .frame(width: 21, height: 21)
                                .background(Color(red: 0.38, green: 1.0, blue: 0.47), in: Circle())
                        } else {
                            Circle()
                                .fill(Color(red: 0.23, green: 0.59, blue: 1.0))
                                .frame(width: 8, height: 8)
                        }
                    }
                }
                .padding(.leading, 18)

                Spacer(minLength: 12)

                Button {
                    onCall(fakeUser)
                } label: {
                    Image(systemName: "phone.fill")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(Color(red: 0.09, green: 0.09, blue: 0.1), in: Circle())
                        .overlay(Circle().stroke(.white.opacity(0.09), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .padding(.leading, 14)

                Image(systemName: "chevron.right")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(Color(red: 0.43, green: 0.43, blue: 0.45))
                    .frame(width: 36)
                    .padding(.leading, 12)
            }
            .padding(.leading, 22)
            .padding(.trailing, 16)
            .frame(height: 88)
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 0.13, green: 0.13, blue: 0.16),
                        Color(red: 0.09, green: 0.09, blue: 0.11)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: Capsule()
            )
            .overlay(Capsule().stroke(.white.opacity(0.06), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var displayName: String {
        store.displayNameForParticipants(thread.participantIDs)
    }

    private var fakeUser: FakeUser {
        FakeUser(id: thread.participantIDs.first(where: { $0 != store.currentUser.id }) ?? thread.id, name: displayName)
    }

    private var unreadCount: Int {
        thread.messages.filter { $0.senderID != store.currentUser.id && !$0.isRead }.count
    }

    private var lastTime: String {
        guard let lastMessage = thread.lastMessage else { return "Now" }
        return DMRelativeTimeFormatter.shortTime(from: lastMessage.timestamp)
    }
}

// MARK: - Thread View

struct DMThreadView: View {
    @ObservedObject var store: FakeDMStore
    let threadID: UUID
    var onCall: ((FakeUser) -> Void)? = nil

    @State private var draft: String = ""

    var body: some View {
        VStack(spacing: 0) {
            detailTopBar
                .padding(.horizontal, 16)
                .padding(.top, 10)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 10) {
                        Spacer()
                            .frame(height: 12)
                        Text("Today")
                            .font(.system(size: 12, weight: .black))
                            .foregroundStyle(Color(red: 0.62, green: 0.62, blue: 0.66))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(Color(red: 0.08, green: 0.08, blue: 0.1), in: Capsule())
                            .overlay(Capsule().stroke(.white.opacity(0.06), lineWidth: 1))
                            .padding(.bottom, 4)
                        ForEach(messages) { msg in
                            DMMessageBubble(message: msg, isMe: msg.senderID == store.currentUser.id)
                                .id(msg.id)
                        }
                        Spacer()
                            .frame(height: 12)
                    }
                    .padding(.horizontal, 16)
                }
                .onAppear {
                    scrollToBottom(proxy)
                    store.markThreadRead(threadID)
                }
                .onChange(of: messages.count) {
                    scrollToBottom(proxy)
                }
            }

            composer
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }

    private var detailTopBar: some View {
        HStack(spacing: 0) {
            DMAvatarCircle(name: displayName, isOnline: true)
                .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 2) {
                Text(displayName)
                    .font(.system(size: 22, weight: .black))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text("Active now")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color(red: 0.56, green: 0.56, blue: 0.59))
            }
            .padding(.leading, 12)

            Spacer(minLength: 12)

            DMCircleIconButton(systemName: "phone.fill", size: 52, iconSize: 24) {
                onCall?(fakeUser)
            }
        }
        .frame(height: 92)
    }

    private var composer: some View {
        HStack(spacing: 10) {
            Button(action: {}) {
                Image(systemName: "plus")
                    .font(.system(size: 22, weight: .black))
                    .foregroundStyle(Color(red: 0.72, green: 0.72, blue: 0.78))
                    .frame(width: 46, height: 46)
                    .background(Color(red: 0.09, green: 0.09, blue: 0.1), in: Circle())
                    .overlay(Circle().stroke(.white.opacity(0.1), lineWidth: 1))
            }
            .buttonStyle(.plain)

            TextField("Message \(displayName)", text: $draft)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.white)
                .tint(.white)
                .padding(.horizontal, 18)
                .frame(height: 56)
                .background(Color(red: 0.09, green: 0.09, blue: 0.1), in: Capsule())
                .overlay(Capsule().stroke(.white.opacity(0.12), lineWidth: 1))

            Button(action: send) {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(sendButtonColor, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private var sendButtonColor: Color {
        draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        ? Color(red: 0.17, green: 0.17, blue: 0.19)
        : Color(red: 0.23, green: 0.59, blue: 1.0)
    }

    private var thread: DMThread? {
        store.threads.first(where: { $0.id == threadID })
    }

    private var messages: [DMMessage] {
        thread?.messages ?? []
    }

    private var displayName: String {
        store.displayNameForParticipants(thread?.participantIDs ?? [])
    }

    private var fakeUser: FakeUser {
        FakeUser(id: thread?.participantIDs.first(where: { $0 != store.currentUser.id }) ?? threadID, name: displayName)
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let thread else { return }
        draft = ""
        store.send(message: text, in: thread.id)
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

    var body: some View {
        HStack {
            if isMe { Spacer(minLength: 0) }

            VStack(alignment: .leading, spacing: 7) {
                Text(message.text)
                    .font(.system(size: 17, weight: .bold))
                    .lineSpacing(2)
                    .foregroundStyle(.white)

                HStack(spacing: 4) {
                    Spacer(minLength: 20)
                    Text(DMRelativeTimeFormatter.shortTime(from: message.timestamp))
                        .font(.system(size: 10, weight: .black))
                        .foregroundStyle(.white.opacity(0.62))
                    if isMe {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .black))
                            .foregroundStyle(.white.opacity(0.72))
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .frame(maxWidth: UIScreen.main.bounds.width * 0.78, alignment: .leading)
            .background(isMe ? Color(red: 0.23, green: 0.59, blue: 1.0) : Color(red: 0.11, green: 0.11, blue: 0.13))
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: 22,
                    bottomLeadingRadius: isMe ? 22 : 6,
                    bottomTrailingRadius: isMe ? 6 : 22,
                    topTrailingRadius: 22
                )
            )

            if !isMe { Spacer(minLength: 0) }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct DMCircleIconButton: View {
    let systemName: String
    let size: CGFloat
    let iconSize: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: iconSize, weight: .black))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(Color(red: 0.09, green: 0.09, blue: 0.1), in: Circle())
                .overlay(Circle().stroke(.white.opacity(0.09), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

private struct DMAvatarCircle: View {
    let name: String
    let isOnline: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.18, green: 0.18, blue: 0.22),
                            Color(red: 0.07, green: 0.07, blue: 0.09)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Text(initials)
                .font(.system(size: 16, weight: .black))
                .foregroundStyle(.white)

            if isOnline {
                Circle()
                    .fill(Color(red: 0.38, green: 1.0, blue: 0.47))
                    .frame(width: 12, height: 12)
                    .overlay(Circle().stroke(Color.black, lineWidth: 2))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }
        }
        .overlay(Circle().stroke(.white.opacity(0.08), lineWidth: 1))
    }

    private var initials: String {
        let letters = name
            .split(separator: " ")
            .prefix(2)
            .compactMap(\.first)
        return letters.isEmpty ? "P" : letters.map(String.init).joined().uppercased()
    }
}

private enum DMRelativeTimeFormatter {
    static func shortTime(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }
}

// MARK: - New Thread Picker

private struct NewThreadPickerView: View {
    @ObservedObject var store: FakeDMStore
    @State private var selected: Set<UUID> = []

    let onCancel: () -> Void
    let onCreate: ([DMUser]) -> Void

    init(store: FakeDMStore, onCancel: @escaping () -> Void, onCreate: @escaping ([DMUser]) -> Void) {
        self.store = store
        self.onCancel = onCancel
        self.onCreate = onCreate
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(store.users, id: \.id) { user in
                    Button {
                        if selected.contains(user.id) {
                            selected.remove(user.id)
                        } else {
                            selected.insert(user.id)
                        }
                    } label: {
                        HStack(spacing: 12) {
                            DMAvatarCircle(name: user.displayName, isOnline: false)
                                .frame(width: 34, height: 34)
                            VStack(alignment: .leading) {
                                Text(user.displayName)
                                Text("@\(user.handle)")
                                    .foregroundColor(.secondary)
                                    .font(.footnote)
                            }
                            Spacer()
                            Image(systemName: selected.contains(user.id) ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(selected.contains(user.id) ? Color.accentColor : Color.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Create") {
                        let chosen = store.users.filter { selected.contains($0.id) }
                        onCreate(chosen)
                    }
                    .disabled(selected.isEmpty)
                }
            }
            .navigationTitle("New Message")
        }
    }
}

// MARK: - Previews

#Preview("DMs List") {
    DMsListView(store: FakeDMStore())
}

#Preview("Thread") {
    let store = FakeDMStore()
    let thread = store.threads[0]
    DMThreadView(store: store, threadID: thread.id)
}
