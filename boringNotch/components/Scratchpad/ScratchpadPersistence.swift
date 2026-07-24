//
//  ScratchpadPersistence.swift
//  boringNotch
//
//  Scratchpad: JSON file persistence. Mirrors ShelfPersistenceService.
//

import Foundation

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

    func load() -> [ScratchTab] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        guard let tabs = try? decoder.decode([ScratchTab].self, from: data) else {
            print("⚠️ Scratchpad persistence file is not decodable")
            return []
        }
        return tabs
    }

    func save(_ tabs: [ScratchTab]) {
        do {
            let data = try encoder.encode(tabs)
            try data.write(to: fileURL, options: Data.WritingOptions.atomic)
        } catch {
            print("Failed to save scratchpad tabs: \(error.localizedDescription)")
        }
    }
}
