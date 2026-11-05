// Support dialog and floating button. Loaded with defer, and only when a Ko-fi link is set.
(() => {
  const dialog = document.getElementById("support-dialog");
  if (!dialog || typeof dialog.showModal !== "function") return;
  const fab = document.getElementById("support-fab");
  const variants = dialog.querySelectorAll("[data-variant]");
  const NAVIGATION_START_MS = 400;
  let opener = null;
  let formTimer = 0;

  // The Ko-fi form is added on the first open, so the page itself never talks to Ko-fi.
  // A frame that never finished loading is replaced, so reopening the dialog can bring it back.
  const loadForm = () => {
    const box = dialog.querySelector("[data-embed-src]");
    if (!box || box.querySelector("iframe")?.dataset.loaded) return;
    const frame = document.createElement("iframe");
    frame.id = "kofiframe";
    frame.title = box.dataset.embedTitle;
    frame.setAttribute("referrerpolicy", "strict-origin-when-cross-origin");
    frame.addEventListener("load", () => { frame.dataset.loaded = "true"; });
    frame.src = box.dataset.embedSrc;
    box.replaceChildren(frame);
  };

  const open = (variant, from) => {
    opener = from;
    for (const v of variants) v.hidden = v.dataset.variant !== variant;
    dialog.setAttribute("aria-labelledby", dialog.querySelector(`[data-variant="${variant}"] h2`).id ||= `support-title-${variant}`);
    if (!dialog.open) dialog.showModal();
    // Firefox and WebKit stop every load in the page, child frames included, when the link's
    // navigation starts, and that happens after this click handler. So the form has to wait.
    clearTimeout(formTimer);
    if (variant === "download") formTimer = setTimeout(loadForm, NAVIGATION_START_MS);
    else loadForm();
  };

  // No preventDefault: the download link keeps working as a plain link.
  for (const a of document.querySelectorAll("a[data-download]")) {
    a.addEventListener("click", () => open("download", a));
  }
  fab?.addEventListener("click", () => open("support", fab));

  dialog.querySelector("[data-close]").addEventListener("click", () => dialog.close());
  dialog.addEventListener("click", (e) => {
    if (e.target !== dialog) return;
    const r = dialog.getBoundingClientRect();
    const inside = e.clientX >= r.left && e.clientX <= r.right && e.clientY >= r.top && e.clientY <= r.bottom;
    if (!inside) dialog.close();
  });
  dialog.addEventListener("close", () => {
    clearTimeout(formTimer);
    if (opener?.isConnected) opener.focus({ preventScroll: true });
    opener = null;
  });

  // The button shows once the hero has scrolled away, and steps aside near the page's own support and download blocks.
  if (fab && "IntersectionObserver" in window) {
    const seen = new Map();
    const update = () => {
      const heroGone = seen.get("hero") === false;
      const nearEnd = ["support", "download"].some((id) => seen.get(id));
      fab.hidden = !(heroGone && !nearEnd);
    };
    const io = new IntersectionObserver((entries) => {
      for (const e of entries) seen.set(e.target.id, e.isIntersecting);
      update();
    });
    for (const id of ["hero", "support", "download"]) {
      const el = document.getElementById(id);
      if (el) io.observe(el);
    }
  }
})();
