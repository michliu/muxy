import Foundation

struct TerminalScreenCell {
    let codepoint: UInt32
    let fg: UInt32
    let bg: UInt32
    let flags: UInt16
}

struct TerminalScreenSnapshot {
    let cols: Int
    let rows: Int
    let cursorX: Int
    let cursorY: Int
    let cursorVisible: Bool
    let defaultFg: UInt32
    let defaultBg: UInt32
    let cells: [TerminalScreenCell]
    let altScreen: Bool
    let cursorKeys: Bool
    let bracketedPaste: Bool
    let focusEvent: Bool
    let mouseEvent: UInt16
    let mouseFormat: UInt16
}

enum TerminalScreenCellFlag {
    static let bold: UInt16 = 1 << 0
    static let italic: UInt16 = 1 << 1
    static let faint: UInt16 = 1 << 2
    static let blink: UInt16 = 1 << 3
    static let inverse: UInt16 = 1 << 4
    static let invisible: UInt16 = 1 << 5
    static let strike: UInt16 = 1 << 6
    static let underline: UInt16 = 1 << 7
    static let overline: UInt16 = 1 << 8
}

enum TerminalScreenPaint {
    static func buildBytes(from snapshot: TerminalScreenSnapshot) -> Data {
        let cols = snapshot.cols
        let rows = snapshot.rows
        guard cols > 0, rows > 0, snapshot.cells.count >= cols * rows else { return Data() }

        var output = String()
        output.reserveCapacity(cols * rows * 4)
        output.append("\u{1B}[0m")
        if snapshot.altScreen {
            output.append("\u{1B}[?1049h")
        }
        output.append("\u{1B}[2J")
        output.append("\u{1B}[H")

        var currentFg: UInt32 = snapshot.defaultFg
        var currentBg: UInt32 = snapshot.defaultBg
        var currentFlags: UInt16 = 0

        for row in 0 ..< rows {
            let trimEnd = lastNonDefaultCellIndex(
                cells: snapshot.cells,
                row: row,
                cols: cols,
                defaultFg: snapshot.defaultFg,
                defaultBg: snapshot.defaultBg
            )

            for col in 0 ..< (trimEnd + 1) {
                let cell = snapshot.cells[row * cols + col]

                if cell.fg != currentFg || cell.bg != currentBg || cell.flags != currentFlags {
                    output.append(
                        sgrSequence(
                            fg: cell.fg,
                            bg: cell.bg,
                            flags: cell.flags,
                            defaultFg: snapshot.defaultFg,
                            defaultBg: snapshot.defaultBg
                        )
                    )
                    currentFg = cell.fg
                    currentBg = cell.bg
                    currentFlags = cell.flags
                }

                output.append(character(for: cell.codepoint))
            }

            if row < rows - 1 {
                output.append("\u{1B}[0m")
                output.append("\r\n")
                currentFg = snapshot.defaultFg
                currentBg = snapshot.defaultBg
                currentFlags = 0
            }
        }

        output.append("\u{1B}[0m")

        let cursorRow = min(max(snapshot.cursorY + 1, 1), rows)
        let cursorCol = min(max(snapshot.cursorX + 1, 1), cols)
        output.append("\u{1B}[\(cursorRow);\(cursorCol)H")

        if !snapshot.cursorVisible {
            output.append("\u{1B}[?25l")
        }

        if snapshot.cursorKeys {
            output.append("\u{1B}[?1h")
        }
        if snapshot.bracketedPaste {
            output.append("\u{1B}[?2004h")
        }
        if snapshot.focusEvent {
            output.append("\u{1B}[?1004h")
        }
        if snapshot.mouseEvent != 0 {
            output.append("\u{1B}[?\(snapshot.mouseEvent)h")
        }
        if snapshot.mouseFormat != 0 {
            output.append("\u{1B}[?\(snapshot.mouseFormat)h")
        }

        return Data(output.utf8)
    }

    private static func lastNonDefaultCellIndex(
        cells: [TerminalScreenCell],
        row: Int,
        cols: Int,
        defaultFg: UInt32,
        defaultBg: UInt32
    ) -> Int {
        let base = row * cols
        var last = -1
        for col in 0 ..< cols {
            let cell = cells[base + col]
            let isBlank = (cell.codepoint == 0 || cell.codepoint == 0x20)
                && cell.fg == defaultFg
                && cell.bg == defaultBg
                && cell.flags == 0
            if !isBlank { last = col }
        }
        return last
    }

    private static func character(for codepoint: UInt32) -> String {
        if codepoint == 0 { return " " }
        guard let scalar = Unicode.Scalar(codepoint) else { return " " }
        return String(Character(scalar))
    }

    private static func sgrSequence(
        fg: UInt32,
        bg: UInt32,
        flags: UInt16,
        defaultFg: UInt32,
        defaultBg: UInt32
    ) -> String {
        var params = ["0"]

        if flags & TerminalScreenCellFlag.bold != 0 { params.append("1") }
        if flags & TerminalScreenCellFlag.faint != 0 { params.append("2") }
        if flags & TerminalScreenCellFlag.italic != 0 { params.append("3") }
        if flags & TerminalScreenCellFlag.underline != 0 { params.append("4") }
        if flags & TerminalScreenCellFlag.blink != 0 { params.append("5") }
        if flags & TerminalScreenCellFlag.inverse != 0 { params.append("7") }
        if flags & TerminalScreenCellFlag.invisible != 0 { params.append("8") }
        if flags & TerminalScreenCellFlag.strike != 0 { params.append("9") }
        if flags & TerminalScreenCellFlag.overline != 0 { params.append("53") }

        if fg != defaultFg {
            params.append("38;2;\((fg >> 16) & 0xFF);\((fg >> 8) & 0xFF);\(fg & 0xFF)")
        }
        if bg != defaultBg {
            params.append("48;2;\((bg >> 16) & 0xFF);\((bg >> 8) & 0xFF);\(bg & 0xFF)")
        }

        return "\u{1B}[\(params.joined(separator: ";"))m"
    }
}
