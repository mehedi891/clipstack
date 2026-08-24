#!/usr/bin/env swift
// Prints the window id of Clipstack's largest on-screen window, for
// screencapture -l. Window enumeration needs no special permission; capturing
// the pixels does.
import CoreGraphics
import Foundation

let minWidth = CommandLine.arguments.count > 1 ? Int(CommandLine.arguments[1]) ?? 0 : 0

guard let windows = CGWindowListCopyWindowInfo(
    [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
) as? [[String: Any]] else { exit(1) }

let candidates = windows.compactMap { w -> (id: Int, area: Double)? in
    guard (w[kCGWindowOwnerName as String] as? String)?.contains("Clipstack") == true,
          let id = w[kCGWindowNumber as String] as? Int,
          let bounds = w[kCGWindowBounds as String] as? [String: Double],
          let width = bounds["Width"], let height = bounds["Height"],
          Int(width) >= minWidth
    else { return nil }
    return (id, width * height)
}

guard let best = candidates.max(by: { $0.area < $1.area }) else { exit(1) }
print(best.id)
