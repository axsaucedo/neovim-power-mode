#!/usr/bin/env python3
"""macOS transparent overlay for Neovim power-mode effects.

Reads JSON-line events from stdin and renders particles, combo counter,
and glow effects on a transparent always-on-top overlay window.

Usage:
    python main.py              # reads events from stdin
    echo '{"event":"keystroke","row":10,"col":25,"combo":5,"level":1}' | python main.py
"""

import math
import random
import signal
import sys
import threading

import AppKit
import Foundation
import Quartz

from particles import ParticleSystem
from nvim_bridge import NvimBridge
from window_tracker import WindowTracker

# --- Constants ---
FPS = 60.0
TIMER_INTERVAL = 1.0 / FPS

# Combo shake parameters
SHAKE_DECAY = 0.85
MAX_SHAKE = 8.0

# Glow parameters
GLOW_RADIUS = 40.0
GLOW_ALPHA_BASE = 0.3

# Level colors (indexed by power level 0-4)
LEVEL_COLORS = [
    (0.0, 1.0, 1.0),     # cyan
    (0.2, 1.0, 0.1),     # green
    (1.0, 0.8, 0.0),     # yellow
    (1.0, 0.4, 0.0),     # orange
    (1.0, 0.08, 0.58),   # deep pink
]


class OverlayView(AppKit.NSView):
    """Custom NSView that draws particles, combo counter, and glow."""

    def initWithFrame_(self, frame):
        self = super().initWithFrame_(frame)
        if self is None:
            return None
        self.particle_system = ParticleSystem()
        self.combo = 0
        self.level = 0
        self.cursor_screen_x = 0
        self.cursor_screen_y = 0
        self.shake_x = 0.0
        self.shake_y = 0.0
        self.glow_alpha = 0.0
        self._lock = threading.Lock()
        return self

    def isFlipped(self):
        # Use top-left origin to match screen coordinates
        return True

    def drawRect_(self, rect):
        context = AppKit.NSGraphicsContext.currentContext()
        if context is None:
            return
        cg = context.CGContext()

        with self._lock:
            particles = list(self.particle_system.get_particles())
            combo = self.combo
            level = self.level
            cx = self.cursor_screen_x
            cy = self.cursor_screen_y
            shake_x = self.shake_x
            shake_y = self.shake_y
            glow_alpha = self.glow_alpha

        # Draw glow behind cursor
        if glow_alpha > 0.01:
            self._draw_glow(cg, cx, cy, glow_alpha, level)

        # Draw particles
        for p in particles:
            r, g, b = p.color
            Quartz.CGContextSetRGBFillColor(cg, r / 255.0, g / 255.0, b / 255.0, p.alpha)
            circle = Quartz.CGRectMake(p.x - p.size, p.y - p.size, p.size * 2, p.size * 2)
            Quartz.CGContextFillEllipseInRect(cg, circle)

        # Draw combo counter
        if combo > 1:
            self._draw_combo(combo, level, cx, shake_x, shake_y)

    def _draw_glow(self, cg, cx, cy, alpha, level):
        """Draw radial glow at cursor position."""
        lr, lg, lb = LEVEL_COLORS[min(level, len(LEVEL_COLORS) - 1)]
        color_space = Quartz.CGColorSpaceCreateDeviceRGB()
        colors = [lr, lg, lb, alpha * GLOW_ALPHA_BASE, lr, lg, lb, 0.0]
        locations = [0.0, 1.0]
        gradient = Quartz.CGGradientCreateWithColorComponents(
            color_space, colors, locations, 2
        )
        center = Quartz.CGPointMake(cx, cy)
        radius = GLOW_RADIUS + (level * 10)
        Quartz.CGContextDrawRadialGradient(
            cg, gradient, center, 0, center, radius,
            Quartz.kCGGradientDrawsBeforeStartLocation | Quartz.kCGGradientDrawsAfterEndLocation
        )

    def _draw_combo(self, combo, level, cx, shake_x, shake_y):
        """Draw combo counter text with shake effect."""
        lr, lg, lb = LEVEL_COLORS[min(level, len(LEVEL_COLORS) - 1)]
        color = AppKit.NSColor.colorWithCalibratedRed_green_blue_alpha_(lr, lg, lb, 0.9)

        font_size = min(28 + level * 4, 48)
        font = AppKit.NSFont.boldSystemFontOfSize_(font_size)
        shadow = AppKit.NSShadow.alloc().init()
        shadow.setShadowColor_(AppKit.NSColor.colorWithCalibratedRed_green_blue_alpha_(lr, lg, lb, 0.6))
        shadow.setShadowOffset_(AppKit.NSMakeSize(0, -2))
        shadow.setShadowBlurRadius_(8.0)

        attrs = {
            AppKit.NSFontAttributeName: font,
            AppKit.NSForegroundColorAttributeName: color,
            AppKit.NSShadowAttributeName: shadow,
        }

        text = Foundation.NSString.stringWithString_(f"{combo}x")
        text_size = text.sizeWithAttributes_(attrs)

        # Position: above cursor, centered, with shake
        draw_x = cx - text_size.width / 2 + shake_x
        draw_y = max(10, self.cursor_screen_y - 50) + shake_y
        point = Foundation.NSMakePoint(draw_x, draw_y)
        text.drawAtPoint_withAttributes_(point, attrs)

    def update_state(self, dt):
        """Called by timer to update animation state."""
        with self._lock:
            self.particle_system.update(dt)
            # Decay shake
            self.shake_x *= SHAKE_DECAY
            self.shake_y *= SHAKE_DECAY
            # Decay glow
            self.glow_alpha = max(0.0, self.glow_alpha - dt * 2.0)

    def on_event(self, event):
        """Handle incoming Neovim event (called from bridge thread)."""
        with self._lock:
            self.combo = event.combo
            self.level = event.level
            if event.row > 0 and event.col > 0:
                # Will be mapped to screen coords by the app controller
                self._pending_row = event.row
                self._pending_col = event.col
            if event.event_type == "keystroke":
                # Trigger particles at cursor
                self.particle_system.spawn(
                    self.cursor_screen_x, self.cursor_screen_y,
                    count=3 + min(event.level * 2, 10)
                )
                # Trigger shake
                intensity = min(event.level + 1, 5)
                self.shake_x = random.uniform(-MAX_SHAKE, MAX_SHAKE) * (intensity / 5.0)
                self.shake_y = random.uniform(-MAX_SHAKE, MAX_SHAKE) * (intensity / 5.0)
                # Trigger glow
                self.glow_alpha = min(1.0, 0.3 + event.level * 0.15)


class OverlayApp:
    """Main application controller."""

    def __init__(self):
        self.app = AppKit.NSApplication.sharedApplication()
        self.app.setActivationPolicy_(AppKit.NSApplicationActivationPolicyAccessory)
        self.window = None
        self.view = None
        self.timer = None
        self.bridge = NvimBridge()
        self.tracker = WindowTracker()
        self._setup_window()
        self._setup_bridge()

    def _setup_window(self):
        """Create transparent, click-through, always-on-top overlay window."""
        screen = AppKit.NSScreen.mainScreen()
        frame = screen.frame()

        self.window = AppKit.NSWindow.alloc().initWithContentRect_styleMask_backing_defer_(
            frame,
            AppKit.NSWindowStyleMaskBorderless,
            AppKit.NSBackingStoreBuffered,
            False,
        )
        self.window.setBackgroundColor_(AppKit.NSColor.clearColor())
        self.window.setOpaque_(False)
        self.window.setLevel_(AppKit.NSFloatingWindowLevel)
        self.window.setIgnoresMouseEvents_(True)
        self.window.setHasShadow_(False)
        self.window.setCollectionBehavior_(
            AppKit.NSWindowCollectionBehaviorCanJoinAllSpaces
            | AppKit.NSWindowCollectionBehaviorStationary
        )

        self.view = OverlayView.alloc().initWithFrame_(frame)
        self.window.setContentView_(self.view)
        self.window.makeKeyAndOrderFront_(None)

        print(f"[main] Overlay window created: {int(frame.size.width)}x{int(frame.size.height)}", file=sys.stderr)

    def _setup_bridge(self):
        """Set up the Neovim event bridge."""
        def on_event(event):
            # Map cursor to screen coordinates
            screen_pos = self.tracker.cursor_to_screen(event.row, event.col)
            if screen_pos:
                sx, sy = screen_pos
                # Convert from top-left screen coords to NSView coords (flipped view)
                with self.view._lock:
                    self.view.cursor_screen_x = sx
                    self.view.cursor_screen_y = sy
            self.view.on_event(event)

        self.bridge.set_callback(on_event)

    def _tick(self, timer):
        """Timer callback: update physics and trigger redraw."""
        self.view.update_state(TIMER_INTERVAL)
        self.view.setNeedsDisplay_(True)

    def run(self):
        """Start the overlay application."""
        # Start Neovim bridge in background thread
        self.bridge.start()

        # Set up 60fps timer on main thread
        self.timer = Foundation.NSTimer.scheduledTimerWithTimeInterval_target_selector_userInfo_repeats_(
            TIMER_INTERVAL, self, "_tick:", None, True
        )
        Foundation.NSRunLoop.currentRunLoop().addTimer_forMode_(
            self.timer, Foundation.NSRunLoopCommonModes
        )

        print("[main] Power Mode overlay running (60fps). Send JSON events to stdin.", file=sys.stderr)
        print("[main] Example: {\"event\":\"keystroke\",\"row\":10,\"col\":25,\"combo\":5,\"level\":1}", file=sys.stderr)
        print("[main] Press Ctrl+C to quit.", file=sys.stderr)

        # Run the Cocoa event loop
        self.app.run()

    def shutdown(self):
        """Graceful shutdown."""
        print("\n[main] Shutting down...", file=sys.stderr)
        self.bridge.stop()
        if self.timer:
            self.timer.invalidate()
        if self.window:
            self.window.orderOut_(None)
        self.app.terminate_(None)


def main():
    overlay = OverlayApp()

    def signal_handler(sig, frame):
        overlay.shutdown()

    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)

    try:
        overlay.run()
    except KeyboardInterrupt:
        overlay.shutdown()


if __name__ == "__main__":
    main()
