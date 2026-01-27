import Foundation

/// Represents a file attachment associated with a calendar event
/// Typically used for Google Drive files attached to Google Calendar events
struct EventAttachment: Codable, Equatable, Identifiable, Sendable {
  let id = UUID()

  /// URL to the attachment file (e.g., Google Drive alternateLink)
  let fileUrl: String

  /// Display name/title of the file
  let title: String

  /// MIME type of the file (e.g., "application/pdf", "image/jpeg")
  let mimeType: String

  /// Optional URL to an icon representing the file type
  let iconLink: String?

  /// Optional file ID for direct API access (e.g., Google Drive file ID)
  let fileId: String?

  /// File size in bytes, if available
  let fileSize: Int64?

  /// Last modified date, if available
  let lastModified: Date?

  init(
    fileUrl: String,
    title: String,
    mimeType: String,
    iconLink: String? = nil,
    fileId: String? = nil,
    fileSize: Int64? = nil,
    lastModified: Date? = nil
  ) {
    self.fileUrl = fileUrl
    self.title = title
    self.mimeType = mimeType
    self.iconLink = iconLink
    self.fileId = fileId
    self.fileSize = fileSize
    self.lastModified = lastModified
  }

  // MARK: - Computed Properties

  /// Human-readable file size string
  var fileSizeString: String? {
    guard let fileSize = fileSize else { return nil }
    return ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
  }

  /// File extension from the title or URL
  var fileExtension: String? {
    let titleExtension = (title as NSString).pathExtension
    if !titleExtension.isEmpty {
      return titleExtension.lowercased()
    }

    let urlExtension = (fileUrl as NSString).pathExtension
    if !urlExtension.isEmpty {
      return urlExtension.lowercased()
    }

    return nil
  }

  /// Determines if this is a Google Drive file
  var isGoogleDriveFile: Bool {
    return fileUrl.contains("drive.google.com") || fileUrl.contains("docs.google.com")
      || fileUrl.contains("sheets.google.com") || fileUrl.contains("slides.google.com")
  }

  /// Determines if this is an image file based on MIME type
  var isImage: Bool {
    return mimeType.hasPrefix("image/")
  }

  /// Determines if this is a document file
  var isDocument: Bool {
    return mimeType.hasPrefix("application/") || mimeType.hasPrefix("text/")
      || mimeType == "application/vnd.google-apps.document"
      || mimeType == "application/vnd.google-apps.spreadsheet"
      || mimeType == "application/vnd.google-apps.presentation"
  }

  /// System icon name based on file type
  var systemIconName: String {
    if isImage {
      return "photo"
    } else if mimeType.hasPrefix("application/pdf") {
      return "doc.richtext"
    } else if mimeType.contains("spreadsheet") || mimeType.contains("excel") {
      return "tablecells"
    } else if mimeType.contains("presentation") || mimeType.contains("powerpoint") {
      return "rectangle.on.rectangle"
    } else if mimeType.contains("document") || mimeType.contains("word") {
      return "doc.text"
    } else if mimeType.hasPrefix("video/") {
      return "video"
    } else if mimeType.hasPrefix("audio/") {
      return "music.note"
    } else if mimeType.hasPrefix("text/") {
      return "doc.plaintext"
    } else {
      return "doc"
    }
  }

  // MARK: - Codable Implementation

  private enum CodingKeys: String, CodingKey {
    case fileUrl
    case title
    case mimeType
    case iconLink
    case fileId
    case fileSize
    case lastModified
  }

  // MARK: - Equatable Implementation

  static func == (lhs: EventAttachment, rhs: EventAttachment) -> Bool {
    return lhs.fileUrl == rhs.fileUrl && lhs.title == rhs.title && lhs.mimeType == rhs.mimeType
      && lhs.iconLink == rhs.iconLink && lhs.fileId == rhs.fileId
  }
}

// MARK: - Factory Methods

extension EventAttachment {
  /// Creates an EventAttachment from Google Calendar API response data
  static func from(googleCalendarData: [String: Any]) -> EventAttachment? {
    guard let fileUrl = googleCalendarData["fileUrl"] as? String,
      let title = googleCalendarData["title"] as? String,
      let mimeType = googleCalendarData["mimeType"] as? String
    else {
      return nil
    }

    let iconLink = googleCalendarData["iconLink"] as? String
    let fileId = googleCalendarData["fileId"] as? String

    return EventAttachment(
      fileUrl: fileUrl,
      title: title,
      mimeType: mimeType,
      iconLink: iconLink,
      fileId: fileId
    )
  }
}

// MARK: - Debug Description

extension EventAttachment: CustomStringConvertible {
  var description: String {
    return "EventAttachment(title: \(title), mimeType: \(mimeType), fileUrl: \(fileUrl))"
  }
}
