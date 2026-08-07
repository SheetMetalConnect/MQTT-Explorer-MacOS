import Foundation
import Observation

/// Mirror of a TopicTreeEngine node, observed by SwiftUI. Only changed nodes
/// are touched when a delta lands, so a payload update re-renders one row.
@Observable
@MainActor
final class UITopicNode {
    let path: String
    let name: String
    var children: [String: UITopicNode] = [:]
    var childOrder: [String] = []
    var messageCount = 0
    var lastUpdate = Date()
    var message: StoredMessage?
    var childCount = 0
    var leafMessageCount = 0
    var childTopicCount = 0
    var expanded = false
    /// MQTT 3.1.1 clears the retain flag on live publishes after subscribe, so
    /// the badge tracks whether the broker ever sent this topic retained.
    var everRetained = false
    @ObservationIgnored weak var parent: UITopicNode?
    /// Bumped on every message so rows can flash an update highlight.
    var updatePulse = 0
    /// Precomputed short preview for the tree row (max 400 chars, decoded).
    var preview: String = ""
    /// Precomputed alongside the preview, so rows never inspect payloads.
    var valueType: MessageRendering.ValueType?

    var id: String { path }

    /// UNS data contracts (`_historian`, `_analytics`, `_process`) mark where a
    /// namespace stops being structure and starts carrying payload.
    var isDataContract: Bool { name.hasPrefix("_") && name.count > 1 }

    init(path: String, name: String) {
        self.path = path
        self.name = name
    }

    func apply(_ update: NodeUpdate) {
        let ownMessageChanged = update.messageCount != messageCount
        messageCount = update.messageCount
        lastUpdate = update.lastUpdate
        childCount = update.childCount
        leafMessageCount = update.leafMessageCount
        childTopicCount = update.childTopicCount
        guard ownMessageChanged else { return }
        message = update.message
        if update.message?.retain == true {
            everRetained = true
        } else if update.message?.payload.isEmpty == true {
            everRetained = false
        }
        updatePulse += 1
        preview = MessageRendering.preview(for: update.message?.payload)
        valueType = MessageRendering.valueType(of: update.message?.payload)
    }
}

/// Flat, renderable slice of the tree: what the List shows.
struct TreeRow: Identifiable, Hashable {
    let path: String
    let depth: Int

    var id: String { path }

    static func == (lhs: TreeRow, rhs: TreeRow) -> Bool {
        lhs.path == rhs.path && lhs.depth == rhs.depth
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(path)
    }
}

enum TopicOrder: String, Codable, CaseIterable, Sendable {
    case none
    case abc
    case messages
    case topics

    var label: String {
        switch self {
        case .none: "As received"
        case .abc: "A → Z"
        case .messages: "Most messages"
        case .topics: "Most topics"
        }
    }
}

/// Holds the mirror tree and turns deltas into UI changes.
@Observable
@MainActor
final class UITreeModel {
    let root = UITopicNode(path: "", name: "")
    @ObservationIgnored private var index: [String: UITopicNode] = [:]

    /// Bumped whenever the set of visible rows can change (structure,
    /// expansion, filter, ordering). Payload-only updates don't bump it.
    private(set) var structureVersion = 0

    /// Flat list of visible rows, recomputed only on structural changes so
    /// payload updates don't invalidate the whole tree view.
    private(set) var rows: [TreeRow] = []

    var filter: String = "" {
        didSet {
            guard oldValue != filter else { return }
            needle = filter.trimmingCharacters(in: .whitespaces)
            structureVersion += 1
            rebuildRows()
        }
    }
    var order: TopicOrder = .none {
        didSet {
            guard oldValue != order else { return }
            structureVersion += 1
            rebuildRows()
        }
    }

    @ObservationIgnored private var needle = ""
    var autoExpandLimit = 0
    var autoExpandDepth = 3

    init() {
        root.expanded = true
        index[""] = root
    }

    var selectedPath: String?

    func node(at path: String) -> UITopicNode? {
        index[path]
    }

    /// Move the selection to the next visible row (or the previous one when
    /// the selection is the first row).
    func selectNextVisible() {
        let rows = visibleRows()
        guard !rows.isEmpty else {
            selectedPath = nil
            return
        }
        guard let selectedPath,
              let current = rows.firstIndex(where: { $0.path == selectedPath }) else {
            return
        }
        let next = current + 1 < rows.count ? current + 1 : max(current - 1, 0)
        self.selectedPath = rows[next].path
    }

    func setExpanded(_ expanded: Bool, path: String) {
        guard let node = index[path] else { return }
        if node.expanded != expanded {
            node.expanded = expanded
            structureVersion += 1
            rebuildRows()
        }
    }

    func toggleExpanded(path: String) {
        guard let node = index[path] else { return }
        node.expanded.toggle()
        structureVersion += 1
        rebuildRows()
    }

    /// Expand every node. Returns false when the tree is too large to expand
    /// safely, leaving it untouched.
    @discardableResult
    func expandAll() -> Bool {
        guard index.count <= Self.autoExpandTopicCeiling else { return false }
        var changed = false
        for node in index.values where !node.expanded && node.childCount > 0 {
            node.expanded = true
            changed = true
        }
        if changed {
            structureVersion += 1
            rebuildRows()
        }
        return true
    }

    func collapseAll() {
        var changed = false
        for node in index.values where node !== root && node.expanded {
            node.expanded = false
            changed = true
        }
        if changed {
            structureVersion += 1
            rebuildRows()
        }
    }

    func clear() {
        root.children.removeAll()
        root.childOrder.removeAll()
        root.message = nil
        root.messageCount = 0
        index = ["": root]
        selectedPath = nil
        structureVersion += 1
        rows = []
    }

    func apply(_ delta: TreeDelta) {
        var structureChanged = false

        for path in delta.removed {
            guard let node = index.removeValue(forKey: path) else { continue }
            if let parent = index[parentPath(of: path)] {
                parent.children.removeValue(forKey: node.name)
                parent.childOrder.removeAll { $0 == node.name }
            }
            if selectedPath == path || selectedPath?.hasPrefix(path + "/") == true {
                selectedPath = parentPath(of: path)
            }
            unindexDescendants(of: node)
            structureChanged = true
        }

        for update in delta.added {
            guard let node = insert(update) else { continue }
            if isVisible(node) { structureChanged = true }
        }

        for update in delta.updated {
            guard let node = index[update.path] else {
                if let inserted = insert(update), isVisible(inserted) {
                    structureChanged = true
                }
                continue
            }
            // Gaining or losing children only matters if the row is on screen.
            if update.childCount != node.childCount, isVisible(node) {
                structureChanged = true
            }
            node.apply(update)
        }

        if structureChanged {
            structureVersion += 1
            rebuildRows()
        }
    }

    // MARK: Keyboard traversal

    func selectAdjacent(delta: Int) {
        guard !rows.isEmpty else {
            selectedPath = nil
            return
        }
        guard let selectedPath,
              let current = rows.firstIndex(where: { $0.path == selectedPath }) else {
            return
        }
        let target = current + delta
        guard target >= 0, target < rows.count else { return }
        self.selectedPath = rows[target].path
    }

    /// Left arrow: collapse the selected node, or move to its parent.
    func collapseSelectedOrMoveOutward() {
        guard let selectedPath, let node = index[selectedPath] else { return }
        if node.expanded && node.childCount > 0 {
            setExpanded(false, path: selectedPath)
        } else {
            let parent = parentPath(of: selectedPath)
            if !parent.isEmpty {
                self.selectedPath = parent
            }
        }
    }

    /// Right arrow: expand the selected node, or move to its first child.
    func expandSelectedOrMoveInward() {
        guard let selectedPath, let node = index[selectedPath] else { return }
        if !node.expanded && node.childCount > 0 {
            setExpanded(true, path: selectedPath)
        } else if node.expanded,
                  let first = visibleChildren(of: node).first {
            self.selectedPath = first.path
        }
    }

    private func visibleChildren(of node: UITopicNode) -> [UITopicNode] {
        node.childOrder.compactMap { node.children[$0] }.filter(matchesFilter)
    }

    private func rebuildRows() {
        var newRows: [TreeRow] = []
        newRows.reserveCapacity(rows.count)
        appendRows(of: root, depth: 0, to: &newRows)
        guard newRows != rows else { return }
        rows = newRows
    }

    /// Depth-first flattening of visible rows, honoring expansion, filter and
    /// ordering. Called by the view when structureVersion changes.
    func visibleRows() -> [TreeRow] {
        var rows: [TreeRow] = []
        appendRows(of: root, depth: 0, to: &rows)
        return rows
    }

    private func appendRows(of node: UITopicNode, depth: Int, to rows: inout [TreeRow]) {
        var children = node.childOrder.compactMap { node.children[$0] }

        switch order {
        case .none:
            break
        case .abc:
            children.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .messages:
            children.sort { $0.leafMessageCount > $1.leafMessageCount }
        case .topics:
            children.sort { $0.childTopicCount > $1.childTopicCount }
        }

        let filtering = !needle.isEmpty
        for child in children {
            if filtering, !matchesFilter(child) {
                // A hidden node can still contain matches, so descend without
                // rendering it. Collapsed subtrees are skipped when unfiltered.
                if child.childCount > 0 {
                    appendRows(of: child, depth: depth, to: &rows)
                }
                continue
            }
            rows.append(TreeRow(path: child.path, depth: depth))
            if child.expanded, child.childCount > 0 {
                appendRows(of: child, depth: depth + 1, to: &rows)
            }
        }
    }

    private func matchesFilter(_ node: UITopicNode) -> Bool {
        if needle.isEmpty { return true }
        return node.path.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    /// Auto-expansion stops once the tree is large: opening thousands of rows
    /// on a busy broker is both unreadable and expensive to lay out.
    static let autoExpandTopicCeiling = 5_000

    private func shouldAutoExpand(_ update: NodeUpdate) -> Bool {
        guard autoExpandLimit > 0, index.count < Self.autoExpandTopicCeiling else { return false }
        guard update.childCount > 0, update.childCount <= autoExpandLimit else { return false }
        let depth = update.path.reduce(1) { $1 == "/" ? $0 + 1 : $0 }
        return depth <= autoExpandDepth
    }

    @discardableResult
    private func insert(_ update: NodeUpdate) -> UITopicNode? {
        guard index[update.path] == nil, let parent = parentMirror(for: update.path) else { return nil }
        let name = update.path.split(separator: "/", omittingEmptySubsequences: false).last.map(String.init) ?? update.path
        let node = UITopicNode(path: update.path, name: name)
        node.apply(update)
        node.expanded = shouldAutoExpand(update)
        node.parent = parent
        parent.children[name] = node
        parent.childOrder.append(name)
        index[update.path] = node
        return node
    }

    /// A row is on screen only when every ancestor is expanded. While a filter
    /// is active the visible set is recomputed anyway, so treat it as visible.
    private func isVisible(_ node: UITopicNode) -> Bool {
        if !needle.isEmpty { return true }
        var current = node.parent
        while let ancestor = current {
            if ancestor !== root, !ancestor.expanded { return false }
            current = ancestor.parent
        }
        return true
    }

    private func unindexDescendants(of node: UITopicNode) {
        var stack = Array(node.children.values)
        while let current = stack.popLast() {
            index.removeValue(forKey: current.path)
            stack.append(contentsOf: current.children.values)
        }
    }

    private func parentMirror(for path: String) -> UITopicNode? {
        index[parentPath(of: path)]
    }

    private func parentPath(of path: String) -> String {
        let segments = path.split(separator: "/", omittingEmptySubsequences: false).dropLast()
        return segments.joined(separator: "/")
    }
}
