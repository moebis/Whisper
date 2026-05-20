import AppKit
import SwiftUI

class OverlayState: ObservableObject {
    @Published var transcript: String = ""
    @Published var isPolishing: Bool = false
}

private enum OverlayMetrics {
    static let canvasSize = CGSize(width: 384, height: 112)
    static let pillSize = CGSize(width: 344, height: 78)
    static let waveformSize = CGSize(width: 112, height: 42)
    static let visibleBottomOffset: CGFloat = 56
}

class OverlayWindow: NSPanel {
    static let shared = OverlayWindow()
    let state = OverlayState()
    
    private init() {
        // Create a borderless, non-activating panel (so it doesn't take focus away from other apps)
        super.init(
            contentRect: NSRect(origin: .zero, size: OverlayMetrics.canvasSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        self.isReleasedWhenClosed = false
        self.level = .statusBar // Float above other applications
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = false // Disable window shadow to prevent square corners, let SwiftUI render it
        self.ignoresMouseEvents = true // Allow clicks to pass through the HUD
        
        positionAtBottomCenter()
    }
    
    /// Centers the overlay panel horizontally at the bottom of the main screen.
    func positionAtBottomCenter() {
        guard let screen = NSScreen.main else { return }
        let screenRect = screen.visibleFrame
        let windowWidth = OverlayMetrics.canvasSize.width
        let windowHeight = OverlayMetrics.canvasSize.height
        
        // Place it just above the bottom edge of the visible screen area.
        let x = screenRect.origin.x + (screenRect.width - windowWidth) / 2
        let y = screenRect.origin.y + OverlayMetrics.visibleBottomOffset
        
        self.setFrame(NSRect(x: x, y: y, width: windowWidth, height: windowHeight), display: true)
    }
    
    /// Shows the overlay panel with the live audio feed visualizer.
    func show(withLevelObservable audioEngine: AudioEngine) {
        let contentView = NSHostingView(rootView: OverlayView(audioEngine: audioEngine, state: state))
        self.contentView = contentView
        
        positionAtBottomCenter()
        self.orderFrontRegardless()
    }
    
    /// Hides the overlay panel.
    func hide() {
        self.orderOut(nil)
    }
}

// MARK: - SwiftUI Visualizer View

struct OverlayView: View {
    @ObservedObject var audioEngine: AudioEngine
    @ObservedObject var state: OverlayState
    @State private var breath = false
    
    var body: some View {
        ZStack {
            ZStack {
                LiquidGlassBackground(isPolishing: state.isPolishing)
                
                HStack(spacing: 14) {
                    statusGlyph
                    
                    VStack(alignment: .leading, spacing: 3) {
                        Text(state.isPolishing ? "Polishing" : "Listening")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.96))
                        
                        Text(state.isPolishing ? "Refining the transcript" : "Left Control to stop")
                            .font(.system(size: 10.5, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.58))
                    }
                    .frame(width: 110, alignment: .leading)
                    
                    Spacer(minLength: 10)
                    
                    LiquidWaveform(
                        level: CGFloat(audioEngine.audioLevel),
                        isPolishing: state.isPolishing
                    )
                    .frame(width: OverlayMetrics.waveformSize.width, height: OverlayMetrics.waveformSize.height)
                }
                .padding(.horizontal, 20)
            }
            .frame(width: OverlayMetrics.pillSize.width, height: OverlayMetrics.pillSize.height)
            .shadow(color: Color(red: 0.03, green: 0.08, blue: 0.16).opacity(0.38), radius: 24, x: 0, y: 14)
            .onAppear {
                breath = true
            }
        }
        .frame(width: OverlayMetrics.canvasSize.width, height: OverlayMetrics.canvasSize.height)
    }
    
    private var statusGlyph: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            accent.opacity(state.isPolishing ? 0.38 : 0.46),
                            accent.opacity(0.08),
                            .clear
                        ],
                        center: .center,
                        startRadius: 4,
                        endRadius: 28
                    )
                )
                .scaleEffect(breath ? 1.08 : 0.94)
            
            Circle()
                .strokeBorder(.white.opacity(0.18), lineWidth: 1)
                .background(Circle().fill(.white.opacity(0.08)))
            
            Image(systemName: state.isPolishing ? "sparkles" : "mic.fill")
                .font(.system(size: state.isPolishing ? 15 : 16, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.white)
                .shadow(color: accent.opacity(0.7), radius: 8, x: 0, y: 0)
        }
        .frame(width: 42, height: 42)
        .animation(.easeInOut(duration: 1.3).repeatForever(autoreverses: true), value: breath)
    }
    
    private var accent: Color {
        state.isPolishing ? Color(red: 1.0, green: 0.72, blue: 0.32) : Color(red: 0.36, green: 0.85, blue: 1.0)
    }
}

private struct LiquidWaveform: View {
    let level: CGFloat
    let isPolishing: Bool
    
    private let barCount = 15
    
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let activity = visualActivity
            let phase = timeline.date.timeIntervalSinceReferenceDate * (isPolishing ? 2.4 : 1.8 + Double(activity) * 6.2)
            HStack(alignment: .center, spacing: 3) {
                ForEach(0..<barCount, id: \.self) { index in
                    Capsule(style: .continuous)
                        .fill(barGradient(index: index))
                        .opacity(0.42 + activity * 0.58)
                        .frame(width: 3.8, height: barHeight(index: index, phase: phase))
                        .shadow(color: barGlow.opacity(0.18 + activity * 0.46), radius: 3 + activity * 7, x: 0, y: 0)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                Capsule(style: .continuous)
                    .fill(
                        RadialGradient(
                            colors: [barGlow.opacity(0.18 * activity), .clear],
                            center: .center,
                            startRadius: 2,
                            endRadius: 68
                        )
                    )
                    .blur(radius: 10)
            }
            .overlay(alignment: .center) {
                Capsule(style: .continuous)
                    .fill(.white.opacity(0.08 + activity * 0.10))
                    .frame(height: 1)
                    .padding(.horizontal, 4)
                    .blendMode(.screen)
            }
        }
    }
    
    private func barHeight(index: Int, phase: TimeInterval) -> CGFloat {
        let normalizedIndex = CGFloat(index) / CGFloat(max(barCount - 1, 1))
        let centerFalloff = max(0.0, 1.0 - abs(normalizedIndex - 0.5) * 1.62)
        let wave = (sin(phase + Double(index) * 0.72) + 1.0) / 2.0
        let counterWave = (sin(phase * 0.58 - Double(index) * 0.94) + 1.0) / 2.0
        let activity = visualActivity
        let baseShape = 5.0 + centerFalloff * 7.0
        
        if isPolishing {
            let height = baseShape + centerFalloff * 14.0 + CGFloat(wave) * 8.0
            return min(38, max(7, height))
        }
        
        let speechLift = centerFalloff * 27.0 * activity
        let transient = (CGFloat(wave) * 13.0 + CGFloat(counterWave) * 7.0) * activity
        let edgeKick = (1.0 - centerFalloff) * 6.0 * activity
        let height = baseShape + speechLift + transient + edgeKick
        return min(40, max(5, height))
    }
    
    private func barGradient(index: Int) -> LinearGradient {
        let warm = Color(red: 1.0, green: 0.72, blue: 0.34)
        let cyan = Color(red: 0.39, green: 0.88, blue: 1.0)
        let blue = Color(red: 0.48, green: 0.58, blue: 1.0)
        let colors = isPolishing ? [warm, .white.opacity(0.9)] : [cyan, blue]
        return LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
    }
    
    private var barGlow: Color {
        isPolishing ? Color(red: 1.0, green: 0.68, blue: 0.28) : Color(red: 0.34, green: 0.88, blue: 1.0)
    }
    
    private var visualActivity: CGFloat {
        if isPolishing { return 0.48 }
        
        let clampedLevel = min(1.0, max(0.0, level))
        let gated = min(1.0, max(0.0, (clampedLevel - 0.035) / 0.965))
        return pow(gated, 0.72)
    }
}

private struct LiquidGlassBackground: View {
    let isPolishing: Bool
    
    var body: some View {
        ZStack {
            VisualEffectView(material: .hudWindow, blendingMode: .withinWindow)
            
            LinearGradient(
                colors: [
                    .white.opacity(0.18),
                    tint.opacity(0.08),
                    .black.opacity(0.06)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            RadialGradient(
                colors: [tint.opacity(0.22), .clear],
                center: .topTrailing,
                startRadius: 8,
                endRadius: 150
            )
            
            Capsule(style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.48), .white.opacity(0.10), tint.opacity(0.20)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
                .padding(0.5)
            
            Capsule(style: .continuous)
                .stroke(.black.opacity(0.18), lineWidth: 0.5)
                .padding(1.4)
            
            Capsule(style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [.white.opacity(0.32), .clear],
                        startPoint: .top,
                        endPoint: .center
                    )
                )
                .frame(height: 22)
                .padding(.horizontal, 18)
                .offset(y: -21)
                .blur(radius: 7)
                .blendMode(.screen)
        }
        .clipShape(Capsule(style: .continuous))
    }
    
    private var tint: Color {
        isPolishing ? Color(red: 1.0, green: 0.66, blue: 0.24) : Color(red: 0.32, green: 0.82, blue: 1.0)
    }
}

// MARK: - Visual Effect Wrapper

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
