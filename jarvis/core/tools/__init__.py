"""Werkzeuge (Phase 2).

`registry` haelt die Tools, `dispatch` fuehrt sie aus (Permission, Schema,
Timeout), `loop` dreht die Runde Modell → Tool → Modell.
"""

from core import delegation  # noqa: F401  - registriert ask_agent
from core.tools import builtin, memory_tools, outbox, search  # noqa: F401  - Registrierung per Import
from core.tools.dispatch import ToolCall, run_tool
from core.tools.loop import run_tool_loop
from core.tools.registry import all_tools, get, register, schemas_for

__all__ = [
    "ToolCall",
    "all_tools",
    "get",
    "register",
    "run_tool",
    "run_tool_loop",
    "schemas_for",
]
