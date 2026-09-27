import Foundation
import SwiftUI
import TallyDesignSystem

/// ASC-14 "Explore with Sample Data": the real demo mode (app-store-compliance.md §3.2 option B)
/// — the full tab shell and Dashboard, running over the bundled flagship persona, behind a
/// persistent SAMPLE DATA banner, with an exit back to Welcome. This is what
/// `WelcomeRoute.sampleData` now leads to (replacing the earlier `SampleDataStub` placeholder).
public struct SampleDataRootView: View {
    let onExit: () -> Void

    @State private var model: SampleDataModel?
    @State private var loadError: Error?

    public init(onExit: @escaping () -> Void) {
        self.onExit = onExit
    }

    public var body: some View {
        let _ = NSLog("DEBUG-NAV: SampleDataRootView.body evaluated; model=%@, loadError=%@",
                      "\(model != nil)", "\(loadError != nil)")
        return Group {
            if let model {
                // TEMPORARY diagnostic: isolate the data layer (SampleDataModel.live() +
                // .refresh(), already proven safe when called directly from a hosted test) from
                // the view layer (TabShellView/DashboardView, never exercised by any hosted test
                // since none of them actually render a SwiftUI view). Bypasses TabShellView
                // entirely to see whether this much alone reaches the screen and stays there.
                Text("SAMPLE DATA — loaded \(model.snapshot?.courses.count ?? -1) courses")
                    .task {
                        NSLog("DEBUG-NAV: model branch .task starting refresh")
                        if model.snapshot == nil { await model.refresh() }
                        NSLog("DEBUG-NAV: model branch .task finished refresh; courses=%d",
                              model.snapshot?.courses.count ?? -1)
                    }
            } else if loadError != nil {
                // The bundled fixture resources failed to load — a packaging bug, not a runtime
                // condition a student can hit in a correctly-built app. Honest, not fabricated:
                // no sample data is shown rather than silently falling back to something fake.
                ContentUnavailableView("Sample data unavailable", systemImage: "exclamationmark.triangle",
                                       description: Text("The bundled sample data couldn't be loaded."))
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Back", action: onExit)
                        }
                    }
            } else {
                ProgressView()
                    .task {
                        NSLog("DEBUG-NAV: ProgressView.task firing load()")
                        load()
                        NSLog("DEBUG-NAV: load() returned; model=%@, loadError=%@",
                              "\(model != nil)", "\(String(describing: loadError))")
                    }
            }
        }
    }

    private func load() {
        do {
            model = try SampleDataModel.live()
            NSLog("DEBUG-NAV: SampleDataModel.live() succeeded")
        } catch {
            loadError = error
            NSLog("DEBUG-NAV: SampleDataModel.live() threw: %@", "\(error)")
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
            Button("Exit", action: onExit)
                .font(TallyTypography.caption.weight(.semibold))
        }
        .foregroundStyle(TallyColor.accentOnFill)
        .padding(.horizontal, TallySpacing.screenMargin)
        .padding(.vertical, TallySpacing.sm)
        .frame(maxWidth: .infinity)
        .background(TallyColor.accent)
        // Deliberately NOT `.accessibilityElement(children: .combine)`: that would fold the
        // "Exit" button into one non-interactive combined element, making it untappable for
        // VoiceOver (and unfindable by UI tests) — an interactive control must stay its own
        // element (HIG: never combine children that include a control).
    }
}
