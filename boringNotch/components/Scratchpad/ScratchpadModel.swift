//
//  ScratchpadModel.swift
//  boringNotch
//
//  Scratchpad: temporary working context storage.
//

import Foundation

struct ScratchTab: Codable, Identifiable, Hashable {
    let id: UUID
    var title: String
    let createdAt: Date
    var updatedAt: Date
    var isPinned: Bool

    init(
        id: UUID = UUID(),
        title: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isPinned: Bool = false
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isPinned = isPinned
    }
}
