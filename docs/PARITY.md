# Website parity

The app does everything haneoka.org does, natively, with the website's
navigation, anatomy, tokens and behaviour. The only parts that may wait are
the 3D chart player and the 3D story player. No page opens the website.

Each page is checked against the website at 412 dp and 1280 dp, light and
dark, before it is ticked. No release is published until every box is ticked.

Status: `[x]` matches the website · `[~]` native, not yet matching · `[ ]` missing.

## Shell

- [x] Colour schemes, type scale, Roboto, Material Symbols Rounded
- [x] Title bar with overflow, search, applied-filter chips
- [x] Settings: appearance, theme colour, density, language, Japanese titles, estimated difficulty, release server, spoilers
- [x] Audio player: now-playing in the bar / drawer, full player sheet
- [x] Drawer: the website's sections, order, labels and icons
- [x] Catalogue hub
- [x] Website links open their native page (`openLink`)
- [ ] Global search
- [ ] Account: sign-in (email, GitHub, Google, X, Discord), profile, account lifecycle
- [ ] Game account binding: link an Our Notes player (by importing its save) to the haneoka account; the profile shows the player's in-game summary (rank, rating, clears, cards); the website's profile and the database carry the binding; app-only pages for it in M3 Expressive

## Home

- [~] Dashboard (banners, event, birthdays, latest songs and cards; missing: announcements, community, news, fan info, layout editing)
- [x] Announcements (list, detail, home module)
- [x] Calendar
- [x] Join

## Library

- [x] Songs · [~] song detail (metrics, skill timeline from the chart, Gekisou stages, rewards, MV; missing: comments)
- [~] Song meta (table, tiers, live/gekisou; missing: scatter chart view)
- [x] Events · [x] event detail (overview, recruitments, reward cards, bonuses by card rank, song, story, live rewards with boost and bonus, rewards, missions) · [x] event tracker (challenge and point rankings, live)
- [x] Characters · [x] character page (profile with rank rewards, cards, stamps, voices, stories, bonds on the friendship board, missions, Live2D list, songs)
- [x] Members · [x] member and snapshot detail (level, training, awakening, rank and skill sliders, stats, upgrade costs, skill text per level)
- [x] Snapshots
- [x] Skills (catalogue, detail, upgrade materials)
- [x] Comics · [x] gacha (featured, rates, simulator with image export) · [x] login campaigns · [x] missions (group overview, group lists) · [x] passes · [x] T.G.W card (rank picker, card art, benefits, grants)
- [x] Studio
- [x] Shop (storefront prices with conversion) · [x] exchange · [x] stamps · [x] stickers (unlock conditions, artwork card) · [x] backgrounds · [x] items (acquisition and uses) · [x] band items (effects and costs by level) · [x] real lives

## Stories

- [x] Event, band, link, birthday, home, afterlive, tutorial: browse with the website's rails and groups
- [x] Transcript reader with locations, speakers and voices (3D player may wait)
- [ ] Story filters · [ ] home spot scene

## Tools

- [ ] Live2D viewer · [ ] Spine viewer · [ ] Assets · [ ] Help
- [x] Player profile · [ ] Team builder · [ ] Song progress · [ ] Stamp maker · [ ] Chart editor

## Games

- [ ] Sonolus · [ ] Song puzzle · [ ] Song guess

## Community

- [ ] Recommended, latest, tags · [ ] mine, following, bookmarks, notifications, activity
- [ ] Playlists · [ ] Forums · [ ] Posts, comments, editor

## GBP archive · Project Sekai

- [ ] Bestdori songs and story sections · [ ] Sekai songs and story sections

## Save

- [x] Import on every platform · [x] save view · [x] export to the team builder
