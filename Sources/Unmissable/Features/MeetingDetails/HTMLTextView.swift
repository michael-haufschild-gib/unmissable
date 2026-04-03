import AppKit
import OSLog
import SwiftUI

private let htmlTextViewLogger = Logger(category: "HTMLTextView")

/// A SwiftUI view that renders HTML content using NSAttributedString and NSTextView
/// Supports rich text formatting, clickable links, and custom theming
struct HTMLTextView: NSViewRepresentable {
    let htmlContent: String?
    let resolvedTheme: ResolvedTheme
    let onLinkTap: ((URL) -> Void)?

    private static let defaultFontSize: CGFloat = 13
    private static let textContainerInsetWidth: CGFloat = 8
    private static let textContainerInsetHeight: CGFloat = 8
    private static let minimumHeight: CGFloat = 20

    init(
        htmlContent: String?,
        resolvedTheme: ResolvedTheme? = nil,
        onLinkTap: ((URL) -> Void)? = nil,
    ) {
        self.htmlContent = htmlContent
        self.resolvedTheme = resolvedTheme ?? .darkBlue
        self.onLinkTap = onLinkTap
    }

    func makeNSView(context: Context) -> NSTextView {
        let textView = NSTextView()

        // Configure text view for read-only rich text display
        textView.backgroundColor = .clear
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.allowsUndo = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainerInset = NSSize(
            width: Self.textContainerInsetWidth,
            height: Self.textContainerInsetHeight,
        )

        // Configure text container
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.textContainer?.containerSize = NSSize(
            width: 0, height: CGFloat.greatestFiniteMagnitude,
        )

        // Set size constraints
        textView.minSize = NSSize(width: 0, height: Self.minimumHeight)
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude,
        )

        // Set up delegate for link handling
        textView.delegate = context.coordinator

        // Set initial content
        let attributedString = createAttributedString(from: htmlContent)
        textView.textStorage?.setAttributedString(attributedString)

        htmlTextViewLogger.debug(
            "HTMLTextView: Created NSTextView with content length: \(attributedString.length)",
        )

        return textView
    }

    func updateNSView(_ textView: NSTextView, context: Context) {
        let coordinator = context.coordinator

        // Skip re-parsing if inputs haven't changed
        if coordinator.lastHtmlContent == htmlContent, coordinator.lastTheme == resolvedTheme {
            return
        }

        let newAttributedText = createAttributedString(from: htmlContent)
        coordinator.lastHtmlContent = htmlContent
        coordinator.lastTheme = resolvedTheme

        htmlTextViewLogger.debug("HTMLTextView: Updating content (\(htmlContent?.count ?? 0) chars)")
        textView.textStorage?.setAttributedString(newAttributedText)

        // Force layout update
        textView.needsLayout = true
        if let textLayoutManager = textView.textLayoutManager {
            textLayoutManager.ensureLayout(for: textLayoutManager.documentRange)
        }

        textView.delegate = coordinator
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onLinkTap: onLinkTap, logger: htmlTextViewLogger)
    }

    // MARK: - HTML Processing

    private func createAttributedString(from htmlContent: String?) -> NSAttributedString {
        guard let htmlContent, !htmlContent.isEmpty else {
            let placeholder = "No description available"
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: Self.defaultFontSize),
                .foregroundColor: resolvedTheme.isDark
                    ? NSColor.lightGray : NSColor.darkGray,
            ]
            return NSAttributedString(string: placeholder, attributes: attributes)
        }

        htmlTextViewLogger.debug("HTMLTextView: Processing content (\(htmlContent.count) chars)")

        // Check if content contains actual HTML tags (not just comparison operators like `x < 5`)
        let isHTML = htmlContent.range(
            of: "</?[a-zA-Z][a-zA-Z0-9]*[\\s>/]",
            options: .regularExpression,
        ) != nil

        if !isHTML {
            // Plain text - create simple attributed string
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: Self.defaultFontSize),
                .foregroundColor: resolvedTheme.isDark ? NSColor.white : NSColor.black,
            ]
            return NSAttributedString(string: htmlContent, attributes: attributes)
        }

        // HTML content - create styled HTML and parse it
        let styledHTML = createStyledHTML(content: htmlContent)

        guard let data = styledHTML.data(using: .utf8) else {
            htmlTextViewLogger.error("HTMLTextView: Failed to convert HTML to data")
            return createPlainTextFallback(htmlContent)
        }

        do {
            let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue,
            ]

            let attributedString = try NSAttributedString(
                data: data, options: options, documentAttributes: nil,
            )
            htmlTextViewLogger.debug("HTMLTextView: Successfully parsed HTML (\(attributedString.length) chars)")
            return attributedString
        } catch {
            htmlTextViewLogger.error("HTMLTextView: Failed to parse HTML - \(error.localizedDescription)")
            return createPlainTextFallback(htmlContent)
        }
    }

    private func createPlainTextFallback(_ text: String) -> NSAttributedString {
        // Strip HTML tags for fallback display
        let plainText = text.replacingOccurrences(
            of: "<[^>]+>", with: "", options: .regularExpression, range: nil,
        )
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: Self.defaultFontSize),
            .foregroundColor: resolvedTheme.isDark ? NSColor.white : NSColor.black,
        ]
        return NSAttributedString(string: plainText, attributes: attributes)
    }

    private func createStyledHTML(content: String) -> String {
        let safeContent = HTMLSanitizer.sanitize(content)
        let isDark = resolvedTheme.isDark
        let bodyColor = isDark ? "#CCCCCC" : "#333333"
        let headingColor = isDark ? "#FFFFFF" : "#000000"
        let linkColor = isDark ? "#4A90E2" : "#007AFF"

        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <style>
                body {
                    font-family: -apple-system, BlinkMacSystemFont, sans-serif;
                    font-size: 13px;
                    line-height: 1.5;
                    color: \(bodyColor);
                    margin: 0;
                    padding: 0;
                    background: transparent;
                }
                h1, h2, h3, h4, h5, h6 {
                    color: \(headingColor);
                    margin: 0.5em 0;
                    font-weight: 600;
                }
                p { margin: 0.5em 0; }
                a {
                    color: \(linkColor);
                    text-decoration: none;
                }
                a:hover { text-decoration: underline; }
                ul, ol {
                    margin: 0.5em 0;
                    padding-left: 1.5em;
                }
                li { margin: 0.25em 0; }
                strong { font-weight: 600; }
                em { font-style: italic; }
            </style>
        </head>
        <body>
            \(safeContent)
        </body>
        </html>
        """
    }

    // MARK: - Coordinator for Link Handling

    class Coordinator: NSObject, NSTextViewDelegate {
        let onLinkTap: ((URL) -> Void)?
        let logger: Logger
        var lastHtmlContent: String?
        var lastTheme: ResolvedTheme?

        init(onLinkTap: ((URL) -> Void)?, logger: Logger) {
            self.onLinkTap = onLinkTap
            self.logger = logger
        }

        private static let allowedLinkSchemes: Set<String> = ["https", "http", "mailto"]

        func textView(_: NSTextView, clickedOnLink link: Any, at _: Int) -> Bool {
            guard let url = link as? URL else { return false }

            guard let scheme = url.scheme?.lowercased(),
                  Self.allowedLinkSchemes.contains(scheme)
            else {
                logger.warning("HTMLTextView: Blocked link with disallowed scheme")
                return true
            }

            logger.info("HTMLTextView: Link tapped (scheme: \(scheme))")

            if let onLinkTap {
                onLinkTap(url)
                return true
            }

            NSWorkspace.shared.open(url)
            return true
        }
    }
}
