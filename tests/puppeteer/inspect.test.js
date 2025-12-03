const puppeteer = require('puppeteer');

(async () => {
  const url = 'http://localhost:8000/glossary.html';
  const browser = await puppeteer.launch({args:['--no-sandbox','--disable-setuid-sandbox']});
  const page = await browser.newPage();
  await page.goto(url, { waitUntil: 'networkidle2' });

  const titlesBefore = await page.evaluate(() =>
    Array.from(document.querySelectorAll('.entry > h3')).map(h => h.textContent.trim())
  );
  console.log('Titles before search:', titlesBefore.length);
  console.log(titlesBefore.slice(0, 40));

  await page.waitForSelector('#glossary-search');
  await page.type('#glossary-search', 'air');
  // wait until at least one visible entry contains 'air' or timeout
  await page.waitForFunction(() => {
    const items = Array.from(document.querySelectorAll('.entry'));
    return items.some(e => getComputedStyle(e).display !== 'none' && /air/i.test(e.textContent));
  }, { timeout: 4000 });

  const visibleAfter = await page.evaluate(() =>
    Array.from(document.querySelectorAll('.entry'))
      .filter(e => getComputedStyle(e).display !== 'none')
      .map(e => e.querySelector('h3') ? e.querySelector('h3').textContent.trim() : e.textContent.trim())
  );
  console.log('Visible after search (count):', visibleAfter.length);
  console.log(visibleAfter.slice(0, 20));

  await browser.close();
  process.exit(0);
})();
