import Foundation

/// One of the flock: an original 8-bit raven with its own look, colours, persona, and party trick.
///
/// A raven is drawn once, standing, in an 11-pixel-wide column of a 16×16 grid, facing right. Everything
/// else (walking, wings up, blinking, and the props for each session state) is composed from that
/// drawing, so every raven can show every state. Plumage is a blue-black with a lighter sheen so it
/// stays visible on the panel's black background.
///
/// Pixels: `B` plumage, `b` its shade, `A` accessory (hat, hood, scarf), `a` its shade, `F` sheen,
/// `f` beak, `T` legs, plus the shared colours `W` white, `K` dark, `Y` gold, `R` red, `G` green,
/// `Z` pale blue, `H` metal, `h` wood, `S`/`s` brick.
public struct Persona: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let role: String
    public let motto: String
    /// 16 rows × 11 columns.
    public let stand: [String]
    /// Rows holding the eyes, for blinking; empty for a raven whose eye is hidden (monocle, glowing eye).
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
    /// Colours shared by every raven and prop.
    public static let sharedColors: [Character: UInt32] = [
        "W": 0xFFFFFF, "K": 0x141414, "H": 0xCCCCCC, "h": 0xB8804D, "S": 0xDB735C, "s": 0xB35445,
        "Y": 0xFFD633, "R": 0xFF544D, "G": 0x52DB6B, "Z": 0xB3DBFF,
    ]

    /// Width of a raven's own drawing; props go to the right of it.
    public static let bodyWidth = 11

    /// Feet for the second step of the walk (replaces the bottom three rows, shared by every raven).
    static let stepLegs = ["...bbbbb...", "...T...T...", "..TT...TT.."]

    public static let personas: [Persona] = [
        Persona(id: "huginn", name: "Huginn", role: "strategist", motto: "Thinks it through, then moves.",
                stand: ["...AAAA....", "..aaaaaa...", "..BBBBBB...", "..BFBBBBB..", "..BBBBHKH..", "..BBBBBBff.", "..BBBBBBf..", "...BBBBB...", "..BBBBBBB..", ".BFBBBBBBB.", ".BBFBBBBBB.", "bBBBBBBBBb.", "b.bBBBBBb..", "...bbbbb...", "....T.T....", "...TT.TT..."],
                eyeRows: [],
                colors: ["B": 0x4B5A82, "b": 0x2E3852, "A": 0xB23A48, "a": 0xE8B84A, "F": 0x8FA3D0, "f": 0xA7AFBF, "T": 0x7A8291],
                trick: [.init(armsUp: false, pixels: [(0, 12, "Y"), (1, 11, "Y"), (1, 12, "Y"), (1, 13, "Y"), (2, 12, "Y"), (3, 12, "H")]),
                        .init(armsUp: false, pixels: [(0, 12, "Y"), (1, 11, "Y"), (1, 12, "W"), (1, 13, "Y"), (2, 12, "Y"), (3, 12, "H"), (0, 10, "W"), (0, 14, "W"), (2, 10, "W"), (2, 14, "W")])]),

        Persona(id: "muninn", name: "Muninn", role: "archivist", motto: "Never forgets a file.",
                stand: ["...........", "...BBBB....", "..BBBBBB...", "..BFBBBBB..", "..BBBHWKH..", "..BBBBBBff.", "..BBBBBBf..", "..AAAAAA...", "..BBBBBBB..", ".BFBBBBBBB.", ".BBFBBBBBB.", "bBBBBBBBBb.", "b.bBBBBBb..", "...bbbbb...", "....T.T....", "...TT.TT..."],
                eyeRows: [4],
                colors: ["B": 0x4E4A72, "b": 0x312E4B, "A": 0x2BB3A3, "a": 0x1F8377, "F": 0x9A93C8, "f": 0xA7AFBF, "T": 0x7A8291],
                trick: [.init(armsUp: false, pixels: [(8, 10, "B"), (9, 11, "W"), (9, 12, "W"), (9, 13, "W"), (10, 11, "H"), (10, 12, "W"), (10, 13, "H"), (11, 11, "W"), (11, 12, "W"), (11, 13, "W")]),
                        .init(armsUp: false, pixels: [(8, 10, "B"), (9, 11, "W"), (9, 12, "W"), (9, 13, "W"), (9, 14, "W"), (10, 11, "H"), (10, 12, "H"), (10, 13, "W"), (10, 14, "H"), (11, 11, "W"), (11, 12, "W"), (11, 13, "W"), (11, 14, "W"), (7, 13, "Y")])]),

        Persona(id: "quill", name: "Quill", role: "scribe", motto: "Writes it clean the first time.",
                stand: ["...AAAA....", "..AAABBB...", "..BBBBBB...", "..BFBBBBB..", "..BBBBWKB..", "..BBBBBBff.", "..BBBBBBf..", "...BBBBB...", "..BBBBBBB..", ".BFBBBBBBB.", ".BBFBBBBBB.", "bBBBBBBBBb.", "b.bBBBBBb..", "...bbbbb...", "....T.T....", "...TT.TT..."],
                eyeRows: [4],
                colors: ["B": 0x3F5F6E, "b": 0x263D48, "A": 0xD9534F, "a": 0xA33A37, "F": 0x8CB4C4, "f": 0xA7AFBF, "T": 0x7A8291],
                trick: [.init(armsUp: false, pixels: [(8, 10, "B"), (7, 11, "W"), (6, 12, "W"), (5, 13, "W"), (8, 11, "K"), (9, 12, "H"), (9, 13, "H")]),
                        .init(armsUp: false, pixels: [(8, 10, "B"), (7, 12, "W"), (6, 13, "W"), (5, 14, "W"), (8, 12, "K"), (9, 12, "H"), (9, 13, "H"), (9, 14, "H")])]),

        Persona(id: "pip", name: "Pip", role: "scout", motto: "Flies ahead to find it.",
                stand: ["...aaaa....", "..aBBBBa...", "..HZHHZH...", "..BFBBBBB..", "..BBBBWKB..", "..BBBBBBff.", "..BBBBBBf..", "...BBBBB...", "..BBBBBBB..", ".BFBBBBBBB.", ".BBFBBBBBB.", "bBBBBBBBBb.", "b.bBBBBBb..", "...bbbbb...", "....T.T....", "...TT.TT..."],
                eyeRows: [4],
                colors: ["B": 0x505A66, "b": 0x343C46, "A": 0x8B5A2B, "a": 0x8B5A2B, "F": 0x9AA6B4, "f": 0xA7AFBF, "T": 0x7A8291],
                trick: [.init(armsUp: true, pixels: [(4, 12, "Z"), (4, 13, "Z"), (6, 13, "Z"), (6, 14, "Z"), (8, 12, "Z"), (8, 13, "Z")]),
                        .init(armsUp: true, pixels: [(3, 13, "Z"), (3, 14, "Z"), (5, 12, "Z"), (5, 13, "Z"), (7, 13, "Z"), (7, 14, "Z")])]),

        Persona(id: "nyx", name: "Nyx", role: "night watch", motto: "Nothing gets past the watch.",
                stand: ["...AAAA....", "..AAAAAA...", ".AABBBBAA..", ".ABFBBBBBA.", "..BBBBYKB..", "..BBBBBBff.", "..BBBBBBf..", "...BBBBB...", "..BBBBBBB..", ".BFBBBBBBB.", ".BBFBBBBBB.", "bBBBBBBBBb.", "b.bBBBBBb..", "...bbbbb...", "....T.T....", "...TT.TT..."],
                eyeRows: [],
                colors: ["B": 0x3A3F5C, "b": 0x24283B, "A": 0x6B3FA0, "a": 0x4A2B70, "F": 0x8088B8, "f": 0xA7AFBF, "T": 0x7A8291],
                trick: [.init(armsUp: false, pixels: [(8, 10, "B"), (9, 11, "H"), (9, 12, "H"), (9, 13, "H"), (10, 11, "H"), (10, 12, "Y"), (10, 13, "H"), (11, 11, "H"), (11, 12, "H"), (11, 13, "H")]),
                        .init(armsUp: false, pixels: [(8, 10, "B"), (9, 11, "H"), (9, 12, "H"), (9, 13, "H"), (10, 11, "H"), (10, 12, "W"), (10, 13, "H"), (11, 11, "H"), (11, 12, "H"), (11, 13, "H"), (9, 14, "Y"), (11, 14, "Y"), (10, 15, "Y")])]),

        Persona(id: "tinker", name: "Tinker", role: "tinkerer", motto: "Every problem is a puzzle box.",
                stand: ["..AAAAA....", ".aaaaaaa...", "..BBBBBB...", "..BFBBBBB..", "..BBBBWKB..", "..BBBBBBff.", "..BBBBBBf..", "...BBBBB...", "..BBBBBBB..", ".BFBBBBBBB.", ".BBFBBBBBB.", "bBBBBBBBBb.", "b.bBBBBBb..", "...bbbbb...", "....T.T....", "...TT.TT..."],
                eyeRows: [4],
                colors: ["B": 0x4A5560, "b": 0x2E363F, "A": 0xF2C230, "a": 0xC99A1E, "F": 0x93A1AE, "f": 0xA7AFBF, "T": 0x7A8291],
                trick: [.init(armsUp: false, pixels: [(8, 10, "B"), (8, 11, "H"), (8, 12, "H"), (7, 13, "H"), (9, 13, "H")]),
                        .init(armsUp: false, pixels: [(8, 10, "B"), (8, 11, "H"), (7, 12, "H"), (6, 12, "H"), (6, 13, "H"), (5, 11, "Y"), (7, 14, "Y")])]),
    ]

    /// The raven a session gets. Stable for the life of the session.
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

    /// Wings raised: the wing edges lift out past the shoulders on both sides.
    static func armsUp(_ body: [[Character]]) -> [[Character]] {
        var g = body
        for (r, c) in [(6, 0), (7, 0), (8, 0), (8, 1), (6, 10), (7, 10), (8, 10), (8, 9)] where g[r][c] == "." { g[r][c] = "B" }
        return g
    }

    static func blinking(_ body: [[Character]], _ p: Persona) -> [[Character]] {
        var g = body
        for row in p.eyeRows { g[row] = g[row].map { $0 == "W" || $0 == "K" ? "b" : $0 } }
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

    // Props sit to the right of the raven (columns 11–19) and are drawn at the raven's own scale.

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

    /// Animation frames for a session state, drawn for a given raven.
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

    /// Two-step walk cycle. The view moves and mirrors the raven; these are just the feet.
    public static func walkFrames(persona p: Persona) -> [[String]] {
        [strings(standing(p)), strings(stepping(p))]
    }

    /// The raven's party trick, shown when the pointer is on it.
    public static func trickFrames(persona p: Persona) -> [[String]] {
        p.trick.map { frame in
            strings(overlaying(frame.armsUp ? armsUp(standing(p)) : standing(p), frame.pixels))
        }
    }
}
