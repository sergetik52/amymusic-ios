import SwiftUI
import CoreGraphics
import UIKit

// MARK: - Hex Color Extension

public extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch cleaned.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 255, 255, 255)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }

    static let amyPurple = Color.white
    static let amyPurpleBright = Color.white
    static let amyBackground = Color(hex: "#090909")
    static let amySurface = Color(hex: "#121212")
}

// MARK: - iOS 26 Liquid Glass Design System Wrappers & Modifiers

/// Provides native iOS 26 `.glassEffect(...)` and `GlassEffectContainer` styling
/// tailored to AmyMusic's dark obsidian + neon palette aesthetic.
public struct AmyLiquidGlassCardModifier<S: Shape>: ViewModifier {
    public var shape: S
    public var tintColor: Color?
    public var tintOpacity: Double
    public var isInteractive: Bool

    public func body(content: Content) -> some View {
        content
            .background {
                shape
                    .fill(.ultraThinMaterial)
                    .overlay {
                        if let tintColor {
                            shape.fill(tintColor.opacity(tintOpacity * 0.45))
                        }
                    }
                    .overlay {
                        shape.stroke(
                            LinearGradient(
                                colors: [
                                    .white.opacity(0.35),
                                    .white.opacity(0.08),
                                    .white.opacity(0.18)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.8
                        )
                    }
            }
    }
}

public extension View {
    /// Applies iOS 26 Liquid Glass with optional dynamic album palette or theme tinting
    /// and interactive specular highlights on touch/drag.
    func amyLiquidGlass<S: Shape>(
        in shape: S = RoundedRectangle(cornerRadius: 24, style: .continuous),
        tint: Color? = nil,
        tintOpacity: Double = 0.25,
        interactive: Bool = false
    ) -> some View {
        modifier(
            AmyLiquidGlassCardModifier(
                shape: shape,
                tintColor: tint,
                tintOpacity: tintOpacity,
                isInteractive: interactive
            )
        )
    }

    /// Applies authentic Apple Liquid Glass top bar treatment
    func appleLiquidGlassTopBar(
        tint: Color? = nil,
        showBottomSeparator: Bool = true,
        cornerRadius: CGFloat = 0
    ) -> some View {
        modifier(
            AppleLiquidGlassTopBarModifier(
                tintColor: tint,
                showBottomSeparator: showBottomSeparator,
                cornerRadius: cornerRadius
            )
        )
    }

    /// Configures native navigation bar with Apple Liquid Glass material
    func appleLiquidGlassNavigationBar(tint: Color? = nil) -> some View {
        self
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
    }
}

// MARK: - Apple Native Liquid Glass Top Bar Modifier

public struct AppleLiquidGlassTopBarModifier: ViewModifier {
    public var tintColor: Color?
    public var showBottomSeparator: Bool
    public var cornerRadius: CGFloat

    public init(tintColor: Color? = nil, showBottomSeparator: Bool = true, cornerRadius: CGFloat = 0) {
        self.tintColor = tintColor
        self.showBottomSeparator = showBottomSeparator
        self.cornerRadius = cornerRadius
    }

    public func body(content: Content) -> some View {
        content
            .background {
                if cornerRadius > 0 {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay {
                            if let tintColor {
                                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                    .fill(tintColor.opacity(0.16))
                            }
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                .stroke(
                                    LinearGradient(
                                        colors: [
                                            .white.opacity(0.35),
                                            .white.opacity(0.08),
                                            .white.opacity(0.18)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 0.8
                                )
                        }
                } else {
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .overlay {
                            if let tintColor {
                                Rectangle().fill(tintColor.opacity(0.12))
                            }
                        }
                        .overlay(alignment: .bottom) {
                            if showBottomSeparator {
                                Rectangle()
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                .white.opacity(0.0),
                                                .white.opacity(0.20),
                                                .white.opacity(0.0)
                                            ],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .frame(height: 0.8)
                            }
                        }
                }
            }
    }
}

// MARK: - Apple Liquid Glass Interactive Button Style

public struct AppleLiquidGlassButtonStyle<S: Shape>: ButtonStyle {
    public var shape: S
    public var tintColor: Color?
    public var tintOpacity: Double
    public var isFilledAccent: Bool
    public var showStroke: Bool
    public var scaleOnPress: CGFloat

    public init(
        shape: S,
        tintColor: Color? = nil,
        tintOpacity: Double = 0.20,
        isFilledAccent: Bool = false,
        showStroke: Bool = true,
        scaleOnPress: CGFloat = 0.93
    ) {
        self.shape = shape
        self.tintColor = tintColor
        self.tintOpacity = tintOpacity
        self.isFilledAccent = isFilledAccent
        self.showStroke = showStroke
        self.scaleOnPress = scaleOnPress
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                if isFilledAccent {
                    shape
                        .fill(tintColor ?? .white)
                        .overlay {
                            if configuration.isPressed {
                                shape.fill(Color.black.opacity(0.18))
                            }
                        }
                        .overlay {
                            if showStroke {
                                shape.stroke(
                                    LinearGradient(
                                        colors: [
                                            .white.opacity(0.75),
                                            .white.opacity(0.20)
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    ),
                                    lineWidth: 0.85
                                )
                            }
                        }
                } else {
                    shape
                        .fill(.ultraThinMaterial)
                        .overlay {
                            if let tintColor {
                                shape.fill(tintColor.opacity(tintOpacity))
                            }
                        }
                        .overlay {
                            if configuration.isPressed {
                                shape.fill(Color.white.opacity(0.16))
                            }
                        }
                        .overlay {
                            if showStroke {
                                shape.stroke(
                                    LinearGradient(
                                        colors: [
                                            .white.opacity(0.40),
                                            .white.opacity(0.08),
                                            .white.opacity(0.20)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 0.8
                                )
                            }
                        }
                }
            }
            .scaleEffect(configuration.isPressed ? scaleOnPress : 1.0)
            .animation(.spring(response: 0.28, dampingFraction: 0.72), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, isPressed in
                if isPressed {
                    UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                }
            }
    }
}

public extension ButtonStyle where Self == AppleLiquidGlassButtonStyle<Capsule> {
    static var appleLiquidGlass: AppleLiquidGlassButtonStyle<Capsule> {
        AppleLiquidGlassButtonStyle(shape: Capsule())
    }
    static func appleLiquidGlass(tint: Color? = nil, isFilledAccent: Bool = false) -> AppleLiquidGlassButtonStyle<Capsule> {
        AppleLiquidGlassButtonStyle(shape: Capsule(), tintColor: tint, isFilledAccent: isFilledAccent)
    }
}

public extension ButtonStyle where Self == AppleLiquidGlassButtonStyle<Circle> {
    static var appleLiquidGlassCircle: AppleLiquidGlassButtonStyle<Circle> {
        AppleLiquidGlassButtonStyle(shape: Circle())
    }
    static func appleLiquidGlassCircle(tint: Color? = nil, isFilledAccent: Bool = false) -> AppleLiquidGlassButtonStyle<Circle> {
        AppleLiquidGlassButtonStyle(shape: Circle(), tintColor: tint, isFilledAccent: isFilledAccent)
    }
}

public extension ButtonStyle {
    static func appleLiquidGlass<S: Shape>(
        _ shape: S,
        tint: Color? = nil,
        isFilledAccent: Bool = false,
        showStroke: Bool = true
    ) -> AppleLiquidGlassButtonStyle<S> {
        AppleLiquidGlassButtonStyle(shape: shape, tintColor: tint, isFilledAccent: isFilledAccent, showStroke: showStroke)
    }
}

// MARK: - Dedicated Apple Liquid Glass Back Button

public struct AppleLiquidGlassBackButton: View {
    public var title: String
    public var action: () -> Void

    public init(title: String = "Назад", action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .bold))
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
        }
        .buttonStyle(AppleLiquidGlassButtonStyle(shape: Capsule()))
    }
}

// MARK: - Cover Art Palette Extractor (Port of extractPaletteFromImage in AudioPlayerContext.jsx)

public actor PaletteExtractor {
    public static let shared = PaletteExtractor()
    private var cache: [String: TrackPalette] = [:]

    public func extractPalette(from urlString: String?) async -> TrackPalette {
        guard let urlString, !urlString.isEmpty, let url = URL(string: urlString) else {
            return .defaultPalette
        }
        if let cached = cache[urlString] {
            return cached
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let uiImage = UIImage(data: data),
                  let cgImage = uiImage.cgImage else {
                return .defaultPalette
            }
            let palette = computePalette(from: cgImage)
            cache[urlString] = palette
            return palette
        } catch {
            return .defaultPalette
        }
    }

    /// Quantizes cover art on a 48x48 bitmap into 24-unit RGB buckets and scores colorfulness + mid-brightness,
    /// matching `extractPaletteFromImage` in `src/audio/AudioPlayerContext.jsx`.
    private func computePalette(from cgImage: CGImage) -> TrackPalette {
        let width = 48
        let height = 48
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var rawData = [UInt8](repeating: 0, count: height * bytesPerRow)

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: &rawData,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            return .defaultPalette
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        struct Cluster {
            var count: Double = 0
            var rSum: Double = 0
            var gSum: Double = 0
            var bSum: Double = 0
            var brightnessSum: Double = 0
            var saturationSum: Double = 0
        }

        var buckets: [String: Cluster] = [:]

        for idx in stride(from: 0, to: rawData.count, by: 4) {
            let r = Double(rawData[idx])
            let g = Double(rawData[idx + 1])
            let b = Double(rawData[idx + 2])
            let a = Double(rawData[idx + 3])

            if a < 180 { continue }
            let brightness = (r * 299 + g * 587 + b * 114) / 1000
            if brightness < 10 || brightness > 246 { continue }

            let maxC = max(r, g, b)
            let minC = min(r, g, b)
            let saturation = maxC - minC

            let qr = Int((r / 24.0).rounded()) * 24
            let qg = Int((g / 24.0).rounded()) * 24
            let qb = Int((b / 24.0).rounded()) * 24
            let key = "\(qr)-\(qg)-\(qb)"

            var cluster = buckets[key, default: Cluster()]
            cluster.count += 1
            cluster.rSum += r
            cluster.gSum += g
            cluster.bSum += b
            cluster.brightnessSum += brightness
            cluster.saturationSum += saturation
            buckets[key] = cluster
        }

        struct ScoredColor {
            var r: Int
            var g: Int
            var b: Int
            var brightness: Double
            var score: Double
        }

        let scored: [ScoredColor] = buckets.values.compactMap { c in
            guard c.count >= 3 else { return nil }
            let r = Int((c.rSum / c.count).rounded())
            let g = Int((c.gSum / c.count).rounded())
            let b = Int((c.bSum / c.count).rounded())
            let avgBrightness = c.brightnessSum / c.count
            let avgSaturation = c.saturationSum / c.count

            let midBrightness = 1.0 - min(1.0, abs(avgBrightness - 118.0) / 118.0)
            let colorfulness = max(0.12, avgSaturation / 255.0)
            let score = sqrt(c.count) * (0.62 + colorfulness * 1.75) * (0.45 + midBrightness * 0.9)
            return ScoredColor(r: r, g: g, b: b, brightness: avgBrightness, score: score)
        }.sorted { $0.score > $1.score }

        guard let primary = scored.first else {
            return .defaultPalette
        }

        let secondary = scored.dropFirst().first { cand in
            let dist = abs(cand.r - primary.r) + abs(cand.g - primary.g) + abs(cand.b - primary.b)
            return dist > 58
        } ?? primary

        func toHex(_ r: Int, _ g: Int, _ b: Int) -> String {
            String(format: "#%02x%02x%02x", min(255, max(0, r)), min(255, max(0, g)), min(255, max(0, b)))
        }

        func shade(_ c: ScoredColor, factor: Double) -> String {
            toHex(Int(Double(c.r) * factor), Int(Double(c.g) * factor), Int(Double(c.b) * factor))
        }

        func boostBright(_ c: ScoredColor) -> String {
            toHex(min(255, Int(Double(c.r) * 1.28 + 32)), min(255, Int(Double(c.g) * 1.28 + 32)), min(255, Int(Double(c.b) * 1.28 + 32)))
        }

        let brighter = secondary.brightness > primary.brightness ? secondary : primary

        return TrackPalette(
            base: shade(primary, factor: 0.42),
            line: toHex(primary.r, primary.g, primary.b),
            bright: boostBright(brighter),
            shadow: shade(primary, factor: 0.22)
        )
    }
}

// MARK: - Audio-Reactive Fluid Mesh Background (Port of FullPlayerOverlay & WaveView Fluid Blobs)

public struct FluidMeshBackgroundView: View {
    public var palette: TrackPalette
    public var energy: AudioEnergy
    public var isPlaying: Bool

    public init(palette: TrackPalette, energy: AudioEnergy = .zero, isPlaying: Bool = false) {
        self.palette = palette
        self.energy = energy
        self.isPlaying = isPlaying
    }

    public var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isPlaying)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let bassBoost = isPlaying ? energy.bass * 0.28 : 0
            let midBoost = isPlaying ? energy.mids * 0.22 : 0

            ZStack {
                Color.amyBackground.ignoresSafeArea()

                if #available(iOS 18.0, *) {
                    MeshGradient(
                        width: 3,
                        height: 3,
                        points: [
                            [0.0, 0.0], [0.5, 0.0], [1.0, 0.0],
                            [0.0, 0.5],
                            [
                                Float(0.5 + 0.14 * sin(t * 0.45) + bassBoost * 0.2),
                                Float(0.5 + 0.14 * cos(t * 0.38) - midBoost * 0.2)
                            ],
                            [1.0, 0.5],
                            [0.0, 1.0], [0.5, 1.0], [1.0, 1.0]
                        ],
                        colors: [
                            Color(hex: palette.shadow), Color(hex: palette.base), Color.black,
                            Color(hex: palette.base), Color(hex: palette.line).opacity(0.75 + bassBoost), Color(hex: palette.shadow),
                            Color.black, Color(hex: palette.bright).opacity(0.42 + midBoost), Color(hex: palette.base)
                        ]
                    )
                    .ignoresSafeArea()
                }

                // Organic floating blurred orbs matching .animate-fluid-blob-1..3 in src/main.css
                GeometryReader { geo in
                    let w = geo.size.width
                    let h = geo.size.height

                    Circle()
                        .fill(Color(hex: palette.line).opacity(0.45))
                        .frame(width: w * (0.78 + bassBoost), height: w * (0.78 + bassBoost))
                        .blur(radius: 75)
                        .offset(
                            x: sin(t * 0.35) * 44 - w * 0.12,
                            y: cos(t * 0.28) * 36 - h * 0.08
                        )

                    Circle()
                        .fill(Color(hex: palette.bright).opacity(0.32))
                        .frame(width: w * (0.65 + midBoost), height: w * (0.65 + midBoost))
                        .blur(radius: 85)
                        .offset(
                            x: cos(t * 0.31) * 52 + w * 0.22,
                            y: sin(t * 0.42) * 48 + h * 0.25
                        )

                    Circle()
                        .fill(Color(hex: palette.base).opacity(0.55))
                        .frame(width: w * 0.85, height: w * 0.85)
                        .blur(radius: 80)
                        .offset(
                            x: sin(t * 0.22 + 1.4) * 38,
                            y: cos(t * 0.29 + 0.8) * 55 + h * 0.15
                        )
                }
                .ignoresSafeArea()

                LinearGradient(
                    colors: [
                        .black.opacity(0.35),
                        .clear,
                        .black.opacity(0.68)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            }
        }
    }
}


