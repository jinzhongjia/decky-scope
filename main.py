"""Stable Decky facade. Keep CALLABLES identical to src/api.ts."""
from bridge import Bridge

CALLABLES = frozenset("get_status get_device_info get_connectivity query_history set_config export_summary".split())


class Plugin:
    async def _main(self):
        self.bridge = Bridge()
        await self.bridge.start()

    async def _unload(self):
        if "bridge" in self.__dict__:
            await self.bridge.unload()

    def __getattr__(self, name):
        if name not in CALLABLES:
            raise AttributeError(name)
        return getattr(self.bridge, name)
