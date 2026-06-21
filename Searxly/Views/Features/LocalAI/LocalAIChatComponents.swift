//
//  LocalAIChatComponents.swift
//  Searxly
//
//  Monochrome, flat building blocks for the redesigned Searxly AI chat.
//  Brand language matches WalletTheme (see brand_black_white): near-black canvas, white/grey ramp,
//  green only for live status. No glass, no accent-blue.
//

import SwiftUI

/// The Searxly hexagon mark, monochrome. Used as the assistant avatar + header glyph.
struct SearxlyChatMark: View {
    var color: Color = WalletTheme.textPrimary
    var lineWidth: CGFloat = 1.4
    var filledDot: Bool = false

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                hexPath(w: w, h: h)
                    .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineJoin: .round))
                if filledDot {
                    Circle()
                        .fill(color)
                        .frame(width: w * 0.20, height: h * 0.20)
                }
            }
        }
    }

    private func hexPath(w: CGFloat, h: CGFloat) -> Path {
        let pts: [(CGFloat, CGFloat)] = [
            (0.50, 0.045), (0.93, 0.29), (0.93, 0.71),
            (0.50, 0.955), (0.07, 0.71), (0.07, 0.29)
        ]
        var p = Path()
        for (i, pt) in pts.enumerated() {
            let cg = CGPoint(x: pt.0 * w, y: pt.1 * h)
            if i == 0 { p.move(to: cg) } else { p.addLine(to: cg) }
        }
        p.closeSubpath()
        return p
    }
}

/// Three softly pulsing dots — the assistant "typing" indicator. Monochrome.
struct TypingDots: View {
    var color: Color = WalletTheme.textSecondary
    @State private var animating = false

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(color)
                    .frame(width: 6, height: 6)
                    .opacity(animating ? 1.0 : 0.3)
                    .animation(
                        .easeInOut(duration: 0.6).repeatForever().delay(Double(i) * 0.18),
                        value: animating
                    )
            }
        }
        .onAppear { animating = true }
        .accessibilityLabel("Searxly AI is thinking")
    }
}
