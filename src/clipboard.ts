// Decky bundles execute in SharedJSContext, not necessarily the visible window.
export async function copyText(text: string, owner?: Document | null): Promise<void> {
  const clipboard = owner?.defaultView?.navigator.clipboard;
  if (!clipboard) throw new Error("clipboard_unavailable");
  await clipboard.writeText(text);
}
