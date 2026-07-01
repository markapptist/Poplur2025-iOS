import Foundation
import CoreLocation
import FirebaseAuth
import FirebaseFirestore

enum DeliveryProviderKind: String, CaseIterable, Identifiable, Sendable {
    case uberDirect = "uber_direct"
    case doorDashDrive = "doordash_drive"
    case mock

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .uberDirect: return "Uber Direct"
        case .doorDashDrive: return "DoorDash Drive"
        case .mock: return "Mock Courier"
        }
    }
}

enum DeliveryOrderStatus: String, CaseIterable, Identifiable, Sendable {
    case requested
    case courierAssigned = "courier_assigned"
    case pickedUp = "picked_up"
    case inTransit = "in_transit"
    case delivered
    case failedCancelled = "failed_cancelled"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .requested: return "Requested"
        case .courierAssigned: return "Courier assigned"
        case .pickedUp: return "Picked up"
        case .inTransit: return "In transit"
        case .delivered: return "Delivered"
        case .failedCancelled: return "Failed/cancelled"
        }
    }

    var sortIndex: Int {
        switch self {
        case .requested: return 0
        case .courierAssigned: return 1
        case .pickedUp: return 2
        case .inTransit: return 3
        case .delivered: return 4
        case .failedCancelled: return 5
        }
    }

    static func from(_ rawValue: String?) -> DeliveryOrderStatus {
        guard let rawValue else { return .requested }
        return DeliveryOrderStatus(rawValue: rawValue) ?? .requested
    }
}

struct DeliveryLocation: Hashable, Sendable {
    var latitude: Double
    var longitude: Double
    var address: String
    var label: String

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var firestoreData: [String: Any] {
        [
            "latitude": latitude,
            "longitude": longitude,
            "address": address,
            "label": label
        ]
    }

    static func from(_ data: [String: Any]?, fallbackLabel: String) -> DeliveryLocation {
        DeliveryLocation(
            latitude: data?["latitude"] as? Double ?? 0,
            longitude: data?["longitude"] as? Double ?? 0,
            address: data?["address"] as? String ?? "",
            label: data?["label"] as? String ?? fallbackLabel
        )
    }
}

struct DeliveryQuote: Hashable, Sendable {
    var provider: DeliveryProviderKind
    var feeEstimate: Double
    var currency: String
    var etaMinutes: Int

    var displayFee: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        return formatter.string(from: NSNumber(value: feeEstimate)) ?? "$\(String(format: "%.2f", feeEstimate))"
    }

    var firestoreData: [String: Any] {
        [
            "amount": feeEstimate,
            "currency": currency,
            "display": displayFee,
            "etaMinutes": etaMinutes
        ]
    }

    static func from(_ data: [String: Any]?, provider: DeliveryProviderKind) -> DeliveryQuote {
        DeliveryQuote(
            provider: provider,
            feeEstimate: data?["amount"] as? Double ?? 0,
            currency: data?["currency"] as? String ?? "USD",
            etaMinutes: data?["etaMinutes"] as? Int ?? 0
        )
    }
}

struct DeliveryCheckoutDraft: Hashable, Sendable {
    var deliveryAddress: String
    var contactName: String
    var phoneNumber: String
    var itemNotes: String
    var dropoffLocation: DeliveryLocation
}

struct ProviderDelivery: Hashable, Sendable {
    var id: String
    var trackingURL: String?
}

struct DeliveryOrder: Identifiable, Hashable, Sendable {
    var id: String
    var postId: String
    var buyerUserId: String
    var merchantUserId: String
    var pickupLocation: DeliveryLocation
    var dropoffLocation: DeliveryLocation
    var provider: DeliveryProviderKind
    var providerDeliveryId: String
    var status: DeliveryOrderStatus
    var trackingUrl: String?
    var feeEstimate: DeliveryQuote
    var contactName: String
    var phoneNumber: String
    var itemNotes: String
    var createdAt: Date?
    var updatedAt: Date?

    init(
        id: String,
        postId: String,
        buyerUserId: String,
        merchantUserId: String,
        pickupLocation: DeliveryLocation,
        dropoffLocation: DeliveryLocation,
        provider: DeliveryProviderKind,
        providerDeliveryId: String,
        status: DeliveryOrderStatus,
        trackingUrl: String?,
        feeEstimate: DeliveryQuote,
        contactName: String,
        phoneNumber: String,
        itemNotes: String,
        createdAt: Date? = nil,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.postId = postId
        self.buyerUserId = buyerUserId
        self.merchantUserId = merchantUserId
        self.pickupLocation = pickupLocation
        self.dropoffLocation = dropoffLocation
        self.provider = provider
        self.providerDeliveryId = providerDeliveryId
        self.status = status
        self.trackingUrl = trackingUrl
        self.feeEstimate = feeEstimate
        self.contactName = contactName
        self.phoneNumber = phoneNumber
        self.itemNotes = itemNotes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init?(id: String, data: [String: Any]) {
        let provider = DeliveryProviderKind(rawValue: data["provider"] as? String ?? "") ?? .mock
        self.init(
            id: id,
            postId: data["postId"] as? String ?? "",
            buyerUserId: data["buyerUserId"] as? String ?? "",
            merchantUserId: data["merchantUserId"] as? String ?? data["postOwnerId"] as? String ?? "",
            pickupLocation: DeliveryLocation.from(data["pickupLocation"] as? [String: Any], fallbackLabel: "Pickup"),
            dropoffLocation: DeliveryLocation.from(data["dropoffLocation"] as? [String: Any], fallbackLabel: "Dropoff"),
            provider: provider,
            providerDeliveryId: data["providerDeliveryId"] as? String ?? "",
            status: DeliveryOrderStatus.from(data["status"] as? String),
            trackingUrl: data["trackingUrl"] as? String,
            feeEstimate: DeliveryQuote.from(data["feeEstimate"] as? [String: Any], provider: provider),
            contactName: data["contactName"] as? String ?? "",
            phoneNumber: data["phoneNumber"] as? String ?? "",
            itemNotes: data["itemNotes"] as? String ?? "",
            createdAt: (data["createdAt"] as? Timestamp)?.dateValue(),
            updatedAt: (data["updatedAt"] as? Timestamp)?.dateValue()
        )
    }
}

enum DeliveryServiceError: LocalizedError {
    case providerNotConfigured(String)
    case missingOrder

    var errorDescription: String? {
        switch self {
        case .providerNotConfigured(let provider):
            return "\(provider) is ready for API key integration, but is not configured yet."
        case .missingOrder:
            return "Delivery order could not be found."
        }
    }
}

protocol DeliveryProvider: Sendable {
    var kind: DeliveryProviderKind { get }
    func createDelivery(orderId: String, request: DeliveryCheckoutDraft, quote: DeliveryQuote) async throws -> ProviderDelivery
    func getQuote(request: DeliveryCheckoutDraft) async throws -> DeliveryQuote
    func getDeliveryStatus(providerDeliveryId: String) async throws -> DeliveryOrderStatus
    func cancelDelivery(providerDeliveryId: String) async throws
}

struct MockDeliveryProvider: DeliveryProvider {
    let kind: DeliveryProviderKind = .mock

    func createDelivery(orderId: String, request: DeliveryCheckoutDraft, quote: DeliveryQuote) async throws -> ProviderDelivery {
        ProviderDelivery(
            id: "mock_\(orderId)",
            trackingURL: "https://poplur.local/delivery/\(orderId)"
        )
    }

    func getQuote(request: DeliveryCheckoutDraft) async throws -> DeliveryQuote {
        DeliveryQuote(provider: .mock, feeEstimate: 6.99, currency: "USD", etaMinutes: 28)
    }

    func getDeliveryStatus(providerDeliveryId: String) async throws -> DeliveryOrderStatus {
        .inTransit
    }

    func cancelDelivery(providerDeliveryId: String) async throws { }
}

struct UberDirectDeliveryProvider: DeliveryProvider {
    let kind: DeliveryProviderKind = .uberDirect

    func createDelivery(orderId: String, request: DeliveryCheckoutDraft, quote: DeliveryQuote) async throws -> ProviderDelivery {
        // TODO: Call Uber Direct Create Delivery with Poplur pickup/dropoff payload.
        throw DeliveryServiceError.providerNotConfigured(kind.displayName)
    }

    func getQuote(request: DeliveryCheckoutDraft) async throws -> DeliveryQuote {
        // TODO: Call Uber Direct quote endpoint once credentials are available.
        throw DeliveryServiceError.providerNotConfigured(kind.displayName)
    }

    func getDeliveryStatus(providerDeliveryId: String) async throws -> DeliveryOrderStatus {
        // TODO: Map Uber Direct delivery statuses into DeliveryOrderStatus.
        throw DeliveryServiceError.providerNotConfigured(kind.displayName)
    }

    func cancelDelivery(providerDeliveryId: String) async throws {
        // TODO: Call Uber Direct cancel endpoint.
        throw DeliveryServiceError.providerNotConfigured(kind.displayName)
    }
}

struct DoorDashDriveDeliveryProvider: DeliveryProvider {
    let kind: DeliveryProviderKind = .doorDashDrive

    func createDelivery(orderId: String, request: DeliveryCheckoutDraft, quote: DeliveryQuote) async throws -> ProviderDelivery {
        // TODO: Call DoorDash Drive delivery creation with Poplur pickup/dropoff payload.
        throw DeliveryServiceError.providerNotConfigured(kind.displayName)
    }

    func getQuote(request: DeliveryCheckoutDraft) async throws -> DeliveryQuote {
        // TODO: Call DoorDash Drive quote endpoint once credentials are available.
        throw DeliveryServiceError.providerNotConfigured(kind.displayName)
    }

    func getDeliveryStatus(providerDeliveryId: String) async throws -> DeliveryOrderStatus {
        // TODO: Map DoorDash Drive statuses into DeliveryOrderStatus.
        throw DeliveryServiceError.providerNotConfigured(kind.displayName)
    }

    func cancelDelivery(providerDeliveryId: String) async throws {
        // TODO: Call DoorDash Drive cancel endpoint.
        throw DeliveryServiceError.providerNotConfigured(kind.displayName)
    }
}

final class DeliveryService {
    static let shared = DeliveryService()

    private let db: Firestore
    private let provider: DeliveryProvider
    private let collectionName = "delivery_orders"

    init(db: Firestore = Firestore.firestore(), provider: DeliveryProvider = MockDeliveryProvider()) {
        self.db = db
        self.provider = provider
    }

    func getQuote(for request: DeliveryCheckoutDraft) async throws -> DeliveryQuote {
        try await provider.getQuote(request: request)
    }

    func createOrder(post: FeedPost, draft: DeliveryCheckoutDraft) async throws -> DeliveryOrder {
        let orderRef = db.collection(collectionName).document()
        let pickupAddress = [post.cityName, post.countryName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
        let pickupLocation = DeliveryLocation(
            latitude: post.latitude,
            longitude: post.longitude,
            address: pickupAddress.isEmpty ? "Poplur post pickup" : pickupAddress,
            label: "Pickup"
        )
        let quote = try await provider.getQuote(request: draft)
        let providerDelivery = try await provider.createDelivery(orderId: orderRef.documentID, request: draft, quote: quote)
        let buyerUserID = Auth.auth().currentUser?.uid ?? "anonymous_mock_buyer"

        var data: [String: Any] = [
            "postId": post.id,
            "buyerUserId": buyerUserID,
            "merchantUserId": post.userID,
            "postOwnerId": post.userID,
            "pickupLocation": pickupLocation.firestoreData,
            "dropoffLocation": draft.dropoffLocation.firestoreData,
            "provider": provider.kind.rawValue,
            "providerDeliveryId": providerDelivery.id,
            "status": DeliveryOrderStatus.requested.rawValue,
            "feeEstimate": quote.firestoreData,
            "contactName": draft.contactName,
            "phoneNumber": draft.phoneNumber,
            "itemNotes": draft.itemNotes,
            "createdAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp()
        ]
        if let trackingURL = providerDelivery.trackingURL {
            data["trackingUrl"] = trackingURL
        }

        try await orderRef.setData(data)

        if provider.kind == .mock {
            startMockStatusSimulation(orderId: orderRef.documentID)
        }

        return DeliveryOrder(
            id: orderRef.documentID,
            postId: post.id,
            buyerUserId: buyerUserID,
            merchantUserId: post.userID,
            pickupLocation: pickupLocation,
            dropoffLocation: draft.dropoffLocation,
            provider: provider.kind,
            providerDeliveryId: providerDelivery.id,
            status: .requested,
            trackingUrl: providerDelivery.trackingURL,
            feeEstimate: quote,
            contactName: draft.contactName,
            phoneNumber: draft.phoneNumber,
            itemNotes: draft.itemNotes
        )
    }

    @discardableResult
    func listen(orderId: String, onChange: @escaping @MainActor (DeliveryOrder?) -> Void) -> ListenerRegistration {
        db.collection(collectionName).document(orderId).addSnapshotListener { snapshot, _ in
            let order = snapshot.flatMap { snap -> DeliveryOrder? in
                guard let data = snap.data() else { return nil }
                return DeliveryOrder(id: snap.documentID, data: data)
            }
            Task { @MainActor in
                onChange(order)
            }
        }
    }

    func getDeliveryStatus(order: DeliveryOrder) async throws -> DeliveryOrderStatus {
        try await provider.getDeliveryStatus(providerDeliveryId: order.providerDeliveryId)
    }

    func cancelOrder(_ order: DeliveryOrder) async throws {
        try await provider.cancelDelivery(providerDeliveryId: order.providerDeliveryId)
        try await db.collection(collectionName).document(order.id).updateData([
            "status": DeliveryOrderStatus.failedCancelled.rawValue,
            "updatedAt": FieldValue.serverTimestamp()
        ])
    }

    private func startMockStatusSimulation(orderId: String) {
        Task {
            let statuses: [DeliveryOrderStatus] = [
                .courierAssigned,
                .pickedUp,
                .inTransit,
                .delivered
            ]
            for status in statuses {
                try? await Task.sleep(nanoseconds: 3_500_000_000)
                try? await db.collection(collectionName).document(orderId).updateData([
                    "status": status.rawValue,
                    "updatedAt": FieldValue.serverTimestamp()
                ])
            }
        }
    }
}
