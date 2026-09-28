import Testing
@testable import TallyFeatures

/// UX-WP-07: the welcome screen's brand-moment entrance. Hosted (not a
/// Linux target: `TallyFeatures` is SwiftUI/iOS-only), but the motion
/// decision itself is a pure value type, so it's tested directly rather
/// than through the simulator (ux-ui.md §3.2 stage 1).
@MainActor
@Suite("Welcome brand moment (UX-WP-07)")
struct WelcomeBrandMomentTests {
    @Test("Reduce Motion: no scale or translate, a single short cross-fade")
    func reduceMotionHasNoScaleOrTranslate() {
        let motion = BrandMomentMotion.forReduceMotion(true)
        #expect(motion.markStartScale == 1)
        #expect(motion.markStartOffsetY == 0)
        // Same animation drives both the panel and the wordmark: one stage, not staggered.
        #expect(motion.panelAnimation == motion.wordmarkAnimation)
    }

    @Test("Normal motion: the mark starts smaller and lower, then rises")
    func normalMotionRisesFromBelow() {
        let motion = BrandMomentMotion.forReduceMotion(false)
        #expect(motion.markStartScale < 1)
        #expect(motion.markStartOffsetY > 0)
        // The wordmark fades in on its own stage, staggered after the panel.
        #expect(motion.wordmarkAnimation != motion.panelAnimation)
    }

    @Test("The two variants are distinct")
    func variantsDiffer() {
        #expect(BrandMomentMotion.forReduceMotion(true) != BrandMomentMotion.forReduceMotion(false))
    }
}
