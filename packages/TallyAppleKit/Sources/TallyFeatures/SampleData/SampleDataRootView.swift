import SwiftUI
import TallyDesignSystem

/// ASC-14 "Explore with Sample Data": the real demo mode (app-store-compliance.md §3.2 option B)
/// — the full Home shell and Dashboard, running over the bundled flagship persona, behind a
/// persistent SAMPLE DATA banner, with an exit back to Welcome. `RootView` shows this for
/// `RootRoute.sample`, a root switch and never a `navigationDestination` push (a pushed `TabView`
/// does not render; see `HomeShellView`).
///
/// This view owns only the sample-data *loading* state. The shell itself comes from `shell`, which
/// `RootView` supplies, so the Home shell is constructed in exactly one file (the hygiene grep
/// gate, perf-app-runtime.md §3 item 2).
public struct SampleDataRootView<Shell: View>: View {
    let onExit: () -> Void
    let shell: (SampleDataModel) -> Shell

    @State private var model: SampleDataModel?
    @State private var loadError: Error?

    public init(onExit: @escaping () -> Void, @ViewBuilder shell: @escaping (SampleDataModel) -> Shell) {
        self.onExit = onExit
        self.shell = shell
    }

    public var body: some View {
        Group {
            if let model {
                shell(model)
                    .task {
                        if model.snapshot == nil { await model.refresh() }
                    }
            } else if loadError != nil {
                // The bundled fixture resources failed to load — a packaging bug, not a runtime
                // condition a student can hit in a correctly-built app. Honest, not fabricated:
                // no sample data is shown rather than silently falling back to something fake.
                // A `NavigationStack` as this root's own root (never pushed), so the toolbar
                // button has somewhere to attach to.
                NavigationStack {
                    ContentUnavailableView("Sample data unavailable", systemImage: "exclamationmark.triangle",
                                           description: Text("The bundled sample data couldn't be loaded."))
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Back", action: onExit)
                            }
                        }
                }
            } else {
                ProgressView()
                    .task { load() }
            }
        }
    }

    private func load() {
        do {
            model = try SampleDataModel.live()
        } catch {
            loadError = error
        }
    }
}

/// The persistent "SAMPLE DATA" banner (ASC-14). Shown above the tab bar on every screen while
/// exploring sample data, with the one way out: "Exit" back to Welcome.
struct SampleDataBanner: View {
    let onExit: () -> Void

    var body: some View {
        HStack {
            Image(systemName: "sparkles")
                .accessibilityHidden(true)
            Text("SAMPLE DATA")
                .font(TallyTypography.caption.weight(.semibold))
            Spacer()
            // A 44 × 44 pt target (HIG minimum). The text alone measured 22 × 14 pt in CI's
            // accessibility hierarchy (run 36363360710), too small to tap reliably.
            Button(action: onExit) {
                Text("Exit")
                    .font(TallyTypography.caption.weight(.semibold))
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
        }
        .foregroundStyle(TallyColor.accentOnFill)
        .padding(.horizontal, TallySpacing.screenMargin)
        .frame(maxWidth: .infinity)
        .background(TallyColor.accent)
        // Deliberately NOT `.accessibilityElement(children: .combine)`: that would fold the
        // "Exit" button into one non-interactive combined element, making it untappable for
        // VoiceOver (and unfindable by UI tests) — an interactive control must stay its own
        // element (HIG: never combine children that include a control).
    }
}
