@testable import Unmissable
import XCTest

final class EventAttachmentTests: XCTestCase {
    // MARK: - File Type Detection

    func testIsImage_trueForImageMimeTypes() {
        let png = makeAttachment(mimeType: "image/png")
        let jpeg = makeAttachment(mimeType: "image/jpeg")
        let svg = makeAttachment(mimeType: "image/svg+xml")

        XCTAssertTrue(png.isImage)
        XCTAssertTrue(jpeg.isImage)
        XCTAssertTrue(svg.isImage)
    }

    func testIsImage_falseForNonImageTypes() {
        let pdf = makeAttachment(mimeType: "application/pdf")
        let video = makeAttachment(mimeType: "video/mp4")

        XCTAssertFalse(pdf.isImage)
        XCTAssertFalse(video.isImage)
    }

    func testIsDocument_trueForDocumentTypes() {
        let pdf = makeAttachment(mimeType: "application/pdf")
        let text = makeAttachment(mimeType: "text/plain")
        let gDoc = makeAttachment(mimeType: "application/vnd.google-apps.document")
        let gSheet = makeAttachment(mimeType: "application/vnd.google-apps.spreadsheet")
        let gSlides = makeAttachment(mimeType: "application/vnd.google-apps.presentation")

        XCTAssertTrue(pdf.isDocument)
        XCTAssertTrue(text.isDocument)
        XCTAssertTrue(gDoc.isDocument)
        XCTAssertTrue(gSheet.isDocument)
        XCTAssertTrue(gSlides.isDocument)
    }

    func testIsDocument_falseForMediaTypes() {
        let video = makeAttachment(mimeType: "video/mp4")
        let image = makeAttachment(mimeType: "image/png")

        XCTAssertFalse(video.isDocument)
        XCTAssertFalse(image.isDocument)
    }

    // MARK: - Google Drive Detection

    func testIsGoogleDriveFile_detectsDriveURLs() {
        let drive = makeAttachment(fileUrl: "https://drive.google.com/file/d/abc/view")
        let docs = makeAttachment(fileUrl: "https://docs.google.com/document/d/xyz")
        let sheets = makeAttachment(fileUrl: "https://sheets.google.com/spreadsheets/d/abc")
        let slides = makeAttachment(fileUrl: "https://slides.google.com/presentation/d/abc")

        XCTAssertTrue(drive.isGoogleDriveFile)
        XCTAssertTrue(docs.isGoogleDriveFile)
        XCTAssertTrue(sheets.isGoogleDriveFile)
        XCTAssertTrue(slides.isGoogleDriveFile)
    }

    func testIsGoogleDriveFile_falseForOtherURLs() {
        let external = makeAttachment(fileUrl: "https://example.com/file.pdf")

        XCTAssertFalse(external.isGoogleDriveFile)
    }

    // MARK: - System Icon Name

    func testSystemIconName_mapsCorrectlyByMimeType() {
        XCTAssertEqual(makeAttachment(mimeType: "image/png").systemIconName, "photo")
        XCTAssertEqual(makeAttachment(mimeType: "application/pdf").systemIconName, "doc.richtext")
        XCTAssertEqual(
            makeAttachment(mimeType: "application/vnd.google-apps.spreadsheet").systemIconName,
            "tablecells"
        )
        XCTAssertEqual(
            makeAttachment(mimeType: "application/vnd.google-apps.presentation").systemIconName,
            "rectangle.on.rectangle"
        )
        XCTAssertEqual(
            makeAttachment(mimeType: "application/vnd.google-apps.document").systemIconName,
            "doc.text"
        )
        XCTAssertEqual(makeAttachment(mimeType: "video/mp4").systemIconName, "video")
        XCTAssertEqual(makeAttachment(mimeType: "audio/mpeg").systemIconName, "music.note")
        XCTAssertEqual(makeAttachment(mimeType: "text/csv").systemIconName, "doc.plaintext")
        XCTAssertEqual(makeAttachment(mimeType: "application/octet-stream").systemIconName, "doc")
    }

    // MARK: - File Size Formatting

    func testFileSizeString_formatsCorrectly() throws {
        let withSize = makeAttachment(fileSize: 2_548_736) // ~2.4 MB
        let sizeString = try XCTUnwrap(withSize.fileSizeString)
        // ByteCountFormatter produces locale-dependent output; verify it's non-empty
        // and corresponds to the megabyte range
        XCTAssertFalse(sizeString.isEmpty, "Size string should not be empty for a 2.4 MB file")
        XCTAssertEqual(withSize.fileSize, 2_548_736, "Raw file size should be preserved")

        let noSize = makeAttachment(fileSize: nil)
        XCTAssertNil(noSize.fileSizeString)
    }

    // MARK: - File Extension

    func testFileExtension_extractsFromTitle() {
        let pdf = EventAttachment(
            fileUrl: "https://example.com/file",
            title: "Report.pdf",
            mimeType: "application/pdf"
        )
        XCTAssertEqual(pdf.fileExtension, "pdf")
    }

    func testFileExtension_fallsBackToURL() {
        let noTitleExt = EventAttachment(
            fileUrl: "https://example.com/file.docx",
            title: "Document",
            mimeType: "application/msword"
        )
        XCTAssertEqual(noTitleExt.fileExtension, "docx")
    }

    func testFileExtension_nilWhenNoneAvailable() {
        let noExt = EventAttachment(
            fileUrl: "https://example.com/file",
            title: "Document",
            mimeType: "application/octet-stream"
        )
        XCTAssertNil(noExt.fileExtension)
    }

    // MARK: - Identity

    func testId_derivedFromFileUrl() {
        let attachment = makeAttachment(fileUrl: "https://example.com/unique-file")
        XCTAssertEqual(attachment.id, "https://example.com/unique-file")
    }

    // MARK: - Codable Round-Trip

    func testCodableRoundTrip_allFieldsPreserved() throws {
        let original = EventAttachment(
            fileUrl: "https://drive.google.com/file/d/abc",
            title: "Design Doc",
            mimeType: "application/pdf",
            iconLink: "https://drive.google.com/icon.png",
            fileId: "abc",
            fileSize: 1_048_576
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(EventAttachment.self, from: data)

        XCTAssertEqual(decoded.fileUrl, original.fileUrl)
        XCTAssertEqual(decoded.title, original.title)
        XCTAssertEqual(decoded.mimeType, original.mimeType)
        XCTAssertEqual(decoded.iconLink, original.iconLink)
        XCTAssertEqual(decoded.fileId, original.fileId)
        XCTAssertEqual(decoded.fileSize, original.fileSize)
    }

    func testCodableRoundTrip_nilOptionals() throws {
        let original = EventAttachment(
            fileUrl: "https://example.com/file",
            title: "Minimal",
            mimeType: "application/octet-stream"
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(EventAttachment.self, from: data)

        XCTAssertNil(decoded.iconLink)
        XCTAssertNil(decoded.fileId)
        XCTAssertNil(decoded.fileSize)
    }

    // MARK: - Helpers

    private func makeAttachment(
        fileUrl: String = "https://example.com/file",
        mimeType: String = "application/octet-stream",
        fileSize: Int64? = nil
    ) -> EventAttachment {
        EventAttachment(
            fileUrl: fileUrl,
            title: "Test File",
            mimeType: mimeType,
            fileSize: fileSize
        )
    }
}
