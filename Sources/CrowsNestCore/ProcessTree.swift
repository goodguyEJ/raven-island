import Foundation

public enum ProcessTree {
    public struct Info { public var ppid: Int32; public var name: String; public var tty: String? }

    public static func info(pid: Int32) -> Info? {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        var kp = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        guard sysctl(&mib, 4, &kp, &size, nil, 0) == 0, size > 0 else { return nil }
        let name = withUnsafePointer(to: &kp.kp_proc.p_comm) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXCOMLEN) + 1) { String(cString: $0) }
        }
        var tty: String?
        let dev = kp.kp_eproc.e_tdev
        if dev != -1, let cname = devname(dev, S_IFCHR) {
            tty = "/dev/" + String(cString: cname)
        }
        return Info(ppid: kp.kp_eproc.e_ppid, name: name, tty: tty)
    }

    /// Parent chain starting at `pid`, nearest first, stopping before launchd.
    public static func ancestors(of pid: Int32 = getppid(), limit: Int = 12) -> (chain: [AncestorProcess], tty: String?) {
        var chain: [AncestorProcess] = []
        var tty: String?
        var current = pid
        while current > 1, chain.count < limit, let i = info(pid: current) {
            chain.append(AncestorProcess(pid: current, name: i.name))
            if tty == nil { tty = i.tty }
            current = i.ppid
        }
        return (chain, tty)
    }

    static let shells: Set<String> = ["sh", "bash", "zsh", "fish", "dash", "env"]

    /// The agent process is the nearest ancestor that isn't a shell wrapper.
    public static func agentPid(in chain: [AncestorProcess]) -> Int32? {
        chain.first { !shells.contains($0.name) }?.pid ?? chain.first?.pid
    }

    public static func isAlive(_ pid: Int32) -> Bool {
        kill(pid, 0) == 0 || errno == EPERM
    }
}
