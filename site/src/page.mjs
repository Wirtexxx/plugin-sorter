const ESC = { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" };
export const esc = (s) => String(s).replace(/[&<>"']/g, (c) => ESC[c]);

const jsonLd = (obj) =>
  `<script type="application/ld+json">${JSON.stringify(obj).replace(/</g, "\\u003c")}</script>`;

export function page(copy, ctx) {
  const { lang, config, hasBefore, otherUrl, url } = ctx;
  const origin = `https://${config.domain}`;
  const enUrl = lang === "en" ? url : otherUrl;
  const ruUrl = lang === "ru" ? url : otherUrl;
  const image = `${origin}/assets/og.png`;
  const dl = (cls = "btn") =>
    `<a class="${cls}" data-download href="${esc(config.downloadUrl)}">${esc(copy.hero.download)}</a>`;

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
    ? `<img src="/assets/picker-before.webp" alt="${esc(copy.picker.beforeAlt)}" loading="lazy">`
    : `<div class="placeholder" role="img" aria-label="${esc(copy.picker.beforeAlt)}">Placeholder: picker-before.webp is missing (local build only)</div>`;

  const rows = copy.compare.rows
    .map((r) => `<tr><th scope="row">${esc(r[0])}</th>${r.slice(1).map((c) => `<td>${esc(c)}</td>`).join("")}</tr>`)
    .join("");
  const heads = copy.compare.headers.map((h) => `<th scope="col">${esc(h)}</th>`).join("");

  const koFi = config.koFiUrl;
  const dialog = koFi
    ? `<dialog id="donate" aria-labelledby="donate-title">
<h2 id="donate-title">${esc(copy.dialog.title)}</h2>
<p>${esc(copy.dialog.text)}</p>
<p><a class="btn" href="${esc(koFi)}" rel="noopener">${esc(copy.dialog.kofi)}</a></p>
<p class="muted">${esc(copy.dialog.macNote)}</p>
<button type="button" data-close>${esc(copy.dialog.close)}</button>
</dialog>`
    : "";
  const koFiLink = koFi ? `<a class="btn" href="${esc(koFi)}" rel="noopener">${esc(copy.support.kofi)}</a>` : "";

  return `<!doctype html>
<html lang="${lang}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${esc(copy.meta.title)}</title>
<meta name="description" content="${esc(copy.meta.description)}">
<link rel="canonical" href="${esc(url)}">
<link rel="alternate" hreflang="en" href="${esc(enUrl)}">
<link rel="alternate" hreflang="ru" href="${esc(ruUrl)}">
<link rel="alternate" hreflang="x-default" href="${esc(enUrl)}">
<meta property="og:type" content="website">
<meta property="og:title" content="${esc(copy.meta.title)}">
<meta property="og:description" content="${esc(copy.meta.description)}">
<meta property="og:url" content="${esc(url)}">
<meta property="og:image" content="${esc(image)}">
<meta property="og:locale" content="${lang === "ru" ? "ru_RU" : "en_US"}">
<meta name="twitter:card" content="summary_large_image">
<meta name="twitter:title" content="${esc(copy.meta.title)}">
<meta name="twitter:description" content="${esc(copy.meta.description)}">
<meta name="twitter:image" content="${esc(image)}">
${jsonLd(app)}
${jsonLd(faq)}
</head>
<body>
<main>
<section id="hero">
<h1>${esc(copy.hero.title)} <span class="accent">${esc(copy.hero.titleAccent)}</span></h1>
<p>${esc(copy.hero.subtitle)}</p>
<p>${dl()}</p>
<p class="muted">${esc(copy.hero.note)}</p>
</section>
<section id="picker">
<h2>${esc(copy.picker.title)}</h2>
<figure><figcaption>${esc(copy.picker.beforeLabel)}</figcaption>${before}</figure>
<figure><figcaption>${esc(copy.picker.afterLabel)}</figcaption><img src="/assets/picker-after.webp" alt="${esc(copy.picker.afterAlt)}" loading="lazy"></figure>
</section>
<section id="features">
${copy.features.map((f) => `<article><h2>${esc(f.title)}</h2><p>${esc(f.text)}</p></article>`).join("\n")}
</section>
<section id="compare">
<h2>${esc(copy.compare.title)}</h2>
<table><thead><tr>${heads}</tr></thead><tbody>${rows}</tbody></table>
</section>
<section id="install">
<h2>${esc(copy.install.title)}</h2>
<ol>${copy.install.steps.map((s) => `<li>${esc(s)}</li>`).join("")}</ol>
<p>${esc(copy.install.why)}</p>
<p>${dl()}</p>
</section>
<section id="faq">
${copy.faq.map((f) => `<details><summary>${esc(f.q)}</summary><p>${esc(f.a)}</p></details>`).join("\n")}
</section>
<section id="support">
<h2>${esc(copy.support.title)}</h2>
<p>${koFiLink} <a href="${esc(config.repoUrl)}">${esc(copy.support.star)}</a> <a href="${esc(config.repoUrl)}/issues">${esc(copy.support.issues)}</a></p>
</section>
</main>
<footer>
<p><a href="${esc(config.repoUrl)}">GitHub</a> · MIT · <a href="${esc(enUrl)}" hreflang="en">English</a> · <a href="${esc(ruUrl)}" hreflang="ru">Русский</a></p>
<p>${esc(copy.footer.independent)} ${esc(copy.footer.owners)}</p>
</footer>
${dialog}
</body>
</html>
`;
}
