import AppKit
import OSLog
import SwiftUI

private let attachmentsLogger = Logger(category: "AttachmentsView")

/// A SwiftUI view that displays event attachments with links to open them
struct AttachmentsView: View {
    let attachments: [EventAttachment]
    @Environment(\.design)
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
    let attachment: EventAttachment
    @Environment(\.design)
    private var design
    @State
    private var isHovered = false

    private static let iconSize: CGFloat = 16
    private static let nameLineLimit = 2
    private static let hoverVisibleOpacity: Double = 1.0
    private static let hoverHiddenOpacity: Double = 0.6
    private static let borderLineWidth: CGFloat = 1
    private static let hoverAnimationDuration: Double = 0.2
    private static let accentBackgroundOpacity: Double = 0.1

    var body: some View {
        Button(action: openAttachment) {
            HStack(spacing: design.spacing.sm) {
                Image(systemName: attachment.systemIconName)
                    .foregroundColor(iconColor)
                    .frame(width: Self.iconSize, height: Self.iconSize)

                VStack(alignment: .leading, spacing: design.spacing.xs) {
                    Text(attachment.title)
                        .font(design.fonts.callout)
                        .foregroundColor(design.colors.textPrimary)
                        .lineLimit(Self.nameLineLimit)
                        .multilineTextAlignment(.leading)

                    HStack(spacing: design.spacing.xs) {
                        if let fileSize = attachment.fileSizeString {
                            Text(fileSize)
                                .font(design.fonts.caption)
                                .foregroundColor(design.colors.textSecondary)
                        }

                        if attachment.isGoogleDriveFile {
                            Text("Google Drive")
                                .font(design.fonts.caption)
                                .foregroundColor(design.colors.textSecondary)
                        }

                        Spacer()

                        Image(systemName: "arrow.up.right.square")
                            .font(design.fonts.caption)
                            .foregroundColor(design.colors.textSecondary)
                            .opacity(isHovered ? Self.hoverVisibleOpacity : Self.hoverHiddenOpacity)
                    }
                }

                Spacer()
            }
            .padding(.horizontal, design.spacing.sm)
            .padding(.vertical, design.spacing.sm)
            .background(backgroundColor)
            .cornerRadius(design.corners.md)
            .overlay(
                RoundedRectangle(cornerRadius: design.corners.md)
                    .stroke(borderColor, lineWidth: Self.borderLineWidth),
            )
        }
        .buttonStyle(UMButtonStyle(.ghost, size: .sm))
        .onHover { hovering in
            withAnimation(.easeInOut(duration: Self.hoverAnimationDuration)) {
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
            design.colors.accentHover
        } else {
            design.colors.textTertiary
        }
    }

    private var backgroundColor: Color {
        isHovered ? design.colors.surface : Color.clear
    }

    private var borderColor: Color {
        isHovered ? design.colors.borderDefault : design.colors.borderSubtle
    }

    // MARK: - Actions

    /// Schemes safe to open from calendar attachment links.
    private static let allowedSchemes: Set<String> = ["https", "http"]

    private func openAttachment() {
        guard let url = URL(string: attachment.fileUrl) else {
            attachmentsLogger.error("AttachmentRow: Invalid URL for attachment")
            return
        }

        guard let scheme = url.scheme?.lowercased(),
              Self.allowedSchemes.contains(scheme)
        else {
            attachmentsLogger.warning("AttachmentRow: Blocked attachment with disallowed scheme")
            return
        }

        attachmentsLogger.info("AttachmentRow: Opening attachment (id: \(attachment.fileId ?? "unknown"))")

        NSWorkspace.shared.open(url)
    }
}

// MARK: - Preview

#if DEBUG
    private enum AttachmentsPreviewConstants {
        static let pdfFileSize: Int64 = 2_548_736
        static let spreadsheetFileSize: Int64 = 1_024_000
        static let previewWidth: CGFloat = 400
    }

    struct AttachmentsView_Previews: PreviewProvider {
        static var previews: some View {
            let sampleAttachments = [
                EventAttachment(
                    fileUrl: "https://drive.google.com/file/d/abc123/view",
                    title: "Project Requirements.pdf",
                    mimeType: "application/pdf",
                    iconLink: "https://drive-thirdparty.googleusercontent.com/16/type/application/pdf",
                    fileId: "abc123",
                    fileSize: AttachmentsPreviewConstants.pdfFileSize,
                ),
                EventAttachment(
                    fileUrl: "https://docs.google.com/document/d/def456/edit",
                    title: "Meeting Notes",
                    mimeType: "application/vnd.google-apps.document",
                    iconLink:
                    "https://drive-thirdparty.googleusercontent.com/16/type/application/vnd.google-apps.document",
                    fileId: "def456",
                ),
                EventAttachment(
                    fileUrl: "https://sheets.google.com/spreadsheets/d/ghi789/edit",
                    title: "Budget Spreadsheet - Q3 2024 Financial Planning.xlsx",
                    mimeType: "application/vnd.google-apps.spreadsheet",
                    iconLink:
                    "https://drive-thirdparty.googleusercontent.com/16/type/application/vnd.google-apps.spreadsheet",
                    fileId: "ghi789",
                    fileSize: AttachmentsPreviewConstants.spreadsheetFileSize,
                ),
            ]

            AttachmentsView(attachments: sampleAttachments)
                .padding()
                .frame(width: AttachmentsPreviewConstants.previewWidth)
                .themed(themeManager: ThemeManager())
        }
    }
#endif
