# Achievements and unlockable app icons (plan)

Status: planned, not built yet.

## The idea

Players earn achievements for story milestones. Some achievements unlock alternate app icons. SNARK-9 notices each new achievement and awards it in character. The first one: **landing on the planet** unlocks the ensign icon (`Art/AppIcons/ensign.png`). The recruitment-poster art becomes the default icon.

## How it would work

### 1. Detecting achievements (engine)

- An `Achievement` table, like `StoryEvent`: an id, a title, a short description, and a trigger.
- **Triggers reuse what we already detect.** Most are a sentence the game prints exactly once. Landing is "The pod lands with a thud", the same sentence that ends the `planet` story event. Others can key off a story event, a room reached for the first time, or the score.
- `GameSession` emits a new `GameEvent.achievementUnlocked(Achievement)` the first time one is earned.

### 2. Remembering them (app)

- **Earned achievements persist across games and launches** in UserDefaults. Restarting the game or the app doesn't take them away.
- RESTORE and in-game RESTART don't matter: once earned, an achievement stays earned.
- A debug way to reset them is needed for demos (a hidden menu item, or a launch flag).

### 3. SNARK-9 awards it

- When an achievement unlocks, the next commentary request includes a line like "Achievement just unlocked: Planetfall (landed on the planet)". The prompt tells SNARK-9 to announce it in character, grudgingly impressed.
- That one turn never passes, so the award is always spoken.
- If an icon came with it, SNARK-9 can mention that too, for example "…and apparently you've earned a new app icon. Don't let it go to your head."

### 4. The app shows it

- A small toast over the room art: "Achievement unlocked: Planetfall", with the icon's thumbnail if one was unlocked.
- An **Achievements** menu lists earned and locked achievements. Locked ones show "???" so nothing gets spoiled.

### 5. Choosing the app icon

- An **App Icon** submenu lists the icons: the poster (default), the ensign (locked until landing), and any future ones.
- **Dock:** selecting an icon sets `NSApp.applicationIconImage` right away, and again at every launch.
- **Finder:** macOS has no supported "alternate icon" API for Mac apps (unlike iOS). The Finder and Launchpad icon comes from the bundle's `AppIcon.icns`. Options:
  - Leave Finder on the default icon and change only the Dock. Simplest; recommended for the hackathon.
  - `NSWorkspace.setIcon(_:forFile:)` on the app bundle. This adds a custom icon file inside the bundle, which breaks the ad-hoc code signature. That's OK for local builds, but not if the app is ever signed for distribution.

## Proposed first achievements

| Id | Title | Trigger | Unlocks |
|---|---|---|---|
| `landed` | Planetfall | "The pod lands with a thud" | Ensign app icon |
| `brig` | Detention, Again | Reaching the Brig | — |
| `escaped` | Abandon Ship | Launching in the escape pod ("…you see the Feinstein dwindle…") | — |

## Open questions

1. Does SNARK-9 award achievements even when commentary is turned off (with just the toast), or only when it's on?
2. Should earned achievements sync between teammates' machines (iCloud key-value store), or stay per Mac? Per Mac is simpler.
3. Should the Finder icon change too (option 2 above), or is the Dock enough?
4. Should Gaurav's voices speak the award in SNARK-9's voice? This probably comes for free, since award lines go through the normal commentary path.
