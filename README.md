# Social Forever

When you quest, the same people keep walking past you. Social Forever keeps a short list of them above your chat, so you can invite someone without digging through whispers and General.

People standing near you sit at the top. Anyone who has spoken in General shows up under that, while they are still in the zone. Click a name to target them, or use the invite button beside the row. Right-click when a group was good or bad, and the next time you meet that person the memory is still there.

Built by **Babunigaming** for World of Warcraft: Forever (Interface 16001). Current version **0.2.20**.

The window sits above the chat frame. Nameplates stay off.

## Install

Copy the `SocialForever` folder into:

```text
Interface/AddOns/SocialForever
```

Then type `/reload`.

`/sf` or `/socialforever` shows and hides the window. The addon compartment button does the same.

## The list

The title is the place you are standing in, plus how many people are nearby. In Ironforge that looks like **The Great Forge (4)**. In a capital city the title still uses the subzone, but the whole city counts as one place for memory.

| | |
| --- | --- |
| Nearby | Stays for 3 minutes while you remain in the same subzone. Out in the world, a different subzone removes them right away. A capital city counts as one place. Group members stay until they leave the group. A new name fades in from nothing. A name that changes place fades to half, moves, then fades back. Only a name that changes place does this. A name that leaves fades out over three seconds and is gone at the end. |
| In this zone | Stays for 10 minutes after speaking in General. Someone already nearby is not repeated here. |
| New zone | 30 seconds after you change zone, names from the previous zone are removed. |
| Order | This zone first, then how often you have seen them, then who has more time left. The order refreshes every 3 seconds. |
| Kill on sight | Stays at the top of that group. |

Names use the same lettering as the rest of the game, so a Chinese name shows as characters rather than empty boxes. A click on a name tries to target them. If that target does not land, they leave the nearby list. The row you currently have targeted keeps a gold frame and background, so it stays visible after the mouse leaves. The button on the right runs `/invite` with the full name.

| Button | Meaning |
| --- | --- |
| Invite | Ready to invite. |
| Invited | The invite was sent. |
| Declined | They declined. Click again to ask once more. |

The button hides while that player is in your group, and it returns to **Invite** after they leave.

## Names

The level appears beside the name once the game has reported it, from your target, your mouseover, or your group. A chat line alone does not include a level.

Name color shows how often you have seen that person, compared with the person you have seen the most:

| Color | How often |
| --- | --- |
| White | First time, or 30% or less of your highest |
| Blue | 31% to 80% |
| Purple | 81% to 100% |

A green, yellow, or red mark replaces that color. Kill on sight uses its own red.

The tooltip says when they were last seen, in whole minutes, and the subzone, such as **Last seen 1 minute ago in Astranaar**. Under that, **Seen before in Ashenvale, Darnassus** lists the zones and dungeons where you have met them. It also shows how many times they have been nearby, how many times they have been in the same zone, your mark, the shared mark, and any flags.

## Marks, flags, and kill on sight

Right-click a name.

- **Green** means group again. **Yellow** is neutral. **Red** is unpleasant.
- Flags start with Really friendly, Generous, Weird, and Bad behavior. The box at the bottom adds a flag of your own.
- **Kill on sight** is personal. It is not shared with other players.

After a group ends, or when someone leaves your party, a small window asks how it was: **Again**, **Okay**, or **Bad**. That sets the mark. A raid conversion does not open it.

## Shared marks

If someone else nearby is also running Social Forever, the two copies can exchange marks and flags through a hidden addon whisper. Nothing is printed in chat. A two-word name is not whispered, because that lookup tells you the player is not online even when they are standing in front of you.

Green counts as +1, yellow as 0, and red as −1. Your mark is included. The tooltip shows how many good, okay, and bad marks made the general color.

These stay on your account only:

- How often you have seen someone
- Kill on sight
- How many times you have grouped with them

Memory is account-wide, in `SocialForeverDB`.

## Window

Drag the title bar to move it. Drag the `..` grip at the bottom-right to resize it. The gear sets the name size (16, 18, or 20) and the background opacity. The border stays solid. Escape closes the right-click menu and the rating window. The main list stays open.

## Development

The step-by-step history is in [DEVELOPMENT.md](DEVELOPMENT.md).
