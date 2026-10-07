import Foundation

/// The game parser's dictionary, read straight from the story file, so a spoken command can be
/// checked before it's sent: a word the parser doesn't know only gets "I don't know the word".
///
/// Planetfall is a version 3 Z-machine game, whose parser reads only the first six
/// "z-characters" of each word ("blather" is stored as "blathe"). Words are compared in that
/// encoding, exactly as the game compares them.
public struct GameVocabulary: Sendable {
    /// Dictionary words as the game stores them (cut to six z-characters), without the
    /// parser's internal entries ("#comm") or punctuation. For Claude's prompt.
    public let words: [String]
    /// Characters the parser treats as words of their own (`.`, `,`, `"`).
    public let separators: Set<Character>
    private let keys: Set<UInt32>

    /// The story's vocabulary, read once. Nil if the story file can't be found or read.
    public static let planetfall: GameVocabulary? = GameLocator.storyURL().flatMap { load(from: $0) }

    public static func load(from url: URL) -> GameVocabulary? {
        (try? Data(contentsOf: url)).flatMap { GameVocabulary(storyData: $0) }
    }

    /// Parses the dictionary table of a version 1-3 story file.
    public init?(storyData: Data) {
        let bytes = [UInt8](storyData)
        guard bytes.count > 64, (1...3).contains(bytes[0]) else { return nil }
        var offset = Int(bytes[8]) << 8 | Int(bytes[9])
        guard offset < bytes.count else { return nil }
        let separatorCount = Int(bytes[offset])
        guard offset + 1 + separatorCount + 3 <= bytes.count else { return nil }
        separators = Set(bytes[(offset + 1)..<(offset + 1 + separatorCount)].map { Character(UnicodeScalar($0)) })
        offset += 1 + separatorCount
        let entryLength = Int(bytes[offset])
        let count = Int(Int16(bitPattern: UInt16(bytes[offset + 1]) << 8 | UInt16(bytes[offset + 2])))
        offset += 3
        guard entryLength >= 4, count > 0, offset + count * entryLength <= bytes.count else { return nil }

        var keys = Set<UInt32>()
        var words: [String] = []
        for index in 0..<count {
            let entry = offset + index * entryLength
            let zchars = Self.zchars(bytes[entry], bytes[entry + 1]) + Self.zchars(bytes[entry + 2], bytes[entry + 3])
            keys.insert(Self.key(zchars))
            let word = Self.decode(zchars)
            if let first = word.first, first.isLetter || first.isNumber { words.append(word) }
        }
        self.keys = keys
        self.words = words
    }

    /// Words in `command` the parser wouldn't recognize, in order. Numbers and the parser's
    /// separators are always fine.
    public func unknownWords(in command: String) -> [String] {
        var unknown: [String] = []
        for token in tokens(in: command) where !token.allSatisfy(\.isNumber) {
            if !keys.contains(Self.key(Self.encode(token))), !unknown.contains(token) { unknown.append(token) }
        }
        return unknown
    }

    /// Drops characters the parser has no use for ("north?" would otherwise be an unknown word)
    /// and collapses spaces.
    public static func normalize(_ command: String) -> String {
        command.filter { $0 != "?" && $0 != "!" }
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    private func tokens(in command: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        for character in command.lowercased() {
            if character.isWhitespace || separators.contains(character) {
                if !current.isEmpty { tokens.append(current) }
                current = ""
            } else {
                current.append(character)
            }
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }

    // MARK: - Z-character encoding (version 3)

    private static let lowercase = Array("abcdefghijklmnopqrstuvwxyz")
    private static let punctuation = Array("0123456789.,!?_#'\"/\\-:()")  // alphabet A2 from z-char 8

    private static func zchars(_ high: UInt8, _ low: UInt8) -> [UInt8] {
        let word = UInt16(high) << 8 | UInt16(low)
        return [UInt8((word >> 10) & 31), UInt8((word >> 5) & 31), UInt8(word & 31)]
    }

    /// Six z-characters packed into one number, the way the parser compares words.
    private static func key(_ zchars: [UInt8]) -> UInt32 {
        zchars.prefix(6).reduce(0) { $0 << 5 | UInt32($1) }
    }

    /// Encodes a lowercase word as dictionary z-characters: cut to six, padded with 5s.
    static func encode(_ word: String) -> [UInt8] {
        var zchars: [UInt8] = []
        for character in word {
            if let index = lowercase.firstIndex(of: character) {
                zchars.append(UInt8(6 + index))
            } else if let index = punctuation.firstIndex(of: character) {
                zchars += [5, UInt8(8 + index)]
            } else {
                // Anything else is spelled out as a 10-bit ZSCII code.
                let code = UInt8(truncatingIfNeeded: character.unicodeScalars.first?.value ?? 63)
                zchars += [5, 6, code >> 5, code & 31]
            }
            if zchars.count >= 6 { break }
        }
        return Array((zchars + Array(repeating: 5, count: 6)).prefix(6))
    }

    private static func decode(_ zchars: [UInt8]) -> String {
        var word = ""
        var index = 0
        var shift: UInt8 = 0
        while index < zchars.count {
            let zchar = zchars[index]
            switch (shift, zchar) {
            case (_, 4), (_, 5):
                shift = zchar
                index += 1
                continue
            case (5, 6) where index + 2 < zchars.count:
                word.append(Character(UnicodeScalar(zchars[index + 1] << 5 | zchars[index + 2])))
                index += 2
            case (5, 8...31):
                word.append(punctuation[Int(zchar) - 8])
            case (0, 6...31), (4, 6...31):
                let letter = lowercase[Int(zchar) - 6]
                word.append(shift == 4 ? Character(letter.uppercased()) : letter)
            default:
                break
            }
            shift = 0
            index += 1
        }
        return word
    }
}
