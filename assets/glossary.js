document.addEventListener('DOMContentLoaded', function () {
  const container = document.querySelector('.main-content');
  if (!container) return;

  // Create top controls: search input and clear
  const controls = document.createElement('div');
  controls.className = 'glossary-controls';
  controls.innerHTML = `
    <label for="glossary-search" class="sr-only">Search glossary</label>
    <input id="glossary-search" type="search" placeholder="Search glossary — type to filter terms" aria-label="Search glossary" />
    <button id="glossary-clear" aria-label="Clear search">Clear</button>
    <div id="glossary-alpha" aria-hidden="false" class="glossary-alpha"></div>
  `;
  container.insertBefore(controls, container.firstChild);

  // Robustly convert any <dt>/<dd> pairs across the page into individual
  // article.entry elements so every glossary term is turned into its own
  // searchable item. This function pairs dt elements with their nearest dd
  // sibling (forward preferred) and preserves id attributes for anchors.
  (function flattenDlPairs() {
    const dtNodes = Array.from(container.querySelectorAll('dt'));
    dtNodes.forEach(dt => {
      // find the dd sibling: prefer the nextElementSibling, else search forward,
      // as a fallback search backward for a previous dd.
      let dd = dt.nextElementSibling;
      while (dd && dd.tagName && dd.tagName.toLowerCase() !== 'dd') {
        dd = dd.nextElementSibling;
      }
      if (!dd) {
        // fallback: look backward
        dd = dt.previousElementSibling;
        while (dd && dd.tagName && dd.tagName.toLowerCase() !== 'dd') {
          dd = dd.previousElementSibling;
        }
      }

      const article = document.createElement('article');
      article.className = 'entry';

      const h3 = document.createElement('h3');
      if (dt.id) h3.id = dt.id;
      h3.textContent = dt.textContent.trim();

      const p = document.createElement('p');
      p.innerHTML = dd ? dd.innerHTML.trim() : '';

      article.appendChild(h3);
      article.appendChild(p);

      // Insert the article right after the dt node's parent <dl> if present,
      // otherwise insert after dt itself.
      const parentDl = dt.closest('dl');
      if (parentDl && parentDl.parentNode) parentDl.parentNode.insertBefore(article, parentDl);
      else dt.parentNode.insertBefore(article, dt.nextSibling);

      // Remove dt and paired dd if they exist
      if (dd && dd.parentNode) dd.parentNode.removeChild(dd);
      if (dt && dt.parentNode) dt.parentNode.removeChild(dt);
    });

    // Remove any now-empty <dl> containers
    Array.from(container.querySelectorAll('dl')).forEach(dl => { if (dl.children.length === 0) dl.remove(); });
  })();


  // Remove group header entries (section titles) so the page is a unified list.
  // We target entries whose H3 looks like a section label rather than a single term.
  const headerPattern = /terms|reference|quick reference|common mixing|parameter|reverb|saturation|noise gate|listening safety/i;
  Array.from(container.querySelectorAll('.entry')).forEach(e => {
    const h = e.querySelector('h3');
    if (h && headerPattern.test(h.textContent)) {
      // remove this node (section header)
      e.remove();
    }
  });

  // Build index from entries (re-read entries after transformations / header removal)
  const entryEls = Array.from(container.querySelectorAll('.entry'));
  // Build index from entries
  const alphaMap = {};
  const entries = []; // structured index: {el, title}
  entryEls.forEach(el => {
    let titleEl = el.querySelector('h3');
    let title = titleEl ? titleEl.textContent.trim() : (el.querySelector('dt') ? el.querySelector('dt').textContent.trim() : '');
    const first = (title[0] || '#').toUpperCase();
    const letter = /[A-Z]/.test(first) ? first : '#';
    alphaMap[letter] = alphaMap[letter] || [];
    const item = {el, title};
    alphaMap[letter].push(item);
    entries.push(item);
  });

  // Add optional image tiles for glossary terms when an asset exists.
  // We create a filename from the term (slug) and attach an <img> if available.
  function termToSlug(s){
    return s.toLowerCase().replace(/[^a-z0-9]+/g,'-').replace(/(^-|-$)/g,'');
  }
  entries.forEach(({el, title})=>{
    if (!title) return;
    // create a container for the body if not present
    let body = el.querySelector('.entry-body');
    if (!body) {
      body = document.createElement('div');
      body.className = 'entry-body';
      // move all children except h3 into entry-body
      Array.from(el.children).forEach(ch => { if (ch.tagName.toLowerCase() !== 'h3') body.appendChild(ch); });
      el.appendChild(body);
    }

    // build multiple candidate slugs to increase chance of matching available assets
    const titleCore = title.split(':')[0].split('(')[0].split('—')[0].split('/')[0].trim();
    const slugCandidates = [termToSlug(title), termToSlug(titleCore)];
    // also add last word e.g. 'Brickwall limiter' -> 'limiter'
    const last = titleCore.split(' ').slice(-1)[0];
    if (last && last.length > 2) slugCandidates.push(termToSlug(last));
    // prefer shorter slugs first (e.g., 'compressor')
    slugCandidates.sort((a,b)=>a.length - b.length);
    // try to find a matching image by testing candidate files
    let imgSrc = null;
    for (const s of slugCandidates){
      const candidate = 'assets/glossary_images/' + s + '.svg';
      // we'll use <img> onerror to remove missing images; but attempt shorter names first
      imgSrc = candidate; break; // set candidate, onerror will clean up if missing
    }
    const imgWrap = document.createElement('div');
    imgWrap.className = 'term-art';
    const img = document.createElement('img');
    img.src = imgSrc;
    // hide the tile if the asset isn't present (onerror)
    img.onerror = function(){ imgWrap.remove(); };
    img.alt = title + ' — image';
    imgWrap.appendChild(img);
    // insert at start of the entry
    el.insertBefore(imgWrap, el.firstChild);
  });

  const alphaDiv = document.getElementById('glossary-alpha');
  // Create letter sections and collapsible containers
  Object.keys(alphaMap).sort().forEach(letter => {
    const section = document.createElement('section');
    section.className = 'glossary-letter-section';
    section.id = 'letter-' + letter;

    const header = document.createElement('button');
    header.className = 'glossary-letter-toggle';
    header.setAttribute('aria-expanded', 'true');
    header.setAttribute('aria-controls', 'content-' + letter);
    header.innerHTML = `<strong>${letter}</strong> <span class="count">(${alphaMap[letter].length})</span>`;

    const content = document.createElement('div');
    content.className = 'glossary-letter-content';
    content.id = 'content-' + letter;
    content.setAttribute('role', 'region');
    content.setAttribute('aria-labelledby', header.id || '');

    // Append entries into content
    alphaMap[letter].forEach(item => content.appendChild(item.el));

    header.addEventListener('click', function () {
      const expanded = header.getAttribute('aria-expanded') === 'true';
      header.setAttribute('aria-expanded', String(!expanded));
      if (expanded) content.style.display = 'none'; else content.style.display = '';
    });

    // Add to page
    alphaDiv.appendChild(header);
    alphaDiv.appendChild(section);
    section.appendChild(content);
  });

  // wire search
  const input = document.getElementById('glossary-search');
  const clear = document.getElementById('glossary-clear');
  function doFilter() {
    const q = input.value.trim().toLowerCase();
    let anyVisible = false;
    entries.forEach(({el, title}) => {
      const text = (title + ' ' + el.textContent).toLowerCase();
      const match = !q || text.indexOf(q) !== -1;
      el.style.display = match ? '' : 'none';
      el.setAttribute('aria-hidden', match ? 'false' : 'true');
      if (match) anyVisible = true;
    });
    // show/hide entire letter sections if none visible
    Object.keys(alphaMap).forEach(letter => {
      const content = document.getElementById('content-' + letter);
      const visibleChild = Array.from(content.children).some(c => c.style.display !== 'none');
      const header = content.previousSibling;
      if (!visibleChild) {
        content.style.display = 'none';
        header.setAttribute('aria-expanded', 'false');
      } else {
        content.style.display = '';
        header.setAttribute('aria-expanded', 'true');
      }
    });
  }
  input.addEventListener('input', doFilter);
  clear.addEventListener('click', function (e){ e.preventDefault(); input.value=''; doFilter(); input.focus(); });

  // Add an alphabetic quick jump area (letters clickable)
  const letters = Object.keys(alphaMap).sort();
  const nav = document.createElement('nav');
  nav.className = 'glossary-alpha-nav';
  letters.forEach(l => {
    const a = document.createElement('a');
    a.href = '#letter-' + l;
    a.textContent = l;
    a.addEventListener('click', function () { setTimeout(()=>document.getElementById('letter-'+l).scrollIntoView({behavior:'smooth'}), 30); });
    nav.appendChild(a);
  });
  container.insertBefore(nav, container.firstChild);
});
