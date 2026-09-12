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
  updateLastSeen();
  return data;
}

// Fire-and-forget, on every page load and every 2 minutes while a tab
// stays open — this is what Roster's online/last-seen column reads.
function updateLastSeen() {
  if (!currentUser) return;
  sb.from('profiles').update({ last_seen_at: new Date().toISOString() }).eq('id', currentUser.id).then(() => {});
  clearInterval(window._lastSeenHeartbeat);
  window._lastSeenHeartbeat = setInterval(() => {
    if (currentUser) sb.from('profiles').update({ last_seen_at: new Date().toISOString() }).eq('id', currentUser.id).then(() => {});
  }, 120000);
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
  links.push({ href: 'streams.html', id: 'streams', label: 'Streams' });
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
    user = `<a href="dashboard.html" class="nav-user-link" id="navlink-account">
              <span class="pill ${isGM() ? 'gm' : isOfficer() ? 'officer' : isMember() ? 'member' : 'outsider'}">${esc(currentProfile.rank || currentProfile.role)}</span>
              <span style="color:var(--bone);font-family:'IBM Plex Mono',monospace;font-size:0.62rem;">${esc(currentProfile.username)}</span>
              <span class="nav-badge" id="navbadge-account" style="display:none;"></span>
            </a>
            <button class="btn" onclick="doLogout()">Logout</button>`;
  } else {
    user = `<a href="login.html" class="btn">Login</a>`;
  }

  el.innerHTML = `${navLinks}<div class="divider"></div><div class="nav-ctas">${user}</div>`;

  if (isOfficer()) loadNavBadges();
  else if (isMember()) loadMemberNavBadges();
}

// Runs after the nav is already visible, so a couple of extra queries never
// delay the page — badges just pop in a moment later.
async function loadNavBadges() {
  const { count: appCount } = await sb.from('applications').select('*', {count:'exact',head:true}).eq('status','pending');
  setNavBadge('applications', appCount);
  const { count: fbCount } = await sb.from('feedback').select('*', {count:'exact',head:true}).eq('status','new');
  setNavBadge('feedback', fbCount);
  const { count: wlCount } = await sb.from('wishlists').select('*', {count:'exact',head:true}).eq('unlock_requested', true);
  setNavBadge('ledger', wlCount); // surfaces on the Ledger tab itself, since Wishlist lives inside it
}

async function loadMemberNavBadges() {
  // Unseen messages from officers
  const { count: msgCount } = await sb.from('player_messages').select('*', {count:'exact',head:true}).eq('to_profile_id', currentUser.id).eq('status', 'sent');
  setNavBadge('account', msgCount);

  // Missing wishlist for the current phase — nudges toward the Ledger
  let phase = null;
  try { const r = await sb.from('site_content').select('*').eq('key','config.current_phase').single(); phase = r.data?.text; } catch (e) { phase = null; }
  if (phase) {
    const { count: wlCount } = await sb.from('wishlists').select('*', {count:'exact',head:true}).eq('profile_id', currentUser.id).eq('phase', phase);
    if (!wlCount) setNavBadge('ledger', 1);
  }
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
// For embedding a JS string value inside a single-quoted onclick="..."
// attribute. JSON.stringify alone isn't enough - it produces a
// double-quoted JS string, but any literal apostrophe in the VALUE (e.g.
// "Naj'entus") still ends the single-quoted HTML attribute early, since
// the HTML parser runs before the JS engine ever sees the string. Escaping
// to \u0027 keeps it as plain text in the markup, and the JS engine still
// reads it back as a real apostrophe once it parses the string.
function jsAttr(s) {
  return JSON.stringify(s).replace(/'/g, '\\u0027');
}
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
  druid: ['Balance','Feral','Restoration'],
};
function classColor(className) { return CLASS_COLORS[(className||'').toLowerCase()] || null; }
function classIcon(className) {
  const src = CLASS_ICONS[(className||'').toLowerCase()];
  return src ? `<img src="${src}" class="cls-icon" alt="">` : '';
}

// Role detected from combat activity (see sync logic) - simple unicode
// symbols rather than custom art, since these are small inline indicators.
function roleIcon(role) {
  const wrap = (content, tooltip) => `<span title="${tooltip||''}" style="display:inline-block;width:1.3em;text-align:center;margin-right:0.25rem;">${content}</span>`;
  if (role === 'tank') return wrap('🛡️', 'Tank (detected from combat activity)');
  if (role === 'healer') return wrap('✚', 'Healer (detected from combat activity)');
  if (role === 'dps') return wrap('⚔️', 'DPS (detected from combat activity)');
  return wrap(''); // reserve the same width even with no detected role, so names always align
}
function getDetectedRole(name) {
  return (typeof gearCheckRows !== 'undefined' && gearCheckRows.find(r => r.character_name === name)?.detected_role) || null;
}

function fmtDate(d) {
  if (!d) return '';
  return new Date(d).toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric' });
}

// ---- ACTIVITY LOG ----
// Fire-and-forget audit trail for officer actions. Never blocks or throws —
// losing a log entry is fine, losing the actual action it's logging is not.
// Fire-and-forget audit trail. Used to be officer-only, but player-initiated
// actions (locking a wishlist, marking an item received) need to show up
// here too now — reading and clearing stay officer/GM-restricted at the
// database level (see schema.sql), this just controls who can add a line.
function logActivity(action, ref) {
  if (!isLoggedIn()) return;
  sb.from('activity_log').insert({
    officer_id: currentUser?.id,
    officer_name: currentProfile?.username || 'Someone',
    action,
    ref_type: ref?.type || null,
    ref_id: ref?.id || null,
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
