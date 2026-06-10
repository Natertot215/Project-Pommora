//
//  NativeTextView+DragSelectBoost.swift
//  MarkdownPM
//
//  Created by Luca Chen on 16.03.26.
//
//  Mouse-down entry point for the text view, plus the autoscroll-boost timer
//  that keeps drag-selection moving when the cursor sits near a window edge.
//

import AppKit

extension NativeTextView {
    override func mouseDown(with event: NSEvent) {
        // Locked / read-only body: a press-and-drag moves the host window.
        // An NSTextView never participates in `isMovableByWindowBackground`
        // (mouse-down is consumed by the text system before the window's
        // drag handler sees it), so drive the standard window drag explicitly.
        // A plain click with no movement is harmlessly swallowed — the body
        // is non-selectable when read-only, so there's nothing to lose.
        if !isEditable {
            // Read-only body: resign any focused field elsewhere (e.g. an active
            // title rename, which a click on a non-first-responder view won't
            // otherwise dismiss), then drag the window.
            window?.makeFirstResponder(nil)
            window?.performDrag(with: event)
            return
        }
        if let toggled = toggleTaskCheckboxIfHit(event: event), toggled {
            return
        }
        if remapClickInParagraphSpacing(event: event) {
            return
        }
        // Hit-test the foldable-headings chevron rect before any drag-select
        // machinery so a chevron click toggles the fold without moving the
        // caret or arming the autoscroll boost timer.
        let viewPoint = convert(event.locationInWindow, from: nil)
        if handleHeadingChevronClick(at: viewPoint) {
            return
        }
        dragStartMouseScreenLoc = NSEvent.mouseLocation
        let boostTimer = Timer(timeInterval: 1.0 / configuration.dragSelection.ticksPerSecond, repeats: true) { [weak self] _ in
            self?.performDragBoostTick()
        }
        RunLoop.current.add(boostTimer, forMode: .common)
        defer {
            boostTimer.invalidate()
            dragStartMouseScreenLoc = nil
        }

        super.mouseDown(with: event)
    }

    func performDragBoostTick() {
        guard let window = self.window,
              let scrollView = enclosingScrollView,
              let start = dragStartMouseScreenLoc else { return }

        let mouseScreen = NSEvent.mouseLocation
        let dragPolicy = configuration.dragSelection
        // Require real drag movement so a static click at the window edge doesn't scroll.
        guard max(abs(mouseScreen.x - start.x), abs(mouseScreen.y - start.y)) > dragPolicy.movementThreshold else { return }

        let mouseInWin = window.convertPoint(fromScreen: mouseScreen)
        let direction: CGFloat
        if mouseInWin.y <= dragPolicy.edgeTriggerDistance {
            direction = 1.0
        } else if mouseInWin.y >= window.frame.height - dragPolicy.edgeTriggerDistance {
            direction = -1.0
        } else {
            return
        }

        let origin = scrollView.contentView.bounds.origin
        scrollView.contentView.scroll(to: NSPoint(x: origin.x, y: origin.y + dragPolicy.scrollStepPerTick * direction))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        (scrollView as? ClampedScrollView)?.clampToInsets()
    }
}
