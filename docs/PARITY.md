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
- [x] Global search (catalogue, stories, help in every language; community posts)
- [x] About
- [x] Account: imported game accounts kept on the device with a player profile · [x] haneoka sign-in through the website (every provider, PKCE handoff, bearer session in secure storage) · [x] profile (display name, handle, bio) and sign-in sessions with revoke · [ ] avatar upload and account deletion stay on the website's account page
- [x] Game account binding: link an imported player to the haneoka account (public or private), update its summary, unlink; stored in `community_game_account` with a summary snapshot; the website's public profile shows server, player ID, rank and rating
- [x] haneoka.org links open in the app on Android (verified App Links)

## Home

- [x] Dashboard (banners, event, birthdays, announcements, latest songs and cards, trending community, bandori.fans, layout customization)
- [x] Announcements (list, detail, home module)
- [x] Calendar
- [x] Join

## Library

- [x] Songs (performer line: resolved names, band logos, vocalist faces) · [x] song detail (metrics, skill timeline from the chart, Gekisou stages, rewards, MV, comments)
- [x] Comments on every catalogue entry the website discusses
- [x] Song meta (table, tiers, live/gekisou, scatter by level and the sorted metric)
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
- [~] Story search (facets by character, band, kind and release still to port) · [ ] home spot scene

## Tools

- [~] Live2D: collection and model pages (preview, motions, expressions) · interactive viewer may wait with the 3D players · [~] Spine: collection and model pages (setup-pose preview, family, animations) · interactive viewer may wait with the 3D players · [x] Assets · [x] Help
- [x] Player profile · [ ] Team builder · [x] Song progress (filled from the imported save) · [~] Stamp maker (textless and original stamps, text layers with the pinned faces, outline, rotation, vertical writing, background, character colours, PNG export, post to community; fixed text frames still to port) · [ ] Chart editor

## Games

- [x] Sonolus · [x] Song puzzle (IDA* solver, hints, replay, edit mode) · [x] Song guess

## Community

- [x] For you, latest, following, mine, bookmarks (balanced columns, entity comments in the feed) · [x] tags · [x] notifications · [x] my comments
- [x] Playlists (picks, Stage Challenge, in-game, community, the reader's own with editor) · [x] Forums · [x] Posts, threaded comments, likes, bookmarks, follows · [x] Post editor with markup, stickers and uploads · [x] Member profiles with linked game accounts

## GBP archive · Project Sekai

- [x] GBP songs and song pages (song-meta metrics) · [x] GBP event, band, main, afterlive and card stories with the scenario reader · [x] Project Sekai songs and story sections

## Save

- [x] Import on every platform · [x] save view · [x] export to the team builder

## One-to-one audit

Every screen is compared against what haneoka.org actually renders, read from
the live DOM (`img` candidates, computed `object-fit`/`object-position`, marks,
app-bar buttons) and from the website source, never inferred.

- [x] Collection tiles: image field order, locale image variants, fit and framing, accent ground, event artwork, Ended/Retired marks, column counts
- [x] Detail galleries: entries, order and locale variants per kind (`detailMediaItems`, `CHARACTER_ART`), captions, natural event art · [x] animated card movie entry (anime parts, then the Live2D intro and loop over the card background)
- [x] App bar: 40 dp actions fitted as the website does, entity Back and previous/next, Menu in the overflow beside Back, identity marks kept beside the title, song ranking / play / Sonolus
- [x] Cross-server catalogue: collections merge JP and international entries with the server mark; JP-only entries open on the JP release · [x] sort options and defaults per kind · [x] shop prices
- [ ] Rails, home modules, stories and tools re-checked the same way
