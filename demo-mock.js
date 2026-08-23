// ============================================================
// DEMO-ONLY MOCK of the Supabase client, so Edit Mode can be
// tried live without a real Supabase project. Not part of the
// deployed site — don't upload this file to GitHub.
// Data lives in localStorage so your edits survive a refresh.
// ============================================================

const DEMO_STORE_KEY = 'delusion_demo_store_v1';

function demoDefaultStore() {
  return {
    profiles: [{ id: 'demo-officer', username: 'Deetarded', role: 'officer', rank: 'Guild Master', created_at: new Date().toISOString() }],
    applications: [],
    site_content: [],
    site_sections: [
      { key: 'stats', data: [{label:'Members',value:'24'},{label:'Open Spots',value:'3'},{label:'Raid Days',value:'Tue / Thu'},{label:'Founded',value:'Aug 2026'}] },
      { key: 'chronicle', data: [
        {date:'17 Aug 2026',title:'Guild founded',body:"Delusions is officially live. Roster forming now — applications open for progression raiding."},
        {date:'15 Aug 2026',title:'First raid night set',body:'Tuesday and Thursday, 20:00 server time. Attendance tracked from week one.'}
      ]},
      { key: 'recruitment', data: [
        {class_name:'Resto Shaman',notes:'Chain heal / totem coverage a plus. Trial raid this week.',priority:'high'},
        {class_name:'Enhance Shaman',notes:'Melee DPS, windfury uptime matters most.',priority:'medium'},
        {class_name:'Warlock',notes:'Any spec considered, curse coordination valued.',priority:'low'}
      ]},
      { key: 'officers_display', data: [{name:'Deetarded',title:'Guild Master'},{name:'—',title:'Raid Lead'},{name:'—',title:'Loot Officer'}] }
    ]
  };
}

function loadDemoStore() {
  try {
    const raw = localStorage.getItem(DEMO_STORE_KEY);
    if (raw) return JSON.parse(raw);
  } catch (e) {}
  return demoDefaultStore();
}
let DEMO = loadDemoStore();
function persistDemo() { localStorage.setItem(DEMO_STORE_KEY, JSON.stringify(DEMO)); }

function demoFrom(table) {
  DEMO[table] = DEMO[table] || [];
  return {
    select(_cols) {
      const p = Promise.resolve({ data: DEMO[table] });
      p.eq = (col, val) => {
        const row = DEMO[table].find(r => r[col] === val);
        return { single: () => Promise.resolve({ data: row || null }) };
      };
      p.in = (col, vals) => Promise.resolve({ data: DEMO[table].filter(r => vals.includes(r[col])) });
      p.order = () => p;
      return p;
    },
    upsert(row) {
      const pk = table === 'profiles' || table === 'applications' ? 'id' : 'key';
      const idx = DEMO[table].findIndex(r => r[pk] === row[pk]);
      if (idx >= 0) DEMO[table][idx] = { ...DEMO[table][idx], ...row };
      else DEMO[table].push(row);
      persistDemo();
      return Promise.resolve({ error: null });
    },
    insert(row) {
      DEMO[table].push({ id: 'demo-' + Date.now(), submitted_at: new Date().toISOString(), ...row });
      persistDemo();
      return Promise.resolve({ error: null });
    },
    update(patch) {
      return { eq: (col, val) => {
        const row = DEMO[table].find(r => r[col] === val);
        if (row) Object.assign(row, patch);
        persistDemo();
        return Promise.resolve({ error: null });
      }};
    }
  };
}

window.supabase = {
  createClient: () => ({
    auth: {
      getUser: async () => ({ data: { user: { id: 'demo-officer' } } }),
      signInWithOAuth: async () => { toast('Demo mode — login is simulated as the Guild Master.', 'info'); return { error: null }; },
      signOut: async () => { localStorage.removeItem(DEMO_STORE_KEY); }
    },
    from: demoFrom
  })
};
