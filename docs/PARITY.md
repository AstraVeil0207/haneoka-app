# Website parity

The app shows everything haneoka.org shows, with the same anatomy, tokens
and behaviour. Each page is checked against the website at 412 dp (phone)
and 1280 dp (desktop), light and dark, before it is ticked.

Status: `[x]` matches the website · `[~]` present, not yet matching · `[ ]` missing.

## Foundation

- [x] Colour schemes from `design-tokens/src/schemes.css` (haneoka + band-1..5)
- [ ] Type scale and font: Roboto + Noto Sans JP, M3 type tokens
- [ ] Icons: Material Symbols Rounded, outline at rest and filled when selected
- [~] Shell: top bar 64, rail 96, drawer 280, pane radius 28, modal drawer on compact
- [ ] Shell motion: fade-through between pages, drawer grows from the rail, search grows from its icon
- [ ] Top bar on compact turns surface-container when the page scrolls
- [ ] Drawer sections collapsible, as on the website
- [ ] Predictive back (Android), edge swipe back (iOS)
- [ ] JSON decoded off the UI thread; collection filtering and sorting memoised
- [ ] Images decoded at display size; disk cache per release

## Shared components (`lib/ui/`, mirrors `src/lit/ui/` and `src/styles/`)

- [ ] Tile: full-bleed media, corner marks, title-medium ×2 lines, body-medium subhead with 16 dp adornment
- [ ] Collection grid: per-kind minimum width, 2/3 columns on compact
- [ ] View switch: grid · list · table
- [ ] Collection list and table
- [ ] Filter sheet with facets and counts; applied filters as removable chips after the title
- [ ] Detail layout: image gallery, section headings, spec list, detail objects, related tiles, accordion
- [ ] Difficulty picker, level switch, upgrade cost
- [ ] Expressive loading indicator, wavy progress
- [ ] Playback controls and audio dock
- [ ] Dialogs, snackbars, selection pane

## Pages

Home: dashboard · announcements · calendar · join

Library: songs · song meta · events · event tracker · characters · member cards ·
snapshots · skills · comics · gacha · login campaigns · missions · passes ·
T.G.W card · studio · shop · exchange · stamps · stickers · backgrounds ·
items · band items · real lives

Stories: every story section (Vega playback later)

Tools: Live2D · Spine · assets · help · player profile · team builder ·
song progress · stamp maker · chart editor

Games: Sonolus · song puzzle · song guess

Anon Tokyo: characters · outfits · shop · goods · decorations · staff ·
customers · tasks · guide · fever

Community: feeds · tags · mine · following · bookmarks · notifications ·
activity · playlists · forums · GBP archive · Project Sekai

Account: sign-in · profile · settings · about · legal

Save: import on every platform · save view · export to the team builder
