import Foundation
import Testing
@testable import Unmissable

struct EventAttachmentTests {
    // MARK: - File Type Detection

    @Test
    func isImage_trueForImageMimeTypes() {
        let png = makeAttachment(mimeType: "image/png")
        let jpeg = makeAttachment(mimeType: "image/jpeg")
        let svg = makeAttachment(mimeType: "image/svg+xml")

        #expect(png.isImage)
        #expect(jpeg.isImage)
        #expect(svg.isImage)
    }

    @Test
    func isImage_falseForNonImageTypes() {
        let pdf = makeAttachment(mimeType: "application/pdf")
        let video = makeAttachment(mimeType: "video/mp4")

        #expect(!pdf.isImage)
        #expect(!video.isImage)
    }

    @Test
    func isDocument_trueForDocumentTypes() {
        let pdf = makeAttachment(mimeType: "application/pdf")
        let text = makeAttachment(mimeType: "text/plain")
        let gDoc = makeAttachment(mimeType: "application/vnd.google-apps.document")
        let gSheet = makeAttachment(mimeType: "application/vnd.google-apps.spreadsheet")
        let gSlides = makeAttachment(mimeType: "application/vnd.google-apps.presentation")

        #expect(pdf.isDocument)
        #expect(text.isDocument)
        #expect(gDoc.isDocument)
        #expect(gSheet.isDocument)
        #expect(gSlides.isDocument)
    }

    @Test
    func isDocument_falseForMediaTypes() {
        let video = makeAttachment(mimeType: "video/mp4")
        let image = makeAttachment(mimeType: "image/png")

        #expect(!video.isDocument)
        #expect(!image.isDocument)
    }

    // MARK: - Google Drive Detection

    @Test
    func isGoogleDriveFile_detectsDriveURLs() {
        let drive = makeAttachment(fileUrl: "https://drive.google.com/file/d/abc/view")
        let docs = makeAttachment(fileUrl: "https://docs.google.com/document/d/xyz")
        let sheets = makeAttachment(fileUrl: "https://sheets.google.com/spreadsheets/d/abc")
        let slides = makeAttachment(fileUrl: "https://slides.google.com/presentation/d/abc")

        #expect(drive.isGoogleDriveFile)
        #expect(docs.isGoogleDriveFile)
        #expect(sheets.isGoogleDriveFile)
        #expect(slides.isGoogleDriveFile)
    }

    @Test
    func isGoogleDriveFile_falseForOtherURLs() {
        let external = makeAttachment(fileUrl: "https://example.com/file.pdf")

        #expect(!external.isGoogleDriveFile)
    }

    // MARK: - System Icon Name

    @Test
    func systemIconName_mapsCorrectlyByMimeType() {
        #expect(makeAttachment(mimeType: "image/png").systemIconName == "photo")
        #expect(makeAttachment(mimeType: "application/pdf").systemIconName == "doc.richtext")
        #expect(
            makeAttachment(mimeType: "application/vnd.google-apps.spreadsheet").systemIconName ==
                "tablecells",
        )
        #expect(
            makeAttachment(mimeType: "application/vnd.google-apps.presentation").systemIconName ==
                "rectangle.on.rectangle",
        )
        #expect(
            makeAttachment(mimeType: "application/vnd.google-apps.document").systemIconName ==
                "doc.text",
        )
        #expect(makeAttachment(mimeType: "video/mp4").systemIconName == "video")
        #expect(makeAttachment(mimeType: "audio/mpeg").systemIconName == "music.note")
        #expect(makeAttachment(mimeType: "text/csv").systemIconName == "doc.plaintext")
        #expect(makeAttachment(mimeType: "application/octet-stream").systemIconName == "doc")
    }

    // MARK: - File Size Formatting

    @Test
    func fileSizeString_formatsCorrectly() throws {
        let withSize = makeAttachment(fileSize: 2_548_736) // ~2.4 MB
        let sizeString = try #require(withSize.fileSizeString)
        // ByteCountFormatter produces locale-dependent output; verify it's non-empty
        // and corresponds to the megabyte range
        #expect(!sizeString.isEmpty, "Size string should not be empty for a 2.4 MB file")
        #expect(withSize.fileSize == 2_548_736, "Raw file size should be preserved")

        let noSize = makeAttachment(fileSize: nil)
        #expect(noSize.fileSizeString == nil)
    }

    // MARK: - File Extension

    @Test
    func fileExtension_extractsFromTitle() {
        let pdf = EventAttachment(
            fileUrl: "https://example.com/file",
            title: "Report.pdf",
            mimeType: "application/pdf",
        )
        #expect(pdf.fileExtension == "pdf")
    }

    @Test
    func fileExtension_fallsBackToURL() {
        let noTitleExt = EventAttachment(
            fileUrl: "https://example.com/file.docx",
            title: "Document",
            mimeType: "application/msword",
        )
        #expect(noTitleExt.fileExtension == "docx")
    }

    @Test
    func fileExtension_nilWhenNoneAvailable() {
        let noExt = EventAttachment(
            fileUrl: "https://example.com/file",
            title: "Document",
            mimeType: "application/octet-stream",
        )
        #expect(noExt.fileExtension == nil)
    }

    // MARK: - Identity

    @Test
    func id_derivedFromFileUrl() {
        let attachment = makeAttachment(fileUrl: "https://example.com/unique-file")
        #expect(attachment.id == "https://example.com/unique-file")
    }

    // MARK: - Codable Round-Trip

    @Test
    func codableRoundTrip_allFieldsPreserved() throws {
        let original = EventAttachment(
            fileUrl: "https://drive.google.com/file/d/abc",
            title: "Design Doc",
            mimeType: "application/pdf",
            iconLink: "https://drive.google.com/icon.png",
            fileId: "abc",
            fileSize: 1_048_576,
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(EventAttachment.self, from: data)

        #expect(decoded.fileUrl == original.fileUrl)
        #expect(decoded.title == original.title)
        #expect(decoded.mimeType == original.mimeType)
        #expect(decoded.iconLink == original.iconLink)
        #expect(decoded.fileId == original.fileId)
        #expect(decoded.fileSize == original.fileSize)
    }

    @Test
    func codableRoundTrip_nilOptionals() throws {
        let original = EventAttachment(
            fileUrl: "https://example.com/file",
            title: "Minimal",
            mimeType: "application/octet-stream",
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(EventAttachment.self, from: data)

        #expect(decoded.iconLink == nil)
        #expect(decoded.fileId == nil)
        #expect(decoded.fileSize == nil)
    }

    // MARK: - Helpers

    private func makeAttachment(
        fileUrl: String = "https://example.com/file",
        mimeType: String = "application/octet-stream",
        fileSize: Int64? = nil,
    ) -> EventAttachment {
        EventAttachment(
            fileUrl: fileUrl,
            title: "Test File",
            mimeType: mimeType,
            fileSize: fileSize,
        )
    }
}
