-- ============================================================
-- DELUSION — Supabase schema
-- Run this once in Supabase → SQL Editor → New query → Run
-- ============================================================

-- ---------- PROFILES ----------
create table if not exists profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text,
  avatar_url text,
  role text not null default 'outsider',   -- outsider | member | officer
  rank text default '',                     -- display title, e.g. "Guild Master"
  created_at timestamptz default now()
);

-- Auto-create a profile row whenever someone signs in for the first time
create or replace function public.handle_new_user()
returns trigger as $$
begin
  insert into public.profiles (id, username, avatar_url)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'full_name', new.raw_user_meta_data->>'name', 'Adventurer'),
    new.raw_user_meta_data->>'avatar_url'
  )
  on conflict (id) do nothing;
  return new;
end;
$$ language plpgsql security definer;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- ---------- APPLICATIONS ----------
create table if not exists applications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete cascade,
  applicant_name text,
  class_spec text,
  experience text,
  status text not null default 'pending',   -- pending | accepted | rejected
  submitted_at timestamptz default now()
);
-- Added later — safe to re-run even if you already ran this file once before
alter table applications add column if not exists warcraftlogs_url text;
alter table applications add column if not exists why_join text;

-- ---------- SITE CONTENT (single editable text/style fields) ----------
create table if not exists site_content (
  key text primary key,
  text text,
  font_size text,
  font_family text,
  color text,
  bg_color text,
  updated_at timestamptz default now()
);
-- Added later — explicit ALTERs so re-running this file also updates a
-- database that was already set up before these columns existed.
alter table site_content add column if not exists box_height text;
alter table site_content add column if not exists crest_offset_x text;
alter table site_content add column if not exists crest_offset_y text;
alter table site_content add column if not exists hidden boolean default false;

-- ---------- SITE SECTIONS (editable repeating lists: news, recruitment, officers, stats) ----------
create table if not exists site_sections (
  key text primary key,
  data jsonb not null default '[]',
  text_style jsonb,
  box_style jsonb,
  updated_at timestamptz default now()
);

insert into site_sections (key, data) values
('stats', '[{"label":"Members","value":"24"},{"label":"Open Spots","value":"3"},{"label":"Raid Days","value":"Tue / Thu"},{"label":"Founded","value":"Aug 2026"}]'),
('chronicle', '[{"date":"17 Aug 2026","title":"Guild founded","body":"Delusions is officially live. Roster forming now — applications open for progression raiding."},{"date":"15 Aug 2026","title":"First raid night set","body":"Tuesday and Thursday, 20:00 server time. Attendance tracked from week one."}]'),
('recruitment', '[{"class_name":"Resto Shaman","notes":"Chain heal / totem coverage a plus. Trial raid this week.","priority":"high"},{"class_name":"Enhance Shaman","notes":"Melee DPS, windfury uptime matters most.","priority":"medium"},{"class_name":"Warlock","notes":"Any spec considered, curse coordination valued.","priority":"low"}]'),
('officers_display', '[{"name":"Deetarded","title":"Guild Master"},{"name":"—","title":"Raid Lead"},{"name":"—","title":"Loot Officer"}]')
on conflict (key) do nothing;

-- ============================================================
-- ROW LEVEL SECURITY
-- ============================================================
alter table profiles enable row level security;
alter table applications enable row level security;
alter table site_content enable row level security;
alter table site_sections enable row level security;

-- profiles: everyone can read (roster/nav needs it), a user can update their own row,
-- officers can update anyone's row (used to promote/demote members)
drop policy if exists "profiles read all" on profiles;
create policy "profiles read all" on profiles for select using (true);

drop policy if exists "profiles update own" on profiles;
create policy "profiles update own" on profiles for update using (auth.uid() = id);

drop policy if exists "officers update any profile" on profiles;
create policy "officers update any profile" on profiles for update using (
  exists (select 1 from profiles p where p.id = auth.uid() and p.role = 'officer')
);

-- applications: a user can submit + see their own; officers see/update all
drop policy if exists "applications insert own" on applications;
create policy "applications insert own" on applications for insert with check (auth.uid() = user_id);

drop policy if exists "applications select own" on applications;
create policy "applications select own" on applications for select using (auth.uid() = user_id);

drop policy if exists "officers select all applications" on applications;
create policy "officers select all applications" on applications for select using (
  exists (select 1 from profiles p where p.id = auth.uid() and p.role = 'officer')
);

drop policy if exists "officers update applications" on applications;
create policy "officers update applications" on applications for update using (
  exists (select 1 from profiles p where p.id = auth.uid() and p.role = 'officer')
);

drop policy if exists "officers delete applications" on applications;
create policy "officers delete applications" on applications for delete using (
  exists (select 1 from profiles p where p.id = auth.uid() and p.role = 'officer')
);

-- site_content / site_sections: public read (so the homepage renders for everyone),
-- only officers can write (this is what makes the visual editor officer-only)
drop policy if exists "site_content read all" on site_content;
create policy "site_content read all" on site_content for select using (true);

drop policy if exists "site_content officer insert" on site_content;
create policy "site_content officer insert" on site_content for insert with check (
  exists (select 1 from profiles p where p.id = auth.uid() and p.role = 'officer')
);

drop policy if exists "site_content officer update" on site_content;
create policy "site_content officer update" on site_content for update using (
  exists (select 1 from profiles p where p.id = auth.uid() and p.role = 'officer')
);

drop policy if exists "site_sections read all" on site_sections;
create policy "site_sections read all" on site_sections for select using (true);

drop policy if exists "site_sections officer insert" on site_sections;
create policy "site_sections officer insert" on site_sections for insert with check (
  exists (select 1 from profiles p where p.id = auth.uid() and p.role = 'officer')
);

drop policy if exists "site_sections officer update" on site_sections;
create policy "site_sections officer update" on site_sections for update using (
  exists (select 1 from profiles p where p.id = auth.uid() and p.role = 'officer')
);
