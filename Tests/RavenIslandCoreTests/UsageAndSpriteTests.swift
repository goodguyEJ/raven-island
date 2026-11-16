import Foundation
import Testing
@testable import RavenIslandCore

@Suite struct UsageTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func payload(_ json: String) throws -> JSONValue { try #require(JSONValue.parse(Data(json.utf8))) }

    @Test func parsesStatusLineUsage() throws {
        let p = try payload(#"{"session_id":"s","model":{"id":"x"},"rate_limits":{"five_hour":{"used_percentage":42.5,"resets_at":1800007200},"seven_day":{"used_percentage":118,"resets_at":1800300000}}}"#)
        let u = try #require(UsageSnapshot(statusLine: p, now: now))
        #expect(u.fiveHour == UsageWindow(usedPercent: 42.5, resetsAt: Date(timeIntervalSince1970: 1_800_007_200)))
        #expect(u.sevenDay?.usedPercent == 100)   // clamped
        #expect(u.updatedAt == now)
    }

    @Test func missingUsageIsNil() throws {
        #expect(UsageSnapshot(statusLine: try payload(#"{"session_id":"s"}"#)) == nil)
        #expect(UsageSnapshot(statusLine: try payload(#"{"rate_limits":{}}"#)) == nil)
        #expect(UsageSnapshot(statusLine: try payload(#"{"rate_limits":{"spend_limit":{"used_percentage":3}}}"#)) == nil)
    }

    @Test func partialReportsMergeAndExpiredWindowsDrop() throws {
        let both = UsageSnapshot(fiveHour: UsageWindow(usedPercent: 40, resetsAt: now + 600),
                                 sevenDay: UsageWindow(usedPercent: 10, resetsAt: now + 90_000), updatedAt: now)
        let onlyFive = try #require(UsageSnapshot(statusLine: try payload(#"{"rate_limits":{"five_hour":{"used_percentage":55}}}"#), now: now + 60))
        let merged = both.merging(onlyFive)
        #expect(merged.fiveHour?.usedPercent == 55)
        #expect(merged.sevenDay?.usedPercent == 10)

        let later = both.current(now: now + 601)   // 5-hour window has reset
        #expect(later.fiveHour == nil)
        #expect(later.sevenDay != nil)
        #expect(both.current(now: now + 100_000).isEmpty)
    }

    @Test func levelsAndCountdowns() {
        #expect(UsageSnapshot.level(10) == .normal)
        #expect(UsageSnapshot.level(75) == .warning)
        #expect(UsageSnapshot.level(90) == .critical)
        #expect(UsageSnapshot.countdown(to: now + 20, now: now) == "1m")
        #expect(UsageSnapshot.countdown(to: now + 12 * 60, now: now) == "12m")
        #expect(UsageSnapshot.countdown(to: now + 2 * 3600 + 13 * 60, now: now) == "2h 13m")
        #expect(UsageSnapshot.countdown(to: now + 3 * 86_400 + 4 * 3600 + 5, now: now) == "3d 4h")
        #expect(UsageSnapshot.countdown(to: now - 50, now: now) == "1m")
    }
}

@Suite struct PixelSpriteTests {
    static let allowed = Set(".BbAaFfTWKHhSsYRGZP")

    func wellFormed(_ frames: [[String]], _ what: String) {
        #expect(frames.count >= 2, "\(what) should animate")
        for (i, frame) in frames.enumerated() {
            #expect(frame.count == PixelSprites.size, "\(what) frame \(i) has \(frame.count) rows")
            for (r, row) in frame.enumerated() {
                #expect(row.count == PixelSprites.width, "\(what) frame \(i) row \(r) is \(row.count) wide")
                #expect(Set(row).isSubset(of: Self.allowed), "\(what) frame \(i) row \(r) has an unknown pixel")
            }
        }
        #expect(Set(frames.map { $0.joined() }).count == frames.count, "\(what) frames should differ")
    }

    @Test func thereIsAFlockOfDistinctRavens() {
        let crew = PixelSprites.personas
        #expect(crew.count >= 5)
        #expect(Set(crew.map(\.id)).count == crew.count)
        #expect(Set(crew.map(\.name)).count == crew.count)
        #expect(Set(crew.map { $0.stand.joined() }).count == crew.count)        // each one is drawn differently
        #expect(Set(crew.map { $0.colors["B"] }).count == crew.count)           // and coloured differently
        for p in crew {
            #expect(p.stand.count == PixelSprites.size, "\(p.id) standing art must be 16 rows")
            #expect(p.stand.allSatisfy { $0.count == PixelSprites.bodyWidth }, "\(p.id) standing rows must be 11 wide")
            // Props start at column 11, so a raven's own drawing must stay left of that.
            #expect(PixelSprites.bodyWidth == 11)
            #expect(!p.motto.isEmpty && !p.role.isEmpty)
            for key in "BbAaFfT" { #expect(p.colors[key] != nil, "\(p.id) is missing colour \(key)") }
            // Every raven has a feathered body below the head, and feet on the floor.
            #expect(p.stand[10].contains("B") && p.stand[15].contains("T"))
        }
    }

    @Test func everyCharacterCanShowEveryState() {
        for p in PixelSprites.personas {
            for state in SessionState.allCases {
                wellFormed(PixelSprites.frames(for: state, persona: p), "\(p.id) \(state)")
                #expect(PixelSprites.frameDuration(for: state) > 0)
            }
            wellFormed(PixelSprites.walkFrames(persona: p), "\(p.id) walk")
            wellFormed(PixelSprites.trickFrames(persona: p), "\(p.id) trick")
            // The character itself is recognisable in every state: its top rows are untouched by props.
            let standing = PixelSprites.walkFrames(persona: p)[0]
            let working = PixelSprites.frames(for: .working, persona: p)[1]
            #expect(working[2].prefix(10) == standing[2].prefix(10))
        }
    }

    @Test func stateFramesCarryTheirProps() {
        let p = PixelSprites.personas[1]
        #expect(PixelSprites.frames(for: .working, persona: p).contains { $0.joined().contains("H") })     // hammer
        #expect(PixelSprites.frames(for: .working, persona: p).allSatisfy { $0.joined().contains("S") })   // wall
        #expect(PixelSprites.frames(for: .needsApproval, persona: p)[0].joined().contains("Y"))             // "!"
        #expect(PixelSprites.frames(for: .waitingForInput, persona: p)[0].joined().contains("Z"))           // "?"
        #expect(PixelSprites.frames(for: .done, persona: p)[0].joined().contains("G"))                      // flag
        #expect(PixelSprites.frames(for: .error, persona: p)[0].joined().contains("R"))                     // sparks
        #expect(!PixelSprites.frames(for: .idle, persona: p)[0].joined().contains("S"))                     // just walking
    }

    @Test func propsAreDrawnAtTheRavensScale() {
        let p = PixelSprites.personas[0]
        func propPixels(_ frame: [String]) -> Int {
            frame.reduce(0) { $0 + $1.dropFirst(PixelSprites.bodyWidth).filter { $0 != "." }.count }
        }
        func tallest(_ state: SessionState, _ work: WorkKind = .building) -> Int {
            PixelSprites.frames(for: state, persona: p, work: work).map(propPixels).max() ?? 0
        }
        #expect(tallest(.working, .thinking) >= 30)
        #expect(tallest(.working, .running) >= 40)
        #expect(tallest(.working, .searching) >= 12)
        #expect(tallest(.working, .building) >= 40)
        #expect(tallest(.done) >= 40)
        #expect(tallest(.needsApproval) >= 14)
        #expect(tallest(.waitingForInput) >= 10)
    }

    @Test func eachKindOfWorkHasItsOwnAnimation() {
        for p in PixelSprites.personas {
            var seen = Set<String>()
            for kind in WorkKind.allCases {
                let frames = PixelSprites.frames(for: .working, persona: p, work: kind)
                wellFormed(frames, "\(p.id) working/\(kind)")
                seen.insert(frames.map { $0.joined() }.joined())
            }
            #expect(seen.count == WorkKind.allCases.count)
        }
        let p = PixelSprites.personas[0]
        #expect(PixelSprites.frames(for: .working, persona: p, work: .building)[0].joined().contains("S"))    // wall
        #expect(!PixelSprites.frames(for: .working, persona: p, work: .thinking)[0].joined().contains("S"))
        #expect(PixelSprites.frames(for: .working, persona: p, work: .running)[0].joined().contains("G"))     // prompt
        #expect(PixelSprites.frames(for: .working, persona: p, work: .searching)[0].joined().contains("H"))   // lens
    }

    @Test func toolsMapToKindsOfWork() {
        #expect(WorkKind.forTool("Grep") == .searching)
        #expect(WorkKind.forTool("Read") == .searching)
        #expect(WorkKind.forTool("WebFetch") == .searching)
        #expect(WorkKind.forTool("Bash") == .running)
        #expect(WorkKind.forTool("Edit") == .building)
        #expect(WorkKind.forTool("Write") == .building)
        #expect(WorkKind.forTool("mcp__jira__searchIssues") == .searching)
        #expect(WorkKind.forTool("mcp__jira__createIssue") == .building)
        #expect(WorkKind.forTool("SomethingNew") == .building)
    }

    @Test func sessionTracksWhatItIsDoing() {
        var store = SessionStore()
        store.apply(event("UserPromptSubmit", ["prompt": "fix it"]))
        #expect(store.sessions["s1"]?.workKind == .thinking)
        store.apply(event("PreToolUse", ["tool_name": "Grep", "tool_input": .object(["pattern": "login"])]))
        #expect(store.sessions["s1"]?.workKind == .searching)
        store.apply(event("PostToolUse", ["tool_name": "Grep"]))
        #expect(store.sessions["s1"]?.workKind == .thinking)       // deciding what to do next
        store.apply(event("PreToolUse", ["tool_name": "Bash", "tool_input": .object(["command": "npm test"])]))
        #expect(store.sessions["s1"]?.workKind == .running)
        store.apply(event("PreToolUse", ["tool_name": "Edit", "tool_input": .object(["file_path": "/a.ts"])]))
        #expect(store.sessions["s1"]?.workKind == .building)
    }

    @Test func characterIsStablePerSession() {
        let a = PixelSprites.persona(for: "b2fe5265-6693").id
        #expect(a == PixelSprites.persona(for: "b2fe5265-6693").id)
        let spread = Set((0..<60).map { PixelSprites.persona(for: "session-\($0)").id })
        #expect(spread.count >= 4)   // sessions don't all get the same character
        #expect(PixelSprites.tintIndex(for: "anything", count: 0) == 0)
    }

    func body(_ frame: [String]) -> String { frame.map { String($0.prefix(PixelSprites.bodyWidth)) }.joined() }

    @Test func ravensMoveInEveryState() {
        for p in PixelSprites.personas {
            for state in SessionState.allCases {
                let kinds: [WorkKind] = state == .working ? WorkKind.allCases : [.building]
                for kind in kinds {
                    let frames = PixelSprites.frames(for: state, persona: p, work: kind)
                    #expect(Set(frames.map(body)).count >= 2, "\(p.id) \(state)/\(kind) body never moves")
                }
            }
            #expect(Set(PixelSprites.walkFrames(persona: p).map(body)).count >= 2)
        }
    }

    @Test func ravensBlinkInEveryState() {
        for p in PixelSprites.personas where !p.eyeRows.isEmpty {
            let shut = PixelSprites.blinking(PixelSprites.standing(p), p)
            func blinks(_ frames: [[String]]) -> Bool {
                frames.contains { f in
                    p.eyeRows.allSatisfy { String(f[$0].prefix(PixelSprites.bodyWidth)) == String(shut[$0].prefix(PixelSprites.bodyWidth)) }
                }
            }
            for state in SessionState.allCases {
                let kinds: [WorkKind] = state == .working ? WorkKind.allCases : [.building]
                for kind in kinds {
                    #expect(blinks(PixelSprites.frames(for: state, persona: p, work: kind)), "\(p.id) \(state)/\(kind) never blinks")
                }
            }
            #expect(blinks(PixelSprites.walkFrames(persona: p)), "\(p.id) never blinks while walking")
        }
    }

    @Test func frameDurationsUnchanged() {
        #expect(PixelSprites.frameDuration(for: .working) == 0.22)
        #expect(PixelSprites.frameDuration(for: .needsApproval) == 0.3)
        #expect(PixelSprites.frameDuration(for: .waitingForInput) == 0.45)
        #expect(PixelSprites.frameDuration(for: .done) == 0.45)
        #expect(PixelSprites.frameDuration(for: .error) == 0.35)
        #expect(PixelSprites.frameDuration(for: .idle) == 0.25)
    }

    @Test func listeningRavenWearsHeadphones() {
        for p in PixelSprites.personas {
            let playing = PixelSprites.listeningFrames(persona: p, playing: true)
            wellFormed(playing, "\(p.id) listening")
            #expect(playing.count >= 4)
            #expect(playing.allSatisfy { $0.joined().contains("P") })
            #expect(Set(playing.map(body)).count >= 2)
            let paused = PixelSprites.listeningFrames(persona: p, playing: false)
            #expect(paused.count == 1); #expect(paused[0].joined().contains("P"))
            #expect(paused[0] != PixelSprites.walkFrames(persona: p)[0])
        }
    }

    @Test func everyFrameCanWearHeadphones() {
        for p in PixelSprites.personas {
            for state in SessionState.allCases {
                let kinds: [WorkKind] = state == .working ? WorkKind.allCases : [.building]
                for kind in kinds {
                    let plain = PixelSprites.frames(for: state, persona: p, work: kind)
                    let wearing = PixelSprites.frames(for: state, persona: p, work: kind, headphones: true)
                    wellFormed(wearing, "\(p.id) \(state)/\(kind) with headphones")
                    #expect(wearing.count == plain.count)
                    #expect(wearing.allSatisfy { $0.joined().contains("P") }, "\(p.id) \(state)/\(kind) lost its headphones")
                    #expect(Set(wearing.map(body)).count >= 2)
                }
            }
            let walk = PixelSprites.walkFrames(persona: p, headphones: true)
            wellFormed(walk, "\(p.id) walking with headphones")
            #expect(walk.allSatisfy { $0.joined().contains("P") })
            let trick = PixelSprites.trickFrames(persona: p, headphones: true)
            #expect(trick.allSatisfy { $0.joined().contains("P") })
            #expect(PixelSprites.frames(for: .working, persona: p) == PixelSprites.frames(for: .working, persona: p, headphones: false))
        }
    }
}
