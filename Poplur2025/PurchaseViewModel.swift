import SwiftUI
import StoreKit
import FirebaseFirestore

typealias StoreKitTransaction = StoreKit.Transaction
typealias FirestoreTransaction = FirebaseFirestore.Transaction

@MainActor
class PurchaseViewModel: ObservableObject {
    @Published var product: Product?
    let productID = "com.poplur.dailyupgrade"
    
    func loadProducts() async throws {
        do {
            let products = try await Product.products(for: [productID])
            product = products.first
        } catch {
            print("Failed to load products: \(error)")
            throw error
        }
    }
    
    func buyUpgrade(quota: DailyQuotaViewModel) async {
        guard let product = product else {
            print("Product not loaded.")
            return
        }
        
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try verification.payloadValue
                await transaction.finish()
                quota.setUpgradePurchased()
            case .userCancelled:
                print("User cancelled the purchase.")
            case .pending:
                print("Purchase is pending.")
            @unknown default:
                print("Unknown purchase result.")
            }
        } catch {
            print("Purchase failed: \(error)")
        }
    }
    
    func restoreIfNeeded(quota: DailyQuotaViewModel) async {
        for await verification in StoreKitTransaction.currentEntitlements {
            do {
                let transaction = try verification.payloadValue
                if transaction.productID == productID {
                    quota.setUpgradePurchased()
                }
            } catch {
                print("Failed to verify transaction: \(error)")
            }
        }
    }
}

struct RadiusPurchasePackage: Identifiable, CaseIterable, Hashable {
    let id: String
    let title: String
    let radiusMeters: Int
    let fallbackPrice: String

    var productID: String { id }

    static let allCases: [RadiusPurchasePackage] = [
        RadiusPurchasePackage(
            id: "com.apptist.Poplur2025.radius.starter",
            title: "Starter Radius",
            radiusMeters: 5_000,
            fallbackPrice: "$1.99"
        ),
        RadiusPurchasePackage(
            id: "com.apptist.Poplur2025.radius.city",
            title: "City Boost",
            radiusMeters: 25_000,
            fallbackPrice: "$4.99"
        ),
        RadiusPurchasePackage(
            id: "com.apptist.Poplur2025.radius.world",
            title: "World Push",
            radiusMeters: 100_000,
            fallbackPrice: "$9.99"
        )
    ]
}

@MainActor
final class RadiusPurchaseViewModel: ObservableObject {
    @Published private(set) var productsByID: [String: Product] = [:]
    @Published private(set) var isLoadingProducts = false
    @Published private(set) var purchasingProductID: String?
    @Published var message: String?

    private let db = Firestore.firestore()

    var canSellRadius: Bool {
        !productsByID.isEmpty
    }

    func loadProducts() async {
        guard !isLoadingProducts else { return }
        isLoadingProducts = true
        defer { isLoadingProducts = false }

        do {
            let ids = RadiusPurchasePackage.allCases.map(\.productID)
            let products = try await Product.products(for: ids)
            productsByID = Dictionary(uniqueKeysWithValues: products.map { ($0.id, $0) })
            if productsByID.isEmpty {
                message = "Radius purchases are not configured in App Store Connect yet."
            }
        } catch {
            message = "Could not load radius products: \(error.localizedDescription)"
        }
    }

    func displayPrice(for package: RadiusPurchasePackage) -> String {
        productsByID[package.productID]?.displayPrice ?? package.fallbackPrice
    }

    func isPurchasing(_ package: RadiusPurchasePackage) -> Bool {
        purchasingProductID == package.productID
    }

    func buyRadius(_ package: RadiusPurchasePackage, userID: String?) async -> Int? {
        guard let userID, !userID.isEmpty else {
            message = "Sign in before buying radius."
            return nil
        }
        guard let product = productsByID[package.productID] else {
            message = "This radius package is not available yet."
            return nil
        }

        purchasingProductID = package.productID
        defer { purchasingProductID = nil }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                try await deliverRadius(package, transaction: transaction, userID: userID)
                await transaction.finish()
                message = "Added \(formatRadius(package.radiusMeters)) to your radius."
                return package.radiusMeters
            case .pending:
                message = "Purchase pending approval."
                return nil
            case .userCancelled:
                return nil
            @unknown default:
                message = "Purchase did not complete."
                return nil
            }
        } catch {
            message = "Purchase failed: \(error.localizedDescription)"
            return nil
        }
    }

    func finishUndeliveredRadiusPurchases(userID: String?) async -> Int {
        guard let userID, !userID.isEmpty else { return 0 }
        var deliveredMeters = 0

        for await verification in StoreKitTransaction.unfinished {
            do {
                let transaction = try checkVerified(verification)
                guard let package = RadiusPurchasePackage.allCases.first(where: { $0.productID == transaction.productID }) else {
                    continue
                }
                try await deliverRadius(package, transaction: transaction, userID: userID)
                await transaction.finish()
                deliveredMeters += package.radiusMeters
            } catch {
                message = "Could not finish a pending radius purchase: \(error.localizedDescription)"
            }
        }

        if deliveredMeters > 0 {
            message = "Restored \(formatRadius(deliveredMeters)) of purchased radius."
        }
        return deliveredMeters
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let safe):
            return safe
        case .unverified(_, let error):
            throw error
        }
    }

    private func deliverRadius(_ package: RadiusPurchasePackage, transaction: StoreKitTransaction, userID: String) async throws {
        let transactionID = String(transaction.id)
        let userRef = db.collection("users").document(userID)
        let purchaseRef = userRef.collection("radiusPurchases").document(transactionID)

        try await db.runTransaction { transaction, errorPointer in
            do {
                let existing = try transaction.getDocument(purchaseRef)
                if existing.exists {
                    return nil
                }

                transaction.setData([
                    "productID": package.productID,
                    "title": package.title,
                    "radiusMeters": package.radiusMeters,
                    "storeTransactionID": transactionID,
                    "purchasedAt": FieldValue.serverTimestamp(),
                    "platform": "ios"
                ], forDocument: purchaseRef)

                transaction.setData([
                    "purchasedRadiusMeters": FieldValue.increment(Int64(package.radiusMeters)),
                    "updatedAt": FieldValue.serverTimestamp()
                ], forDocument: userRef, merge: true)

                return nil
            } catch {
                errorPointer?.pointee = error as NSError
                return nil
            }
        }
    }

    private func formatRadius(_ meters: Int) -> String {
        meters >= 1000 ? "\(meters / 1000) km" : "\(meters) m"
    }
}
