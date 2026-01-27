import AppKit
import OSLog
import SwiftUI

/// A SwiftUI view that renders HTML content using NSAttributedString and NSTextView
/// Supports rich text formatting, clickable links, and custom theming
struct HTMLTextView: NSViewRepresentable {
    private let logger = Logger(subsystem: "com.unmissable.app", category: "HTMLTextView")

    let htmlContent: String?
    let effectiveTheme: EffectiveTheme
    let onLinkTap: ((URL) -> Void)?

    init(
        htmlContent: String?,
        effectiveTheme: EffectiveTheme? = nil,
        onLinkTap: ((URL) -> Void)? = nil
    ) {
        self.htmlContent = htmlContent
        self.effectiveTheme = effectiveTheme ?? .dark
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
        textView.textContainerInset = NSSize(width: 8, height: 8)

        // Configure text container
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.textContainer?.containerSize = NSSize(
            width: 0, height: CGFloat.greatestFiniteMagnitude
        )

        // Set size constraints
        textView.minSize = NSSize(width: 0, height: 20)
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude
        )

        // Set up delegate for link handling
        textView.delegate = context.coordinator

        // Set initial content
        let attributedString = createAttributedString(from: htmlContent)
        textView.textStorage?.setAttributedString(attributedString)

        logger.debug(
            "📝 HTMLTextView: Created NSTextView with content length: \(attributedString.length)"
        )

        return textView
    }

    func updateNSView(_ textView: NSTextView, context: Context) {
        let newAttributedText = createAttributedString(from: htmlContent)

        if !textView.attributedString().isEqual(to: newAttributedText) {
            logger.debug("📝 HTMLTextView: Updating content (\(htmlContent?.count ?? 0) chars)")
            textView.textStorage?.setAttributedString(newAttributedText)

            // Force layout update
            textView.needsLayout = true
            if let layoutManager = textView.layoutManager,
               let textContainer = textView.textContainer {
                layoutManager.ensureLayout(for: textContainer)
            }
        }

        textView.delegate = context.coordinator
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onLinkTap: onLinkTap, logger: logger)
    }

    // MARK: - HTML Processing

    private func createAttributedString(from htmlContent: String?) -> NSAttributedString {
        guard let htmlContent, !htmlContent.isEmpty else {
            let placeholder = "No description available"
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 13),
                .foregroundColor: effectiveTheme == .dark
                    ? NSColor.secondaryLabelColor : NSColor.secondaryLabelColor,
            ]
            return NSAttributedString(string: placeholder, attributes: attributes)
        }

        logger.debug("📝 HTMLTextView: Processing content (\(htmlContent.count) chars)")

        // Check if content is HTML or plain text
        let isHTML = htmlContent.contains("<") && htmlContent.contains(">")

        if !isHTML {
            // Plain text - create simple attributed string
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 13),
                .foregroundColor: effectiveTheme == .dark ? NSColor.labelColor : NSColor.labelColor,
            ]
            return NSAttributedString(string: htmlContent, attributes: attributes)
        }

        // HTML content - create styled HTML and parse it
        let styledHTML = createStyledHTML(content: htmlContent)

        guard let data = styledHTML.data(using: .utf8) else {
            logger.error("❌ HTMLTextView: Failed to convert HTML to data")
            return createPlainTextFallback(htmlContent)
        }

        do {
            let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue,
            ]

            let attributedString = try NSAttributedString(
                data: data, options: options, documentAttributes: nil
            )
            logger.debug("✅ HTMLTextView: Successfully parsed HTML (\(attributedString.length) chars)")
            return attributedString
        } catch {
            logger.error("❌ HTMLTextView: Failed to parse HTML - \(error.localizedDescription)")
            return createPlainTextFallback(htmlContent)
        }
    }

    private func createPlainTextFallback(_ text: String) -> NSAttributedString {
        // Strip HTML tags for fallback display
        let plainText = text.replacingOccurrences(
            of: "<[^>]+>", with: "", options: .regularExpression, range: nil
        )
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: effectiveTheme == .dark ? NSColor.labelColor : NSColor.labelColor,
        ]
        return NSAttributedString(string: plainText, attributes: attributes)
    }

    private func createStyledHTML(content: String) -> String {
        let isDark = effectiveTheme == .dark
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
            \(content)
        </body>
        </html>
        """
    }

    // MARK: - Coordinator for Link Handling

    class Coordinator: NSObject, NSTextViewDelegate {
        let onLinkTap: ((URL) -> Void)?
        let logger: Logger

        init(onLinkTap: ((URL) -> Void)?, logger: Logger) {
            self.onLinkTap = onLinkTap
            self.logger = logger
        }

        func textView(_: NSTextView, clickedOnLink link: Any, at _: Int) -> Bool {
            guard let url = link as? URL else { return false }

            logger.info("🔗 HTMLTextView: Link tapped - \(url.absoluteString)")

            if let onLinkTap {
                onLinkTap(url)
                return true
            }

            NSWorkspace.shared.open(url)
            return true
        }
    }
}
