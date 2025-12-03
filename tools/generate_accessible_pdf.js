// Simple helper that uses Puppeteer to render the site's glossary page to PDF.
// This is a best-effort, print-style PDF and may not produce fully tagged/accessibility-compliant PDFs.
// Usage (from WebSite/V7):
//   node tools/generate_accessible_pdf.js ./glossary.html ./assets/glossary-print.pdf

const fs = require('fs');
const path = require('path');
const puppeteer = require('puppeteer');

async function usage() {
  console.log('Usage: node tools/generate_accessible_pdf.js <input-html> <output-pdf>');
  process.exit(1);
}

async function run(inPath, outPath) {
  const url = 'file://' + path.resolve(inPath);
  const browser = await puppeteer.launch({args:['--no-sandbox','--disable-setuid-sandbox']});
  const page = await browser.newPage();
  await page.goto(url, {waitUntil: 'networkidle2'});

  // Print to PDF — enable background and set reasonable margins for print
  await page.pdf({path: outPath, format: 'A4', printBackground: true, margin: {top:'12mm', bottom:'12mm', left:'12mm', right:'12mm'}});
  await browser.close();
  console.log('Wrote', outPath, '- note: for fully tagged PDFs use an advanced PDF authoring tool (Adobe Acrobat, or a LaTeX/PDF/assistive toolchain)');
}

const args = process.argv.slice(2);
if (args.length !== 2) usage();
run(args[0], args[1]).catch(e => { console.error('Error generating PDF:', e); process.exit(2); });
