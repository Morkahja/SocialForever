# Development log

Social Forever, by Babunigaming. Newest step first.

When a change ships, add it at the top. Keep the note about what the player can see, and why it was made.

## 0.4.1 — Tabs, same-mob grouping, Nearby-only memory

- List split into Nearby (area/subzone tab) and Zone (General roster tab); zone list shows up to 100 with `100+` when full.
- Subzone purge delayed 15s; combat list display + click shield retained.
- `sameMobAsk` / `sameMobAutoInvite` (default off, mutually exclusive). After regen + meter settle, DamageDone spell target details find shared mob names; ask popup or `C_PartyInfo.InviteUnit` / fallback secure Invite; 5-minute per-player cooldown.
- Familiarity and place history only from Nearby; zoneTimes counter and tooltip line removed.

## 0.3.2 — Immediate mark paint while frozen

- `UI.PaintRowAppearance(key)` refreshes mark letter/colors (and invite block) for one row without reordering; called from SetColor / ToggleKos / flags after RefreshList.
- Leaving the list always force-rebuilds once so deferred detection/sort catch up; mark/KOS invalidates the 3s stable-sort hold; menu hide re-checks freeze; mid-paint RefreshList sets listDirty instead of dropping the update.

## 0.3.1 — List stability + target priority

- Current player target (if present in Nearby) is pinned to the first Nearby row; pin updates on `PLAYER_TARGET_CHANGED` via existing Scan/Publish and forces a resort when the pin changes so the 3s stable-hold cannot bury them.
- Hovering the list container, rows, Invite buttons, or scrollbar sets `S.listFrozen`; `UI.RefreshList` then marks `S.listDirty` and only refreshes target chrome. Detection keeps running underneath.
- On mouse leave of the whole interactive area, one rebuild applies (`skipMove`) with current sort + pin. Scroll/resize while frozen repaints from `S.displayOrdered` without adopting live additions/removals.

## 0.3.0 — Multi-file split

- Split the former single `SocialForever.lua` into load-ordered modules: `Core`, `Memory`, `Group`, `Detection`, `Sharing`, `UI`, `Events`.
- Shared namespace is `SocialForever` (`SF`), with `SF.Const`, `SF.State` (including former `P` as `SF.State.P`), `SF.Util`, and per-module tables. `SocialForeverDB` schema unchanged.
- No player-facing behavior change intended; slash commands and the addon compartment still enter through `Events.lua`.
- Pushed to GitHub without a release tag so CurseForge does not pick this build up.

## 0.2.32 — Nearby presence validation

- Every 5 seconds, only the current Nearby set is checked against live unit tokens (target, mouseover, soft targets, party/raid, nameplates, and the usual chains).
- A real distance over 50 yards removes them immediately. No matching token starts a short unconfirmed window (about 18s for trackable sources, 25s for interaction sources), then they leave Nearby.
- Missing a token is not treated as proof they left. Group members are not aged out while still grouped. Nameplate remove accelerates the stale timer without an instant drop.
- The 3-minute TTL remains the final fallback.

## 0.2.31 — Plumbing optimization pass

- The 0.5s unit scan still runs, but the list only rebuilds when the displayed nearby/zone set, group status, or current target actually changes. Quiet TTL refreshes no longer repaint.
- Fade/move OnUpdate is armed only while an animation is active, then cleared.
- Familiarity maximum is cached and updated when nearby/zone counts rise, instead of walking the whole saved DB every refresh.
- Damage meter harvests once per finished combat (debounced), current session only, GUID-deduped.
- General roster events debounce to one scan; the safety refresh is every 60s. Login still loads the roster promptly.
- Combat-log chat polling only Publishes when it finds a new player link.
- Raid members/targets scan on a 3s ticker that exists only while you are in a raid. Group membership is a cached lookup for party and raid, so Invite hides for raid mates too.

## 0.2.30 — General roster reader fixed again

- You were right: after 0.2.29 it still only showed talkers.
- Modern roster info returns `name, owner, moderator, guid`, not an 8th-slot GUID. The code was dropping GUIDs and often querying with the chat channel number instead of the ChannelFrame display index.
- It now tries the display index and the channel number, uses the listed member count from the channel UI, and only selects General when the roster is empty so the client fills it.

## 0.2.29 — General roster actually loads

- **In this zone** was meant to list people on the General channel roster, not only people who talk.
- Finding General used the wrong return from the channel API, so the roster never loaded. Speaking in General still worked.
- General is found through the joined-channel list, then the display list, and the roster refreshes more often.

## 0.2.28 — Other faction reads dusty red

- Opposite-faction names use a muted dusty war-red so they stand out from your own side.
- That color is not the bright Red mark. Green, Yellow, Red, and Kill on Sight marks still win when set.
- Faction comes from the unit when seen; race fills it in for the classic races. Skyborne can be either side, so they need a real faction read.

## 0.2.27 — No offline echoes on Nearby

- Offline party or raid members were still treated as grouped, so Nearby kept refreshing their timer and never let them expire.
- The damage meter also walked older combat sessions, and GUID name lookup works for offline characters, so yesterday's groupmate could be re-added after every fight.
- Offline group members are dropped. Meter and GUID paths only count players the client still has as a live connected unit. Old stored meter sessions are ignored.

## 0.2.26 — Race, class, and level on the list

- The level sits to the right of the name in class color, instead of being glued onto the name text.
- Between the name and the level is one icon chosen for that race and class together, including Skyborne.
- Race and class are remembered when the client exposes them, so the icon can still show later from GUID or unit data.

## 0.2.25 — More ways to notice people

- Friendly nameplates you turn on yourself can feed Nearby. Social Forever never flips that setting.
- A player who buffs you, or resurrects you, can appear Nearby when Forever still exposes the caster.
- After combat ends, other players from the damage meter can appear Nearby when that data is readable.
- The General channel roster and yell fill **In this zone** only. They do not raise familiarity.
- Raid members in range and a few more unit tokens are scanned. Secret values are skipped, not forced.

## 0.2.24 — You are not nearby

- Your own name could show in the list when one path stored it with a space and another with a hyphen. Those forms are treated as the same person, and you stay off the list.

## 0.2.23 — No false “not playing” for two-word names

- Hello whispers were still going out for hyphenated two-word names such as `Lyrianda-Nik`. The client looks that up as a spaced name and prints that nobody is playing.
- Two-word names are not whispered. One-word names still exchange marks as before.

## 0.2.22 — Sealed names in a dungeon

- In a dungeon while grouped, reading a sealed unit name could error when the list refreshed. Those names are skipped instead of compared.

## 0.2.21 — Close sits on the left

- The close **x** is in the top-left corner, so it is harder to hit by mistake when using the gear.
- Hovering the **x** shows how to open the window again with `/sf` or `/socialforever`.

## 0.2.20 — Fade, then move, then fade back

- A name that is about to change place fades to half opacity while it is still in the old place. It moves at half opacity, then fades back to full in the new place.
- Names that are not changing place stay as they are.
- That fade takes twice as long as before.

## 0.2.19 — Three minutes, and a short history

- Nearby names stay for 3 minutes. The time on the tooltip is in whole minutes: just now, 1 minute ago, 2 minutes ago.
- Last seen includes the subzone, such as **Last seen 1 minute ago in Astranaar**.
- **Seen before in Ashenvale, Darnassus** lists the zones and dungeons where you have met them. A dungeon is stored by its dungeon name.
- The tooltip no longer explains the target click.
- If a click does not target that person, they leave the nearby list.

## 0.2.18 — Slower fades, and a dip when a name moves

- A new name fades in from invisible. It no longer pops in at full strength and then fades.
- When the sort moves a name, that row dips to half opacity and comes back in the new place.
- A name that leaves fades out over three seconds. At zero opacity it is removed, instead of the old fast pulse.

## 0.2.17 — Chinese names are readable

- A Chinese name was already on the list, but the letters drew as empty boxes. The list had switched to a Latin-only font. The portrait still used the game font, which has those characters.
- The name line now keeps the game font, including Chinese and other scripts. The 16, 18, and 20 size choices still apply.

## 0.2.16 — The window loads again

- 0.2.15 never started. Lua stopped the file while it was loading, so the list, the gold target frame, and the fades from that build never appeared.
- 0.2.16 loads. The target row still keeps its gold frame and warm background.

## 0.2.15 — The current target stays marked

- The row for your current target keeps a gold frame and a warm background after the mouse leaves, so you can see who you have targeted.

## 0.2.14 — Fade in, pulse, fade out

- A name fades in when it joins the list.
- A name that leaves pulses in opacity, then fades out, instead of vanishing in one step.

## 0.2.13 — Only the current subzone outdoors

- Out in the world, a nearby name from another subzone is removed as soon as you leave that subzone, even if time is left on the timer. The list stays the people around you.
- Inside a capital city the whole city is still one place, so the bank and the auction house do not clear each other.
- Group members stay with you.
- The tooltip says **In this subzone, Goldshire** when it matches, or **Met in Northshire** when the stored place is somewhere else. In a city it says **In this city**.

## 0.2.12 — No false “not playing” message

- Mousing over a two-word name was sending a hidden addon whisper to that name, such as `Statefarm Dotcom`. The client looks that whisper target up and prints that nobody by that name is playing, even when they are online.
- Those whispers are skipped. There is no `/who`. One-word names still exchange marks as before.

## 0.2.11 — Tooltip follows the list

- The hover tooltip closes when its row leaves the list, including when a zone change clears the window. It no longer stays stuck on screen.
- The tooltip keeps **Last seen** and no longer shows when the name drops off.

## 0.2.10 — Timers, and leaving the last zone behind

- The tooltip shows how long ago a name was last seen, and how long until it drops off the list. Group members say they stay while they are in the group.
- The list sorts by this zone first, then by how often you have seen them, then by who has more time left. A familiar name from another zone no longer sits above the people who are actually here.
- 30 seconds after the main zone changes, names still tagged with the previous zone are removed. Anyone seen again in the new zone keeps their place. Booty Bay no longer inherits a city full of people from the zone you just left.

## Docs — README and this log

- `README.md` is the player-facing page for GitHub: install, the list, invites, colors, marks, and how shared marks work.
- This file is the running history. New steps go at the top while development continues.

## 0.2.9 — Level, and a calmer memory of places

- The level sits beside the name once the game has reported it.
- A nearby count is stored with the place you met that person. Coming back in that same place does not add another count. A different place does, and only when they enter the list again.
- Ironforge, Stormwind, Darnassus, Orgrimmar, Thunder Bluff, Undercity, the Exodar, Silvermoon City, Shattrath City, and Dalaran each count as one place. Their subzones do not add extra meetings.
- Out in the world, the subzone is the place.
- People still on the timer from another subzone drop under the people in the subzone you are standing in, so clicking down the list starts with who is actually there.
- Group members keep the place you are in now, so they stay with the top of the list while you travel together.

## 0.2.8 — Longer nearby memory, and the place in the title

- Nearby names stay for five minutes. Activity starts that time over.
- The title shows the current subzone, then the nearby count, such as `The Great Forge (4)`.
- The first version of the place rule treated a subzone change as a brand-new meeting. 0.2.9 replaced that with a remembered place.

## 0.2.7 — Marks and flags only

- Ignore, Add to Friends, and the star row left the right-click menu.
- The menu is the mark, the flags, a box for a flag of your own, and kill on sight.

## 0.2.6 — Ignore crash, and a friend button that could not run

- Ignore crashed because it called `Touch` before that function existed.
- Add to Friends was calling a protected friend API from the menu, so the click did nothing. A secure `/friend` button was tried here, then both actions were removed in 0.2.7.

## 0.2.5 — A calmer list, and an invite button that is separate from the name

- The order of the list refreshes every 3 seconds. New people still appear immediately.
- The right-click menu stays open until the mouse button is released. A click outside closes it after that.
- The invite control sits beside the name. It reads Invite, Invited, or Declined.
- The invite uses the full name, such as `/invite Chad Thorne`.
- Leaving the group puts a stuck Invited button back to Invite.

## 0.2.4 — How often you have seen someone

- A person is counted once each time they enter a list, not on every refresh while they remain.
- The tooltip shows **Been nearby** and **Been in the same zone**.
- Nearby hold was one minute in this version, and group members stayed on the list.
- Names go white, blue, then purple against the person you have seen the most.
- A mark or kill on sight still uses its own color.
- People you have seen more often sit higher. The rating window also opens when one player leaves the group.

## 0.2.3 — Invite click no longer fights the name

- The invite button is a sibling of the name row, so the two clicks do not share one secure button.
- Both clicks run on mouse down. Invited paints immediately, with no timer in between.
- The tooltips show the exact `/target` and `/invite` lines.

## 0.2.2 — Targeting from the list

- Name rows are secure buttons on a plain list, with a scroll offset. They are not inside a scroll frame, which was swallowing the click.
- Left-click runs `/target` with the first name.
- Secure buttons are left untouched while you are in combat, so the list freezes instead of erroring.

## 0.2.1 — The window, the zone, and who stays visible

- Nearby players are the top section. People who speak in General are **In this zone**, for 10 minutes.
- The gear replaces the old font toggle. It sets auto-invite, name size (16, 18, or 20), and background opacity.
- The window can be resized from the bottom-right grip. Size and place are saved.
- Two-word names display with a space. Slash commands use the spoken name.
- Kill on sight sorts to the top of a section and shows a red K when there is no other mark.
- Ignore, at this point, kept the player on the list with a red mark and an Ignored flag, sorted last. That menu row was removed in 0.2.7.
- Mobs are kept out. A two-word name is taken from a crafting line, not from combat prose.
- Distance sorts closest-first when the game reports a real distance.

## 0.2.0 — First playable list

- A small window above the chat frame lists nearby players.
- Green, yellow, and red marks, flags, and a custom flag.
- After a party ends, up to four people can be rated Again, Okay, or Bad.
- Other copies of the addon can whisper marks and flags. Green is +1, yellow is 0, red is −1.
- Memory is account-wide in `SocialForeverDB`.
- Nameplates were tried and removed. Sightings come from speech, emotes, crafting, the cursor, and units the game is already tracking.
- Background friend invites were removed from the ticker. This client blocks an invite that is not a real button click.
