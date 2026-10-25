import asyncio
import json
import unittest
from types import SimpleNamespace

from app.realtime.manager import ConnectionManager
from app.schemas.realtime import StallUpdated


class FakeSocket:
    def __init__(self, *, fail=False, block=False, ip="127.0.0.1"):
        self.client = SimpleNamespace(host=ip)
        self.fail = fail
        self.block = block
        self.messages = asyncio.Queue()
        self.started = asyncio.Event()
        self.closed = asyncio.Event()
        self.close_code = None

    async def accept(self):
        pass

    async def send_text(self, message):
        self.started.set()
        if self.fail:
            raise RuntimeError("peer disconnected")
        if self.block:
            await asyncio.Event().wait()
        self.messages.put_nowait(json.loads(message))

    async def close(self, code):
        self.close_code = code
        self.closed.set()


class ConnectionManagerTests(unittest.IsolatedAsyncioTestCase):
    async def test_global_and_per_ip_limits_release_slots_on_disconnect(self):
        manager = ConnectionManager(max_connections=2, max_per_ip=1)
        self.addAsyncCleanup(manager.close)
        first, same_ip = FakeSocket(ip="127.0.0.1"), FakeSocket(ip="127.0.0.1")
        second, third = FakeSocket(ip="127.0.0.2"), FakeSocket(ip="127.0.0.3")
        self.assertTrue(await manager.connect(first))
        self.assertFalse(await manager.connect(same_ip))
        self.assertEqual(same_ip.close_code, 1008)
        self.assertTrue(await manager.connect(second))
        self.assertFalse(await manager.connect(third))
        self.assertEqual(manager.connection_count, 2)
        await manager.disconnect(first)
        self.assertTrue(await manager.connect(same_ip))

    async def test_concurrent_handshakes_reserve_capacity_before_accept(self):
        manager = ConnectionManager(max_connections=1, max_per_ip=1)
        self.addAsyncCleanup(manager.close)
        entered, release = asyncio.Event(), asyncio.Event()
        first, second = FakeSocket(), FakeSocket()
        async def accept():
            entered.set()
            await release.wait()
        first.accept = accept
        pending = asyncio.create_task(manager.connect(first))
        await entered.wait()
        self.assertFalse(await manager.connect(second))
        release.set()
        self.assertTrue(await pending)

    async def test_failed_accept_returns_reserved_slot(self):
        manager = ConnectionManager(max_connections=1, max_per_ip=1)
        self.addAsyncCleanup(manager.close)
        failed = FakeSocket()
        async def fail():
            raise RuntimeError("handshake failed")
        failed.accept = fail
        with self.assertRaises(RuntimeError):
            await manager.connect(failed)
        self.assertTrue(await manager.connect(FakeSocket()))

    async def asyncSetUp(self):
        self.manager = ConnectionManager(send_timeout=0.1)
        self.addAsyncCleanup(self.manager.close)

    def notification(self, occupied=True):
        return StallUpdated(
            restroom_id=1, stall_id=1, occupied=occupied, total_stalls=1,
            available_stalls=int(not occupied), available_bidet_stalls=int(not occupied),
        )

    async def receive(self, socket):
        return await asyncio.wait_for(socket.messages.get(), timeout=1)

    async def test_multiple_clients_receive_fifo_and_shutdown_closes_all(self):
        sockets = [FakeSocket(), FakeSocket()]
        for socket in sockets:
            await self.manager.connect(socket)
        for state in (True, False, True):
            self.manager.broadcast(self.notification(state))
        for socket in sockets:
            received = [await self.receive(socket) for _ in range(3)]
            self.assertEqual([message["occupied"] for message in received], [True, False, True])
        await self.manager.close()
        self.assertEqual(self.manager.connection_count, 0)
        self.assertTrue(all(socket.close_code == 1000 for socket in sockets))

    async def test_send_failure_isolated_from_healthy_client(self):
        failed, healthy = FakeSocket(fail=True), FakeSocket()
        await self.manager.connect(failed)
        await self.manager.connect(healthy)
        self.manager.broadcast(self.notification())
        self.assertTrue((await self.receive(healthy))["occupied"])
        await asyncio.wait_for(failed.closed.wait(), timeout=1)
        self.assertEqual(failed.close_code, 1011)
        self.assertEqual(self.manager.connection_count, 1)
        self.manager.broadcast(self.notification(False))
        self.assertFalse((await self.receive(healthy))["occupied"])

    async def test_slow_send_does_not_delay_healthy_client_and_times_out(self):
        slow, healthy = FakeSocket(block=True), FakeSocket()
        await self.manager.connect(slow)
        await self.manager.connect(healthy)
        self.manager.broadcast(self.notification())
        await self.receive(healthy)
        self.assertFalse(slow.closed.is_set())
        await asyncio.wait_for(slow.closed.wait(), timeout=1)
        self.assertEqual(slow.close_code, 1011)
        self.assertEqual(self.manager.connection_count, 1)

    async def test_full_queue_drops_only_slow_client(self):
        manager = ConnectionManager(queue_size=1, send_timeout=5)
        self.addAsyncCleanup(manager.close)
        slow, healthy = FakeSocket(block=True), FakeSocket()
        await manager.connect(slow)
        await manager.connect(healthy)
        manager.broadcast(self.notification())
        await asyncio.wait_for(slow.started.wait(), timeout=1)
        await self.receive(healthy)
        manager.broadcast(self.notification(False))
        await self.receive(healthy)
        manager.broadcast(self.notification())
        self.assertTrue((await self.receive(healthy))["occupied"])
        await asyncio.wait_for(slow.closed.wait(), timeout=1)
        self.assertEqual(slow.close_code, 1011)
        self.assertEqual(manager.connection_count, 1)

    async def test_disconnect_is_idempotent_and_removes_recipient(self):
        socket = FakeSocket()
        await self.manager.connect(socket)
        await self.manager.disconnect(socket)
        await self.manager.disconnect(socket)
        self.manager.broadcast(self.notification())
        self.assertTrue(socket.messages.empty())
        self.assertEqual(socket.close_code, 1000)
        self.assertEqual(self.manager.connection_count, 0)


if __name__ == "__main__":
    unittest.main()
