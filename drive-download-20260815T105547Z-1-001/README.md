# Hans Sese — Video Portfolio

A simple, modern portfolio site for your short-form product videos and reels.
No server or code knowledge needed to keep it updated.

## Preview it

Double-click `index.html`. It opens in your browser.

To share it online, drag the whole folder into [Netlify Drop](https://app.netlify.com/drop)
or push it to a GitHub Pages repo — no setup required.

## Project layout

```
index.html      the page itself
css/style.css   styles (edit to change look)
js/site.js      YOUR info: name, bio, links, accent colour
js/data.js      generated list of your media (do not edit)
js/details.json titles & descriptions for each reel (edit this)
videos/         put video files here
images/         put photos here (optional)
thumbs/         poster images, generated automatically
tools/          two scripts that do the work for you
```

## Adding or removing videos (the scalable part)

1. **Add**: drop the file into `videos/` (`.mov`, `.mp4`, `.mkv`, `.webm`, `.m4v`, `.avi` all work).
   - **Remove**: just delete the file from `videos/`. That's it.
   - **Hide without deleting**: in `js/details.json`, set `"hide": true` for that reel.
2. Run **`tools/convert.ps1`** (right-click → Run with PowerShell). This creates a
   browser-friendly MP4 copy and a poster thumbnail. It only processes new files, so it's safe to re-run.
3. Run **`tools/regenerate.ps1`**. This rebuilds `js/data.js`.
4. Refresh `index.html`.

### Adding photos

Drop `.jpg`, `.png`, `.webp` or `.gif` files into the `images/` folder, then run `tools/regenerate.ps1`.

## Giving your reels real titles

Open **`js/details.json`** — each reel has an entry like this:

```json
"copy_0286DA4D-06B6-44AD-8CC6-AA2039020D5F": {
  "title": "Smart Watch Launch Reel",
  "category": "Products",
  "description": "15-second launch teaser cut to a beat — product reveal, key features, strong ending.",
  "tags": ["tech", "launch", "product"],
  "order": 1,
  "hide": false
}
```

- `title` — shown on the card and in the player
- `category` — used for the filter buttons ("Products", "Photography", etc.)
- `description` — shown when the video opens
- `tags` — makes the search box work ("tech", "launch", ...)
- `order` — lower numbers appear first (1, 2, 3...)
- `hide` — `true` removes it from the site without deleting the file

After editing, re-run `tools/regenerate.ps1` and refresh the page.

> The key (e.g. `copy_0286DA4D-...`) is the file name without its extension.
> `_note` and `_example` entries are just for reference — they don't appear on the site.

## Changing your info

Open **`js/site.js`** and edit:
- your name, job title, tagline and bio
- email / phone / social links (leave `""` to hide a button)
- the accent colour (`"accent"`), e.g. `"#e8546b"`
- the software/skills tags in the About section

## Customising the look

The whole design lives in `css/style.css`. Easy places to start:
- `--bg` / `--card` — background and card colours
- `--accent` — highlight colour (also overridable from `js/site.js`)
- `.grid` `columns: 4 280px` — number and minimum width of grid columns

## Notes

- The converted MP4s are what the site plays (works in every browser — Safari, Chrome, Firefox, Edge).
- The original `.mov` files stay in `videos/` as your source material. You can move them out
  of the folder if you want a smaller upload; the MP4s are all the site needs.
- Everything is static HTML/CSS/JS — free to host anywhere, no backend.
