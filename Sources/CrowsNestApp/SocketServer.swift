import Foundation
import CrowsNestCore

/// A hook invocation that is waiting for an answer. The bridge on the other end blocks until
/// `reply` is called, or goes away on its own (the agent cancelled the hook, or timed it out).
final class BlockingConnection {
    private let fd: Int32
    private let queue: DispatchQueue
    private let lock = NSLock()
    private var finished = false
    private var peerClosed = false
    private var closeHandler: (() -> Void)?
    private var source: DispatchSourceRead?

    init(fd: Int32, queue: DispatchQueue) {
        self.fd = fd
        self.queue = queue
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in self?.readable() }
        source.setCancelHandler { close(fd) }
        self.source = source
        source.resume()
    }

    private func readable() {
        var buffer = [UInt8](repeating: 0, count: 256)
        let n = recv(fd, &buffer, buffer.count, 0)
        if n > 0 || (n < 0 && (errno == EAGAIN || errno == EINTR)) { return }   // stray bytes: ignore
        lock.lock()
        let wasFinished = finished
        finished = true
        peerClosed = true
        let handler = closeHandler
        lock.unlock()
        guard !wasFinished else { return }
        source?.cancel()
        if let handler { DispatchQueue.main.async(execute: handler) }
    }

    deinit {
        // Dropped without an answer: cancelling runs the handler that closes the descriptor.
        source?.cancel()
    }

    /// Tells the bridge the request is still on screen, so it keeps waiting instead of giving up.
    /// Sent once when the request arrives and then every second as a heartbeat.
    func acknowledge() {
        lock.lock()
        let wasFinished = finished
        lock.unlock()
        guard !wasFinished else { return }
        queue.async { [fd] in
            if let body = try? JSONEncoder().encode(Reply.ackReply) { try? UnixSocket.sendFrame(fd: fd, body) }
        }
    }

    /// Runs `handler` on the main queue if the bridge disconnects before a reply is sent.
    func whenPeerCloses(_ handler: @escaping () -> Void) {
        lock.lock()
        let already = peerClosed
        if !already { closeHandler = handler }
        lock.unlock()
        if already { DispatchQueue.main.async(execute: handler) }
    }

    func reply(_ reply: Reply) {
        lock.lock()
        let wasFinished = finished
        finished = true
        lock.unlock()
        guard !wasFinished else { return }
        queue.async { [fd, source] in
            if let body = try? JSONEncoder().encode(reply) { try? UnixSocket.sendFrame(fd: fd, body) }
            source?.cancel()
        }
    }
}

/// Accepts one connection per hook invocation. Non-blocking events are read and closed;
/// blocking events hand the caller a `BlockingConnection`.
final class SocketServer {
    enum StartError: Error { case alreadyRunning }
    typealias Handler = (_ envelope: Envelope, _ connection: BlockingConnection?) -> Void

    private let path: String
    private let handler: Handler
    private var listenFD: Int32 = -1
    private let workQueue = DispatchQueue(label: "crowsnest.socket.work", attributes: .concurrent)
    private let connectionQueue = DispatchQueue(label: "crowsnest.socket.blocking")

    init(path: String, handler: @escaping Handler) {
        self.path = path
        self.handler = handler
    }

    func start() throws {
        try AppPaths.ensureRoot()
        if FileManager.default.fileExists(atPath: path) {
            // A live listener means another instance owns the socket; otherwise the file is stale.
            if let fd = try? UnixSocket.connect(path: path) {
                close(fd)
                throw StartError.alreadyRunning
            }
            unlink(path)
        }
        listenFD = try UnixSocket.listen(path: path)
        let fd = listenFD
        let thread = Thread { [weak self] in
            while true {
                let conn = accept(fd, nil, nil)
                if conn < 0 {
                    let code = errno
                    if code == EINTR || code == ECONNABORTED { continue }
                    if code == EMFILE || code == ENFILE || code == ENOBUFS || code == ENOMEM {
                        usleep(200_000)   // out of descriptors for now: wait for some to free up
                        continue
                    }
                    if code == EBADF || code == EINVAL || code == ENOTSOCK {
                        // Listener is gone for good. Remove the socket so bridges fail fast and pass
                        // through, instead of queueing behind a listener that will never answer.
                        self?.stop()
                        break
                    }
                    usleep(50_000)   // anything else is a one-off for that connection
                    continue
                }
                // Cap connections still being read, so a flood of slow senders can't tie up the app.
                guard let self, self.beginRead() else { close(conn); continue }
                self.workQueue.async { self.serve(conn) }
            }
        }
        thread.name = "crowsnest.socket.accept"
        thread.start()
    }

    func stop() {
        if listenFD >= 0 { close(listenFD); listenFD = -1 }
        unlink(path)
    }

    // The 2 s deadline is what bounds a slow sender; this cap only stops an extreme flood.
    static let maxReadsInFlight = 256
    private let readLock = NSLock()
    private var readsInFlight = 0

    private func beginRead() -> Bool {
        readLock.lock(); defer { readLock.unlock() }
        guard readsInFlight < Self.maxReadsInFlight else { return false }
        readsInFlight += 1
        return true
    }

    private func endRead() {
        readLock.lock(); readsInFlight -= 1; readLock.unlock()
    }

    private func serve(_ fd: Int32) {
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        UnixSocket.setTimeouts(fd: fd, sendMs: 1000, recvMs: 0)
        // The whole message must arrive within two seconds, however it trickles in.
        let data = try? UnixSocket.readFrame(fd: fd, deadline: Date().addingTimeInterval(2))
        endRead()
        guard let data, let envelope = Envelope.decode(data) else {
            close(fd)
            return
        }
        guard envelope.blocking else {
            close(fd)
            DispatchQueue.main.async { self.handler(envelope, nil) }
            return
        }
        UnixSocket.setTimeouts(fd: fd, sendMs: 1000, recvMs: 0)
        let connection = BlockingConnection(fd: fd, queue: connectionQueue)
        DispatchQueue.main.async { self.handler(envelope, connection) }
    }
}
