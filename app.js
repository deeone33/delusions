// ============================================================
// DELUSION — shared JS (auth, nav, guards, utils)
// ============================================================

// Delusions Supabase project
const SUPABASE_URL = 'https://ebgudfwppgjvbckbxvyz.supabase.co';
const SUPABASE_KEY = 'sb_publishable_BJFTMOugMCYzyT7Ls_mflw_O_YJwxQa';
const sb = window.supabase.createClient(SUPABASE_URL, SUPABASE_KEY);

let currentUser    = null;
let currentProfile = null;

// ---- AUTH ----
async function loadSession() {
  const { data: { user } } = await sb.auth.getUser();
  if (!user) { currentUser = null; currentProfile = null; return null; }
  currentUser = user;
  const { data } = await sb.from('profiles').select('*').eq('id', user.id).single();
  currentProfile = data;
  return data;
}

const isGM       = () => currentProfile?.role === 'gm';
const isOfficer  = () => currentProfile?.role === 'officer' || isGM();
const isMember   = () => currentProfile?.role === 'member' || isOfficer();
const isLoggedIn = () => !!currentUser;

async function loginDiscord() {
  const base = window.location.origin + (window.location.pathname.includes('/') ? window.location.pathname.replace(/\/[^/]*$/, '/') : '/');
  const { error } = await sb.auth.signInWithOAuth({
    provider: 'discord',
    options: { redirectTo: base + 'dashboard.html' }
  });
  if (error) toast(error.message, 'error');
}

async function doLogout() {
  await sb.auth.signOut();
  window.location.href = 'index.html';
}

// ---- GUARDS ----
async function requireMember() {
  await loadSession();
  if (!isLoggedIn()) { toast('Please log in first.', 'error'); setTimeout(() => window.location.href = 'login.html', 800); return false; }
  if (!isMember()) { toast("Members only — you'll get access once an officer accepts your application.", 'error'); setTimeout(() => window.location.href = 'dashboard.html', 1200); return false; }
  return true;
}
async function requireOfficer() {
  await loadSession();
  if (!isLoggedIn()) { toast('Please log in first.', 'error'); setTimeout(() => window.location.href = 'login.html', 800); return false; }
  if (!isOfficer()) { toast('Officers only.', 'error'); setTimeout(() => window.location.href = 'dashboard.html', 1000); return false; }
  return true;
}

// ---- NAV ----
function renderNav(active) {
  const el = document.getElementById('topnav');
  if (!el) return;

  const links = [{ href: 'index.html', id: 'home', label: 'Home' }];
  if (isOfficer()) {
    links.push({ href: 'roster.html', id: 'roster', label: 'Roster' });
    links.push({ href: 'ledger.html', id: 'ledger', label: 'Ledger' });
  } else if (isMember()) {
    links.push({ href: 'ledger.html', id: 'ledger', label: 'Ledger' });
  }
  if (isMember()) links.push({ href: 'feedback.html', id: 'feedback', label: 'Feedback' });
  if (isOfficer()) {
    links.push({ href: 'applications.html', id: 'applications', label: 'Applications' });
    links.push({ href: 'officers.html', id: 'officers', label: 'Officers' });
  }
  if (!isMember()) links.push({ href: 'apply.html', id: 'apply', label: 'Apply' });

  const navLinks = links.map(l =>
    `<a href="${l.href}" class="${l.id === active ? 'active' : ''}" id="navlink-${l.id}">${l.label}<span class="nav-badge" id="navbadge-${l.id}" style="display:none;"></span></a>`
  ).join('');

  let user = '';
  if (currentProfile) {
    user = `<a href="dashboard.html" class="nav-user-link">
              <span class="pill ${isGM() ? 'gm' : isOfficer() ? 'officer' : isMember() ? 'member' : 'outsider'}">${esc(currentProfile.rank || currentProfile.role)}</span>
              <span style="color:var(--bone);font-family:'IBM Plex Mono',monospace;font-size:0.62rem;">${esc(currentProfile.username)}</span>
            </a>
            <button class="btn" onclick="doLogout()">Logout</button>`;
  } else {
    user = `<a href="login.html" class="btn">Login</a>`;
  }

  el.innerHTML = `${navLinks}<div class="divider"></div><div class="nav-ctas">${user}</div>`;

  if (isOfficer()) loadNavBadges();
}

// Runs after the nav is already visible, so a couple of extra queries never
// delay the page — badges just pop in a moment later.
async function loadNavBadges() {
  const { count: appCount } = await sb.from('applications').select('*', {count:'exact',head:true}).eq('status','pending');
  setNavBadge('applications', appCount);
  const { count: fbCount } = await sb.from('feedback').select('*', {count:'exact',head:true}).eq('status','new');
  setNavBadge('feedback', fbCount);
}
function setNavBadge(id, count) {
  const el = document.getElementById(`navbadge-${id}`);
  if (!el) return;
  if (count > 0) { el.textContent = count; el.style.display = ''; }
  else { el.style.display = 'none'; }
}

// ---- TOAST ----
function toast(msg, type = 'info') {
  const t = document.createElement('div');
  t.className = `toast ${type}`;
  t.textContent = msg;
  document.body.appendChild(t);
  setTimeout(() => t.remove(), 3000);
}

// ---- UTILS ----
function esc(s) {
  if (s == null) return '';
  return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
}
// ---- CLASS DATA (shared: Ledger, Manage Members, Apply form) ----
const CLASS_COLORS = {
  warrior:'#C79C6E', paladin:'#F58CBA', hunter:'#ABD473', rogue:'#FFF569',
  priest:'#FFFFFF', shaman:'#0070DE', mage:'#69CCF0', warlock:'#9482C9', druid:'#FF7D0A'
};
const CLASS_ICONS = {
  warrior:'icons/warrior.png', paladin:'icons/paladin.png', hunter:'icons/hunter.png',
  rogue:'icons/rogue.png', priest:'icons/priest.png', shaman:'icons/shaman.png',
  mage:'icons/mage.png', warlock:'icons/warlock.png', druid:'icons/druid.png'
};
const CLASS_SPECS = {
  warrior: ['Arms','Fury','Protection'],
  paladin: ['Holy','Protection','Retribution'],
  hunter: ['Beast Mastery','Marksmanship','Survival'],
  rogue: ['Assassination','Combat','Subtlety'],
  priest: ['Discipline','Holy','Shadow'],
  shaman: ['Elemental','Enhancement','Restoration'],
  mage: ['Arcane','Fire','Frost'],
  warlock: ['Affliction','Demonology','Destruction'],
  druid: ['Balance','Feral Combat','Restoration'],
};
function classColor(className) { return CLASS_COLORS[(className||'').toLowerCase()] || null; }
function classIcon(className) {
  const src = CLASS_ICONS[(className||'').toLowerCase()];
  return src ? `<img src="${src}" class="cls-icon" alt="">` : '';
}

function fmtDate(d) {
  if (!d) return '';
  return new Date(d).toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric' });
}

// ---- ACTIVITY LOG ----
// Fire-and-forget audit trail for officer actions. Never blocks or throws —
// losing a log entry is fine, losing the actual action it's logging is not.
function logActivity(action) {
  if (!isOfficer()) return;
  sb.from('activity_log').insert({
    officer_id: currentUser?.id,
    officer_name: currentProfile?.username || 'An officer',
    action,
  }).then(({ error }) => { if (error) console.warn('activity log failed:', error.message); });
}

// ---- COLLAPSIBLE SECTIONS ----
// Generic +/- toggle used for anything that should start hidden (officer
// forms, upload panels) so pages don't open cluttered by default.
function toggleCollapse(bodyId, iconId) {
  const body = document.getElementById(bodyId);
  const icon = document.getElementById(iconId);
  const isOpen = body.style.display !== 'none';
  body.style.display = isOpen ? 'none' : 'block';
  if (icon) icon.textContent = isOpen ? '+' : '−';
}
