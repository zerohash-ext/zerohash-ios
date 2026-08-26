import XCTest
@testable import ZerohashSDK

final class WithdrawFundsNotAvailableTests: XCTestCase {

    private func encodedObject<T: Encodable>(_ value: T) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    func testOmitsAvailabilityWhenUncaptured() throws {
        let state = WithdrawState.rejected(
            reason: WithdrawRejectReason.fundsNotAvailable, pendingTransfer: nil)
        let obj = try encodedObject(state)
        XCTAssertEqual(obj["state"] as? String, "rejected")
        XCTAssertEqual(obj["reason"] as? String, "funds_not_available")
        XCTAssertFalse(obj.keys.contains("fundsAvailability"))
        XCTAssertFalse(obj.keys.contains("pendingTransfer"))
    }

    func testAvailabilityRoundTripsWhenPresent() throws {
        let state = WithdrawState.rejected(
            reason: WithdrawRejectReason.fundsNotAvailable,
            pendingTransfer: nil,
            fundsAvailability: FundsAvailability(
                asset: "USDC", availableToSend: "0", availableToSendFiat: "0"))
        let obj = try encodedObject(state)
        let availability = try XCTUnwrap(obj["fundsAvailability"] as? [String: Any])
        XCTAssertEqual(availability["asset"] as? String, "USDC")
        XCTAssertEqual(availability["availableToSend"] as? String, "0")

        let data = try JSONEncoder().encode(state)
        XCTAssertEqual(try JSONDecoder().decode(WithdrawState.self, from: data), state)
    }

    func testDecodesFromTheWire() throws {
        let state = try decode(WithdrawState.self, """
        {
          "state": "rejected",
          "reason": "funds_not_available",
          "fundsAvailability": {
            "asset": "ETH",
            "availableToSend": "0.01035350998522571",
            "availableToSendFiat": null
          }
        }
        """)
        guard case .rejected(let reason, let pending, let availability) = state else {
            return XCTFail("expected a rejected state, got \(state)")
        }
        XCTAssertEqual(reason, WithdrawRejectReason.fundsNotAvailable)
        XCTAssertNil(pending)
        XCTAssertEqual(availability?.asset, "ETH")
        XCTAssertEqual(availability?.availableToSend, "0.01035350998522571")
        XCTAssertNil(availability?.availableToSendFiat)
    }

    func testMapsFromTheJSBoundary() throws {
        let state = try Coinbase.mapWithdrawState([
            "state": "rejected", "reason": "funds_not_available",
        ])
        XCTAssertEqual(
            state,
            .rejected(reason: WithdrawRejectReason.fundsNotAvailable, pendingTransfer: nil))
    }

    func testIsTerminal() {
        XCTAssertTrue(
            WithdrawState.rejected(
                reason: WithdrawRejectReason.fundsNotAvailable,
                pendingTransfer: nil).endsSession)
        XCTAssertFalse(
            WithdrawState.rejected(
                reason: WithdrawRejectReason.otpRejected, pendingTransfer: nil).endsSession)
    }
}
