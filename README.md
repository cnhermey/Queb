# Queb (v0.9.1)

When you log in, the addon helps you find guildmates on the same quests, so you can group up instead of questing alone. Grouped questing is faster.

- **Login summary.** About 20 seconds after you log in, chat lists the guildmates you share the most quests with, plus their level and zone. Click a name to whisper that player, or right-click it to invite them.
- **The Queb window** (type `/queb`, click any circle, or go to Esc → Options → AddOns → Queb). It has two tabs:
  - **Quebmates:** guildmates ranked by shared quests, then by closest level. Each name has the roles that player picked (Blizzard's tank, healer and damage icons) right after it. Each row has an Invite button, and hovering over a row compares your progress with theirs on each shared quest.
  - **Settings:** every option, as Blizzard checkboxes and sliders. The same window appears in Blizzard's AddOns options, and changes in one show up in the other.
- **Your role.** Right of the tabs, tick Tank, Healer and/or Damage, like the Dungeon Finder role check. Roles your class can't play are grayed out. Quebmates see your choice next to your name. Group members without Queb show the role assigned in the group, if any. Both sides need Queb 0.9.0 or newer to see each other's picks.
- **Resizable window.** Drag the grabber in the bottom-right corner, in both directions; make it short when your list is short. The Settings tab scrolls when the window is shorter than its options. The size and position are remembered.
- **Class-colored circles right after each quest title** in the quest list and the objective tracker. They only use empty space: the addon measures where the title ends and where the next Blizzard element starts (the checkmark, for example), and never covers icons. Titles that wrap or are cut short get no circles on the row, but hovering over them still shows the circles in the tooltip. Each circle is a guildmate on that quest, and a gold ring means they're ready to turn it in. Hover to see progress.
- **EllesmereUI Quest Tracker support.** When Ellesmere's own tracker is on (its default style on Forever), the circles appear on each quest row, to the **right** of the title. They go through Ellesmere's official row API, which reserves space there; the left side holds Ellesmere's focus buttons. Up to 3 circles fit, plus "+N". Hovering over an Ellesmere quest shows the same circles in its tooltip. With Ellesmere's "Blizzard" or "Classic" styles, the normal tracker circles appear after the title.
- **Guild & Communities tooltips.** Hover over a guildmate in the guild member list to see "Queb: N shared quests", up to 6 of those quests with their progress, and a circle in their class color. When shared quests can't be seen, the tooltip shows a short reason: "no Queb, not grouped", "too far away", "offline" or "syncing". Turn it off with Settings → Guild tooltips.
- **OpenMap player markers.** With OpenMap installed, hovering a player on its map shows the same Queb lines as the guild tooltip: guildmates' dots (when they share their position in OpenMap), party and raid dots, and zone badges (only the people you share quests with, most first). Turn it off with Settings → OpenMap players, or from OpenMap's own menu ("Queb: shared quests").
- **Circles in quest tooltips.** Hover over a quest area or quest marker on the world map, a quest in the map's quest list, or a quest in the tracker. Blizzard's tooltip then gains a row of class-colored circles plus each guildmate's progress. Turn it off with Settings → Quest tooltips.

- **Can share (yellow "!").** Queb shows quests a guildmate could share with you: quests they have and you don't, that you haven't done, and that are near your level. You'll see them in the Quebmates tab (a "!" with a count on their row; hover for the list), in the login summary ("can share 2") and in guild, OpenMap and zone tooltips. The reverse works too: hovering one of your quests shows "Can share with:" and the guildmates who could take it from you. The "!" is Blizzard's available-quest icon, never a class color, so it can't be confused with a guildmate circle. The game only lets players share a quest while grouped and nearby, so invite first. Queb can't check quest chains or class/race limits, so once in a while the game may still refuse a share. Both sides need Queb 0.8.3 or newer. Turn it off with Settings → Can share.
- **Near your level.** When you share no quests with someone, the summary and the window also suggest online guildmates within ±3 levels of you (Settings → Level range changes this), with anyone in your zone listed first. This includes guildmates who don't have the addon, because their level and zone come from the guild roster.

### Guildmates without the addon
- **Ungrouped:** they show up in "Near your level", using level and zone from the guild roster, and you can invite them from there. Which quests they're on is unknown, because the game doesn't share another player's quests outside a party.
- **Grouped with you:** faded circles show which of your quests they're on (using `C_QuestLog.IsUnitOnQuest`, no progress numbers), and the tooltip says "on quest, no Queb". This is on by default; Settings → Group members without Queb turns it off.
- With the addon on both sides, you also get full progress and sharing without grouping.

### Looks like Blizzard's UI
Queb is built to look like part of WoW: Forever's own interface:
- Queb's icon is a spider web with one circle per class color, painted in the style of WoW's web icons. It fills the round portrait of the Queb window and shows in the AddOns list and the AddOns options page (`Media/Icon.tga`, 128 × 128).
- The circles use Blizzard's round texture, shaded like the class-colored party dots on the minimap. The gold "ready to turn in" ring is the only custom art; it's tinted Blizzard gold.
- The Queb window uses Blizzard's standard window (your portrait, title bar, close button, inset list with a Blizzard scroll bar), class icons and Blizzard buttons. Escape closes it, it plays the normal open/close sounds, and it remembers where you drag it.
- Tooltips use Blizzard's colors: gold headers, white text, green for done, gray for unknown.
- Chat messages look like system messages, with a short "Queb:" prefix.
- If a Blizzard asset is missing on your build, Queb falls back to the nearest one. `/queb probe` reports what it found (the "Look:" line).

## Install
1. Copy the `Queb` folder to `World of Warcraft\_forever_\Interface\AddOns\`.
   **Copy the folder; don't symlink it.** On Forever, a symlinked addon folder silently resets its SavedVariables.
2. Restart the game, or `/reload` if it's already running, and enable the addon on the character screen.
3. The TOC says `## Interface: 16001`. If the addon shows as out of date, check the real number with
   `/run print(select(4, GetBuildInfo()))` and update the TOC line.

## First in-game test (solo)
1. Pick up a few quests.
2. Type `/queb`, open the Settings tab and tick **Demo guildmates**. This adds 1 to 7 fake guildmates to your first quests. Check the quest log, the tracker and the Quebmates tab (demo guildmates have roles too). Tick a role next to the tabs, and drag the corner to resize. Invite stays disabled for the fake guildmates.
3. Open Esc → Options → AddOns → Queb and check that the same window appears there.
4. `/queb probe` reports which Blizzard frames, hooks and assets were found on this build, plus sync stats and known Queb users. Paste the output back into the project.
5. Untick **Demo guildmates** to turn the demo off. (The demo always starts off after a reload.)

## With guildmates
- Each guildmate needs the addon installed. Sync starts at login, and quest changes are sent within about 5 seconds.
- `/queb probe` lists who the addon has heard from. Settings → **Resync** forces a re-announce.

## Commands
- `/queb` opens or closes the Queb window. Everything else is in its Settings tab.
- `/queb probe` is a developer report for testing (frames, hooks, assets, sync stats, known users).

Default settings: guild sync on, party sync off, faded circles for grouped players without the addon on, circles in both the quest list and the tracker, and at most 5 circles before the rest collapse into "+N".

## How it works
| File | Role |
|---|---|
| `Util.lua` | Helpers: secret-value guard, timers, hashing, name handling, quest entry wire format |
| `Core.lua` | Event frame, internal message bus, SavedVariables (`QuebDB`) |
| `QuestState.lua` | Snapshot of your quest log (questID → completion + objective counts) with a state hash |
| `Peers.lua` | Known addon users, guild roster (class + online), `GetSharers(questID)`, demo mode |
| `Commands.lua` | `/queb` and the hidden `/queb probe` report |
| `Comm.lua` | Versioned, chunked, throttled addon messages on the `GUILD` channel (and optionally party). Resyncs after sending is blocked |
| `UI_Common.lua` | Class-colored dot widget, tooltip, coalesced refresh |
| `UI_QuestLog.lua` | Dots in the quest list (Modern `QuestMapFrame`, Classic `QuestLogFrame`) |
| `UI_Tracker.lua` | Dots in the tracker (Modern `ObjectiveTrackerFrame`, Classic `QuestWatchFrame`) |
| `UI_Tooltip.lua` | Post-hooks `GameTooltip:Show` and adds circles and progress lines when the tooltip belongs to the world map, quest log or tracker |
| `UI_Ellesmere.lua` | EllesmereUI Quest Tracker support: registers through `EllesmereUI.RegisterQuestTrackerRow` and refreshes with `EllesmereUI.RefreshQuestTrackerRows` |
| `UI_Guild.lua` | Guild member tooltips: Modern `CommunitiesFrame` member list (load-on-demand, ScrollBox rows) and Classic `GuildFrame` rows |
| `Options.lua` | Settings tab: Blizzard checkboxes, sliders and buttons for every option, through one setter (`ns.Options:Set`) |
| `Roles.lua` | Your roles (`QuebDB.roles`), class limits, role encoding for messages, Blizzard role icons, the role picker |
| `Buddies.lua` | Login summary; the Queb panel (Quebmates + Settings tabs, role picker) built in the resizable `/queb` window and in Esc → Options → AddOns; Invite (`C_PartyInfo.InviteUnit`) |
| `API.lua` | `Queb.GetSharers(questID)` and `RegisterCallback`, for other trackers |

Protocol messages:
- `HI`: presence and heartbeat, sent every 5 minutes.
- `RQ`: request a peer's state.
- `ST`: full state.
- `QU`: changed quests only.

Each message carries a hash of the sender's quest state. If a receiver's copy no longer matches that hash, it asks for the full state again, so missed messages fix themselves.

Taint safety: the addon only uses post-hooks (`hooksecurefunc` and `HookScript`) and only creates frames it owns. It never writes fields onto Blizzard frames, and every refresh is deferred and coalesced.

## Needs in-game verification
- Frame and method names in both UI presets (run `/queb probe`).
- The Queb page in Esc → Options → AddOns (registered with Blizzard's `Settings` API).
- Where the dots sit after each title. They should never overlap Blizzard icons; check rows with long titles.
- Map tooltips: with Settings → **Debug messages** on, the first time you hover over each map area or marker, chat prints which quest it detected. If an area shows no circles, paste that line here.
- The format of sender names in addon messages (Debug messages prints the first one received).
- Whether guild addon messages work on Forever, and what happens to them inside instances.
