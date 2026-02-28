"""Neovim connection bridge: reads events from stdin or pynvim RPC."""

import json
import sys
import threading


class NvimEvent:
    """Represents a parsed event from Neovim."""
    __slots__ = ("event_type", "row", "col", "combo", "level", "raw")

    def __init__(self, event_type, row=0, col=0, combo=0, level=0, raw=None):
        self.event_type = event_type
        self.row = row
        self.col = col
        self.combo = combo
        self.level = level
        self.raw = raw or {}


class NvimBridge:
    """Reads JSON-line events from stdin (piped from Neovim plugin via jobstart).

    Expected JSON format per line:
        {"event":"keystroke","row":10,"col":25,"combo":15,"level":2}

    Event types: keystroke, combo_update, cursor_move
    """

    def __init__(self, callback=None):
        self._callback = callback
        self._thread = None
        self._running = False

    def set_callback(self, callback):
        """Set the callback function invoked on each event: callback(NvimEvent)."""
        self._callback = callback

    def start(self):
        """Start reading events in a background thread."""
        if self._running:
            return
        self._running = True
        self._thread = threading.Thread(target=self._read_loop, daemon=True)
        self._thread.start()
        print("[nvim_bridge] Started stdin event reader", file=sys.stderr)

    def stop(self):
        self._running = False

    def _read_loop(self):
        """Read JSON lines from stdin until EOF or stopped."""
        try:
            for line in sys.stdin:
                if not self._running:
                    break
                line = line.strip()
                if not line:
                    continue
                try:
                    data = json.loads(line)
                except json.JSONDecodeError as e:
                    print(f"[nvim_bridge] JSON parse error: {e} | line: {line!r}", file=sys.stderr)
                    continue

                event = NvimEvent(
                    event_type=data.get("event", "unknown"),
                    row=data.get("row", 0),
                    col=data.get("col", 0),
                    combo=data.get("combo", 0),
                    level=data.get("level", 0),
                    raw=data,
                )

                if self._callback:
                    try:
                        self._callback(event)
                    except Exception as e:
                        print(f"[nvim_bridge] Callback error: {e}", file=sys.stderr)

        except Exception as e:
            print(f"[nvim_bridge] Read loop error: {e}", file=sys.stderr)
        finally:
            print("[nvim_bridge] Stdin reader exited", file=sys.stderr)
            self._running = False

    def _try_rpc_fallback(self):
        """Attempt direct pynvim RPC connection as fallback."""
        try:
            import pynvim
            nvim = pynvim.attach("socket", path="/tmp/nvim-power-mode.sock")
            print("[nvim_bridge] Connected via pynvim RPC", file=sys.stderr)
            return nvim
        except Exception as e:
            print(f"[nvim_bridge] RPC fallback failed: {e}", file=sys.stderr)
            return None
