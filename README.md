# Mute

This addon functions similarly to the default Blizzard ignore system by introducing muting tools for players, guilds, chat term filtering, and an automated collector called Watcher.

Mute is integrated into the Ignore window within the Friends/Social UI, as well as accessible via the chat command /mutelis. It also includes other slash commands like `/mute Player Name`, as well as Right Click menu options.

## Key Features
* **Guild Muting:** Guilds can be specified to cover a wide range of muted players, however it may require having seen a player in that guild for it to work (such as seen via nameplate or /who info).
* **Guild Member Exceptions:** Specific players within a guild can be whitelisted from a guild mute. They won't be excempt from the terms filter.
* **Ignore Frame:** The default Ignore frame will now have some tabs for Mute and Terms, and it resizes the frame a bit since it was a very small frame to begin with.

### Term Filtering
Messages based on specific keywords or patterns are also muted/blocked. There's a few different settings available for it:
* **Contains:** Blocks the message if the exact text appears anywhere within a word.
* **Word:** Blocks the message only if the term is used as a standalone word.
* **Contains All:** Blocks the message only if a comma-separated list of words are *all* present.
* **Advanced:** Supports full Lua pattern matching for complex filtering, such as links or gold spamers.

### Speech Bubble Filtering
It also attempts to take muted messages seen and associates with with the contents of a speech bubble to mute. There isn't a way to tell who the sender of a message is however, so it isn't perfect.

### Watcher
Some specific guilds in WoW Forever are tracked automatically using the Watcher to gather guild census data and automatically apply Mutes on members.
* **Categorized Watchlist:** Automatically categorizes identified players into confidence tiers: 
  * *Verified* (Confirmed by standard game API + network data)
  * *Addon* (Self-reported by their own client)
  * *Reported* (Flagged by other users' census reports)
  * *Suspected* (Unverified substring match)

Watcher messages are normally disabled by default.

## Differences from Ignore
* **Higher Capacity:** Ignores are capped at a much lower number and the list is typically character-specific. Mutes are fully account-wide and don't have a specified cap.
* **Shift-Click:** Destructive actions (like unmuting a guild or deleting a term) require holding `Shift` to prevent accidental clicks. This function was carried onto the Unignore button.

## Limitations & Known Issues
Due to the constraints of the World of Warcraft API, there are a few limitations to how Mute operates:

* **Speech Bubble Ambiguity:** The WoW client does not expose the sender of a speech bubble directly to the UI code. Mute works around this by matching the *text* of the bubble to recent chat events. If a muted player and an unmuted player say the exact same phrase (e.g., "lol") at the exact same time, the addon cannot differentiate them and may hide both (or neither).
* **Instanced Combat:** Message detection within instanced combat is outside the capability of the addon, meaning if a muted player or a term is present in dungeon combat, it won't be hidden. There's currently no workaround to this.
* **Other Interactions:** Unlike the Ignore function, this won't prevent you from grouping with other players, opening trade, background functions like preventing LFG tool grouping, or other obscure methods of interaction. To cover all of these cases either far exceeds the capability of the addon or is well outside the scope.

## Future Features?
I would advocate to have Blizzard lift the ignore cap primarily. If this is done I can try to add a feature to facilitate migrating all individual Mute entries into ignores. Some simple changes would be to primarily just show the entire account's ignore list in frame (not be character-specific) and to raise the 50 ignore cap to compensate. This tool can't cover all of the possible interactions that Ignore would othewise normally prevent, and it shouldn't be treated as a long-term solution.

## Slash Commands
Slash commands are available in each localization as well as English for every localization (in case translate tools are bad):
`/mute Player Name` - mutes a player
`/mutelist` - Opens the mutelist UI

🇪🇸🇲🇽: /silencio
/silenciarlista

🇩🇪: /stumm
/stummelliste

🇫🇷: /muet
/muetliste

🇮🇹: /silenzia
/silenzialista

🇵🇹🇧🇷: /mudo
/silenciarlista

🇷🇺: /молчать
/отключитьзвуксписок

🇰🇷: /무음
/무음목록

🇨🇳: /禁音
/禁音列表

🇹🇼: /消音
/消音列表