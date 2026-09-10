import CryptoKit
import Foundation

struct ConversationSummary: Identifiable, Codable {
    let id: UUID
    let title: String
    let updatedAt: Date
}

// One atomic file per conversation, separated by account and backend. No cloud backup/sync.
struct LocalConversationStorage {
    let directory: URL

    init(namespace: String, root: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]) {
        let key = SHA256.hash(data: Data(namespace.utf8)).map { String(format: "%02x", $0) }.joined()
        directory = root.appendingPathComponent("Conversations", isDirectory: true).appendingPathComponent(key, isDirectory: true)
    }

    func summaries() throws -> (items: [ConversationSummary], unreadableCount: Int) {
        guard FileManager.default.fileExists(atPath: directory.path) else { return ([], 0) }
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
        var items: [ConversationSummary] = []
        var unreadableCount = 0
        for file in files {
            do {
                let header = try JSONDecoder().decode(Header.self, from: Data(contentsOf: file))
                guard header.version == 1, header.summary.id.uuidString == file.deletingPathExtension().lastPathComponent else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                items.append(header.summary)
            } catch { unreadableCount += 1 }
        }
        return (items.sorted { $0.updatedAt > $1.updatedAt }, unreadableCount)
    }

    func load(_ id: UUID) throws -> Conversation {
        let saved = try JSONDecoder().decode(SavedConversation.self, from: Data(contentsOf: file(id)))
        guard saved.version == 1, saved.conversation.id == id else { throw CocoaError(.fileReadCorruptFile) }
        return saved.conversation
    }

    func save(_ conversation: Conversation) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        var folder = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try folder.setResourceValues(values)
        let saved = SavedConversation(version: 1,
            summary: ConversationSummary(id: conversation.id, title: conversation.title, updatedAt: conversation.updatedAt),
            conversation: conversation)
        try JSONEncoder().encode(saved).write(to: file(conversation.id), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    func delete(_ id: UUID) throws { try FileManager.default.removeItem(at: file(id)) }

    func deleteAll() throws {
        if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
    }

    private func file(_ id: UUID) -> URL { directory.appendingPathComponent(id.uuidString).appendingPathExtension("json") }
    private struct Header: Decodable { let version: Int; let summary: ConversationSummary }
    private struct SavedConversation: Codable {
        let version: Int
        let summary: ConversationSummary
        let conversation: Conversation
    }
}
