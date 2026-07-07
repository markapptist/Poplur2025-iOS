import SwiftUI
import SpriteKit
import FirebaseAuth

struct PoplurStoreView: View {
    @StateObject private var cart = CartViewModel()
    @StateObject private var creditVM = CreatorCreditPurchaseViewModel()
    @State private var showingCart = false
    @State private var balance: Decimal = 100.00

    private var userID: String? { Auth.auth().currentUser?.uid }

    static let radiusProducts: [StoreProduct] = [
        StoreProduct(
            id: "com.apptist.Poplur2025.radius.starter",
            name: "Starter Radius",
            price: 9.99,
            imageName: "radius_starter",
            description: "Add 5 km of reach for local drops, nearby events, and first-wave visibility.",
            kind: .radiusStarter
        ),
        StoreProduct(
            id: "com.apptist.Poplur2025.radius.city",
            name: "City Boost",
            price: 19.99,
            imageName: "radius_city",
            description: "Add 25 km and stretch your Poplur signal across the city.",
            kind: .radiusCity
        ),
        StoreProduct(
            id: "com.apptist.Poplur2025.radius.world",
            name: "World Push",
            price: 49.99,
            imageName: "radius_world",
            description: "Add 100 km for wide releases, global moments, and high-reach launches.",
            kind: .radiusWorld
        )
    ]

    var body: some View {
        MockBrowser(urlString: "www.poplurstore.ca") {
            StoreWebsiteContent(
                balance: balance,
                cartCount: cart.items.reduce(0) { $0 + $1.quantity },
                radiusProducts: Self.radiusProducts,
                creditCards: StoreCreditCard.catalog,
                creditVM: creditVM,
                userID: userID,
                showCart: { showingCart = true },
                addProduct: addProduct
            )
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
                async let balance: () = creditVM.loadBalance(userID: uid)
                _ = await (products, balance)
            } else {
                await products
            }
        }
    }

    private func addProduct(_ product: StoreProduct) {
        guard product.price <= balance else { return }
        cart.add(product)
        balance -= product.price
    }
}

private struct StoreWebsiteContent: View {
    let balance: Decimal
    let cartCount: Int
    let radiusProducts: [StoreProduct]
    let creditCards: [StoreCreditCard]
    @ObservedObject var creditVM: CreatorCreditPurchaseViewModel
    let userID: String?
    let showCart: () -> Void
    let addProduct: (StoreProduct) -> Void

    var body: some View {
        VStack(spacing: 0) {
            StoreSiteNavigation(balance: balance, cartCount: cartCount, showCart: showCart)

            StoreCreditCardCarousel(cards: creditCards)
                .padding(.top, 8)

            StoreHeroSection()

            StoreCreatorCreditsSection(creditVM: creditVM, userID: userID)

            StoreProductSection(products: radiusProducts, addProduct: addProduct)

            StoreDeviceShowcase()
        }
        .frame(maxWidth: .infinity)
        .background(Color.white)
    }
}

private struct StoreSiteNavigation: View {
    let balance: Decimal
    let cartCount: Int
    let showCart: () -> Void

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var isCompact: Bool {
        horizontalSizeClass == .compact
    }

    var body: some View {
        HStack(spacing: isCompact ? 12 : 24) {
            Text("Poplur")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.primary)

            if !isCompact {
                HStack(spacing: 22) {
                    ForEach(["Store", "Cards", "Radius", "Phone", "Support"], id: \.self) { item in
                        Text(item)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.black.opacity(0.66))
                    }
                }
            }

            Spacer(minLength: 8)

            Text(balance.currencyFormat)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.black.opacity(0.72))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(Color.black.opacity(0.055))
                )

            Button(action: showCart) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "bag")
                        .poplurIconShader()
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 34, height: 34)

                    if cartCount > 0 {
                        Text("\(cartCount)")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 16, height: 16)
                            .background(Circle().fill(Color(red: 0.0, green: 0.45, blue: 1.0)))
                            .offset(x: 4, y: -2)
                    }
                }
                .foregroundColor(.black.opacity(0.78))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Show Cart")
        }
        .padding(.horizontal, isCompact ? 18 : 38)
        .frame(height: 54)
        .background(.ultraThinMaterial)
    }
}

private struct StoreHeroSection: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("Poplur Store")
                .font(.system(size: 54, weight: .semibold))
                .minimumScaleFactor(0.65)
                .lineLimit(1)
                .foregroundColor(.black)

            Text("Cards, radius, and Poplur gear for bigger local reach.")
                .font(.system(size: 20, weight: .regular))
                .multilineTextAlignment(.center)
                .foregroundColor(.black.opacity(0.64))
                .frame(maxWidth: 620)
        }
        .padding(.horizontal, 24)
        .padding(.top, 38)
        .padding(.bottom, 44)
        .frame(maxWidth: .infinity)
        .background(Color.white)
    }
}

private struct StoreProductSection: View {
    let products: [StoreProduct]
    let addProduct: (StoreProduct) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .lastTextBaseline) {
                Text("Radius Boosts")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundColor(.black)

                Spacer()

                Text("Instant delivery")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.black.opacity(0.48))
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 16)], spacing: 16) {
                ForEach(products) { product in
                    StoreProductCard(product: product) {
                        addProduct(product)
                    }
                }
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 36)
        .frame(maxWidth: 1080)
        .frame(maxWidth: .infinity)
        .background(Color(red: 0.965, green: 0.965, blue: 0.975))
    }
}

private struct StoreProductCard: View {
    let product: StoreProduct
    let addAction: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            RadiusProductVisual(product: product)
                .frame(height: 132)

            VStack(spacing: 7) {
                Text(product.name)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.black)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)

                Text(product.description)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(.black.opacity(0.58))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            HStack(spacing: 12) {
                Text(product.price.currencyFormat)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.black)

                Spacer(minLength: 0)

                Button(action: addAction) {
                    Label("Add", systemImage: "bag.badge.plus")
                        .font(.system(size: 14, weight: .semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .foregroundColor(.white)
                        .background(
                            Capsule()
                                .fill(Color(red: 0.0, green: 0.45, blue: 1.0))
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 318)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.black.opacity(0.065), lineWidth: 1)
        )
    }
}

private struct RadiusProductVisual: View {
    let product: StoreProduct

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(visualGradient)
                .poplurBrowserMetalGlass(intensity: 0.48)

            Circle()
                .stroke(Color.white.opacity(0.42), lineWidth: 1)
                .frame(width: 92, height: 92)

            Circle()
                .stroke(Color.white.opacity(0.28), lineWidth: 1)
                .frame(width: 124, height: 124)

            VStack(spacing: 4) {
                Text(radiusAmount)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)

                Text("RADIUS")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white.opacity(0.76))
            }
        }
    }

    private var radiusAmount: String {
        switch product.kind {
        case .radiusStarter:
            return "+5 km"
        case .radiusCity:
            return "+25 km"
        case .radiusWorld:
            return "+100 km"
        default:
            return "BOOST"
        }
    }

    private var visualGradient: LinearGradient {
        switch product.kind {
        case .radiusStarter:
            return LinearGradient(
                colors: [Color(red: 0.10, green: 0.48, blue: 0.90), Color(red: 0.13, green: 0.70, blue: 0.58)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .radiusCity:
            return LinearGradient(
                colors: [Color(red: 0.94, green: 0.55, blue: 0.12), Color(red: 0.76, green: 0.11, blue: 0.26)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .radiusWorld:
            return LinearGradient(
                colors: [Color(red: 0.12, green: 0.14, blue: 0.18), Color(red: 0.48, green: 0.24, blue: 0.76)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        default:
            return LinearGradient(colors: [.black, .gray], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
}

private struct StoreCreatorCreditsSection: View {
    @ObservedObject var creditVM: CreatorCreditPurchaseViewModel
    let userID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .lastTextBaseline) {
                Text("Creator Credits")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundColor(.black)

                Spacer()

                HStack(spacing: 5) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(Color(red: 0.9, green: 0.2, blue: 0.6))

                    if creditVM.isLoadingBalance {
                        ProgressView().scaleEffect(0.7)
                    } else {
                        Text("\(creditVM.availableCredits) credits")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.black.opacity(0.58))
                    }
                }
            }

            Text("Used for AI image, video, voice, and music generation. Credits never expire.")
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(.black.opacity(0.52))

            if let msg = creditVM.message {
                Text(msg)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(msg.lowercased().contains("failed") || msg.lowercased().contains("not") ? .red : Color(red: 0.0, green: 0.55, blue: 0.25))
                    .padding(.vertical, 2)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 16)], spacing: 16) {
                ForEach(CreatorCreditPackage.allCases) { package in
                    StoreCreditPackageCard(
                        package: package,
                        price: creditVM.displayPrice(for: package),
                        isPurchasing: creditVM.isPurchasing(package),
                        productsLoaded: !creditVM.productsByID.isEmpty
                    ) {
                        Task { await creditVM.buyCredits(package, userID: userID) }
                    }
                }
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 36)
        .frame(maxWidth: 1080)
        .frame(maxWidth: .infinity)
        .background(Color(red: 0.975, green: 0.968, blue: 0.990))
    }
}

private struct StoreCreditPackageCard: View {
    let package: CreatorCreditPackage
    let price: String
    let isPurchasing: Bool
    let productsLoaded: Bool
    let buyAction: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            CreditPackageVisual(package: package)
                .frame(height: 110)

            VStack(spacing: 6) {
                Text(package.title)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.black)
                    .multilineTextAlignment(.center)

                Text(package.description)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(.black.opacity(0.56))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            HStack(spacing: 12) {
                Text(price)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.black)

                Spacer(minLength: 0)

                Button(action: buyAction) {
                    if isPurchasing {
                        ProgressView()
                            .frame(width: 60, height: 34)
                    } else {
                        Label("Buy", systemImage: "sparkles")
                            .font(.system(size: 14, weight: .semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .foregroundColor(.white)
                            .background(
                                Capsule()
                                    .fill(productsLoaded
                                          ? Color(red: 0.78, green: 0.12, blue: 0.52)
                                          : Color.gray.opacity(0.5))
                            )
                    }
                }
                .buttonStyle(.plain)
                .disabled(isPurchasing || !productsLoaded)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 280)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.black.opacity(0.065), lineWidth: 1)
        )
    }
}

private struct CreditPackageVisual: View {
    let package: CreatorCreditPackage

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(gradient)
                .poplurBrowserMetalGlass(intensity: 0.42)

            VStack(spacing: 2) {
                Text("\(package.credits)")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                Text("CREDITS")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white.opacity(0.76))
            }

            Image(systemName: "sparkles")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white.opacity(0.55))
                .offset(x: 42, y: -26)

            Image(systemName: "sparkles")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.white.opacity(0.38))
                .offset(x: -38, y: 22)
        }
    }

    private var gradient: LinearGradient {
        switch package.credits {
        case 100:
            return LinearGradient(
                colors: [Color(red: 0.70, green: 0.12, blue: 0.78), Color(red: 0.35, green: 0.10, blue: 0.82)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        case 500:
            return LinearGradient(
                colors: [Color(red: 0.88, green: 0.16, blue: 0.52), Color(red: 0.60, green: 0.08, blue: 0.76)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        default:
            return LinearGradient(
                colors: [Color(red: 0.06, green: 0.08, blue: 0.18), Color(red: 0.52, green: 0.10, blue: 0.62)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        }
    }
}

private struct StoreDeviceShowcase: View {
    var body: some View {
        VStack(spacing: 16) {
            Text("Popular Phone")
                .font(.system(size: 36, weight: .semibold))
                .foregroundColor(.white)

            Text("The shiny Poplur handset for your member card, calls, and local drops.")
                .font(.system(size: 17, weight: .regular))
                .foregroundColor(.white.opacity(0.72))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 520)

            Image("poplur_bling_phone_01_silver_diamond")
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 330)
                .shadow(color: .black.opacity(0.26), radius: 26, x: 0, y: 16)
        }
        .padding(.horizontal, 24)
        .padding(.top, 42)
        .padding(.bottom, 54)
        .frame(maxWidth: .infinity)
        .background(Color.black)
    }
}

private struct StoreCreditCard: Identifiable, Hashable {
    let id: String
    let name: String
    let spriteSheetName: String

    static let catalog: [StoreCreditCard] = [
        StoreCreditCard(id: "cosmic-silver", name: "Cosmic Silver", spriteSheetName: "poplur_card_cosmic_silver_spritesheet"),
        StoreCreditCard(id: "icy-aqua", name: "Icy Aqua", spriteSheetName: "poplur_card_icy_aqua_spritesheet"),
        StoreCreditCard(id: "champagne-gold", name: "Champagne Gold", spriteSheetName: "poplur_card_champagne_gold_spritesheet"),
        StoreCreditCard(id: "jet-black", name: "Jet Black Onyx", spriteSheetName: "poplur_card_jet_black_onyx_spritesheet"),
        StoreCreditCard(id: "amethyst", name: "Amethyst Purple", spriteSheetName: "poplur_card_amethyst_purple_spritesheet"),
        StoreCreditCard(id: "ruby", name: "Ruby Red", spriteSheetName: "poplur_card_ruby_red_spritesheet"),
        StoreCreditCard(id: "emerald", name: "Emerald Green", spriteSheetName: "poplur_card_emerald_green_spritesheet"),
        StoreCreditCard(id: "sapphire", name: "Sapphire Blue", spriteSheetName: "poplur_card_sapphire_blue_spritesheet")
    ]
}

private struct StoreCreditCardCarousel: View {
    let cards: [StoreCreditCard]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let cardWidth = min(max(proxy.size.width * 0.68, 228), 348)
            let cardHeight = cardWidth / StoreCreditCardSpriteScene.aspectRatio
            let spacing: CGFloat = 18
            let cycleWidth = CGFloat(cards.count) * (cardWidth + spacing)
            let speed: CGFloat = 34
            let cycleDuration = max(1, Double(cycleWidth / speed))
            let repeatedCards = Array(repeating: cards, count: 3).flatMap { $0 }

            TimelineView(.animation) { context in
                let elapsed = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: cycleDuration)
                let offset = reduceMotion ? 0 : -CGFloat(elapsed) * speed

                HStack(spacing: spacing) {
                    ForEach(Array(repeatedCards.enumerated()), id: \.offset) { _, card in
                        StoreCreditCardSpriteView(card: card)
                            .frame(width: cardWidth, height: cardHeight)
                            .accessibilityLabel(card.name)
                    }
                }
                .offset(x: offset)
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .leading)
            }
        }
        .frame(height: 270)
        .clipped()
        .background(Color.white)
    }
}

private final class StoreCreditCardSpriteScene: SKScene {
    static let nativeCardSize = CGSize(width: 482, height: 320)
    static let aspectRatio = nativeCardSize.width / nativeCardSize.height

    private let sheetName: String
    private var cardNode: SKSpriteNode?

    private static let cardShader = SKShader(source: """
    void main() {
        vec4 base = texture2D(u_texture, v_tex_coord);
        float sweep = sin(u_time * 0.7) * 0.5 + 0.5;
        float diagonal = v_tex_coord.x + v_tex_coord.y * 0.58;
        float band = 1.0 - smoothstep(0.0, 0.18, abs(diagonal - (0.42 + sweep * 0.62)));
        vec3 shine = vec3(0.18, 0.20, 0.22) * band * base.a;
        gl_FragColor = vec4(base.rgb + shine, base.a);
    }
    """)

    init(sheetName: String) {
        self.sheetName = sheetName
        super.init(size: Self.nativeCardSize)
        scaleMode = .resizeFill
        backgroundColor = .clear
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMove(to view: SKView) {
        view.allowsTransparency = true
        view.backgroundColor = .clear
        buildCard()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        layoutCard()
    }

    private func buildCard() {
        guard cardNode == nil else { return }

        let node = SKSpriteNode(texture: makeFirstTexture())
        node.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        node.shader = Self.cardShader
        addChild(node)
        cardNode = node
        layoutCard()
    }

    private func makeFirstTexture() -> SKTexture {
        let sheet = SKTexture(imageNamed: sheetName)
        let sheetSize = CGSize(width: 1122, height: 1402)
        let origin = CGPoint(x: 62, y: 54)
        let rect = CGRect(
            x: origin.x / sheetSize.width,
            y: (sheetSize.height - origin.y - Self.nativeCardSize.height) / sheetSize.height,
            width: Self.nativeCardSize.width / sheetSize.width,
            height: Self.nativeCardSize.height / sheetSize.height
        )
        let texture = SKTexture(rect: rect, in: sheet)
        texture.filteringMode = .linear
        return texture
    }

    private func layoutCard() {
        guard let cardNode else { return }
        cardNode.position = CGPoint(x: size.width / 2, y: size.height / 2)
        cardNode.size = size
    }
}

private struct StoreCreditCardSpriteView: UIViewRepresentable {
    let card: StoreCreditCard

    func makeUIView(context: Context) -> SKView {
        let view = SKView(frame: .zero)
        view.allowsTransparency = true
        view.backgroundColor = .clear
        view.isOpaque = false
        view.ignoresSiblingOrder = true
        view.preferredFramesPerSecond = 60
        view.isUserInteractionEnabled = false
        view.presentScene(StoreCreditCardSpriteScene(sheetName: card.spriteSheetName))
        return view
    }

    func updateUIView(_ uiView: SKView, context: Context) {
        if uiView.scene == nil {
            uiView.presentScene(StoreCreditCardSpriteScene(sheetName: card.spriteSheetName))
        }
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
