import CoreFoundation
import Foundation
import SwiftUI

public enum NativeTabRole: String, Sendable {
    case navigation
    case search
    case action
}

func nativeTabPresentationIdentifier(sourceIdentifier: String, index: Int) -> String {
    "\(sourceIdentifier)#\(index)"
}

func nativeTabPresentationSelectedIdentifier(sourceIdentifiers: [String],
                                             selectedSourceIdentifier: String,
                                             fallbackIndex: Int) -> String {
    let selectedIndex = sourceIdentifiers.firstIndex(of: selectedSourceIdentifier) ?? fallbackIndex
    let sourceIdentifier = sourceIdentifiers.indices.contains(selectedIndex)
        ? sourceIdentifiers[selectedIndex]
        : selectedSourceIdentifier
    return nativeTabPresentationIdentifier(sourceIdentifier: sourceIdentifier, index: selectedIndex)
}

func nativeTabPresentationIsHidden(explicitlyHidden: Bool, hasPushedDestination: Bool,
                                   keepsOnPush: Bool = false) -> Bool {
    explicitlyHidden || (hasPushedDestination && !keepsOnPush)
}

public enum NativeTabPresentationPlacement: String, Sendable {
    case bottom
    case leading

    public init(wire: String?) {
        self = wire.flatMap(Self.init(rawValue:)) ?? .bottom
    }
}

func nativeTabPresentationIsActive(minimumWidth: Double?, minimumHeight: Double?,
                                   windowSize: CGSize) -> Bool {
    if minimumWidth == nil, minimumHeight == nil { return true }
    guard windowSize.width > 0, windowSize.height > 0 else { return false }
    if let minimumWidth, Double(windowSize.width) < minimumWidth { return false }
    if let minimumHeight, Double(windowSize.height) < minimumHeight { return false }
    return true
}

/// What a presenter's tap on a tab does.
enum NativeTabActivation: Equatable {
    /// Sends the tab's own press and leaves `selection` alone. Action tabs
    /// have no screen to show, so selecting them would flash an empty tab.
    case pressAction
    /// The already selected, owning tab was tapped again.
    case reselect
    /// The tab is already selected, so activate it directly.
    case activate
    /// Move `selection`, which activates the tab through `onChange`.
    case select
}

func nativeTabActivation(identifier: String, url: String, isSearch: Bool,
                         selection: String, owningId: String, hasPendingTab: Bool) -> NativeTabActivation {
    if url.isEmpty && !isSearch { return .pressAction }
    if selection == identifier, identifier == owningId, !hasPendingTab { return .reselect }
    if selection == identifier { return .activate }
    return .select
}

/// Indices into the full tab list of the tabs the TabView should declare.
/// Presentation-only tabs exist only while a custom presentation is active.
/// Indices always refer to the full list, so coordinators, descriptor ids and
/// activation stay keyed the same way whichever tabs are left out.
func nativeTabEligibleIndices(presentationOnly: [Bool], usesCustomPresentation: Bool) -> [Int] {
    presentationOnly.indices.filter { usesCustomPresentation || !presentationOnly[$0] }
}

/// Nav-bar actions to draw. While a custom tab presentation is showing,
/// actions flagged `hidden_with_tab_presentation` (PHP
/// `NavAction::hiddenWithTabPresentation()`) are left out because the
/// presentation already offers them; otherwise every action is kept.
func nativeVisibleNavActions(_ actions: [NativeUINode], tabPresentationActive: Bool) -> [NativeUINode] {
    guard tabPresentationActive else { return actions }
    return actions.filter { !$0.props.getBool("hidden_with_tab_presentation") }
}

private struct NativeTabPresentationActiveKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// True while the root tabs draw a custom presentation (side rail)
    /// instead of the stock tab bar. Set by `NativeRootTabsRenderer`.
    var nativeTabPresentationActive: Bool {
        get { self[NativeTabPresentationActiveKey.self] }
        set { self[NativeTabPresentationActiveKey.self] = newValue }
    }
}

/// The tab whose URL is the longest match for `currentUri`, or nil when no
/// candidate URL matches. Path match, so a query on the current URI still
/// belongs to its tab; a tab URL with its own query matches the full URI and
/// wins by being longer. Same rule as `TabBar::highlight()`.
func nativeTabUrlOwnerIndex(currentUri: String, candidates: [(index: Int, url: String)]) -> Int? {
    guard !currentUri.isEmpty else { return nil }
    let currentPath = PerTabNavigationCoordinator.path(of: currentUri)
    var best: (index: Int, length: Int)?
    for candidate in candidates where !candidate.url.isEmpty {
        let isMatch = currentUri == candidate.url
            || currentPath == candidate.url
            || currentPath.hasPrefix(candidate.url + "/")
        if isMatch, candidate.url.count > (best?.length ?? -1) {
            best = (candidate.index, candidate.url.count)
        }
    }
    return best?.index
}

/// The tab that owns `currentUri`, chosen from `candidates` by URL match
/// (see `nativeTabUrlOwnerIndex`). Falls back to the first active
/// candidate, then the first candidate, then 0.
func nativeTabOwningIndex(currentUri: String,
                          candidates: [(index: Int, url: String, isActive: Bool)]) -> Int {
    nativeTabUrlOwnerIndex(currentUri: currentUri,
                           candidates: candidates.map { (index: $0.index, url: $0.url) })
        ?? candidates.first(where: \.isActive)?.index
        ?? candidates.first?.index
        ?? 0
}

/// The index of the tab that owns `currentUri` across ALL tabs, when that tab
/// is not declared right now (a presentation-only tab while the presentation
/// is inactive). The renderer must not sync such a URI into the fallback
/// tab's stack; it asks the fallback tab to activate instead so PHP replaces
/// the URI. Nil when the real owner is declared or nothing matches.
func nativeTabHiddenOwnerIndex(currentUri: String,
                               tabs: [(url: String, isEligible: Bool)]) -> Int? {
    guard let owner = nativeTabUrlOwnerIndex(
        currentUri: currentUri,
        candidates: tabs.enumerated().map { (index: $0.offset, url: $0.element.url) }
    ), !tabs[owner].isEligible else { return nil }
    return owner
}

public struct NativeTabDescriptor: Identifiable, Sendable {
    public let id: String
    public let label: String
    public let accessibilityLabel: String
    public let icon: String
    public let badge: String?
    public let showsNews: Bool
    public let role: NativeTabRole

    public init(id: String, label: String, accessibilityLabel: String, icon: String,
                badge: String?, showsNews: Bool, role: NativeTabRole) {
        self.id = id
        self.label = label
        self.accessibilityLabel = accessibilityLabel
        self.icon = icon
        self.badge = badge
        self.showsNews = showsNews
        self.role = role
    }
}

/// Renders a tab descriptor's NativePHP icon identifier, including app-owned
/// `custom:` assets, with the same resolver used by NativePHP's stock chrome.
public struct NativeTabIcon: View {
    private let name: String
    private let pointSize: CGFloat
    private let relativeTo: Font.TextStyle?

    public init(_ name: String, pointSize: CGFloat = 17,
                relativeTo: Font.TextStyle? = nil) {
        self.name = name
        self.pointSize = pointSize
        self.relativeTo = relativeTo
    }

    public var body: some View {
        NativeIconView(name, pointSize: pointSize, relativeTo: relativeTo)
    }
}

public struct NativeTabPresentationConfiguration {
    private let values: [String: Any]

    public init?(json: String) {
        guard json.utf8.count <= 16_384,
              let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let values = object as? [String: Any],
              Self.depth(of: values) <= 8 else { return nil }
        self.values = values
    }

    private static func depth(of value: Any) -> Int {
        if let object = value as? [String: Any] {
            return 1 + (object.values.map(depth).max() ?? 0)
        }
        if let array = value as? [Any] {
            return 1 + (array.map(depth).max() ?? 0)
        }
        return 0
    }

    public func string(_ key: String) -> String? { values[key] as? String }
    public func bool(_ key: String) -> Bool? { values[key] as? Bool }
    public func number(_ key: String) -> Double? {
        guard let number = values[key] as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        return number.doubleValue
    }
    public func strings(_ key: String) -> [String]? { values[key] as? [String] }
    public func object(_ key: String) -> [String: Any]? { values[key] as? [String: Any] }
}

public struct NativeTabPresentationContext {
    public let tabs: [NativeTabDescriptor]
    public let selectedTabIdentifier: String
    public let configuration: NativeTabPresentationConfiguration
    public let isHidden: Bool
    public let isPushed: Bool
    private let activation: (String) -> Void

    public init(tabs: [NativeTabDescriptor], selectedTabIdentifier: String,
                configuration: NativeTabPresentationConfiguration, isHidden: Bool,
                isPushed: Bool = false,
                activate: @escaping (String) -> Void) {
        self.tabs = tabs
        self.selectedTabIdentifier = selectedTabIdentifier
        self.configuration = configuration
        self.isHidden = isHidden
        self.isPushed = isPushed
        self.activation = activate
    }

    public func activate(_ tabIdentifier: String) {
        guard tabs.contains(where: { $0.id == tabIdentifier }) else { return }
        activation(tabIdentifier)
    }
}

public typealias NativeTabPresenter = (NativeTabPresentationContext) -> AnyView

public final class NativeTabPresentationRegistry {
    public static let shared = NativeTabPresentationRegistry()

    private var presenters: [String: NativeTabPresenter] = [:]
    private var overlays: [String: NativeTabPresenter] = [:]
    private let lock = NSLock()

    private init() {}

    /// Registers a presenter. The first registration for an identifier wins.
    @discardableResult
    public func register(identifier: String, presenter: @escaping NativeTabPresenter) -> Bool {
        register(identifier: identifier, presenter: presenter, overlay: nil)
    }

    /// Registers a presenter with an optional overlay drawn above the tab content.
    /// The presenter and overlay are stored as one pair, so the first registration wins.
    @discardableResult
    public func register(identifier: String, presenter: @escaping NativeTabPresenter,
                         overlay: NativeTabPresenter?) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard presenters[identifier] == nil else {
            Self.diagnostic("Duplicate tab presenter '\(identifier)' ignored; first registration wins.")
            return false
        }
        presenters[identifier] = presenter
        overlays[identifier] = overlay
        return true
    }

    func presenter(for identifier: String) -> NativeTabPresenter? {
        lock.lock()
        defer { lock.unlock() }
        return presenters[identifier]
    }

    func overlay(for identifier: String) -> NativeTabPresenter? {
        lock.lock()
        defer { lock.unlock() }
        return overlays[identifier]
    }

    func resolve(identifier: String,
                 configuration: NativeTabPresentationConfiguration?) -> NativeTabPresenter? {
        guard !identifier.isEmpty, identifier != "system", configuration != nil else { return nil }
        return presenter(for: identifier)
    }

    static func diagnostic(_ message: String) {
#if DEBUG
        print("[NativePHP] \(message)")
#endif
    }

    func resetForTesting() {
        lock.lock()
        presenters.removeAll()
        overlays.removeAll()
        lock.unlock()
    }
}
