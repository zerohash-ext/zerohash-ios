import XCTest

@testable import ZerohashSDK

/// The rows go out as JSON, and the contract types every optional as `T | null`
/// rather than as an optional key (`docs/contracts/types.md`). The synthesized
/// `Codable` conformance uses `encodeIfPresent`, which drops a nil key entirely,
/// so rows were leaving with `totalStakedPercent` missing instead of null.
///
/// A round-trip test cannot catch this — decoding accepts both shapes, so it
/// stays green either way. The wire shape has to be asserted directly.
final class AssetBalanceEncodingTests: XCTestCase {

    private func encodedObject(_ row: AssetBalance) throws -> [String: Any] {
        let data = try JSONEncoder().encode(row)
        let object = try JSONSerialization.jsonObject(with: data)
        return try XCTUnwrap(object as? [String: Any])
    }

    /// A row with every optional absent — e.g. BTC, which cannot be staked.
    private var rowWithNoOptionals: AssetBalance {
        AssetBalance(
            key: "BTC",
            label: "Bitcoin",
            amount: "0.5321",
            notional: "34120.55",
            currency: nil,
            totalStakedPercent: nil,
            precision: nil,
            extractedAt: "2026-07-27T18:04:11.000Z"
        )
    }

    func testANilStakedPercentIsEncodedAsNullRatherThanOmitted() throws {
        let json = try encodedObject(rowWithNoOptionals)

        XCTAssertTrue(
            json.keys.contains("totalStakedPercent"),
            "the key must survive: JS sees a dropped key as undefined, not null"
        )
        XCTAssertTrue(json["totalStakedPercent"] is NSNull)
    }

    func testTheOtherNilOptionalsAreAlsoEncodedAsNull() throws {
        let json = try encodedObject(rowWithNoOptionals)

        XCTAssertTrue(json.keys.contains("currency"))
        XCTAssertTrue(json["currency"] is NSNull)
        XCTAssertTrue(json.keys.contains("precision"))
        XCTAssertTrue(json["precision"] is NSNull)
    }

    func testEveryContractFieldIsPresentExactlyOnce() throws {
        let json = try encodedObject(rowWithNoOptionals)

        XCTAssertEqual(
            Set(json.keys),
            [
                "key", "label", "amount", "notional", "currency", "totalStakedPercent",
                "precision", "extractedAt",
            ]
        )
    }

    func testPresentValuesStillEncodeAsThemselves() throws {
        let json = try encodedObject(
            AssetBalance(
                key: "ETH",
                label: "Ethereum",
                amount: "10",
                notional: "25000",
                currency: "USD",
                totalStakedPercent: "50",
                precision: 8,
                extractedAt: "2026-07-27T18:04:11.000Z"
            )
        )

        XCTAssertEqual(json["key"] as? String, "ETH")
        XCTAssertEqual(json["currency"] as? String, "USD")
        XCTAssertEqual(json["totalStakedPercent"] as? String, "50")
        XCTAssertEqual(json["precision"] as? Int, 8)
    }

    /// Decoding has to keep accepting both an explicit null and a missing key, or
    /// a stored/replayed row from an older build stops round-tripping.
    func testDecodingAcceptsBothAnExplicitNullAndAMissingKey() throws {
        let explicitNull = """
            {"key":"BTC","label":"Bitcoin","amount":"1","notional":"2",
             "currency":null,"totalStakedPercent":null,"precision":null,
             "extractedAt":"2026-07-27T18:04:11.000Z"}
            """
        let missingKeys = """
            {"key":"BTC","label":"Bitcoin","amount":"1","notional":"2",
             "extractedAt":"2026-07-27T18:04:11.000Z"}
            """

        for payload in [explicitNull, missingKeys] {
            let row = try JSONDecoder().decode(
                AssetBalance.self, from: Data(payload.utf8))
            XCTAssertNil(row.totalStakedPercent)
            XCTAssertNil(row.currency)
            XCTAssertNil(row.precision)
        }
    }
}
