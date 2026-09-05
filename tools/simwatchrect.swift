// Print the watch screen's rect in screen points: "x y w h".
// It is the largest AXGroup that is a direct child of the Simulator window.
import ApplicationServices
import Foundation
func pid(of name: String) -> pid_t? {
    let out = Pipe(); let p = Process()
    p.executableURL = URL(fileURLWithPath: "/bin/ps")
    p.arguments = ["-Aco", "pid,comm"]; p.standardOutput = out
    try? p.run(); p.waitUntilExit()
    let s = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    for line in s.split(separator: "\n") where line.hasSuffix(name) {
        return pid_t(line.trimmingCharacters(in: .whitespaces).split(separator: " ")[0]) ?? nil
    }
    return nil
}
func attr(_ e: AXUIElement, _ k: String) -> CFTypeRef? {
    var v: CFTypeRef?; return AXUIElementCopyAttributeValue(e, k as CFString, &v) == .success ? v : nil
}
func frame(_ e: AXUIElement) -> CGRect? {
    guard let pv = attr(e, kAXPositionAttribute), let sv = attr(e, kAXSizeAttribute) else { return nil }
    var pt = CGPoint.zero, sz = CGSize.zero
    AXValueGetValue(pv as! AXValue, .cgPoint, &pt); AXValueGetValue(sv as! AXValue, .cgSize, &sz)
    return CGRect(origin: pt, size: sz)
}
guard let p = pid(of: "Simulator") else { exit(1) }
var best: CGRect? = nil
for w in (attr(AXUIElementCreateApplication(p), kAXWindowsAttribute) as? [AXUIElement]) ?? [] {
    for c in (attr(w, kAXChildrenAttribute) as? [AXUIElement]) ?? [] {
        guard (attr(c, kAXRoleAttribute) as? String) == "AXGroup", let f = frame(c) else { continue }
        if best == nil || f.width * f.height > best!.width * best!.height { best = f }
    }
}
guard let r = best else { exit(1) }
print("\(Int(r.minX)) \(Int(r.minY)) \(Int(r.width)) \(Int(r.height))")
