// ============================================================
// DELUSION — visual editor engine
// Powers officer-only "Edit Mode": every [data-edit] text node
// and [data-box] container becomes stylable (size/font/color),
// and repeating sections (site_sections) become add/remove-able.
// ============================================================

let editMode = false;
const contentCache = {};   // key -> site_content row
const sectionsCache = {};  // key -> site_sections row
const saveTimers = {};

const FONT_OPTIONS = [
  { label: 'Newsreader (serif)', value: "'Newsreader',serif" },
  { label: 'Plex Mono',          value: "'IBM Plex Mono',monospace" },
  { label: 'Manrope (sans)',     value: "'Manrope',sans-serif" },
];

// ---------- LOAD ----------
async function loadEditableContent() {
  const { data } = await sb.from('site_content').select('*');
  (data || []).forEach(r => contentCache[r.key] = r);
}
async function loadSections() {
  const { data } = await sb.from('site_sections').select('*');
  (data || []).forEach(r => sectionsCache[r.key] = r);
}

// ---------- APPLY SAVED OVERRIDES TO STATIC [data-edit] ELEMENTS ----------
function applyContentOverrides() {
  document.querySelectorAll('[data-edit]').forEach(el => {
    const key = el.getAttribute('data-edit');
    const row = contentCache[key];
    if (!row) return;
    if (row.text != null && !el.hasAttribute('data-no-text')) el.textContent = row.text;
    if (row.font_size) el.style.fontSize = row.font_size;
    if (row.font_family) el.style.fontFamily = row.font_family;
    if (row.color) el.style.color = row.color;
    if (row.bg_color) el.style.backgroundColor = row.bg_color;
  });

  // Boxes (buttons, the colophon frame, the staffbox frame, etc) store their
  // own style under their data-box key. They don't hold text, just look/feel.
  document.querySelectorAll('[data-box]').forEach(el => {
    const key = el.getAttribute('data-box');
    const row = contentCache[key];
    if (!row) return;
    if (row.font_size) el.style.fontSize = row.font_size;
    if (row.font_family) el.style.fontFamily = row.font_family;
    if (row.color) el.style.color = row.color;
    if (row.bg_color) el.style.backgroundColor = row.bg_color;
    if (row.box_height && el.hasAttribute('data-resize-h')) el.style.minHeight = row.box_height;
    if (row.crest_offset_x) el.style.setProperty('--cx', row.crest_offset_x);
    if (row.crest_offset_y) el.style.setProperty('--cy', row.crest_offset_y);
    if (row.hidden) el.style.display = 'none';
  });

  // Editable placeholder/example text on form fields (apply.html)
  document.querySelectorAll('[data-edit-placeholder]').forEach(el => {
    const key = el.getAttribute('data-edit-placeholder');
    const row = contentCache[key];
    if (row && row.text != null) el.placeholder = row.text;
  });
}

// ---------- SAVE ----------
function debounceSaveText(key, el) {
  clearTimeout(saveTimers[key]);
  saveTimers[key] = setTimeout(() => saveContent(key, { text: el.textContent }), 500);
}
async function saveContent(key, patch) {
  const merged = { ...(contentCache[key] || {}), key, ...patch, updated_at: new Date().toISOString() };
  contentCache[key] = merged;
  const { error } = await sb.from('site_content').upsert(merged);
  if (error) toast('Save failed: ' + error.message, 'error');
}
async function saveSection(key, patch) {
  const merged = { ...(sectionsCache[key] || {}), key, ...patch, updated_at: new Date().toISOString() };
  sectionsCache[key] = merged;
  const { error } = await sb.from('site_sections').upsert(merged);
  if (error) toast('Save failed: ' + error.message, 'error');
}

// ---------- EDIT MODE TOGGLE ----------
function setEditMode(on) {
  editMode = on;
  document.body.classList.toggle('edit-mode', on);

  document.querySelectorAll('[data-edit]:not([data-box])').forEach(el => {
    el.contentEditable = on;
    el.oninput = null; el.onblur = null;
    if (on) {
      el.oninput = () => debounceSaveText(el.getAttribute('data-edit'), el);
      el.onblur  = () => saveContent(el.getAttribute('data-edit'), { text: el.textContent });
      el.onfocus = () => openStylePanel(el.getAttribute('data-edit'), el, { box: false });
    }
  });

  document.querySelectorAll('[data-box]').forEach(el => {
    const existingBtn = el.querySelector(':scope > .edit-box-btn');
    if (existingBtn) existingBtn.remove();
    const existingHandle = el.querySelector(':scope > .resize-handle');
    if (existingHandle) existingHandle.remove();
    // stop links from navigating away while editing (still lets contenteditable children work)
    el.onclick = on ? (e) => { if (!e.target.hasAttribute('contenteditable')) e.preventDefault(); } : null;

    const key = el.getAttribute('data-box');
    const isHidden = !!contentCache[key]?.hidden;
    if (isHidden) {
      el.classList.toggle('box-hidden-preview', on);
      el.style.display = on ? '' : 'none';
    }

    if (on) {
      if (el.tagName !== 'IMG') {
        const btn = document.createElement('button');
        btn.className = 'edit-box-btn';
        btn.type = 'button';
        btn.textContent = '\u270E';
        btn.title = 'Style this box';
        btn.onclick = (e) => { e.preventDefault(); e.stopPropagation(); openStylePanel(el.getAttribute('data-box'), btn, { box: true }); };
        el.appendChild(btn);
      }

      if (el.hasAttribute('data-resize-h')) {
        const handle = document.createElement('div');
        handle.className = 'resize-handle';
        handle.title = 'Drag up or down to resize';
        handle.innerHTML = '<span></span><span></span><span></span>';
        el.appendChild(handle);
        wireResizeHandle(handle, el);
      }
      if (el.hasAttribute('data-draggable')) {
        el.style.pointerEvents = 'auto';
        el.style.cursor = 'move';
        wireDraggableImage(el);
      }
    } else if (el.hasAttribute('data-draggable')) {
      el.style.pointerEvents = 'none';
      el.style.cursor = '';
    }
  });

  renderStats();
  renderChronicle();
  renderRecruitment();
  renderOfficersDisplay();
  wirePlaceholderEditables(on);
}

// ---------- EDITABLE PLACEHOLDER TEXT (input/textarea hint text) ----------
function wirePlaceholderEditables(on) {
  document.querySelectorAll('[data-edit-placeholder]').forEach(el => {
    const key = el.getAttribute('data-edit-placeholder');
    const existing = el.parentElement.querySelector(':scope > .edit-ph-btn');
    if (existing) existing.remove();
    if (on) {
      const btn = document.createElement('button');
      btn.type = 'button'; btn.className = 'edit-ph-btn'; btn.textContent = '✎ hint text';
      btn.onclick = () => {
        const val = window.prompt('Example/placeholder text shown before someone types:', el.placeholder || '');
        if (val !== null) { el.placeholder = val; saveContent(key, { text: val }); }
      };
      el.insertAdjacentElement('afterend', btn);
    }
  });
}

// ---------- DRAG-TO-REPOSITION (currently used by the header crest image) ----------
function wireDraggableImage(el) {
  if (el._dragWired) return;
  el._dragWired = true;
  const key = el.getAttribute('data-box');
  let startX = 0, startY = 0, baseX = 0, baseY = 0;

  function readVar(name) {
    const v = el.style.getPropertyValue(name);
    return v ? parseFloat(v) : 0;
  }
  function start(x, y) { startX = x; startY = y; baseX = readVar('--cx'); baseY = readVar('--cy'); }
  function move(x, y) {
    el.style.setProperty('--cx', (baseX + (x - startX)) + 'px');
    el.style.setProperty('--cy', (baseY + (y - startY)) + 'px');
  }
  function end() {
    saveContent(key, { crest_offset_x: readVar('--cx') + 'px', crest_offset_y: readVar('--cy') + 'px' });
    document.removeEventListener('mousemove', onMouseMove);
    document.removeEventListener('mouseup', onMouseUp);
    document.removeEventListener('touchmove', onTouchMove);
    document.removeEventListener('touchend', onMouseUp);
  }
  function onMouseMove(e) { move(e.clientX, e.clientY); }
  function onMouseUp() { end(); }
  function onTouchMove(e) { if (e.touches[0]) move(e.touches[0].clientX, e.touches[0].clientY); }

  el.addEventListener('mousedown', (e) => {
    e.preventDefault(); e.stopPropagation();
    start(e.clientX, e.clientY);
    document.addEventListener('mousemove', onMouseMove);
    document.addEventListener('mouseup', onMouseUp);
  });
  el.addEventListener('touchstart', (e) => {
    e.stopPropagation();
    if (e.touches[0]) start(e.touches[0].clientX, e.touches[0].clientY);
    document.addEventListener('touchmove', onTouchMove, { passive: true });
    document.addEventListener('touchend', onMouseUp);
  }, { passive: true });
  el.addEventListener('dblclick', (e) => {
    e.preventDefault(); e.stopPropagation();
    el.style.setProperty('--cx', '0px'); el.style.setProperty('--cy', '0px');
    saveContent(key, { crest_offset_x: '0px', crest_offset_y: '0px' });
  });
}

// ---------- DRAG-TO-RESIZE (currently used by the masthead) ----------
function wireResizeHandle(handle, el) {
  const key = el.getAttribute('data-box');
  let startY = 0, startH = 0;

  function start(clientY) {
    startY = clientY;
    startH = el.getBoundingClientRect().height;
    document.body.style.cursor = 'ns-resize';
  }
  function move(clientY) {
    const dy = clientY - startY;
    const newH = Math.max(160, Math.min(760, Math.round(startH + dy)));
    el.style.minHeight = newH + 'px';
  }
  function end() {
    document.body.style.cursor = '';
    const finalH = Math.round(el.getBoundingClientRect().height) + 'px';
    saveContent(key, { box_height: finalH });
    document.removeEventListener('mousemove', onMouseMove);
    document.removeEventListener('mouseup', onMouseUp);
    document.removeEventListener('touchmove', onTouchMove);
    document.removeEventListener('touchend', onMouseUp);
  }
  function onMouseMove(e) { move(e.clientY); }
  function onMouseUp() { end(); }
  function onTouchMove(e) { if (e.touches[0]) move(e.touches[0].clientY); }

  handle.addEventListener('mousedown', (e) => {
    e.preventDefault(); e.stopPropagation();
    start(e.clientY);
    document.addEventListener('mousemove', onMouseMove);
    document.addEventListener('mouseup', onMouseUp);
  });
  handle.addEventListener('touchstart', (e) => {
    e.stopPropagation();
    if (e.touches[0]) start(e.touches[0].clientY);
    document.addEventListener('touchmove', onTouchMove, { passive: true });
    document.addEventListener('touchend', onMouseUp);
  }, { passive: true });
}

// ---------- STYLE PANEL ----------
function removeStylePanel() {
  document.querySelectorAll('.edit-panel').forEach(p => p.remove());
}
function currentFontSizeRem(el) {
  const px = parseFloat(getComputedStyle(el).fontSize);
  return Math.round((px / 16) * 10) / 10;
}
function openStylePanel(key, anchorEl, opts = {}) {
  removeStylePanel();
  const cur = contentCache[key] || {};
  const targetEl = opts.box ? anchorEl.closest('[data-box]') : anchorEl;
  let sizeRem = cur.font_size ? parseFloat(cur.font_size) : currentFontSizeRem(targetEl);

  const panel = document.createElement('div');
  panel.className = 'edit-panel';
  const resizable = opts.box && targetEl.hasAttribute('data-resize-h');
  let heightPx = resizable ? (cur.box_height ? parseInt(cur.box_height) : Math.round(targetEl.getBoundingClientRect().height)) : null;
  panel.innerHTML = `
    <div class="edit-panel-row">
      <label>Size</label>
      <div>
        <button data-act="dec" type="button">−</button>
        <span class="ep-size-val">${sizeRem}rem</span>
        <button data-act="inc" type="button">+</button>
      </div>
    </div>
    <div class="edit-panel-row">
      <label>Font</label>
      <select class="ep-font">
        ${FONT_OPTIONS.map(f => `<option value="${f.value}" ${cur.font_family===f.value?'selected':''}>${f.label}</option>`).join('')}
      </select>
    </div>
    <div class="edit-panel-row">
      <label>Text color</label>
      <input type="color" class="ep-color" value="${cur.color || '#f5efe9'}">
    </div>
    ${opts.box ? `
    <div class="edit-panel-row">
      <label>Box color</label>
      <input type="color" class="ep-bg" value="${cur.bg_color || '#0b0909'}">
    </div>` : ''}
    ${resizable ? `
    <div class="edit-panel-row">
      <label>Height</label>
      <div>
        <button data-act="hdec" type="button">−</button>
        <span class="ep-height-val">${heightPx}px</span>
        <button data-act="hinc" type="button">+</button>
      </div>
    </div>` : ''}
    <div class="edit-panel-row ep-actions">
      <button class="ep-reset" type="button">Reset</button>
      ${opts.box ? `<button class="ep-hide" type="button">${contentCache[key]?.hidden ? 'Show box' : 'Hide box'}</button>` : ''}
      <button class="ep-close" type="button">Done</button>
    </div>
  `;
  document.body.appendChild(panel);

  const r = anchorEl.getBoundingClientRect();
  let top = r.bottom + 8, left = r.left;
  if (left + 230 > window.innerWidth) left = window.innerWidth - 240;
  if (top + 220 > window.innerHeight) top = r.top - 228;
  panel.style.top = Math.max(8, top) + 'px';
  panel.style.left = Math.max(8, left) + 'px';

  const sizeVal = panel.querySelector('.ep-size-val');
  panel.querySelector('[data-act="inc"]').onclick = () => { sizeRem = Math.round((sizeRem+0.1)*10)/10; sizeVal.textContent = sizeRem+'rem'; targetEl.style.fontSize = sizeRem+'rem'; saveContent(key,{font_size:sizeRem+'rem'}); };
  panel.querySelector('[data-act="dec"]').onclick = () => { sizeRem = Math.max(0.5, Math.round((sizeRem-0.1)*10)/10); sizeVal.textContent = sizeRem+'rem'; targetEl.style.fontSize = sizeRem+'rem'; saveContent(key,{font_size:sizeRem+'rem'}); };
  panel.querySelector('.ep-font').onchange = (e) => { targetEl.style.fontFamily = e.target.value; saveContent(key,{font_family:e.target.value}); };
  panel.querySelector('.ep-color').oninput = (e) => { targetEl.style.color = e.target.value; saveContent(key,{color:e.target.value}); };
  const bgInput = panel.querySelector('.ep-bg');
  if (bgInput) bgInput.oninput = (e) => { targetEl.style.backgroundColor = e.target.value; saveContent(key,{bg_color:e.target.value}); };
  if (resizable) {
    const hVal = panel.querySelector('.ep-height-val');
    panel.querySelector('[data-act="hinc"]').onclick = () => { heightPx = Math.min(760, heightPx+20); hVal.textContent = heightPx+'px'; targetEl.style.minHeight = heightPx+'px'; saveContent(key,{box_height:heightPx+'px'}); };
    panel.querySelector('[data-act="hdec"]').onclick = () => { heightPx = Math.max(160, heightPx-20); hVal.textContent = heightPx+'px'; targetEl.style.minHeight = heightPx+'px'; saveContent(key,{box_height:heightPx+'px'}); };
  }
  panel.querySelector('.ep-reset').onclick = () => {
    targetEl.style.fontSize = ''; targetEl.style.fontFamily = ''; targetEl.style.color = ''; targetEl.style.backgroundColor = '';
    if (resizable) targetEl.style.minHeight = '';
    saveContent(key, { font_size: null, font_family: null, color: null, bg_color: null, box_height: resizable ? null : undefined });
    removeStylePanel();
  };
  const hideBtn = panel.querySelector('.ep-hide');
  if (hideBtn) {
    hideBtn.onclick = () => {
      const nowHidden = !contentCache[key]?.hidden;
      saveContent(key, { hidden: nowHidden });
      targetEl.classList.toggle('box-hidden-preview', nowHidden);
      targetEl.style.display = ''; // stay visible (faded) while in edit mode
      hideBtn.textContent = nowHidden ? 'Show box' : 'Hide box';
    };
  }
  panel.querySelector('.ep-close').onclick = () => removeStylePanel();

  setTimeout(() => document.addEventListener('mousedown', outsideClose), 0);
  function outsideClose(e) {
    if (!panel.contains(e.target) && e.target !== anchorEl) {
      removeStylePanel();
      document.removeEventListener('mousedown', outsideClose);
    }
  }
}

// ---------- SECTION RENDERERS (stats / chronicle / recruitment / officers) ----------
function renderStats() {
  const wrap = document.getElementById('stats-wrap');
  if (!wrap) return;
  const row = sectionsCache['stats'] || {};
  const items = row.data || [];
  wrap.innerHTML = items.map((it, i) => `
    <div class="colophon-cell">
      <span class="k" ${editMode?`contenteditable="true" data-si="stats" data-i="${i}" data-f="label"`:''}>${esc(it.label)}</span>
      <span class="v" ${editMode?`contenteditable="true" data-si="stats" data-i="${i}" data-f="value"`:''}>${esc(it.value)}</span>
      ${editMode?`<button class="edit-item-del" type="button" data-del="stats" data-i="${i}">×</button>`:''}
    </div>
  `).join('');
  wireSectionEditing('stats', items);
  if (editMode && !document.getElementById('stats-add')) {
    const btn = document.createElement('button');
    btn.id = 'stats-add'; btn.className='btn edit-add-btn'; btn.type='button'; btn.textContent='+ Add stat';
    btn.onclick = () => { items.push({label:'New Stat',value:'—'}); saveSection('stats',{data:items}); renderStats(); };
    wrap.insertAdjacentElement('afterend', btn);
  } else if (!editMode) {
    const b = document.getElementById('stats-add'); if (b) b.remove();
  }
}

function renderChronicle() {
  const wrap = document.getElementById('chronicle-wrap');
  if (!wrap) return;
  const row = sectionsCache['chronicle'] || {};
  const items = row.data || [];
  wrap.innerHTML = items.map((it, i) => `
    <div class="chronicle-item">
      <span class="date" ${editMode?`contenteditable="true" data-si="chronicle" data-i="${i}" data-f="date"`:''}>${esc(it.date)}</span>
      <div>
        <h4 ${editMode?`contenteditable="true" data-si="chronicle" data-i="${i}" data-f="title"`:''}>${esc(it.title)}</h4>
        <p ${editMode?`contenteditable="true" data-si="chronicle" data-i="${i}" data-f="body"`:''}>${esc(it.body)}</p>
      </div>
      ${editMode?`<button class="edit-item-del" type="button" data-del="chronicle" data-i="${i}">×</button>`:''}
    </div>
  `).join('');
  wireSectionEditing('chronicle', items);
  toggleAddBtn('chronicle-add', wrap, editMode, () => { items.unshift({date:fmtDate(new Date()),title:'New dispatch',body:'Write the news here.'}); saveSection('chronicle',{data:items}); renderChronicle(); }, '+ Add dispatch');
}

function renderRecruitment() {
  const wrap = document.getElementById('recruitment-wrap');
  if (!wrap) return;
  const row = sectionsCache['recruitment'] || {};
  const items = row.data || [];
  wrap.innerHTML = items.map((it, i) => `
    <div class="ad">
      <h4 ${editMode?`contenteditable="true" data-si="recruitment" data-i="${i}" data-f="class_name"`:''}>${esc(it.class_name)}</h4>
      <p ${editMode?`contenteditable="true" data-si="recruitment" data-i="${i}" data-f="notes"`:''}>${esc(it.notes)}</p>
      <span class="badge ${it.priority}" data-cycle="recruitment" data-i="${i}" title="${editMode?'Click to cycle priority':''}">Priority: ${esc(it.priority)}</span>
      ${editMode?`<button class="edit-item-del" type="button" data-del="recruitment" data-i="${i}">×</button>`:''}
    </div>
  `).join('');
  wireSectionEditing('recruitment', items);
  if (editMode) {
    wrap.querySelectorAll('[data-cycle="recruitment"]').forEach(badge => {
      badge.style.cursor = 'pointer';
      badge.onclick = () => {
        const order = ['high','medium','low'];
        const i = parseInt(badge.getAttribute('data-i'));
        const cur = items[i].priority || 'low';
        items[i].priority = order[(order.indexOf(cur)+1) % order.length];
        saveSection('recruitment', { data: items });
        renderRecruitment();
      };
    });
  }
  toggleAddBtn('recruitment-add', wrap, editMode, () => { items.push({class_name:'New Role',notes:'Describe what you need.',priority:'low'}); saveSection('recruitment',{data:items}); renderRecruitment(); }, '+ Add opening');
}

function renderOfficersDisplay() {
  const wrap = document.getElementById('officers-wrap');
  if (!wrap) return;
  const row = sectionsCache['officers_display'] || {};
  const items = row.data || [];
  wrap.innerHTML = items.map((it, i) => `
    <div class="officer-cell">
      <span class="who" ${editMode?`contenteditable="true" data-si="officers_display" data-i="${i}" data-f="name"`:''}>${esc(it.name)}</span>
      <span class="role" ${editMode?`contenteditable="true" data-si="officers_display" data-i="${i}" data-f="title"`:''}>${esc(it.title)}</span>
      ${editMode?`<button class="edit-item-del" type="button" data-del="officers_display" data-i="${i}">×</button>`:''}
    </div>
  `).join('');
  wireSectionEditing('officers_display', items);
  toggleAddBtn('officers-add', wrap, editMode, () => { items.push({name:'—',title:'New Role'}); saveSection('officers_display',{data:items}); renderOfficersDisplay(); }, '+ Add officer');
}

function toggleAddBtn(id, wrap, on, handler, label) {
  let btn = document.getElementById(id);
  if (on && !btn) {
    btn = document.createElement('button');
    btn.id = id; btn.className = 'btn edit-add-btn'; btn.type = 'button'; btn.textContent = label;
    wrap.insertAdjacentElement('afterend', btn);
  }
  if (btn) { btn.style.display = on ? '' : 'none'; btn.onclick = handler; }
}

function wireSectionEditing(sectionKey, items) {
  const scope = document;
  scope.querySelectorAll(`[data-si="${sectionKey}"]`).forEach(el => {
    el.oninput = () => {
      const i = parseInt(el.getAttribute('data-i'));
      const f = el.getAttribute('data-f');
      items[i][f] = el.textContent;
    };
    el.onblur = () => saveSection(sectionKey, { data: items });
  });
  scope.querySelectorAll(`[data-del="${sectionKey}"]`).forEach(btn => {
    btn.onclick = () => {
      const i = parseInt(btn.getAttribute('data-i'));
      items.splice(i, 1);
      saveSection(sectionKey, { data: items });
      renderAllSections();
    };
  });
}

function renderAllSections() {
  renderStats(); renderChronicle(); renderRecruitment(); renderOfficersDisplay();
}

// ---------- INIT (call from each page after loadSession) ----------
async function initEditableHome() {
  await Promise.all([loadEditableContent(), loadSections()]);
  applyContentOverrides();
  renderAllSections();

  const toggleWrap = document.getElementById('edit-toggle-wrap');
  if (toggleWrap && isOfficer()) {
    toggleWrap.innerHTML = `<label class="edit-toggle"><input type="checkbox" id="edit-toggle-cb"> Edit Mode</label>`;
    document.getElementById('edit-toggle-cb').onchange = (e) => setEditMode(e.target.checked);
  }
}
