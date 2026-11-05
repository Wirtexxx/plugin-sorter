const ESC = { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" };
export const esc = (s) => String(s).replace(/[&<>"']/g, (c) => ESC[c]);

// For text on the page only: keeps the product's name on one line.
const nb = (s) => esc(s).replace(/FL Studio/g, "FL&nbsp;Studio");

const jsonLd = (obj) =>
  `<script type="application/ld+json">${JSON.stringify(obj).replace(/</g, "\\u003c")}</script>`;

/** Every image the pages reference. A release build fails if one is missing. */
export const RELEASE_IMAGES = [
  "picker-before.webp", "picker-after.webp",
  "app.webp", "app-800.webp", "app-cards.webp", "app-cards-800.webp",
  "strip.webp", "icon.png", "og.png",
];

// Sizes of the files scripts/assets.mjs writes.
const APP = { width: 1600, height: 1138 };
const PICKER = { width: 1600, height: 1016 };
const STRIP = { width: 2904, height: 66 };

const svg = (body, attrs = "") =>
  `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true" ${attrs}>${body}</svg>`;

const ICONS = {
  download: svg('<path d="M12 4v11m0 0 4.5-4.5M12 15l-4.5-4.5M5 19.5h14"/>'),
  arrow: svg('<path d="M4 12h15m0 0-5.5-5.5M19 12l-5.5 5.5"/>'),
  uninstall: svg('<path d="M4.5 7h15M9.5 7V4.5h5V7M6.5 7l1 12.5h9l1-12.5M10 11v5m4-5v5"/>'),
  duplicates: svg('<rect x="9" y="9" width="11" height="11" rx="2.5"/><path d="M5.5 15H5a1.5 1.5 0 0 1-1.5-1.5V5A1.5 1.5 0 0 1 5 3.5h8.5A1.5 1.5 0 0 1 15 5v.5"/>'),
  off: svg('<path d="M12 3.5v8M7 6.3a8 8 0 1 0 10 0"/>'),
  licenses: svg('<circle cx="8" cy="15.5" r="4.5"/><path d="m11.5 12.5 8-8m-3 3 2.5 2.5m-5.5.5 2 2"/>'),
  star: svg('<path d="m12 3.5 2.6 5.4 5.9.8-4.3 4.1 1 5.9-5.2-2.8-5.2 2.8 1-5.9-4.3-4.1 5.9-.8z"/>'),
  bug: svg('<path d="M12 21a8.5 8.5 0 1 0 0-17 8.5 8.5 0 0 0 0 17zM12 8.5v5m0 3.2v.1"/>'),
  heart: svg('<path d="M12 20s-7.5-4.6-7.5-10.2A4.3 4.3 0 0 1 12 7.2a4.3 4.3 0 0 1 7.5 2.6C19.5 15.4 12 20 12 20z"/>'),
};

const MARKS = {
  yes: '<path d="m5 12.5 4.5 4.5L19 7.5"/>',
  part: '<path d="M6 12h12"/>',
  no: '<path d="m7 7 10 10M17 7 7 17"/>',
};
const mark = (kind) =>
  `<svg class="mark mark-${kind}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${MARKS[kind]}</svg>`;

// A knob like the ones in the app: the arc covers 270 degrees at full value.
const arc = (value, cls = "") => {
  const full = 113.1;
  return `<circle cx="30" cy="30" r="24" fill="none" stroke="rgba(255,255,255,.1)" stroke-width="5" stroke-linecap="round" stroke-dasharray="${full} 151" transform="rotate(135 30 30)"/>
<circle class="${cls}" cx="30" cy="30" r="24" fill="none" stroke-width="5" stroke-linecap="round" stroke-dasharray="${(full * value).toFixed(1)} 151" transform="rotate(135 30 30)"/>`;
};

const SKINS = ["#A76BFF", "#35D8A6", "#FF9F43", "#5CB8FF"];

// What a picker looks like with no pictures. Only the local placeholder uses it.
const PLAIN_NAMES = [
  "Auto-Tune Pro", "CamelCrusher", "CLA-76 Stereo", "Crystalline", "FabFilter Micro", "GClip",
  "HalfTime", "Infiltrator", "kHs Bitcrush", "kHs Chorus", "kHs Clipper", "kHs Distortion",
  "kHs Filter", "kHs Flanger", "kHs Haas", "kHs Phaser", "kHs Resonator", "kHs Reverser",
  "OTT", "Portal", "Pro-C 2", "Pro-C 3", "Pro-DS", "Pro-G",
  "Pro-MB", "Pro-Q 4", "Pro-R 2", "RC-20 Retro Color", "Saturn 2", "ShaperBox 3",
  "Simplon", "soothe2", "The God Particle", "Thermal", "Timeless 3", "trueBalance",
  "ValhallaDelay", "ValhallaPlate", "ValhallaRoom", "ValhallaShimmer", "ValhallaUberMod", "Volcano 3",
];

export function page(copy, ctx) {
  const { lang, config, hasBefore, otherUrl, url } = ctx;
  const origin = `https://${config.domain}`;
  const enUrl = lang === "en" ? url : otherUrl;
  const ruUrl = lang === "ru" ? url : otherUrl;
  const image = `${origin}/assets/og.png`;
  const home = lang === "ru" ? "/ru/" : "/";
  const dl = (label = copy.hero.download, cls = "btn", icon = ICONS.download) =>
    `<a class="${cls}" data-download href="${esc(config.downloadUrl)}">${icon}${esc(label)}</a>`;

  const app = {
    "@context": "https://schema.org",
    "@type": "SoftwareApplication",
    name: "Plugin Sorter",
    applicationCategory: "MultimediaApplication",
    operatingSystem: "macOS 11+",
    description: copy.meta.description,
    url,
    downloadUrl: config.downloadUrl,
    license: "https://opensource.org/licenses/MIT",
    inLanguage: lang,
    offers: { "@type": "Offer", price: "0", priceCurrency: "USD" },
  };
  const faq = {
    "@context": "https://schema.org",
    "@type": "FAQPage",
    mainEntity: copy.faq.map((f) => ({
      "@type": "Question",
      name: f.q,
      acceptedAnswer: { "@type": "Answer", text: f.a },
    })),
  };

  const before = hasBefore
    ? `<img src="/assets/picker-before.webp" alt="${esc(copy.picker.beforeAlt)}" width="${PICKER.width}" height="${PICKER.height}" loading="lazy" decoding="async">`
    : `<div class="placeholder" role="img" aria-label="${esc(copy.picker.beforeAlt)}">
<div class="placeholder-names" aria-hidden="true">${PLAIN_NAMES.map((n) => `<span>${esc(n)}</span>`).join("")}</div>
<p class="placeholder-tag">${esc(copy.picker.placeholder)}</p>
</div>`;

  const heads = copy.compare.headers.map((h) => `<th scope="col" role="columnheader">${esc(h)}</th>`).join("");
  const cell = ([kind, text], label) =>
    `<td role="cell" data-label="${nb(label)}">${mark(kind)}${nb(text)}</td>`;
  const rows = copy.compare.rows
    .map((r) => `<tr role="row"><th scope="row" role="rowheader">${nb(r.label)}</th>${cell(r.fl, copy.compare.headers[1])}${cell(r.ps, copy.compare.headers[2])}</tr>`)
    .join("\n");

  const item = Object.fromEntries(copy.features.items.map((f) => [f.id, f]));
  const text = (f) => `<h3>${esc(f.title)}</h3>\n<p>${esc(f.text)}</p>`;
  const small = (id) =>
    `<article class="card card-${id} rise"><span class="ico">${ICONS[id]}</span>${text(item[id])}</article>`;

  const steps = copy.install.steps.map((s, i) => `<li class="step rise">
<div class="knob" aria-hidden="true"><svg viewBox="0 0 60 60">${arc((i + 1) / copy.install.steps.length, "knob-arc")}</svg>${i + 1}</div>
<div><h3>${esc(s.title)}</h3>
<p>${esc(s.text)}</p>
${(s.paths ?? []).map((p) => `<div class="path" data-macos><b>${esc(p.label)}</b>${esc(p.text)}</div>`).join("\n")}</div>
</li>`).join("\n");

  const koFi = config.koFiUrl;
  const embed = config.koFiEmbedUrl;
  const dialog = koFi
    ? `<dialog id="support-dialog" aria-labelledby="support-title">
<button type="button" class="dlg-x" data-close aria-label="${esc(copy.dialog.close)}">${svg('<path d="m6 6 12 12M18 6 6 18"/>')}</button>
<div data-variant="download">
<h2 id="support-title">${esc(copy.dialog.title)}</h2>
<p>${esc(copy.dialog.text)}</p>
<p class="muted">${esc(copy.dialog.macNote)}</p>
</div>
<div data-variant="support" hidden>
<h2>${esc(copy.dialog.supportTitle)}</h2>
<p>${esc(copy.dialog.supportText)}</p>
</div>
${embed ? `<div class="kofi" data-embed-src="${esc(embed)}"></div>\n` : ""}<p class="dlg-fallback"><a class="btn-ghost" href="${esc(koFi)}" target="_blank" rel="noopener">${ICONS.heart}${esc(copy.dialog.fallback)}</a></p>
<p class="muted dlg-note">${esc(copy.dialog.embedNote)}</p>
</dialog>
<button type="button" id="support-fab" class="fab" data-support-open hidden>${ICONS.heart}<span>${esc(copy.dialog.fab)}</span></button>`
    : "";
  const koFiLink = koFi ? `<a class="btn" href="${esc(koFi)}" rel="noopener">${ICONS.heart}${esc(copy.support.kofi)}</a>` : "";

  const stripImg = `<img src="/assets/strip.webp" alt="" aria-hidden="true" width="${STRIP.width}" height="${STRIP.height}" loading="lazy" decoding="async">`;
  const langSwitch = (code, href, label) =>
    code === lang
      ? `<span aria-current="true">${label}</span>`
      : `<a href="${href}" hreflang="${code}" lang="${code}">${label}</a>`;

  return `<!doctype html>
<html lang="${lang}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${esc(copy.meta.title)}</title>
<meta name="description" content="${esc(copy.meta.description)}">
<meta name="theme-color" content="#101014">
<link rel="canonical" href="${esc(url)}">
<link rel="alternate" hreflang="en" href="${esc(enUrl)}">
<link rel="alternate" hreflang="ru" href="${esc(ruUrl)}">
<link rel="alternate" hreflang="x-default" href="${esc(enUrl)}">
<link rel="icon" type="image/png" href="/assets/icon.png">
<link rel="apple-touch-icon" href="/assets/icon.png">
<link rel="preload" href="/assets/fonts/manrope-${lang === "ru" ? "cyrillic" : "latin"}.woff2" as="font" type="font/woff2" crossorigin>
<link rel="stylesheet" href="/assets/styles.css">
${koFi ? '<script src="/assets/site.js" defer></script>\n' : ""}<meta property="og:type" content="website">
<meta property="og:title" content="${esc(copy.meta.title)}">
<meta property="og:description" content="${esc(copy.meta.description)}">
<meta property="og:url" content="${esc(url)}">
<meta property="og:image" content="${esc(image)}">
<meta property="og:image:width" content="1200">
<meta property="og:image:height" content="630">
<meta property="og:locale" content="${lang === "ru" ? "ru_RU" : "en_US"}">
<meta name="twitter:card" content="summary_large_image">
<meta name="twitter:title" content="${esc(copy.meta.title)}">
<meta name="twitter:description" content="${esc(copy.meta.description)}">
<meta name="twitter:image" content="${esc(image)}">
${jsonLd(app)}
${jsonLd(faq)}
</head>
<body>
<a class="skip" href="#main">${esc(copy.nav.skip)}</a>
<header class="top">
<div class="wrap top-in">
<a class="brand" href="${home}"><img src="/assets/icon.png" alt="" aria-hidden="true" width="256" height="256">Plugin Sorter</a>
<nav aria-label="${esc(copy.nav.label)}">
<a href="#picker">${esc(copy.nav.picker)}</a>
<a href="#features">${esc(copy.nav.features)}</a>
<a href="#compare">${esc(copy.nav.compare)}</a>
<a href="#install">${esc(copy.nav.install)}</a>
<a href="#faq">${esc(copy.nav.faq)}</a>
</nav>
<div class="top-end">
<div class="lang" role="group" aria-label="${esc(copy.nav.language)}">${langSwitch("en", "/", "EN")}${langSwitch("ru", "/ru/", "RU")}</div>
${dl(copy.nav.download, "btn btn-sm", "")}
</div>
</div>
</header>
<main id="main">
<section id="hero">
<div class="wrap">
<p class="badge"><span class="led"></span>${esc(copy.hero.badge)}</p>
<h1>${esc(copy.hero.title)} <span class="grad" data-gradient>${nb(copy.hero.titleAccent)}</span>${copy.hero.titleEnd ? ` ${esc(copy.hero.titleEnd)}` : ""}</h1>
<p class="hero-sub">${nb(copy.hero.subtitle)}</p>
<p class="hero-cta">${dl()}</p>
<p class="hero-note">${esc(copy.hero.note)}</p>
<div class="hero-media">
<img src="/assets/app.webp" srcset="/assets/app-800.webp 800w, /assets/app.webp 1600w" sizes="(max-width: 720px) 150vw, (max-width: 1160px) calc(100vw - 32px), 1080px" alt="${esc(copy.hero.imageAlt)}" width="${APP.width}" height="${APP.height}" fetchpriority="high">
</div>
</div>
<div class="strip" aria-hidden="true"><div class="strip-in">${stripImg}${stripImg}</div></div>
</section>
<section id="picker">
<div class="wrap">
<div class="head center rise">
<p class="eyebrow"><span class="led"></span>${esc(copy.picker.eyebrow)}</p>
<h2>${nb(copy.picker.title)}</h2>
<p class="lead">${nb(copy.picker.lead)}</p>
</div>
<div class="pair">
<figure class="before rise"><figcaption><span class="led"></span>${esc(copy.picker.beforeLabel)}</figcaption><div class="shot">${before}</div></figure>
<figure class="after rise"><figcaption><span class="led"></span>${esc(copy.picker.afterLabel)}</figcaption><div class="shot"><img src="/assets/picker-after.webp" alt="${esc(copy.picker.afterAlt)}" width="${PICKER.width}" height="${PICKER.height}" loading="lazy" decoding="async"></div></figure>
</div>
<ul class="points">${copy.picker.points.map((p) => `<li>${esc(p)}</li>`).join("")}</ul>
</div>
</section>
<section id="features">
<div class="wrap">
<div class="head rise">
<p class="eyebrow"><span class="led"></span>${esc(copy.features.eyebrow)}</p>
<h2>${esc(copy.features.title)}</h2>
<p class="lead">${esc(copy.features.lead)}</p>
</div>
<div class="bento">
<article class="card card-sort rise">
<div class="tree" role="img" aria-label="${esc(copy.features.sortAlt)}">
<div class="files"><span class="root">VST3/</span><span>FabFilter Pro-Q 4.vst3</span><span>OTT.vst3</span><span>Serum2.vst3</span><span>soothe2.vst3</span><span>ValhallaSupermassive.vst3</span></div>
<div class="tree-arrow">${ICONS.arrow}</div>
<div class="files"><span class="root">VST3/</span><span class="dir">FabFilter/</span><span class="in">FabFilter Pro-Q 4.vst3</span><span class="dir">Xfer Records/</span><span class="in">OTT.vst3</span><span class="in">Serum2.vst3</span><span class="dir">oeksound/</span><span class="in">soothe2.vst3</span></div>
</div>
${text(item.sort)}
</article>
<article class="card card-check rise">
<ul class="lamps" role="img" aria-label="${esc(copy.features.checkAlt)}">
<li><span class="lamp" style="--c:var(--mint)"></span><span><b>FabFilter Pro-Q 4</b><small>FabFilter</small></span></li>
<li><span class="lamp" style="--c:var(--amber)"></span><span><b>kHs Chorus</b><small>Kilohearts</small></span></li>
<li><span class="lamp" style="--c:var(--danger)"></span><span><b>OldReverb</b><small>Legacy Audio</small></span></li>
</ul>
${text(item.check)}
</article>
${small("uninstall")}
${small("duplicates")}
${small("off")}
${small("licenses")}
<article class="card card-cards rise">
<div>
${text(item.cards)}
<p class="skins-label">${esc(copy.features.skinsLabel)}</p>
<ul class="skins">${copy.features.skins.map((name, i) => `<li class="skin" style="--a:${SKINS[i]}"><svg viewBox="0 0 60 60" aria-hidden="true">${arc(0.72, "arc")}<circle cx="30" cy="30" r="14" fill="#2c2c33"/></svg>${esc(name)}</li>`).join("")}</ul>
</div>
<div class="cards-shot"><img src="/assets/app-cards.webp" srcset="/assets/app-cards-800.webp 800w, /assets/app-cards.webp 1600w" sizes="(max-width: 1040px) calc(100vw - 80px), 680px" alt="${esc(copy.features.cardsAlt)}" width="${APP.width}" height="${APP.height}" loading="lazy" decoding="async"></div>
</article>
</div>
</div>
</section>
<section id="compare">
<div class="wrap">
<div class="head rise">
<p class="eyebrow"><span class="led"></span>${esc(copy.compare.eyebrow)}</p>
<h2>${nb(copy.compare.title)}</h2>
<p class="lead">${nb(copy.compare.lead)}</p>
</div>
<div class="table-wrap rise">
<table role="table"><thead><tr role="row">${heads}</tr></thead><tbody>
${rows}
</tbody></table>
</div>
</div>
</section>
<section id="install">
<div class="wrap">
<div class="head center rise">
<p class="eyebrow"><span class="led"></span>${esc(copy.install.eyebrow)}</p>
<h2>${esc(copy.install.title)}</h2>
</div>
<ol class="steps">
${steps}
</ol>
<p class="why">${esc(copy.install.why)}</p>
<div class="cta-row">${dl()}<p class="small-note">${esc(copy.cta.note)}</p></div>
</div>
</section>
<section id="faq">
<div class="wrap">
<div class="head center rise"><h2>${esc(copy.faqTitle)}</h2></div>
<div class="faq">
${copy.faq.map((f) => `<details><summary>${esc(f.q)}</summary><p>${esc(f.a)}</p></details>`).join("\n")}
</div>
</div>
</section>
<section id="support">
<div class="wrap">
<div class="support rise">
<p class="eyebrow"><span class="led"></span>${esc(copy.support.eyebrow)}</p>
<h2>${esc(copy.support.title)}</h2>
<p class="lead">${esc(copy.support.text)}</p>
<div class="support-links">${koFiLink}<a class="btn-ghost" href="${esc(config.repoUrl)}">${ICONS.star}${esc(copy.support.star)}</a><a class="btn-ghost" href="${esc(config.repoUrl)}/issues">${ICONS.bug}${esc(copy.support.issues)}</a></div>
</div>
</div>
</section>
<section id="download">
<div class="wrap">
<div class="finale rise">
<img src="/assets/icon.png" alt="" aria-hidden="true" width="256" height="256" loading="lazy" decoding="async">
<h2>${esc(copy.cta.title)}</h2>
<div class="cta-row">${dl()}<p class="small-note">${esc(copy.cta.note)}</p></div>
</div>
</div>
</section>
</main>
<footer>
<div class="wrap">
<div class="foot-links">
<a class="brand" href="${home}">Plugin Sorter</a>
<a href="${esc(config.repoUrl)}">GitHub</a>
<a href="${esc(config.repoUrl)}/blob/main/LICENSE">${esc(copy.footer.license)}</a>
<a href="/" hreflang="en" lang="en">English</a>
<a href="/ru/" hreflang="ru" lang="ru">Русский</a>
</div>
<p class="legal">${esc(copy.footer.independent)} ${esc(copy.footer.owners)}</p>
</div>
</footer>
${dialog}
</body>
</html>
`;
}
