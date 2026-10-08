# Social Forever — Changelog

## 0.4.1 — 2026-10-08

- Nearby and zone people are on separate tabs. The nearby tab uses your subzone name; the zone tab uses the zone name (and can show 100+).
- After you change subzone, names stay on Nearby for at least 15 seconds so the list does not jump as much.
- Optional same-mob grouping: ask before inviting, or auto-invite, when someone nearby was damaging the same mob you were. Both settings default off.
- Mouseovers and other sightings can show on the list during combat; brand-new rows stay click-safe until combat ends.
- Memory is Nearby-only: “Been nearby” counts real Nearby encounters, and “Seen before in …” only updates when they have been Nearby. The old same-zone times line is gone.

## 0.3.2 — 2026-10-07

- Marks, clear mark, and Kill on sight update that player's color and letter on the list right away, even while your mouse is over it.
- After you leave the list, sorting and normal updates continue as usual.

## 0.3.1 — 2026-10-07

- Your current target stays at the top of Nearby while you have them targeted.
- The Nearby list no longer jumps around while your mouse is over it — invites and clicks stay on the same person until you move away.
- Player tooltips show level, race, and class.

## 0.3.0 — 2026-10-07

- Same player-facing behavior. The addon code is now split into several Lua files so it is easier to maintain.

## 0.2.32 — 2026-10-07

- Nearby drops people sooner when they are clearly gone or stop showing up for a short while. The 3-minute timer is still the last resort.

## 0.2.31 — 2026-10-07

- Same detection and list behavior, with less repeated background work while you play.

## 0.2.30 — 2026-10-07

- **In this zone** from the General roster should work without people talking. The roster reader was still using the wrong channel id and GUID fields.

## 0.2.29 — 2026-10-06

- **In this zone** now fills from the General channel roster again, without waiting for someone to speak.

## 0.2.28 — 2026-10-06

- Players of the other faction show in a dusty war-red on the list, different from a Red mark.

## 0.2.27 — 2026-10-06

- Offline group members and old damage-meter names no longer keep showing up on Nearby.

## 0.2.26 — 2026-10-06

- Each nearby name now shows a race-and-class icon between the name and the level.
- The level uses that player's class color. Skyborne have their own icon set.

## 0.2.25 — 2026-10-06

- More ways to notice people nearby: friendly nameplates you already enabled, players who buff you, resurrections, and other combat participants after a fight ends.
- The General channel roster and yell now feed **In this zone** without counting as a real encounter.
- Raid members in range and a few extra unit tokens are scanned the same way as party targets.

## 0.2.24 — 2026-10-06

- Your own character no longer appears in the nearby list.

## 0.2.23 — 2026-10-05

- Two-word names no longer trigger “No player named … is currently playing” when Social Forever tries to say hello. Those names are not whispered.

## 0.2.22 — 2026-10-05

- Fixed a Lua error that could fire in a dungeon while in a group, when the client sealed a unit name.

## 0.2.21 — 2026-10-05

- First CurseForge beta.
- The close **x** sits in the top-left corner, away from the gear button.
- Hovering the **x** shows that `/sf` or `/socialforever` brings the window back.
