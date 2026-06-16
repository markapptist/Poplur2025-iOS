import Foundation
import SwiftUI

// MARK: - Models
public struct DMUser: Identifiable, Hashable {
    public let id: UUID
    public var displayName: String
    public var handle: String
    public var avatarSystemImage: String

    public init(id: UUID, displayName: String, handle: String, avatarSystemImage: String) {
        self.id = id
        self.displayName = displayName
        self.handle = handle
        self.avatarSystemImage = avatarSystemImage
    }
}

public struct DMMessage: Identifiable, Hashable {
    public let id: UUID
    public let senderID: UUID
    public var text: String
    public var timestamp: Date
    public var isRead: Bool

    public init(id: UUID, senderID: UUID, text: String, timestamp: Date, isRead: Bool) {
        self.id = id
        self.senderID = senderID
        self.text = text
        self.timestamp = timestamp
        self.isRead = isRead
    }
}

public struct DMThread: Identifiable, Hashable {
    public let id: UUID
    public var participantIDs: [UUID] // includes current user id
    public var messages: [DMMessage]

    public init(id: UUID, participantIDs: [UUID], messages: [DMMessage]) {
        self.id = id
        self.participantIDs = participantIDs
        self.messages = messages
    }

    public var lastMessage: DMMessage? { messages.last }
}

// MARK: - Fake Store
@MainActor
public final class FakeDMStore: ObservableObject {
    @Published public private(set) var currentUser: DMUser
    @Published public private(set) var users: [DMUser]
    @Published public private(set) var threads: [DMThread]

    public init(seed: Bool = true) {
        let me = DMUser(id: UUID(), displayName: "You", handle: "you", avatarSystemImage: "person.circle.fill")
        self.currentUser = me
        self.users = [
            DMUser(id: UUID(), displayName: "Mia", handle: "mia", avatarSystemImage: "person.circle.fill"),
            DMUser(id: UUID(), displayName: "Jay", handle: "jay", avatarSystemImage: "person.circle.fill"),
            DMUser(id: UUID(), displayName: "Alex Johnson", handle: "alexj", avatarSystemImage: "person.circle.fill"),
            DMUser(id: UUID(), displayName: "Samira Khan", handle: "samk", avatarSystemImage: "person.crop.circle"),
            DMUser(id: UUID(), displayName: "Diego Morales", handle: "diegom", avatarSystemImage: "person.circle"),
            DMUser(id: UUID(), displayName: "Mina Park", handle: "minap", avatarSystemImage: "person.crop.circle.fill")
        ]
        self.threads = []

        if seed {
            seedThread(with: "Alex Johnson", messages: ["Hey! This is a demo DM thread.", "Reply to keep the conversation going."])
            seedThread(with: "Jay", messages: ["The map animation is ready"])
            seedThread(with: "Mia", messages: ["Let's post at the food market"])
        }
    }

    private func seedThread(with displayName: String, messages: [String]) {
        guard let other = users.first(where: { $0.displayName == displayName }) else { return }
        let thread = createThread(with: [other])
        for message in messages {
            _ = send(message: message, in: thread.id, from: other.id)
        }
    }

    // MARK: - Thread creation (FIXED: reuse existing)
    @discardableResult
    public func createThread(with participants: [DMUser]) -> DMThread {
        let participantIDs = ([currentUser.id] + participants.map { $0.id })
            .reduce(into: [UUID]()) { acc, id in
                if acc.contains(id) == false { acc.append(id) }
            }

        // 🔑 Reuse: find thread with same participants (order-independent)
        if let existingIndex = threads.firstIndex(where: { Set($0.participantIDs) == Set(participantIDs) }) {
            let existing = threads.remove(at: existingIndex)
            threads.insert(existing, at: 0) // move to top like Messages apps
            return existing
        }

        // Otherwise, create a new one
        let thread = DMThread(id: UUID(), participantIDs: participantIDs, messages: [])
        threads.insert(thread, at: 0)
        return thread
    }

    // MARK: - Messaging
    @discardableResult
    public func send(message text: String, in threadID: UUID, from senderID: UUID? = nil) -> DMMessage? {
        guard let index = threads.firstIndex(where: { $0.id == threadID }) else { return nil }

        let sender = senderID ?? currentUser.id
        let msg = DMMessage(
            id: UUID(),
            senderID: sender,
            text: text,
            timestamp: Date(),
            isRead: sender == currentUser.id
        )

        threads[index].messages.append(msg)

        // Move updated thread to top
        let updated = threads.remove(at: index)
        threads.insert(updated, at: 0)

        return msg
    }

    public func markThreadRead(_ threadID: UUID) {
        guard let index = threads.firstIndex(where: { $0.id == threadID }) else { return }
        for i in threads[index].messages.indices {
            threads[index].messages[i].isRead = true
        }
    }

    // MARK: - UI helpers
    public func displayNameForParticipants(_ ids: [UUID]) -> String {
        let others = ids.filter { $0 != currentUser.id }
        let names = others.compactMap { id in users.first(where: { $0.id == id })?.displayName }
        return names.isEmpty ? "Messages" : names.joined(separator: ", ")
    }

    public func user(for id: UUID) -> DMUser? {
        if id == currentUser.id { return currentUser }
        return users.first(where: { $0.id == id })
    }
}
