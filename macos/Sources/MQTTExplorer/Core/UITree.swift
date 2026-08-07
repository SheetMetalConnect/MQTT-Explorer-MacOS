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
    /// Bumped on every message so rows can flash an update highlight.
    var updatePulse = 0
    /// Precomputed short preview for the tree row (max 400 chars, decoded).
    var preview: String = ""

    var id: String { path }

    init(path: String, name: String) {
        self.path = path
        self.name = name
    }

    func apply(_ update: NodeUpdate) {
        messageCount = update.messageCount
        lastUpdate = update.lastUpdate
        message = update.message
        childCount = update.childCount
        leafMessageCount = update.leafMessageCount
        childTopicCount = update.childTopicCount
        updatePulse += 1
        preview = MessageRendering.preview(for: update.message?.payload)
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
    private var index: [String: UITopicNode] = [:]

    /// Bumped whenever the set of visible rows can change (structure,
    /// expansion, filter, ordering). Payload-only updates don't bump it.
    private(set) var structureVersion = 0

    /// Flat list of visible rows, recomputed only on structural changes so
    /// payload updates don't invalidate the whole tree view.
    private(set) var rows: [TreeRow] = []

    var filter: String = "" {
        didSet {
            structureVersion += 1
            rebuildRows()
        }
    }
    var order: TopicOrder = .none {
        didSet {
            structureVersion += 1
            rebuildRows()
        }
    }
    var autoExpandLimit = 0

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
            // Drop any descendants from the index as well.
            let prefix = path + "/"
            for key in index.keys where key.hasPrefix(prefix) {
                index.removeValue(forKey: key)
            }
            structureChanged = true
        }

        for update in delta.added {
            guard index[update.path] == nil else { continue }
            guard let parent = parentMirror(for: update.path) else { continue }
            let name = update.path.split(separator: "/", omittingEmptySubsequences: false).last.map(String.init) ?? update.path
            let node = UITopicNode(path: update.path, name: name)
            node.apply(update)
            node.expanded = shouldAutoExpand(update)
            parent.children[name] = node
            parent.childOrder.append(name)
            index[update.path] = node
            structureChanged = true
        }

        for update in delta.updated {
            guard let node = index[update.path] else { continue }
            if update.childCount != node.childCount {
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
        appendRows(of: root, depth: 0, to: &newRows)
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

        for child in children {
            if !matchesFilter(child) {
                // A node that doesn't match can still have matching
                // descendants; descend but don't render the node itself.
                if child.childCount > 0 {
                    appendRows(of: child, depth: depth, to: &rows)
                }
                continue
            }
            rows.append(TreeRow(path: child.path, depth: depth))
            if child.expanded {
                appendRows(of: child, depth: depth + 1, to: &rows)
            }
        }
    }

    private func matchesFilter(_ node: UITopicNode) -> Bool {
        let needle = filter.trimmingCharacters(in: .whitespaces)
        if needle.isEmpty { return true }
        return node.path.localizedCaseInsensitiveContains(needle)
    }

    private func shouldAutoExpand(_ update: NodeUpdate) -> Bool {
        autoExpandLimit > 0 && update.childCount > 0 && update.childCount <= autoExpandLimit
    }

    private func parentMirror(for path: String) -> UITopicNode? {
        index[parentPath(of: path)]
    }

    private func parentPath(of path: String) -> String {
        let segments = path.split(separator: "/", omittingEmptySubsequences: false).dropLast()
        return segments.joined(separator: "/")
    }
}
