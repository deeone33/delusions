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

const isOfficer  = () => currentProfile?.role === 'officer';
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
  if (isMember()) links.push({ href: 'roster.html', id: 'roster', label: 'Roster' });
  if (isOfficer()) {
    links.push({ href: 'applications.html', id: 'applications', label: 'Applications' });
    links.push({ href: 'officers.html', id: 'officers', label: 'Officers' });
  }
  if (!isMember()) links.push({ href: 'apply.html', id: 'apply', label: 'Apply' });

  const navLinks = links.map(l =>
    `<a href="${l.href}" class="${l.id === active ? 'active' : ''}">${l.label}</a>`
  ).join('');

  let user = '';
  if (currentProfile) {
    user = `<a href="dashboard.html" class="nav-user-link">
              <span class="pill ${isOfficer() ? 'officer' : isMember() ? 'member' : 'outsider'}">${esc(currentProfile.rank || currentProfile.role)}</span>
              <span style="color:var(--bone);font-family:'IBM Plex Mono',monospace;font-size:0.62rem;">${esc(currentProfile.username)}</span>
            </a>
            <button class="btn" onclick="doLogout()">Logout</button>`;
  } else {
    user = `<a href="login.html" class="btn">Login</a>`;
  }

  el.innerHTML = `${navLinks}<div class="divider"></div><div class="nav-ctas">${user}</div>`;
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
function fmtDate(d) {
  if (!d) return '';
  return new Date(d).toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric' });
}
