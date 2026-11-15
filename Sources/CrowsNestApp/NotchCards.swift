import SwiftUI
import CrowsNestCore

struct PillButton: View {
    var title: String
    var hint: String? = nil
    var tint: Color = .white
    var prominent = false
    var disabled = false
    var action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(title).font(.system(size: 12, weight: .semibold))
                if let hint {
                    Text(hint).font(.system(size: 10, weight: .medium)).opacity(0.6)
                }
            }
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 12)
            .frame(height: 26)
            .foregroundStyle(prominent ? Color.black : tint)
            .background(Capsule().fill(prominent ? tint.opacity(hovered ? 1 : 0.9) : tint.opacity(hovered ? 0.26 : 0.16)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.4 : 1)
        .onHover { hovered = $0 }
    }
}

struct DarkField: View {
    var placeholder: String
    @Binding var text: String
    var live = true
    var onSubmit: () -> Void

    @ViewBuilder private var field: some View {
        if live {
            TextField(placeholder, text: $text).textFieldStyle(.plain)
        } else {
            // Text fields don't render offscreen; show the placeholder for snapshots.
            Text(placeholder).opacity(0.4).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    var body: some View {
        field
            .font(.system(size: 12))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.white.opacity(0.12)))
            .onSubmit(onSubmit)
    }
}

private struct BottomEdgeKey: PreferenceKey {
    static var defaultValue: CGFloat = .infinity
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// A scrolling box that knows whether its last line has been brought into view. Until it has, it
/// shows a "more below" marker, and the card keeps Allow switched off.
/// In offscreen snapshots (where scroll views don't render) it just clips.
struct ReviewScroll<Content: View>: View {
    var live: Bool
    @Binding var reachedEnd: Bool
    @ViewBuilder var content: Content
    private let space = "review-scroll"

    var body: some View {
        if live {
            GeometryReader { outer in
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 0) {
                        content.frame(maxWidth: .infinity, alignment: .leading)
                        Color.clear.frame(height: 1).background(GeometryReader { g in
                            Color.clear.preference(key: BottomEdgeKey.self, value: g.frame(in: .named(space)).maxY)
                        })
                    }
                }
                .coordinateSpace(name: space)
                .onPreferenceChange(BottomEdgeKey.self) { bottom in
                    if bottom <= outer.size.height + 6 { reachedEnd = true }
                }
                .overlay(alignment: .bottom) {
                    if !reachedEnd {
                        Text("↓  More below — scroll to the end to allow")
                            .font(.system(size: 10.5, weight: .semibold)).foregroundStyle(.black)
                            .padding(.horizontal, 9).padding(.vertical, 3)
                            .background(Capsule().fill(Color.yellow))
                            .padding(.bottom, 5)
                            .allowsHitTesting(false)
                    }
                }
            }
        } else {
            content.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).clipped()
        }
    }
}

/// Headings, bullets, and code blocks only: enough to read a plan.
struct MarkdownLite: View {
    var text: String

    private struct Line: Identifiable { let id: Int; let kind: Kind; let text: String }
    private enum Kind { case h1, h2, bullet, code, body, gap }

    private var lines: [Line] {
        var out: [Line] = []
        var inCode = false
        for (i, raw) in text.components(separatedBy: "\n").enumerated() {
            let t = raw.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("```") { inCode.toggle(); continue }
            if inCode { out.append(Line(id: i, kind: .code, text: raw)); continue }
            if t.isEmpty { out.append(Line(id: i, kind: .gap, text: "")) }
            else if t.hasPrefix("# ") { out.append(Line(id: i, kind: .h1, text: String(t.dropFirst(2)))) }
            else if t.hasPrefix("#") { out.append(Line(id: i, kind: .h2, text: t.trimmingCharacters(in: CharacterSet(charactersIn: "# ")))) }
            else if t.hasPrefix("- ") || t.hasPrefix("* ") { out.append(Line(id: i, kind: .bullet, text: String(t.dropFirst(2)))) }
            else { out.append(Line(id: i, kind: .body, text: t)) }
        }
        return out
    }

    private func inline(_ s: String) -> AttributedString {
        guard var text = try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) else {
            return AttributedString(s)
        }
        // Plan text comes from the agent. Links are shown as plain text, never as something clickable
        // whose label could differ from where it goes.
        for range in text.runs.filter({ $0.link != nil }).map(\.range) { text[range].link = nil }
        return text
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(lines) { line in
                switch line.kind {
                case .h1: Text(inline(line.text)).font(.system(size: 14, weight: .bold)).padding(.top, 2)
                case .h2: Text(inline(line.text)).font(.system(size: 12.5, weight: .semibold)).padding(.top, 2)
                case .bullet:
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("•"); Text(inline(line.text))
                    }.font(.system(size: 12))
                case .code: Text(line.text).font(.system(size: 11, design: .monospaced)).foregroundStyle(.white.opacity(0.8))
                case .body: Text(inline(line.text)).font(.system(size: 12))
                case .gap: Color.clear.frame(height: 4)
                }
            }
        }
        .foregroundStyle(.white.opacity(0.92))
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct RequestCard: View {
    var request: PendingRequest
    /// Other requests queued behind this one.
    var more: Int
    var live: Bool
    var onDecision: (Decision) -> Void
    /// Called once everything on the card has been scrolled into view.
    var onReviewed: () -> Void = {}
    /// Called when a note field opens or closes, so keyboard shortcuts stay off while typing.
    var onEditing: (Bool) -> Void = { _ in }

    @State private var note = ""
    @State private var writingNote = false
    @State private var picked: [Int: Set<String>] = [:]
    @State private var other: [Int: String] = [:]
    @State private var reachedEnd = false
    @State private var armed = false

    /// Buttons ignore input for a moment after the card appears, so a click or key press meant for
    /// the previous card cannot land on this one.
    private var canAct: Bool { !live || armed }
    private var canAllow: Bool { canAct && (!live || reachedEnd) && !request.isTooLongToReview }

    static func height(for request: PendingRequest) -> CGFloat {
        switch request.kind {
        case .permission: return 226
        case .plan: return 350
        case .question:
            let body = request.questions.reduce(CGFloat(0)) { $0 + 24 + CGFloat($1.options.count) * 32 + 34 }
            return min(360, 62 + body + 38)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            switch request.kind {
            case .permission: permissionBody
            case .question: questionBody
            case .plan: planBody
            }
        }
        .padding(12)
        .frame(height: Self.height(for: request) - 6)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white.opacity(0.09)))
        .padding(.horizontal, 8)
        .padding(.bottom, 6)
        .task(id: request.id) {
            try? await Task.sleep(nanoseconds: UInt64(AppModel.armingDelay * 1_000_000_000))
            armed = true
        }
        .onChange(of: reachedEnd) { _, reached in if reached { onReviewed() } }
        .onChange(of: writingNote) { _, open in onEditing(open) }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                StatusGlyph(state: request.kind == .question ? .waitingForInput : .needsApproval, size: 15, animated: live)
                Text(TextSafety.visible(request.title)).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                Spacer(minLength: 4)
                if more > 0 {
                    Text("Decision 1 of \(more + 1)")
                        .font(.system(size: 10.5, weight: .semibold))
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Capsule().fill(SessionState.needsApproval.color.opacity(0.22)))
                        .foregroundStyle(SessionState.needsApproval.color)
                }
            }
            Text(TextSafety.visible(request.projectName))
                .font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.5)).lineLimit(1)
        }
    }

    /// Where the request runs, in full. Shown inside the scrolling area so nothing is cut.
    private var workingDirectoryLine: some View {
        Text("in " + TextSafety.visible(request.workingDirectory))
            .font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.55))
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
    }

    // MARK: Permission

    private var permissionBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            ReviewScroll(live: live, reachedEnd: $reachedEnd) { detailView.padding(9) }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.black.opacity(0.55)))
            if writingNote {
                HStack(spacing: 6) {
                    DarkField(placeholder: "Tell the agent why, or what to do instead", text: $note, live: live) {
                        if canAct { onDecision(.deny(message: note)) }
                    }
                    PillButton(title: "Deny", tint: .red, prominent: true, disabled: !canAct) { onDecision(.deny(message: note)) }
                    PillButton(title: "Back") { writingNote = false }
                }
            } else {
                HStack(spacing: 6) {
                    PillButton(title: "Deny", hint: "⌃⌥N", tint: .red, disabled: !canAct) { onDecision(.deny(message: nil)) }
                    PillButton(title: "Deny + note", disabled: !canAct) { writingNote = true }
                    Spacer(minLength: 4)
                    PillButton(title: "Terminal", disabled: !canAct) { onDecision(.terminal) }
                    if request.alwaysAllowLabel != nil {
                        PillButton(title: "Always allow", tint: .green, disabled: !canAllow) { onDecision(.alwaysAllow) }
                    }
                    PillButton(title: "Allow", hint: "⌃⌥Y", tint: .green, prominent: true, disabled: !canAllow) { onDecision(.allow) }
                }
            }
        }
    }

    private func mono(_ s: String, color: Color = .white.opacity(0.92)) -> some View {
        Text(TextSafety.visible(s)).font(.system(size: 11.5, design: .monospaced)).foregroundStyle(color)
            .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
    }

    private func prefixed(_ s: String, _ mark: String) -> String {
        s.split(separator: "\n", omittingEmptySubsequences: false).map { mark + $0 }.joined(separator: "\n")
    }

    private func pathLine(_ path: String) -> some View {
        Text(TextSafety.visible(path)).font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.5))
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private var detailView: some View {
        if request.isTooLongToReview {
            VStack(alignment: .leading, spacing: 6) {
                Label("Too long to review here", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(.yellow)
                Text("This request is too large for the panel, so it can't be allowed from here. Use Terminal to read it in full, or deny it.")
                    .font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                workingDirectoryLine
                switch request.detail {
                case .command(let command, let noteText):
                    mono(command)
                    if let noteText, !noteText.isEmpty {
                        Text(TextSafety.visible(noteText)).font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                case .edit(let path, let old, let new):
                    pathLine(path)
                    mono(prefixed(old, "- "), color: Color(red: 1, green: 0.52, blue: 0.5))
                    mono(prefixed(new, "+ "), color: Color(red: 0.5, green: 0.9, blue: 0.56))
                case .write(let path, let content):
                    pathLine(path)
                    mono(content)
                case .generic(let json):
                    mono(json)
                }
                // Every remaining input field, so nothing that changes what the call does is left off.
                if !request.otherFields.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Also set").font(.system(size: 10.5, weight: .semibold)).foregroundStyle(.yellow.opacity(0.9))
                        ForEach(request.otherFields, id: \.key) { field in
                            mono("\(field.key) = \(field.value)", color: .yellow.opacity(0.9))
                        }
                    }
                    .padding(.top, 2)
                }
                if let rule = request.alwaysAllowLabel {
                    Text("Always allow adds \(TextSafety.visible(rule))" + (request.alwaysAllowDestination.map { " for \($0)" } ?? ""))
                        .font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.6))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                }
            }
        }
    }

    // MARK: Question

    private var answers: [String: String]? {
        var out: [String: String] = [:]
        for (i, q) in request.questions.enumerated() {
            var parts = q.options.map(\.label).filter { picked[i]?.contains($0) == true }   // keep option order
            let typed = (other[i] ?? "").trimmingCharacters(in: .whitespaces)
            if !typed.isEmpty { parts.append(typed) }
            if parts.isEmpty { return nil }
            out[q.question] = parts.joined(separator: ", ")
        }
        return out.isEmpty ? nil : out
    }

    private func toggle(_ label: String, question i: Int, multi: Bool) {
        guard canAct else { return }
        var set = picked[i] ?? []
        if multi {
            if set.contains(label) { set.remove(label) } else { set.insert(label) }
        } else {
            set = [label]
            other[i] = ""
        }
        picked[i] = set
        // One single-choice question: picking an option is the answer.
        if !multi, request.questions.count == 1, let a = answers { onDecision(.answers(a)) }
    }

    private var questionBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            ReviewScroll(live: live, reachedEnd: $reachedEnd) {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(request.questions.enumerated()), id: \.offset) { i, q in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(TextSafety.visible(q.question)).font(.system(size: 12.5, weight: .medium)).foregroundStyle(.white)
                                .fixedSize(horizontal: false, vertical: true)
                            ForEach(q.options, id: \.label) { option in
                                optionRow(option, selected: picked[i]?.contains(option.label) == true, multi: q.multiSelect) {
                                    toggle(option.label, question: i, multi: q.multiSelect)
                                }
                            }
                            DarkField(placeholder: "Other…", text: Binding(
                                get: { other[i] ?? "" },
                                set: { other[i] = $0; if !q.multiSelect, !$0.isEmpty { picked[i] = [] } }), live: live) {
                                if canAct, let a = answers { onDecision(.answers(a)) }
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack(spacing: 6) {
                PillButton(title: "In terminal", disabled: !canAct) { onDecision(.terminal) }
                Spacer()
                PillButton(title: "Send answer", tint: .green, prominent: true, disabled: answers == nil || !canAct) {
                    if let a = answers { onDecision(.answers(a)) }
                }
            }
        }
    }

    private func optionRow(_ option: QuestionOption, selected: Bool, multi: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: selected ? (multi ? "checkmark.square.fill" : "largecircle.fill.circle")
                                           : (multi ? "square" : "circle"))
                    .font(.system(size: 12)).foregroundStyle(selected ? Color.green : .white.opacity(0.55))
                Text(TextSafety.visible(option.label)).font(.system(size: 12, weight: .medium)).foregroundStyle(.white)
                if let d = option.detail, !d.isEmpty {
                    Text(TextSafety.visible(d)).font(.system(size: 11)).foregroundStyle(.white.opacity(0.5)).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 9)
            .frame(height: 27)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.white.opacity(selected ? 0.16 : 0.07)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Plan

    private var planBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            ReviewScroll(live: live, reachedEnd: $reachedEnd) {
                if request.isTooLongToReview {
                    Text("This plan is too long for the panel, so it can't be approved from here. Use Terminal to read it in full.")
                        .font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.8)).padding(10)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        workingDirectoryLine
                        MarkdownLite(text: TextSafety.visible(request.plan ?? "(The plan had no text.)"))
                    }
                    .padding(10)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.black.opacity(0.55)))
            if writingNote {
                HStack(spacing: 6) {
                    DarkField(placeholder: "What should change?", text: $note, live: live) {
                        if canAct, !note.isEmpty { onDecision(.deny(message: note)) }
                    }
                    PillButton(title: "Send", tint: .orange, prominent: true, disabled: note.isEmpty || !canAct) {
                        onDecision(.deny(message: note))
                    }
                    PillButton(title: "Back") { writingNote = false }
                }
            } else {
                HStack(spacing: 6) {
                    PillButton(title: "Send feedback…", tint: .orange, disabled: !canAct) { writingNote = true }
                    Spacer(minLength: 4)
                    PillButton(title: "In terminal", disabled: !canAct) { onDecision(.terminal) }
                    PillButton(title: "Approve plan", hint: "⌃⌥Y", tint: .green, prominent: true, disabled: !canAllow) { onDecision(.allow) }
                }
            }
        }
    }
}
