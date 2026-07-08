import SwiftUI
import FirebaseAuth

// MARK: - Design palette (sampled from the Store mockup)

private enum StoreC {
    static let pageBG      = Color(red: 253/255, green: 243/255, blue: 246/255) // #FDF3F6
    static let card        = Color(red: 253/255, green: 247/255, blue: 249/255) // #FDF7F9
    static let heroCard    = Color(red: 253/255, green: 212/255, blue: 221/255) // #FDD4DD
    static let plusBanner  = Color(red: 252/255, green: 229/255, blue: 240/255) // #FCE5F0
    static let accent      = Color(red: 247/255, green: 38/255,  blue: 112/255) // #F72670
    static let title       = Color(red: 16/255,  green: 20/255,  blue: 38/255)
    static let secondary   = Color(red: 140/255, green: 138/255, blue: 150/255)
    static let cartBtnBG   = Color(red: 253/255, green: 232/255, blue: 241/255)
    static let divider     = Color(red: 238/255, green: 228/255, blue: 234/255)
}

private struct StoreCategory: Identifiable {
    let id: String
    let icon: String
    let line1: String
    let line2: String
}

struct PoplurStoreView: View {
    @StateObject private var cart = CartViewModel()
    @StateObject private var creditVM = CreatorCreditPurchaseViewModel()
    @State private var showingCart = false
    @State private var searchText = ""
    @State private var balance: Decimal = 100.00

    private var userID: String? { Auth.auth().currentUser?.uid }

    /// The four products shown in the Store mockup.
    static let featuredProducts: [StoreProduct] = [
        StoreProduct(
            id: "com.apptist.Poplur2025.card.world",
            name: "Poplur World Card",
            price: 24.99,
            imageName: "store_p_card",
            description: "Your Poplur World Service card for member perks and local drops.",
            kind: .electronics
        ),
        StoreProduct(
            id: "com.apptist.Poplur2025.hardware.cube",
            name: "Poplur Cube V2",
            price: 39.99,
            imageName: "store_p_cube",
            description: "The second-generation Poplur Cube — your physical companion device.",
            kind: .electronics
        ),
        StoreProduct(
            id: "com.apptist.Poplur2025.radius.starter",
            name: "5km Radius Boost",
            price: 4.99,
            imageName: "store_p_5km",
            description: "Add 5 km of reach for local drops, nearby events, and first-wave visibility.",
            kind: .radiusStarter
        ),
        StoreProduct(
            id: "com.apptist.Poplur2025.radius.city",
            name: "25km Radius Boost",
            price: 19.99,
            imageName: "store_p_25km",
            description: "Add 25 km and stretch your Poplur signal across the city.",
            kind: .radiusCity
        )
    ]

    private static let categories: [StoreCategory] = [
        StoreCategory(id: "cards",   icon: "store_cat_cards",    line1: "Service",  line2: "Cards"),
        StoreCategory(id: "radius",  icon: "store_cat_radius",   line1: "Radius",   line2: "Boosts"),
        StoreCategory(id: "hw",      icon: "store_cat_hardware", line1: "Poplur",   line2: "Hardware"),
        StoreCategory(id: "digital", icon: "store_cat_digital",  line1: "Digital",  line2: "Goods"),
        StoreCategory(id: "bundles", icon: "store_cat_bundles",  line1: "Bundles",  line2: "")
    ]

    private var cartCount: Int { cart.items.reduce(0) { $0 + $1.quantity } }

    private var visibleProducts: [StoreProduct] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return Self.featuredProducts }
        return Self.featuredProducts.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        ZStack {
            StoreC.pageBG.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    header
                    searchRow
                    heroCard
                    categoryCard
                    popularProducts
                    plusBanner
                    trustFooter
                }
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
        }
        .sheet(isPresented: $showingCart) {
            CartSheet(cart: cart) {
                cart.clear()
                showingCart = false
            }
        }
        .task {
            async let products: () = creditVM.loadProducts()
            if let uid = userID {
                async let loadedBalance: () = creditVM.loadBalance(userID: uid)
                _ = await (products, loadedBalance)
            } else {
                await products
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        ZStack {
            Text("Poplur Store")
                .font(.system(size: 32, weight: .black, design: .rounded))
                .foregroundStyle(StoreC.title)

            HStack {
                Spacer()
                Button { showingCart = true } label: {
                    ZStack(alignment: .topTrailing) {
                        Image("store_ic_bag")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 62, height: 62)

                        if cartCount > 0 {
                            Text("\(cartCount)")
                                .font(.system(size: 12, weight: .black, design: .rounded))
                                .foregroundStyle(.white)
                                .frame(width: 22, height: 22)
                                .background(Color.red, in: Circle())
                                .offset(x: 2, y: -2)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Show Cart")
            }
        }
    }

    // MARK: - Search

    private var searchRow: some View {
        HStack(spacing: 12) {
            HStack(spacing: 14) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 21, weight: .heavy))
                    .foregroundStyle(StoreC.accent)

                TextField("", text: $searchText, prompt: Text("Search products...").foregroundColor(StoreC.secondary))
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(StoreC.title)
                    .tint(StoreC.accent)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
            }
            .padding(.horizontal, 20)
            .frame(height: 62)
            .frame(maxWidth: .infinity)
            .background(StoreC.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))

            Image("store_ic_filter")
                .resizable()
                .scaledToFit()
                .frame(width: 62, height: 62)
        }
    }

    // MARK: - Hero

    private var heroCard: some View {
        ZStack(alignment: .topLeading) {
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                Image("store_hero")
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 250)
            }

            VStack(alignment: .leading, spacing: 20) {
                Text("World Service Cards,\nradius boosts,\nand Poplur hardware.")
                    .font(.system(size: 19, weight: .heavy, design: .rounded))
                    .foregroundStyle(StoreC.title)
                    .lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Text("Shop Now")
                        .font(.system(size: 18, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 26)
                        .padding(.vertical, 14)
                        .background(StoreC.accent, in: Capsule())
                        .shadow(color: StoreC.accent.opacity(0.35), radius: 10, x: 0, y: 6)
                }
                .buttonStyle(.plain)
            }
            .padding(.leading, 20)
            .padding(.top, 34)
        }
        .frame(maxWidth: .infinity, minHeight: 240, alignment: .leading)
        .background(StoreC.heroCard, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    // MARK: - Categories

    private var categoryCard: some View {
        HStack(alignment: .top, spacing: 4) {
            ForEach(Self.categories) { category in
                VStack(spacing: 10) {
                    Image(category.icon)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 58, height: 58)

                    VStack(spacing: 1) {
                        Text(category.line1)
                            .font(.system(size: 13, weight: .heavy, design: .rounded))
                            .foregroundStyle(StoreC.title)
                        if !category.line2.isEmpty {
                            Text(category.line2)
                                .font(.system(size: 13, weight: .heavy, design: .rounded))
                                .foregroundStyle(StoreC.title)
                        }
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 18)
        .padding(.horizontal, 6)
        .background(StoreC.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    // MARK: - Popular products

    private var popularProducts: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Popular Products")
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundStyle(StoreC.title)
                Spacer()
                Button {
                    searchText = ""
                } label: {
                    HStack(spacing: 4) {
                        Text("See All")
                            .font(.system(size: 16, weight: .heavy, design: .rounded))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .black))
                    }
                    .foregroundStyle(StoreC.accent)
                }
                .buttonStyle(.plain)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(visibleProducts) { product in
                        productCard(product)
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 4)
            }
        }
    }

    private func productCard(_ product: StoreProduct) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(product.imageName)
                .resizable()
                .scaledToFit()
                .frame(height: 104)
                .frame(maxWidth: .infinity)

            Text(product.name)
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .foregroundStyle(StoreC.title)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            HStack {
                Text(product.price.currencyFormat)
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .foregroundStyle(StoreC.title)

                Spacer(minLength: 6)

                Button { addProduct(product) } label: {
                    Image(systemName: "cart.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(StoreC.accent)
                        .frame(width: 40, height: 36)
                        .background(StoreC.cartBtnBG, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(product.price > balance)
                .opacity(product.price > balance ? 0.45 : 1)
            }
        }
        .padding(14)
        .frame(width: 176)
        .background(StoreC.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.035), radius: 8, x: 0, y: 4)
    }

    // MARK: - Poplur+ banner

    private var plusBanner: some View {
        HStack(spacing: 14) {
            Image("store_ic_plus")
                .resizable()
                .scaledToFit()
                .frame(width: 56, height: 56)

            Text("Members get exclusive discounts and perks!")
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .foregroundStyle(StoreC.accent)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 4)

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                Text("Join Poplur+")
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    .background(StoreC.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(StoreC.plusBanner, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    // MARK: - Trust footer

    private var trustFooter: some View {
        HStack(spacing: 0) {
            trustItem("store_t_secure",    "Secure",    "Payments")
            trustDivider
            trustItem("store_t_fast",      "Fast",      "Delivery")
            trustDivider
            trustItem("store_t_protected", "Protected", "Purchase")
            trustDivider
            trustItem("store_t_returns",   "Easy",      "Returns")
        }
        .padding(.vertical, 18)
        .background(StoreC.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var trustDivider: some View {
        Rectangle()
            .fill(StoreC.divider)
            .frame(width: 1, height: 62)
    }

    private func trustItem(_ icon: String, _ line1: String, _ line2: String) -> some View {
        VStack(spacing: 8) {
            Image(icon)
                .resizable()
                .scaledToFit()
                .frame(width: 48, height: 48)
            VStack(spacing: 1) {
                Text(line1)
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .foregroundStyle(StoreC.title)
                Text(line2)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(StoreC.secondary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Actions

    private func addProduct(_ product: StoreProduct) {
        guard product.price <= balance else { return }
        cart.add(product)
        balance -= product.price
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
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
        PoplurStoreView()
    }
}
