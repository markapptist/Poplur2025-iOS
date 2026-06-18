import SwiftUI

struct PoplurStoreView: View {
    @StateObject var cart = CartViewModel()
    @State var showingCart = false
    @State var balance: Decimal = 100.00
    
    static let radiusProducts: [StoreProduct] = [
        StoreProduct(
            id: "com.apptist.Poplur2025.radius.starter",
            name: "Starter Radius",
            price: 9.99,
            imageName: "radius_starter",
            description: "Kickstart your reach with an extra +5 km radius.",
            kind: .radiusStarter
        ),
        StoreProduct(
            id: "com.apptist.Poplur2025.radius.city",
            name: "City Boost",
            price: 19.99,
            imageName: "radius_city",
            description: "Expand your presence across the city with +25 km.",
            kind: .radiusCity
        ),
        StoreProduct(
            id: "com.apptist.Poplur2025.radius.world",
            name: "World Push",
            price: 49.99,
            imageName: "radius_world",
            description: "Go global. Add +100 km to your radius.",
            kind: .radiusWorld
        )
    ]
    
    var body: some View {
        MockBrowser(urlString: "http://www.poplur.ca") {
            VStack(spacing: 16) {
                header
                
                Divider()
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Radius Boosts")
                        .font(.title2)
                        .bold()
                        .padding(.horizontal)
                    
                    TimeMachineCarousel(items: Self.radiusProducts) { (product: StoreProduct) in
                        ProductCard(product: product, addAction: {
                            if product.price <= balance {
                                cart.add(product)
                                balance -= product.price
                            }
                        })
                        .frame(width: 280)
                    }
                    .frame(height: 320)
                }
                Spacer()
            }
            .padding(.vertical)
        }
        .sheet(isPresented: $showingCart) {
            CartSheet(cart: cart) {
                // Simple mock checkout: clear cart and close
                cart.clear()
                showingCart = false
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showingCart.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "cart")
                        if cart.items.count > 0 {
                            Text("\(cart.items.count)")
                                .font(.caption2)
                                .bold()
                                .padding(5)
                                .background(Circle().fill(Color.red))
                                .foregroundColor(.white)
                        }
                    }
                }
                .accessibilityLabel("Show Cart")
            }
        }
    }
    
    private var header: some View {
        HStack(spacing: 12) {
            Text("Poplur Store")
                .font(.largeTitle)
                .bold()
            Spacer()
            Text(balance.currencyFormat)
                .font(.headline)
                .padding(8)
                .background(Color.green.opacity(0.2))
                .clipShape(Capsule())
        }
        .padding(.horizontal)
    }
}

private struct ProductCard: View {
    let product: StoreProduct
    let addAction: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(product.imageName)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: 140)
                .clipped()
                .cornerRadius(12)
                .shadow(radius: 3)
            Text(product.name)
                .font(.title3)
                .bold()
                .multilineTextAlignment(.center)
            Text(product.description)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .padding(.horizontal)
            Text(product.price.currencyFormat)
                .font(.headline)
            Button(action: addAction) {
                Text("Add to Cart")
                    .font(.body.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
            .padding(.horizontal)
        }
        .padding()
        .background(Color(UIColor.systemBackground))
        .cornerRadius(16)
        .shadow(radius: 5)
    }
}

private extension Decimal {
    var currencyFormat: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = Locale.current.currency?.identifier ?? "USD"
        return formatter.string(for: self as NSDecimalNumber) ?? "$0.00"
    }
}

struct PoplurStoreView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            PoplurStoreView()
        }
    }
}
