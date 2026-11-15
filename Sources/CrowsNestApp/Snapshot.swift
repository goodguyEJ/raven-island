import AppKit
import SwiftUI
import CrowsNestCore

/// `Crow's Nest --snapshot DIR` renders the panel's states to PNG files with sample data,
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

        let usage = UsageSnapshot(fiveHour: UsageWindow(usedPercent: 42, resetsAt: Date().addingTimeInterval(2 * 3600 + 13 * 60)),
                                  sevenDay: UsageWindow(usedPercent: 81, resetsAt: Date().addingTimeInterval(3 * 86_400 + 4 * 3600)),
                                  updatedAt: Date())
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
            ("7-approval-command", all, true, notch, bash, 1),
            ("8-approval-edit", working, true, notch, edit, 0),
            ("9-question", working, true, notch, question, 0),
            ("10-plan", working, true, notch, plan, 0),
        ]
        for (name, sessions, expanded, g, req, more) in cases {
            let view = ZStack(alignment: .top) {
                LinearGradient(colors: [Color(red: 0.36, green: 0.47, blue: 0.62), Color(red: 0.78, green: 0.72, blue: 0.66)],
                               startPoint: .top, endPoint: .bottom)
                Rectangle().fill(.white.opacity(0.28)).frame(height: 37)   // stand-in menu bar
                NotchContentView(sessions: sessions, expanded: expanded, geometry: g, animated: false,
                                 request: req, moreRequests: more, usage: expanded ? usage : nil)
                    .padding(.top, g.topOffset + (g.hasNotch ? 0 : 7))
            }
            .frame(width: 680, height: expanded ? g.expandedSize(sessionCount: sessions.count, cardHeight: req.map(RequestCard.height(for:)) ?? 0, footerHeight: UsageStrip.height).height + g.topOffset + 70 : 90)
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
        let columns = ["stand", "step", "trick", "trick", "think", "search", "run", "build", "ask", "wait", "done", "error"]
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
    /// The first-run setup window, as a new user would see it with an existing status line.
    static func writeSetupWindow(to out: URL) {
        let facts = SetupFacts(claudeCodeFound: true, otherApprovalTools: 0, currentStatusLine: "bash ~/statusline.sh")
        let view = SetupView(model: AppModel(), settings: Settings(defaults: UserDefaults(suiteName: "crowsnest-snapshot")!),
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
