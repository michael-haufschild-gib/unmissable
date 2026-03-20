@testable import Unmissable
import XCTest

final class EventAttachmentTests: XCTestCase {
    func testFromGoogleCalendarData_parsesOptionalMetadataFields() throws {
        let input: [String: Any] = [
            "fileUrl": "https://drive.google.com/file/d/abc123/view",
            "title": "Quarterly Plan.pdf",
            "mimeType": "application/pdf",
            "iconLink": "https://example.com/icon.png",
            "fileId": "abc123",
            "fileSize": "2548736",
            "lastModified": "2026-07-15T10:30:45Z",
        ]

        let attachment = try XCTUnwrap(EventAttachment.from(googleCalendarData: input))

        XCTAssertEqual(attachment.fileSize, 2_548_736)
        XCTAssertEqual(attachment.fileId, "abc123")
        XCTAssertEqual(attachment.iconLink, "https://example.com/icon.png")

        let expectedDate = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-07-15T10:30:45Z"))
        XCTAssertEqual(attachment.lastModified, expectedDate)
    }

    func testFromGoogleCalendarData_acceptsNumericFileSize() throws {
        let input: [String: Any] = [
            "fileUrl": "https://drive.google.com/file/d/abc123/view",
            "title": "Budget.xlsx",
            "mimeType": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
            "fileSize": Int64(1024),
        ]

        let attachment = try XCTUnwrap(EventAttachment.from(googleCalendarData: input))
        XCTAssertEqual(attachment.fileSize, 1024)
    }
}
