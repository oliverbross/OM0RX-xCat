"""Serialized FLEX I/O primitives used by the standalone coordinator."""

from __future__ import annotations

import asyncio
import threading
import time
from concurrent.futures import ThreadPoolExecutor
from functools import partial
from typing import Any, Callable

_command_lock = asyncio.Lock()
_radio_executor = ThreadPoolExecutor(max_workers=2, thread_name_prefix="flex-radio-io")
_radio_io_lock = threading.RLock()


def get_radio_command_lock() -> asyncio.Lock:
    """Return the process-wide lock used by all coordinated FLEX mutations."""
    return _command_lock


class RadioIODeadlineError(TimeoutError):
    """The operation could not enter the shared FLEX socket lane in time."""


def run_radio_io_sync(
    operation: Callable[[], Any],
    *,
    cancel_event: threading.Event | None = None,
    admission_deadline: float | None = None,
) -> Any:
    if admission_deadline is None:
        _radio_io_lock.acquire()
    else:
        remaining = admission_deadline - time.monotonic()
        if remaining <= 0 or not _radio_io_lock.acquire(timeout=remaining):
            raise RadioIODeadlineError("FLEX socket I/O admission timed out")
    try:
        if cancel_event is not None and cancel_event.is_set():
            raise RadioIODeadlineError("FLEX socket I/O was cancelled before admission")
        if admission_deadline is not None and time.monotonic() >= admission_deadline:
            raise RadioIODeadlineError("FLEX socket I/O admission timed out")
        return operation()
    finally:
        _radio_io_lock.release()


async def run_radio_io(
    operation: Callable[[], Any], *, timeout: float | None = None
) -> Any:
    loop = asyncio.get_running_loop()
    cancel_event = threading.Event()
    deadline = time.monotonic() + timeout if timeout is not None else None
    future = loop.run_in_executor(
        _radio_executor,
        partial(
            run_radio_io_sync,
            operation,
            cancel_event=cancel_event,
            admission_deadline=deadline,
        ),
    )
    try:
        if timeout is None:
            return await future
        return await asyncio.wait_for(future, timeout=max(0.01, float(timeout)))
    except (asyncio.CancelledError, TimeoutError):
        cancel_event.set()
        future.cancel()
        raise
