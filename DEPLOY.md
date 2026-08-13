# Vortex SiteTrack v4 — deploy & upgrade notes

## Files in this package
| File | Purpose |
|---|---|
| `index.html` | the whole application (paste your Supabase URL + anon key at the top) |
| `upgrade_v4.sql` | run once in Supabase → SQL Editor |
| `sw.js` | service worker — offline shell |
| `manifest.webmanifest` | makes the app installable on phones |
| `icon-192.png`, `icon-512.png` | home-screen icons |

All five files must sit **together in the same folder** on the server (repo root).

## Order of work
1. Supabase → SQL Editor → paste `upgrade_v4.sql` → Run.
2. Open `index.html`, paste `SUPABASE_URL` and `SUPABASE_ANON_KEY` on lines 118–120 (same two values as v3).
3. Upload all files to the repo root.
4. Settings → Pages → Deploy from branch → `main` / root.
5. Supabase → Authentication → URL Configuration → set Site URL + Redirect URL to the new address.

## Free hosting options
- **GitHub Pages** — free, public repo only on the free plan. Fine: the anon key is meant to be public, RLS does the protecting.
- **Cloudflare Pages** — free, works from a private repo, edge node in Singapore. Connect repo → build command: *(none)* → output directory: `/`.
- **Vercel** — free, same idea as Netlify.

Never commit the `service_role` key. Only the anon key belongs in `index.html`.

## On-site install (supervisors)
- Android/Chrome: open the URL → menu → *Add to Home screen*.
- iPhone/Safari: open the URL → Share → *Add to Home Screen*.

Once installed it opens full-screen with no browser bar and keeps working with no signal.
Reports submitted offline are held on the phone and sent automatically when data returns —
the amber bar at the bottom of the screen shows how many are waiting.

## Cache note
After you push a new `index.html`, bump `const CACHE = "sitetrack-v4"` in `sw.js`
to `sitetrack-v5` so every phone picks up the new version immediately.
