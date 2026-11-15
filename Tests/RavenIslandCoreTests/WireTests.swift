import Foundation
import Testing
@testable import RavenIslandCore

@Suite struct WireTests {
    @Test func payloadSurvivesRoundTripWithUnknownFields() throws {
        let raw = #"{"session_id":"abc","hook_event_name":"PreToolUse","tool_input":{"n":3,"f":1.5,"ok":true,"none":null,"list":["a",{"b":[]}]},"brand_new_field":{"x":1}}"#
        let payload = try #require(JSONValue.parse(Data(raw.utf8)))
        let env = Envelope(agent: "claude", event: "PreToolUse", blocking: false, payload: payload,
                           context: TerminalContext(termProgram: "ghostty", tty: "/dev/ttys001",
                                                    ancestors: [AncestorProcess(pid: 5, name: "claude")], agentPid: 5))
        let decoded = try JSONDecoder().decode(Envelope.self, from: JSONEncoder().encode(env))
        #expect(decoded == env)
        #expect(decoded.sessionID == "abc")
        #expect(decoded.payload["brand_new_field"]?["x"]?.number == 1)
        #expect(decoded.payload["tool_input"]?["f"]?.number == 1.5)
    }

    @Test func garbageIsNotJSON() {
        #expect(JSONValue.parse(Data("not json".utf8)) == nil)
        #expect(JSONValue.parse(Data()) == nil)
    }

    @Test func onlyPermissionRequestsBlock() {
        #expect(BlockingEvents.isBlocking(event: "PermissionRequest", payload: .null))
        #expect(!BlockingEvents.isBlocking(event: "PreToolUse", payload: .null))
        #expect(!BlockingEvents.isBlocking(event: "Stop", payload: .null))
    }

    @Test func framesCrossASocket() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("cn-" + UUID().uuidString.prefix(8))
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = dir.appendingPathComponent("t.sock").path

        #expect(throws: SocketError.self) { _ = try UnixSocket.connect(path: path) }   // nothing listening

        let listener = try UnixSocket.listen(path: path)
        defer { close(listener) }
        let big = Data((0..<200_000).map { UInt8($0 % 251) })
        let client = try UnixSocket.connect(path: path)
        defer { close(client) }
        let server = accept(listener, nil, nil)
        defer { close(server) }

        let writer = Thread { try? UnixSocket.sendFrame(fd: client, big); try? UnixSocket.sendFrame(fd: client, Data()) }
        writer.start()
        #expect(try UnixSocket.readFrame(fd: server) == big)
        #expect(try UnixSocket.readFrame(fd: server) == Data())

        close(client)
        #expect(throws: SocketError.closed) { _ = try UnixSocket.readFrame(fd: server) }
    }

    @Test func processTreeFindsItself() {
        let me = ProcessTree.info(pid: getpid())
        #expect(me != nil)
        #expect(ProcessTree.isAlive(getpid()))
        let chain = [AncestorProcess(pid: 9, name: "sh"), AncestorProcess(pid: 8, name: "claude"), AncestorProcess(pid: 7, name: "zsh")]
        #expect(ProcessTree.agentPid(in: chain) == 8)
    }
}
