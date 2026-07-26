//
//  ScratchpadPersistence.swift
//  boringNotch
//
//  Scratchpad: JSON file persistence. Mirrors ShelfPersistenceService.
//

import Foundation

private struct PersistenceContainer: Codable {
    let tabs: [ScratchTab]
    let contents: [UUID: String]
}

/// Temporary struct for migrating from the old format where content was
/// embedded in ScratchTab. After one save, all data is in the new format.
private struct ScratchTabWithContent: Codable {
    let id: UUID
    let title: String
    let content: String
    let createdAt: Date
    let updatedAt: Date
    let isPinned: Bool
}

final class ScratchpadPersistenceService {
    static let shared = ScratchpadPersistenceService()

    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private init() {
        let fm = FileManager.default
        let support = try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let dir = (support ?? fm.temporaryDirectory).appendingPathComponent("boringNotch", isDirectory: true).appendingPathComponent("Scratchpad", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("tabs.json")
        encoder.outputFormatting = [.prettyPrinted]
        decoder.dateDecodingStrategy = .iso8601
        encoder.dateEncodingStrategy = .iso8601
    }

    func load() -> (tabs: [ScratchTab], contents: [UUID: String]) {
        guard let data = try? Data(contentsOf: fileURL) else { return ([], [:]) }

        // New format: { "tabs": [...], "contents": { "id": "content", ... } }
        if let container = try? decoder.decode(PersistenceContainer.self, from: data) {
            return (container.tabs, container.contents)
        }

        // Migration from old format: [ScratchTabWithContent, ...]
        if let oldTabs = try? decoder.decode([ScratchTabWithContent].self, from: data) {
            let tabs = oldTabs.map { ScratchTab(id: $0.id, title: $0.title, createdAt: $0.createdAt, updatedAt: $0.updatedAt, isPinned: $0.isPinned) }
            let contents = Dictionary(uniqueKeysWithValues: oldTabs.map { ($0.id, $0.content) })
            // Immediately re-save in the new format so the old file is migrated.
            save(tabs, contents: contents)
            return (tabs, contents)
        }

        return ([], [:])
    }

    func save(_ tabs: [ScratchTab], contents: [UUID: String]) {
        let container = PersistenceContainer(tabs: tabs, contents: contents)
        do {
            let data = try encoder.encode(container)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("Failed to save scratchpad tabs: \(error.localizedDescription)")
        }
    }
}