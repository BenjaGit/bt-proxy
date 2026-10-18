"""Connection tracking across connect retries (issue #13).

A failed attempt's disconnect callback must not untrack the connection that
a later attempt brings up, or Home Assistant's disconnect request finds
nothing and BlueZ keeps the link (and a proxy slot) forever.

Run: uv run --with pytest python -m pytest tests/
"""

import asyncio

import pytest
from bleak.exc import BleakError

import bt_proxy.ble_manager as ble_manager

ADDRESS = 0x00042F0F09A2


class FakeClient:
    """Stands in for BleakClient; each connect() follows the shared script."""

    script: list[str] = []
    instances: list["FakeClient"] = []

    def __init__(self, target, disconnected_callback=None, timeout=None):
        self._callback = disconnected_callback
        self.is_connected = False
        self.disconnect_calls = 0
        FakeClient.instances.append(self)

    async def connect(self):
        step = FakeClient.script.pop(0)
        if step == "inprogress":
            raise BleakError("[org.bluez.Error.InProgress] Operation already in progress")
        if step == "fail":
            # BlueZ reports the aborted link before connect() raises.
            self._callback(self)
            raise BleakError("[org.bluez.Error.Failed] br-connection-canceled")
        self.is_connected = True

    async def disconnect(self):
        self.disconnect_calls += 1
        self.is_connected = False

    def fire_disconnected(self):
        self._callback(self)


@pytest.fixture
def manager(monkeypatch):
    FakeClient.instances = []
    monkeypatch.setattr(ble_manager, "BleakClient", FakeClient)
    monkeypatch.setattr(ble_manager, "CONNECT_RETRY_DELAY", 0)

    async def no_bluez(self, mac):
        return None

    monkeypatch.setattr(ble_manager.BLEManager, "_bluez_clear_state", no_bluez)
    mgr = ble_manager.BLEManager()
    mgr.reported_disconnects = []
    mgr.set_callbacks(
        on_advertisement=lambda *a: None,
        on_disconnect=mgr.reported_disconnects.append,
        on_notify=lambda *a: None,
    )
    return mgr


def test_link_from_a_retry_stays_tracked(manager, monkeypatch):
    # Internal retries are off by default; the tracking must hold if enabled.
    monkeypatch.setattr(ble_manager, "CONNECT_MAX_RETRIES", 3)
    FakeClient.script = ["fail", "ok"]
    ok, _mtu, error = asyncio.run(manager.connect_device(ADDRESS))
    assert ok and error == 0
    assert manager.get_connection(ADDRESS) is not None

    live = FakeClient.instances[-1]
    asyncio.run(manager.disconnect_device(ADDRESS))
    assert live.disconnect_calls == 1
    assert manager.get_connection(ADDRESS) is None


def test_failed_attempt_is_not_reported_while_connecting(manager, monkeypatch):
    # Internal retries are off by default; the tracking must hold if enabled.
    monkeypatch.setattr(ble_manager, "CONNECT_MAX_RETRIES", 3)
    # Home Assistant gets one answer per connect request: the result of
    # connect_device(). A disconnect for an attempt that is being retried
    # would tell it the link is gone while it is still being set up.
    FakeClient.script = ["fail", "ok"]
    asyncio.run(manager.connect_device(ADDRESS))
    assert manager.reported_disconnects == []


def test_late_callback_from_an_earlier_attempt_is_ignored(manager, monkeypatch):
    # Internal retries are off by default; the tracking must hold if enabled.
    monkeypatch.setattr(ble_manager, "CONNECT_MAX_RETRIES", 3)
    FakeClient.script = ["fail", "ok"]
    asyncio.run(manager.connect_device(ADDRESS))
    first, live = FakeClient.instances[0], FakeClient.instances[-1]

    first.fire_disconnected()
    assert manager.get_connection(ADDRESS) is not None
    assert manager.reported_disconnects == []

    # The live link dropping is still reported. Bleak fires the callback on
    # the event loop, and the handler schedules BlueZ cleanup there.
    async def live_drop():
        live.is_connected = False
        live.fire_disconnected()
        await asyncio.sleep(0)

    asyncio.run(live_drop())
    assert manager.reported_disconnects == [ADDRESS]
    assert manager.get_connection(ADDRESS) is None


# Home Assistant (aioesphomeapi) gives up on a connect request after 20 s.
HA_CONNECT_RESPONSE_TIMEOUT = 20.0


def test_connect_answers_within_home_assistant_timeout():
    # A slower answer arrives after HA has moved on: the attempt is wasted and
    # the late link has to be torn down again.
    budget = ble_manager.CONNECT_TIMEOUT + ble_manager.MTU_ACQUIRE_TIMEOUT
    assert budget * ble_manager.CONNECT_MAX_RETRIES < HA_CONNECT_RESPONSE_TIMEOUT


def test_a_failed_request_is_answered_after_one_attempt(manager):
    # Retrying is Home Assistant's job (bleak_retry_connector); retrying here
    # too only stretches the answer past HA's timeout.
    FakeClient.script = ["fail", "ok"]
    ok, _mtu, _error = asyncio.run(manager.connect_device(ADDRESS))
    assert not ok
    assert len(FakeClient.instances) == 1


def test_first_failure_does_not_block_the_next_request(manager):
    # HA retries a failed connect right away; refusing that retry wastes the
    # poll. Only repeated failures should hold requests back.
    FakeClient.script = ["fail"]
    asyncio.run(manager.connect_device(ADDRESS))
    assert manager._connect_backoff_remaining(ADDRESS) == 0

    FakeClient.script = ["fail"]
    asyncio.run(manager.connect_device(ADDRESS))
    assert manager._connect_backoff_remaining(ADDRESS) > 0


def test_in_progress_state_is_cleared_even_on_the_last_attempt(manager, monkeypatch):
    removed = []

    async def remove_device(self, mac):
        removed.append(mac)

    monkeypatch.setattr(ble_manager.BLEManager, "_bluez_remove_device", remove_device)
    FakeClient.script = ["inprogress"]
    ok, _mtu, _error = asyncio.run(manager.connect_device(ADDRESS))
    assert not ok
    assert removed == ["00:04:2F:0F:09:A2"]
