import XCTest

@testable import ZerohashSDK

/// Covers the bridge payload → typed event parsers. The status and the
/// account-matching validation both arrive nested and `success` is derived rather
/// than sent, so a silent shape change would hand hosts an empty event.
final class FundDepositEventTests: XCTestCase {

    private func depositPayload(
        statusValue: String,
        validationStatus: String? = nil,
        validationReason: String? = nil
    ) -> [String: Any] {
        var payload: [String: Any] = [
            "depositId": "dep-1",
            "assetId": "USDC",
            "networkId": "ethereum",
            "amount": "10",
            "status": [
                "value": statusValue,
                "details": "some detail",
                "occurredAt": "2026-08-19T00:00:00Z",
            ],
        ]
        if let validationStatus {
            var validation: [String: Any] = ["status": validationStatus]
            if let validationReason { validation["reason"] = validationReason }
            payload["accountMatchingValidation"] = validation
        }
        return payload
    }

    // MARK: - FundDepositEvent

    func testFlattensTheNestedStatusAndDerivesSuccess() {
        let event = FundDepositEvent(from: depositPayload(statusValue: "PROCESSED"))

        XCTAssertEqual(event.depositId, "dep-1")
        XCTAssertEqual(event.status, "PROCESSED")
        XCTAssertEqual(event.statusDetails, "some detail")
        XCTAssertEqual(event.statusOccurredAt, "2026-08-19T00:00:00Z")
        XCTAssertEqual(event.assetId, "USDC")
        XCTAssertEqual(event.networkId, "ethereum")
        XCTAssertEqual(event.amount, "10")
        XCTAssertTrue(event.success)
    }

    /// `CONFIRMED` belongs here, not with success: the shared integrations flow shows
    /// its success screen only at `PROCESSED`. Auth on connect-ios is the one that
    /// also accepts `CONFIRMED`, because its own success rule is profile-gated.
    func testIsNotSuccessfulWhileNonTerminalOrFailed() {
        for value in ["PENDING", "CONFIRMED", "FAILED", "ACCOUNT_VALIDATION_FAILED"] {
            let event = FundDepositEvent(from: depositPayload(statusValue: value))
            XCTAssertFalse(event.success, "\(value) must not report success")
            XCTAssertEqual(event.status, value)
        }
    }

    /// The web flow checks account matching before the status, so a deposit still
    /// verifying shows the verifying screen even once the status reads `PROCESSED`.
    func testIsNotSuccessfulWhileAccountMatchingIsPending() {
        let event = FundDepositEvent(
            from: depositPayload(statusValue: "PROCESSED", validationStatus: "PENDING")
        )

        XCTAssertFalse(event.success)
    }

    /// `INVALID` and `ERROR` both send the web flow to the deposit-failed screen.
    func testIsNotSuccessfulWhenAccountMatchingRejects() {
        for validation in ["INVALID", "ERROR"] {
            let event = FundDepositEvent(
                from: depositPayload(statusValue: "PROCESSED", validationStatus: validation)
            )
            XCTAssertFalse(event.success, "\(validation) must not report success")
        }
    }

    /// `VALID` passes through, and so does any value we don't recognise — web falls
    /// through to the status check rather than treating it as a failure.
    func testIsSuccessfulWhenAccountMatchingDoesNotBlock() {
        for validation in ["VALID", "SKIPPED"] {
            let event = FundDepositEvent(
                from: depositPayload(statusValue: "PROCESSED", validationStatus: validation)
            )
            XCTAssertTrue(event.success, "\(validation) must not block success")
        }
    }

    func testKeepsTheAccountMatchingReason() {
        let event = FundDepositEvent(
            from: depositPayload(
                statusValue: "CONFIRMED",
                validationStatus: "INVALID",
                validationReason: "name mismatch"
            )
        )

        XCTAssertEqual(event.accountMatchingStatus, "INVALID")
        XCTAssertEqual(event.accountMatchingReason, "name mismatch")
    }

    func testToleratesAnAbsentValidationAndAnEmptyPayload() {
        let withoutValidation = FundDepositEvent(from: depositPayload(statusValue: "PROCESSED"))
        XCTAssertNil(withoutValidation.accountMatchingStatus)
        XCTAssertNil(withoutValidation.accountMatchingReason)

        let empty = FundDepositEvent(from: [:])
        XCTAssertNil(empty.depositId)
        XCTAssertNil(empty.status)
        XCTAssertNil(empty.statusDetails)
        XCTAssertFalse(empty.success)
    }

    func testKeepsTheRawPayloadForAnythingNotSurfaced() {
        var payload = depositPayload(statusValue: "PROCESSED")
        payload["somethingNew"] = "value"

        let event = FundDepositEvent(from: payload, jsonString: "{\"raw\":true}")

        XCTAssertEqual(event.data["somethingNew"] as? String, "value")
        XCTAssertEqual(event.jsonString, "{\"raw\":true}")
    }

    /// The status object is the discriminator between the two fund deposit paths, so
    /// a flat `status` string must not be mistaken for it.
    func testIgnoresAFlatStatusString() {
        let event = FundDepositEvent(from: ["depositId": "dep-1", "status": "PROCESSED"])

        XCTAssertNil(event.status)
        XCTAssertFalse(event.success)
    }

    // MARK: - FundEvent

    func testFundEventReadsTheFlatCompletionShape() {
        let event = FundEvent(from: [
            "depositAddress": "addr",
            "network": "ethereum",
            "assetSymbol": "USDC",
            "amount": "10",
            "transactionId": "tx-1",
            "fundId": "fund-1",
            "notionalAmount": "10.00",
        ])

        XCTAssertEqual(event.depositAddress, "addr")
        XCTAssertEqual(event.network, "ethereum")
        XCTAssertEqual(event.assetSymbol, "USDC")
        XCTAssertEqual(event.amount, "10")
        XCTAssertEqual(event.transactionId, "tx-1")
        XCTAssertEqual(event.fundId, "fund-1")
        XCTAssertEqual(event.notionalAmount, "10.00")
    }

    func testFundEventToleratesAnEmptyPayload() {
        let event = FundEvent(from: [:])

        XCTAssertNil(event.transactionId)
        XCTAssertNil(event.assetSymbol)
        XCTAssertTrue(event.data.isEmpty)
    }

    // MARK: - CryptoWithdrawalsEvent

    func testCryptoWithdrawalsEventKeepsTheStatusDetails() {
        let event = CryptoWithdrawalsEvent(from: [
            "withdrawalRequestId": "wr-1",
            "status": "FAILED",
            "statusDetails": "insufficient balance",
            "assetId": "btc",
            "networkId": "bitcoin",
            "amount": "0.5",
        ])

        XCTAssertEqual(event.withdrawalRequestId, "wr-1")
        XCTAssertEqual(event.status, "FAILED")
        XCTAssertEqual(event.statusDetails, "insufficient balance")
        XCTAssertEqual(event.assetId, "btc")
        XCTAssertEqual(event.networkId, "bitcoin")
        XCTAssertEqual(event.amount, "0.5")
    }
}
