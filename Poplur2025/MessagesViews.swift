import Foundation
import SwiftUI

// MARK: - Design palette (sampled from the Chats mockups)

private enum ChatC {
    static let pageBG    = Color(red: 253/255, green: 239/255, blue: 245/255) // #FDEFF5
    static let card      = Color(red: 254/255, green: 245/255, blue: 249/255) // #FEF5F9
    static let avatarBG  = Color(red: 253/255, green: 227/255, blue: 238/255) // #FDE3EE
    static let accent    = Color(red: 255/255, green: 45/255,  blue: 130/255) // #FF2D82
    static let title     = Color(red: 16/255,  green: 20/255,  blue: 38/255)
    static let secondary = Color(red: 138/255, green: 138/255, blue: 150/255)
    static let online    = Color(red: 71/255,  green: 200/255, blue: 61/255)
    static let todayPill = Color(red: 250/255, green: 240/255, blue: 245/255)
    static let iconGray  = Color(red: 150/255, green: 148/255, blue: 158/255)
}

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
    @State private var searchText = ""
    @State private var videoCallUser: DMUser? = nil

    init(store: FakeDMStore) {
        self.store = store
    }

    var body: some View {
        ZStack {
            ChatC.pageBG.ignoresSafeArea()

            if let selectedThreadID {
                DMThreadView(
                    store: store,
                    threadID: selectedThreadID,
                    onVideoCall: { user in videoCallUser = user }
                )
                .transition(.opacity)
            } else {
                listContent
                    .transition(.opacity)
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
        .fullScreenCover(item: $videoCallUser) { user in
            DMCallCoordinatorView(calleeName: user.displayName, isVideo: true) { videoCallUser = nil }
        }
    }

    private var listContent: some View {
        VStack(spacing: 0) {
            DMTopBar(
                title: "Chats",
                onEdit: { showingNewThreadSheet = true }
            )
            .padding(.horizontal, 20)
            .padding(.top, 22)

            DMSearchField(text: $searchText)
                .padding(.horizontal, 20)
                .padding(.top, 22)

            ScrollView {
                LazyVStack(spacing: 14) {
                    ForEach(filteredThreads, id: \.id) { thread in
                        DMThreadRow(thread: thread, store: store) {
                            selectedThreadID = thread.id
                        } onVideoCall: { user in
                            videoCallUser = user
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 30)
            }
            .scrollIndicators(.hidden)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        HStack(spacing: 14) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(ChatC.accent)

            TextField("", text: $text, prompt: Text("Search chats...").foregroundColor(ChatC.secondary))
                .font(.system(size: 19, weight: .semibold, design: .rounded))
                .foregroundStyle(ChatC.title)
                .tint(ChatC.accent)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
        }
        .padding(.horizontal, 22)
        .frame(height: 62)
        .background(ChatC.card, in: Capsule())
        .shadow(color: .black.opacity(0.04), radius: 10, x: 0, y: 4)
    }
}

private struct DMTopBar: View {
    let title: String
    let onEdit: () -> Void

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    // Same icon shown in the hold-menu wheel that opens this screen.
                    HoldMenuIconBadge(icon: HoldMenuIcons.chat, size: 40)
                    Text(title)
                        .font(.system(size: 40, weight: .black, design: .rounded))
                        .foregroundStyle(ChatC.title)
                }

                Text("Recent messages")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(ChatC.accent)
            }

            Spacer()

            Button(action: onEdit) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(ChatC.accent)
                    .frame(width: 62, height: 62)
                    .background(ChatC.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 4)
            }
            .buttonStyle(.plain)
        }
    }
}

private struct DMThreadRow: View {
    let thread: DMThread
    @ObservedObject var store: FakeDMStore
    let onOpen: () -> Void
    let onVideoCall: (DMUser) -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 16) {
                DMAvatarCircle(name: displayName, isOnline: true)
                    .frame(width: 62, height: 62)

                VStack(alignment: .leading, spacing: 6) {
                    Text(displayName)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(ChatC.title)
                        .lineLimit(1)

                    Text(thread.lastMessage?.text ?? "Start the conversation")
                        .font(.system(size: 17, weight: .medium, design: .rounded))
                        .foregroundStyle(ChatC.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 8) {
                    Text(lastTime)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(ChatC.accent)

                    HStack(spacing: 8) {
                        if unreadCount > 0 {
                            Text("\(unreadCount)")
                                .font(.system(size: 15, weight: .black, design: .rounded))
                                .foregroundStyle(.white)
                                .frame(width: 32, height: 32)
                                .background(ChatC.accent, in: Circle())
                        }

                        Button {
                            onVideoCall(videoCallUser)
                        } label: {
                            Image(systemName: "video.fill")
                                .font(.system(size: 19, weight: .semibold))
                                .foregroundStyle(ChatC.iconGray)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity)
            .background(ChatC.card, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .shadow(color: .black.opacity(0.035), radius: 10, x: 0, y: 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var displayName: String {
        store.displayNameForParticipants(thread.participantIDs)
    }

    private var videoCallUser: DMUser {
        let userID = thread.participantIDs.first(where: { $0 != store.currentUser.id }) ?? thread.id
        return store.user(for: userID) ?? DMUser(
            id: userID,
            displayName: displayName,
            handle: displayName.lowercased().replacingOccurrences(of: " ", with: "."),
            avatarSystemImage: "person.circle.fill"
        )
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
    var onVideoCall: ((DMUser) -> Void)? = nil

    @State private var draft: String = ""
    @State private var showVideoCall = false
    @State private var showAudioCall = false

    var body: some View {
        VStack(spacing: 0) {
            detailTopBar
                .padding(.horizontal, 20)
                .padding(.top, 12)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        Text("Today")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(ChatC.secondary)
                            .padding(.horizontal, 22)
                            .padding(.vertical, 10)
                            .background(ChatC.todayPill, in: Capsule())
                            .padding(.vertical, 10)

                        ForEach(messages) { msg in
                            DMMessageBubble(message: msg, isMe: msg.senderID == store.currentUser.id)
                                .id(msg.id)
                        }

                        Spacer().frame(height: 12)
                    }
                    .padding(.horizontal, 18)
                }
                .scrollIndicators(.hidden)
                .onAppear {
                    scrollToBottom(proxy)
                    store.markThreadRead(threadID)
                }
                .onChange(of: messages.count) {
                    scrollToBottom(proxy)
                }
            }

            composer
                .padding(.horizontal, 18)
                .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ChatC.pageBG.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .fullScreenCover(isPresented: $showVideoCall) {
            DMCallCoordinatorView(calleeName: displayName, isVideo: true) { showVideoCall = false }
        }
        .fullScreenCover(isPresented: $showAudioCall) {
            DMCallCoordinatorView(calleeName: displayName, isVideo: false) { showAudioCall = false }
        }
    }

    private var detailTopBar: some View {
        HStack(spacing: 0) {
            DMAvatarCircle(name: displayName, isOnline: true)
                .frame(width: 62, height: 62)

            VStack(alignment: .leading, spacing: 3) {
                Text(displayName)
                    .font(.system(size: 26, weight: .black, design: .rounded))
                    .foregroundStyle(ChatC.title)
                    .lineLimit(1)

                HStack(spacing: 5) {
                    Circle()
                        .fill(ChatC.online)
                        .frame(width: 9, height: 9)
                    Text("Active now")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(ChatC.online)
                }
            }
            .padding(.leading, 14)

            Spacer(minLength: 12)

            HStack(spacing: 12) {
                DMSquareIconButton(systemName: "phone.fill", iconSize: 22) { showAudioCall = true }
                DMSquareIconButton(systemName: "video.fill", iconSize: 22) { showVideoCall = true }
            }
        }
        .frame(height: 92)
    }

    private var composer: some View {
        HStack(spacing: 12) {
            TextField(
                "",
                text: $draft,
                prompt: Text("Message \(displayName)").foregroundColor(ChatC.secondary)
            )
            .font(.system(size: 19, weight: .semibold, design: .rounded))
            .foregroundStyle(ChatC.title)
            .tint(ChatC.accent)
            .padding(.horizontal, 22)
            .frame(height: 64)
            .background(ChatC.card, in: Capsule())
            .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 4)

            Button(action: send) {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 58, height: 58)
                    .background(sendButtonColor, in: Circle())
                    .shadow(color: sendButtonColor.opacity(0.35), radius: 8, x: 0, y: 4)
            }
            .buttonStyle(.plain)
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private var sendButtonColor: Color {
        draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        ? ChatC.accent.opacity(0.45)
        : ChatC.accent
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
            if isMe { Spacer(minLength: 40) }

            VStack(alignment: .leading, spacing: 10) {
                Text(message.text)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .lineSpacing(2)
                    .foregroundStyle(isMe ? Color.white : ChatC.title)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 4) {
                    Spacer(minLength: 20)
                    Text(DMRelativeTimeFormatter.shortTime(from: message.timestamp))
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(isMe ? Color.white.opacity(0.75) : ChatC.secondary)
                    if isMe {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .black))
                            .foregroundStyle(Color.white.opacity(0.8))
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 18)
            .frame(maxWidth: UIScreen.main.bounds.width * 0.80, alignment: .leading)
            .background(isMe ? ChatC.accent : ChatC.card)
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .shadow(color: isMe ? ChatC.accent.opacity(0.22) : .black.opacity(0.05), radius: 10, x: 0, y: 4)

            if !isMe { Spacer(minLength: 40) }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct DMSquareIconButton: View {
    let systemName: String
    let iconSize: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: iconSize, weight: .bold))
                .foregroundStyle(ChatC.accent)
                .frame(width: 58, height: 58)
                .background(ChatC.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 4)
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
                .fill(ChatC.avatarBG)
            Text(initials)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(ChatC.accent)

            if isOnline {
                Circle()
                    .fill(ChatC.online)
                    .frame(width: 15, height: 15)
                    .overlay(Circle().stroke(ChatC.card, lineWidth: 2.5))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }
        }
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
                                .poplurIconShader()
                                .foregroundColor(selected.contains(user.id) ? ChatC.accent : Color.secondary)
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
