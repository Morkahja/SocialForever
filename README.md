# Social Forever

**Social Forever remembers the people you meet while playing World of Warcraft: Forever.**

While you quest, the same players often cross your path again and again. Social Forever keeps a small list of those people above your chat so they are easier to recognize, target, invite, and remember the next time you meet.

Over time, strangers can become familiar names.

Built by **Babunigaming** for **World of Warcraft: Forever** (Interface 16001).  
Current version: **0.2.25**

## What it does

Social Forever keeps track of players you encounter and gives you a simple social history for them.

You can:

- See recently encountered players in a small movable window.
- Click a name to target that player.
- Invite them directly from the list.
- See how often you have encountered them before.
- See where you have met them in the past.
- Mark players as **Green**, **Yellow**, or **Red** based on your experience with them.
- Add flags such as **Really friendly**, **Generous**, **Weird**, or **Bad behavior**.
- Create your own custom flags.
- Mark someone as **Kill on sight**.
- Rate party members after a group ends.
- Exchange marks and flags with nearby players who also use Social Forever.

Your social memory is stored account-wide in `SocialForeverDB`.

## The player list

The window is split into two kinds of players.

### Nearby

Players the addon has recently detected around you appear at the top.

A nearby player normally remains on the list for **3 minutes** after the last sighting. Seeing them again refreshes that timer.

Out in the world, moving into another subzone removes players from the previous subzone immediately. Capital cities are treated as one larger place, so walking between areas of Ironforge or Stormwind does not clear everyone from the list.

Party members remain visible until they leave the group.

### In this zone

Players who speak in **General** chat appear under the nearby players while they are still in your zone.

They remain there for **10 minutes** after speaking.

A player who is already in the Nearby section is not shown twice.

When you change to another main zone, players left over from the previous zone are cleared after about **30 seconds**.

## How players are ordered

The list tries to keep the most relevant people near the top.

It prioritizes:

1. Players in your current zone and area.
2. Players marked **Kill on sight** within their section.
3. People you have encountered more often.
4. Players seen more recently.

The order refreshes every few seconds rather than constantly jumping around.

New names fade in, departing names fade out, and names that change position briefly fade before moving.

## Targeting and inviting

Click a nearby player's name to try to target them.

If the target does not resolve to that player, Social Forever removes them from the nearby list rather than pretending they are still there.

Your current target is highlighted with a gold frame.

The button beside a player can show:

| Button | Meaning |
| --- | --- |
| **Invite** | Ready to invite them. |
| **Invited** | An invitation has been sent. |
| **Declined** | They declined. You can click again to invite them once more. |

The invite button disappears while that player is already in your group and returns after they leave.

## Familiar faces

Social Forever remembers how often you encounter each player.

Names gradually change color based on how familiar that person is compared with the player you have encountered most often:

| Color | Familiarity |
| --- | --- |
| **White** | First encounter, or up to 30% of your highest count |
| **Blue** | 31% to 80% |
| **Purple** | 81% to 100% |

A Green, Yellow, Red, or Kill on Sight mark overrides this familiarity color.

Hover over a player to see more of their history, including:

- When they were last seen.
- The subzone where they were last seen.
- Other zones or dungeons where you have encountered them.
- How many times they have been nearby.
- How many times they have appeared in the same zone.
- Your mark and the shared mark.
- Any flags attached to them.

Their level appears once WoW has actually reported it through your target, mouseover, or group. A chat message by itself does not reveal a player's level.

## Marks, flags, and Kill on Sight

Right-click a player to add your own impression of them.

### Marks

- **Green** — someone you would happily group with again.
- **Yellow** — neutral.
- **Red** — someone you had a bad experience with.

### Flags

The built-in flags are:

- Really friendly
- Generous
- Weird
- Bad behavior

You can also create your own custom flags.

### Kill on Sight

**Kill on sight** is a personal flag. It is never shared with other Social Forever users.

## Rating a group

When a party ends, or when someone leaves your party, Social Forever can ask:

**How was this group?**

Each player can be rated:

- **Again**
- **Okay**
- **Bad**

These become Green, Yellow, and Red marks.

Converting the group into a raid does not open the rating window.

## Shared marks

If another nearby player is also using Social Forever, the two addons can quietly exchange marks and flags through WoW's addon-message system.

Nothing is printed in normal chat.

Shared marks use a simple score:

- Green = +1
- Yellow = 0
- Red = -1

Your own mark is included in the result. The tooltip shows how many good, okay, and bad marks contributed to the shared impression.

Some information always stays personal and is never shared:

- How often you have seen someone.
- Kill on sight.
- How many times you have grouped with someone.

Two-word character names are not contacted through the hidden addon whisper because this client can incorrectly report those players as offline even while they are standing nearby.

## How "nearby" works

Social Forever does **not** scan every player within a fixed radius. WoW does not give addons a simple list of everyone standing around you.

Instead, Social Forever builds the nearby list from players the game has already exposed through things such as:

- Your target, mouseover, focus, or soft target.
- Friendly nameplates, if you have turned them on yourself (Shift+V). Social Forever never changes that setting.
- Someone who buffs you, when Forever still exposes the caster.
- A resurrection cast on you.
- Other players who showed up in the damage meter after a fight ends.
- Party and raid members who are actually within range.
- Say, emotes, craft lines, duel, and trade.

**In this zone** is broader and weaker. It includes people who speak in General, people currently on the General channel roster, and yell. Being on that roster alone does not count as an encounter or raise familiarity.

Because of that, a silent player standing beside you may not appear immediately if the game has not exposed them to the addon yet.

Social Forever does not enable nameplates or use `/who` to build the list. The combat log event stream is not used.

## Window and settings

The window normally sits above the chat frame.

- The close **x** sits in the top-left corner, away from the gear button.
- Hover the **x** for a reminder that `/sf` or `/socialforever` brings the window back.
- Drag the title bar to move it.
- Drag the `..` grip in the bottom-right corner to resize it.
- Use the gear button to change the name size, background opacity, and friend auto-invite setting.
- Use the mouse wheel to scroll longer lists.
- Press Escape to close the right-click menu or group-rating window. The main Social Forever window stays open.

Use:

```text
/sf
```

or

```text
/socialforever
```

to show or hide the window. The addon-compartment button does the same.

## Installation

Copy the `SocialForever` folder into:

```text
Interface/AddOns/SocialForever
```

Then reload the game:

```text
/reload
```

## Development

The version-by-version development history is in [DEVELOPMENT.md](DEVELOPMENT.md).
