import Foundation

struct ChatUser: Codable, Identifiable, Hashable {
    let id: UUID
    let name: String
    let avatarURL: URL?
    
    init(id: UUID = UUID(), name: String, avatarURL: URL? = nil) {
        self.id = id
        self.name = name
        self.avatarURL = avatarURL
    }
}

struct ChatMessage: Codable, Identifiable, Hashable {
    let id: UUID
    let sender: ChatUser
    let content: String
    let sentDate: Date
    
    init(id: UUID = UUID(), sender: ChatUser, content: String, sentDate: Date = Date()) {
        self.id = id
        self.sender = sender
        self.content = content
        self.sentDate = sentDate
    }
}

struct ConversationThread: Codable, Identifiable, Hashable {
    let id: UUID
    let title: String
    let participants: [ChatUser]
    var messages: [ChatMessage]
    
    init(id: UUID = UUID(), title: String, participants: [ChatUser], messages: [ChatMessage] = []) {
        self.id = id
        self.title = title
        self.participants = participants
        self.messages = messages
    }
}

struct ChatDateFormatter {
    static let shared: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()
}
