import SwiftUI

/// Right-hand sidebar with the Details and Publish tabs, switched through a
/// native segmented control.
struct SidebarView: View {
    @Bindable var model: AppModel

    enum Tab: String, CaseIterable {
        case details = "Details"
        case publish = "Publish"
    }

    @State private var tab: Tab = .details

    var body: some View {
        VStack(spacing: 0) {
            Picker("Sidebar", selection: $tab) {
                ForEach(Tab.allCases, id: \.self) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            switch tab {
            case .details:
                DetailsView(model: model)
            case .publish:
                PublishView(model: model)
            }
        }
    }
}
