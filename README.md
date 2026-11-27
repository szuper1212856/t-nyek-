# Tények++

The Tények++ website, its installable viewer app with push notifications, and the Szerkesztőség staff app.

| Path | What it is |
| --- | --- |
| `index.html` | Public site and installable viewer app |
| `szerkesztoseg/` | Staff app for Kiss Balázs and Kiss Olivér (`/szerkesztoseg/`) |
| `config.js` | Supabase and notification keys, shared by both apps |
| `sw.js`, `manifest.webmanifest`, `icons/` | What makes the site installable and able to receive notifications |
| `supabase/setup.sql` | Database tables and access rules |
| `supabase/functions/notify-episode/` | Sends the push notification when a new episode goes out |

Until `config.js` is filled in, the public site keeps working with the two built-in episodes and sends story tips by email.

## Setup

### 1. Database

In the Supabase dashboard, open **SQL Editor**, paste the whole of `supabase/setup.sql`, and click **Run**. It also adds the two existing episodes. Running it again is safe.

### 2. Staff accounts

**Authentication → Users → Add user → Create new user**: add an account for Balázs and one for Olivér, with **Auto Confirm User** ticked.

Then run this in the SQL Editor, with Olivér's real email address:

```sql
insert into public.staff (user_id, name)
select id, 'Kiss Balázs' from auth.users where email = 'balazs.kiss@creascola.hu';

insert into public.staff (user_id, name)
select id, 'Kiss Olivér' from auth.users where email = 'OLIVER-EMAIL-HERE';
```

Then turn off public sign-ups: **Authentication → Sign In / Providers → Allow new users to sign up** → off.

### 3. Notification keys

On your Mac, in Terminal:

```
npx web-push generate-vapid-keys
```

It prints a **Public Key** and a **Private Key**. The private key only goes into Supabase (step 4), never into `config.js` or GitHub.

### 4. Notification function

**Edge Functions → Secrets**, add three secrets:

| Name | Value |
| --- | --- |
| `VAPID_PUBLIC_KEY` | the Public Key from step 3 |
| `VAPID_PRIVATE_KEY` | the Private Key from step 3 |
| `VAPID_SUBJECT` | `mailto:balazs.kiss@creascola.hu` |

**Edge Functions → Deploy a new function → Via Editor**: name it exactly `notify-episode`, replace the example code with the contents of `supabase/functions/notify-episode/index.ts`, and deploy. Leave JWT verification on.

Or with the Supabase CLI, from the repo folder:

```
supabase login
supabase link --project-ref YOUR-PROJECT-REF
supabase secrets set VAPID_PUBLIC_KEY=... VAPID_PRIVATE_KEY=... VAPID_SUBJECT=mailto:balazs.kiss@creascola.hu
supabase functions deploy notify-episode
```

### 5. config.js

Fill in the three values. The URL and key are under **Project Settings → API Keys** (use the publishable or `anon` key, never the secret or `service_role` key).

```js
window.TENYEK_CONFIG = {
  supabaseUrl: "https://YOUR-PROJECT-REF.supabase.co",
  supabaseKey: "YOUR-PUBLISHABLE-OR-ANON-KEY",
  vapidPublicKey: "THE-PUBLIC-KEY-FROM-STEP-3"
};
```

### 6. Upload

Upload everything in this folder to the GitHub repo, keeping the folder structure. Vercel needs no extra settings.

Then open `https://tenyek.vercel.app/szerkesztoseg/` and log in.

## Everyday use

**New episode:** Szerkesztőség → Adások → **+ Új adás** → paste the YouTube link, add a title → **Adás mentése**. It appears on the site straight away, and with "Értesítés a nézőknek" on, every subscribed phone gets a notification.

**Story tips** from the site land in Szerkesztőség → Sztorik as *Beérkezett*. Move them through Ötlet → Forgatás → Vágás → Kész, add notes for each other, and link the finished episode.

**Installing the apps:** on Android, Chrome offers "Telepítés". On iPhone, open the page in Safari → Share → **Add to Home Screen**. Notifications on iPhone need iOS 16.4 or newer and only work from the home-screen app. Install the staff app the same way from `/szerkesztoseg/`.
