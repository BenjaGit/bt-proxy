"""Links the client never uses or releases are closed by the proxy.

Seen 20/11-2026 on bt-proxy-1: Home Assistant gave up on a connect (cancelled
on its side) while the proxy was still connecting. No disconnect request is
sent in that case, so the link the proxy brought up stayed for hours, the
thermostat stopped advertising and the slot was never freed.

Run: uv run --with pytest python -m pytest tests/
"""

import asyncio

import pytest

import bt_proxy.ble_manager as ble_manager

ADDRESS = 0x00042F957685


class FakeClient:
    reports_disconnect = True
    instances: list["FakeClient"] = []

    def __init__(self, target, disconnected_callback=None, timeout=None):
        self._callback = disconnected_callback
        self.is_connected = False
        self.disconnect_calls = 0
        FakeClient.instances.append(self)

    async def connect(self):
        self.is_connected = True

    async def disconnect(self):
        self.disconnect_calls += 1
        self.is_connected = False
        if FakeClient.reports_disconnect:
            self._callback(self)


def make_manager(monkeypatch, **kwargs):
    FakeClient.reports_disconnect = True
    FakeClient.instances = []
    monkeypatch.setattr(ble_manager, "BleakClient", FakeClient)
    monkeypatch.setattr(ble_manager, "IDLE_CHECK_INTERVAL", 0.01)

    async def no_bluez(self, mac):
        return None

    monkeypatch.setattr(ble_manager.BLEManager, "_bluez_clear_state", no_bluez)
    mgr = ble_manager.BLEManager(**kwargs)
    mgr.told = []
    mgr.set_callbacks(
        on_advertisement=lambda *a: None,
        on_disconnect=mgr.told.append,
        on_notify=lambda *a: None,
    )
    return mgr


async def settle(mgr):
    for _ in range(50):
        await asyncio.sleep(0.01)
        if not mgr._connections:
            return


def test_unused_link_is_closed_and_the_client_told(monkeypatch):
    async def run():
        mgr = make_manager(monkeypatch, idle_timeout=0.05)
        assert (await mgr.connect_device(ADDRESS))[0]
        await settle(mgr)
        assert FakeClient.instances[0].disconnect_calls == 1
        assert mgr.free_connections == mgr.max_connections
        assert mgr.told == [ADDRESS]
        await mgr.cleanup()

    asyncio.run(run())


def test_client_is_told_even_if_bluez_never_reports_the_disconnect(monkeypatch):
    async def run():
        mgr = make_manager(monkeypatch, idle_timeout=0.05)
        FakeClient.reports_disconnect = False
        assert (await mgr.connect_device(ADDRESS))[0]
        await settle(mgr)
        assert mgr.allocated_addresses == []
        assert mgr.told == [ADDRESS]
        await mgr.cleanup()

    asyncio.run(run())


def test_link_in_use_is_kept(monkeypatch):
    async def run():
        mgr = make_manager(monkeypatch, idle_timeout=0.1)
        assert (await mgr.connect_device(ADDRESS))[0]
        for _ in range(20):
            await asyncio.sleep(0.02)
            assert mgr.get_connection(ADDRESS) is not None  # a GATT request
        assert mgr.told == []
        await mgr.cleanup()

    asyncio.run(run())


def test_link_with_a_notification_subscription_is_kept(monkeypatch):
    async def run():
        mgr = make_manager(monkeypatch, idle_timeout=0.05)
        assert (await mgr.connect_device(ADDRESS))[0]
        mgr._connections[ADDRESS]._notify_handles.add(0x2A)
        await asyncio.sleep(0.3)
        assert mgr.allocated_addresses == [ADDRESS]
        assert mgr.told == []
        await mgr.cleanup()

    asyncio.run(run())


def test_zero_turns_it_off(monkeypatch):
    async def run():
        mgr = make_manager(monkeypatch, idle_timeout=0)
        assert (await mgr.connect_device(ADDRESS))[0]
        await asyncio.sleep(0.2)
        assert mgr.allocated_addresses == [ADDRESS]
        assert mgr._idle_task is None
        await mgr.cleanup()

    asyncio.run(run())


def test_watchdog_runs_again_for_a_later_link(monkeypatch):
    async def run():
        mgr = make_manager(monkeypatch, idle_timeout=0.05)
        assert (await mgr.connect_device(ADDRESS))[0]
        await settle(mgr)
        await asyncio.sleep(0.05)
        assert (await mgr.connect_device(ADDRESS))[0]
        await settle(mgr)
        assert mgr.told == [ADDRESS, ADDRESS]
        await mgr.cleanup()

    asyncio.run(run())
