import Foundation
import Combine
import UserNotifications
import SwiftUI

struct FakeUser: Identifiable, Equatable {
    let id: UUID
    let name: String
}

struct FakeChatThread: Identifiable, Equatable {
    let id: UUID
    let participants: [FakeUser]
    var unreadCount: Int = 0
}

struct FakeMessage: Identifiable, Equatable {
    let id: UUID
    let threadID: UUID
    let sender: FakeUser
    let content: String
    let timestamp: Date
}

@MainActor
class FakeChatStore: ObservableObject {
    private static let maximumMessagesPerThread = 100

    @Published private(set) var threads: [FakeChatThread] = []
    @Published private(set) var messagesByThreadID: [UUID: [FakeMessage]] = [:]
    
    private var users: [FakeUser] = []
    private var timer: Timer?
    
    // The currently active thread ID in the UI; no notification if message arrives in this thread
    @Published var activeThreadID: UUID?
    
    private let notificationCenter = UNUserNotificationCenter.current()
    
    init() {
        seedFakeData()
        requestNotificationAuthorization()
    }
    
    deinit {
        timer?.invalidate()
    }
    
    private func seedFakeData() {
        // Create fake users
        let user1 = FakeUser(id: UUID(), name: "Alice")
        let user2 = FakeUser(id: UUID(), name: "Bob")
        let user3 = FakeUser(id: UUID(), name: "Charlie")
        let user4 = FakeUser(id: UUID(), name: "Diana")
        users = [user1, user2, user3, user4]
        
        // Create fake threads
        let thread1 = FakeChatThread(id: UUID(), participants: [user1, user2])
        let thread2 = FakeChatThread(id: UUID(), participants: [user1, user3])
        let thread3 = FakeChatThread(id: UUID(), participants: [user1, user4])
        
        threads = [thread1, thread2, thread3]
        
        // Seed initial messages for each thread
        messagesByThreadID[thread1.id] = [
            FakeMessage(id: UUID(), threadID: thread1.id, sender: user2, content: "Hey Alice, how are you?", timestamp: Date().addingTimeInterval(-3600)),
            FakeMessage(id: UUID(), threadID: thread1.id, sender: user1, content: "I'm good Bob, thanks!", timestamp: Date().addingTimeInterval(-3500))
        ]
        messagesByThreadID[thread2.id] = [
            FakeMessage(id: UUID(), threadID: thread2.id, sender: user3, content: "Alice, are you coming to the party?", timestamp: Date().addingTimeInterval(-7200))
        ]
        messagesByThreadID[thread3.id] = [
            FakeMessage(id: UUID(), threadID: thread3.id, sender: user4, content: "Don't forget our meeting tomorrow.", timestamp: Date().addingTimeInterval(-1800))
        ]
    }
    
    /// Deliberately does NOT ask. Raising Apple's notification sheet from a
    /// store's init meant a system alert with no Poplur card in front of it,
    /// at whatever moment this happened to be constructed. The ask belongs to
    /// the clay permission card (HomeTwin.tsx →
    /// PoplurPermissionRouting.requestNotificationsAfterPrimer). Posting a
    /// local notification without authorization simply no-ops, which is the
    /// correct behaviour until the user has said yes.
    private func requestNotificationAuthorization() {}
    
    func sendMessage(threadID: UUID, sender: FakeUser, content: String) {
        let newMessage = FakeMessage(id: UUID(), threadID: threadID, sender: sender, content: content, timestamp: Date())
        append(newMessage, to: threadID)

        if let index = threads.firstIndex(where: { $0.id == threadID }) {
            // If sender is not the current user (assumed here as users[0]), increment unread count
            // But for sending message, we consider sender is current user, so reset unreadCount
            if sender == users[0] {
                threads[index].unreadCount = 0
            } else {
                threads[index].unreadCount = min(
                    threads[index].unreadCount + 1,
                    Self.maximumMessagesPerThread
                )
            }
        }
    }
    
    func markThreadAsRead(threadID: UUID) {
        guard let index = threads.firstIndex(where: { $0.id == threadID }) else { return }
        threads[index].unreadCount = 0
    }

    /// The simulation is explicitly leased by the visible chat surface. It is
    /// idempotent so SwiftUI lifecycle callbacks cannot multiply timers.
    func startIncomingMessageSimulation() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.simulateIncomingMessage()
            }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func stopIncomingMessageSimulation() {
        timer?.invalidate()
        timer = nil
    }
    
    private func simulateIncomingMessage() {
        guard timer != nil, !threads.isEmpty, !users.isEmpty else { return }

        // Pick a random thread
        let randomThreadIndex = Int.random(in: 0..<threads.count)
        let thread = threads[randomThreadIndex]

        // Random sender from participants excluding the assumed current user (users[0])
        let possibleSenders = thread.participants.filter { $0 != users[0] }
        guard let sender = possibleSenders.randomElement() else { return }

        // Generate a random fake message content
        let fakeContents = [
            "Hello!",
            "How's it going?",
            "Did you see that?",
            "Let's catch up soon.",
            "I'll send you the files.",
            "Thanks for your help!",
            "Can you call me back?",
            "Check this out!",
            "Meeting at 3PM.",
            "Got it!"
        ]
        let content = fakeContents.randomElement() ?? "Hi!"

        let newMessage = FakeMessage(id: UUID(), threadID: thread.id, sender: sender, content: content, timestamp: Date())
        append(newMessage, to: thread.id)

        // Update unread count if this thread is not active
        if activeThreadID != thread.id {
            threads[randomThreadIndex].unreadCount = min(
                threads[randomThreadIndex].unreadCount + 1,
                Self.maximumMessagesPerThread
            )
            postLocalNotification(for: newMessage, thread: thread)
        }
    }

    private func append(_ message: FakeMessage, to threadID: UUID) {
        var threadMessages = messagesByThreadID[threadID] ?? []
        let overflow = threadMessages.count - Self.maximumMessagesPerThread + 1
        if overflow > 0 {
            threadMessages.removeFirst(overflow)
        }
        threadMessages.append(message)
        messagesByThreadID[threadID] = threadMessages
    }
    
    private func postLocalNotification(for message: FakeMessage, thread: FakeChatThread) {
        let content = UNMutableNotificationContent()
        content.title = "New message from \(message.sender.name)"
        content.body = message.content
        content.sound = .default
        content.threadIdentifier = thread.id.uuidString
        
        // Deliver immediately
        let request = UNNotificationRequest(identifier: message.id.uuidString, content: content, trigger: nil)
        
        notificationCenter.add(request) { error in
            if let error = error {
                // Handle error if needed
                print("Error posting notification: \(error)")
            }
        }
    }
}
