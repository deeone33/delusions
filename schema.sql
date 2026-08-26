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
-- Added later — safe to re-run
alter table profiles add column if not exists character_name text;  -- deprecated, kept for backward-compat only — see profile_characters below
alter table profiles add column if not exists joined_at timestamptz; -- when they became a member (accepted or manually promoted)

-- One account can have multiple linked characters (main + alts), so
-- attendance/loot aggregate correctly regardless of which character
-- someone brought to a given raid.
create table if not exists profile_characters (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid references profiles(id) on delete cascade,
  character_name text not null,
  created_at timestamptz default now()
);
-- One-time migration: carry over anything already set in the old single
-- character_name field so existing officer work isn't lost.
insert into profile_characters (profile_id, character_name)
select id, character_name from profiles
where character_name is not null and character_name <> ''
  and not exists (
    select 1 from profile_characters pc
    where pc.profile_id = profiles.id and lower(pc.character_name) = lower(profiles.character_name)
  );

alter table profile_characters enable row level security;
drop policy if exists "public read profile_characters" on profile_characters;
create policy "public read profile_characters" on profile_characters for select using (true);
drop policy if exists "officers write profile_characters" on profile_characters;
create policy "officers write profile_characters" on profile_characters for insert with check (
  exists (select 1 from profiles p where p.id = auth.uid() and p.role = 'officer')
);
drop policy if exists "officers delete profile_characters" on profile_characters;
create policy "officers delete profile_characters" on profile_characters for delete using (
  exists (select 1 from profiles p where p.id = auth.uid() and p.role = 'officer')
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

-- ---------- LOOT LOG ----------
create table if not exists loot_log (
  id uuid primary key default gen_random_uuid(),
  raid_title text,
  awarded_at date,
  item_name text,
  item_link text,
  winner_name text,
  response text,          -- BIS / MS / OS / etc, whatever the officer's council uses
  raw jsonb,               -- the original CSV row, untouched, so nothing is ever lost
  uploaded_by uuid references profiles(id),
  created_at timestamptz default now()
);
-- Added later — safe to re-run even if loot_log already exists
alter table loot_log add column if not exists class_name text;

-- ---------- RAID ATTENDANCE ----------
-- Populated from the DelusionsAttendance in-game addon (/dumpraid), pasted
-- in by an officer. Deliberately separate from loot_log: loot only tells
-- you who WON something, not who was actually there.
create table if not exists raid_nights (
  id uuid primary key default gen_random_uuid(),
  title text,
  raid_date date,
  created_by uuid references profiles(id),
  created_at timestamptz default now()
);

create table if not exists raid_attendees (
  id uuid primary key default gen_random_uuid(),
  raid_night_id uuid references raid_nights(id) on delete cascade,
  character_name text not null,
  class_name text
);

alter table raid_nights    enable row level security;
alter table raid_attendees enable row level security;

drop policy if exists "public read raid_nights" on raid_nights;
create policy "public read raid_nights" on raid_nights for select using (true);
drop policy if exists "officers insert raid_nights" on raid_nights;
create policy "officers insert raid_nights" on raid_nights for insert with check (
  exists (select 1 from profiles p where p.id = auth.uid() and p.role = 'officer')
);
drop policy if exists "officers delete raid_nights" on raid_nights;
create policy "officers delete raid_nights" on raid_nights for delete using (
  exists (select 1 from profiles p where p.id = auth.uid() and p.role = 'officer')
);

drop policy if exists "public read raid_attendees" on raid_attendees;
create policy "public read raid_attendees" on raid_attendees for select using (true);
drop policy if exists "officers insert raid_attendees" on raid_attendees;
create policy "officers insert raid_attendees" on raid_attendees for insert with check (
  exists (select 1 from profiles p where p.id = auth.uid() and p.role = 'officer')
);

alter table loot_log enable row level security;

drop policy if exists "public read loot_log" on loot_log;
create policy "public read loot_log" on loot_log for select using (true);

drop policy if exists "officers insert loot_log" on loot_log;
create policy "officers insert loot_log" on loot_log for insert with check (
  exists (select 1 from profiles p where p.id = auth.uid() and p.role = 'officer')
);

drop policy if exists "officers delete loot_log" on loot_log;
create policy "officers delete loot_log" on loot_log for delete using (
  exists (select 1 from profiles p where p.id = auth.uid() and p.role = 'officer')
);

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
alter table applications add column if not exists officer_note text;  -- visible to the applicant, set when accepting/rejecting

-- ---------- POLLS ----------
-- Audience controls who can see AND vote: officers | members (officers+members) | all (any logged-in account, outsiders included).
-- This is enforced at the RLS level, not just hidden in the UI — if the
-- database won't return a poll to someone, the Polls tab correctly doesn't
-- even appear for them, current or past.
create table if not exists polls (
  id uuid primary key default gen_random_uuid(),
  question text not null,
  audience text not null default 'members',  -- officers | members | all
  status text not null default 'open',       -- open | closed
  created_by uuid references profiles(id),
  created_by_name text,
  created_at timestamptz default now(),
  closed_at timestamptz
);

create table if not exists poll_options (
  id uuid primary key default gen_random_uuid(),
  poll_id uuid references polls(id) on delete cascade,
  option_text text not null,
  sort_order int default 0
);

create table if not exists poll_votes (
  id uuid primary key default gen_random_uuid(),
  poll_id uuid references polls(id) on delete cascade,
  option_id uuid references poll_options(id) on delete cascade,
  voter_id uuid references profiles(id),
  voter_name text,
  created_at timestamptz default now(),
  unique(poll_id, voter_id)
);

alter table polls        enable row level security;
alter table poll_options enable row level security;
alter table poll_votes   enable row level security;

drop policy if exists "polls visible by audience" on polls;
create policy "polls visible by audience" on polls for select using (
  exists (select 1 from profiles p where p.id = auth.uid() and p.role = 'officer')
  or (audience = 'members' and exists (select 1 from profiles p where p.id = auth.uid() and p.role in ('member','officer')))
  or (audience = 'all' and auth.uid() is not null)
);
drop policy if exists "officers write polls" on polls;
create policy "officers write polls" on polls for insert with check (
  exists (select 1 from profiles p where p.id = auth.uid() and p.role = 'officer')
);
drop policy if exists "officers update polls" on polls;
create policy "officers update polls" on polls for update using (
  exists (select 1 from profiles p where p.id = auth.uid() and p.role = 'officer')
);
drop policy if exists "officers delete polls" on polls;
create policy "officers delete polls" on polls for delete using (
  exists (select 1 from profiles p where p.id = auth.uid() and p.role = 'officer')
);

drop policy if exists "poll_options visible with poll" on poll_options;
create policy "poll_options visible with poll" on poll_options for select using (
  exists (select 1 from polls po where po.id = poll_id and (
    exists (select 1 from profiles p where p.id = auth.uid() and p.role = 'officer')
    or (po.audience = 'members' and exists (select 1 from profiles p where p.id = auth.uid() and p.role in ('member','officer')))
    or (po.audience = 'all' and auth.uid() is not null)
  ))
);
drop policy if exists "officers write poll_options" on poll_options;
create policy "officers write poll_options" on poll_options for insert with check (
  exists (select 1 from profiles p where p.id = auth.uid() and p.role = 'officer')
);

drop policy if exists "poll_votes visible with poll" on poll_votes;
create policy "poll_votes visible with poll" on poll_votes for select using (
  exists (select 1 from polls po where po.id = poll_id and (
    exists (select 1 from profiles p where p.id = auth.uid() and p.role = 'officer')
    or (po.audience = 'members' and exists (select 1 from profiles p where p.id = auth.uid() and p.role in ('member','officer')))
    or (po.audience = 'all' and auth.uid() is not null)
  ))
);
drop policy if exists "vote if audience allows" on poll_votes;
create policy "vote if audience allows" on poll_votes for insert with check (
  voter_id = auth.uid() and exists (select 1 from polls po where po.id = poll_id and po.status = 'open' and (
    exists (select 1 from profiles p where p.id = auth.uid() and p.role = 'officer')
    or (po.audience = 'members' and exists (select 1 from profiles p where p.id = auth.uid() and p.role in ('member','officer')))
    or (po.audience = 'all' and auth.uid() is not null)
  ))
);
drop policy if exists "voter update own vote" on poll_votes;
create policy "voter update own vote" on poll_votes for update using (voter_id = auth.uid());
drop policy if exists "officers delete poll_votes" on poll_votes;
create policy "officers delete poll_votes" on poll_votes for delete using (
  exists (select 1 from profiles p where p.id = auth.uid() and p.role = 'officer')
);

-- ---------- ACTIVITY LOG ----------
-- Audit trail for officer actions — who deleted/approved/edited what.
create table if not exists activity_log (
  id uuid primary key default gen_random_uuid(),
  officer_id uuid references profiles(id),
  officer_name text,
  action text not null,
  created_at timestamptz default now()
);

alter table activity_log enable row level security;
drop policy if exists "officers read activity_log" on activity_log;
create policy "officers read activity_log" on activity_log for select using (
  exists (select 1 from profiles p where p.id = auth.uid() and p.role = 'officer')
);
drop policy if exists "officers write activity_log" on activity_log;
create policy "officers write activity_log" on activity_log for insert with check (
  exists (select 1 from profiles p where p.id = auth.uid() and p.role = 'officer')
);

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
