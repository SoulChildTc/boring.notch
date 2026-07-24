//
//  ScratchpadStore.swift
//  boringNotch
//
//  Scratchpad: state management. Mirrors ShelfStateViewModel (.shared singleton),
//  with debounced (500ms) save on content edits.
//

import Foundation

@MainActor
final class ScratchpadStore: ObservableObject {
    static let shared = ScratchpadStore()

    @Published private(set) var tabs: [ScratchTab] = []

    @Published var selectedTabID: ScratchTab.ID?

    @Published var isEnlarged: Bool = false

    // Live editing content lives here, NOT in @Published tabs, so keystrokes never
    // trigger objectWillChange (which would rebuild every tab chip on each char).
    // Merged back into `tabs` only when saving.
    private var contentCache: [ScratchTab.ID: String] = [:]

    private var saveTask: Task<Void, Never>?

    var isEmpty: Bool { tabs.isEmpty }

    var selectedTab: ScratchTab? {
        guard let selectedTabID else { return nil }
        return tabs.first { $0.id == selectedTabID }
    }

    private init() {
        tabs = ScratchpadPersistenceService.shared.load()
        contentCache = Dictionary(uniqueKeysWithValues: tabs.map { ($0.id, $0.content) })
        selectedTabID = tabs.first?.id
    }

    private func mergedTabs() -> [ScratchTab] {
        tabs.map { tab in
            var copy = tab
            if let cached = contentCache[tab.id], cached != tab.content {
                copy.content = cached
            }
            return copy
        }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        let snapshot = mergedTabs()
        saveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled, self != nil else { return }
            ScratchpadPersistenceService.shared.save(snapshot)
        }
    }

    private func nextUntitledTitle() -> String {
        var index = tabs.count + 1
        let existing = Set(tabs.map { $0.title })
        while existing.contains("未命名-\(index)") {
            index += 1
        }
        return "未命名-\(index)"
    }

    @discardableResult
    func newTab() -> ScratchTab {
        let tab = ScratchTab(title: nextUntitledTitle())
        tabs.append(tab)
        contentCache[tab.id] = ""
        selectedTabID = tab.id
        scheduleSave()
        return tab
    }

    func remove(_ tab: ScratchTab) {
        let removedIndex = tabs.firstIndex { $0.id == tab.id }
        tabs.removeAll { $0.id == tab.id }
        contentCache[tab.id] = nil
        if selectedTabID == tab.id {
            if let removedIndex, removedIndex < tabs.count {
                selectedTabID = tabs[removedIndex].id
            } else {
                selectedTabID = tabs.last?.id
            }
        }
        scheduleSave()
    }

    func togglePin(_ tab: ScratchTab) {
        guard let idx = tabs.firstIndex(where: { $0.id == tab.id }) else { return }
        tabs[idx].isPinned.toggle()
        tabs[idx].updatedAt = Date()
        scheduleSave()
    }

    func rename(_ tabID: ScratchTab.ID, to newTitle: String) {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let idx = tabs.firstIndex(where: { $0.id == tabID }) else { return }
        guard tabs[idx].title != trimmed else { return }
        tabs[idx].title = trimmed
        tabs[idx].updatedAt = Date()
        scheduleSave()
    }

    // Called on every keystroke. Writes to the non-published cache only, so NO
    // view observing the store is invalidated. Only the disk save is scheduled.
    func commitContent(_ content: String, for tabID: ScratchTab.ID) {
        guard contentCache[tabID] != content else { return }
        contentCache[tabID] = content
        scheduleSave()
    }

    func content(for tabID: ScratchTab.ID) -> String {
        contentCache[tabID] ?? tabs.first { $0.id == tabID }?.content ?? ""
    }
}
