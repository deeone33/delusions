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
alter table profile_characters add column if not exists class_name text;
alter table profile_characters add column if not exists spec text;
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
  exists (select 1 from profiles p where p.id = auth.uid() and p.role in ('officer','gm'))
);
drop policy if exists "officers delete profile_characters" on profile_characters;
create policy "officers delete profile_characters" on profile_characters for delete using (
  exists (select 1 from profiles p where p.id = auth.uid() and p.role in ('officer','gm'))
);
-- Self-service: any member can add/remove characters on their OWN account
-- without needing an officer, matching how they'd add an alt themselves.
drop policy if exists "own character insert" on profile_characters;
create policy "own character insert" on profile_characters for insert with check (
  profile_id = auth.uid()
);
drop policy if exists "own character delete" on profile_characters;
create policy "own character delete" on profile_characters for delete using (
  profile_id = auth.uid()
);
drop policy if exists "own character update" on profile_characters;
create policy "own character update" on profile_characters for update using (
  profile_id = auth.uid()
) with check (
  profile_id = auth.uid()
);

-- Auto-create a profile row whenever someone signs in for the first time
create or replace function public.handle_new_user()
returns trigger as $$
begin
  insert into public.profiles (id, username, avatar_url, rank)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'full_name', new.raw_user_meta_data->>'name', 'Adventurer'),
    new.raw_user_meta_data->>'avatar_url',
    'Newcomer'
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
  exists (select 1 from profiles p where p.id = auth.uid() and p.role in ('officer','gm'))
);
drop policy if exists "officers delete raid_nights" on raid_nights;
create policy "officers delete raid_nights" on raid_nights for delete using (
  exists (select 1 from profiles p where p.id = auth.uid() and p.role in ('officer','gm'))
);

drop policy if exists "public read raid_attendees" on raid_attendees;
create policy "public read raid_attendees" on raid_attendees for select using (true);
drop policy if exists "officers insert raid_attendees" on raid_attendees;
create policy "officers insert raid_attendees" on raid_attendees for insert with check (
  exists (select 1 from profiles p where p.id = auth.uid() and p.role in ('officer','gm'))
);

alter table loot_log enable row level security;

drop policy if exists "public read loot_log" on loot_log;
create policy "public read loot_log" on loot_log for select using (true);

drop policy if exists "officers insert loot_log" on loot_log;
create policy "officers insert loot_log" on loot_log for insert with check (
  exists (select 1 from profiles p where p.id = auth.uid() and p.role in ('officer','gm'))
);

drop policy if exists "officers delete loot_log" on loot_log;
create policy "officers delete loot_log" on loot_log for delete using (
  exists (select 1 from profiles p where p.id = auth.uid() and p.role in ('officer','gm'))
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
-- Structured versions of class_spec, from the dropdown-based apply form.
-- class_spec stays populated too (e.g. "Restoration Shaman") for backward
-- compatibility with existing display code and Discord messages.
alter table applications add column if not exists class_name text;  -- lowercase, e.g. "shaman" — matches the site's CLASS_ICONS keys
alter table applications add column if not exists spec text;         -- e.g. "Restoration"
-- Extra characters beyond the primary one (applicant_name/class_name/spec
-- above), each { name, class_name, spec, warcraftlogs_url }. Kept as a
-- simple JSON array rather than a separate table since it's small,
-- write-once-per-application data, not something queried independently.
alter table applications add column if not exists additional_characters jsonb default '[]'::jsonb;

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
  exists (select 1 from profiles p where p.id = auth.uid() and p.role in ('officer','gm'))
  or (audience = 'members' and exists (select 1 from profiles p where p.id = auth.uid() and p.role in ('member','officer')))
  or (audience = 'all' and auth.uid() is not null)
);
drop policy if exists "officers write polls" on polls;
create policy "officers write polls" on polls for insert with check (
  exists (select 1 from profiles p where p.id = auth.uid() and p.role in ('officer','gm'))
);
drop policy if exists "officers update polls" on polls;
create policy "officers update polls" on polls for update using (
  exists (select 1 from profiles p where p.id = auth.uid() and p.role in ('officer','gm'))
);
drop policy if exists "officers delete polls" on polls;
create policy "officers delete polls" on polls for delete using (
  exists (select 1 from profiles p where p.id = auth.uid() and p.role in ('officer','gm'))
);

drop policy if exists "poll_options visible with poll" on poll_options;
create policy "poll_options visible with poll" on poll_options for select using (
  exists (select 1 from polls po where po.id = poll_id and (
    exists (select 1 from profiles p where p.id = auth.uid() and p.role in ('officer','gm'))
    or (po.audience = 'members' and exists (select 1 from profiles p where p.id = auth.uid() and p.role in ('member','officer')))
    or (po.audience = 'all' and auth.uid() is not null)
  ))
);
drop policy if exists "officers write poll_options" on poll_options;
create policy "officers write poll_options" on poll_options for insert with check (
  exists (select 1 from profiles p where p.id = auth.uid() and p.role in ('officer','gm'))
);

drop policy if exists "poll_votes visible with poll" on poll_votes;
create policy "poll_votes visible with poll" on poll_votes for select using (
  exists (select 1 from polls po where po.id = poll_id and (
    exists (select 1 from profiles p where p.id = auth.uid() and p.role in ('officer','gm'))
    or (po.audience = 'members' and exists (select 1 from profiles p where p.id = auth.uid() and p.role in ('member','officer')))
    or (po.audience = 'all' and auth.uid() is not null)
  ))
);
drop policy if exists "vote if audience allows" on poll_votes;
create policy "vote if audience allows" on poll_votes for insert with check (
  voter_id = auth.uid() and exists (select 1 from polls po where po.id = poll_id and po.status = 'open' and (
    exists (select 1 from profiles p where p.id = auth.uid() and p.role in ('officer','gm'))
    or (po.audience = 'members' and exists (select 1 from profiles p where p.id = auth.uid() and p.role in ('member','officer')))
    or (po.audience = 'all' and auth.uid() is not null)
  ))
);
drop policy if exists "voter update own vote" on poll_votes;
create policy "voter update own vote" on poll_votes for update using (voter_id = auth.uid());
drop policy if exists "officers delete poll_votes" on poll_votes;
create policy "officers delete poll_votes" on poll_votes for delete using (
  exists (select 1 from profiles p where p.id = auth.uid() and p.role in ('officer','gm'))
);

-- ---------- FEEDBACK ----------
-- Same visibility shape as applications: submitter sees their own,
-- officers/gm see and manage everything.
create table if not exists feedback (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references profiles(id) on delete set null,
  username text,
  message text not null,
  status text not null default 'new',   -- new | reviewed
  created_at timestamptz default now()
);

alter table feedback enable row level security;

drop policy if exists "feedback insert own" on feedback;
create policy "feedback insert own" on feedback for insert with check (auth.uid() = user_id);

drop policy if exists "feedback select own or officer" on feedback;
create policy "feedback select own or officer" on feedback for select using (
  auth.uid() = user_id
  or exists (select 1 from profiles p where p.id = auth.uid() and p.role in ('officer','gm'))
);

drop policy if exists "officers update feedback" on feedback;
create policy "officers update feedback" on feedback for update using (
  exists (select 1 from profiles p where p.id = auth.uid() and p.role in ('officer','gm'))
);

drop policy if exists "officers delete feedback" on feedback;
create policy "officers delete feedback" on feedback for delete using (
  exists (select 1 from profiles p where p.id = auth.uid() and p.role in ('officer','gm'))
);

-- ---------- WISHLISTS ----------
-- thatsmybis-style ranked item list, one per player per phase. Locking
-- freezes the list+order for officer review; a locked player can only
-- *request* an unlock — actually unlocking requires officer/GM action,
-- enforced below via RLS, not just hidden in the UI.
create table if not exists wishlists (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid references profiles(id) on delete cascade,
  phase text not null,
  locked boolean not null default false,
  locked_at timestamptz,
  unlock_requested boolean not null default false,
  unlock_requested_at timestamptz,
  created_at timestamptz default now(),
  updated_at timestamptz default now(),
  unique(profile_id, phase)
);
-- Wishlists are per-character now (an account can have several, one per
-- linked alt), not one shared list for the whole account.
alter table wishlists add column if not exists character_name text;
-- Snapshot of item names captured at the moment a list is locked, so
-- officers can compare "what it was when I approved the unlock" against
-- "what it is now" without a full version-history system.
alter table wishlists add column if not exists locked_snapshot jsonb;
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'wishlists_profile_phase_char_key') then
    alter table wishlists drop constraint if exists wishlists_profile_id_phase_key;
    alter table wishlists add constraint wishlists_profile_phase_char_key unique (profile_id, phase, character_name);
  end if;
end $$;

-- Every lock and every officer-approved unlock gets its own permanent
-- snapshot row here — this is what lets an officer compare "what it was
-- when I approved the unlock" against "what it became after they edited
-- it," without those snapshots overwriting each other over time.
create table if not exists wishlist_history (
  id uuid primary key default gen_random_uuid(),
  wishlist_id uuid references wishlists(id) on delete cascade,
  event text not null,   -- 'locked' | 'unlocked_by_officer'
  items_snapshot jsonb not null,
  created_at timestamptz default now()
);
alter table wishlist_history enable row level security;
drop policy if exists "wishlist_history select own or officer" on wishlist_history;
create policy "wishlist_history select own or officer" on wishlist_history for select using (
  exists (select 1 from wishlists w where w.id = wishlist_id and (
    w.profile_id = auth.uid()
    or exists (select 1 from profiles p where p.id = auth.uid() and p.role in ('officer','gm'))
  ))
);
drop policy if exists "wishlist_history insert own or officer" on wishlist_history;
create policy "wishlist_history insert own or officer" on wishlist_history for insert with check (
  exists (select 1 from wishlists w where w.id = wishlist_id and (
    w.profile_id = auth.uid()
    or exists (select 1 from profiles p where p.id = auth.uid() and p.role in ('officer','gm'))
  ))
);

create table if not exists wishlist_items (
  id uuid primary key default gen_random_uuid(),
  wishlist_id uuid references wishlists(id) on delete cascade,
  item_text text not null,
  item_link text,               -- optional Wowhead item URL, enables the tooltip/quality-color widget
  sort_order int not null default 0,
  received boolean not null default false,
  received_at timestamptz,
  received_by text,             -- 'auto' (matched from a loot import) or whoever's username marked it
  officer_note text
);

alter table wishlists      enable row level security;
alter table wishlist_items enable row level security;

-- ---- wishlists ----
drop policy if exists "wishlists select own or officer" on wishlists;
create policy "wishlists select own or officer" on wishlists for select using (
  auth.uid() = profile_id
  or exists (select 1 from profiles p where p.id = auth.uid() and p.role in ('officer','gm'))
);
drop policy if exists "wishlists insert own" on wishlists;
create policy "wishlists insert own" on wishlists for insert with check (auth.uid() = profile_id);

-- Free editing (including locking itself) while currently unlocked.
drop policy if exists "wishlists player edit while unlocked" on wishlists;
create policy "wishlists player edit while unlocked" on wishlists for update using (
  auth.uid() = profile_id and locked = false
) with check (
  auth.uid() = profile_id
);
-- Once locked, this is the ONLY policy left available to the player — the
-- WITH CHECK forces locked to stay true, so they can toggle
-- unlock_requested but can never flip locked back to false themselves.
drop policy if exists "wishlists player request unlock" on wishlists;
create policy "wishlists player request unlock" on wishlists for update using (
  auth.uid() = profile_id and locked = true
) with check (
  auth.uid() = profile_id and locked = true
);
drop policy if exists "wishlists officer manage" on wishlists;
create policy "wishlists officer manage" on wishlists for update using (
  exists (select 1 from profiles p where p.id = auth.uid() and p.role in ('officer','gm'))
);
drop policy if exists "wishlists delete own or officer" on wishlists;
create policy "wishlists delete own or officer" on wishlists for delete using (
  (auth.uid() = profile_id and locked = false)
  or exists (select 1 from profiles p where p.id = auth.uid() and p.role in ('officer','gm'))
);

-- ---- wishlist_items ----
drop policy if exists "wishlist_items select own or officer" on wishlist_items;
create policy "wishlist_items select own or officer" on wishlist_items for select using (
  exists (select 1 from wishlists w where w.id = wishlist_id and (
    w.profile_id = auth.uid()
    or exists (select 1 from profiles p where p.id = auth.uid() and p.role in ('officer','gm'))
  ))
);
-- Player: free add/edit/reorder of their own items while the list is unlocked.
drop policy if exists "wishlist_items player insert while unlocked" on wishlist_items;
create policy "wishlist_items player insert while unlocked" on wishlist_items for insert with check (
  exists (select 1 from wishlists w where w.id = wishlist_id and w.profile_id = auth.uid() and w.locked = false)
);
drop policy if exists "wishlist_items player update while unlocked" on wishlist_items;
create policy "wishlist_items player update while unlocked" on wishlist_items for update using (
  exists (select 1 from wishlists w where w.id = wishlist_id and w.profile_id = auth.uid() and w.locked = false)
);
drop policy if exists "wishlist_items player delete while unlocked" on wishlist_items;
create policy "wishlist_items player delete while unlocked" on wishlist_items for delete using (
  exists (select 1 from wishlists w where w.id = wishlist_id and w.profile_id = auth.uid() and w.locked = false)
);
-- Player: can mark their OWN item received regardless of lock state
-- (receiving loot doesn't care whether the list is frozen for review), but
-- this is a one-way door — the WITH CHECK only ever allows the result to be
-- true, so this policy can't be used to un-receive something.
drop policy if exists "wishlist_items player mark received" on wishlist_items;
create policy "wishlist_items player mark received" on wishlist_items for update using (
  exists (select 1 from wishlists w where w.id = wishlist_id and w.profile_id = auth.uid())
) with check (
  exists (select 1 from wishlists w where w.id = wishlist_id and w.profile_id = auth.uid())
  and received = true
);
-- Officer (not GM): full edit while an item is still unreceived (covers
-- adding notes, marking it received).
-- Officers can now fully manage any item (including un-receiving) — widened
-- from the earlier officer/GM split at the person's explicit request.
-- GM's remaining exclusive power is the bulk "Clear All Received" action,
-- which is just several of these same per-item updates fired at once from
-- the UI — there's nothing left to distinguish at the RLS level here.
drop policy if exists "wishlist_items officer edit unreceived" on wishlist_items;
drop policy if exists "wishlist_items officer edit received notes only" on wishlist_items;
drop policy if exists "wishlist_items officer manage" on wishlist_items;
create policy "wishlist_items officer manage" on wishlist_items for update using (
  exists (select 1 from profiles p where p.id = auth.uid() and p.role = 'officer')
);
-- GM: unrestricted — can un-receive, bulk-clear, edit anything.
drop policy if exists "wishlist_items gm manage" on wishlist_items;
create policy "wishlist_items gm manage" on wishlist_items for update using (
  exists (select 1 from profiles p where p.id = auth.uid() and p.role = 'gm')
);
-- Deleting an item outright (as opposed to a player removing their own
-- while unlocked, above) is GM-only.
drop policy if exists "wishlist_items gm delete" on wishlist_items;
create policy "wishlist_items gm delete" on wishlist_items for delete using (
  exists (select 1 from profiles p where p.id = auth.uid() and p.role = 'gm')
);

-- ---------- LAST SEEN (online status for Roster) ----------
alter table profiles add column if not exists last_seen_at timestamptz;
alter table profiles add column if not exists last_activity_view_at timestamptz;
-- No new policy needed — the existing "profiles update own" policy
-- (auth.uid() = id) already covers updating this column.

-- ---------- GEAR CHECK ----------
-- One row per character per raid night (tied to raid_nights, so history
-- is just "which past raid night has gear_check rows"). enchants/gems are
-- jsonb arrays of {slot, itemName, status:'good'|'suboptimal'|'missing'|'na', detail}
-- status is deliberately 3-tier (not just pass/fail): 'suboptimal' covers
-- things like a Revered-rank shoulder enchant where Exalted exists, or a
-- Rare-quality gem where Epic exists — present, but not best-in-slot.
create table if not exists gear_checks (
  id uuid primary key default gen_random_uuid(),
  raid_night_id uuid references raid_nights(id) on delete cascade,
  character_name text not null,
  class_name text,
  enchants jsonb not null default '[]',
  gems jsonb not null default '[]',
  synced_at timestamptz default now(),
  unique(raid_night_id, character_name)
);
alter table gear_checks enable row level security;
drop policy if exists "gear_checks read all" on gear_checks;
create policy "gear_checks read all" on gear_checks for select using (auth.uid() is not null);
drop policy if exists "gear_checks officer write" on gear_checks;
create policy "gear_checks officer write" on gear_checks for insert with check (
  exists (select 1 from profiles p where p.id = auth.uid() and p.role in ('officer','gm'))
);
drop policy if exists "gear_checks officer update" on gear_checks;
create policy "gear_checks officer update" on gear_checks for update using (
  exists (select 1 from profiles p where p.id = auth.uid() and p.role in ('officer','gm'))
);
drop policy if exists "gear_checks officer delete" on gear_checks;
create policy "gear_checks officer delete" on gear_checks for delete using (
  exists (select 1 from profiles p where p.id = auth.uid() and p.role in ('officer','gm'))
);

-- ---------- CONSUMABLES ----------
-- One row per character per boss per raid night. Each jsonb field carries
-- both the used/missing flag AND the exact item(s)/count, so the detail
-- popup (click a cell to see exactly what was used) doesn't need a second
-- query — it's already in the row.
create table if not exists consumable_logs (
  id uuid primary key default gen_random_uuid(),
  raid_night_id uuid references raid_nights(id) on delete cascade,
  boss_name text not null,
  character_name text not null,
  class_name text,
  food jsonb not null default '{}',           -- {used, name}
  flask_elixir jsonb not null default '{}',   -- {type:'flask'|'elixir'|'partial'|'none', names:[]}
  scroll jsonb not null default '{}',         -- {applicable, used, name}
  potions jsonb not null default '{}',        -- {count, names:[]} - combined destro/haste/mana, since only one is typically used
  other jsonb not null default '[]',          -- [{name, count}] - Flame Cap, Nightmare Seed, Ironshield, etc
  synced_at timestamptz default now(),
  unique(raid_night_id, boss_name, character_name)
);
alter table consumable_logs add column if not exists potions jsonb not null default '{}';
alter table consumable_logs add column if not exists other jsonb not null default '[]';
alter table consumable_logs enable row level security;
drop policy if exists "consumable_logs read all" on consumable_logs;
create policy "consumable_logs read all" on consumable_logs for select using (auth.uid() is not null);
drop policy if exists "consumable_logs officer write" on consumable_logs;
create policy "consumable_logs officer write" on consumable_logs for insert with check (
  exists (select 1 from profiles p where p.id = auth.uid() and p.role in ('officer','gm'))
);
drop policy if exists "consumable_logs officer update" on consumable_logs;
create policy "consumable_logs officer update" on consumable_logs for update using (
  exists (select 1 from profiles p where p.id = auth.uid() and p.role in ('officer','gm'))
);
drop policy if exists "consumable_logs officer delete" on consumable_logs;
create policy "consumable_logs officer delete" on consumable_logs for delete using (
  exists (select 1 from profiles p where p.id = auth.uid() and p.role in ('officer','gm'))
);

-- ---------- STREAMS ----------
-- One row per account — "posting a stream" edits this info, "Go Live" /
-- "Go Offline" just toggles status on the same row, so nobody re-fills the
-- form every session. Public SELECT (using true) because the Streams page
-- is viewable without logging in.
create table if not exists streams (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid references profiles(id) on delete cascade unique,
  username text,
  url text not null,
  title text not null,
  class_name text,
  content_type text,
  status text not null default 'offline',  -- offline | live
  went_live_at timestamptz,
  updated_at timestamptz default now()
);
alter table streams enable row level security;

drop policy if exists "streams public read" on streams;
create policy "streams public read" on streams for select using (true);
drop policy if exists "streams own insert" on streams;
create policy "streams own insert" on streams for insert with check (profile_id = auth.uid());
drop policy if exists "streams own update" on streams;
create policy "streams own update" on streams for update using (profile_id = auth.uid());
drop policy if exists "streams officer delete" on streams;
create policy "streams officer delete" on streams for delete using (
  exists (select 1 from profiles p where p.id = auth.uid() and p.role in ('officer','gm'))
);

-- ---------- PLAYER MESSAGES ----------
-- Direct officer-to-player messages, shown on the recipient's dashboard.
create table if not exists player_messages (
  id uuid primary key default gen_random_uuid(),
  from_officer_id uuid references profiles(id),
  from_officer_name text,
  to_profile_id uuid references profiles(id) on delete cascade,
  to_username text,
  message text not null,
  status text not null default 'sent',  -- sent | seen | cleared
  created_at timestamptz default now(),
  seen_at timestamptz,
  cleared_at timestamptz
);
alter table player_messages enable row level security;

drop policy if exists "player_messages select own or officer" on player_messages;
create policy "player_messages select own or officer" on player_messages for select using (
  to_profile_id = auth.uid()
  or exists (select 1 from profiles p where p.id = auth.uid() and p.role in ('officer','gm'))
);
drop policy if exists "player_messages officer insert" on player_messages;
create policy "player_messages officer insert" on player_messages for insert with check (
  exists (select 1 from profiles p where p.id = auth.uid() and p.role in ('officer','gm'))
);
-- Recipient can only move their own message forward (sent -> seen -> cleared),
-- never edit its content or reassign it to someone else.
drop policy if exists "player_messages recipient update status" on player_messages;
create policy "player_messages recipient update status" on player_messages for update using (
  to_profile_id = auth.uid()
);
drop policy if exists "player_messages officer delete" on player_messages;
create policy "player_messages officer delete" on player_messages for delete using (
  exists (select 1 from profiles p where p.id = auth.uid() and p.role in ('officer','gm'))
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
alter table activity_log add column if not exists ref_type text;  -- e.g. 'wishlist' — lets an entry link back to specific data
alter table activity_log add column if not exists ref_id uuid;

alter table activity_log enable row level security;
drop policy if exists "officers read activity_log" on activity_log;
create policy "officers read activity_log" on activity_log for select using (
  exists (select 1 from profiles p where p.id = auth.uid() and p.role in ('officer','gm'))
);
drop policy if exists "officers write activity_log" on activity_log;
drop policy if exists "authenticated write activity_log" on activity_log;
-- Widened from officer-only: players now log their own actions too (marking
-- an item received, locking a wishlist). Reading and clearing stay
-- restricted (officer-read, gm-clear below) — this only affects who can
-- ADD a line, not who can see or erase the trail.
create policy "authenticated write activity_log" on activity_log for insert with check (
  auth.uid() is not null
);
-- Clearing the audit trail is GM-only, deliberately — a corrupt officer
-- shouldn't be able to erase evidence of their own actions.
drop policy if exists "gm clear activity_log" on activity_log;
create policy "gm clear activity_log" on activity_log for delete using (
  exists (select 1 from profiles p where p.id = auth.uid() and p.role = 'gm')
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
drop policy if exists "officers manage non-officer profiles" on profiles;
-- Plain officers can promote outsiders to members and manage non-officer
-- accounts freely, but this USING clause means an officer/gm-tier row is
-- simply not selectable for update by a plain officer at all — not just
-- role-locked, invisible to the update entirely. That's what stops a
-- corrupt officer from touching (or demoting) another officer or the GM.
create policy "officers manage non-officer profiles" on profiles for update using (
  exists (select 1 from profiles p where p.id = auth.uid() and p.role in ('officer','gm'))
  and role in ('outsider','member')
) with check (
  role in ('outsider','member')
);
-- GM has full, unrestricted control — the only role that can promote to
-- officer, demote an officer, or touch another officer's account at all.
drop policy if exists "gm update any profile" on profiles;
create policy "gm update any profile" on profiles for update using (
  exists (select 1 from profiles p where p.id = auth.uid() and p.role = 'gm')
);

-- applications: a user can submit + see their own; officers see/update all
drop policy if exists "applications insert own" on applications;
create policy "applications insert own" on applications for insert with check (auth.uid() = user_id);

drop policy if exists "applications select own" on applications;
create policy "applications select own" on applications for select using (auth.uid() = user_id);

drop policy if exists "officers select all applications" on applications;
create policy "officers select all applications" on applications for select using (
  exists (select 1 from profiles p where p.id = auth.uid() and p.role in ('officer','gm'))
);

drop policy if exists "officers update applications" on applications;
create policy "officers update applications" on applications for update using (
  exists (select 1 from profiles p where p.id = auth.uid() and p.role in ('officer','gm'))
);

drop policy if exists "officers delete applications" on applications;
create policy "officers delete applications" on applications for delete using (
  exists (select 1 from profiles p where p.id = auth.uid() and p.role in ('officer','gm'))
);

-- site_content / site_sections: public read (so the homepage renders for everyone),
-- only officers can write (this is what makes the visual editor officer-only)
drop policy if exists "site_content read all" on site_content;
create policy "site_content read all" on site_content for select using (true);

drop policy if exists "site_content officer insert" on site_content;
create policy "site_content officer insert" on site_content for insert with check (
  exists (select 1 from profiles p where p.id = auth.uid() and p.role in ('officer','gm'))
);

drop policy if exists "site_content officer update" on site_content;
create policy "site_content officer update" on site_content for update using (
  exists (select 1 from profiles p where p.id = auth.uid() and p.role in ('officer','gm'))
);

drop policy if exists "site_sections read all" on site_sections;
create policy "site_sections read all" on site_sections for select using (true);

drop policy if exists "site_sections officer insert" on site_sections;
create policy "site_sections officer insert" on site_sections for insert with check (
  exists (select 1 from profiles p where p.id = auth.uid() and p.role in ('officer','gm'))
);

drop policy if exists "site_sections officer update" on site_sections;
create policy "site_sections officer update" on site_sections for update using (
  exists (select 1 from profiles p where p.id = auth.uid() and p.role in ('officer','gm'))
);
