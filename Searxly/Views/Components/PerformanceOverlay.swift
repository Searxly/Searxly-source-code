//
//  PerformanceOverlay.swift
//  Searxly
//
//  Floating performance overlay for Developer Mode.
//  Shows approximate FPS and memory usage.
//

import SwiftUI
import Combine
import Darwin
import CoreVideo

struct PerformanceOverlay: View {
    @State private var fps: Double = 60
    @State private var memoryMB: Double = 0

    private let statsTimer = Timer.publish(every: 0.75, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: "speedometer")
                    .font(.system(size: 11, weight: .medium))
                Text(String(format: "%.1f FPS", fps))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
            }

            HStack(spacing: 6) {
                Image(systemName: "memorychip")
                    .font(.system(size: 11, weight: .medium))
                Text(String(format: "%.1f MB", memoryMB))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
            }

            let stats = TabHibernationManager.shared.stats
            Text("\(stats.active) active • \(stats.hibernated) hibernated • \(stats.total) total")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)

            if stats.active > 0 {
                let perTab = memoryMB / Double(max(stats.active, 1))
                Text(String(format: "%.1f MB / active tab", perTab))
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
        )
        // True render FPS via CVDisplayLink
        .background(
            FPSDisplayLink(fps: $fps)
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
        )
        .onReceive(statsTimer) { _ in
            updateMemoryAndStats()
        }
        .onAppear {
            updateMemoryAndStats()
        }
    }

    private func updateMemoryAndStats() {
        memoryMB = DeveloperSettings.currentMemoryUsageMB()
    }
}

// MARK: - True Render FPS using modern NSView.displayLink (macOS 14+)

private struct FPSDisplayLink: NSViewRepresentable {
    @Binding var fps: Double

    func makeNSView(context: Context) -> NSView {
        let view = FPSView(fps: $fps)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class FPSView: NSView {
    @Binding var fps: Double
    private var displayLink: CADisplayLink?
    private var frameTimes: [CFTimeInterval] = []
    private let maxSamples = 30

    init(fps: Binding<Double>) {
        self._fps = fps
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        setupDisplayLink()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if newWindow == nil {
            stopDisplayLink()
        }
    }

    private func setupDisplayLink() {
        stopDisplayLink()

        // Modern recommended API (macOS 14+ / Sequoia+)
        let link = self.displayLink(target: self, selector: #selector(tick))
        self.displayLink = link
        link.add(to: .main, forMode: .common)
    }

    @objc private func tick(_ link: CADisplayLink) {
        let currentTime = link.timestamp

        if let last = frameTimes.last {
            let delta = currentTime - last
            if delta > 0 {
                frameTimes.append(delta)
                if frameTimes.count > maxSamples {
                    frameTimes.removeFirst()
                }

                let averageDelta = frameTimes.reduce(0, +) / Double(frameTimes.count)
                let newFPS = 1.0 / averageDelta

                DispatchQueue.main.async { [weak self] in
                    self?.fps = min(max(newFPS, 0), 240)
                }
            }
        } else {
            frameTimes.append(currentTime)
        }
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
        frameTimes.removeAll()
    }

    deinit {
        stopDisplayLink()
    }
}

#Preview {
    PerformanceOverlay()
        .padding()
        .background(Color.black)
}