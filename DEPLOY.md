# DELUSION — Deployment Guide

This is a separate project from "Is a Problem" — it needs its own Supabase project,
Discord app, and GitHub repo. None of your old credentials carry over.

## Step 1: Create a new Supabase project

1. https://supabase.com → New Project (e.g. name it "delusion")
2. Wait for it to finish provisioning
3. Go to SQL Editor → New query → paste the full contents of `schema.sql` → Run
   - This creates the tables (profiles, applications, site_content, site_sections),
     sets up row-level security, and seeds the default homepage content.

## Step 2: Get your API credentials

1. Supabase → Project Settings → API
2. Copy the **Project URL** and the **anon / publishable key**
3. Open `app.js` and replace:
   ```js
   const SUPABASE_URL = 'https://YOUR-PROJECT-REF.supabase.co';
   const SUPABASE_KEY = 'YOUR-PUBLISHABLE-KEY';
   ```

## Step 3: Set up Discord login

1. https://discord.com/developers/applications → New Application → name it "Delusions"
2. OAuth2 → General → copy Client ID and Client Secret
3. Supabase → Authentication → Providers → Discord → enable it, paste in the Client ID/Secret
4. Supabase will show you a callback URL like `https://YOUR-PROJECT-REF.supabase.co/auth/v1/callback`
   — copy it into Discord Developer Portal → OAuth2 → Redirects

## Step 4: Make yourself the first officer

1. Log in to your (not-yet-deployed) site once via Discord — this creates your `profiles` row automatically
2. Supabase → Table Editor → `profiles` → find your row
3. Set `role` to `officer` and `rank` to e.g. `Guild Master`
4. Save — you'll now see the **Edit Mode** toggle at the top of the homepage

## Step 5: Push to GitHub

1. github.com → New Repository → name it `delusion` → Public → don't initialize with a README
2. Upload all project files: `index.html`, `login.html`, `apply.html`, `dashboard.html`,
   `roster.html`, `applications.html`, `officers.html`, `style.css`, `app.js`, `editor.js`,
   `logo.png`
3. Commit

## Step 6: Enable GitHub Pages

1. Repo → Settings → Pages → Source: "Deploy from a branch" → Branch: `main`, folder `/ (root)` → Save
2. After ~2 minutes your site is live at `https://YOUR-USERNAME.github.io/delusion/`

## Step 7: Update redirect URLs

Once you have the GitHub Pages URL (or a custom domain):

1. Supabase → Authentication → URL Configuration
   - Site URL: your live URL
   - Redirect URLs: add `https://YOUR-URL/**`
2. If you later attach a custom domain, repeat this step with the new domain

## How the visual editor works

- Only accounts with `role = 'officer'` in the `profiles` table see the **Edit Mode** toggle
  (top-left of the homepage, next to "Est. Aug 2026").
- Turn it on and every text field becomes directly editable — click in and type.
- Every box/button gets a small ✎ button in its corner — click it to open a panel where you
  can change **font size, font family, text color, and background color** for that element.
- The stat cards, chronicle (news), recruitment postings, and officer list are fully
  add/remove-able in Edit Mode (a "+ Add" button appears below each list, and a small × shows
  on each item).
- Everything saves automatically to Supabase a moment after you stop typing/changing it —
  no publish button, no page reload needed. Other visitors see the changes immediately.
- Reset any element's styling back to default with the "Reset" button in its style panel
  (this clears size/font/color overrides but keeps your text).

## Notes / current scope

- Font size, font family, text color, and background color are supported per-element.
  Things like custom fonts beyond the 3 loaded (Newsreader, IBM Plex Mono, Manrope),
  per-element font weight, and image/logo replacement aren't wired up yet — say the word
  if you want any of those added.
- Button links (href) aren't editable from the UI yet, just their label text and color —
  let me know if you want that too.
