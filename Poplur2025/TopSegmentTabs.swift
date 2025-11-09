import SwiftUI

struct TopSegmentTabs<Content: View>: View {
    @Binding var selection: AppTab
    let segments: [String]
    let contentBuilder: (AppTab) -> Content

    init(
        selection: Binding<AppTab>,
        segments: [String],
        @ViewBuilder contentBuilder: @escaping (AppTab) -> Content
    ) {
        _selection = selection
        self.segments = segments
        self.contentBuilder = contentBuilder
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selection) {
                ForEach(AppTab.allCases, id: \.self) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding()

            contentBuilder(selection)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.black.ignoresSafeArea())
    }
}
