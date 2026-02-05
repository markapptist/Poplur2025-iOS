import SwiftUI
import StoreKit

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
        do {
            for await verification in Transaction.currentEntitlements {
                do {
                    let transaction = try verification.payloadValue
                    if transaction.productID == productID {
                        quota.setUpgradePurchased()
                    }
                } catch {
                    print("Failed to verify transaction: \(error)")
                }
            }
        } catch {
            print("Failed to restore transactions: \(error)")
        }
    }
}
