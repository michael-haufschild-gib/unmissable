import Foundation
import Testing
@testable import Unmissable

struct DisplayIdentifierTests {
    @Test
    func persistenceKey_combinesVendorModelSerial() {
        let id = DisplayIdentifier(
            vendor: 1715,
            model: 10_092,
            serial: 16_843_009,
            localizedName: "PA278CV (2)",
        )
        #expect(id.persistenceKey == "1715-10092-16843009")
    }

    @Test
    func equality_matchesOnHardwareFingerprintOnly() {
        let id1 = DisplayIdentifier(
            vendor: 1715,
            model: 10_092,
            serial: 16_843_009,
            isBuiltIn: false,
            localizedName: "PA278CV (2)",
        )
        let id2 = DisplayIdentifier(
            vendor: 1715,
            model: 10_092,
            serial: 16_843_009,
            isBuiltIn: true,
            localizedName: "Completely Different Name",
        )
        #expect(id1 == id2, "Equality should ignore localizedName and isBuiltIn")
    }

    @Test
    func equality_differentSerials_notEqual() {
        let id1 = DisplayIdentifier(vendor: 1715, model: 10_092, serial: 16_843_009)
        let id2 = DisplayIdentifier(vendor: 1715, model: 10_092, serial: 16_843_043)
        #expect(id1 != id2, "Different serials should produce different identifiers")
    }

    @Test
    func hashValue_sameForEqualIdentifiers() {
        let id1 = DisplayIdentifier(
            vendor: 1715,
            model: 10_092,
            serial: 100,
            localizedName: "A",
        )
        let id2 = DisplayIdentifier(
            vendor: 1715,
            model: 10_092,
            serial: 100,
            localizedName: "B",
        )
        #expect(id1.hashValue == id2.hashValue, "Equal identifiers must have equal hashes")
    }

    @Test
    func setContainment_identicalHardwareCollapsesToOneEntry() {
        let id1 = DisplayIdentifier(vendor: 1, model: 2, serial: 3, localizedName: "A")
        let id2 = DisplayIdentifier(vendor: 1, model: 2, serial: 3, localizedName: "B")
        let set: Set<DisplayIdentifier> = [id1, id2]
        #expect(set.count == 1, "Identical hardware fingerprints should collapse in a Set")
    }

    @Test
    func description_returnsLocalizedName() {
        let id = DisplayIdentifier(vendor: 0, model: 0, serial: 0, localizedName: "Built-in Retina Display")
        #expect(id.description == "Built-in Retina Display")
    }
}
