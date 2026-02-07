//
//  MouseHelpers.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation
import OSLog

// MARK: - Logger Extension

private extension Logger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? ""

    /// Logger for mouse helper operations.
    static let mouseHelpers = Logger(subsystem: subsystem, category: "MouseHelpers")
}

/// A namespace for mouse helper operations.
enum MouseHelpers {
    private static let cursorLock = DispatchQueue(label: "MouseHelpers.cursorLock")
    private static var cursorHideCount = 0
    private static var autoShowWorkItem: DispatchWorkItem?
    private static let watchdogTimeout: DispatchTimeInterval = .seconds(2)

    private static func scheduleAutoShow() {
        let workItem = DispatchWorkItem {
            forceShowCursor(reason: "watchdog timeout")
        }
        autoShowWorkItem?.cancel()
        autoShowWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + watchdogTimeout, execute: workItem)
    }

    private static func cancelAutoShow() {
        autoShowWorkItem?.cancel()
        autoShowWorkItem = nil
    }

    private static func forceShowCursor(reason: String) {
        cursorLock.sync { cursorHideCount = 0 }
        let result = CGDisplayShowCursor(CGMainDisplayID())
        if result != .success {
            Logger.mouseHelpers.error("Force show cursor failed (reason: \(reason), error: \(result.rawValue))")
        } else {
            Logger.mouseHelpers.info("Cursor force-shown (reason: \(reason))")
        }
    }

    /// Returns the location of the mouse cursor in the coordinate
    /// space used by `AppKit`, with the origin at the bottom left
    /// of the screen.
    static var locationAppKit: CGPoint? {
        CGEvent(source: nil)?.unflippedLocation
    }

    /// Returns the location of the mouse cursor in the coordinate
    /// space used by `CoreGraphics`, with the origin at the top left
    /// of the screen.
    static var locationCoreGraphics: CGPoint? {
        CGEvent(source: nil)?.location
    }

    /// Hides the mouse cursor and increments the hide cursor count.
    static func hideCursor() {
        var shouldHide = false
        cursorLock.sync {
            cursorHideCount += 1
            shouldHide = cursorHideCount == 1
        }

        guard shouldHide else { return }

        let result = CGDisplayHideCursor(CGMainDisplayID())
        if result != .success {
            Logger.mouseHelpers.error("CGDisplayHideCursor failed with error code \(result.rawValue)")
            cursorLock.sync { cursorHideCount = 0 } // Reset on failure
        } else {
            scheduleAutoShow()
        }
    }

    /// Decrements the hide cursor count and shows the mouse cursor
    /// if the count is `0`.
    static func showCursor() {
        var shouldShow = false
        var wasAlreadyZero = false
        cursorLock.sync {
            if cursorHideCount > 0 {
                cursorHideCount -= 1
                shouldShow = cursorHideCount == 0
            } else {
                wasAlreadyZero = true
            }
        }

        if wasAlreadyZero {
            Logger.mouseHelpers.debug("showCursor called with count already zero")
            return
        }

        guard shouldShow else { return }

        cancelAutoShow()

        let result = CGDisplayShowCursor(CGMainDisplayID())
        if result != .success {
            Logger.mouseHelpers.error("CGDisplayShowCursor failed with error code \(result.rawValue)")
            // Don't reset count on failure to prevent imbalance
        }
    }

    /// Moves the mouse cursor to the given point without generating
    /// events.
    ///
    /// - Parameter point: The point to move the cursor to in global
    ///   display coordinates.
    static func warpCursor(to point: CGPoint) {
        let result = CGWarpMouseCursorPosition(point)
        if result != .success {
            Logger.mouseHelpers.error("CGWarpMouseCursorPosition failed with error code \(result.rawValue)")
        }
    }

    /// Connects or disconnects the positions of the mouse and cursor.
    ///
    /// - Parameter connected: A Boolean value that determines whether
    ///   to connect or disconnect the positions.
    static func associateMouseAndCursor(_ connected: Bool) {
        let result = CGAssociateMouseAndMouseCursorPosition(connected ? 1 : 0)
        if result != .success {
            Logger.mouseHelpers.error("CGAssociateMouseAndMouseCursorPosition failed with error code \(result.rawValue)")
        }
    }

    /// Returns a Boolean value that indicates whether a mouse button
    /// is pressed.
    ///
    /// - Parameter button: The mouse button to check. Pass `nil` to
    ///   check all available mouse buttons (Quartz supports up to 32).
    static func isButtonPressed(_ button: CGMouseButton? = nil) -> Bool {
        let stateID = CGEventSourceStateID.combinedSessionState
        if let button {
            return CGEventSource.buttonState(stateID, button: button)
        }
        for n: UInt32 in 0 ... 31 {
            guard
                let button = CGMouseButton(rawValue: n),
                CGEventSource.buttonState(stateID, button: button)
            else {
                continue
            }
            return true
        }
        return false
    }

    /// Returns a Boolean value that indicates whether the last mouse
    /// movement event occurred within the given duration.
    ///
    /// - Parameter duration: The duration within which the last mouse
    ///   movement event must have occurred in order to return `true`.
    static func lastMovementOccurred(within duration: Duration) -> Bool {
        let stateID = CGEventSourceStateID.combinedSessionState
        let seconds = CGEventSource.secondsSinceLastEventType(stateID, eventType: .mouseMoved)
        return .seconds(seconds) <= duration
    }

    /// Returns a Boolean value that indicates whether the last scroll
    /// wheel event occurred within the given duration.
    ///
    /// - Parameter duration: The duration within which the last scroll
    ///   wheel event must have occurred in order to return `true`.
    static func lastScrollWheelOccurred(within duration: Duration) -> Bool {
        let stateID = CGEventSourceStateID.combinedSessionState
        let seconds = CGEventSource.secondsSinceLastEventType(stateID, eventType: .scrollWheel)
        return .seconds(seconds) <= duration
    }
}
