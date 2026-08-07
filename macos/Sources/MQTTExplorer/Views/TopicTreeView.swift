import SwiftUI

/// The topic tree, a native macOS list with standard selection. The root row
/// shows the broker host; rows are expander + bold name + collapsed counts +
/// " = preview". Click selects and toggles, arrow keys navigate, Delete
/// clears a topic recursively.
struct TopicTreeView: View {
    @Bindable var model: AppModel
    @FocusState private var searchFocused: Bool

    /// Route List selection changes through selectTopic so the publish topic
    /// follows the selection and the compare message resets.
    private var selection: Binding<String?> {
        Binding(
            get: { model.tree.selectedPath },
            set: { path in
                if let path { model.selectTopic(path) }
            }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            treeList
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusSearch)) { _ in
            searchFocused = true
        }
    }

    /// Filter field and expand/collapse-all controls above the tree.
    private var header: some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                    .imageScale(.small)
                    .foregroundStyle(.secondary)
                TextField("Filter topics", text: $model.settings.topicFilter)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                if !model.settings.topicFilter.isEmpty {
                    Button {
                        model.settings.topicFilter = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .help("Clear filter")
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 5).fill(.quaternary.opacity(0.5)))

            Spacer(minLength: 0)

            Button {
                if !model.tree.expandAll() {
                    model.showNotification("Too many topics to expand at once. Use the filter to narrow down.")
                }
            } label: {
                Image(systemName: "rectangle.expand.vertical")
            }
            .buttonStyle(.borderless)
            .help("Expand all topics")

            Button {
                model.tree.collapseAll()
            } label: {
                Image(systemName: "rectangle.compress.vertical")
            }
            .buttonStyle(.borderless)
            .help("Collapse all topics")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .onAppear { searchFocused = true }
    }

    private var treeList: some View {
        ScrollViewReader { proxy in
            List(selection: selection) {
                rootRow
                ForEach(model.tree.rows) { row in
                    if let node = model.tree.node(at: row.path) {
                        TopicRowView(model: model, node: node, depth: row.depth + 1)
                            .tag(row.path)
                            .id(row.path)
                    }
                }
            }
            .listStyle(.inset)
            .onChange(of: model.tree.selectedPath) { _, path in
                if let path {
                    withAnimation(.easeOut(duration: 0.1)) {
                        proxy.scrollTo(path, anchor: .center)
                    }
                }
            }
        }
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(keys: [.upArrow, .downArrow, .leftArrow, .rightArrow]) { press in
            switch press.key {
            case .upArrow: model.tree.selectAdjacent(delta: -1)
            case .downArrow: model.tree.selectAdjacent(delta: 1)
            case .leftArrow: model.tree.collapseSelectedOrMoveOutward()
            case .rightArrow: model.tree.expandSelectedOrMoveInward()
            default: return .ignored
            }
            return .handled
        }
        .onKeyPress(keys: [.delete, .deleteForward]) { _ in
            guard let path = model.tree.selectedPath else { return .ignored }
            Task {
                await model.clearTopic(path: path, recursive: true)
            }
            return .handled
        }
    }

    /// The root row shows the connected broker's host name.
    private var rootRow: some View {
        HStack(spacing: 4) {
            Image(systemName: "chevron.down")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .frame(width: 12)
            Text(model.selectedProfile?.host ?? "")
                .bold()
                .lineLimit(1)
        }
        .padding(.leading, 8)
        .padding(.vertical, 2)
    }
}

private struct TopicRowView: View {
    @Bindable var model: AppModel
    let node: UITopicNode
    let depth: Int

    @State private var flashing = false

    var body: some View {
        HStack(spacing: 4) {
            expander
            Text(node.name)
                .bold()
                .lineLimit(1)
            if !node.expanded, node.childCount > 0 {
                Text("(\(node.childTopicCount) topic(s), \(node.leafMessageCount) message(s))")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if node.message != nil, !node.preview.isEmpty {
                Text("= " + node.preview)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, CGFloat(depth) * 16)
        .padding(.vertical, 1)
        .contentShape(Rectangle())
        .overlay {
            if flashing {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.yellow.opacity(0.35))
            }
        }
        .onTapGesture {
            // A click selects and toggles expansion.
            model.selectTopic(node.path)
            model.tree.toggleExpanded(path: node.path)
        }
        .onHover { inside in
            // "Quick Preview": select topics on mouse over, when enabled and
            // the node actually carries a payload.
            if inside && model.settings.selectTopicWithMouseOver && node.message != nil {
                model.selectTopic(node.path)
            }
        }
        .onChange(of: node.updatePulse) {
            guard model.settings.highlightTopicUpdates else { return }
            flashing = true
            Task {
                try? await Task.sleep(for: .milliseconds(350))
                flashing = false
            }
        }
    }

    @ViewBuilder
    private var expander: some View {
        if node.childCount > 0 {
            Image(systemName: node.expanded ? "chevron.down" : "chevron.right")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .frame(width: 12)
                .onTapGesture {
                    model.tree.toggleExpanded(path: node.path)
                }
        } else {
            Color.clear.frame(width: 12, height: 1)
        }
    }
}
