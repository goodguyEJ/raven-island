import SwiftUI
import RavenIslandCore

extension SessionState {
    var color: Color {
        switch self {
        case .idle: return .gray
        case .working: return .blue
        case .needsApproval: return .orange
        case .waitingForInput: return .yellow
        case .done: return .green
        case .error: return .red
        }
    }
}

func elapsed(since date: Date, now: Date) -> String {
    let s = max(0, Int(now.timeIntervalSince(date)))
    if s < 60 { return "\(s)s" }
    if s < 3600 { return "\(s / 60)m \(s % 60)s" }
    return "\(s / 3600)h \((s % 3600) / 60)m"
}

struct DebugView: View {
    @ObservedObject var model: AppModel

    private static let timeFormat: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"; return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if model.sessions.isEmpty {
                Text("No sessions yet. Start or continue a Claude Code session.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                TimelineView(.periodic(from: .now, by: 1)) { timeline in
                    List(model.sessions) { s in row(s, now: timeline.date) }
                        .listStyle(.inset)
                }
                .frame(minHeight: 140)
            }
            Divider()
            Text("Events").font(.headline).padding(.horizontal, 12).padding(.top, 8)
            ScrollViewReader { proxy in
                List(model.log) { e in
                    HStack(spacing: 10) {
                        Text(Self.timeFormat.string(from: e.time)).foregroundStyle(.secondary)
                        Text(e.session).foregroundStyle(.secondary)
                        Text(e.event).fontWeight(.medium)
                        Text(e.detail).foregroundStyle(.secondary).lineLimit(1)
                    }
                    .font(.system(.caption, design: .monospaced))
                    .id(e.id)
                }
                .listStyle(.plain)
                .onChange(of: model.log.count) { _, _ in
                    if let last = model.log.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
        .frame(minWidth: 620, minHeight: 460)
    }

    private var header: some View {
        HStack(spacing: 16) {
            Label("\(model.sessions.count) sessions", systemImage: "rectangle.stack")
            Label("\(model.eventCount) events", systemImage: "bolt")
            Spacer()
            if let s = model.hookStatus {
                Label(s.isFullyInstalled ? "Hooks installed" : "Hooks: \(s.installed.count)/\(Installer.events.count)",
                      systemImage: s.isFullyInstalled ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(s.isFullyInstalled ? .green : .orange)
            }
            Button("Refresh") { model.refreshHookStatus() }
        }
        .font(.callout)
        .padding(12)
    }

    private func row(_ s: Session, now: Date) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle().fill(s.state.color).frame(width: 10, height: 10).padding(.top, 4)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(s.projectName).fontWeight(.semibold)
                    if s.subagents > 0 {
                        Text("+\(s.subagents) subagent\(s.subagents == 1 ? "" : "s")")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(s.state.label) · \(elapsed(since: s.stateSince, now: now))")
                        .font(.callout).foregroundStyle(s.state.color)
                }
                if let title = s.title { Text(title).lineLimit(1).foregroundStyle(.secondary) }
                HStack(spacing: 8) {
                    if let a = s.activity { Text(a).lineLimit(1) }
                    Spacer()
                    Text([s.context.termProgram, s.context.tty.map { $0.replacingOccurrences(of: "/dev/", with: "") },
                          s.context.tmuxPane.map { "tmux \($0)" }].compactMap { $0 }.joined(separator: " · "))
                }
                .font(.caption).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }
}
