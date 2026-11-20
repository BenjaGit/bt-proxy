"""Pausing the scanner while a connect is in flight (experiment, opt-in).

On a single-radio controller active scanning resumes the moment a link is
established, just when the first connection events decide whether the link
survives (HCI 0x3E). With pause_scan_on_connect the scanner is stopped for the
duration of connect_device() and started again afterwards, whatever the outcome.

Run: uv run --with pytest python -m pytest tests/
"""

import asyncio

import pytest
from bleak.exc import BleakError

import bt_proxy.ble_manager as ble_manager

ADDRESS = 0x00042F0F09A2


class FakeScanner:
    events: list[str] = []
    fail_next_start = False

    def __init__(self, **kwargs):
        pass

    async def start(self):
        if FakeScanner.fail_next_start:
            FakeScanner.fail_next_start = False
            raise BleakError("[org.bluez.Error.InProgress] Operation already in progress")
        FakeScanner.events.append("scan-start")

    async def stop(self):
        FakeScanner.events.append("scan-stop")


class FakeClient:
    outcome = "ok"

    def __init__(self, target, disconnected_callback=None, timeout=None):
        self.is_connected = False

    async def connect(self):
        FakeScanner.events.append("connect")
        if FakeClient.outcome == "fail":
            raise BleakError("[org.bluez.Error.Failed] br-connection-canceled")
        self.is_connected = True

    async def disconnect(self):
        self.is_connected = False


def make_manager(monkeypatch, pause):
    FakeScanner.events = []
    FakeScanner.fail_next_start = False
    FakeClient.outcome = "ok"
    monkeypatch.setattr(ble_manager, "BleakScanner", FakeScanner)
    monkeypatch.setattr(ble_manager, "BleakClient", FakeClient)
    monkeypatch.setattr(ble_manager, "SCAN_START_RETRY_DELAY", 0)

    async def no_bluez(self, mac):
        return None

    monkeypatch.setattr(ble_manager.BLEManager, "_bluez_clear_state", no_bluez)
    mgr = ble_manager.BLEManager(pause_scan_on_connect=pause)
    mgr.states = []
    mgr.set_callbacks(
        on_advertisement=lambda *a: None,
        on_disconnect=lambda *a: None,
        on_notify=lambda *a: None,
        on_scanner_state=mgr.states.append,
    )
    return mgr


async def scan_then_connect(mgr):
    await mgr.start_scanning()
    FakeScanner.events.clear()
    mgr.states.clear()
    return await mgr.connect_device(ADDRESS)


def test_scanner_is_left_alone_by_default(monkeypatch):
    mgr = make_manager(monkeypatch, pause=False)
    ok, _mtu, _err = asyncio.run(scan_then_connect(mgr))
    assert ok
    assert FakeScanner.events == ["connect"]


def test_scanner_is_paused_around_a_successful_connect(monkeypatch):
    mgr = make_manager(monkeypatch, pause=True)
    ok, _mtu, _err = asyncio.run(scan_then_connect(mgr))
    assert ok
    assert FakeScanner.events == ["scan-stop", "connect", "scan-start"]


def test_scanner_is_resumed_after_a_failed_connect(monkeypatch):
    mgr = make_manager(monkeypatch, pause=True)
    FakeClient.outcome = "fail"
    ok, _mtu, _err = asyncio.run(scan_then_connect(mgr))
    assert not ok
    assert FakeScanner.events == ["scan-stop", "connect", "scan-start"]


def test_pause_is_not_reported_to_home_assistant(monkeypatch):
    # The scanner is back within one connect timeout; a STOPPED state would
    # make Home Assistant treat the proxy as not scanning.
    mgr = make_manager(monkeypatch, pause=True)
    asyncio.run(scan_then_connect(mgr))
    assert mgr.states == []


def test_scanner_that_was_not_running_is_not_started(monkeypatch):
    mgr = make_manager(monkeypatch, pause=True)
    ok, _mtu, _err = asyncio.run(mgr.connect_device(ADDRESS))
    assert ok
    assert FakeScanner.events == ["connect"]


def test_resume_survives_a_transient_start_error(monkeypatch):
    mgr = make_manager(monkeypatch, pause=True)

    async def run():
        await mgr.start_scanning()
        FakeScanner.events.clear()
        FakeScanner.fail_next_start = True
        return await mgr.connect_device(ADDRESS)

    ok, _mtu, _err = asyncio.run(run())
    assert ok
    assert FakeScanner.events[-1] == "scan-start"
    assert mgr._scanning


def test_stop_request_during_a_pause_is_honoured(monkeypatch):
    # Home Assistant unsubscribing while a connect is in flight must not get
    # the scanner started again behind its back.
    mgr = make_manager(monkeypatch, pause=True)

    class StoppingClient(FakeClient):
        async def connect(self):
            await mgr.stop_scanning()
            await super().connect()

    monkeypatch.setattr(ble_manager, "BleakClient", StoppingClient)
    ok, _mtu, _err = asyncio.run(scan_then_connect(mgr))
    assert ok
    assert FakeScanner.events == ["scan-stop", "connect"]
    assert not mgr._scanning
