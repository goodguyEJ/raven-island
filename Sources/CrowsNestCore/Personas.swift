import Foundation

/// One of the crew: an original pixel-art field agent with its own look, colours, and party trick.
///
/// An agent is drawn once, standing, in an 11-pixel-wide column of a 16×16 grid: a big head, a small
/// suited body. Everything else (walking, arms up, blinking, and the props for each session state) is
/// composed from that drawing, so every agent can show every state.
///
/// Pixels: `B` suit, `b` suit shade and shoes, `A` hair or hat, `a` its shade, `F` skin, `f` skin shade,
/// `T` tie, plus the shared colours `W` white, `K` dark, `Y` gold, `R` red, `G` green, `Z` pale blue,
/// `H` metal, `h` wood, `S`/`s` brick.
public struct Persona: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let role: String
    public let motto: String
    /// 16 rows × 11 columns.
    public let stand: [String]
    /// Rows holding the eyes, for blinking; empty for an agent behind sunglasses.
    public let eyeRows: [Int]
    /// Hex colours for `B`, `b`, `A`, `a`, `F`, `f`, `T`.
    public let colors: [Character: UInt32]
    /// The party trick: for each frame, whether the arms are up and the extra pixels to draw (row, column, pixel).
    public let trick: [TrickFrame]

    public struct TrickFrame: Sendable {
        public let armsUp: Bool
        public let pixels: [(Int, Int, Character)]
    }
}

extension PixelSprites {
    /// Colours shared by every agent and prop.
    public static let sharedColors: [Character: UInt32] = [
        "W": 0xFFFFFF, "K": 0x141414, "H": 0xCCCCCC, "h": 0xB8804D, "S": 0xDB735C, "s": 0xB35445,
        "Y": 0xFFD633, "R": 0xFF544D, "G": 0x52DB6B, "Z": 0xB3DBFF,
    ]

    /// Width of an agent's own drawing; props go to the right of it.
    public static let bodyWidth = 11

    /// Suit, shirt and tie, hands at the sides, legs and shoes. Shared by most of the crew.
    static let suit = ["..BBWTWBB..", ".BBBWTWBBB.", ".FBBBTBBBF.", "..BBBBBBB..", "..BBB.BBB..", "..BBB.BBB..", "..bbb.bbb.."]
    /// Legs for the second step of the walk (replaces the bottom three rows).
    static let stepLegs = ["...BBBBB...", "...BB.BB...", "...bb.bb..."]

    public static let personas: [Persona] = [
        // Field lead: short dark hair, aviators, earpiece, charcoal suit, red tie.
        Persona(id: "bolt", name: "Bolt", role: "field lead", motto: "Eyes on the target. Always.",
                stand: ["..AAAAAAA..", ".AAAAAAAAA.", ".AAAAAAAAA.", ".AAFFFFFAA.", ".AFFFFFFFA.", ".FKKKKKKKF.",
                        ".FFKKFKKFW.", "..FFFfFFFW.", "...FFFFF..."] + suit,
                eyeRows: [],
                colors: ["B": 0x465063, "b": 0x2E3644, "A": 0x4A3728, "a": 0x35271C, "F": 0xF2C9A0, "f": 0xD99E7E, "T": 0xE5484D],
                // Flashes a badge.
                trick: [.init(armsUp: false, pixels: [(11, 9, "B"), (11, 10, "B"), (11, 11, "F"), (9, 12, "Y"), (9, 13, "Y"), (10, 12, "Y"),
                                                      (10, 13, "Y"), (11, 12, "Y"), (11, 13, "Y"), (12, 12, "Y")]),
                        .init(armsUp: false, pixels: [(10, 9, "B"), (10, 10, "B"), (10, 11, "F"), (8, 12, "Y"), (8, 13, "Y"), (9, 12, "W"),
                                                      (9, 13, "Y"), (10, 12, "Y"), (10, 13, "Y"), (11, 12, "Y"), (7, 14, "W"), (6, 12, "W")])]),

        // Analyst: long violet hair, glasses, navy suit, tablet under the arm.
        Persona(id: "merlo", name: "Merlo", role: "analyst", motto: "The data never lies.",
                stand: ["..AAAAAAA..", ".AAAAAAAAA.", "AAAAAAAAAAA", "AAAAFFFFAAA", "AAFFFFFFFAA", "AFHKHFHKHFA",
                        "AFFKFFFKFFA", "A.FFFfFFF.A", "A..FFFFF..A"] + suit,
                eyeRows: [5, 6],
                colors: ["B": 0x34548C, "b": 0x243A63, "A": 0x6A5AA8, "a": 0x4B3F7A, "F": 0xD9A27A, "f": 0xBD855E, "T": 0xB08CFF],
                // Pulls up intel on a tablet.
                trick: [.init(armsUp: false, pixels: [(11, 9, "B"), (11, 10, "F"), (9, 11, "H"), (9, 12, "H"), (9, 13, "H"), (9, 14, "H"),
                                                      (10, 11, "H"), (10, 12, "G"), (10, 13, "K"), (10, 14, "H"), (11, 11, "H"), (11, 12, "K"),
                                                      (11, 13, "G"), (11, 14, "H"), (12, 11, "H"), (12, 12, "H"), (12, 13, "H"), (12, 14, "H")]),
                        .init(armsUp: false, pixels: [(11, 9, "B"), (11, 10, "F"), (9, 11, "H"), (9, 12, "H"), (9, 13, "H"), (9, 14, "H"),
                                                      (10, 11, "H"), (10, 12, "K"), (10, 13, "G"), (10, 14, "H"), (11, 11, "H"), (11, 12, "G"),
                                                      (11, 13, "G"), (11, 14, "H"), (12, 11, "H"), (12, 12, "H"), (12, 13, "H"), (12, 14, "H"),
                                                      (7, 13, "G")])]),

        // Infiltrator: beanie, headset with a mic boom, tactical turtleneck.
        Persona(id: "kage", name: "Kage", role: "infiltrator", motto: "In and out. No trace.",
                stand: ["..AAAAAAA..", ".AAAAAAAAA.", ".AAAAAAAAA.", ".aaaaaaaaa.", ".FFFFFFFFF.", ".FKKFFFKKF.",
                        "HFFFFFFFFF.", "H.FFFFFFF..", ".HHFFFFF...",
                        "..BBBBBBB..", ".BBBbBbBBB.", ".FBBBBBBBF.", "..BBBBBBB..", "..BBB.BBB..", "..BBB.BBB..", "..bbb.bbb.."],
                eyeRows: [5],
                colors: ["B": 0x3F5560, "b": 0x2A3A42, "A": 0x5A6478, "a": 0x3E4656, "F": 0xF2C9A0, "f": 0xD99E7E, "T": 0x3F5560],
                // Radios in: signal rings spread from the headset.
                trick: [.init(armsUp: false, pixels: [(4, 11, "Z"), (5, 12, "Z"), (6, 11, "Z")]),
                        .init(armsUp: false, pixels: [(3, 12, "Z"), (4, 13, "Z"), (5, 14, "Z"), (6, 13, "Z"), (7, 12, "Z"), (5, 12, "W")])]),

        // Pilot: blonde ponytail, aviators, grey suit, blue tie.
        Persona(id: "nova", name: "Nova", role: "pilot", motto: "Wheels up in five.",
                stand: ["..AAAAAAA..", ".AAAAAAAAAA", ".AAAAAAAAAA", ".AAFFFFFAAA", ".AFFFFFFFAA", ".FKKKKKKKFA",
                        ".FFKKFKKFFA", "..FFFfFFF.A", "...FFFFF..."] + suit,
                eyeRows: [],
                colors: ["B": 0x7C8596, "b": 0x555D6C, "A": 0xF2C14E, "a": 0xD19F2E, "F": 0xF7D7B5, "f": 0xE0AE8C, "T": 0x3B82F6],
                // Snaps a salute.
                trick: [.init(armsUp: false, pixels: [(11, 9, "."), (10, 10, "B"), (9, 10, "B"), (8, 10, "B")]),
                        .init(armsUp: false, pixels: [(11, 9, "."), (10, 10, "B"), (9, 10, "B"), (8, 10, "B"), (7, 10, "B"), (6, 10, "B"),
                                                      (5, 10, "F"), (2, 12, "W"), (4, 13, "W")])]),

        // Handler: grey hair, moustache, brown suit, green tie, briefcase.
        Persona(id: "pesto", name: "Pesto", role: "handler", motto: "The package is secure.",
                stand: ["..AAAAAAA..", ".AAAAAAAAA.", ".AFFFFFFFA.", ".AFFFFFFFA.", ".FFFFFFFFF.", ".FFKFFFKFF.",
                        ".FFKFFFKFF.", "..FAAAAAF..", "...FFFFF..."] + suit,
                eyeRows: [5, 6],
                colors: ["B": 0x7A5638, "b": 0x563B25, "A": 0xC4CAD4, "a": 0x9299A6, "F": 0xA8734F, "f": 0x8A5A3B, "T": 0x3FB96B],
                // Hands over the briefcase.
                trick: [.init(armsUp: false, pixels: [(12, 10, "h"), (12, 11, "h"), (13, 9, "h"), (13, 10, "h"), (13, 11, "h"), (13, 12, "h"),
                                                      (14, 9, "h"), (14, 10, "Y"), (14, 11, "h"), (14, 12, "h")]),
                        .init(armsUp: false, pixels: [(11, 9, "B"), (11, 10, "F"), (10, 11, "h"), (10, 12, "h"), (11, 10, "h"), (11, 11, "h"),
                                                      (11, 12, "h"), (11, 13, "h"), (12, 10, "h"), (12, 11, "Y"), (12, 12, "h"), (12, 13, "h")])]),

        // Investigator: fedora, trench coat with the collar up, sunglasses.
        Persona(id: "sleuth", name: "Sleuth", role: "investigator", motto: "Follows the stack trace.",
                stand: ["...AAAAA...", "..AAAAAAA..", "..aaaaaaa..", "AAAAAAAAAAA", ".FFFFFFFFF.", ".FKKKKKKKF.",
                        ".FFKKFKKFF.", "..FFFfFFF..", "..BFFFFFB..",
                        "..BBWTWBB..", ".BBBWTWBBB.", ".FBBBTBBBF.", ".BBBBBBBBB.", "..BBB.BBB..", "..BBB.BBB..", "..bbb.bbb.."],
                eyeRows: [],
                colors: ["B": 0xC9A66B, "b": 0x9C7C45, "A": 0x7A5230, "a": 0x3B2A1A, "F": 0xE8B894, "f": 0xC98F6B, "T": 0x3A4150],
                // Finds a clue.
                trick: [.init(armsUp: false, pixels: [(11, 9, "B"), (11, 10, "h"), (8, 11, "H"), (8, 12, "H"), (8, 13, "H"), (9, 11, "H"),
                                                      (9, 13, "H"), (10, 11, "H"), (10, 12, "H"), (10, 13, "H")]),
                        .init(armsUp: false, pixels: [(11, 9, "B"), (12, 10, "h"), (9, 11, "H"), (9, 12, "H"), (9, 13, "H"), (10, 11, "H"),
                                                      (10, 12, "Z"), (10, 13, "H"), (11, 11, "H"), (11, 12, "H"), (11, 13, "H"),
                                                      (4, 12, "Y"), (5, 12, "Y"), (6, 12, "Y"), (8, 12, "Y")])]),
    ]

    /// The agent a session gets. Stable for the life of the session.
    public static func persona(for sessionID: String) -> Persona {
        personas[tintIndex(for: sessionID, count: personas.count)]
    }

    // MARK: Composition

    static func grid(_ rows: [String]) -> [[Character]] {
        rows.map { row in
            var cells = Array(row)
            if cells.count < width { cells += Array(repeating: ".", count: width - cells.count) }
            return cells
        }
    }

    static func strings(_ grid: [[Character]]) -> [String] { grid.map { String($0) } }

    static func standing(_ p: Persona) -> [[Character]] { grid(p.stand) }

    static func stepping(_ p: Persona) -> [[Character]] {
        var g = standing(p)
        for (i, row) in grid(stepLegs).enumerated() { g[size - stepLegs.count + i] = row }
        return g
    }

    /// Arms raised: the hands leave the sides and go up and out past the shoulders.
    static func armsUp(_ body: [[Character]]) -> [[Character]] {
        var g = body
        for c in [1, 9] where g[11][c] == "F" { g[11][c] = "." }
        for (r, c, pixel) in [(9, 1, Character("B")), (8, 0, "F"), (9, 9, "B"), (8, 10, "F")] where g[r][c] == "." { g[r][c] = pixel }
        return g
    }

    static func blinking(_ body: [[Character]], _ p: Persona) -> [[Character]] {
        var g = body
        for row in p.eyeRows { g[row] = g[row].map { $0 == "K" ? "f" : $0 } }
        return g
    }

    static func overlaying(_ body: [[Character]], _ pixels: [(Int, Int, Character)]) -> [[Character]] {
        var g = body
        for (r, c, pixel) in pixels where r >= 0 && r < size && c >= 0 && c < width { g[r][c] = pixel }
        return g
    }

    static func art(_ rows: [String], row: Int, column: Int) -> [(Int, Int, Character)] {
        rows.enumerated().flatMap { r, line in
            line.enumerated().compactMap { c, pixel in pixel == "." ? nil : (row + r, column + c, pixel) }
        }
    }

    // Props sit to the right of the agent (columns 11–19) and are drawn at the agent's own scale.

    static let cloud = [".WWWWW.", "WWWWWWW", "WWWWWWW", "WWWWWWW", ".WWWWW."]
    static let thinkingProps: [[(Int, Int, Character)]] = [
        art(["W"], row: 9, column: 11),
        art(["W"], row: 9, column: 11) + art(["WW", "WW"], row: 6, column: 12),
        art(["W"], row: 9, column: 11) + art(["WW", "WW"], row: 6, column: 12)
            + art([".WWWWW.", "WWWWWWW", "WKWKWKW", "WWWWWWW", ".WWWWW."], row: 0, column: 13),
        art(["W"], row: 9, column: 11) + art(["WW", "WW"], row: 6, column: 12)
            + art([".WWWWW.", "WWYYYWW", "WWYYYWW", "WWWYWWW", ".WWWWW."], row: 0, column: 13),
    ]

    static let lens = [".HHH.", "HZ..H", "H...H", "H...H", ".HHH."]
    static let searchingProps: [[(Int, Int, Character)]] = [
        art(["BF"], row: 11, column: 10) + art(["h"], row: 10, column: 12) + art(lens, row: 5, column: 13),
        art(["BF"], row: 11, column: 10) + art(["h"], row: 11, column: 12) + art(["h"], row: 10, column: 13)
            + art([".HHH.", "H...H", "H..ZH", "H...H", ".HHH."], row: 5, column: 14),
    ]

    static let runningProps: [[(Int, Int, Character)]] = [
        art(["HHHHHHHHH", "HKKKKKKKH", "HKGKKKKKH", "HKKGKKKKH", "HKGKGGGKH", "HKKKKKKKH", "HHHHHHHHH"], row: 4, column: 11),
        art(["HHHHHHHHH", "HKKKKKKKH", "HKGKKKKKH", "HKKGKKKKH", "HKGKKKKKH", "HKKKKKKKH", "HHHHHHHHH"], row: 4, column: 11),
    ]

    static func wall(courses: Int) -> [(Int, Int, Character)] {
        art((0..<courses).map { $0 % 2 == 0 ? "SsSsSsS" : "sSsSsSs" }, row: size - courses, column: 13)
    }
    static func hammerUp(courses: Int) -> [(Int, Int, Character)] {
        art(["BF"], row: 11, column: 10) + art(["HHHH", "HHHH"], row: 2, column: 11)
            + art(["h", "h", "h", "h", "h", "h", "h"], row: 4, column: 12) + wall(courses: courses)
    }
    static func hammerDown(courses: Int, sparks: [(Int, Int, Character)]) -> [(Int, Int, Character)] {
        let top = size - courses
        return art(["BF"], row: top - 1, column: 10) + art(["hh"], row: top - 1, column: 12)
            + art(["HHH", "HHH", "HHH"], row: top - 3, column: 14) + wall(courses: courses)
            + sparks.map { ($0.0 + top, $0.1, $0.2) }
    }
    static let buildingProps: [[(Int, Int, Character)]] = [
        hammerUp(courses: 4),
        hammerDown(courses: 4, sparks: [(-5, 13, "Y"), (-6, 15, "Y"), (-5, 18, "Y")]),
        hammerUp(courses: 5),
        hammerDown(courses: 5, sparks: [(-6, 13, "Y"), (-5, 16, "Y"), (-7, 18, "Y"), (-4, 18, "Y")]),
    ]

    static let bang = art(["YY", "YY", "YY", "YY", "YY", "YY", "..", "YY", "YY"], row: 2, column: 14)
    static let approvalProps: [[(Int, Int, Character)]] = [
        art(["B"], row: 10, column: 10) + art(["F"], row: 9, column: 11) + bang,
        art(["BF"], row: 11, column: 10) + bang,
    ]

    static let question = [".ZZZ.", "ZZ.ZZ", "...ZZ", "..ZZ.", "..Z..", ".....", "..Z.."]
    static let waitingProps: [[(Int, Int, Character)]] = [
        art(question, row: 3, column: 13),
        art(question.map { $0.replacingOccurrences(of: "Z", with: "W") }, row: 3, column: 13),
    ]

    static let pole = art(Array(repeating: "h", count: 10), row: 1, column: 13)
    static let goal = art(["SsSsSs", "sSsSsS", "SsSsSs", "sSsSsS", "SsSsSs"], row: 11, column: 12)
    static let doneProps: [[(Int, Int, Character)]] = [
        pole + art(["GGGGG", "GGGGG", "GGGGG"], row: 1, column: 14) + goal,
        pole + art(["GGGG.", ".GGGG", "GGGG."], row: 1, column: 14) + goal,
    ]

    static let errorProps: [[(Int, Int, Character)]] = [
        art(["R...R", ".R.R.", "..R..", ".R.R.", "R...R"], row: 3, column: 13) + [(10, 12, "R"), (12, 17, "R")],
        art(["R...R", ".R.R.", "..R..", ".R.R.", "R...R"], row: 4, column: 14) + [(2, 12, "R"), (11, 13, "R"), (13, 18, "R")],
    ]

    /// Animation frames for a session state, drawn for a given agent.
    /// While working, `work` picks the animation: thinking, searching, running a command, or building.
    public static func frames(for state: SessionState, persona p: Persona, work: WorkKind = .building) -> [[String]] {
        let stand = standing(p)
        func on(_ body: [[Character]], _ prop: [(Int, Int, Character)]) -> [String] { strings(overlaying(body, prop)) }
        switch state {
        case .working:
            switch work {
            case .building: return buildingProps.map { on(stand, $0) }
            case .thinking: return thinkingProps.map { on(stand, $0) }
            case .searching: return searchingProps.map { on(stand, $0) }
            case .running: return runningProps.map { on(stand, $0) }
            }
        case .needsApproval:
            return approvalProps.map { on(stand, $0) }
        case .waitingForInput:
            return [on(stand, waitingProps[0]), on(blinking(stand, p), waitingProps[1])]
        case .done:
            return [on(armsUp(stand), doneProps[0]), on(stand, doneProps[1])]
        case .error:
            return [on(stand, errorProps[0]), on(p.eyeRows.isEmpty ? armsUp(stand) : blinking(stand, p), errorProps[1])]
        case .idle:
            return walkFrames(persona: p)
        }
    }

    /// Two-step walk cycle. The view moves and mirrors the agent; these are just the legs.
    public static func walkFrames(persona p: Persona) -> [[String]] {
        [strings(standing(p)), strings(stepping(p))]
    }

    /// The agent's party trick, shown when the pointer is on it.
    public static func trickFrames(persona p: Persona) -> [[String]] {
        p.trick.map { frame in
            strings(overlaying(frame.armsUp ? armsUp(standing(p)) : standing(p), frame.pixels))
        }
    }
}
