import SwiftUI
import TallyCanvasAPI
import TallyDesignSystem
import TallyStrings

/// UX-WP-08: school search over `InstitutionDirectory` and `ClientRegistry`.
/// Every state in ux-ui.md §3.2.1's table: idle, searching (300 ms debounce,
/// 2+ characters), results, address-typed, no match, and offline. Selecting
/// a school not in the `ClientRegistry` never shows a broken login — it
/// reports `.notEnabled` through `onSelectNotEnabled` so the caller can show
/// the "Ask My School" screen (ux-ui.md: "Never a broken login").
struct SchoolSearchView: View {
    @State private var viewModel: SchoolSearchViewModel
    @FocusState private var searchFieldFocused: Bool
    @State private var showSearchingRow = false
    @State private var showAddressHelp = false

    let onSelectEnabled: (InstitutionMatch, ClientRegistration) -> Void
    let onSelectNotEnabled: (String) -> Void

    init(
        viewModel: SchoolSearchViewModel,
        onSelectEnabled: @escaping (InstitutionMatch, ClientRegistration) -> Void,
        onSelectNotEnabled: @escaping (String) -> Void
    ) {
        _viewModel = State(wrappedValue: viewModel)
        self.onSelectEnabled = onSelectEnabled
        self.onSelectNotEnabled = onSelectNotEnabled
    }

    private var isSearching: Bool { viewModel.state == .searching }

    /// `@State` retains the model instance across re-renders (its contract:
    /// only the *first* `initialValue` for this view's identity is used), but
    /// `$viewModel.query` isn't available for a `@State`-held `@Observable`
    /// class the way it is for a value type or a `@Bindable` — so this is a
    /// small hand-written `Binding` onto the model's own property instead.
    private var queryBinding: Binding<String> {
        Binding(get: { viewModel.query }, set: { viewModel.query = $0 })
    }

    var body: some View {
        content
            .listStyle(.plain)
            .background(TallyColor.bgCanvas)
            .navigationTitle(Text(L10n.Onboarding.SchoolSearch.navigationTitle()))
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: queryBinding, prompt: Text(L10n.Onboarding.SchoolSearch.searchPrompt()))
            .searchFocused($searchFieldFocused)
            .onAppear { searchFieldFocused = true }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(String(localized: L10n.Onboarding.SchoolSearch.cantFindIt())) { showAddressHelp = true }
                        .font(TallyTypography.footnote)
                }
            }
            .sheet(isPresented: $showAddressHelp) { AddressHelpSheet() }
            // "after 400 ms only, to avoid a flash" (ux-ui.md §3.2.1).
            .task(id: isSearching) {
                showSearchingRow = false
                guard isSearching else { return }
                try? await Task.sleep(for: .milliseconds(400))
                if !Task.isCancelled { showSearchingRow = isSearching }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle:
            idleList
        case .searching:
            List { if showSearchingRow { searchingRow } }
        case .results(let matches):
            List(matches, id: \.id) { match in
                Button { select(match) } label: { schoolRow(match) }
                    .buttonStyle(.plain)
            }
        case .addressTyped(let host):
            List { addressRow(host) }
        case .noMatch:
            ScrollView {
                VStack(spacing: TallySpacing.lg) {
                    ContentUnavailableView.search(text: viewModel.query)
                    Text(L10n.Onboarding.SchoolSearch.noMatchHint())
                        .font(TallyTypography.footnote)
                        .foregroundStyle(TallyColor.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, TallySpacing.xxl)
                }
                .padding(.top, TallySpacing.xxl)
            }
        case .offline:
            ContentUnavailableView(
                String(localized: L10n.Onboarding.SchoolSearch.offlineTitle()),
                systemImage: "wifi.slash",
                description: Text(L10n.Onboarding.SchoolSearch.offlineDescription())
            )
        case .searchFailed:
            ContentUnavailableView {
                Label(String(localized: L10n.Onboarding.SchoolSearch.searchFailedTitle()), systemImage: "exclamationmark.triangle")
            } description: {
                Text(L10n.Onboarding.SchoolSearch.searchFailedDescription())
            } actions: {
                Button(String(localized: L10n.Onboarding.retry()), action: viewModel.retry)
            }
        }
    }

    private var idleList: some View {
        List {
            if let recentSchool = viewModel.recentSchool {
                Section(String(localized: L10n.Onboarding.SchoolSearch.recentSectionTitle())) {
                    Button { select(recentSchool) } label: { schoolRow(recentSchool) }
                        .buttonStyle(.plain)
                }
            }
            Section {
                Text(L10n.Onboarding.SchoolSearch.typeAtLeast2Letters())
                    .font(TallyTypography.footnote)
                    .foregroundStyle(TallyColor.textSecondary)
            }
        }
    }

    private var searchingRow: some View {
        HStack(spacing: TallySpacing.sm) {
            ProgressView()
            Text(L10n.Onboarding.SchoolSearch.searching())
                .font(TallyTypography.body)
                .foregroundStyle(TallyColor.textSecondary)
        }
    }

    /// "Row: building.columns, school name (headline, wraps to 2 lines), domain
    /// (subheadline), chevron. 44 pt+ tall" (ux-ui.md §3.2.1).
    private func schoolRow(_ match: InstitutionMatch) -> some View {
        HStack(spacing: TallySpacing.md) {
            Image(systemName: "building.columns")
                .font(.system(.title3))
                .foregroundStyle(TallyColor.accent)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: TallySpacing.xs) {
                Text(match.name)
                    .font(TallyTypography.cardTitle)
                    .foregroundStyle(TallyColor.textPrimary)
                    .lineLimit(2)
                Text(match.host)
                    .font(TallyTypography.subheadline)
                    .foregroundStyle(TallyColor.textSecondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(TallyColor.textSecondary)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    /// "Address typed" row: "Use *canvas.myschool.edu*" (ux-ui.md §3.2.1).
    private func addressRow(_ host: String) -> some View {
        Button { selectAddress(host) } label: {
            HStack(spacing: TallySpacing.md) {
                Image(systemName: "link")
                    .font(.system(.title3))
                    .foregroundStyle(TallyColor.accent)
                    .frame(width: 28)
                (Text(L10n.Onboarding.SchoolSearch.useAddressPrefix()) + Text(host).italic())
                    .font(TallyTypography.cardTitle)
                    .foregroundStyle(TallyColor.textPrimary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(TallyColor.textSecondary)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(localized: L10n.Onboarding.SchoolSearch.useAddressAccessibilityLabel(host)))
    }

    private func select(_ match: InstitutionMatch) {
        switch viewModel.selection(for: match) {
        case .enabled(let match, let registration): onSelectEnabled(match, registration)
        case .notEnabled(let school): onSelectNotEnabled(school)
        }
    }

    private func selectAddress(_ host: String) {
        switch viewModel.selectionForTypedAddress(host) {
        case .enabled(let match, let registration): onSelectEnabled(match, registration)
        case .notEnabled(let school): onSelectNotEnabled(school)
        }
    }
}

/// "Help link ... opens a sheet explaining how to find the address" (ux-ui.md §3.2.1).
private struct AddressHelpSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(L10n.Onboarding.SchoolSearch.addressHelpBody())
                    .font(TallyTypography.body)
                    .foregroundStyle(TallyColor.textPrimary)
                    .padding(TallySpacing.screenMargin)
            }
            .navigationTitle(Text(L10n.Onboarding.SchoolSearch.addressHelpTitle()))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: L10n.Account.done())) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
