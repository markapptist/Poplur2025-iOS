import SwiftUI

struct ChatThreadListView: View {
    @StateObject private var chatStore: FakeChatStore
    @State private var navigateToThread: FakeChatThread? = nil
    
    init() {
        _chatStore = StateObject(wrappedValue: FakeChatStore())
    }
    
    init(chatStore: FakeChatStore) {
        _chatStore = StateObject(wrappedValue: chatStore)
    }
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(chatStore.threads, id: \.id) { (item: FakeChatThread) in
                    NavigationLink(destination: DMDetailView(thread: item)) {
                        HStack(alignment: .top, spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(Color.blue)
                                    .frame(width: 48, height: 48)
                                Text(initials(for: chatTitle(for: item)))
                                    .font(.headline)
                                    .foregroundColor(.white)
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(chatTitle(for: item))
                                        .font(.headline)
                                    Spacer()
                                }
                                
                                HStack(alignment: .center) {
                                    Text(lastMessagePreview(for: item))
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                    Spacer()
                                    if item.unreadCount > 0 {
                                        Text("\(item.unreadCount)")
                                            .font(.caption2)
                                            .bold()
                                            .padding(6)
                                            .background(Color.red)
                                            .foregroundColor(.white)
                                            .clipShape(Circle())
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.white)
            
            NavigationLink(
                destination: Group {
                    if let thread = navigateToThread {
                        DMDetailView(thread: thread)
                    } else {
                        EmptyView()
                    }
                },
                isActive: Binding(
                    get: { navigateToThread != nil },
                    set: { newValue in if !newValue { navigateToThread = nil } }
                )
            ) {
                EmptyView()
            }
            .hidden()
        }
        .background(Color.white)
        .navigationTitle("Chats")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: { startNewConversation() }) {
                    Image(systemName: "plus")
                }
            }
        }
    }
    
    private func initials(for name: String) -> String {
        let parts = name.split(separator: " ")
        let initials = parts.prefix(2).map { $0.first.map { String($0) } ?? "" }.joined()
        return initials.uppercased()
    }
    
    private func timestampString(for date: Date) -> String {
        let formatter = DateFormatter()
        if Calendar.current.isDateInToday(date) {
            formatter.dateFormat = "h:mm a"
        } else {
            formatter.dateFormat = "MMM d"
        }
        return formatter.string(from: date)
    }
    
    private func chatTitle(for thread: FakeChatThread) -> String {
        // Fallback title using a short form of the id
        // If your model later adds a `displayName`, you can switch to it here.
        let shortId = String(String(describing: thread.id).prefix(6))
        return "Chat \(shortId)"
    }
    
    private func lastMessagePreview(for thread: FakeChatThread) -> String {
        // Derive a preview string safely from available properties on FakeChatThread.
        // If your model later adds a `lastMessagePreview`, switch to it here.
        // Try common fallbacks by name; if none exist, return a placeholder.
        // NOTE: Adjust the property names below to match your model when available.
        if let mirrorPreview = (Mirror(reflecting: thread).children.first { $0.label == "lastMessageText" })?.value as? String, !mirrorPreview.isEmpty {
            return mirrorPreview
        }
        if let mirrorPreview = (Mirror(reflecting: thread).children.first { $0.label == "preview" })?.value as? String, !mirrorPreview.isEmpty {
            return mirrorPreview
        }
        return "No messages yet"
    }
    
    private func startNewConversation() {
        // Attempt to create a new fake thread using minimal assumptions.
        // We derive an ID and rely on fallback title/preview helpers.
        // If your real model has an initializer, replace this with it.
        let newId = UUID()
        // Try to synthesize a FakeChatThread via Mirror-based injection of common fields.
        // If construction fails in your model, consider updating this to use your store's API.
        if let thread = constructFakeThread(id: newId, preview: "Say hi to your new contact!", unread: 0) {
            navigateToThread = thread
        }
    }

    private func constructFakeThread(id: UUID, preview: String, unread: Int) -> FakeChatThread? {
        // Best-effort: if FakeChatThread is a struct with memberwise init, try common initializers via reflection is not possible.
        // Instead, try to find an empty initializer and mutate via KVC-like Mirror (not supported). So we fall back to using a store if available.
        // As a lightweight workaround, navigate to an existing thread if any; otherwise do nothing.
        return chatStore.threads.first
    }
}

struct DMDetailView: View {
    let thread: FakeChatThread
    
    @State private var messages: [Message] = []
    @State private var draft: String = ""
    
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(messages) { msg in
                        HStack {
                            if msg.isIncoming {
                                Text(msg.text)
                                    .padding(10)
                                    .background(Color(white: 0.95))
                                    .foregroundColor(.black)
                                    .cornerRadius(12)
                                Spacer()
                            } else {
                                Spacer()
                                Text(msg.text)
                                    .padding(10)
                                    .background(Color.blue)
                                    .foregroundColor(.white)
                                    .cornerRadius(12)
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.vertical, 12)
            }
            .background(Color.white)

            HStack(spacing: 8) {
                TextField("Message", text: $draft)
                    .textFieldStyle(.roundedBorder)
                Button("Send") { send() }
                    .buttonStyle(.borderedProminent)
            }
            .padding()
            .background(Color.white)
        }
        .navigationTitle(chatTitle(for: thread))
        .background(Color.white)
        .onAppear { seedConversation() }
    }
    
    private func chatTitle(for thread: FakeChatThread) -> String {
        // Fallback title using a short form of the id
        // If your model later adds a `displayName`, you can switch to it here.
        let shortId = String(String(describing: thread.id).prefix(6))
        return "Chat \(shortId)"
    }
    
    private func lastMessagePreview(for thread: FakeChatThread) -> String {
        if let mirrorPreview = (Mirror(reflecting: thread).children.first { $0.label == "lastMessageText" })?.value as? String, !mirrorPreview.isEmpty {
            return mirrorPreview
        }
        if let mirrorPreview = (Mirror(reflecting: thread).children.first { $0.label == "preview" })?.value as? String, !mirrorPreview.isEmpty {
            return mirrorPreview
        }
        return "No messages yet"
    }
    
    struct Message: Identifiable {
        let id = UUID()
        let text: String
        let isIncoming: Bool
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        messages.append(Message(text: text, isIncoming: false))
        draft = ""
        simulateReply(to: text)
    }
    private func simulateReply(to text: String) {
        let replyOptions = [
            "Got it!",
            "Sounds good.",
            "Can you tell me more?",
            "👍",
            "😂",
            "Absolutely!",
            "Let's do it."
        ]
        let reply = replyOptions.randomElement() ?? "Okay"
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            messages.append(Message(text: reply, isIncoming: true))
        }
    }
    
    private func seedConversation() {
        if messages.isEmpty {
            messages = [
                Message(text: "Hey there!", isIncoming: true),
                Message(text: "This is a simulated chat.", isIncoming: true)
            ]
        }
    }
}

