import SwiftUI

struct ChatHaptics: ViewModifier {
    let isSending: Bool
    let revealProgress: Double?
    let isVisible: Bool
    @Environment(\.scenePhase) private var scenePhase
    @State private var lastRevealPulse: ContinuousClock.Instant?
    @State private var revealPulse = 0

    private var isActive: Bool { isVisible && scenePhase == .active }

    func body(content: Content) -> some View {
        content
            .sensoryFeedback(.impact(weight: .light, intensity: 0.7), trigger: isSending) { old, new in
                isActive && !old && new
            }
            .onChange(of: revealProgress) { old, new in
                guard let new else {
                    lastRevealPulse = nil
                    return
                }
                guard isActive, isSending, new > (old ?? 0), new < 1 else { return }

                // Follow visible text, not network deltas, and avoid buzzing on every animation frame.
                let now = ContinuousClock.now
                if let lastRevealPulse, lastRevealPulse.duration(to: now) < .milliseconds(120) { return }
                lastRevealPulse = now
                revealPulse += 1
            }
            .sensoryFeedback(.impact(weight: .light, intensity: 0.25), trigger: revealPulse) { _, _ in
                isActive && isSending && revealProgress != nil
            }
    }
}
