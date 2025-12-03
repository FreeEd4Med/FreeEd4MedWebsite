const puppeteer = require('puppeteer');

(async () => {
  const url = 'http://localhost:8000/glossary.html';
  const browser = await puppeteer.launch({args:['--no-sandbox','--disable-setuid-sandbox']});
  const page = await browser.newPage();
  page.setDefaultTimeout(20000);

  try {
    await page.goto(url, { waitUntil: 'networkidle2' });

    // check page loaded
    const title = await page.title();
    console.log('Page title:', title);

    // ensure the search input exists
    await page.waitForSelector('#glossary-search');

    // default count of visible entries
    const initialVisible = await page.evaluate(() => {
      return Array.from(document.querySelectorAll('.entry')).filter(e => getComputedStyle(e).display !== 'none').length;
    });
    console.log('Initial visible entries:', initialVisible);

    // type a search term we know exists (case-insensitive) and test
    await page.type('#glossary-search', 'air');

    // Wait until at least one visible entry contains the search term (robust across Puppeteer versions)
    await page.waitForFunction(() => {
      const items = Array.from(document.querySelectorAll('.entry'));
      return items.some(e => getComputedStyle(e).display !== 'none' && /air/i.test(e.textContent));
    }, { timeout: 4000 });

    const visibleAfterSearch = await page.evaluate(() => {
      return Array.from(document.querySelectorAll('.entry'))
        .filter(e => getComputedStyle(e).display !== 'none')
        .map(e => e.textContent.trim()).slice(0,10);
    });

    console.log('Visible entries after search:', visibleAfterSearch.length);

    if (visibleAfterSearch.length === 0) throw new Error('Search returned no visible entries — expected at least one (e.g., Air)');
    const found = visibleAfterSearch.some(s => /air/i.test(s));
    if (!found) throw new Error('Search did not match expected text (Air) — filtering may be broken');

    console.log('\n✅ Puppeteer check passed: glossary search filters entries as expected.');
    await browser.close();
    process.exit(0);
  } catch (err) {
    console.error('\n❌ Puppeteer check failed:', err.message || err);
    await browser.close();
    process.exit(2);
  }
})();
