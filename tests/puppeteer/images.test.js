const puppeteer = require('puppeteer');

(async () => {
  const url = 'http://localhost:8000/glossary.html';
  const browser = await puppeteer.launch({args:['--no-sandbox','--disable-setuid-sandbox']});
  const page = await browser.newPage();
  await page.goto(url, { waitUntil: 'networkidle2' });

  const counts = await page.evaluate(() => ({
    entries: document.querySelectorAll('.entry').length,
    imageTiles: document.querySelectorAll('.entry .term-art').length,
    sample: Array.from(document.querySelectorAll('.entry')).slice(0,12).map(e => ({ title: (e.querySelector('h3') ? e.querySelector('h3').textContent.trim() : ''), hasImage: !!e.querySelector('.term-art') }))
  }));
  console.log('Entries:', counts.entries);
  console.log('Image tiles:', counts.imageTiles);
  console.log('Sample entries w/ image availability:', counts.sample);
  await browser.close();
  process.exit(0);
})();