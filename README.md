# PvP Opt In
By default no pvp and pass through enemy team players.

This plugin was written as alternative to /friendly plugins as players usually forgot to enable it or were unhappy with how collision groups mess up certain things like elevators. So hopefully by putting all that on it's head, there wont ever be the need to report for RDM again!

### Features:

- Global PvP toggle
- Pair PvP via invites, player can disable invites
- Walk through enemies base on pvp state
- Color players based on pvp state
- Sentries and bots ignore non-pvp players
- Fully translatable
- Blocks various conditions between non-pvp players
- Prevent players pushing eachother with e.g. loose cannon outside of pvp
- Bosses and Skeleton ignore players that are not in PvP (see ConVars)
- Generates a config at cfg/sourcemod/plugin.pvpoptin.cfg

*Note on Supressing AI Targeting:* Due to how the targeting for sentries and some bosses is implemented,
supressing a player or entity from being targeted results in the sentry or boss not seeing any enemy and idling or
entering a false positive state.

### ConVars:

**`pvp_joinoverride "0"`**   
Define global PvP State when player joins.   
0 = Load player choice, 1 = Force out of PvP, -1 = Force enable PvP

**`pvp_nocollide "1"`**   
Can be used to disable player collision between enemies.   
0 = Don't change, 1 = with global pvp disabled, 2 = never collied

**`pvp_gamestates "all"`**   
The game states when this plugin should be active or all if it should always run. Following states are possible: all, waiting, pregame, running, overtime, suddendeath, gameover

**`pvp_buildings_vs_zombies "2"`**   
Control sentry <-> skeleton targeting.   
Possible values: -1 = Fully ignore, even manual damage, 0 = Never target, 1 = Global PvP only, 2 = This is PvE so Always

**`pvp_buildings_vs_bosses "2"`**   
Control sentry <-> boss targeting.   
Possible values: -1 = Fully ignore, even manual damage, 0 = Never target, 1 = Global PvP only, 2 = This is PvE so Always

**`pvp_players_vs_zombies "1"`**   
Control player <-> skeleton targeting.   
Possible values: -1 = Fully ignore, even manual damage, 0 = Never target, 1 = Global PvP only, 2 = This is PvE so Always

**`pvp_players_vs_bosses "1"`**   
Control player <-> boss targeting.   
Possible values: -1 = Fully ignore, even manual damage, 0 = Never target, 1 = Global PvP only, 2 = This is PvE so Always

**`pvp_playertaint_enable "1"`**   
Can be used to disable player tainting based on pvp state

**`pvp_playertaint_bluoff "255 255 225"`**   
Color for players on BLU with global PvP disabled.

**`pvp_playertaint_bluon "255 125 125"`**   
Color for players on BLU with global PvP enabled.

**`pvp_playertaint_redoff "255 255 225"`**   
Color for players on RED with global PvP disabled.

**`pvp_playertaint_redon "125 125 255"`**   
Color for players on RED with global PvP enabled.

For all colors for format is `R G B A` from 0 to 255 or web color `#RRGGBBAA`. Alpha is optional.

### Commands:

**`/pvp`**   
Toggle global PvP on or off

**`/pvp player`**
Invite to, accept and end pair PvP with another player.
If the player was not found, get a menu.

**`/stoppvp`**
End pair PvP with all players.
If no pair PvP running, toggle ignore state.

**`/forcepvp <target|'map'> <0|1>`**
Override the targets global pvp choice. If you use 'map' it will apply to all players joining the server. Non persistent (will reset on map change). Requires admin flag Slay.

**`/mirror <target> <0|1>`**   
Force mirror damage on someone. Mirror damage only affects players that are not PvPing, and is only for fun.

**`/mirrorme`**
Mirror your damage agains non-PvP players.

**New Target Selectors:**
- `@pvp` Select all players with global PvP enabled
- `@!pvp` Select all players with global PvP enabled

There's also a settings menu to toggle global PvP and pair PvP.

### Dependencies:

Install the following required plugins:
- [DHooks](https://forums.alliedmods.net/showpost.php?p=2588686&postcount=589)
- [CollisionHook](https://github.com/Adrianilloo/Collisionhook/releases)
- [TF Utils](https://github.com/nosoop/SM-TFUtils/releases)

**Note:** DHooks was added to SM 1.11, you might not need to download it in the future.

The CollisionHook branch I linked is prebuilt, but the **gamedata might be outdate**.
Check [this file](https://github.com/Adrianilloo/Collisionhook/blob/master/extra/collisionhook.txt), it should be up to date.

If you want to compile the plugin you will need [SMLib's transitional syntax branch](https://github.com/bcserv/smlib/tree/transitional_syntax) and [MoreColors](https://raw.githubusercontent.com/DoctorMcKay/sourcemod-plugins/master/scripting/include/morecolors.inc)

