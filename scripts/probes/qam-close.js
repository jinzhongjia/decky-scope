(() => {
  const chunk = Object.keys(window).find((k) => /^webpackChunk/.test(k));
  let req;
  window[chunk].push([
    [Symbol("scope-qam")],
    {},
    (r) => {
      req = r;
    },
  ]);
  for (const id in req.m) {
    if (!String(req.m[id]).includes("NavigationManager")) continue;
    let exports;
    try {
      exports = req(id);
    } catch {
      continue;
    }
    for (const value of Object.values(exports)) {
      if (
        !value ||
        typeof value.Navigate !== "function" ||
        !value.NavigationManager
      )
        continue;
      const main = value.WindowStore?.GamepadUIMainWindowInstance;
      if (main?.MenuStore?.OpenQuickAccessMenu) {
        value.CloseSideMenus();
        return "closed side menus";
      }
      return {
        routerKeys: Object.keys(value),
        windowStoreKeys: Object.keys(value.WindowStore || {}),
      };
    }
  }
  return "router unavailable";
})();
