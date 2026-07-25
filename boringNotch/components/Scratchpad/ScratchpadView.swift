//
//  ScratchpadView.swift
//  boringNotch
//
//  Scratchpad UI: VS Code style top tab strip + text editor area.
//  Layout stays within the fixed openNotchSize height (see CLAUDE.md known limits).
//

import SwiftUI
import MarkdownUI

struct ScratchpadView: View {
    @StateObject private var store = ScratchpadStore.shared
    @EnvironmentObject private var vm: BoringViewModel
    @Namespace private var tabHighlight

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            tabStrip
            editor
        }
        .background(WindowFocusRequester().frame(width: 0, height: 0))
        .onAppear {
            if store.isEmpty {
                store.newTab()
            } else if store.selectedTabID == nil {
                store.selectedTabID = store.tabs.first?.id
            }
            // Markdown editing/preview wants room, so Scratchpad defaults to enlarged.
            // The user can still shrink manually; leaving the tab resets to this default.
            store.isEnlarged = true
            vm.applyScratchpadEnlarged(true)
        }
    }

    private var tabStrip: some View {
        HStack(spacing: 4) {
            ScrollView(.horizontal) {
                HStack(spacing: 4) {
                    ForEach(store.tabs) { tab in
                        ScratchTabChip(tab: tab, isSelected: store.selectedTabID == tab.id, highlight: tabHighlight)
                    }
                    Button {
                        store.newTab()
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.gray)
                            .frame(width: 22, height: 22)
                            .background(Color(nsColor: .secondarySystemFill).opacity(0.5))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                }
            }
            .scrollIndicators(.never)

            Spacer(minLength: 4)

            if let selectedID = store.selectedTabID {
                let previewing = store.isPreviewing(selectedID)
                Button {
                    store.togglePreview(selectedID)
                } label: {
                    Image(systemName: previewing ? "pencil" : "eye")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(previewing ? .white : .gray)
                        .frame(width: 22, height: 22)
                        .background(Color(nsColor: .secondarySystemFill).opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .help(previewing ? "编辑" : "预览 Markdown")

                // Hidden ⌘E shortcut mirroring the preview toggle.
                Button("") { store.togglePreview(selectedID) }
                    .buttonStyle(.plain)
                    .frame(width: 0, height: 0)
                    .opacity(0)
                    .keyboardShortcut("e", modifiers: .command)
            }

            Button {
                let next = !store.isEnlarged
                store.isEnlarged = next
                vm.applyScratchpadEnlarged(next)
            } label: {
                Image(systemName: store.isEnlarged
                      ? "arrow.down.right.and.arrow.up.left"
                      : "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.gray)
                    .frame(width: 22, height: 22)
                    .background(Color(nsColor: .secondarySystemFill).opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .help(store.isEnlarged ? "还原" : "放大")
        }
        .frame(height: 26)
    }

    @ViewBuilder
    private var editor: some View {
        if let selectedID = store.selectedTabID {
            Group {
                if store.isPreviewing(selectedID) {
                    ScratchMarkdownPreview(tabID: selectedID)
                } else {
                    ScratchTextEditor(tabID: selectedID)
                        .id(selectedID)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .textBackgroundColor).opacity(0.15))
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "note.text")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white, .gray)
                    .imageScale(.large)
                Text("暂无标签页")
                    .foregroundStyle(.gray)
                    .font(.system(.body, design: .rounded))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// A single tab chip. Double-click the title to rename inline; Return or losing
// focus commits, Escape cancels.
private struct ScratchTabChip: View {
    let tab: ScratchTab
    let isSelected: Bool
    let highlight: Namespace.ID
    private let store = ScratchpadStore.shared
    @State private var isRenaming = false
    @State private var draftTitle = ""
    @State private var showCloseConfirm = false
    @FocusState private var fieldFocused: Bool

    var body: some View {
        Group {
            if showCloseConfirm {
                closeConfirmContent
            } else {
                normalContent
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            ZStack {
                if isSelected {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(nsColor: .secondarySystemFill))
                        .matchedGeometryEffect(id: "selectedTabHighlight", in: highlight)
                }
            }
        )
        .contentShape(Rectangle())
    }

    private var normalContent: some View {
        HStack(spacing: 4) {
            if tab.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(.orange)
            }

            if isRenaming {
                TextField("", text: $draftTitle)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 72)
                    .focused($fieldFocused)
                    .onSubmit { commitRename() }
                    .onExitCommand { cancelRename() }
                    .onChange(of: fieldFocused) { _, focused in
                        if !focused { commitRename() }
                    }
            } else {
                Text(tab.title)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                    .foregroundStyle(isSelected ? .white : .gray)
            }

            Button {
                requestClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.gray)
            }
            .buttonStyle(.plain)
        }
        .onTapGesture {
            withAnimation(.smooth(duration: 0.2)) {
                store.selectedTabID = tab.id
            }
        }
        .contextMenu {
            Button("重命名") { startRename() }
            Button(tab.isPinned ? "取消固定" : "固定") { store.togglePin(tab) }
            Button("关闭", role: .destructive) { requestClose() }
        }
    }

    // Inline close confirmation, rendered inside the notch panel so moving the
    // cursor to it does not leave the panel's hover area (which would dismiss it).
    private var closeConfirmContent: some View {
        HStack(spacing: 6) {
            Text("关闭？")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white)
            Button {
                store.remove(tab)
            } label: {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            Button {
                showCloseConfirm = false
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.gray)
            }
            .buttonStyle(.plain)
        }
    }

    private func requestClose() {
        if store.content(for: tab.id).isEmpty {
            store.remove(tab)
        } else {
            showCloseConfirm = true
        }
    }

    private func startRename() {
        store.selectedTabID = tab.id
        draftTitle = tab.title
        isRenaming = true
        DispatchQueue.main.async { fieldFocused = true }
    }

    private func commitRename() {
        guard isRenaming else { return }
        store.rename(tab.id, to: draftTitle)
        isRenaming = false
    }

    private func cancelRename() {
        isRenaming = false
    }
}

// Markdown preview for one tab. Reads the tab's live content from the store
// (contentCache is updated on every keystroke) and renders it with MarkdownUI.
private struct ScratchMarkdownPreview: View {
    let tabID: ScratchTab.ID
    private let store = ScratchpadStore.shared

    var body: some View {
        let text = store.content(for: tabID)
        ScrollView(.vertical) {
            Group {
                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("空白内容")
                        .foregroundStyle(.gray)
                        .font(.system(size: 12))
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Markdown(text)
                        .markdownTextStyle {
                            FontSize(13)
                        }
                        .textSelection(.enabled)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.never)
    }
}

// Custom NSTextView wrapper. Each instance is bound to ONE fixed tabID. The parent
// applies `.id(tabID)`, so switching tabs remounts a fresh editor — every instance
// only ever reads/writes its own tab, making cross-tab corruption impossible.
private struct ScratchTextEditor: NSViewRepresentable {
    let tabID: ScratchTab.ID
    private let store = ScratchpadStore.shared

    func makeCoordinator() -> Coordinator { Coordinator(tabID: tabID, store: store) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = HorizontalPassThroughScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.autohidesScrollers = true

        let textView = NSTextView()
        textView.delegate = context.coordinator
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.isRichText = false
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 6, height: 6)
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.textContainer?.widthTracksTextView = true

        // Load this tab's content once. Suppress the resulting textDidChange so the
        // initial load is not mistaken for a user edit.
        context.coordinator.isLoading = true
        textView.string = store.content(for: tabID)
        context.coordinator.isLoading = false

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {}

    @MainActor final class Coordinator: NSObject, NSTextViewDelegate {
        let tabID: ScratchTab.ID
        let store: ScratchpadStore
        var isLoading = false

        init(tabID: ScratchTab.ID, store: ScratchpadStore) {
            self.tabID = tabID
            self.store = store
        }

        func textDidChange(_ notification: Notification) {
            guard !isLoading, let tv = notification.object as? NSTextView else { return }
            store.commitContent(tv.string, for: tabID)
        }
    }
}

// Scroll view that keeps vertical scrolling for itself but forwards
// horizontal-dominant scroll events up the responder chain, so the notch panel's
// left/right pan monitor (tab switching) receives the real horizontal delta
// instead of the scroll view consuming it.
private final class HorizontalPassThroughScrollView: NSScrollView {
    override func scrollWheel(with event: NSEvent) {
        if abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) {
            nextResponder?.scrollWheel(with: event)
        } else {
            super.scrollWheel(with: event)
        }
    }
}

// Requests key-window status for the notch panel when Scratchpad is shown,
// so the TextEditor can receive keyboard input. The panel only allows this
// while currentView == .scratchpad (see BoringNotchWindow.canBecomeKey).
private struct WindowFocusRequester: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window, !window.isKeyWindow else { return }
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

#Preview {
    ScratchpadView()
        .environmentObject(BoringViewModel())
        .frame(width: 640, height: 190)
        .background(.black)
}
