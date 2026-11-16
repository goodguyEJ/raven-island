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
        "Y": 0xFFD633, "R": 0xFF544D, "G": 0x52DB6B, "Z": 0xB3DBFF, "P": 0x5EC8E5,
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

    /// Wings raised: the wing edges lift out past the shoulders on both sides, and the folded wing
    /// along the body (its edge and sheen) goes, or the raven would seem to have a third wing.
    static func armsUp(_ body: [[Character]]) -> [[Character]] {
        var g = body
        for (r, c) in [(6, 0), (7, 0), (8, 0), (8, 1), (6, 10), (7, 10), (8, 10), (8, 9)] where g[r][c] == "." { g[r][c] = "B" }
        // (11, 9) stays: a prop's arm (the hammer) joins the body there.
        for (r, c) in [(9, 1), (10, 1), (11, 0), (11, 1), (12, 0), (9, 9), (10, 9)] { g[r][c] = "." }
        for (r, c) in [(9, 2), (10, 3)] where g[r][c] == "F" { g[r][c] = "B" }
        return g
    }

    static func blinking(_ body: [[Character]], _ p: Persona) -> [[Character]] {
        var g = body
        for row in p.eyeRows { g[row] = g[row].map { $0 == "W" || $0 == "K" ? "b" : $0 } }
        return g
    }

    /// Moves part of the raven's own columns, leaving the prop columns alone.
    static func shifted(_ body: [[Character]], rows: ClosedRange<Int>, down: Int = 0, right: Int = 0) -> [[Character]] {
        var g = body
        for r in rows { for c in 0..<bodyWidth { g[r][c] = "." } }
        for r in rows {
            for c in 0..<bodyWidth where body[r][c] != "." {
                let (nr, nc) = (r + down, c + right)
                if nr >= 0, nr < size, nc >= 0, nc < bodyWidth { g[nr][nc] = body[r][c] }
            }
        }
        return g
    }

    /// Breathing: head and chest sink one pixel over the feet.
    static func breathing(_ body: [[Character]]) -> [[Character]] { shifted(body, rows: 0...12, down: 1) }
    static func headForward(_ body: [[Character]]) -> [[Character]] { shifted(body, rows: 0...6, right: 1) }
    static func headBack(_ body: [[Character]]) -> [[Character]] { shifted(body, rows: 0...6, right: -1) }
    static func wingToChin(_ body: [[Character]]) -> [[Character]] { overlaying(body, [(7, 8, "F"), (7, 9, "B"), (8, 9, "B")]) }
    static func footUp(_ body: [[Character]]) -> [[Character]] {
        overlaying(body, [(14, 7, "T"), (15, 6, "."), (15, 7, ".")])
    }
    /// Legs tucked as if just off the ground.
    static func hopping(_ body: [[Character]]) -> [[Character]] {
        overlaying(body, [(15, 3, "."), (15, 4, "."), (15, 6, "."), (15, 7, "."), (14, 3, "T"), (14, 7, "T")])
    }

    /// Two passes over a prop cycle, the second with the breath in, so every frame stays distinct.
    /// `pose` shapes the body for each prop frame; `blinkAt` closes the eyes on one frame of the first pass.
    static func alive(_ p: Persona, _ props: [[(Int, Int, Character)]], blinkAt: Int? = nil, wearing: Bool = false,
                      pose: (Int, [[Character]]) -> [[Character]] = { $1 }) -> [[String]] {
        let stand = wearing ? headphones(standing(p)) : standing(p)
        let first = props.indices.map { i -> [String] in
            let body = pose(i, stand)
            return strings(overlaying(i == blinkAt ? blinking(body, p) : body, props[i]))
        }
        let sunk = props.map { $0.map { r, c, px in c < bodyWidth ? (r + 1, c, px) : (r, c, px) } }
        let second = props.indices.map { strings(overlaying(breathing(pose($0, stand)), sunk[$0])) }
        return first + second
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
    /// `headphones`: music is playing, so the raven wears them over whatever it is doing.
    public static func frames(for state: SessionState, persona p: Persona, work: WorkKind = .building,
                              headphones: Bool = false) -> [[String]] {
        switch state {
        case .working:
            switch work {
            case .building: return alive(p, buildingProps, blinkAt: 1, wearing: headphones) { i, b in i % 2 == 0 ? armsUp(b) : b }
            case .thinking: return alive(p, thinkingProps, blinkAt: 1, wearing: headphones) { i, b in wingToChin(i < 2 ? b : headBack(b)) }
            case .searching: return alive(p, searchingProps, blinkAt: 0, wearing: headphones) { i, b in i == 1 ? headForward(b) : b }
            case .running: return alive(p, runningProps, blinkAt: 0, wearing: headphones) { i, b in i == 1 ? footUp(b) : b }
            }
        case .needsApproval:
            return alive(p, approvalProps, blinkAt: 0, wearing: headphones)
        case .waitingForInput:
            return alive(p, waitingProps, blinkAt: 1, wearing: headphones) { i, b in i == 0 ? headBack(b) : b }
        case .done:
            return alive(p, doneProps, blinkAt: 1, wearing: headphones) { i, b in i == 0 ? hopping(armsUp(b)) : b }
        case .error:
            return alive(p, errorProps, blinkAt: 0, wearing: headphones) { i, b in i == 1 ? (p.eyeRows.isEmpty ? armsUp(b) : blinking(b, p)) : b }
        case .idle:
            return walkFrames(persona: p, headphones: headphones)
        }
    }

    /// Walk cycle with a bounce, a head bob, and one blink. The view moves and mirrors the raven.
    public static func walkFrames(persona p: Persona, headphones wearing: Bool = false) -> [[String]] {
        let (stand, step) = wearing ? (headphones(standing(p)), headphones(stepping(p))) : (standing(p), stepping(p))
        return [stand, step, breathing(stand), breathing(step), headForward(stand), headForward(step),
                p.eyeRows.isEmpty ? footUp(stand) : blinking(stand, p), breathing(headForward(step))].map(strings)
    }

    /// Headphones seen side-on, as the ravens face right: one cup over the ear just behind the eye,
    /// and the band up over the crown, hidden wherever a hat or goggles sit on top.
    static func headphones(_ body: [[Character]]) -> [[Character]] {
        var g = overlaying(body, [(3, 3, "P"), (3, 4, "P"), (4, 3, "P"), (4, 4, "P")])
        for (r, c) in [(1, 4), (2, 4)] where "BbF.".contains(g[r][c]) { g[r][c] = "P" }
        return g
    }

    static let note = [".WW", ".W.", "WW."]

    /// Playing: a head bob with a note rising beside it. Paused: one still frame, headphones on.
    public static func listeningFrames(persona p: Persona, playing: Bool) -> [[String]] {
        let wearing = headphones(standing(p))
        guard playing else { return [strings(wearing)] }
        let bob = breathing(wearing)
        return [strings(wearing), strings(bob),
                strings(overlaying(wearing, art(note, row: 6, column: 11))),
                strings(overlaying(bob, art(note, row: 2, column: 12)))]
    }

    /// Turned to face us: the back half of the side-on drawing (crown, hat, folded wing) mirrored
    /// across the middle column, then two eyes and a beak seen head-on. A glowing eye stays gold.
    static func facing(_ p: Persona) -> [[Character]] {
        var g = standing(p)
        let middle = bodyWidth / 2
        for r in 0..<size { for c in (middle + 1)..<bodyWidth { g[r][c] = g[r][bodyWidth - 1 - c] } }
        let eye: Character = p.stand[4].contains("Y") ? "Y" : "W"
        return overlaying(g, [(4, 3, eye), (4, 4, "K"), (4, 6, "K"), (4, 7, eye),
                              (5, 4, "f"), (5, 5, "f"), (5, 6, "f"), (6, 5, "f")])
    }

    /// Headphones seen head-on: a cup either side of the head and the band over the crown.
    static func frontHeadphones(_ body: [[Character]]) -> [[Character]] {
        var g = overlaying(body, [(3, 1, "P"), (4, 1, "P"), (3, 9, "P"), (4, 9, "P")])
        for (r, c) in [(2, 2), (2, 8)] where "BbF.".contains(g[r][c]) { g[r][c] = "P" }
        return g
    }

    /// Facing us, then one wing raised and out: the view plays them as a wave.
    public static func waveFrames(persona p: Persona, headphones wearing: Bool = false) -> [[String]] {
        let front = wearing ? frontHeadphones(facing(p)) : facing(p)
        var lowered = front
        for (r, c) in [(9, 9), (10, 9), (11, 9), (11, 10), (12, 10)] { lowered[r][c] = "." }
        let up = overlaying(lowered, [(8, 9, "B"), (7, 10, "B"), (6, 10, "B"), (5, 10, "B"), (4, 10, "F")])
        let out = overlaying(lowered, [(8, 9, "B"), (7, 10, "B"), (6, 11, "B"), (5, 11, "B"), (4, 12, "F")])
        return [front, up, out].map(strings)
    }

    /// The raven's party trick, shown when the pointer is on it.
    public static func trickFrames(persona p: Persona, headphones wearing: Bool = false) -> [[String]] {
        let stand = wearing ? headphones(standing(p)) : standing(p)
        return p.trick.map { frame in
            strings(overlaying(frame.armsUp ? armsUp(stand) : stand, frame.pixels))
        }
    }
}
