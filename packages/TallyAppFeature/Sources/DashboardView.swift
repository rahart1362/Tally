import SwiftUI
import TallyDesignSystem

public struct DashboardView: View {
    public init() {}
    public var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Text("Overall Standing").font(.Tally.headline)
                        Text("A- (91.2%)").font(.Tally.largeTitle).foregroundColor(.Tally.primary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .tallyCardStyle().accessibilityElement(children: .combine)
                    
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        Text("Alerts").font(.Tally.title2)
                        Text("Calculus assignment missing").foregroundColor(.Tally.danger)
                        Text("Biology exam tomorrow").foregroundColor(.Tally.warning)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .tallyCardStyle().accessibilityElement(children: .combine)
                }
                .padding()
            }
            .background(Color.Tally.background.ignoresSafeArea())
            .navigationTitle("Dashboard")
        }
    }
}

