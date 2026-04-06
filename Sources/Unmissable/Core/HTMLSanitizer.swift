import Foundation

/// Strips dangerous HTML elements that could execute code or load external resources.
/// Uses a character-scanning tokenizer instead of regex for correct handling of
/// malformed HTML, nested content, and edge cases in attribute values.
/// Preserves safe formatting tags (p, a, strong, em, ul, ol, li, h1-h6, br, div, span, img, etc.)
/// used in calendar event descriptions.
nonisolated enum HTMLSanitizer {
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

        // Skip to end of tag (handling quoted attribute values).
        // Also stop at unquoted '<' — browsers treat it as ending the tag,
        // and attackers use it to smuggle payloads past the tag boundary.
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
            } else if html[i] == "<" {
                // Unquoted '<' inside a tag means malformed HTML.
                // End the tag here; the '<' starts the next token.
                break
            } else {
                i = html.index(after: i)
            }
        }

        // Build the extracted tag. If we stopped at '>', include it and advance past.
        // If we stopped at '<' or endIndex, synthesize a closing '>' so downstream
        // attribute sanitization sees a well-formed tag.
        let tagEnd: String.Index
        let fullTag: String
        if i < html.endIndex, html[i] == ">" {
            tagEnd = html.index(after: i)
            fullTag = String(html[from ..< tagEnd])
        } else {
            tagEnd = i
            fullTag = String(html[from ..< i]) + ">"
        }

        return ParsedTag(
            tagName: tagName,
            fullTag: fullTag,
            isClosing: isClosing,
            afterTag: tagEnd,
        )
    }

    /// Advances past the closing tag `</tagName>` for a dangerous paired element.
    /// Handles nested instances of the same tag.
    private static func skipToClosingTag(
        _ html: String, from: String.Index, tagName: String,
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

    /// Intermediate result from reading a quoted attribute value.
    private struct QuotedValue {
        let value: String
        let quote: Character
        let afterQuote: String.Index
    }

    /// Parsed attribute name with its position context for emit decisions.
    private struct ParsedAttributeName {
        let name: String
        let nameLower: String
        let wsStart: String.Index
        let attrStart: String.Index
        let isEventHandler: Bool
    }

    /// Minimum length for `on*` to be considered an event handler (e.g. "on" + at least one char).
    private static let minEventHandlerPrefixLength = 2

    /// Removes event handler attributes (on*), neutralizes javascript:/data: URIs in href,
    /// and strips all `src` attributes to prevent external resource loading via the
    /// Foundation HTML importer. Calendar descriptions should never auto-fetch remote assets.
    private static func sanitizeAttributes(_ tag: String) -> String {
        // Fast path: no attributes to sanitize
        guard tag.contains("=") else { return tag }

        var result = ""
        result.reserveCapacity(tag.count)
        var i = copyTagPrefix(tag, into: &result)

        // Process attributes one at a time
        while i < tag.endIndex {
            if tag[i] == ">" || (tag[i] == "/" && nextChar(tag, after: i) == ">") {
                result.append(contentsOf: tag[i...])
                break
            }

            if tag[i].isWhitespace {
                i = processAttribute(tag, from: i, into: &result)
            } else if tag[i] == "/" {
                // Browsers treat '/' between tag name and attributes as whitespace.
                // Skip it and process what follows as an attribute to prevent XSS
                // bypasses like <svg/onload=alert(1)>.
                i = tag.index(after: i)
                if i < tag.endIndex, tag[i].isASCIILetter {
                    result.append(" ")
                    i = processAttribute(tag, from: i, into: &result)
                }
            } else {
                result.append(tag[i])
                i = tag.index(after: i)
            }
        }

        return result
    }

    /// Copies the tag opener (`<`, optional `/`, and tag name) into `result`.
    /// Returns the index immediately after the tag name.
    private static func copyTagPrefix(
        _ tag: String, into result: inout String,
    ) -> String.Index {
        var i = tag.startIndex
        result.append(tag[i]) // '<'
        i = tag.index(after: i)
        if i < tag.endIndex, tag[i] == "/" {
            result.append(tag[i])
            i = tag.index(after: i)
        }
        while i < tag.endIndex, tag[i].isASCIILetterOrDigit {
            result.append(tag[i])
            i = tag.index(after: i)
        }
        return i
    }

    /// Processes a single attribute (starting from whitespace before the name).
    /// Strips event handler attributes and neutralizes dangerous URIs.
    /// Returns the index after the processed attribute.
    private static func processAttribute(
        _ tag: String, from start: String.Index, into result: inout String,
    ) -> String.Index {
        var i = start

        // Consume leading whitespace
        let wsStart = i
        while i < tag.endIndex, tag[i].isWhitespace {
            i = tag.index(after: i)
        }

        // Read attribute name
        let attrStart = i
        var attrName = ""
        while i < tag.endIndex, tag[i].isASCIILetterOrDigit || tag[i] == "-" || tag[i] == "_" {
            attrName.append(tag[i])
            i = tag.index(after: i)
        }

        let nameLower = attrName.lowercased()
        let attr = ParsedAttributeName(
            name: attrName,
            nameLower: nameLower,
            wsStart: wsStart,
            attrStart: attrStart,
            isEventHandler: nameLower.hasPrefix("on") && nameLower.count > Self.minEventHandlerPrefixLength,
        )

        // Look for `= value`
        var tempI = skipWhitespace(tag, from: i)

        guard tempI < tag.endIndex, tag[tempI] == "=" else {
            // Boolean attribute (no value)
            if !attr.isEventHandler {
                result.append(contentsOf: tag[wsStart ..< i])
            }
            return i
        }

        tempI = skipWhitespace(tag, from: tag.index(after: tempI))

        if let quoted = readQuotedValue(tag, from: tempI) {
            return emitQuotedAttribute(tag, attr: attr, quoted: quoted, into: &result)
        }

        // Unquoted value — advance past it
        let unquotedStart = tempI
        while tempI < tag.endIndex, !tag[tempI].isWhitespace, tag[tempI] != ">" {
            tempI = tag.index(after: tempI)
        }
        if attr.isEventHandler {
            // Drop event handler entirely
        } else if attr.nameLower == "src" {
            // Always neutralize src — prevent external resource loading
            result.append(contentsOf: tag[attr.wsStart ..< attr.attrStart])
            result.append(attr.name)
            result.append("=\"about:blank\"")
        } else if attr.nameLower == "href",
                  isDangerousURI(String(tag[unquotedStart ..< tempI]))
        {
            // Neutralize dangerous URI in unquoted href value
            result.append(contentsOf: tag[attr.wsStart ..< attr.attrStart])
            result.append(attr.name)
            result.append("=\"about:blank\"")
        } else {
            result.append(contentsOf: tag[wsStart ..< tempI])
        }
        return tempI
    }

    /// Emits a quoted attribute, either dropping it (event handler), neutralizing the URI,
    /// or copying it verbatim. Returns the index after the attribute.
    private static func emitQuotedAttribute(
        _ tag: String,
        attr: ParsedAttributeName,
        quoted: QuotedValue,
        into result: inout String,
    ) -> String.Index {
        if attr.isEventHandler {
            return quoted.afterQuote
        }

        // src attributes are always neutralized — auto-loading external resources
        // (images, video, audio) is a privacy/tracking vector in untrusted HTML.
        // href is only neutralized for javascript:/data: schemes.
        let shouldNeutralize = attr.nameLower == "src"
            || (attr.nameLower == "href" && isDangerousURI(quoted.value))

        if shouldNeutralize {
            result.append(contentsOf: tag[attr.wsStart ..< attr.attrStart])
            result.append(attr.name)
            result.append("=")
            result.append(quoted.quote)
            result.append("about:blank")
            result.append(quoted.quote)
        } else {
            result.append(contentsOf: tag[attr.wsStart ..< quoted.afterQuote])
        }
        return quoted.afterQuote
    }

    /// Reads a quoted attribute value starting at the opening quote character.
    /// Returns nil if `from` does not point to a quote.
    private static func readQuotedValue(
        _ tag: String, from: String.Index,
    ) -> QuotedValue? {
        guard from < tag.endIndex,
              tag[from] == "\"" || tag[from] == "'"
        else { return nil }

        let quote = tag[from]
        let valueStart = tag.index(after: from)
        var valueEnd = valueStart
        while valueEnd < tag.endIndex, tag[valueEnd] != quote {
            valueEnd = tag.index(after: valueEnd)
        }
        let afterQuote = valueEnd < tag.endIndex
            ? tag.index(after: valueEnd) : valueEnd

        return QuotedValue(
            value: String(tag[valueStart ..< valueEnd]),
            quote: quote,
            afterQuote: afterQuote,
        )
    }

    /// Advances past whitespace characters, returning the first non-whitespace index.
    private static func skipWhitespace(
        _ tag: String, from: String.Index,
    ) -> String.Index {
        var i = from
        while i < tag.endIndex, tag[i].isWhitespace {
            i = tag.index(after: i)
        }
        return i
    }

    /// Start of the ASCII graphic character range (printable, non-whitespace).
    private static let asciiGraphicRangeStart: UInt32 = 0x21
    /// End of the ASCII graphic character range (printable, non-whitespace).
    private static let asciiGraphicRangeEnd: UInt32 = 0x7E
    /// Maximum number of digits allowed in a numeric HTML entity.
    private static let maxEntityDigits = 8
    /// Radix for hexadecimal number parsing.
    private static let hexRadix = 16
    /// Radix for decimal number parsing.
    private static let decimalRadix = 10

    /// Checks if a URI value starts with `javascript:` or `data:` (case-insensitive).
    /// Decodes HTML entities and strips all non-ASCII-graphic characters before the
    /// scheme check to prevent bypasses like `&#106;avascript:`, `java&#x0A;script:`,
    /// or any undecoded named entity (e.g. `&nbsp;`, `&ZeroWidthSpace;`) that resolves
    /// to a non-ASCII character browsers might strip from URL schemes.
    private static func isDangerousURI(_ value: String) -> Bool {
        let decoded = decodeHTMLEntities(value)
        // Keep only ASCII graphic characters (0x21-0x7E) for the scheme check.
        // This strips control chars, whitespace, NBSP, zero-width chars, and any
        // non-ASCII character that could be injected via undecoded named entities.
        // The original value is not modified — only the detection check uses this.
        let normalized = String(decoded.unicodeScalars.filter { scalar in
            scalar.value >= asciiGraphicRangeStart && scalar.value <= asciiGraphicRangeEnd
        })
        let lowered = normalized.lowercased()
        return lowered.hasPrefix("javascript:") || lowered.hasPrefix("data:")
    }

    /// Decodes numeric HTML entities (&#NNN; and &#xHH;) and common named entities
    /// to their character equivalents for URI safety checks.
    private static func decodeHTMLEntities(_ value: String) -> String {
        guard value.contains("&") else { return value }

        var result = ""
        result.reserveCapacity(value.count)
        var i = value.startIndex

        while i < value.endIndex {
            if value[i] == "&" {
                if let decoded = tryDecodeEntity(value, from: i) {
                    result.append(decoded.character)
                    i = decoded.afterEntity
                    continue
                }
            }
            result.append(value[i])
            i = value.index(after: i)
        }

        return result
    }

    private struct DecodedEntity {
        let character: Character
        let afterEntity: String.Index
    }

    /// Named entities relevant to URI bypass attacks.
    /// Includes &colon; (used to obfuscate "javascript:" / "data:"),
    /// &Tab;/&NewLine; (inline whitespace bypasses), and standard entities.
    /// Comparison is case-insensitive because HTML5 named entities are case-sensitive
    /// (e.g. &Tab; not &tab;) but attackers may use any casing — safer to match all.
    private static let namedEntities: [(String, Character)] = [
        ("amp;", "&"), ("lt;", "<"), ("gt;", ">"), ("quot;", "\""), ("apos;", "'"),
        ("colon;", ":"), ("semi;", ";"), ("tab;", "\t"), ("newline;", "\n"),
        ("lpar;", "("), ("rpar;", ")"), ("sol;", "/"), ("period;", "."),
        ("comma;", ","), ("excl;", "!"), ("num;", "#"), ("equals;", "="),
    ]

    private static func tryDecodeEntity(
        _ value: String, from start: String.Index,
    ) -> DecodedEntity? {
        let afterAmp = value.index(after: start)
        guard afterAmp < value.endIndex else { return nil }

        if value[afterAmp] == "#" {
            return tryDecodeNumericEntity(value, afterHash: value.index(after: afterAmp))
        }

        let remaining = String(value[afterAmp...]).lowercased()
        for (suffix, char) in namedEntities where remaining.hasPrefix(suffix) {
            let afterEntity = value.index(afterAmp, offsetBy: suffix.count)
            return DecodedEntity(character: char, afterEntity: afterEntity)
        }

        return nil
    }

    private static func tryDecodeNumericEntity(
        _ value: String, afterHash: String.Index,
    ) -> DecodedEntity? {
        guard afterHash < value.endIndex else { return nil }

        var i = afterHash
        let isHex = value[i] == "x" || value[i] == "X"
        if isHex {
            i = value.index(after: i)
        }

        var digits = ""
        while i < value.endIndex, value[i] != ";" {
            digits.append(value[i])
            i = value.index(after: i)
            if digits.count > maxEntityDigits { return nil }
        }

        guard i < value.endIndex, value[i] == ";" else { return nil }
        let afterSemicolon = value.index(after: i)

        let codePoint: UInt32? = if isHex {
            UInt32(digits, radix: hexRadix)
        } else {
            UInt32(digits, radix: decimalRadix)
        }

        guard let cp = codePoint, let scalar = Unicode.Scalar(cp) else { return nil }
        return DecodedEntity(character: Character(scalar), afterEntity: afterSemicolon)
    }

    private static func nextChar(_ s: String, after i: String.Index) -> Character? {
        let next = s.index(after: i)
        return next < s.endIndex ? s[next] : nil
    }
}

// MARK: - Character Helpers

private nonisolated extension Character {
    var isASCIILetter: Bool {
        ("a" ... "z").contains(self) || ("A" ... "Z").contains(self)
    }

    var isASCIILetterOrDigit: Bool {
        isASCIILetter || ("0" ... "9").contains(self)
    }
}
