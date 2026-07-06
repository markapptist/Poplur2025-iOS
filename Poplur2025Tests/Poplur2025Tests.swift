//
//  Poplur2025Tests.swift
//  Poplur2025Tests
//
//  Created by Apptist Inc. on 2025-08-03.
//

import Foundation
import Testing
@testable import Poplur2025

struct Poplur2025Tests {

    @Test func freeUserCannotGenerateWithoutCredits() async throws {
        let service = PoplurAIStackService()
        let request = AIGenerationRequest(
            userId: "free-user",
            plan: .free,
            contentType: .image,
            prompt: "Create a premium Poplur poster",
            inputAssetIds: [],
            publishMetadata: nil,
            campaignAssetTypes: [],
            metadata: [:]
        )

        let balance = CreatorCreditBalance(userId: "free-user", availableCredits: 0, reservedCredits: 0, updatedAt: Date())

        #expect(throws: AIStackError.aiLockedForPlan) {
            _ = try service.validateGenerationRequest(request, balance: balance)
        }
    }

    @Test func userWithCreditsCanReserveGenerationCost() async throws {
        let ledger = CreatorCreditLedger()
        try await ledger.grant(userId: "creator", amount: 25, type: .promotionalGrant)
        try await ledger.reserve(userId: "creator", amount: 5, jobId: "job-1", provider: .google, contentType: .image)

        let balance = await ledger.balance(for: "creator")
        #expect(balance.availableCredits == 20)
        #expect(balance.reservedCredits == 5)
    }

    @Test func failedGenerationRefundsReservedCredits() async throws {
        let ledger = CreatorCreditLedger()
        try await ledger.grant(userId: "creator", amount: 25, type: .promotionalGrant)
        try await ledger.reserve(userId: "creator", amount: 5, jobId: "job-1", provider: .google, contentType: .image)
        try await ledger.refund(userId: "creator", amount: 5, relatedJobId: "job-1")

        let balance = await ledger.balance(for: "creator")
        #expect(balance.availableCredits == 25)
        #expect(balance.reservedCredits == 0)
    }

    @Test func negativeBalancesAreImpossible() async throws {
        let ledger = CreatorCreditLedger()

        await #expect(throws: AIStackError.insufficientCredits) {
            try await ledger.reserve(userId: "creator", amount: 5, jobId: "job-1", provider: .google, contentType: .image)
        }
    }

    @Test func radiusBoostDeductsCreditsAndUpdatesVisibilityRadius() async throws {
        let ledger = CreatorCreditLedger()
        try await ledger.grant(userId: "creator", amount: 50, type: .purchasedCredits)
        let service = PoplurAIStackService(ledger: ledger)
        let post = AIMapPost(
            id: "post-1",
            userId: "creator",
            assetIds: ["asset-1"],
            publishMetadata: AIMapPublishMetadata(
                latitude: 43.6532,
                longitude: -79.3832,
                locationName: "Toronto",
                address: nil,
                radiusMeters: 1_000,
                contentType: .image,
                businessId: nil,
                campaignId: nil,
                expirationDate: nil,
                tags: [],
                category: nil
            ),
            organicRadiusMeters: 1_000,
            boostedRadiusMeters: 0,
            boostExpiresAt: nil,
            engagementScore: 0,
            visibilityStatus: "visible"
        )

        let boosted = try await service.applyRadiusBoost(post: post, userId: "creator", tier: .local)
        let balance = await ledger.balance(for: "creator")

        #expect(boosted.boostedRadiusMeters == 2_000)
        #expect(boosted.boostExpiresAt != nil)
        #expect(balance.availableCredits == 40)
    }

    @Test func mapPublishingRequiresValidLocationMetadata() throws {
        let service = PoplurAIStackService()
        let metadata = AIMapPublishMetadata(
            latitude: 999,
            longitude: -79.3832,
            locationName: "Bad latitude",
            address: nil,
            radiusMeters: 1_000,
            contentType: .image,
            businessId: nil,
            campaignId: nil,
            expirationDate: nil,
            tags: [],
            category: nil
        )

        #expect(throws: AIStackError.invalidLocation) {
            try service.validatePublishMetadata(metadata)
        }
    }
}
