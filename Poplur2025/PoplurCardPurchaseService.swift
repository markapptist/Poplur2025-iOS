import CryptoKit
import FirebaseAuth
import FirebaseFunctions
import Foundation
import StoreKit

enum PoplurStoreAccountToken {
    /// StoreKit's app-account token is derived exactly the same way as the
    /// verification function: SHA-256(Firebase UID), first 16 bytes, with the
    /// RFC 4122 version/variant bits applied. The UID itself never leaves the
    /// authenticated Firebase session or enters the web checkout payload.
    static func value(forFirebaseUID uid: String) -> UUID {
        var bytes = Array(SHA256.hash(data: Data(uid.utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0f) | 0x50
        bytes[8] = (bytes[8] & 0x3f) | 0x80

        let uuidBytes: uuid_t = (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        )
        return UUID(uuid: uuidBytes)
    }
}

struct PoplurCardCheckoutResult {
    enum Status: String {
        case success
        case cancelled
        case pending
        case failure
    }

    let status: Status
    let message: String
    let completedProductCounts: [String: Int]
    let creditsAdded: Int
    let availableCredits: Int?

    func webPayload(requestID: String) -> [String: Any] {
        var completedItems: [[String: Any]] = []
        for productID in completedProductCounts.keys.sorted() {
            guard let quantity = completedProductCounts[productID], quantity > 0 else { continue }
            var item: [String: Any] = ["productId": productID, "quantity": quantity]
            if let cardID = PoplurCardPurchaseService.cardID(forProductID: productID) {
                item["cardId"] = cardID
            }
            completedItems.append(item)
        }
        var payload: [String: Any] = [
            "type": "poplurStoreCheckoutResult",
            "requestId": requestID,
            "status": status.rawValue,
            "message": message,
            "creditsAdded": creditsAdded,
            "completedItems": completedItems
        ]
        if let availableCredits {
            payload["availableCredits"] = availableCredits
        }
        return payload
    }
}

extension Notification.Name {
    /// Emitted only after an account-bound unfinished StoreKit card transaction
    /// has been verified by the server and finished during app-lifetime recovery.
    static let poplurCardPurchaseRecovered = Notification.Name("PoplurCardPurchaseRecovered")
}

enum PoplurCardPurchaseRecoveryNotification {
    static let productIDKey = "productID"
}

enum PoplurCardPurchaseError: LocalizedError {
    case signedOut
    case checkoutAlreadyRunning
    case purchaseRecoveryInProgress
    case invalidBag
    case unsupportedProduct
    case unavailableProducts
    case unverifiedTransaction
    case serverDidNotGrant

    var errorDescription: String? {
        switch self {
        case .signedOut:
            return "Sign in before purchasing Poplur Credits."
        case .checkoutAlreadyRunning:
            return "Another App Store checkout is already in progress."
        case .purchaseRecoveryInProgress:
            return "Poplur is finishing an interrupted App Store purchase. Please try checkout again in a moment."
        case .invalidBag:
            return "The bag could not be validated. Please review it and try again."
        case .unsupportedProduct:
            return "The bag contains a card that is not available in this version of Poplur."
        case .unavailableProducts:
            return "One or more cards are not available from the App Store yet."
        case .unverifiedTransaction:
            return "The App Store transaction could not be verified."
        case .serverDidNotGrant:
            return "The purchase was not granted by Poplur. Your bag is unchanged; please try again."
        }
    }
}

/// StoreKit owns payment authorization; the Firebase callable owns credit
/// delivery. A transaction is never finished until that callable confirms the
/// signed StoreKit JWS was verified and the idempotent server grant succeeded.
@MainActor
final class PoplurCardPurchaseService {
    static let shared = PoplurCardPurchaseService()

    static let productIDByCardID: [String: String] = [
        "inverted": "com.apptist.Poplur2025.card.inverted",
        "lens": "com.apptist.Poplur2025.card.lens",
        "splitDiamond": "com.apptist.Poplur2025.card.splitdiamond",
        "swoosh": "com.apptist.Poplur2025.card.swoosh"
    ]
    static let supportedProductIDs = Set(productIDByCardID.values)

    nonisolated static func cardID(forProductID productID: String) -> String? {
        switch productID {
        case "com.apptist.Poplur2025.card.inverted": "inverted"
        case "com.apptist.Poplur2025.card.lens": "lens"
        case "com.apptist.Poplur2025.card.splitdiamond": "splitDiamond"
        case "com.apptist.Poplur2025.card.swoosh": "swoosh"
        default: nil
        }
    }

    private struct CheckoutLine {
        let productID: String
        let quantity: Int
    }

    private struct Grant {
        let productID: String
        let creditsAdded: Int
        let availableCredits: Int?
    }

    private let auth: Auth
    private let functions: Functions
    private var checkoutInFlight = false
    private var pendingResolutionInFlight = false
    private var transactionUpdatesTask: Task<Void, Never>?
    private var unfinishedRecoveryTask: Task<Void, Never>?
    private var authStateHandle: AuthStateDidChangeListenerHandle?
    private var backgroundTransactionsInFlight: Set<UInt64> = []

    init(
        auth: Auth = .auth(),
        functions: Functions = Functions.functions(region: "us-central1")
    ) {
        self.auth = auth
        self.functions = functions
    }

    /// Starts once at app launch. StoreKit can approve an Ask-to-Buy or finish
    /// another interrupted consumable while no Store screen exists, so credit
    /// delivery cannot depend on reconstructing a web bag after relaunch.
    func startObservingTransactions() {
        guard transactionUpdatesTask == nil else { return }

        authStateHandle = auth.addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor [weak self] in
                self?.scheduleUnfinishedRecovery(for: user?.uid)
            }
        }
        transactionUpdatesTask = Task { @MainActor [weak self] in
            for await verification in StoreKit.Transaction.updates {
                guard !Task.isCancelled, let self else { break }
                await self.recoverObservedTransaction(verification)
            }
        }
        scheduleUnfinishedRecovery(for: auth.currentUser?.uid)
    }

    func displayPrices() async -> [String: String] {
        guard let products = try? await Product.products(for: Array(Self.supportedProductIDs)) else {
            return [:]
        }
        return Dictionary(uniqueKeysWithValues: products.map { ($0.id, $0.displayPrice) })
    }

    func checkout(
        rawItems: Any?,
        pendingResolution: @escaping (PoplurCardCheckoutResult) -> Void = { _ in }
    ) async -> PoplurCardCheckoutResult {
        guard !pendingResolutionInFlight else {
            return PoplurCardCheckoutResult(
                status: .failure,
                message: "Another App Store purchase is still awaiting approval.",
                completedProductCounts: [:],
                creditsAdded: 0,
                availableCredits: nil
            )
        }
        guard !checkoutInFlight else {
            return failure(.checkoutAlreadyRunning)
        }
        // Recovery may already have sent an unfinished transaction to the
        // server. Do not let a new charge path race its final StoreKit finish;
        // the user can retry as soon as that bounded reconciliation completes.
        guard backgroundTransactionsInFlight.isEmpty else {
            return failure(.purchaseRecoveryInProgress)
        }
        checkoutInFlight = true
        defer {
            checkoutInFlight = false
            scheduleUnfinishedRecovery(for: auth.currentUser?.uid)
        }

        var completedCounts: [String: Int] = [:]
        var totalCreditsAdded = 0
        var latestAvailableCredits: Int?

        do {
            guard let uid = auth.currentUser?.uid, !uid.isEmpty else {
                throw PoplurCardPurchaseError.signedOut
            }
            let lines = try Self.validatedLines(from: rawItems)
            var remainingProductIDs = lines.flatMap { line in
                Array(repeating: line.productID, count: line.quantity)
            }
            let accountToken = PoplurStoreAccountToken.value(forFirebaseUID: uid)

            // If a previous server call failed, StoreKit deliberately still has
            // that consumable unfinished. Deliver it before creating another
            // charge for the same requested bag unit.
            for await verification in StoreKit.Transaction.unfinished {
                let candidate: StoreKit.Transaction
                switch verification {
                case .verified(let transaction):
                    candidate = transaction
                case .unverified(let transaction, _):
                    guard remainingProductIDs.contains(transaction.productID),
                          Self.supportedProductIDs.contains(transaction.productID),
                          transaction.appAccountToken == accountToken else { continue }
                    throw PoplurCardPurchaseError.unverifiedTransaction
                }
                guard let requestedIndex = remainingProductIDs.firstIndex(of: candidate.productID),
                      Self.supportedProductIDs.contains(candidate.productID),
                      candidate.appAccountToken == accountToken else { continue }
                let grant = try await grant(
                    verification,
                    expectedProductID: candidate.productID
                )
                await candidate.finish()
                remainingProductIDs.remove(at: requestedIndex)
                Self.record(grant, counts: &completedCounts)
                totalCreditsAdded += grant.creditsAdded
                latestAvailableCredits = grant.availableCredits ?? latestAvailableCredits
            }

            let uniqueRemainingIDs = Array(Set(remainingProductIDs))
            let products = try await Product.products(for: uniqueRemainingIDs)
            let productsByID = Dictionary(uniqueKeysWithValues: products.map { ($0.id, $0) })
            guard productsByID.count == uniqueRemainingIDs.count else {
                throw PoplurCardPurchaseError.unavailableProducts
            }

            for (purchaseIndex, productID) in remainingProductIDs.enumerated() {
                guard let product = productsByID[productID] else {
                    throw PoplurCardPurchaseError.unavailableProducts
                }
                let purchase = try await product.purchase(options: [.appAccountToken(accountToken)])
                switch purchase {
                case .success(let verification):
                    let transaction = try Self.verifiedTransaction(from: verification)
                    guard transaction.productID == productID else {
                        throw PoplurCardPurchaseError.unverifiedTransaction
                    }
                    let grant = try await grant(verification, expectedProductID: productID)
                    await transaction.finish()
                    Self.record(grant, counts: &completedCounts)
                    totalCreditsAdded += grant.creditsAdded
                    latestAvailableCredits = grant.availableCredits ?? latestAvailableCredits

                case .userCancelled:
                    let purchased = completedCounts.values.reduce(0, +)
                    let message = purchased == 0
                        ? "Checkout was cancelled. Your bag is unchanged."
                        : "Checkout was cancelled after \(purchased) item\(purchased == 1 ? "" : "s") completed. Only the remaining items stay in your bag."
                    return PoplurCardCheckoutResult(
                        status: .cancelled,
                        message: message,
                        completedProductCounts: completedCounts,
                        creditsAdded: totalCreditsAdded,
                        availableCredits: latestAvailableCredits
                    )

                case .pending:
                    startPendingResolution(
                        productID: productID,
                        accountToken: accountToken,
                        unpurchasedItemCount: remainingProductIDs.count - purchaseIndex - 1,
                        completion: pendingResolution
                    )
                    return PoplurCardCheckoutResult(
                        status: .pending,
                        message: "The App Store purchase is awaiting approval. Completed items were removed from your bag; Poplur will update the pending item automatically.",
                        completedProductCounts: completedCounts,
                        creditsAdded: totalCreditsAdded,
                        availableCredits: latestAvailableCredits
                    )

                @unknown default:
                    throw PoplurCardPurchaseError.serverDidNotGrant
                }
            }

            let count = completedCounts.values.reduce(0, +)
            let creditMessage = totalCreditsAdded > 0
                ? " \(totalCreditsAdded.formatted()) Poplur Credits were added."
                : " Your Poplur Credits are ready."
            return PoplurCardCheckoutResult(
                status: .success,
                message: "\(count) App Store purchase\(count == 1 ? "" : "s") verified." + creditMessage,
                completedProductCounts: completedCounts,
                creditsAdded: totalCreditsAdded,
                availableCredits: latestAvailableCredits
            )
        } catch {
            let purchased = completedCounts.values.reduce(0, +)
            let prefix = purchased > 0
                ? "\(purchased) item\(purchased == 1 ? "" : "s") completed; only the remaining items stay in your bag. "
                : ""
            return PoplurCardCheckoutResult(
                status: .failure,
                message: prefix + error.localizedDescription,
                completedProductCounts: completedCounts,
                creditsAdded: totalCreditsAdded,
                availableCredits: latestAvailableCredits
            )
        }
    }

    private func startPendingResolution(
        productID: String,
        accountToken: UUID,
        unpurchasedItemCount: Int,
        completion: @escaping (PoplurCardCheckoutResult) -> Void
    ) {
        guard !pendingResolutionInFlight else { return }
        pendingResolutionInFlight = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            let result = await self.resolvePendingPurchase(
                productID: productID,
                accountToken: accountToken,
                unpurchasedItemCount: unpurchasedItemCount
            )
            self.pendingResolutionInFlight = false
            completion(result)
            self.scheduleUnfinishedRecovery(for: self.auth.currentUser?.uid)
        }
    }

    private func scheduleUnfinishedRecovery(for uid: String?) {
        unfinishedRecoveryTask?.cancel()
        unfinishedRecoveryTask = nil
        guard let uid, !uid.isEmpty, !checkoutInFlight, !pendingResolutionInFlight else { return }

        unfinishedRecoveryTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for await verification in StoreKit.Transaction.unfinished {
                guard !Task.isCancelled,
                      self.auth.currentUser?.uid == uid,
                      !self.checkoutInFlight,
                      !self.pendingResolutionInFlight else { return }
                await self.recoverVerifiedTransaction(verification, firebaseUID: uid)
            }
        }
    }

    private func recoverObservedTransaction(
        _ verification: VerificationResult<StoreKit.Transaction>
    ) async {
        guard !checkoutInFlight,
              !pendingResolutionInFlight,
              let uid = auth.currentUser?.uid,
              !uid.isEmpty else { return }
        await recoverVerifiedTransaction(verification, firebaseUID: uid)
    }

    private func recoverVerifiedTransaction(
        _ verification: VerificationResult<StoreKit.Transaction>,
        firebaseUID uid: String
    ) async {
        guard case .verified(let transaction) = verification,
              Self.supportedProductIDs.contains(transaction.productID),
              transaction.appAccountToken == PoplurStoreAccountToken.value(forFirebaseUID: uid),
              backgroundTransactionsInFlight.insert(transaction.id).inserted else { return }
        defer { backgroundTransactionsInFlight.remove(transaction.id) }

        do {
            let serverGrant = try await grant(verification, expectedProductID: transaction.productID)
            guard auth.currentUser?.uid == uid else { return }
            // Recheck immediately before StoreKit finish. Checkout also refuses
            // to start while this transaction remains in the in-flight set, so
            // recovery cannot silently remove a bag-reconcilable transaction
            // and make the checkout charge a replacement unit.
            guard !checkoutInFlight, !pendingResolutionInFlight else { return }
            await transaction.finish()
            let message = serverGrant.creditsAdded > 0
                ? "Recovered an interrupted App Store purchase. \(serverGrant.creditsAdded.formatted()) Poplur Credits were added."
                : "Finished an interrupted App Store purchase that was already delivered."
            let result = PoplurCardCheckoutResult(
                status: .success,
                message: message,
                completedProductCounts: [transaction.productID: 1],
                creditsAdded: serverGrant.creditsAdded,
                availableCredits: serverGrant.availableCredits
            )
            NotificationCenter.default.post(
                name: .poplurCardPurchaseRecovered,
                object: result,
                userInfo: [PoplurCardPurchaseRecoveryNotification.productIDKey: transaction.productID]
            )
        } catch {
            // Leave the transaction unfinished. StoreKit will surface it again
            // on the next authenticated launch/update; never finish before the
            // server confirms the idempotent credit grant.
            print("[PoplurCardPurchaseService] recovery deferred for \(transaction.productID): \(error.localizedDescription)")
        }
    }

    private func resolvePendingPurchase(
        productID: String,
        accountToken: UUID,
        unpurchasedItemCount: Int
    ) async -> PoplurCardCheckoutResult {
        // Approval can race the listener task onto the actor. Check the durable
        // unfinished queue first, then remain subscribed for a future update.
        for await verification in StoreKit.Transaction.unfinished {
            if let result = await resolvePendingUpdate(
                verification,
                productID: productID,
                accountToken: accountToken,
                unpurchasedItemCount: unpurchasedItemCount
            ) {
                return result
            }
        }
        for await verification in StoreKit.Transaction.updates {
            if let result = await resolvePendingUpdate(
                verification,
                productID: productID,
                accountToken: accountToken,
                unpurchasedItemCount: unpurchasedItemCount
            ) {
                return result
            }
        }
        return failure(.serverDidNotGrant)
    }

    private func resolvePendingUpdate(
        _ verification: VerificationResult<StoreKit.Transaction>,
        productID: String,
        accountToken: UUID,
        unpurchasedItemCount: Int
    ) async -> PoplurCardCheckoutResult? {
        let candidate: StoreKit.Transaction
        switch verification {
        case .verified(let transaction):
            candidate = transaction
        case .unverified(let transaction, _):
            guard transaction.productID == productID,
                  transaction.appAccountToken == accountToken else { return nil }
            return failure(.unverifiedTransaction)
        }
        guard candidate.productID == productID,
              candidate.appAccountToken == accountToken else { return nil }

        do {
            let serverGrant = try await grant(verification, expectedProductID: productID)
            await candidate.finish()
            let hasMoreItems = unpurchasedItemCount > 0
            return PoplurCardCheckoutResult(
                status: hasMoreItems ? .failure : .success,
                message: hasMoreItems
                    ? "The approval-pending card was verified. The remaining \(unpurchasedItemCount) item\(unpurchasedItemCount == 1 ? "" : "s") can now be checked out."
                    : "The approval-pending App Store purchase was verified. Your Poplur Credits are ready.",
                completedProductCounts: [productID: 1],
                creditsAdded: serverGrant.creditsAdded,
                availableCredits: serverGrant.availableCredits
            )
        } catch {
            return PoplurCardCheckoutResult(
                status: .failure,
                message: error.localizedDescription,
                completedProductCounts: [:],
                creditsAdded: 0,
                availableCredits: nil
            )
        }
    }

    private func failure(_ error: PoplurCardPurchaseError) -> PoplurCardCheckoutResult {
        PoplurCardCheckoutResult(
            status: .failure,
            message: error.localizedDescription,
            completedProductCounts: [:],
            creditsAdded: 0,
            availableCredits: nil
        )
    }

    private static func validatedLines(from rawItems: Any?) throws -> [CheckoutLine] {
        guard let rawValues = rawItems as? [Any], !rawValues.isEmpty else {
            throw PoplurCardPurchaseError.invalidBag
        }
        var rawLines: [[String: Any]] = []
        rawLines.reserveCapacity(rawValues.count)
        for rawValue in rawValues {
            guard let rawLine = rawValue as? [String: Any] else {
                throw PoplurCardPurchaseError.invalidBag
            }
            rawLines.append(rawLine)
        }

        var productOrder: [String] = []
        var quantities: [String: Int] = [:]
        for rawLine in rawLines {
            let cardID = rawLine["cardId"] as? String
            let declaredIOSProductID = rawLine["iosProductId"] as? String
            let mappedProductID = cardID.flatMap { productIDByCardID[$0] }
            guard cardID == nil || mappedProductID != nil,
                  let productID = mappedProductID ?? declaredIOSProductID,
                  supportedProductIDs.contains(productID),
                  declaredIOSProductID == nil || declaredIOSProductID == productID,
                  let quantityNumber = rawLine["quantity"] as? NSNumber else {
                throw PoplurCardPurchaseError.unsupportedProduct
            }
            let rawQuantity = quantityNumber.doubleValue
            guard rawQuantity.rounded(.towardZero) == rawQuantity,
                  rawQuantity >= 1,
                  rawQuantity <= 10 else {
                throw PoplurCardPurchaseError.invalidBag
            }
            if quantities[productID] == nil { productOrder.append(productID) }
            quantities[productID, default: 0] += Int(rawQuantity)
        }

        let totalQuantity = quantities.values.reduce(0, +)
        guard totalQuantity > 0, totalQuantity <= 20 else {
            throw PoplurCardPurchaseError.invalidBag
        }
        var lines: [CheckoutLine] = []
        lines.reserveCapacity(productOrder.count)
        for productID in productOrder {
            guard let quantity = quantities[productID] else { continue }
            lines.append(CheckoutLine(productID: productID, quantity: quantity))
        }
        return lines
    }

    private static func verifiedTransaction(
        from verification: VerificationResult<StoreKit.Transaction>
    ) throws -> StoreKit.Transaction {
        switch verification {
        case .verified(let transaction):
            return transaction
        case .unverified:
            throw PoplurCardPurchaseError.unverifiedTransaction
        }
    }

    private func grant(
        _ verification: VerificationResult<StoreKit.Transaction>,
        expectedProductID: String
    ) async throws -> Grant {
        let transaction = try Self.verifiedTransaction(from: verification)
        guard transaction.productID == expectedProductID else {
            throw PoplurCardPurchaseError.unverifiedTransaction
        }

        let response: HTTPSCallableResult = try await withCheckedThrowingContinuation { continuation in
            functions.httpsCallable("verifyCardPurchase").call([
                "platform": "ios",
                "productId": expectedProductID,
                "signedTransaction": verification.jwsRepresentation
            ]) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let result {
                    continuation.resume(returning: result)
                } else {
                    continuation.resume(throwing: PoplurCardPurchaseError.serverDidNotGrant)
                }
            }
        }

        guard let data = response.data as? [String: Any],
              data["verified"] as? Bool == true,
              data["productId"] as? String == expectedProductID else {
            throw PoplurCardPurchaseError.serverDidNotGrant
        }
        return Grant(
            productID: expectedProductID,
            creditsAdded: Self.intValue(data["creditsAdded"]),
            availableCredits: Self.optionalIntValue(data["availableCredits"])
        )
    }

    private static func record(_ grant: Grant, counts: inout [String: Int]) {
        counts[grant.productID, default: 0] += 1
    }

    private static func intValue(_ value: Any?) -> Int {
        optionalIntValue(value) ?? 0
    }

    private static func optionalIntValue(_ value: Any?) -> Int? {
        if let int = value as? Int { return int }
        if let number = value as? NSNumber { return number.intValue }
        if let string = value as? String { return Int(string) }
        return nil
    }
}
