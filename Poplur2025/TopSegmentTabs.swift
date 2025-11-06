import SwiftUI

// A simple top-segmented tab container used by HomeView on iPad.
// It displays a segmented control with the provided segment titles,
// binds the selection to an AppTab, and renders content via contentBuilder.
struct TopSegmentTabs<Content: View>: View {
    @Binding var selection: AppTab
    let segments: [String]
    let contentBuilder: (AppTab) -> Content

    var body: some View {
        VStack(spacing: 0) {
            // Top segmented control
            Picker("", selection: $selection) {
                ForEach(AppTab.allCases, id: \.self) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .background(Color(UIColor.systemBackground).opacity(0.9))
            .zIndex(1)

            // Selected content
            contentBuilder(selection)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .ignoresSafeArea(edges: .bottom)
    }
}
