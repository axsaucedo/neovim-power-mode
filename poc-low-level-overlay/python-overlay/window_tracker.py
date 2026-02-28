"""Track iTerm2 window position on macOS for cursor-to-screen mapping."""

import subprocess
import sys
import time

# Offsets to account for iTerm2 chrome, tab bar, tmux status, line numbers, etc.
DEFAULT_X_OFFSET = 4    # left padding inside terminal
DEFAULT_Y_OFFSET = 70   # title bar + tab bar approximate height
DEFAULT_CELL_WIDTH = 8
DEFAULT_CELL_HEIGHT = 16
CACHE_TTL = 2.0  # seconds between window position refreshes


class WindowTracker:
    def __init__(self, cell_width=DEFAULT_CELL_WIDTH, cell_height=DEFAULT_CELL_HEIGHT,
                 x_offset=DEFAULT_X_OFFSET, y_offset=DEFAULT_Y_OFFSET):
        self.cell_width = cell_width
        self.cell_height = cell_height
        self.x_offset = x_offset
        self.y_offset = y_offset
        self._cached_bounds = None
        self._cache_time = 0

    def get_iterm_window_bounds(self):
        """Get iTerm2 front window bounds via AppleScript. Returns (x, y, width, height) or None."""
        now = time.time()
        if self._cached_bounds and (now - self._cache_time) < CACHE_TTL:
            return self._cached_bounds

        script = '''
tell application "iTerm2"
    set w to front window
    set b to bounds of w
    return (item 1 of b) & "," & (item 2 of b) & "," & (item 3 of b) & "," & (item 4 of b)
end tell
'''
        try:
            result = subprocess.run(
                ["osascript", "-e", script],
                capture_output=True, text=True, timeout=3
            )
            if result.returncode != 0:
                print(f"[window_tracker] AppleScript error: {result.stderr.strip()}", file=sys.stderr)
                return self._cached_bounds

            parts = result.stdout.strip().split(",")
            if len(parts) != 4:
                print(f"[window_tracker] Unexpected bounds format: {result.stdout.strip()}", file=sys.stderr)
                return self._cached_bounds

            x1, y1, x2, y2 = [int(p.strip()) for p in parts]
            bounds = (x1, y1, x2 - x1, y2 - y1)
            self._cached_bounds = bounds
            self._cache_time = now
            return bounds

        except subprocess.TimeoutExpired:
            print("[window_tracker] AppleScript timed out", file=sys.stderr)
            return self._cached_bounds
        except Exception as e:
            print(f"[window_tracker] Error: {e}", file=sys.stderr)
            return self._cached_bounds

    def cursor_to_screen(self, row, col, window_bounds=None):
        """Map Neovim (row, col) to screen pixel coordinates.

        Args:
            row: Neovim cursor row (1-based)
            col: Neovim cursor column (1-based)
            window_bounds: (x, y, width, height) or None to auto-detect

        Returns:
            (screen_x, screen_y) in screen pixel coordinates, or None on failure.
        """
        if window_bounds is None:
            window_bounds = self.get_iterm_window_bounds()
        if window_bounds is None:
            return None

        win_x, win_y, win_w, win_h = window_bounds

        # Convert 1-based row/col to 0-based pixel offset within terminal content area
        pixel_x = win_x + self.x_offset + (col - 1) * self.cell_width
        pixel_y = win_y + self.y_offset + (row - 1) * self.cell_height

        return (pixel_x, pixel_y)

    def get_terminal_content_area(self, window_bounds=None):
        """Return the content area rect (x, y, w, h) inside the terminal window."""
        if window_bounds is None:
            window_bounds = self.get_iterm_window_bounds()
        if window_bounds is None:
            return None

        win_x, win_y, win_w, win_h = window_bounds
        return (
            win_x + self.x_offset,
            win_y + self.y_offset,
            win_w - self.x_offset * 2,
            win_h - self.y_offset - self.x_offset,
        )
