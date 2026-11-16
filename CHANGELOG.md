# Changelog

## 0.14.2 (2026-11-16)
- Map quest tooltips no longer visibly rebuild: Blizzard builds them over a few frames, so Queb's lines flashed under the title and then jumped to the bottom. The tooltip now stays hidden until it's finished (a couple of frames, at most 0.3 s) and appears complete. Also applies to OpenMap player markers.
- Dungeons section: DungeonJournal's quest-chain pages (Cozy Sleeping Bag, Onyxia Attunement, Mallet of Zul'Farrak) are no longer listed as dungeons.
- Dungeons tooltips: clearer words: "on quest", "available" (was "can pick up" / "to pick up"), "need pre-quest" and "level too low" counted separately (were lumped as "not yet").
- Shift-click a dungeon title now tells your group (party, raid or instance chat) which of its quests you're on, then which you still need, as clickable quest links (plain titles if the list is long; at most 3 lines each). Done quests and quests not for your class are left out. Not grouped: "Not in a party".
- The green "share" text on dungeon quest rows is now a real **Share** button (clicking the rest of the row no longer shares).

## 0.14.1 (2026-11-16)
- Smoother circles everywhere (quest log, trackers, tooltips, Dungeons section, DungeonJournal rows): new anti-aliased `Dot`, `Ring` and `Check` textures made for small sizes, the dark rim built into the dot (no separate shadow layer to drift), pixel snapping off. Replaces Blizzard's round mask, which looked crunchy when shrunk. Dots are 12 px with a 1 px gap.
- New: a circle with a **green check** in the middle = that player has turned the quest in. Shown on quest rows, in quest tooltips ("Done") and in the Dungeons section (replaces the plain check there). Known from the dungeon quest answers (DQ/DA).
- Demo guildmates include a "done" example. `/queb probe` "Look:" line reports the smoothing support.

## 0.14.0 (2026-11-16)
- New **Dungeons** section in the Quebmates tab: one collapsible block per dungeon (the dungeon name is the title), a column per person (you, group members, guildmates with Queb near the dungeon's level) and a row per quest showing who is on it, ready, done, can pick it up, needs a pre-quest or a higher level, or can't take it. Hover for details; click a quest to share it; Shift-click a dungeon to put its quest names into chat.
- Quest lists come from DungeonJournal when installed, else from Questie's database.
- "Done" / "can pick up" are asked from each player's Queb (new `DQ`/`DA` messages; older builds ignore them and show "update Queb").
- Circles on DungeonJournal's quest rows, right after the quest name, with the usual tooltip. Follows Settings → Quest log.
- New settings: Sharing → Dungeon quests; Quebmates → Dungeons: group, Dungeons: guild (all on).
- `/queb probe` adds a "Dungeons:" line.

## 0.13.0 (2026-11-15)
- "Can share" now checks quest prerequisites (earlier quests in the chain, class, race, reputation, breadcrumbs) with Questie's quest database. No Questie, or a quest Questie doesn't know: no "!" (Queb never guesses).
- When the game refuses a share ("not eligible", "already done", …), the sharer's Queb tells the other player's Queb, and the "!" for that quest stays hidden for them until they level up. The sharer stops seeing them in "Can share with:".
- "Can share with:" only lists players on Queb 0.13.0 or newer (older builds didn't check prerequisites).
- `/queb probe` adds a "Prereqs:" line (Questie found, checks, refusals, share hook).

## 0.12.2 (2026-11-15)
- `/q` works the same as `/queb`. `/queb probe` reports if another addon also uses `/q`.

## 0.12.1 (2026-11-15)
- Circles are solid class color again (dark rim, no highlight). The v0.8.4 removal had been lost in a merge.

## 0.12.0 (2026-11-15)
- Circles on Questie's quest tracker, right after each quest title (in the space Questie keeps at its right edge). Questie's tracker tooltip gets the "Also on this quest" lines. Setting: Objective tracker.
- Blizzard tracker: if a quest block has no `HeaderText` (possible on Forever), Queb now finds the title the way EllesmereUI does (first text region) instead of drawing nothing.
- `/queb probe` shows how many tracker quests Queb found and how many got circles, for Blizzard's and Questie's trackers.

## 0.11.0 (2026-11-15)
- "Queb: Quest completed: [quest]" in party chat when you turn in a quest, like Questie's announcement. Only when Questie isn't loaded; party only (not raids or instances); once per quest. Setting: Settings → Sharing → Announce in party (grayed out, marked "(Questie)", while Questie is loaded).

## 0.10.0 (2026-11-15)
- Party and raid members who aren't in your guild: party sync is now on by default (existing installs switched on once), so any Queb user in your group gets circles, progress, "Can share" and a Quebmates row.
- Player tooltips: hover a group member (unit frames, raid frames, nameplates, world) or a known Queb user to see shared quests. Setting: Player tooltips.
- Quest mob tooltips: hovering a mob/NPC tied to your quest names who else is on it. Setting: Quest mob tooltips.
- Quest tooltips say "Also on this quest" (was "Guildmates on this quest").
- Fix: a non-guild group member without Queb could read "offline" in tooltips.

## 0.9.2 (2026-11-15)
- Role picker shows only the roles your class can play (no grayed-out checkboxes).

## 0.9.1 (2026-11-15)
- Window can be made much shorter (min height 220 instead of 420); the Settings tab scrolls when it doesn't fit.
- Resizing keeps the window's top edge in place.

## 0.9.0 (2026-11-15)
- "Buddies" is now "Quebmates" (tab, chat, settings).
- Role picker next to the tabs: Tank / Healer / Damage, any combination, limited by class. Shared with other Queb users (HI field 5, "@" part in ST; older builds ignore both).
- Role icons next to each name in the Quebmates list (group role for members without Queb).
- The Queb window is resizable (corner grabber); size is remembered.

## 0.8.4 (2026-11-15)
- Plain row circles: dark rim + solid class color (highlight removed).

## 0.8.3 (2026-11-15)
- "Can share": yellow "!" for quests a guildmate can share with you (Buddies, login summary, guild and OpenMap tooltips) and "Can share with:" on your own quest tooltips. New WT message, backward compatible. Setting: Settings → Buddies → Can share.

## 0.8.2 (2026-11-15)
- Custom Queb icon (web with 9 class-colored circles): window portrait, AddOns list, options page.

## 0.8.1
- Queb lines on OpenMap player markers and zone badges.

## 0.8.0
- `/queb` opens the main window (Buddies + Settings tabs); same panel in Esc → Options → AddOns.

## 0.7.x
- Native Blizzard look pass; short-phrase text; unknown status shows only the reason.

## 0.6.0
- Renamed from Team Up Forever to Queb.

## 0.1 – 0.5
- Guild quest sharing protocol, row circles, login summary, Buddies window, quest/guild tooltips, EllesmereUI Quest Tracker support.
