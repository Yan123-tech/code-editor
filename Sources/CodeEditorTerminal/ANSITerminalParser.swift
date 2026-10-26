import Foundation

// MARK: - TerminalParser Protocol

/// Parses raw terminal byte streams into styled output lines.
public protocol TerminalParser: AnyObject, Sendable {
    func feed(_ data: Data, as defaultType: TerminalOutputType) -> [TerminalOutputLine]
    func flush(as defaultType: TerminalOutputType) -> [TerminalOutputLine]
    func reset()
}

// MARK: - TerminalCell

/// Represents a single character cell on the active line with its formatting style.
struct TerminalCell: Equatable, Sendable {
    var character: Character
    var style: TerminalStyle

    init(character: Character = " ", style: TerminalStyle = .default) {
        self.character = character
        self.style = style
    }
}

// MARK: - Parser State

private enum ParserState {
    case normal
    case escape
    case csi(params: String)
    case osc(params: String)
    case charset
}

// MARK: - ANSITerminalParser

/// A stateful ANSI escape sequence and control-character parser.
///
/// Handles:
/// - Control characters: `\n` (line feed), `\r` (carriage return overwrite), `\x08`/`\x7F` (backspace), `\t` (tab).
/// - ANSI CSI SGR formatting: bold, dim, italic, underline, standard 8/16 colors, 256 colors, and 24-bit RGB truecolor.
/// - ANSI CSI line editing: `\e[K` (erase to end), `\e[1K` (erase to start), `\e[2K` (erase line).
/// - Cursor movements (`\e[C`, `\e[D`, `\e[H`).
/// - Graceful handling of OSC, charset sequences, and fragmented data packets.
public final class ANSITerminalParser: TerminalParser, @unchecked Sendable {
    private let lock = NSLock()
    private var state: ParserState = .normal
    private var cells: [TerminalCell] = []
    private var cursorColumn: Int = 0
    private var currentStyle: TerminalStyle = .default
    private var savedCursorColumn: Int = 0

    private let maxLineLength = 8192

    public init() {}

    // MARK: - TerminalParser Implementation

    public func feed(_ data: Data, as defaultType: TerminalOutputType = .standard) -> [TerminalOutputLine] {
        lock.lock()
        defer { lock.unlock() }

        var outputLines: [TerminalOutputLine] = []
        guard let string = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            return []
        }

        for char in string {
            processCharacter(char, defaultType: defaultType, outputLines: &outputLines)
        }

        return outputLines
    }

    public func flush(as defaultType: TerminalOutputType = .standard) -> [TerminalOutputLine] {
        lock.lock()
        defer { lock.unlock() }

        if !cells.isEmpty {
            let line = buildLine(from: cells, defaultType: defaultType)
            cells.removeAll()
            cursorColumn = 0
            state = .normal
            return [line]
        }
        return []
    }

    public func reset() {
        lock.lock()
        defer { lock.unlock() }

        cells.removeAll()
        cursorColumn = 0
        currentStyle = .default
        savedCursorColumn = 0
        state = .normal
    }

    // MARK: - Character Processing

    private func processCharacter(
        _ char: Character,
        defaultType: TerminalOutputType,
        outputLines: inout [TerminalOutputLine]
    ) {
        switch state {
        case .normal:
            processNormal(char, defaultType: defaultType, outputLines: &outputLines)

        case .escape:
            processEscape(char)

        case .csi(var params):
            if isCSITerminator(char) {
                state = .normal
                executeCSI(command: char, params: params)
            } else {
                params.append(char)
                state = .csi(params: params)
            }

        case .osc(var params):
            // OSC terminates with BEL (0x07) or ST (\e\)
            if char == "\u{07}" || char == "\\" {
                state = .normal
            } else {
                params.append(char)
                state = .osc(params: params)
            }

        case .charset:
            // Single character designation (e.g. (B for ASCII), consume and return
            state = .normal
        }
    }

    private func processNormal(
        _ char: Character,
        defaultType: TerminalOutputType,
        outputLines: inout [TerminalOutputLine]
    ) {
        switch char {
        case "\n":
            let line = buildLine(from: cells, defaultType: defaultType)
            outputLines.append(line)
            cells.removeAll()
            cursorColumn = 0

        case "\r":
            cursorColumn = 0

        case "\u{08}", "\u{7F}":  // Backspace / DEL
            cursorColumn = max(0, cursorColumn - 1)

        case "\t":
            let tabStop = (cursorColumn / 8 + 1) * 8
            while cursorColumn < tabStop && cursorColumn < maxLineLength {
                writeCell(Character(" "))
            }

        case "\u{1B}":  // Escape
            state = .escape

        case "\u{00}", "\u{07}":  // Null / Bell
            break

        default:
            // Regular printable character
            writeCell(char)
        }
    }

    private func processEscape(_ char: Character) {
        switch char {
        case "[":
            state = .csi(params: "")
        case "]":
            state = .osc(params: "")
        case "(", ")":
            state = .charset
        case "7":
            savedCursorColumn = cursorColumn
            state = .normal
        case "8":
            cursorColumn = savedCursorColumn
            state = .normal
        case "c":  // RIS - Reset
            cells.removeAll()
            cursorColumn = 0
            currentStyle = .default
            state = .normal
        default:
            state = .normal
        }
    }

    // MARK: - CSI Command Execution

    private func isCSITerminator(_ char: Character) -> Bool {
        guard let ascii = char.asciiValue else { return true }
        return ascii >= 0x40 && ascii <= 0x7E
    }

    private func executeCSI(command: Character, params: String) {
        let cleanParams = params.trimmingCharacters(in: CharacterSet(charactersIn: "?>"))
        let parts = cleanParams.split(separator: ";").map { String($0) }
        let numbers = parts.compactMap { Int($0) }

        switch command {
        case "m":  // SGR - Select Graphic Rendition
            applySGR(numbers: numbers, rawParts: parts)

        case "K":  // Erase in line
            let mode = numbers.first ?? 0
            switch mode {
            case 0:  // Erase to end of line
                if cursorColumn < cells.count {
                    cells.removeSubrange(cursorColumn..<cells.count)
                }
            case 1:  // Erase to beginning of line
                let end = min(cursorColumn, cells.count)
                for i in 0..<end {
                    cells[i] = TerminalCell(character: " ", style: currentStyle)
                }
            case 2:  // Erase entire line
                cells.removeAll()
                cursorColumn = 0
            default:
                break
            }

        case "J":  // Erase in display
            let mode = numbers.first ?? 0
            if mode == 2 || mode == 3 {
                cells.removeAll()
                cursorColumn = 0
            }

        case "C":  // Cursor forward
            let count = max(1, numbers.first ?? 1)
            cursorColumn = min(maxLineLength, cursorColumn + count)

        case "D":  // Cursor backward
            let count = max(1, numbers.first ?? 1)
            cursorColumn = max(0, cursorColumn - count)

        case "H", "f":  // Cursor position
            if numbers.count >= 2 {
                cursorColumn = max(0, numbers[1] - 1)
            } else {
                cursorColumn = 0
            }

        default:
            break
        }
    }

    // MARK: - SGR Attributes

    private func applySGR(numbers: [Int], rawParts: [String]) {
        guard !numbers.isEmpty else {
            currentStyle = .default
            return
        }

        var i = 0
        while i < numbers.count {
            let code = numbers[i]
            switch code {
            case 0:
                currentStyle = .default
            case 1:
                currentStyle.isBold = true
            case 2:
                currentStyle.isDim = true
            case 3:
                currentStyle.isItalic = true
            case 4:
                currentStyle.isUnderline = true
            case 22:
                currentStyle.isBold = false
                currentStyle.isDim = false
            case 23:
                currentStyle.isItalic = false
            case 24:
                currentStyle.isUnderline = false

            // Standard foregrounds
            case 30: currentStyle.foregroundColor = .black
            case 31: currentStyle.foregroundColor = .red
            case 32: currentStyle.foregroundColor = .green
            case 33: currentStyle.foregroundColor = .yellow
            case 34: currentStyle.foregroundColor = .blue
            case 35: currentStyle.foregroundColor = .magenta
            case 36: currentStyle.foregroundColor = .cyan
            case 37: currentStyle.foregroundColor = .white
            case 39: currentStyle.foregroundColor = nil

            // Standard backgrounds
            case 40: currentStyle.backgroundColor = .black
            case 41: currentStyle.backgroundColor = .red
            case 42: currentStyle.backgroundColor = .green
            case 43: currentStyle.backgroundColor = .yellow
            case 44: currentStyle.backgroundColor = .blue
            case 45: currentStyle.backgroundColor = .magenta
            case 46: currentStyle.backgroundColor = .cyan
            case 47: currentStyle.backgroundColor = .white
            case 49: currentStyle.backgroundColor = nil

            // Bright foregrounds
            case 90: currentStyle.foregroundColor = .brightBlack
            case 91: currentStyle.foregroundColor = .brightRed
            case 92: currentStyle.foregroundColor = .brightGreen
            case 93: currentStyle.foregroundColor = .brightYellow
            case 94: currentStyle.foregroundColor = .brightBlue
            case 95: currentStyle.foregroundColor = .brightMagenta
            case 96: currentStyle.foregroundColor = .brightCyan
            case 97: currentStyle.foregroundColor = .brightWhite

            // Bright backgrounds
            case 100: currentStyle.backgroundColor = .brightBlack
            case 101: currentStyle.backgroundColor = .brightRed
            case 102: currentStyle.backgroundColor = .brightGreen
            case 103: currentStyle.backgroundColor = .brightYellow
            case 104: currentStyle.backgroundColor = .brightBlue
            case 105: currentStyle.backgroundColor = .brightMagenta
            case 106: currentStyle.backgroundColor = .brightCyan
            case 107: currentStyle.backgroundColor = .brightWhite

            // Extended foreground 38;5;n or 38;2;r;g;b
            case 38:
                if i + 2 < numbers.count && numbers[i + 1] == 5 {
                    currentStyle.foregroundColor = TerminalColor.ansi256(numbers[i + 2])
                    i += 2
                } else if i + 4 < numbers.count && numbers[i + 1] == 2 {
                    let r = Double(numbers[i + 2]) / 255.0
                    let g = Double(numbers[i + 3]) / 255.0
                    let b = Double(numbers[i + 4]) / 255.0
                    currentStyle.foregroundColor = TerminalColor(red: r, green: g, blue: b)
                    i += 4
                }

            // Extended background 48;5;n or 48;2;r;g;b
            case 48:
                if i + 2 < numbers.count && numbers[i + 1] == 5 {
                    currentStyle.backgroundColor = TerminalColor.ansi256(numbers[i + 2])
                    i += 2
                } else if i + 4 < numbers.count && numbers[i + 1] == 2 {
                    let r = Double(numbers[i + 2]) / 255.0
                    let g = Double(numbers[i + 3]) / 255.0
                    let b = Double(numbers[i + 4]) / 255.0
                    currentStyle.backgroundColor = TerminalColor(red: r, green: g, blue: b)
                    i += 4
                }

            default:
                break
            }
            i += 1
        }
    }

    // MARK: - Cell Operations

    private func writeCell(_ char: Character) {
        guard cursorColumn < maxLineLength else { return }

        let cell = TerminalCell(character: char, style: currentStyle)
        if cursorColumn < cells.count {
            cells[cursorColumn] = cell
        } else {
            while cells.count < cursorColumn {
                cells.append(TerminalCell(character: " ", style: currentStyle))
            }
            cells.append(cell)
        }
        cursorColumn += 1
    }

    private func buildLine(from cells: [TerminalCell], defaultType: TerminalOutputType) -> TerminalOutputLine {
        guard !cells.isEmpty else {
            return TerminalOutputLine(text: "", type: defaultType, spans: [])
        }

        let plainText = String(cells.map { $0.character })

        var spans: [TerminalOutputSpan] = []
        var currentText = ""
        var activeStyle = cells[0].style

        for cell in cells {
            if cell.style == activeStyle {
                currentText.append(cell.character)
            } else {
                spans.append(TerminalOutputSpan(text: currentText, style: activeStyle))
                currentText = String(cell.character)
                activeStyle = cell.style
            }
        }
        if !currentText.isEmpty {
            spans.append(TerminalOutputSpan(text: currentText, style: activeStyle))
        }

        return TerminalOutputLine(text: plainText, type: defaultType, spans: spans)
    }
}
