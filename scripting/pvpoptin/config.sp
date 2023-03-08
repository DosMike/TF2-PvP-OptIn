#if defined _pvpoptin_config
 #endinput
#endif
#define _pvpoptin_config
#if !defined PLUGIN_VERSION
 #error Please compile the main file
#endif

#include "common.sp"

static ConVar cvar_Version;
static ConVar cvar_JoinForceState;
static ConVar cvar_NoCollide;
static ConVar cvar_ActiveStates;
static ConVar cvar_PairPvPRequestMenu;
static ConVar cvar_UsePlayerColors;
static ConVar cvar_ColorGlobalOnRed;
static ConVar cvar_ColorGlobalOnBlu;
static ConVar cvar_ColorGlobalOffRed;
static ConVar cvar_ColorGlobalOffBlu;
static ConVar cvar_UsePvPParticle;
static ConVar cvar_BuildingsVersusZombies;
static ConVar cvar_BuildingsVersusBosses;
static ConVar cvar_PlayersVersusZombies;
static ConVar cvar_PlayersVersusBosses;
static ConVar cvar_SpawnKillProperties;
static ConVar cvar_ToggleAction;

static void hookAndLoadCvar(ConVar cvar, ConVarChanged handler) {
	char def[20], val[20];
	cvar.GetDefault(def, sizeof(def));
	cvar.GetString(val, sizeof(val));
	Call_StartFunction(INVALID_HANDLE, handler);
	Call_PushCell(cvar);
	Call_PushString(def);
	Call_PushString(val);
	Call_Finish();
	cvar.AddChangeHook(handler);
}

void Plugin_SetupConvars() {
	cvar_Version = CreateConVar( "pvp_optin_version", PLUGIN_VERSION, "PvP Opt-In Version", FCVAR_NOTIFY|FCVAR_DONTRECORD);
	cvar_JoinForceState = CreateConVar( "pvp_joinoverride", "0", "Define global PvP State when player joins. 0 = Load player choice, 1 = Force out of PvP, -1 = Force enable PvP", _, true, -1.0, true, 1.0);
	cvar_NoCollide = CreateConVar( "pvp_nocollide", "1", "Can be used to disable player collision between enemies. 0 = Don't change, 1 = with global pvp disabled, 2 = never collied", _, true, 0.0, true, 2.0);
	cvar_ActiveStates = CreateConVar( "pvp_gamestates", "all", "Games states where this plugin should be active. Possible values: all, waiting, pregame, running, overtime, suddendeath, gameover", _);
	cvar_PairPvPRequestMenu = CreateConVar( "pvp_requestmenus", "1", "When players request pair PvP: 0 = requeste will have to use /pvp requester, 1 = requestee will receive a menu, 2 = will force VGUI menus", _, true, 0.0, true, 2.0);
	cvar_BuildingsVersusZombies = CreateConVar( "pvp_buildings_vs_zombies", "2", "Control sentry <-> skeleton targeting. Possible values: -1 = Fully ignore, even manual damage, 0 = Never target, 1 = Global PvP only, 2 = This is PvE so Always", _, true, -1.0, true, 2.0);
	cvar_BuildingsVersusBosses = CreateConVar( "pvp_buildings_vs_bosses", "2", "Control sentry <-> boss targeting. Possible values: -1 = Fully ignore, even manual damage, 0 = Never target, 1 = Global PvP only, 2 = This is PvE so Always", _, true, -1.0, true, 2.0);
	cvar_PlayersVersusZombies = CreateConVar( "pvp_players_vs_zombies", "1", "Control player <-> skeleton targeting. Possible values: -1 = Fully ignore, even manual damage, 0 = Never target, 1 = Global PvP only, 2 = This is PvE so Always", _, true, -1.0, true, 2.0);
	cvar_PlayersVersusBosses = CreateConVar( "pvp_players_vs_bosses", "1", "Control player <-> boss targeting. Possible values: -1 = Fully ignore, even manual damage, 0 = Never target, 1 = Global PvP only, 2 = This is PvE so Always", _, true, -1.0, true, 2.0);
	cvar_UsePlayerColors = CreateConVar( "pvp_playertaint_enable", "1", "Can be used to disable player tainting based on pvp state", _, true, 0.0, true, 1.0);
	cvar_ColorGlobalOnRed = CreateConVar( "pvp_playertaint_redon", "125 125 255", "Color for players on RED with global PvP enabled. Argument is R G B A from 0 to 255 or web color #RRGGBBAA. Alpha is optional.", _);
	cvar_ColorGlobalOnBlu = CreateConVar( "pvp_playertaint_bluon", "255 125 125", "Color for players on BLU with global PvP enabled. Argument is R G B A from 0 to 255 or web color #RRGGBBAA. Alpha is optional.", _);
	cvar_ColorGlobalOffRed = CreateConVar( "pvp_playertaint_redoff", "255 255 225", "Color for players on RED with global PvP disabled. Argument is R G B A from 0 to 255 or web color #RRGGBBAA. Alpha is optional.", _);
	cvar_ColorGlobalOffBlu = CreateConVar( "pvp_playertaint_bluoff", "255 255 225", "Color for players on BLU with global PvP disabled. Argument is R G B A from 0 to 255 or web color #RRGGBBAA. Alpha is optional.", _);
	cvar_UsePvPParticle = CreateConVar( "pvp_playerparticle_enable", "1", "Play a particle on players that can be PvPed. Playes for both global and pair PvP", _, true, 0.0, true, 1.0);
	cvar_SpawnKillProperties = CreateConVar( "pvp_spawnkill_protection", "15 5 35 100 60", "Four parameters to configure spawn protection. min penalty, protection time, max penalty, threashold, timeout. Empty to disable, invalid values will use default.");
	cvar_ToggleAction = CreateConVar( "pvp_toggle_action", "0", "Flags for what to do when global pvp is toggled (set to sum): 1 - Respawn when entering, 2 - Kill when entering, 4 - Respawn when leaving, 8 - Kill when leaving", _, true, 0.0, true, 16.0);
	//create fancy plugin config - should be sourcemod/pvpoptin.cfg
	AutoExecConfig();
	//hook cvars and load current values
	hookAndLoadCvar(cvar_Version, OnCVarChanged_Version);
	hookAndLoadCvar(cvar_JoinForceState, OnCVarChanged_JoinForceState);
	hookAndLoadCvar(cvar_NoCollide, OnCVarChanged_NoCollision);
	hookAndLoadCvar(cvar_ActiveStates, OnCVarChanged_ActiveStates);
	hookAndLoadCvar(cvar_PairPvPRequestMenu, OnCVarChanged_PairPvPRequestMenu);
	hookAndLoadCvar(cvar_BuildingsVersusZombies, OnCVarChanged_BuildingsVersusZombies);
	hookAndLoadCvar(cvar_BuildingsVersusBosses, OnCVarChanged_BuildingsVersusBosses);
	hookAndLoadCvar(cvar_PlayersVersusZombies, OnCVarChanged_PlayersVersusZombies);
	hookAndLoadCvar(cvar_PlayersVersusBosses, OnCVarChanged_PlayersVersusBosses);
	hookAndLoadCvar(cvar_UsePlayerColors, OnCVarChanged_UsePlayerTaint);
	hookAndLoadCvar(cvar_ColorGlobalOnRed, OnCVarChanged_PlayerTaint);
	hookAndLoadCvar(cvar_ColorGlobalOnBlu, OnCVarChanged_PlayerTaint);
	hookAndLoadCvar(cvar_ColorGlobalOffRed, OnCVarChanged_PlayerTaint);
	hookAndLoadCvar(cvar_ColorGlobalOffBlu, OnCVarChanged_PlayerTaint);
	hookAndLoadCvar(cvar_UsePvPParticle, OnCVarChanged_UsePvPParticle);
	hookAndLoadCvar(cvar_SpawnKillProperties, OnCVarChanged_SpawnKillProperties);
	hookAndLoadCvar(cvar_ToggleAction, OnCVarChanged_ToggleAction);
}

//region cvar handling
public void OnCVarChanged_Version(ConVar convar, const char[] oldValue, const char[] newValue) {
	if (!StrEqual(newValue, PLUGIN_VERSION)) convar.SetString(PLUGIN_VERSION);
}
public void OnCVarChanged_JoinForceState(ConVar convar, const char[] oldValue, const char[] newValue) {
	joinForceState = convar.IntValue;
}
public void OnCVarChanged_NoCollision(ConVar convar, const char[] oldValue, const char[] newValue) {
	noCollideState = convar.IntValue;
}
public void OnCVarChanged_ActiveStates(ConVar convar, const char[] oldValue, const char[] newValue) {
	eGameState activeStates;
	if (StrContains(newValue,"all",false)!=-1) { activeStates = view_as<eGameState>(-1); }
	else {
		if (StrContains(newValue,"pregame",false)!=-1) activeStates |= GameState_PreGame;
		if (StrContains(newValue,"waiting",false)!=-1) activeStates |= GameState_Waiting;
		if (StrContains(newValue,"running",false)!=-1) activeStates |= GameState_Running;
		if (StrContains(newValue,"overtime",false)!=-1) activeStates |= GameState_Overtime;
		if (StrContains(newValue,"suddendeath",false)!=-1) activeStates |= GameState_SuddenDeath;
		if (StrContains(newValue,"gameover",false)!=-1) activeStates |= GameState_GameOver;
	}
	activeGameStates = activeStates;
	UpdateActiveState(currentGameState);
}
public void OnCVarChanged_PairPvPRequestMenu(ConVar convar, const char[] oldValue, const char[] newValue) {
	pairPvPRequestMenu = convar.IntValue;
}
public void OnCVarChanged_BuildingsVersusZombies(ConVar convar, const char[] oldValue, const char[] newValue) {
	ePlayerVsAiFlags value;
	switch (convar.IntValue) {
		case -1: value = PvA_Zombies_Ignored;
		case 0: value = PvA_Zombies_Never;
		case 1: value = PvA_Zombies_GlobalPvP;
		case 2: value = PvA_Zombies_Always;
		default: {
			PrintToServer("Invalid value for Building VS Zombies, using -1");
			value = PvA_Zombies_Ignored;
		}
	}
	pvaBuildings = (pvaBuildings & PvA_BOSSES) | value;
}
public void OnCVarChanged_BuildingsVersusBosses(ConVar convar, const char[] oldValue, const char[] newValue) {
	ePlayerVsAiFlags value;
	switch (convar.IntValue) {
		case -1: value = PvA_Bosses_Ignored;
		case 0: value = PvA_Bosses_Never;
		case 1: value = PvA_Bosses_GlobalPvP;
		case 2: value = PvA_Bosses_Always;
		default: {
			PrintToServer("Invalid value for Building VS Bosses, using -1");
			value = PvA_Bosses_Ignored;
		}
	}
	pvaBuildings = (pvaBuildings & PvA_ZOMBIES) | value;
}
public void OnCVarChanged_PlayersVersusZombies(ConVar convar, const char[] oldValue, const char[] newValue) {
	ePlayerVsAiFlags value;
	switch (convar.IntValue) {
		case -1: value = PvA_Zombies_Ignored;
		case 0: value = PvA_Zombies_Never;
		case 1: value = PvA_Zombies_GlobalPvP;
		case 2: value = PvA_Zombies_Always;
		default: {
			PrintToServer("Invalid value for Player VS Zombies, using -1");
			value = PvA_Zombies_Ignored;
		}
	}
	pvaPlayers = (pvaPlayers & PvA_BOSSES) | value;
}
public void OnCVarChanged_PlayersVersusBosses(ConVar convar, const char[] oldValue, const char[] newValue) {
	ePlayerVsAiFlags value;
	switch (convar.IntValue) {
		case -1: value = PvA_Bosses_Ignored;
		case 0: value = PvA_Bosses_Never;
		case 1: value = PvA_Bosses_GlobalPvP;
		case 2: value = PvA_Bosses_Always;
		default: {
			PrintToServer("Invalid value for Player VS Bosses, using -1");
			value = PvA_Bosses_Ignored;
		}
	}
	pvaPlayers = (pvaPlayers & PvA_ZOMBIES) | value;
}
public void OnCVarChanged_UsePlayerTaint(ConVar convar, const char[] oldValue, const char[] newValue) {
	if (!(usePlayerStateColors = convar.BoolValue)) {
		for (int i=1;i<=MaxClients;i++) {
			if (IsClientInGame(i) && GetClientTeam(i)>1) {
				SetPlayerColor(i);
			}
		}
	}
}
public void OnCVarChanged_PlayerTaint(ConVar convar, const char[] oldValue, const char[] newValue) {
	//spliterate
	char args[4][16];
	char buffer[50];
	strcopy(buffer, sizeof(buffer), newValue);
	int argc;
	for (int to;argc<4;) {
		if ((to = SplitString(buffer, " ", args[argc], sizeof(args[])))<0) {
			strcopy(args[argc], sizeof(args[]), buffer); //manually get tail
		}
		if (strlen(args[argc])) argc++; //no empty parts
		if (to >= strlen(buffer) || to < 0) break;
		Format(buffer, sizeof(buffer), "%s", buffer[to]); //cut head
	}
	//parse values
	int r,g,b,a=255; bool valid=true;
	if (argc == 1 && args[0][0] == '#') {
		int color, plen = StringToIntEx(args[0][1],color,16), slen = strlen(args[0])-1;
		if (slen != plen) { //fallthrough
			valid = false;
		} else if (slen == 6) {
			r = (color>>16) & 0xff;
			g = (color>>8) & 0xff;
			b = color & 0xff;
		} else if (slen == 8) {
			r = (color>>24) & 0xff;
			g = (color>>16) & 0xff;
			b = (color>>8) & 0xff;
			a = color & 0xff;
		}
	} else if (argc == 3 || argc == 4) {
		valid &= strlen(args[0]) == StringToIntEx(args[0], r) && 0<=r<=255;
		valid &= strlen(args[1]) == StringToIntEx(args[1], g) && 0<=g<=255;
		valid &= strlen(args[2]) == StringToIntEx(args[2], b) && 0<=b<=255;
		if (argc == 4)
			valid &= strlen(args[3]) == StringToIntEx(args[3], a) && 0<=a<=255;
	} else valid = false;
	if (!valid) {
		convar.SetString(oldValue); // unknown format
		return;
	}
	//pick target
	int ci;
	if (convar == cvar_ColorGlobalOnRed) {
		ci = 0;
	} else if (convar == cvar_ColorGlobalOnBlu) {
		ci = 1;
	} else if (convar == cvar_ColorGlobalOffRed) {
		ci = 2;
	} else if (convar == cvar_ColorGlobalOffBlu) {
		ci = 3;
	}
	playerStateColors[ci][0] = r;
	playerStateColors[ci][1] = g;
	playerStateColors[ci][2] = b;
	playerStateColors[ci][3] = a;
	//update clients
	for (int i=1;i<=MaxClients;i++) {
		if (IsClientInGame(i)&&IsPlayerAlive(i)) {
			UpdateEntityFlagsGlobalPvP(i, IsGlobalPvP(i));
		}
	}
}
public void OnCVarChanged_UsePvPParticle(ConVar convar, const char[] oldValue, const char[] newValue) {
	if (!(usePvPParticle = convar.BoolValue)) {
		for (int client=1;client<=MaxClients;client++) {
			if (IsClientInGame(client) && GetClientTeam(client)>1) {
				ParticleEffectStop(client);
			}
			clientParticleAttached[client] = false;
		}
	}
}
public void OnCVarChanged_SpawnKillProperties(ConVar convar, const char[] oldValue, const char[] newValue) {
	int mscore,ptime,score,limit,btime;
	int off,len;
	char arg[32];
	if (strlen(newValue)==0) {
		spawnKill_maxTime = 0.0;
		spawnKill_minIncrease = 0;
		spawnKill_maxIncreaseRoot = 0.0;
		spawnKill_threashold = 0;
		spawnKill_banTime = 0;
		return;
	}
	if ((len=BreakString(newValue[off], arg, sizeof(arg))) < 1 || StringToIntEx(arg,mscore)!=strlen(arg) || mscore <1) {
		convar.SetString("15 5 35 100 60");
		return;
	} else off += len;
	if ((len=BreakString(newValue[off], arg, sizeof(arg))) < 1 || StringToIntEx(arg,ptime)!=strlen(arg) || ptime <1) {
		convar.SetString("15 5 35 100 60");
		return;
	} else off += len;
	if ((len=BreakString(newValue[off], arg, sizeof(arg))) < 1 || StringToIntEx(arg,score)!=strlen(arg) || score < mscore) {
		convar.SetString("15 5 35 100 60");
		return;
	} else off += len;
	if ((len=BreakString(newValue[off], arg, sizeof(arg))) < 1 || StringToIntEx(arg,limit)!=strlen(arg) || limit <1) {
		convar.SetString("15 5 35 100 60");
		return;
	} else off += len;
	BreakString(newValue[off], arg, sizeof(arg));
	if (StringToIntEx(arg,btime)!=strlen(arg) || btime <1) {
		convar.SetString("15 5 35 100 60");
		return;
	}
	
	spawnKill_maxTime = float(ptime); //protection time
	spawnKill_minIncrease = mscore; //score increase at insta-kill
	if (score > mscore) spawnKill_maxIncreaseRoot = SquareRoot(float(score-mscore)); //score increase at insta-kill
	else spawnKill_maxIncreaseRoot = 0.0; //using a flat increase
	spawnKill_threashold = limit; //maximum score before banning
	spawnKill_banTime = btime; //time to ban for
}

public void OnCVarChanged_ToggleAction(ConVar convar, const char[] oldValue, const char[] newValue) {
	togglePvPAction = (convar.IntValue & 0x0F);
}

//enregion
