"""mDNS must advertise a routable address, not the loopback fallback.

When the service starts before DHCP has finished, get_local_ip() falls back to
127.0.0.1. Advertising that makes the proxy undiscoverable until a restart, so
startup waits for a real address instead.

Run: uv run --with pytest python -m pytest tests/
"""

import asyncio

import bt_proxy.__main__ as main


def test_waits_until_a_routable_address_appears(monkeypatch):
    answers = iter(["127.0.0.1", "127.0.0.1", "192.168.40.5"])
    monkeypatch.setattr(main, "get_local_ip", lambda: next(answers))
    monkeypatch.setattr(main, "LOCAL_IP_RETRY_INTERVAL", 0)

    assert asyncio.run(main.wait_for_local_ip()) == "192.168.40.5"


def test_returns_at_once_when_the_network_is_up(monkeypatch):
    calls = []

    def ip():
        calls.append(1)
        return "192.168.40.4"

    monkeypatch.setattr(main, "get_local_ip", ip)

    assert asyncio.run(main.wait_for_local_ip()) == "192.168.40.4"
    assert len(calls) == 1


def test_register_mdns_advertises_the_awaited_address(monkeypatch):
    seen = {}

    class FakeZeroconf:
        def __init__(self, ip_version=None):
            pass

        async def async_register_service(self, info):
            seen["addresses"] = info.parsed_addresses()

    monkeypatch.setattr(main, "AsyncZeroconf", FakeZeroconf)

    asyncio.run(main.register_mdns("bt-proxy-2", 6053, "B8:27:EB:3D:94:5D", "192.168.40.5"))

    assert seen["addresses"] == ["192.168.40.5"]
