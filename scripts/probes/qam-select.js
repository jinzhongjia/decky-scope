(() => {
  const button = [...document.querySelectorAll('[role="button"],button')].find(
    (e) =>
      e.textContent.trim() === "DeckScope" &&
      e.getBoundingClientRect().height > 0,
  );
  if (!button) return "DeckScope entry missing";
  button.dispatchEvent(new MouseEvent("click", { bubbles: true }));
  return "selected DeckScope";
})();
