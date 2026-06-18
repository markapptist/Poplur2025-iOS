import SwiftUI
import Foundation

struct StoreProduct: Identifiable, Hashable {
    enum Kind {
        case radiusStarter, radiusCity, radiusWorld
        case electronics, clothing, food, book, other
    }
    let id: String
    let name: String
    let price: Decimal
    let imageName: String
    let description: String
    let kind: Kind
}

struct CartItem: Identifiable {
    let id = UUID()
    let product: StoreProduct
    var quantity: Int

    var name: String { product.name }
    var priceFormatted: String { formattedDecimal(product.price) }
    var image: UIImage { UIImage(named: product.imageName) ?? UIImage() }
}

final class CartViewModel: ObservableObject {
    @Published private(set) var items: [CartItem] = []

    var totalPrice: Decimal {
        items.reduce(0) { $0 + $1.product.price * Decimal($1.quantity) }
    }

    var totalPriceFormatted: String { formattedDecimal(totalPrice) }

    func add(_ product: StoreProduct) {
        if let i = items.firstIndex(where: { $0.product.id == product.id }) {
            items[i].quantity += 1
        } else {
            items.append(CartItem(product: product, quantity: 1))
        }
    }

    func clear() { items.removeAll() }

    func removeItem(_ item: CartItem) {
        items.removeAll { $0.id == item.id }
    }

    func updateQuantity(for id: UUID, quantity: Int) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        if quantity <= 0 { items.remove(at: i) } else { items[i].quantity = quantity }
    }
}

private func formattedDecimal(_ value: Decimal) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .currency
    formatter.currencyCode = Locale.current.currency?.identifier ?? "USD"
    return formatter.string(for: value as NSDecimalNumber) ?? "$0.00"
}
