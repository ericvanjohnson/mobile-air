import Testing
import SwiftUI
@testable import NativePHP

private func pluginInitializerCompilationFixture() {
    NativeTabPresentationRegistry.shared.register(identifier: "fixture:initializer") { _ in
        AnyView(EmptyView())
    }
}

/// Serialized because several tests reset the shared presenter registry.
@Suite(.serialized)
struct NativePHPTests {

    @Test func example() async throws {
        // Write your test here and use APIs like `#expect(...)` to check expected conditions.
    }

    @Test func tabPresentationRegistryIsDeterministic() async throws {
        let registry = NativeTabPresentationRegistry.shared
        registry.resetForTesting()
        #expect(registry.register(identifier: "acme:floating") { _ in AnyView(EmptyView()) })
        #expect(!registry.register(identifier: "acme:floating") { _ in AnyView(Text("second")) })
        #expect(registry.presenter(for: "acme:floating") != nil)
        #expect(registry.presenter(for: "missing") == nil)
        registry.resetForTesting()
    }

    @Test func tabPresentationResolutionFallsBackUnlessAValidPresenterResolves() throws {
        let registry = NativeTabPresentationRegistry.shared
        registry.resetForTesting()
        defer { registry.resetForTesting() }

        let configuration = try #require(NativeTabPresentationConfiguration(json: "{}"))
        #expect(registry.resolve(identifier: "", configuration: nil) == nil)
        #expect(registry.resolve(identifier: "system", configuration: configuration) == nil)
        #expect(registry.resolve(identifier: "example:missing", configuration: configuration) == nil)

        #expect(registry.register(identifier: "example:available") { _ in AnyView(EmptyView()) })
        #expect(registry.resolve(identifier: "example:available", configuration: nil) == nil)
        #expect(registry.resolve(identifier: "example:available", configuration: configuration) != nil)
    }

    @Test func tabPresentationConfigurationAndActivationAreValidated() async throws {
        let configuration = try #require(NativeTabPresentationConfiguration(
            json: #"{"radius":24,"glass":true,"labels":["Home","Profile"]}"#
        ))
        #expect(configuration.number("radius") == 24)
        #expect(configuration.bool("glass") == true)
        #expect(configuration.number("glass") == nil)
        #expect(configuration.bool("radius") == nil)
        #expect(configuration.strings("labels") == ["Home", "Profile"])
        #expect(NativeTabPresentationConfiguration(json: "[1,2]") == nil)

        var activated: [String] = []
        let context = NativeTabPresentationContext(
            tabs: [NativeTabDescriptor(
                id: "home", label: "Home", accessibilityLabel: "Home", icon: "house",
                badge: nil, showsNews: false, role: .navigation
            )],
            selectedTabIdentifier: "home",
            configuration: configuration,
            isHidden: false,
            activate: { activated.append($0) }
        )
        context.activate("unknown")
        context.activate("home")
        #expect(activated == ["home"])
    }

    @Test func tabPresentationIdentifiersDisambiguateDuplicateSourceIdentifiers() {
        #expect(nativeTabPresentationIdentifier(sourceIdentifier: "home", index: 0) == "home#0")
        #expect(nativeTabPresentationIdentifier(sourceIdentifier: "home", index: 1) == "home#1")
    }

    @Test func tabPresentationSelectionTracksTheLiveSelectedTab() {
        let identifiers = ["home", "profile"]
        #expect(nativeTabPresentationSelectedIdentifier(
            sourceIdentifiers: identifiers,
            selectedSourceIdentifier: "profile",
            fallbackIndex: 0
        ) == "profile#1")
        #expect(nativeTabPresentationSelectedIdentifier(
            sourceIdentifiers: identifiers,
            selectedSourceIdentifier: "missing",
            fallbackIndex: 0
        ) == "home#0")
    }

    @Test func customPresentationUsesEffectiveSystemTabVisibility() {
        #expect(!nativeTabPresentationIsHidden(explicitlyHidden: false, hasPushedDestination: false))
        #expect(nativeTabPresentationIsHidden(explicitlyHidden: true, hasPushedDestination: false))
        #expect(nativeTabPresentationIsHidden(explicitlyHidden: false, hasPushedDestination: true))
    }

    @Test func pluginInitializerCanAccessPublicRegistry() {
        NativeTabPresentationRegistry.shared.resetForTesting()
        pluginInitializerCompilationFixture()
        #expect(NativeTabPresentationRegistry.shared.presenter(for: "fixture:initializer") != nil)
        NativeTabPresentationRegistry.shared.resetForTesting()
    }

    @Test func tabPresentationPlacementParsesWireValues() {
        #expect(NativeTabPresentationPlacement(wire: "leading") == .leading)
        #expect(NativeTabPresentationPlacement(wire: "bottom") == .bottom)
        #expect(NativeTabPresentationPlacement(wire: nil) == .bottom)
        #expect(NativeTabPresentationPlacement(wire: "diagonal") == .bottom)
    }

    @Test func tabPresentationActivationRequiresBothMinimums() {
        func active(_ width: Double, _ height: Double) -> Bool {
            nativeTabPresentationIsActive(minimumWidth: 900, minimumHeight: 600,
                                          windowSize: CGSize(width: width, height: height))
        }

        #expect(active(951, 669))
        #expect(!active(956, 440))
        #expect(!active(669, 951))
        #expect(active(1366, 1024))
        #expect(!active(0, 0))
        #expect(nativeTabPresentationIsActive(minimumWidth: nil, minimumHeight: nil,
                                              windowSize: CGSize(width: 320, height: 480)))
    }

    @Test func tabPresentationKeepsOnPushOnlyWhenAsked() {
        #expect(nativeTabPresentationIsHidden(explicitlyHidden: false, hasPushedDestination: true))
        #expect(!nativeTabPresentationIsHidden(explicitlyHidden: false, hasPushedDestination: true,
                                               keepsOnPush: true))
        #expect(nativeTabPresentationIsHidden(explicitlyHidden: true, hasPushedDestination: false,
                                              keepsOnPush: true))
    }

    @Test func tabPresentationOverlayRegistersWithPresenter() {
        let registry = NativeTabPresentationRegistry.shared
        registry.resetForTesting()
        defer { registry.resetForTesting() }

        #expect(registry.register(identifier: "fixture:overlay",
                                  presenter: { _ in AnyView(EmptyView()) },
                                  overlay: { _ in AnyView(EmptyView()) }))
        #expect(registry.overlay(for: "fixture:overlay") != nil)

        #expect(registry.register(identifier: "fixture:plain") { _ in AnyView(EmptyView()) })
        #expect(registry.overlay(for: "fixture:plain") == nil)
    }

    @Test func tabPresentationWithoutMinimumsIsActiveBeforeLayout() {
        #expect(nativeTabPresentationIsActive(minimumWidth: nil, minimumHeight: nil,
                                              windowSize: .zero))
        #expect(!nativeTabPresentationIsActive(minimumWidth: 900, minimumHeight: nil,
                                               windowSize: .zero))
    }

    @Test func activationForAnActionTabNeverChangesSelection() {
        func activation(_ identifier: String, url: String = "", isSearch: Bool = false,
                        selection: String = "log", owningId: String = "log",
                        hasPendingTab: Bool = false) -> NativeTabActivation {
            nativeTabActivation(identifier: identifier, url: url, isSearch: isSearch,
                                selection: selection, owningId: owningId, hasPendingTab: hasPendingTab)
        }

        #expect(activation("commit") == .pressAction)
        #expect(activation("commit", selection: "commit") == .pressAction)
        #expect(activation("commit", hasPendingTab: true) == .pressAction)

        #expect(activation("search", isSearch: true) == .select)
        #expect(activation("remotes", url: "/remotes") == .select)
        #expect(activation("log", url: "/log") == .reselect)
        #expect(activation("log", url: "/log", hasPendingTab: true) == .activate)
        #expect(activation("remotes", url: "/remotes", selection: "remotes") == .activate)
    }

    @Test func presentationOnlyTabsKeepTheirIndicesWhenFiltered() {
        let presentationOnly = [false, false, true, false]

        #expect(nativeTabEligibleIndices(presentationOnly: presentationOnly,
                                         usesCustomPresentation: false) == [0, 1, 3])
        #expect(nativeTabEligibleIndices(presentationOnly: presentationOnly,
                                         usesCustomPresentation: true) == [0, 1, 2, 3])
        #expect(nativeTabEligibleIndices(presentationOnly: [], usesCustomPresentation: false).isEmpty)
    }

    @Test func navActionsFlaggedForTabPresentationHideOnlyWhileItShows() {
        func action(_ id: Int, flagged: Bool) -> NativeUINode {
            NativeUINode(id: id, type: "top_bar_action", layout: nil, style: nil,
                         props: GenericProps(flagged ? ["hidden_with_tab_presentation": true] : [:]),
                         onPress: 0, onLongPress: 0, children: [])
        }
        let actions = [action(1, flagged: true), action(2, flagged: false)]

        #expect(nativeVisibleNavActions(actions, tabPresentationActive: true).map(\.id) == [2])
        #expect(nativeVisibleNavActions(actions, tabPresentationActive: false).map(\.id) == [1, 2])
        #expect(nativeVisibleNavActions([action(3, flagged: false)], tabPresentationActive: true).map(\.id) == [3])
    }

    @Test func owningTabComesFromEligibleTabsOnly() {
        let tabs: [(index: Int, url: String, isActive: Bool)] = [
            (index: 0, url: "/log", isActive: false),
            (index: 1, url: "/remotes", isActive: false),
            (index: 3, url: "/profile", isActive: true),
        ]

        #expect(nativeTabOwningIndex(currentUri: "/remotes/42", candidates: tabs) == 1)
        #expect(nativeTabOwningIndex(currentUri: "/profile?ref=push", candidates: tabs) == 3)
        #expect(nativeTabOwningIndex(currentUri: "/settings", candidates: tabs) == 3)
        #expect(nativeTabOwningIndex(currentUri: "", candidates: tabs) == 3)
        #expect(nativeTabOwningIndex(currentUri: "/settings", candidates: [
            (index: 2, url: "", isActive: false),
            (index: 4, url: "/log", isActive: false),
        ]) == 2)
        #expect(nativeTabOwningIndex(currentUri: "/log", candidates: []) == 0)
    }

    @Test func owningTabPrefersTheLongestMatchingUrl() {
        let tabs: [(index: Int, url: String, isActive: Bool)] = [
            (index: 0, url: "/remotes", isActive: true),
            (index: 1, url: "/remotes?tab=closed", isActive: false),
            (index: 2, url: "/remotes/archive", isActive: false),
        ]

        #expect(nativeTabOwningIndex(currentUri: "/remotes?tab=closed", candidates: tabs) == 1)
        #expect(nativeTabOwningIndex(currentUri: "/remotes/archive/7", candidates: tabs) == 2)
        #expect(nativeTabOwningIndex(currentUri: "/remotesx", candidates: tabs) == 0)
    }

    @Test func uriOwnedByAHiddenPresentationOnlyTabIsNotSyncedElsewhere() {
        let narrow: [(url: String, isEligible: Bool)] = [
            (url: "/log", isEligible: true),
            (url: "/settings", isEligible: false),
            (url: "", isEligible: false),
        ]

        #expect(nativeTabHiddenOwnerIndex(currentUri: "/settings", tabs: narrow) == 1)
        #expect(nativeTabHiddenOwnerIndex(currentUri: "/settings/keys?x=1", tabs: narrow) == 1)
        #expect(nativeTabHiddenOwnerIndex(currentUri: "/log/42", tabs: narrow) == nil)
        #expect(nativeTabHiddenOwnerIndex(currentUri: "/elsewhere", tabs: narrow) == nil)
        #expect(nativeTabHiddenOwnerIndex(currentUri: "", tabs: narrow) == nil)

        let wide = narrow.map { (url: $0.url, isEligible: true) }
        #expect(nativeTabHiddenOwnerIndex(currentUri: "/settings", tabs: wide) == nil)

        let rootHidden: [(url: String, isEligible: Bool)] = [
            (url: "/", isEligible: false),
            (url: "/log", isEligible: true),
        ]
        #expect(nativeTabHiddenOwnerIndex(currentUri: "/log/7", tabs: rootHidden) == nil)
        #expect(nativeTabHiddenOwnerIndex(currentUri: "/", tabs: rootHidden) == 0)
    }

}
