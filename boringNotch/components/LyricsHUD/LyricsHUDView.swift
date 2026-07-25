import SwiftUI
import Defaults
import Combine

struct LyricsHUDView: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject var musicManager = MusicManager.shared
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @State private var currentLine: String = ""
    @State private var scrollOffset: CGFloat = 0
    @State private var hideHUDTask: Task<Void, Never>?
    private let lyricsTimer = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()
    
    var body: some View {
        if coordinator.showLyricsHUD && !coordinator.lyricsHUDHiddenByHover && Defaults[.enableLyricsHUD] && !Defaults[.inlineHUD] {
            GeometryReader { geo in
                let frameWidth = geo.size.width
                Text(currentLine)
                    .font(.caption)
                    .foregroundStyle(
                        Defaults[.playerColorTinting]
                            ? Color(nsColor: musicManager.avgColor).ensureMinimumBrightness(factor: 0.6)
                            : .white
                    )
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .offset(x: scrollOffset)
                    .frame(maxWidth: frameWidth, alignment: .center)
                    .clipped()
                    .onChange(of: currentLine) { _, newLine in
                        scrollOffset = 0
                        let nsFont = NSFont.preferredFont(forTextStyle: .caption1)
                        let textWidth = newLine.size(withAttributes: [.font: nsFont]).width
                        if textWidth > frameWidth {
                            let distance = textWidth - frameWidth + 8
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                withAnimation(.linear(duration: Double(distance) / 30)) {
                                    scrollOffset = -distance
                                }
                            }
                        }
                    }
            }
            .frame(height: 18)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(.black.opacity(0.6))
            )
            .padding(.bottom, 0)
            .padding(.horizontal, 8)
            .transition(.opacity)
            .onReceive(lyricsTimer) { _ in
                updateCurrentLine()
            }
            .onHover { hovering in
                hideHUDTask?.cancel()
                coordinator.isHoveringHUD = hovering
                if hovering {
                    hideHUDTask = Task {
                        try? await Task.sleep(for: .seconds(0.5))
                        guard !Task.isCancelled else { return }
                        await MainActor.run {
                            withAnimation(.easeOut(duration: 0.15)) {
                                coordinator.lyricsHUDHiddenByHover = true
                            }
                        }
                    }
                }
            }
        }
    }
    
    private func updateCurrentLine() {
        guard musicManager.isPlaying else {
            currentLine = ""
            return
        }
        let elapsed: Double = {
            let delta = Date().timeIntervalSince(musicManager.timestampDate)
            let progressed = musicManager.elapsedTime + (delta * musicManager.playbackRate)
            return min(max(progressed, 0), musicManager.songDuration)
        }()
        let line: String = {
            if musicManager.isFetchingLyrics { return "Loading lyrics…" }
            if !musicManager.syncedLyrics.isEmpty {
                return musicManager.lyricLine(at: elapsed)
            }
            let trimmed = musicManager.currentLyrics.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "No lyrics found" : trimmed.replacingOccurrences(of: "\n", with: " ")
        }()
        if line != currentLine {
            currentLine = line
        }
    }
}