import SwiftUI

// MARK: - In-App Floating Mini-Karaoke Window (Port of MiniKaraoke in src/App.jsx)

public struct MiniKaraokeFloatingOverlay: View {
    @Bindable var player: AudioPlayerManager
    @Binding var isPresented: Bool
    var onExpandFullPlayer: () -> Void

    @State private var dragOffset: CGSize = .zero

    public var body: some View {
        let palette = player.currentTrack?.palette ?? .defaultPalette
        let activeIdx = LyricsService.activeLyricIndex(
            in: player.currentLyrics.lines,
            currentTime: player.currentTime,
            offsetMs: player.currentTrackLyricsOffsetMs()
        )

        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                AsyncImage(url: URL(string: player.currentTrack?.coverUrl ?? "")) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Color.white.opacity(0.12)
                }
                .frame(width: 34, height: 34)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(player.currentTrack?.title ?? "Нет трека")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(player.currentTrack?.artist ?? "AmyMusic")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.65))
                        .lineLimit(1)
                }

                Spacer()

                Button {
                    onExpandFullPlayer()
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(AppleLiquidGlassButtonStyle(shape: Circle()))

                Button {
                    withAnimation(.spring(duration: 0.3)) {
                        isPresented = false
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(AppleLiquidGlassButtonStyle(shape: Circle()))
            }

            Divider().overlay(.white.opacity(0.12))

            if player.currentLyrics.lines.isEmpty {
                Text("Текст для этого трека не найден")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 18)
            } else {
                let sliceStart = max(0, (activeIdx ?? 0) - 1)
                let sliceEnd = min(player.currentLyrics.lines.count, sliceStart + 4)
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(player.currentLyrics.lines[sliceStart..<sliceEnd].enumerated()), id: \.element.id) { offset, line in
                        let globalIdx = sliceStart + offset
                        let isCurrent = globalIdx == activeIdx
                        Button {
                            player.seek(to: line.time)
                        } label: {
                            Text(line.text)
                                .font(.system(size: isCurrent ? 15 : 13, weight: isCurrent ? .bold : .medium))
                                .foregroundStyle(isCurrent ? .white : .white.opacity(0.42))
                                .blur(radius: isCurrent ? 0 : 0.8)
                                .lineLimit(2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .animation(.spring(duration: 0.28), value: activeIdx)
            }
        }
        .padding(14)
        .frame(width: 300)
        .amyLiquidGlass(
            in: RoundedRectangle(cornerRadius: 24, style: .continuous),
            tint: Color(hex: palette.shadow),
            tintOpacity: 0.55,
            interactive: true
        )
        .shadow(color: .black.opacity(0.45), radius: 24, y: 12)
        .offset(dragOffset)
        .gesture(
            DragGesture()
                .onChanged { value in
                    dragOffset = value.translation
                }
        )
    }
}
