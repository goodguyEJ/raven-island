import Foundation

public enum SocketError: Error, Equatable {
    case posix(String, Int32)
    case closed
    case frameTooLarge
    case pathTooLong
}

/// Blocking POSIX Unix-domain socket helpers with length-prefixed frames
/// (4-byte big-endian length, then that many bytes).
public enum UnixSocket {
    public static let maxFrame = 8 * 1024 * 1024

    static func address(_ path: String) throws -> sockaddr_un {
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: addr.sun_path) else { throw SocketError.pathTooLong }
        withUnsafeMutableBytes(of: &addr.sun_path) { $0.copyBytes(from: bytes) }
        return addr
    }

    static func makeSocket() throws -> Int32 {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw SocketError.posix("socket", errno) }
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        return fd
    }

    /// Connects, or throws immediately if nothing is listening. Never blocks on a missing peer.
    public static func connect(path: String) throws -> Int32 {
        let fd = try makeSocket()
        var addr = try address(path)
        let flags = fcntl(fd, F_GETFL)
        _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)
        let rc = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard rc == 0 else { let e = errno; close(fd); throw SocketError.posix("connect", e) }
        _ = fcntl(fd, F_SETFL, flags)
        return fd
    }

    public static func listen(path: String, backlog: Int32 = 128) throws -> Int32 {
        let fd = try makeSocket()
        var addr = try address(path)
        let rc = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard rc == 0 else { let e = errno; close(fd); throw SocketError.posix("bind", e) }
        chmod(path, 0o600)
        guard Darwin.listen(fd, backlog) == 0 else { let e = errno; close(fd); throw SocketError.posix("listen", e) }
        return fd
    }

    /// 0 clears the timeout.
    public static func setTimeouts(fd: Int32, sendMs: Int, recvMs: Int) {
        func tv(_ ms: Int) -> timeval { timeval(tv_sec: ms / 1000, tv_usec: Int32((ms % 1000) * 1000)) }
        var s = tv(sendMs), r = tv(recvMs)
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &s, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &r, socklen_t(MemoryLayout<timeval>.size))
    }

    public static func writeAll(fd: Int32, _ data: Data) throws {
        try data.withUnsafeBytes { (buf: UnsafeRawBufferPointer) in
            var offset = 0
            while offset < buf.count {
                let n = write(fd, buf.baseAddress! + offset, buf.count - offset)
                if n < 0 {
                    if errno == EINTR { continue }
                    throw SocketError.posix("write", errno)
                }
                offset += n
            }
        }
    }

    public static func readExact(fd: Int32, count: Int) throws -> Data {
        var data = Data(count: count)
        var offset = 0
        try data.withUnsafeMutableBytes { (buf: UnsafeMutableRawBufferPointer) in
            while offset < count {
                let n = read(fd, buf.baseAddress! + offset, count - offset)
                if n == 0 { throw SocketError.closed }
                if n < 0 {
                    if errno == EINTR { continue }
                    throw SocketError.posix("read", errno)
                }
                offset += n
            }
        }
        return data
    }

    /// Reads one frame, giving up when `deadline` passes, however slowly the bytes arrive.
    /// Memory grows with what actually arrives, not with the length the sender claims.
    public static func readFrame(fd: Int32, deadline: Date) throws -> Data {
        func read(_ count: Int) throws -> Data {
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 64 * 1024)
            while data.count < count {
                let remaining = deadline.timeIntervalSinceNow
                guard remaining > 0 else { throw SocketError.posix("deadline", ETIMEDOUT) }
                var pfd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
                let ready = poll(&pfd, 1, Int32(max(1, min(remaining, 60) * 1000)))
                if ready < 0 { if errno == EINTR { continue }; throw SocketError.posix("poll", errno) }
                if ready == 0 { continue }
                let n = Darwin.read(fd, &buffer, min(buffer.count, count - data.count))
                if n == 0 { throw SocketError.closed }
                if n < 0 { if errno == EINTR || errno == EAGAIN { continue }; throw SocketError.posix("read", errno) }
                data.append(buffer, count: n)
            }
            return data
        }
        let header = try read(4)
        let len = header.withUnsafeBytes { Int(UInt32(bigEndian: $0.loadUnaligned(as: UInt32.self))) }
        guard len <= maxFrame else { throw SocketError.frameTooLarge }
        return len == 0 ? Data() : try read(len)
    }

    /// The process on the other end of a connected Unix socket.
    public static func peerPID(fd: Int32) -> pid_t? {
        var pid: pid_t = 0
        var size = socklen_t(MemoryLayout<pid_t>.size)
        // SOL_LOCAL = 0, LOCAL_PEERPID = 2 (sys/un.h)
        guard getsockopt(fd, 0, 2, &pid, &size) == 0, pid > 0 else { return nil }
        return pid
    }

    /// The executable a process is running, with symlinks resolved.
    public static func executablePath(pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return URL(fileURLWithPath: String(cString: buffer)).resolvingSymlinksInPath().path
    }

    public static func frame(_ body: Data) -> Data {
        var len = UInt32(body.count).bigEndian
        var out = Data(bytes: &len, count: 4)
        out.append(body)
        return out
    }

    public static func sendFrame(fd: Int32, _ body: Data) throws {
        guard body.count <= maxFrame else { throw SocketError.frameTooLarge }
        try writeAll(fd: fd, frame(body))
    }

    public static func readFrame(fd: Int32) throws -> Data {
        let header = try readExact(fd: fd, count: 4)
        let len = header.withUnsafeBytes { Int(UInt32(bigEndian: $0.loadUnaligned(as: UInt32.self))) }
        guard len <= maxFrame else { throw SocketError.frameTooLarge }
        return len == 0 ? Data() : try readExact(fd: fd, count: len)
    }
}
