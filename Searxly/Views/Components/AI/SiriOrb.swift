//
//  SiriOrb.swift
//  Searxly
//
//  Beautiful, lightweight animated "Siri-like" glass orb for the Searxly Agent.
//  Inspired by open-source patterns (metasidd/Orb, amosgyamfi Siri animations) + Apple's new Liquid Glass.
//  Fully gated behind glassEnabled / reduce motion for performance and accessibility.
//  No new dependencies; pure SwiftUI + Canvas/Timeline where helpful.
//

import SwiftUI

enum AIOrbState {
    case idle
    case thinking
    case responding
}

struct SiriOrb: View {
    let state: AIOrbState
    let size: CGFloat
    let glassEnabled: Bool

    @State private var phase: Double = 0
    @State private var secondaryPhase: Double = 0
    @State private var tertiaryPhase: Double = 0   // extra organic motion for "something happening inside"

    private var isActive: Bool {
        state == .thinking || state == .responding
    }

    private var isThinking: Bool {
        state == .thinking
    }

    var body: some View {
        ZStack {
            // Outer glow — always present when glass enabled, but much stronger and more "alive" when thinking
            if glassEnabled {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.accentColor.opacity(isThinking ? 0.38 : 0.12),
                                Color.blue.opacity(isThinking ? 0.22 : 0.06),
                                .clear
                            ],
                            center: .center,
                            startRadius: size * 0.1,
                            endRadius: size * 0.75
                        )
                    )
                    .frame(width: size * 1.32, height: size * 1.32)
                    .blur(radius: isThinking ? 20 : 10)
                    .scaleEffect(1.0 + sin(phase * .pi * 1.6) * (isThinking ? 0.07 : 0.03))
                    .opacity(isThinking ? 0.85 : 0.55)
                    .animation(.easeInOut(duration: 0.6), value: isThinking)
            }

            // Base soft glow / glass shell (respects reduce)
            orbShell
                .frame(width: size, height: size)

            // === Liquid glassy "S" centerpiece (Searxly) ===
            // Sits in the middle of the orb, feels like it's inside the liquid glass.
            // Integrates with the orb's breathing and gets a strong glow when the model is thinking.
            if glassEnabled {
                centralLiquidS
                    .frame(width: size * 0.58, height: size * 0.58)
                    .scaleEffect(isThinking ? 1.04 : 1.0)
                    .animation(.spring(response: 0.6, dampingFraction: 0.7), value: isThinking)
            }

            // Dynamic layers (only when glass + active for cheap perf)
            if glassEnabled && isActive {
                activeLayers
                    .frame(width: size, height: size)
            } else if !glassEnabled {
                // Static premium fallback for reduced glass: calm ring + subtle center
                staticReducedOrb
                    .frame(width: size, height: size)
            }
        }
        .onAppear {
            // Start perpetual phases for internal movement. Using repeatForever here is the most
            // lightweight way to keep the orb "alive" without a Timer or TimelineView.
            withAnimation(.linear(duration: 3.2).repeatForever(autoreverses: false)) {
                phase = 1
            }
            withAnimation(.linear(duration: 5.8).repeatForever(autoreverses: false)) {
                secondaryPhase = 1
            }
            withAnimation(.linear(duration: 4.1).repeatForever(autoreverses: false)) {
                tertiaryPhase = 1
            }
        }
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        switch state {
        case .idle: "Searxly Agent idle"
        case .thinking: "Searxly Agent thinking"
        case .responding: "Searxly Agent responding"
        }
    }

    // MARK: - Shell (glass or material)

    private var orbShell: some View {
        ZStack {
            // Outer soft blur / glass (stronger ethereal glow when thinking)
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(glassEnabled ? 0.08 : 0.04),
                            Color.white.opacity(glassEnabled ? 0.02 : 0.01),
                            .clear
                        ],
                        center: .center,
                        startRadius: size * 0.15,
                        endRadius: size * 0.52
                    )
                )
                .blur(radius: glassEnabled ? (isThinking ? 11 : 8) : 2)

            Circle()
                .fill(.thinMaterial)
                .opacity(glassEnabled ? 0.55 : 0.75)

            // Subtle liquid glass edge / border
            if glassEnabled {
                Circle()
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.22),
                                Color.white.opacity(0.06),
                                Color.white.opacity(0.14)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.0
                    )
                    .blur(radius: 0.5)
            } else {
                Circle()
                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.8)
            }

            // Calm center "core" — becomes more vibrant and slightly wobbles when thinking
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            (glassEnabled ? Color.accentColor : Color.primary).opacity(isThinking ? 0.48 : (isActive ? 0.35 : 0.18)),
                            .clear
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: size * (isThinking ? 0.42 : 0.38)
                    )
                )
                .scaleEffect(isThinking ? 0.96 : (isActive ? 0.92 : 0.78))
                .offset(
                    x: sin(tertiaryPhase * 2.4) * (isThinking ? 2.2 : 0.8),
                    y: cos(tertiaryPhase * 1.9) * (isThinking ? 1.6 : 0.6)
                )
                .opacity(isThinking ? 0.55 : 0.75) // let the glassy S be the hero in the center
                .animation(.spring(response: 0.6, dampingFraction: 0.8), value: isActive)
        }
    }

    // MARK: - Central liquid glassy "S" (Searxly identity)
    // Beautiful liquid-glass "S" that sits in the middle of the orb.
    // It feels embedded in the glass, gently moves with the orb's phases,
    // and gets a strong integrated glow + life when the model is thinking.
    private var centralLiquidS: some View {
        let sSize = size * 0.72   // dynamic size based on the orb

        return ZStack {
            // Thinking glow behind the S (integrated liquid halo)
            if isThinking {
                Text("S")
                    .font(.system(size: sSize, weight: .black, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                Color.accentColor.opacity(0.9),
                                Color.blue.opacity(0.6)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .blur(radius: sSize * 0.11)
                    .scaleEffect(1.08 + sin(phase * .pi * 1.8) * 0.04)
                    .opacity(0.65)
            }

            // Deep liquid base (soft blurred S for depth/refraction)
            Text("S")
                .font(.system(size: sSize, weight: .black, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.25))
                .blur(radius: 3)
                .offset(
                    x: sin(tertiaryPhase * 1.6) * (isThinking ? 1.5 : 0.6),
                    y: cos(tertiaryPhase * 2.1) * (isThinking ? 1.2 : 0.5)
                )

            // Main glassy S with premium liquid look
            Text("S")
                .font(.system(size: sSize, weight: .black, design: .rounded))
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            Color.white,
                            Color.white.opacity(0.92),
                            Color.accentColor.opacity(isThinking ? 0.35 : 0.15)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: .white.opacity(0.6), radius: isThinking ? 6 : 3, x: 0, y: 1)
                .shadow(color: Color.accentColor.opacity(isThinking ? 0.5 : 0.15), radius: isThinking ? 9 : 2)

            // Liquid edge highlight (thin glassy stroke + top light)
            Text("S")
                .font(.system(size: sSize, weight: .black, design: .rounded))
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(isThinking ? 0.9 : 0.65),
                            Color.white.opacity(0.1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .blendMode(.overlay)
                .blur(radius: 0.6)

            // Extra thinking "liquid life" — the S feels like it's glowing from inside the glass
            if isThinking {
                Text("S")
                    .font(.system(size: sSize, weight: .black, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.7))
                    .blur(radius: 2.5)
                    .scaleEffect(1.01 + sin(phase * .pi * 2.4) * 0.025)
                    .opacity(0.6)
            }
        }
        .scaleEffect(0.82) // size it nicely inside the orb core
        .offset(
            x: sin(phase * 0.9) * (isThinking ? 1.8 : 0.7),
            y: cos(tertiaryPhase * 1.3) * (isThinking ? 1.4 : 0.6)
        )
    }

    // MARK: - Active (thinking/responding) layers — fluid but cheap

    private var activeLayers: some View {
        ZStack {
            // Primary breathing + wave ring (more energetic on thinking)
            Circle()
                .stroke(
                    AngularGradient(
                        colors: [
                            Color.accentColor.opacity(0.55),
                            Color.blue.opacity(0.35),
                            Color.accentColor.opacity(0.55)
                        ],
                        center: .center,
                        startAngle: .degrees(phase * 360),
                        endAngle: .degrees(phase * 360 + 280)
                    ),
                    lineWidth: isThinking ? 4.0 : 2.2
                )
                .frame(width: size * (isThinking ? 0.90 : 0.82),
                       height: size * (isThinking ? 0.90 : 0.82))
                .rotationEffect(.degrees(secondaryPhase * -180))
                .scaleEffect(0.96 + sin(phase * .pi * 2) * (isThinking ? 0.048 : 0.018))
                .blur(radius: isThinking ? 2.2 : 1.5)
                .animation(.easeInOut(duration: 0.35), value: isThinking)

            // Secondary counter-rotating softer band
            Circle()
                .stroke(
                    AngularGradient(
                        colors: [
                            Color.blue.opacity(0.28),
                            Color.accentColor.opacity(0.22),
                            Color.blue.opacity(0.28)
                        ],
                        center: .center,
                        startAngle: .degrees(-phase * 240),
                        endAngle: .degrees(-phase * 240 + 200)
                    ),
                    lineWidth: 1.8
                )
                .frame(width: size * 0.96, height: size * 0.96)
                .rotationEffect(.degrees(phase * 120))
                .opacity(state == .responding ? 0.7 : 0.9)
                .blur(radius: 2.5)

            // Inner pulsing core highlight (glass refraction feel) — stronger + faster when thinking
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(isThinking ? 0.32 : 0.18),
                            .clear
                        ],
                        center: .center,
                        startRadius: size * 0.08,
                        endRadius: size * 0.32
                    )
                )
                .scaleEffect(0.7 + sin(phase * .pi * 2.4) * (isThinking ? 0.16 : 0.12))
                .blur(radius: isThinking ? 4 : 3)
                .offset(
                    x: sin(tertiaryPhase * .pi * 1.7) * (isThinking ? 3.5 : 1.5),
                    y: cos(tertiaryPhase * .pi * 2.3) * (isThinking ? 2.8 : 1.2)
                )
                .animation(.easeInOut(duration: 0.35), value: isThinking)

            // === Internal "something is happening" particles / liquid motion ===
            // Subtle drifting elements inside the glass orb.
            // Kept very light (max 3) to avoid visual glitches/jank during streaming + thinking updates.
            let particleCount = isThinking ? 3 : 2
            ForEach(0..<particleCount, id: \.self) { i in
                let speed = 1.3 + Double(i) * 0.4
                let radius = size * (isThinking ? 0.22 : 0.15)

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.white.opacity(isThinking ? 0.7 : 0.5),
                                Color.accentColor.opacity(isThinking ? 0.45 : 0.25),
                                .clear
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: 2.5
                        )
                    )
                    .frame(width: isThinking ? 4.5 : 3.5, height: isThinking ? 4.5 : 3.5)
                    .offset(
                        x: cos(phase * speed + Double(i) * 1.7) * radius,
                        y: sin(phase * (speed * 0.9) + Double(i) * 2.1) * radius * 0.8
                    )
                    .scaleEffect(0.8 + sin(phase * 2.8 + Double(i)) * (isThinking ? 0.25 : 0.15))
            }
        }
    }

    // MARK: - Reduced glass static fallback (still looks premium)

    private var staticReducedOrb: some View {
        ZStack {
            Circle()
                .fill(.regularMaterial)
                .overlay(
                    Circle()
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.7)
                )

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.primary.opacity(0.22),
                            .clear
                        ],
                        center: .center,
                        startRadius: 4,
                        endRadius: size * 0.42
                    )
                )
                .scaleEffect(0.78)
        }
    }
}

// Convenience for the chat sheet
extension SiriOrb {
    init(state: AIOrbState, size: CGFloat) {
        // Default: derive glass from manager (safe at call sites)
        self.init(
            state: state,
            size: size,
            glassEnabled: !UserDefaults.standard.bool(forKey: "reduceLiquidGlass")
        )
    }
}
