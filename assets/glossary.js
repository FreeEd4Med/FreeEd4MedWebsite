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
