"""Agent-owned station telemetry value types.

Persistence belongs to the former full application and is intentionally not a
Windows-agent dependency.  The coordinator accepts optional persistence
callbacks and otherwise operates entirely in memory.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime
from typing import Any, Mapping


@dataclass(frozen=True, slots=True)
class StationSnapshot:
    observed_at: datetime
    received_at: datetime
    source: str
    quality: str
    stale_after_seconds: float | None
    state: Mapping[str, Any]
    metrics: Mapping[str, float | int | bool | None] = field(default_factory=dict)
    units: Mapping[str, str] = field(default_factory=dict)


@dataclass(frozen=True, slots=True)
class StationEvent:
    occurred_at: datetime
    event_type: str
    severity: str
    source: str
    details: Mapping[str, Any] = field(default_factory=dict)
    correlation_id: str | None = None


@dataclass(frozen=True, slots=True)
class TuneResult:
    transaction_id: str
    started_at: datetime
    completed_at: datetime
    outcome: str
    source: str
    route_id: str | None = None
    frequency_hz: int | None = None
    swr_before: float | None = None
    swr_after: float | None = None
    details: Mapping[str, Any] = field(default_factory=dict)
