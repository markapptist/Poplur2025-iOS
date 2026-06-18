import SwiftUI

struct CartSheet: View {
    @ObservedObject var cart: CartViewModel
    var onCheckout: () -> Void

    var body: some View {
        VStack {
            HStack {
                Spacer()
                Text("Total: \(cart.totalPriceFormatted)")
                    .font(.headline)
                    .padding()
            }
            List {
                ForEach(cart.items) { item in
                    HStack(spacing: 16) {
                        Image(item.product.imageName)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 60, height: 60)
                            .cornerRadius(8)

                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.name)
                                .font(.headline)
                            Text(item.priceFormatted)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Stepper(value: Binding<Int>(
                            get: { item.quantity },
                            set: { cart.updateQuantity(for: item.id, quantity: $0) }
                        ), in: 1...99) {
                            Text("Qty: \(item.quantity)")
                                .frame(minWidth: 60, alignment: .trailing)
                        }
                        Button(action: { cart.removeItem(item) }) {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                        }
                        .buttonStyle(BorderlessButtonStyle())
                    }
                    .padding(.vertical, 8)
                }
                .onDelete { indexSet in
                    for index in indexSet {
                        cart.removeItem(cart.items[index])
                    }
                }
            }
            .listStyle(PlainListStyle())
            Divider()
            Button(action: onCheckout) {
                Text("Checkout")
                    .bold()
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(cart.items.isEmpty ? Color.gray.opacity(0.5) : Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .disabled(cart.items.isEmpty)
            .padding()
        }
        .presentationDetents([.medium, .large])
    }
}
