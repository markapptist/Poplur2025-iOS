import SwiftUI
import Combine

public struct TimeMachineCarousel<ItemView: View, Item: Identifiable>: View {
    public let items: [Item]
    public let itemView: (Item) -> ItemView
    @State private var index: Int = 0
    @State private var timerCancellable: Cancellable?
    public var interval: TimeInterval

    public init(items: [Item], interval: TimeInterval = 3, @ViewBuilder itemView: @escaping (Item) -> ItemView) {
        self.items = items
        self.interval = interval
        self.itemView = itemView
    }

    public var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            TabView(selection: $index) {
                ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                    itemView(item)
                        .frame(width: size.width, height: size.height)
                        .rotation3DEffect(
                            .degrees(Double(index == i ? 0 : (index > i ? 30 : -30))),
                            axis: (x: 0, y: 1, z: 0),
                            anchorZ: 1,
                            perspective: 0.7
                        )
                        .scaleEffect(index == i ? 1 : 0.8)
                        .animation(.easeInOut(duration: 0.5), value: index)
                        .tag(i)
                }
            }
            .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
            .onAppear { startTimer() }
            .onDisappear { stopTimer() }
        }
    }

    private func startTimer() {
        timerCancellable = Timer.publish(every: interval, on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                withAnimation {
                    index = (index + 1) % items.count
                }
            }
    }

    private func stopTimer() {
        timerCancellable?.cancel()
        timerCancellable = nil
    }
}

struct TimeMachineCarousel_Previews: PreviewProvider {
    struct DummyItem: Identifiable {
        let id = UUID()
        let color: Color
        let text: String
    }

    static let sampleItems: [DummyItem] = [
        DummyItem(color: .red, text: "One"),
        DummyItem(color: .green, text: "Two"),
        DummyItem(color: .blue, text: "Three"),
        DummyItem(color: .orange, text: "Four")
    ]

    static var previews: some View {
        TimeMachineCarousel(items: sampleItems, interval: 2) { item in
            ZStack {
                item.color
                Text(item.text)
                    .font(.largeTitle)
                    .bold()
                    .foregroundColor(.white)
            }
            .cornerRadius(12)
            .shadow(radius: 4)
            .padding()
        }
        .frame(height: 250)
        .padding()
        .previewLayout(.sizeThatFits)
    }
}
