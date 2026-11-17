import AppKit
import SwiftUI
import RavenIslandCore

/// `Raven Island --snapshot DIR` renders the panel's states to PNG files with sample data,
/// so the design can be reviewed without a live session.
@MainActor
enum Snapshot {
    static func sample() -> [Session] {
        func s(_ id: String, _ dir: String, _ title: String, _ state: SessionState, _ activity: String?,
               ago: TimeInterval, sub: Int = 0, work: WorkKind = .building) -> Session {
            var session = Session(id: id, agent: "claude", cwd: "/Users/dev/" + dir, title: title.isEmpty ? nil : title, state: state,
                                  stateSince: Date().addingTimeInterval(-ago), lastEventAt: Date(), activity: activity,
                                  subagents: sub, permissionMode: "default", context: TerminalContext())
            session.workKind = work
            return session
        }
        return [
            s("1", "api-server", "Add pagination to the orders endpoint", .needsApproval, "Running: npm run migrate", ago: 12),
            s("2", "mobile-app", "Which auth flow should the app use?", .waitingForInput, nil, ago: 95),
            s("3", "web-dashboard", "Fix the login redirect bug", .working, "Searching login", ago: 221, sub: 2, work: .searching),
            s("5", "docs-site", "Update the changelog", .working, "Thinking", ago: 8, work: .thinking),
            s("6", "scripts", "", .idle, nil, ago: 40),
            s("4", "infra", "Upgrade the base image", .done, nil, ago: 3720),
        ]
    }

    static func temperatures(cpu: Double, ssd: Double, battery: Double) -> [ShownTemperature] {
        Temperatures(readings: [SensorReading(name: "PMU tdie1", celsius: cpu), SensorReading(name: "NAND CH0 temp", celsius: ssd),
                                SensorReading(name: "gas gauge battery", celsius: battery)]).shown
    }
    static let sampleTemperatures = temperatures(cpu: 50, ssd: 34, battery: 29.8)

    static func write(to dir: String) {
        let out = URL(fileURLWithPath: dir, isDirectory: true)
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let notch = NotchGeometry(hasNotch: true, notchWidth: 185, notchHeight: 37, topOffset: 0, screenFrame: .zero,
                                  idleStroll: true, crewStage: true)
        let plain = NotchGeometry(hasNotch: false, notchWidth: 0, notchHeight: 0, topOffset: 30, screenFrame: .zero,
                                  idleStroll: true, crewStage: true)
        let all = sample()
        let working = [all[2], all[5]]
        func request(_ event: String, _ tool: String, _ input: JSONValue, suggestions: [JSONValue] = []) -> PendingRequest? {
            PendingRequest(envelope: Envelope(agent: "claude", event: event, blocking: true, payload: .object([
                "session_id": "1", "hook_event_name": .string(event), "cwd": "/Users/dev/api-server",
                "tool_name": .string(tool), "tool_input": input, "permission_suggestions": .array(suggestions),
            ]), context: TerminalContext()))
        }
        let bash = request("PermissionRequest", "Bash",
            .object(["command": "npm run migrate -- --env staging", "description": "Apply pending database migrations",
                     "run_in_background": true]),
            suggestions: [.object(["type": "addRules", "behavior": "allow", "destination": "localSettings",
                                   "rules": .array([.object(["toolName": "Bash", "ruleContent": "npm run migrate:*"])])])])
        let edit = request("PermissionRequest", "Edit", .object([
            "file_path": "/Users/dev/api-server/src/routes/orders.ts",
            "old_string": "const orders = await db.orders.findAll()\nres.json(orders)",
            "new_string": "const page = Number(req.query.page ?? 1)\nconst orders = await db.orders.findAll({ limit: 50, offset: (page - 1) * 50 })\nres.json({ page, orders })"]))
        let question = request("PreToolUse", "AskUserQuestion", .object(["questions": .array([.object([
            "question": "Which auth flow should the app use?", "header": "Auth", "multiSelect": false,
            "options": .array([.object(["label": "Magic link", "description": "Email a one-time sign-in link"]),
                               .object(["label": "Password", "description": "Email and password"]),
                               .object(["label": "OAuth", "description": "Sign in with an existing account"])])])])]))
        let plan = request("PermissionRequest", "ExitPlanMode", .object(["plan": .string("""
        # Add pagination to the orders endpoint

        ## Changes
        - Accept `page` and `pageSize` query parameters in **orders.ts**
        - Clamp `pageSize` to 100 and default it to 50
        - Return `{ page, pageSize, total, orders }`

        ## Verification
        - Unit tests for the clamping and default values
        - Run the existing API test suite
        """)]))

        writeSpriteSheet(to: out)
        writeSetupWindow(to: out)

        let cases: [(String, [Session], Bool, NotchGeometry, PendingRequest?, Int)] = [
            ("1-collapsed-working", working, false, notch, nil, 0),
            ("2-collapsed-attention", all, false, notch, nil, 0),
            ("3-expanded", all, true, notch, nil, 0),
            ("4-expanded-empty", [], true, notch, nil, 0),
            ("3b-expanded-paged", all + (7...12).map { i in
                var x = all[2]; x = Session(id: "extra\(i)", agent: "claude", cwd: "/Users/dev/service-\(i)", title: "Background task \(i)",
                                            state: .working, stateSince: Date().addingTimeInterval(-Double(i * 40)), lastEventAt: Date(),
                                            activity: "Running: npm test", subagents: 0, permissionMode: nil, context: TerminalContext())
                x.workKind = .running; return x }, true, notch, nil, 0),
            ("4b-collapsed-empty", [], false, notch, nil, 0),
            ("5-pill-collapsed", all, false, plain, nil, 0),
            ("6-pill-expanded", working, true, plain, nil, 0),
            ("7-approval-command", all, true, notch, bash, 2),
            ("8-approval-edit", working, true, notch, edit, 0),
            ("9-question", working, true, notch, question, 0),
            ("10-plan", working, true, notch, plan, 0),
        ]
        for (name, sessions, expanded, g, req, more) in cases {
            let view = ZStack(alignment: .top) {
                LinearGradient(colors: [Color(red: 0.36, green: 0.47, blue: 0.62), Color(red: 0.78, green: 0.72, blue: 0.66)],
                               startPoint: .top, endPoint: .bottom)
                Rectangle().fill(.white.opacity(0.28)).frame(height: 37)   // stand-in menu bar
                NotchContentView(sessions: sessions, expanded: expanded, geometry: g, animated: false, live: false,
                                 request: req, queued: more > 0 ? [edit, question].compactMap { $0 }.prefix(more).map { $0 } : [],
                                 waitingSessionIDs: req.map { [$0.sessionID] } ?? [])
                    .padding(.top, g.topOffset + (g.hasNotch ? 0 : 7))
            }
            .frame(width: 680, height: expanded ? g.expandedSize(sessionCount: sessions.count, cardHeight: req.map(RequestCard.height(for:)) ?? 0, focus: req != nil, queued: req == nil ? 0 : more).height + g.topOffset + 70 : 90)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
                  let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else {
                print("failed: \(name)"); continue
            }
            try? png.write(to: out.appendingPathComponent(name + ".png"))
            print("wrote \(name).png")
        }
        writeIdleHome(to: out, notch: notch, plain: plain)
        let track = NowPlaying(app: .spotify, title: "Night Drive Through the Neon City (Extended Mix)", artist: "The Sample Band",
                               album: "Samples", isPlaying: true, duration: 214, position: 81, asOf: Date(), trackID: "sample")
        writeWeekStrips(to: out)
        let headerCases: [(String, [Session], PendingRequest?)] = [
            ("19-header-mini-player", [all[2], all[3]], nil),
            ("19b-header-mini-player-compact", [all[2], all[5], all[3]], nil),
            ("19c-header-mini-player-hidden-for-decision", all, bash),
            ("23d-temperatures-sessions", [all[2], all[3]], nil),
        ]
        for (name, sessions, req) in headerCases {
            var g = notch
            g.temperatureFooter = name.hasPrefix("23")
            let view = ZStack(alignment: .top) {
                LinearGradient(colors: [Color(red: 0.36, green: 0.47, blue: 0.62), Color(red: 0.78, green: 0.72, blue: 0.66)],
                               startPoint: .top, endPoint: .bottom)
                NotchContentView(sessions: sessions, expanded: true, geometry: g, animated: false, live: false, request: req,
                                 waitingSessionIDs: req.map { [$0.sessionID] } ?? [], nowPlaying: track,
                                 temperatures: name.hasPrefix("23e") ? temperatures(cpu: 93, ssd: 52, battery: 36)
                                     : name.hasPrefix("23") ? sampleTemperatures : [])
            }
            .frame(width: 680, height: g.expandedSize(sessionCount: sessions.count, cardHeight: req.map(RequestCard.height(for:)) ?? 0,
                                                          focus: req != nil).height + 70)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
                  let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else {
                print("failed: \(name)"); continue
            }
            try? png.write(to: out.appendingPathComponent(name + ".png"))
            print("wrote \(name).png")
        }
    }

    /// The idle home with sample music and events, in its main states.
    static func writeIdleHome(to out: URL, notch: NotchGeometry, plain: NotchGeometry) {
        let now = Date()
        let playing = NowPlaying(app: .spotify, title: "Night Drive", artist: "The Sample Band", album: "Samples",
                                 isPlaying: true, duration: 214, position: 81, asOf: now, trackID: "sample")
        var paused = playing
        paused.isPlaying = false
        let events = [AgendaEvent(id: "1", title: "Standup", start: now + 25 * 60, end: now + 40 * 60, color: 0xE5484D),
                      AgendaEvent(id: "2", title: "Planning", start: now + 2 * 3600, end: now + 3 * 3600, color: 0x3E8EF7),
                      AgendaEvent(id: "3", title: "Review", start: now + 4 * 3600, end: now + 5 * 3600, color: 0x30A46C)]
        let tomorrowOnly = [AgendaEvent(id: "t", title: "Dentist", start: now + 24 * 3600, end: now + 25 * 3600, color: 0x30A46C)]
        let label = Agenda.collapsedLabel(events, now: now, calendar: .current, locale: .current)
        let artwork = NSImage(size: NSSize(width: 64, height: 64), flipped: false) { rect in
            NSColor(red: 0.85, green: 0.42, blue: 0.30, alpha: 1).setFill(); rect.fill()
            NSColor(red: 0.98, green: 0.80, blue: 0.40, alpha: 1).setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 18, dy: 18)).fill()
            return true
        }
        func idle(_ track: NowPlaying?, _ agenda: [AgendaEvent], label: String?, agendaOn: Bool) -> IdleHome {
            IdleHome(nowPlaying: track, showMusic: true,
                     agenda: Agenda.remainingToday(agenda, now: now, calendar: .current, limit: nil), collapsedLabel: label,
                     agendaOn: agendaOn, weekHasEvents: AgendaWeek(now: now, calendar: .current).hasEvents(agenda, now: now, calendar: .current))
        }
        var strollOff = notch
        strollOff.idleStroll = false
        let cases: [(String, NotchGeometry, IdleHome, Bool, Bool)] = [
            ("11-idle-both-expanded", notch, idle(playing, events, label: label, agendaOn: true), true, true),
            ("11b-idle-both-collapsed", notch, idle(playing, events, label: label, agendaOn: true), false, true),
            ("11c-idle-both-pill-expanded", plain, idle(playing, events, label: label, agendaOn: true), true, true),
            ("11d-idle-both-pill-collapsed", plain, idle(playing, events, label: label, agendaOn: true), false, true),
            ("12-idle-music-only-expanded", notch, idle(playing, [], label: nil, agendaOn: false), true, true),
            ("13-idle-calendar-only-expanded", notch, idle(nil, events, label: label, agendaOn: true), true, true),
            ("13b-idle-calendar-only-collapsed", notch, idle(nil, events, label: label, agendaOn: true), false, true),
            ("14-idle-track-paused-nothing-else-today", notch, idle(paused, [], label: nil, agendaOn: true), true, true),
            ("15-idle-controls-denied", notch, idle(playing, events, label: label, agendaOn: true), true, false),
            ("16-idle-stroll-off-music-collapsed", strollOff, idle(playing, [], label: nil, agendaOn: false), false, true),
            ("18-idle-raven-listening-collapsed", notch, idle(playing, events, label: label, agendaOn: true), false, true),
            ("18b-idle-raven-paused-collapsed", notch, idle(paused, [], label: nil, agendaOn: false), false, true),
            ("18c-idle-raven-pill", plain, idle(playing, events, label: label, agendaOn: true), false, true),
            ("18d-idle-characters-off-collapsed", notch, idle(playing, events, label: label, agendaOn: true), false, true),
            ("20-music-badge-tint", notch, idle(playing, events, label: label, agendaOn: true), true, true),
            ("20b-record-spotify", notch, idle(playing, [], label: nil, agendaOn: false), true, true),
            ("20c-record-music", notch, idle(paused, [], label: nil, agendaOn: false), true, true),
            ("21c-week-empty-today", notch, idle(nil, tomorrowOnly, label: nil, agendaOn: true), true, true),
            ("22-calendar-placeholder-off", notch, idle(playing, [], label: nil, agendaOn: false), true, true),
            ("22b-calendar-placeholder-allow", notch, idle(playing, [], label: nil, agendaOn: false), true, true),
            ("22c-calendar-placeholder-denied", notch, idle(playing, [], label: nil, agendaOn: false), true, true),
            ("23-temperatures-ravens", notch, .none, true, true),
            ("23b-temperatures-music-calendar", notch, idle(playing, events, label: label, agendaOn: true), true, true),
            ("23e-temperatures-warning-and-hot", notch, .none, true, true),
        ]
        for (name, base, home, expanded, allowed) in cases {
            var g = base
            g.idleHome = home
            g.temperatureFooter = name.hasPrefix("23")
            var track = home.hasTrack ? (home.isPlaying ? playing : paused) : nil
            if name.hasPrefix("20c") { track?.app = .appleMusic }
            let art = name.hasPrefix("12") || name.hasPrefix("20b") || name.hasPrefix("20c") ? nil : artwork
            let agenda = name.hasPrefix("21c") ? tomorrowOnly : events
            let view = ZStack(alignment: .top) {
                LinearGradient(colors: [Color(red: 0.36, green: 0.47, blue: 0.62), Color(red: 0.78, green: 0.72, blue: 0.66)],
                               startPoint: .top, endPoint: .bottom)
                Rectangle().fill(.white.opacity(0.28)).frame(height: 37)
                NotchContentView(sessions: [], expanded: expanded, geometry: g, animated: name.hasPrefix("18") && !name.hasPrefix("18b"),
                                 characters: name.hasPrefix("18") && !name.hasPrefix("18d"),
                                 nowPlaying: track, artwork: art, tint: art.flatMap(MusicSource.tint(of:)), controlsAllowed: allowed,
                                 agenda: home.agendaOn ? agenda : [],
                                 calendarPrompt: name.hasPrefix("22b") ? .allow : name.hasPrefix("22c") ? .openSettings
                                     : name.hasPrefix("22") ? .turnOn : nil,
                                 temperatures: name.hasPrefix("23e") ? temperatures(cpu: 93, ssd: 52, battery: 36)
                                     : name.hasPrefix("23") ? sampleTemperatures : [])
                    .padding(.top, g.topOffset + (g.hasNotch ? 0 : 7))
            }
            .frame(width: 680, height: expanded ? g.expandedSize(sessionCount: 0).height + g.topOffset + 70 : 90)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
                  let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else {
                print("failed: \(name)"); continue
            }
            try? png.write(to: out.appendingPathComponent(name + ".png"))
            print("wrote \(name).png")
        }
    }

    static func pick(_ p: Persona, _ state: SessionState, _ work: WorkKind, _ index: Int?) -> [String] {
        let frames = PixelSprites.frames(for: state, persona: p, work: work)
        return frames[index ?? frames.count - 1]
    }

    /// Every character with its walk, party trick, and each state, enlarged for reviewing the pixel art.
    static func writeSpriteSheet(to out: URL) {
        func cell(_ frame: [String], _ p: Persona) -> some View {
            Canvas { context, size in PixelBot.draw(frame, persona: p, in: &context, size: size) }.frame(width: 90, height: 72)
        }
        let columns = ["stand", "step", "trick", "trick", "think", "search", "run", "build", "ask", "wait", "done", "error", "listen", "paused", "face", "wave", "wave"]
        let view = VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("").frame(width: 92)
                ForEach(Array(columns.enumerated()), id: \.offset) { _, name in
                    Text(name).font(.system(size: 10)).foregroundStyle(.white.opacity(0.6)).frame(width: 90)
                }
            }
            ForEach(PixelSprites.personas) { p in
                let walk = PixelSprites.walkFrames(persona: p), trick = PixelSprites.trickFrames(persona: p)
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(p.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                        Text(p.role).font(.system(size: 10)).foregroundStyle(.white.opacity(0.6))
                    }
                    .frame(width: 92, alignment: .leading)
                    cell(walk[0], p); cell(walk[1], p); cell(trick[0], p); cell(trick[1], p)
                    cell(pick(p, .working, .thinking, nil), p); cell(pick(p, .working, .searching, 0), p)
                    cell(pick(p, .working, .running, 0), p); cell(pick(p, .working, .building, 1), p)
                    cell(pick(p, .needsApproval, .building, 0), p); cell(pick(p, .waitingForInput, .building, 0), p)
                    cell(pick(p, .done, .building, 0), p); cell(pick(p, .error, .building, 0), p)
                    cell(PixelSprites.listeningFrames(persona: p, playing: true)[3], p)
                    cell(PixelSprites.listeningFrames(persona: p, playing: false)[0], p)
                    ForEach(0..<3, id: \.self) { cell(PixelSprites.waveFrames(persona: p)[$0], p) }
                }
            }
        }
        .padding(20)
        .background(Color.black)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        if let image = renderer.nsImage, let tiff = image.tiffRepresentation,
           let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            try? png.write(to: out.appendingPathComponent("0-characters.png"))
            print("wrote 0-characters.png")
        }
    }
}

extension Snapshot {
    /// The first-run setup window, as a new user would see it.
    static func writeSetupWindow(to out: URL) {
        let facts = SetupFacts(claudeCodeFound: true, otherApprovalTools: 0)
        let view = SetupView(model: AppModel(), settings: Settings(defaults: UserDefaults(suiteName: "ravenisland-snapshot")!),
                             facts: facts, close: {})
            .background(Color(nsColor: .windowBackgroundColor))
            .environment(\.colorScheme, .dark)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        if let image = renderer.nsImage, let tiff = image.tiffRepresentation,
           let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            try? png.write(to: out.appendingPathComponent("11-setup.png"))
        }
    }
}

extension Snapshot {
    /// The week strip on its own with tomorrow selected, so the result does not depend on the time of day.
    static func writeWeekStrips(to out: URL) {
        let tomorrow = AgendaWeek(now: Date(), calendar: .current).days[AgendaWeek.daysBefore + 1]
        let titles = ["Standup", "Design review", "Customer call", "Planning", "Retro"]
        let colors: [UInt32] = [0xE5484D, 0x8E4EC6, 0xF76B15, 0x3E8EF7, 0x30A46C]
        var five: [AgendaEvent] = []
        for k in 0..<5 {
            let start: Date = tomorrow + TimeInterval(9 * 3600 + k * 5400)
            five.append(AgendaEvent(id: "f\(k)", title: titles[k], start: start, end: start + 1800, color: colors[k]))
        }
        for (name, events) in [("21b-week-more", five), ("21d-week-other-day", [five[4]])] {
            let view = AgendaWeekView(events: events, onOpenCalendar: {}, selectedOverride: tomorrow)
                .frame(width: 240, height: 80).padding(12).background(Color.black)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
                  let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { continue }
            try? png.write(to: out.appendingPathComponent(name + ".png"))
            print("wrote \(name).png")
        }
    }
}
