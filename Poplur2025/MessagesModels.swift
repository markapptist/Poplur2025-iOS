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
            DMUser(id: UUID(), displayName: "Alex Johnson", handle: "alexj", avatarSystemImage: "person.circle.fill"),
            DMUser(id: UUID(), displayName: "Samira Khan", handle: "samk", avatarSystemImage: "person.crop.circle"),
            DMUser(id: UUID(), displayName: "Diego Morales", handle: "diegom", avatarSystemImage: "person.circle"),
            DMUser(id: UUID(), displayName: "Mina Park", handle: "minap", avatarSystemImage: "person.crop.circle.fill")
        ]
        self.threads = []

        if seed {
            if let other = users.first {
                let thread = createThread(with: [other])
                _ = send(message: "Hey! This is a demo DM thread.", in: thread.id, from: other.id)
                _ = send(message: "Reply to keep the conversation going.", in: thread.id, from: other.id)
            }
        }
    }

    @discardableResult
    public func createThread(with participants: [DMUser]) -> DMThread {
        let ids = [currentUser.id] + participants.map { $0.id }
        let thread = DMThread(id: UUID(), participantIDs: ids, messages: [])
        threads.insert(thread, at: 0)
        return thread
    }

    @discardableResult
    public func send(message text: String, in threadID: UUID, from senderID: UUID? = nil) -> DMMessage? {
        guard let index = threads.firstIndex(where: { $0.id == threadID }) else { return nil }
        let msg = DMMessage(id: UUID(), senderID: senderID ?? currentUser.id, text: text, timestamp: Date(), isRead: senderID == currentUser.id)
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

    public func displayNameForParticipants(_ ids: [UUID]) -> String {
        let others = ids.filter { $0 != currentUser.id }
        let names = others.compactMap { id in users.first(where: { $0.id == id })?.displayName }
        return names.joined(separator: ", ")
    }

    public func user(for id: UUID) -> DMUser? {
        if id == currentUser.id { return currentUser }
        return users.first(where: { $0.id == id })
    }
}
