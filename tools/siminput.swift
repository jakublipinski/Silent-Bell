// Synthesise taps and Crown scrolls on the watch Simulator.
//
// Two things that are easy to get wrong and cost an hour each:
//   * The Simulator must be the ACTIVE app or it swallows the click. We raise it
//     with NSRunningApplication.activate(), which is a normal API call — not an
//     Apple event, so it needs no Automation permission (that is the one
//     AppleScript/System Events requires, and the one we do not have).
//   * A mouseDown without .mouseEventClickState set to 1 is not a click as far
//     as most apps are concerned; the press lands and nothing happens.
import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

guard AXIsProcessTrusted() else {
    FileHandle.standardError.write("not trusted for Accessibility\n".data(using: .utf8)!); exit(2)
}
func raiseSimulator() {
    guard let app = NSWorkspace.shared.runningApplications
        .first(where: { $0.bundleIdentifier == "com.apple.iphonesimulator" }) else { return }
    if !app.isActive { app.activate(options: []); usleep(700_000) }
}
let a = CommandLine.arguments
let cmd = a[1]
if cmd == "check" { exit(0) }   // pre-flight: we got here, so we are trusted
let pt = CGPoint(x: Double(a[2])!, y: Double(a[3])!)
raiseSimulator()

func move(_ p: CGPoint) {
    CGEvent(mouseEventSource: nil, mouseType: .mouseMoved,
            mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
    usleep(150_000)
}
switch cmd {
case "click":
    move(pt)
    let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown,
                       mouseCursorPosition: pt, mouseButton: .left)!
    down.setIntegerValueField(.mouseEventClickState, value: 1)
    down.post(tap: .cghidEventTap)
    usleep(110_000)
    let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp,
                     mouseCursorPosition: pt, mouseButton: .left)!
    up.setIntegerValueField(.mouseEventClickState, value: 1)
    up.post(tap: .cghidEventTap)
    usleep(200_000)
case "scroll":
    let amount = Int32(a[4])!, steps = 10
    move(pt)
    for _ in 0..<steps {
        CGEvent(scrollWheelEvent2Source: nil, units: .pixel,
                wheelCount: 1, wheel1: amount / Int32(steps), wheel2: 0, wheel3: 0)?
            .post(tap: .cghidEventTap)
        usleep(50_000)
    }
default: exit(1)
}
