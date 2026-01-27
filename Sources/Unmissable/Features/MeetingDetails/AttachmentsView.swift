import AppKit
import OSLog
import SwiftUI

/// A SwiftUI view that displays event attachments with links to open them
struct AttachmentsView: View {
    private let logger = Logger(subsystem: "com.unmissable.app", category: "AttachmentsView")

    let attachments: [EventAttachment]

    var body: some View {
        if !attachments.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "paperclip")
                        .foregroundColor(.secondary)
                    Text("Attachments")
                        .font(.headline)
                        .foregroundColor(.primary)
                }

                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(attachments) { attachment in
                        AttachmentRow(attachment: attachment)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }
}

/// Individual attachment row component
struct AttachmentRow: View {
    private let logger = Logger(subsystem: "com.unmissable.app", category: "AttachmentRow")

    let attachment: EventAttachment
    @State private var isHovered = false

    var body: some View {
        Button(action: openAttachment) {
            HStack(spacing: 8) {
                // File type icon
                Image(systemName: attachment.systemIconName)
                    .foregroundColor(iconColor)
                    .frame(width: 16, height: 16)

                VStack(alignment: .leading, spacing: 2) {
                    // File name
                    Text(attachment.title)
                        .font(.body)
                        .foregroundColor(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    // File details
                    HStack(spacing: 4) {
                        if let fileSize = attachment.fileSizeString {
                            Text(fileSize)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }

                        if attachment.isGoogleDriveFile {
                            Text("•")
                                .font(.caption2)
                                .foregroundColor(.secondary)

                            Text("Google Drive")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Image(systemName: "arrow.up.right.square")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .opacity(isHovered ? 1.0 : 0.6)
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(backgroundColor)
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(borderColor, lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
        .help("Open \(attachment.title)")
    }

    // MARK: - Computed Properties

    private var iconColor: Color {
        if attachment.isImage {
            .green
        } else if attachment.isDocument {
            .blue
        } else if attachment.mimeType.hasPrefix("video/") {
            .purple
        } else if attachment.mimeType.hasPrefix("audio/") {
            .orange
        } else {
            .gray
        }
    }

    private var backgroundColor: Color {
        if isHovered {
            Color.gray.opacity(0.1)
        } else {
            Color.clear
        }
    }

    private var borderColor: Color {
        if isHovered {
            Color.gray.opacity(0.3)
        } else {
            Color.gray.opacity(0.15)
        }
    }

    // MARK: - Actions

    private func openAttachment() {
        guard let url = URL(string: attachment.fileUrl) else {
            logger.error("❌ AttachmentRow: Invalid URL for attachment - \(attachment.fileUrl)")
            return
        }

        logger.info(
            "🔗 AttachmentRow: Opening attachment - \(attachment.title) at \(url.absoluteString)"
        )

        // Open the URL in the default browser/app
        NSWorkspace.shared.open(url)
    }
}

// MARK: - Preview

#if DEBUG
    struct AttachmentsView_Previews: PreviewProvider {
        static var previews: some View {
            let sampleAttachments = [
                EventAttachment(
                    fileUrl: "https://drive.google.com/file/d/abc123/view",
                    title: "Project Requirements.pdf",
                    mimeType: "application/pdf",
                    iconLink: "https://drive-thirdparty.googleusercontent.com/16/type/application/pdf",
                    fileId: "abc123",
                    fileSize: 2_548_736
                ),
                EventAttachment(
                    fileUrl: "https://docs.google.com/document/d/def456/edit",
                    title: "Meeting Notes",
                    mimeType: "application/vnd.google-apps.document",
                    iconLink:
                    "https://drive-thirdparty.googleusercontent.com/16/type/application/vnd.google-apps.document",
                    fileId: "def456"
                ),
                EventAttachment(
                    fileUrl: "https://sheets.google.com/spreadsheets/d/ghi789/edit",
                    title: "Budget Spreadsheet - Q3 2024 Financial Planning.xlsx",
                    mimeType: "application/vnd.google-apps.spreadsheet",
                    iconLink:
                    "https://drive-thirdparty.googleusercontent.com/16/type/application/vnd.google-apps.spreadsheet",
                    fileId: "ghi789",
                    fileSize: 1_024_000
                ),
            ]

            VStack(spacing: 20) {
                // With attachments
                AttachmentsView(attachments: sampleAttachments)
                    .padding()
                    .background(Color.gray.opacity(0.05))
                    .cornerRadius(8)

                // Empty state
                AttachmentsView(attachments: [])
                    .padding()
                    .background(Color.gray.opacity(0.05))
                    .cornerRadius(8)

                Text("Empty attachments view should show nothing")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .frame(width: 400)
            .customThemedEnvironment()
        }
    }
#endif
