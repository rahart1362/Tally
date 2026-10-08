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
    /// D26: at AX5 the system's bottom search capsule is cut flat by the keyboard. R1 (round 2):
    /// a plain top field, below, replaces the system search bar entirely at these sizes, both to
    /// stay above the keyboard and to support wrapping and a custom glyph `.searchable` cannot.
    @Environment(\.dynamicTypeSize) private var typeSize

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
        Group {
            // R1 (ux-fp1 round 2): the system search bar (`.searchable`) cannot wrap a long query
            // or guarantee its own glyph at AX5 — `.navigationBarDrawer` clipped the typed text at
            // its leading edge, dropped the glyph and kept the placeholder at the standard size,
            // none of which a `UISearchBar` exposes a way to fix. At accessibility sizes, a plain
            // field above the results replaces it; below them, `.searchable` is unchanged.
            //
            // Round 3: round 2 hung the field on the results as a top `safeAreaInset`. The first
            // Audit tour to reach it at AX5 (run 37798261057, all 4 AX5 legs) showed the field
            // stop taking input as soon as the results changed state: "northfield" stayed "no",
            // "canvas.northfield.example" stayed "canv" — the first letters that move the screen
            // out of its idle state, when `content` swaps one `List` for another. Hypothesis, not
            // observed directly: the inset's host moves with the `List` it is attached to, and the
            // field loses keyboard focus. A sibling above the results in a `VStack` never moves
            // with them; `SchoolSearchUITests.testTypingAnAddressAtAccessibilityXXXLKeepsEveryCharacter`
            // is the check.
            if typeSize.isAccessibilitySize {
                VStack(spacing: 0) {
                    accessibleSearchField
                    content
                        .listStyle(.plain)
                        .background(TallyColor.bgCanvas)
                }
            } else {
                content
                    .listStyle(.plain)
                    .background(TallyColor.bgCanvas)
                    .searchable(text: queryBinding, prompt: Text(L10n.Onboarding.SchoolSearch.searchPrompt()))
                    .searchFocused($searchFieldFocused)
            }
        }
        .navigationTitle(Text(L10n.Onboarding.SchoolSearch.navigationTitle()))
        // R4 (ux-fp1 round 3): at accessibility sizes the large title never rendered above the
        // field's opaque top inset, leaving an empty ~75 pt band (Gate 2 round 2, all 4 AX5 legs).
        // Inline there, the title sits in the bar between Back and "Can't find it?" and the field
        // starts right under it; below the accessibility sizes, unchanged.
        .navigationBarTitleDisplayMode(typeSize.isAccessibilitySize ? NavigationBarItem.TitleDisplayMode.inline : .large)
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

    /// R1: full width, `TallyTypography.body` (scales with Dynamic Type like the typed text, unlike
    /// the system field's placeholder, which stayed at the standard size), `axis: .vertical` so a
    /// long query wraps onto a second line instead of clipping at the leading edge, and an explicit
    /// glyph (the system field dropped its own at this placement/size).
    private var accessibleSearchField: some View {
        HStack(spacing: TallySpacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(TallyColor.textSecondary)
                .accessibilityHidden(true)
            TextField(String(localized: L10n.Onboarding.SchoolSearch.searchPrompt()), text: queryBinding, axis: .vertical)
                .font(TallyTypography.body)
                .foregroundStyle(TallyColor.textPrimary)
                .focused($searchFieldFocused)
                .submitLabel(.search)
                // Kept so a future test/tour update can find this field directly; the system
                // search bar it replaces here has no identifier of its own either, so nothing
                // that found the old field by identifier is being broken by this.
                .accessibilityIdentifier("schoolSearch.field")
        }
        .padding(.horizontal, TallySpacing.md)
        .padding(.vertical, TallySpacing.sm)
        .frame(minHeight: 44)
        .background(TallyColor.bgCard, in: RoundedRectangle(cornerRadius: TallyRadius.iconTile, style: .continuous))
        .padding(.horizontal, TallySpacing.screenMargin)
        .padding(.vertical, TallySpacing.sm)
        .background(TallyColor.bgCanvas)
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
            // ux-fp2 D20: centred when it fits, scrolling when it does not (AX5).
            .tallyCenteredScrolling()
        case .searchFailed:
            ContentUnavailableView {
                Label(String(localized: L10n.Onboarding.SchoolSearch.searchFailedTitle()), systemImage: "exclamationmark.triangle")
            } description: {
                Text(L10n.Onboarding.SchoolSearch.searchFailedDescription())
            } actions: {
                Button(String(localized: L10n.Onboarding.retry()), action: viewModel.retry)
            }
            .tallyCenteredScrolling()
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
