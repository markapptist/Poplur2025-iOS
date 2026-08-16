import XCTest
@testable import Poplur2025

final class PoplurCardPurchaseServiceTests: XCTestCase {
    func testFirebaseUIDProducesStableStoreAccountToken() {
        XCTAssertEqual(
            PoplurStoreAccountToken.value(forFirebaseUID: "firebase-user-123").uuidString.lowercased(),
            "4ab08c5d-68ee-518c-88df-44084fd659b3"
        )
    }

    func testStoreAccountTokenHasVersionFiveAndRFC4122Variant() {
        let token = PoplurStoreAccountToken.value(forFirebaseUID: "another-user")
        let bytes = withUnsafeBytes(of: token.uuid) { Array($0) }

        XCTAssertEqual(bytes[6] >> 4, 5)
        XCTAssertEqual(bytes[8] >> 6, 2)
    }

    func testSupportedCardProductIDsAreExact() {
        XCTAssertEqual(PoplurCardPurchaseService.supportedProductIDs, [
            "com.apptist.Poplur2025.card.inverted",
            "com.apptist.Poplur2025.card.lens",
            "com.apptist.Poplur2025.card.splitdiamond",
            "com.apptist.Poplur2025.card.swoosh"
        ])
    }

    func testStableCardIDsMapToIOSProducts() {
        XCTAssertEqual(PoplurCardPurchaseService.productIDByCardID, [
            "inverted": "com.apptist.Poplur2025.card.inverted",
            "lens": "com.apptist.Poplur2025.card.lens",
            "splitDiamond": "com.apptist.Poplur2025.card.splitdiamond",
            "swoosh": "com.apptist.Poplur2025.card.swoosh"
        ])
    }

    func testCheckoutWebPayloadCarriesExactRequestAndCompletedQuantity() {
        let productID = "com.apptist.Poplur2025.card.lens"
        let payload = PoplurCardCheckoutResult(
            status: .pending,
            message: "Awaiting approval",
            completedProductCounts: [productID: 2],
            creditsAdded: 1_100,
            availableCredits: 1_500
        ).webPayload(requestID: "request-123")

        XCTAssertEqual(payload["requestId"] as? String, "request-123")
        XCTAssertEqual(payload["status"] as? String, "pending")
        XCTAssertEqual(payload["creditsAdded"] as? Int, 1_100)
        guard let completed = payload["completedItems"] as? [[String: Any]] else {
            return XCTFail("Expected completedItems in the web payload")
        }
        XCTAssertEqual(completed.first?["productId"] as? String, productID)
        XCTAssertEqual(completed.first?["cardId"] as? String, "lens")
        XCTAssertEqual(completed.first?["quantity"] as? Int, 2)
    }

    func testRecoveryNotificationContractIsStable() {
        XCTAssertEqual(Notification.Name.poplurCardPurchaseRecovered.rawValue, "PoplurCardPurchaseRecovered")
        XCTAssertEqual(PoplurCardPurchaseRecoveryNotification.productIDKey, "productID")
    }
}
