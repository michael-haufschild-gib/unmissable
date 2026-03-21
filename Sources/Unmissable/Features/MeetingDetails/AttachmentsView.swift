import AppKit
import OSLog
import SwiftUI

/// A SwiftUI view that displays event attachments with links to open them
struct AttachmentsView: View {
    private let logger = Logger(subsystem: "com.unmissable.app", category: "AttachmentsView")

    let attachments: [EventAttachment]
    @Environment(\.customDesign)
    private var design

    var body: some View {
        if !attachments.isEmpty {
            VStack(alignment: .leading, spacing: design.spacing.sm) {
                HStack {
                    Image(systemName: "paperclip")
                        .foregroundColor(design.colors.textSecondary)
                    Text("Attachments")
                        .font(design.fonts.headline)
                        .foregroundColor(design.colors.textPrimary)
                }

                LazyVStack(alignment: .leading, spacing: design.spacing.sm) {
                    ForEach(attachments) { attachment in
                        AttachmentRow(attachment: attachment)
                    }
                }
            }
            .padding(.vertical, design.spacing.xs)
        }
    }
}

/// Individual attachment row component
struct AttachmentRow: View {
    private let logger = Logger(subsystem: "com.unmissable.app", category: "AttachmentRow")

    let attachment: EventAttachment
    @Environment(\.customDesign)
    private var design
    @State
    private var isHovered = false

    var body: some View {
        Button(action: openAttachment) {
            HStack(spacing: design.spacing.sm) {
                Image(systemName: attachment.systemIconName)
                    .foregroundColor(iconColor)
                    .frame(width: 16, height: 16)

                VStack(alignment: .leading, spacing: 2) {
                    Text(attachment.title)
                        .font(design.fonts.callout)
                        .foregroundColor(design.colors.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    HStack(spacing: design.spacing.xs) {
                        if let fileSize = attachment.fileSizeString {
                            Text(fileSize)
                                .font(design.fonts.caption2)
                                .foregroundColor(design.colors.textSecondary)
                        }

                        if attachment.isGoogleDriveFile {
                            Text("Google Drive")
                                .font(design.fonts.caption2)
                                .foregroundColor(design.colors.textSecondary)
                        }

                        Spacer()

                        Image(systemName: "arrow.up.right.square")
                            .font(design.fonts.caption1)
                            .foregroundColor(design.colors.textSecondary)
                            .opacity(isHovered ? 1.0 : 0.6)
                    }
                }

                Spacer()
            }
            .padding(.horizontal, design.spacing.sm)
            .padding(.vertical, design.spacing.sm)
            .background(backgroundColor)
            .cornerRadius(design.corners.medium)
            .overlay(
                RoundedRectangle(cornerRadius: design.corners.medium)
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
            design.colors.success
        } else if attachment.isDocument {
            design.colors.accent
        } else if attachment.mimeType.hasPrefix("video/") {
            design.colors.warning
        } else if attachment.mimeType.hasPrefix("audio/") {
            design.colors.accentSecondary
        } else {
            design.colors.textTertiary
        }
    }

    private var backgroundColor: Color {
        isHovered ? design.colors.backgroundSecondary : Color.clear
    }

    private var borderColor: Color {
        isHovered ? design.colors.border : design.colors.borderSecondary
    }

    // MARK: - Actions

    private func openAttachment() {
        guard let url = URL(string: attachment.fileUrl) else {
            logger.error("AttachmentRow: Invalid URL for attachment - \(attachment.fileUrl)")
            return
        }

        logger.info(
            "AttachmentRow: Opening attachment - \(attachment.title) at \(url.absoluteString)"
        )

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

            AttachmentsView(attachments: sampleAttachments)
                .padding()
                .frame(width: 400)
                .customThemedEnvironment()
        }
    }
#endif
