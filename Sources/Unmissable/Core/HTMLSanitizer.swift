import Foundation

/// Strips dangerous HTML elements that could execute code or load external resources.
/// Uses a character-scanning tokenizer instead of regex for correct handling of
/// malformed HTML, nested content, and edge cases in attribute values.
/// Preserves safe formatting tags (p, a, strong, em, ul, ol, li, h1-h6, br, div, span, img, etc.)
/// used in calendar event descriptions.
enum HTMLSanitizer {
    /// Tags whose entire content (including nested elements) must be removed.
    private static let dangerousPairedTags: Set<String> = [
        "script", "style", "iframe", "object", "form",
    ]

    /// Self-closing / void tags that must be removed (no inner content to skip).
    private static let dangerousVoidTags: Set<String> = [
        "embed", "link", "meta", "base",
    ]

    /// All dangerous tag names for quick lookup.
    private static let allDangerousTags: Set<String> =
        dangerousPairedTags.union(dangerousVoidTags)

    /// Sanitizes HTML by scanning through the string character-by-character,
    /// removing dangerous elements, event handler attributes, and javascript:/data: URIs.
    static func sanitize(_ html: String) -> String {
        guard !html.isEmpty else { return html }

        var result = ""
        result.reserveCapacity(html.count)
        var index = html.startIndex

        while index < html.endIndex {
            if html[index] == "<" {
                // Potential tag start — parse it
                if let parsed = parseTag(html, from: index) {
                    let tagNameLower = parsed.tagName.lowercased()

                    if dangerousPairedTags.contains(tagNameLower), !parsed.isClosing {
                        // Skip this tag and everything up to and including its closing tag
                        index = skipToClosingTag(html, from: parsed.afterTag, tagName: tagNameLower)
                    } else if allDangerousTags.contains(tagNameLower) {
                        // Dangerous void tag or closing tag of a dangerous paired tag — skip just the tag
                        index = parsed.afterTag
                    } else {
                        // Safe tag — emit it with sanitized attributes
                        let sanitizedTag = sanitizeAttributes(parsed.fullTag)
                        result.append(sanitizedTag)
                        index = parsed.afterTag
                    }
                } else {
                    // Not a valid tag (e.g., `x < 5`) — emit the character literally
                    result.append(html[index])
                    index = html.index(after: index)
                }
            } else {
                result.append(html[index])
                index = html.index(after: index)
            }
        }

        return result
    }

    // MARK: - Tag Parsing

    private struct ParsedTag {
        let tagName: String
        let fullTag: String
        let isClosing: Bool
        let afterTag: String.Index
    }

    /// Attempts to parse an HTML tag starting at `from` (which points to `<`).
    /// Returns nil if the content at `from` is not a valid tag opener.
    private static func parseTag(_ html: String, from: String.Index) -> ParsedTag? {
        var i = html.index(after: from) // skip '<'
        guard i < html.endIndex else { return nil }

        // Check for closing tag
        let isClosing = html[i] == "/"
        if isClosing {
            i = html.index(after: i)
            guard i < html.endIndex else { return nil }
        }

        // Tag name must start with a letter
        guard html[i].isASCIILetter else { return nil }

        // Read tag name
        let nameStart = i
        while i < html.endIndex, html[i].isASCIILetterOrDigit {
            i = html.index(after: i)
        }
        let tagName = String(html[nameStart ..< i])

        // Skip to end of tag (handling quoted attribute values)
        while i < html.endIndex, html[i] != ">" {
            if html[i] == "\"" || html[i] == "'" {
                let quote = html[i]
                i = html.index(after: i)
                while i < html.endIndex, html[i] != quote {
                    i = html.index(after: i)
                }
                if i < html.endIndex {
                    i = html.index(after: i) // skip closing quote
                }
            } else {
                i = html.index(after: i)
            }
        }

        // Move past '>'
        let tagEnd: String.Index = if i < html.endIndex {
            html.index(after: i)
        } else {
            i
        }

        let fullTag = String(html[from ..< tagEnd])

        return ParsedTag(
            tagName: tagName,
            fullTag: fullTag,
            isClosing: isClosing,
            afterTag: tagEnd
        )
    }

    /// Advances past the closing tag `</tagName>` for a dangerous paired element.
    /// Handles nested instances of the same tag.
    private static func skipToClosingTag(
        _ html: String, from: String.Index, tagName: String
    ) -> String.Index {
        var i = from
        var depth = 1

        while i < html.endIndex, depth > 0 {
            if html[i] == "<" {
                if let parsed = parseTag(html, from: i) {
                    let parsedNameLower = parsed.tagName.lowercased()
                    if parsedNameLower == tagName {
                        if parsed.isClosing {
                            depth -= 1
                        } else {
                            depth += 1
                        }
                    }
                    i = parsed.afterTag
                    continue
                }
            }
            i = html.index(after: i)
        }

        return i
    }

    // MARK: - Attribute Sanitization

    /// Removes event handler attributes (on*) and neutralizes javascript:/data: URIs
    /// within a tag string like `<a href="..." onclick="...">`.
    private static func sanitizeAttributes(_ tag: String) -> String {
        // Fast path: no attributes to sanitize
        guard tag.contains("=") else { return tag }

        var result = ""
        result.reserveCapacity(tag.count)
        var i = tag.startIndex

        // Copy up to first whitespace after tag name (the '<' and tag name)
        // Skip '<' and optional '/'
        result.append(tag[i]) // '<'
        i = tag.index(after: i)
        if i < tag.endIndex, tag[i] == "/" {
            result.append(tag[i])
            i = tag.index(after: i)
        }
        // Copy tag name
        while i < tag.endIndex, tag[i].isASCIILetterOrDigit {
            result.append(tag[i])
            i = tag.index(after: i)
        }

        // Now process attributes
        while i < tag.endIndex {
            if tag[i] == ">" || (tag[i] == "/" && nextChar(tag, after: i) == ">") {
                // End of tag — copy remainder
                result.append(contentsOf: tag[i...])
                break
            }

            // Skip whitespace
            if tag[i].isWhitespace {
                let wsStart = i
                while i < tag.endIndex, tag[i].isWhitespace {
                    i = tag.index(after: i)
                }
                // Read ahead to check if this whitespace precedes a dangerous attribute
                let attrStart = i
                var attrName = ""
                while i < tag.endIndex, tag[i].isASCIILetterOrDigit || tag[i] == "-" || tag[i] == "_" {
                    attrName.append(tag[i])
                    i = tag.index(after: i)
                }

                let attrNameLower = attrName.lowercased()
                let isEventHandler = attrNameLower.hasPrefix("on") && attrNameLower.count > 2

                // Check for = and value
                var tempI = i
                // Skip whitespace around =
                while tempI < tag.endIndex, tag[tempI].isWhitespace {
                    tempI = tag.index(after: tempI)
                }

                if tempI < tag.endIndex, tag[tempI] == "=" {
                    tempI = tag.index(after: tempI)
                    // Skip whitespace after =
                    while tempI < tag.endIndex, tag[tempI].isWhitespace {
                        tempI = tag.index(after: tempI)
                    }

                    // Read attribute value
                    if tempI < tag.endIndex, tag[tempI] == "\"" || tag[tempI] == "'" {
                        let quote = tag[tempI]
                        let valueStart = tag.index(after: tempI)
                        var valueEnd = valueStart
                        while valueEnd < tag.endIndex, tag[valueEnd] != quote {
                            valueEnd = tag.index(after: valueEnd)
                        }
                        let value = String(tag[valueStart ..< valueEnd])
                        let afterQuote = valueEnd < tag.endIndex
                            ? tag.index(after: valueEnd) : valueEnd

                        if isEventHandler {
                            // Drop the entire attribute (whitespace + name + = + value)
                            i = afterQuote
                            continue
                        }

                        let isDangerousURI = (attrNameLower == "href" || attrNameLower == "src")
                            && isDangerousURI(value)

                        if isDangerousURI {
                            // Replace the URI value with about:blank
                            result.append(contentsOf: tag[wsStart ..< attrStart])
                            result.append(attrName)
                            result.append("=")
                            result.append(quote)
                            result.append("about:blank")
                            result.append(quote)
                            i = afterQuote
                        } else {
                            // Safe attribute — copy as-is
                            result.append(contentsOf: tag[wsStart ..< afterQuote])
                            i = afterQuote
                        }
                    } else {
                        // Unquoted attribute value — advance past it
                        while tempI < tag.endIndex, !tag[tempI].isWhitespace, tag[tempI] != ">" {
                            tempI = tag.index(after: tempI)
                        }
                        if isEventHandler {
                            i = tempI
                            continue
                        }
                        result.append(contentsOf: tag[wsStart ..< tempI])
                        i = tempI
                    }
                } else {
                    // Attribute without value (boolean attribute)
                    if isEventHandler {
                        // i is already past the attribute name — just skip it
                        continue
                    }
                    result.append(contentsOf: tag[wsStart ..< i])
                }
            } else {
                result.append(tag[i])
                i = tag.index(after: i)
            }
        }

        return result
    }

    /// Checks if a URI value starts with `javascript:` or `data:` (case-insensitive).
    private static func isDangerousURI(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespaces).lowercased()
        return trimmed.hasPrefix("javascript:") || trimmed.hasPrefix("data:")
    }

    private static func nextChar(_ s: String, after i: String.Index) -> Character? {
        let next = s.index(after: i)
        return next < s.endIndex ? s[next] : nil
    }
}

// MARK: - Character Helpers

private extension Character {
    var isASCIILetter: Bool {
        ("a" ... "z").contains(self) || ("A" ... "Z").contains(self)
    }

    var isASCIILetterOrDigit: Bool {
        isASCIILetter || ("0" ... "9").contains(self)
    }
}
