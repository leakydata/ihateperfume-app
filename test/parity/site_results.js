// Ground truth for test/decoder_parity_test.dart: run each case through the LIVE website decoder.
//   NODE_PATH=... node test/parity/site_results.js > test/parity/site_results.json
//   (CHROME=/usr/bin/google-chrome uses the system Chrome if Playwright's own browser isn't downloaded)
const { chromium } = require('playwright');
const cases = require('./cases.json');
(async () => {
  const b = await chromium.launch(process.env.CHROME ? { executablePath: process.env.CHROME } : {});
  const p = await b.newPage({ userAgent: 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 Chrome/140 Safari/537.36' });
  const out = [];
  for (const c of cases) {
    await p.goto('https://ihateperfume.com/label-decoder/?parity=' + Date.now() + '#i=' + encodeURIComponent(c), { waitUntil: 'networkidle' });
    await p.waitForSelector('.ihp-flags__verdict', { timeout: 30000 });
    out.push(await p.evaluate(() => {
      const r = document.getElementById('ihp-decoder-result');
      const sections = {};
      r.querySelectorAll(':scope > h3.ihp-decoder__heading').forEach(h => {
        const ul = h.nextElementSibling && h.nextElementSibling.tagName === 'UL' ? h.nextElementSibling
          : h.nextElementSibling && h.nextElementSibling.nextElementSibling;
        sections[h.textContent] = ul ? [...ul.querySelectorAll(':scope > li > strong')].map(s => s.textContent) : [];
      });
      const v = r.querySelector('.ihp-flags__verdict');
      return {
        verdict: v.classList.contains('is-red') ? 'red' : v.classList.contains('is-amber') ? 'amber' : 'clear',
        verdictText: v.textContent,
        fragrance: sections['Fragrance declared'] || [],
        allergens: sections['Named fragrance allergens'] || [],
        plantOils: sections['Scented plant oils and extracts'] || [],
        flags: [...r.querySelectorAll('.ihp-flags__item')].map(li => ({
          item: li.querySelector('.ihp-flags__name').textContent,
          guess: (li.querySelector('.ihp-flags__guess') || {}).textContent || null,
          chips: [...li.querySelectorAll('.ihp-chip')].map(c => c.textContent),
        })),
      };
    }));
  }
  console.log(JSON.stringify(out, null, 1));
  await b.close();
})();
