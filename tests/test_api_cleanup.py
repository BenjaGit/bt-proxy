"""BLE links must not outlive the API client that opened them.

Seen on a WiFi proxy: the WiFi dropped mid-session, Home Assistant never got
to send its disconnect, and three Danfoss eTRVs stayed connected (red LED, no
advertisements) for a day until the Pi was power-cycled.

Run: uv run --with pytest python -m pytest tests/
"""

import asyncio

import bt_proxy.api_server as api_server
from bt_proxy import proto

ADDRESS = 0x00042F0F131D
OTHER = 0x00042F9532CF


class FakeBLE:
    def __init__(self):
        self.connected: set[int] = set()
        self.disconnect_calls: list[int] = []
        self.free_connections = 3
        self.max_connections = 3
        self.allocated_addresses: list[int] = []

    async def connect_device(self, address):
        self.connected.add(address)
        return True, 23, 0

    async def disconnect_device(self, address):
        self.disconnect_calls.append(address)
        self.connected.discard(address)


class FakeWriter:
    def __init__(self):
        self.sent = bytearray()

    def get_extra_info(self, name, default=None):
        return ("192.168.40.2", 12345)

    def write(self, data):
        self.sent += data

    async def drain(self):
        pass

    def close(self):
        pass

    async def wait_closed(self):
        pass


class FakeServer:
    name = "test"

    def __init__(self, ble):
        self.ble_manager = ble
        self.removed = []

    def remove_connection(self, conn):
        self.removed.append(conn)


def _connect_request(address):
    return proto.encode_field_varint(1, address) + proto.encode_field_varint(
        2, proto.BLE_REQUEST_CONNECT_V3_WITH_CACHE
    )


def _frame(msg_type, data):
    return proto.frame_message(msg_type, data)


async def _run_client(feed: bytes, eof: bool, ble: FakeBLE, timeout=1.0):
    reader = asyncio.StreamReader()
    reader.feed_data(feed)
    if eof:
        reader.feed_eof()
    conn = api_server.APIConnection(reader, FakeWriter(), FakeServer(ble))
    await asyncio.wait_for(conn.run(), timeout)
    return conn


def test_dropped_client_releases_its_links():
    ble = FakeBLE()
    feed = _frame(proto.MSG_BLE_DEVICE_REQUEST, _connect_request(ADDRESS))
    asyncio.run(_run_client(feed, eof=True, ble=ble))
    assert ble.disconnect_calls == [ADDRESS]
    assert ble.connected == set()


def test_silent_client_is_dropped_and_releases_its_links(monkeypatch):
    # WiFi gone: no EOF, no reset, just silence.
    monkeypatch.setattr(api_server, "CLIENT_IDLE_TIMEOUT", 0.05)
    ble = FakeBLE()
    feed = _frame(proto.MSG_BLE_DEVICE_REQUEST, _connect_request(ADDRESS))
    asyncio.run(_run_client(feed, eof=False, ble=ble))
    assert ble.disconnect_calls == [ADDRESS]


def test_links_the_client_released_are_not_touched_again():
    ble = FakeBLE()
    disconnect = proto.encode_field_varint(1, ADDRESS) + proto.encode_field_varint(
        2, proto.BLE_REQUEST_DISCONNECT
    )
    feed = (
        _frame(proto.MSG_BLE_DEVICE_REQUEST, _connect_request(ADDRESS))
        + _frame(proto.MSG_BLE_DEVICE_REQUEST, _connect_request(OTHER))
        + _frame(proto.MSG_BLE_DEVICE_REQUEST, disconnect)
    )
    asyncio.run(_run_client(feed, eof=True, ble=ble))
    # ADDRESS once by request; only OTHER is left for the cleanup.
    assert ble.disconnect_calls == [ADDRESS, OTHER]


def test_link_lost_on_its_own_is_not_disconnected_again():
    ble = FakeBLE()

    async def scenario():
        reader = asyncio.StreamReader()
        reader.feed_data(
            _frame(proto.MSG_BLE_DEVICE_REQUEST, _connect_request(ADDRESS))
        )
        conn = api_server.APIConnection(reader, FakeWriter(), FakeServer(ble))
        task = asyncio.create_task(conn.run())
        await asyncio.sleep(0.01)
        conn.push_disconnect(ADDRESS)  # the eTRV dropped the link itself
        reader.feed_eof()
        await asyncio.wait_for(task, 1.0)

    asyncio.run(scenario())
    assert ble.disconnect_calls == []
