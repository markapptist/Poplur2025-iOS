import SwiftUI
import FirebaseFirestore

struct DeliverToMeButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Deliver", systemImage: "shippingbox.fill")
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .foregroundStyle(.black)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(
                    Capsule()
                        .fill(Color(red: 0.27, green: 1.0, blue: 0.38))
                )
                .shadow(color: .black.opacity(0.35), radius: 12, x: 0, y: 6)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Deliver to me")
    }
}

struct DeliveryFlowView: View {
    let post: FeedPost
    let displayName: String

    @Environment(\.dismiss) private var dismiss
    @State private var deliveryAddress = ""
    @State private var contactName = ""
    @State private var phoneNumber = ""
    @State private var itemNotes = ""
    @State private var estimateText = "$6.99 estimate"
    @State private var orderId: String?
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            LinearGradient(
                colors: [
                    Color(red: 0.10, green: 0.20, blue: 0.12).opacity(0.95),
                    .black,
                    Color(red: 0.05, green: 0.05, blue: 0.08)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            if let orderId {
                DeliveryOrderStatusView(orderId: orderId, onClose: { dismiss() })
            } else {
                checkoutContent
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .task {
            await refreshEstimate()
        }
    }

    private var checkoutContent: some View {
        VStack(spacing: 0) {
            header(title: "Deliver to Me", subtitle: displayName)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    postSummary
                    deliveryField(
                        title: "Delivery address",
                        placeholder: "Street, unit, city",
                        text: $deliveryAddress,
                        axis: .vertical,
                        minHeight: 78
                    )
                    deliveryField(title: "Contact name", placeholder: "Name for courier", text: $contactName)
                    deliveryField(title: "Phone number", placeholder: "Courier contact number", text: $phoneNumber)
                    deliveryField(
                        title: "Item/package notes",
                        placeholder: "Door code, handoff notes, item details",
                        text: $itemNotes,
                        axis: .vertical,
                        minHeight: 98
                    )
                    feeEstimate

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(Color(red: 1, green: 0.35, blue: 0.35))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Button {
                        submit()
                    } label: {
                        HStack {
                            if isSubmitting {
                                ProgressView()
                                    .tint(.black)
                            } else {
                                Image(systemName: "shippingbox.fill")
                            }
                            Text(isSubmitting ? "Requesting courier" : "Request Delivery")
                        }
                        .font(.system(size: 18, weight: .heavy, design: .rounded))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 17)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(red: 0.27, green: 1.0, blue: 0.38))
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isSubmitting)
                    .opacity(isSubmitting ? 0.72 : 1)
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 28)
            }
        }
    }

    private var postSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Pickup")
                .font(.system(size: 12, weight: .black, design: .rounded))
                .foregroundStyle(.white.opacity(0.55))
                .textCase(.uppercase)
            Text(pickupDisplay)
                .font(.system(size: 20, weight: .black, design: .rounded))
                .foregroundStyle(.white)
            Text("Location shared only with delivery")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.55))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.white.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(.white.opacity(0.12), lineWidth: 1)
                )
        )
    }

    private var feeEstimate: some View {
        HStack {
            VStack(alignment: .leading, spacing: 5) {
                Text("Estimated delivery fee")
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .foregroundStyle(.white.opacity(0.58))
                    .textCase(.uppercase)
                Text(estimateText)
                    .font(.system(size: 24, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
            }
            Spacer()
            Image(systemName: "bolt.fill")
                .font(.system(size: 20, weight: .black))
                .foregroundStyle(Color(red: 0.27, green: 1.0, blue: 0.38))
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.white.opacity(0.08))
        )
    }

    private func header(title: String, subtitle: String) -> some View {
        HStack(alignment: .center, spacing: 14) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .black))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(Circle().fill(.white.opacity(0.10)))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 30, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.58))
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 18)
    }

    private func deliveryField(
        title: String,
        placeholder: String,
        text: Binding<String>,
        axis: Axis = .horizontal,
        minHeight: CGFloat = 58
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .black, design: .rounded))
                .foregroundStyle(.white.opacity(0.58))
                .textCase(.uppercase)
            TextField(placeholder, text: text, axis: axis)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .tint(Color(red: 0.27, green: 1.0, blue: 0.38))
                .padding(14)
                .frame(minHeight: minHeight, alignment: .topLeading)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.white.opacity(0.08))
                )
        }
    }

    private var pickupDisplay: String {
        [post.cityName, post.countryName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
            .ifEmpty("Poplur post location")
    }

    private func submit() {
        let address = deliveryAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = contactName.trimmingCharacters(in: .whitespacesAndNewlines)
        let phone = phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !address.isEmpty, !name.isEmpty, !phone.isEmpty else {
            errorMessage = "Add a delivery address, contact name, and phone number."
            return
        }

        errorMessage = nil
        isSubmitting = true
        Task {
            do {
                let order = try await DeliveryService.shared.createOrder(post: post, draft: draft)
                await MainActor.run {
                    orderId = order.id
                    isSubmitting = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isSubmitting = false
                }
            }
        }
    }

    private func refreshEstimate() async {
        do {
            let quote = try await DeliveryService.shared.getQuote(for: draft)
            await MainActor.run {
                estimateText = "\(quote.displayFee) estimate"
            }
        } catch {
            await MainActor.run {
                estimateText = "$6.99 estimate"
            }
        }
    }

    private var draft: DeliveryCheckoutDraft {
        DeliveryCheckoutDraft(
            deliveryAddress: deliveryAddress,
            contactName: contactName,
            phoneNumber: phoneNumber,
            itemNotes: itemNotes,
            dropoffLocation: DeliveryLocation(
                latitude: post.latitude,
                longitude: post.longitude,
                address: deliveryAddress,
                label: "Dropoff"
            )
        )
    }
}

struct DeliveryOrderStatusView: View {
    let orderId: String
    let onClose: () -> Void

    @State private var order: DeliveryOrder?
    @State private var listener: ListenerRegistration?

    private let timeline: [DeliveryOrderStatus] = [
        .requested,
        .courierAssigned,
        .pickedUp,
        .inTransit,
        .delivered
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 14) {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 17, weight: .black))
                        .foregroundStyle(.white)
                        .frame(width: 42, height: 42)
                        .background(Circle().fill(.white.opacity(0.10)))
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Delivery Status")
                        .font(.system(size: 29, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                    Text(order?.provider.displayName ?? "Mock Courier")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.58))
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 18)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    orderSummary
                    statusTimeline
                    if let trackingUrl = order?.trackingUrl, !trackingUrl.isEmpty {
                        trackingCard(trackingUrl)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 28)
            }
        }
        .onAppear {
            listener = DeliveryService.shared.listen(orderId: orderId) { latest in
                order = latest
            }
        }
        .onDisappear {
            listener?.remove()
            listener = nil
        }
    }

    private var orderSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(order?.status.displayName ?? "Requested")
                .font(.system(size: 28, weight: .black, design: .rounded))
                .foregroundStyle(.white)
            Text(order?.feeEstimate.displayFee ?? "$6.99")
                .font(.system(size: 17, weight: .heavy, design: .rounded))
                .foregroundStyle(Color(red: 0.27, green: 1.0, blue: 0.38))
            Text(order?.dropoffLocation.address.ifEmpty("Delivery address pending") ?? "Delivery address pending")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.58))
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.white.opacity(0.08))
        )
    }

    private var statusTimeline: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(timeline) { status in
                statusRow(status)
            }
            if order?.status == .failedCancelled {
                statusRow(.failedCancelled)
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.white.opacity(0.06))
        )
    }

    private func statusRow(_ status: DeliveryOrderStatus) -> some View {
        let activeStatus = order?.status ?? .requested
        let isComplete = activeStatus != .failedCancelled && status.sortIndex <= activeStatus.sortIndex
        let isFailure = status == .failedCancelled
        return HStack(spacing: 14) {
            Image(systemName: isFailure ? "xmark.circle.fill" : (isComplete ? "checkmark.circle.fill" : "circle"))
                .font(.system(size: 22, weight: .black))
                .foregroundStyle(isFailure ? .red : (isComplete ? Color(red: 0.27, green: 1.0, blue: 0.38) : .white.opacity(0.32)))
                .frame(width: 28)
            Text(status.displayName)
                .font(.system(size: 17, weight: .black, design: .rounded))
                .foregroundStyle(isComplete || isFailure ? .white : .white.opacity(0.42))
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
    }

    private func trackingCard(_ url: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tracking")
                .font(.system(size: 12, weight: .black, design: .rounded))
                .foregroundStyle(.white.opacity(0.58))
                .textCase(.uppercase)
            Text(url)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .textSelection(.enabled)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.white.opacity(0.08))
        )
    }
}

private extension String {
    func ifEmpty(_ replacement: String) -> String {
        isEmpty ? replacement : self
    }
}
