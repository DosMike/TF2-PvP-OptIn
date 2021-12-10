#include <sourcemod>
#include <tf2_stocks>
#include <sdkhooks>
#include <clientprefs>
#include <morecolors>
#include <smlib>
#include <collisionhook>
#include <dhooks>
#include <tf2utils>

#define PLUGIN_VERSION "21w49d"
#pragma newdecls required
#pragma semicolon 1

public Plugin myinfo = {
	name = "[TF2] Opt In PvP",
	author = "reBane",
	description = "Opt In PvP for LazyPurple Silly Servers",
	version = PLUGIN_VERSION,
	url = "N/A"
}

// will be double checked with TF2Util_GetPlayerConditionProvider
static TFCond pvpConditions[] = {
	TFCond_Slowed,
	TFCond_Bonked,
	TFCond_Dazed,
	TFCond_OnFire,
	TFCond_Jarated,
	TFCond_Bleeding,
	TFCond_Milked,
	TFCond_MarkedForDeath,
	TFCond_RestrictToMelee,
	TFCond_MarkedForDeathSilent,
	TFCond_Sapped,
	TFCond_MeleeOnly,
	TFCond_FreezeInput,
	TFCond_KnockedIntoAir,
	TFCond_Gas,
	TFCond_BurningPyro,
	TFCond_LostFooting,
	TFCond_AirCurrent
};

enum eGameState(<<=1) {
	GameState_Never=0,
	GameState_Waiting=1,
	GameState_PreGame,
	GameState_Running,
	GameState_Overtime,
	GameState_SuddenDeath,
	GameState_GameOver
}

static bool isActive;
static eGameState currentGameState;
static bool globalPvP[MAXPLAYERS+1];
static bool forcePvP[MAXPLAYERS+1]; //for events
static bool pairPvP[MAXPLAYERS+1][MAXPLAYERS+1];
static int pairPvPrequest[MAXPLAYERS+1];
static bool pairPvPignored[MAXPLAYERS+1];
static bool clientFirstSpawn[MAXPLAYERS+1];
static DHookSetup hdl_INextBot_IsEnemy;
static bool detoured_INextBot_IsEnemy;
static DHookSetup hdl_CTFPlayer_ApplyGenericPushbackImpulse;
static bool detoured_CTFPlayer_ApplyGenericPushbackImpulse;
static DHookSetup hdl_CObjectSentrygun_ValidTargetPlayer;
static bool detoured_CObjectSentrygun_ValidTargetPlayer;

static ConVar cvar_Version;
static ConVar cvar_JoinForceState;
static int joinForceState;
static ConVar cvar_NoCollide;
static int noCollideState;
static ConVar cvar_NoTarget;
static bool noTargetPlayers;
static ConVar cvar_ActiveStates;
static eGameState activeGameStates;
static ConVar cvar_UsePlayerColors;
static bool usePlayerStateColors;
static ConVar cvar_ColorGlobalOnRed;
static ConVar cvar_ColorGlobalOnBlu;
static ConVar cvar_ColorGlobalOffRed;
static ConVar cvar_ColorGlobalOffBlu;
static int playerStateColors[4][4];

#define COOKIE_GLOBALPVP "enableGlobalPVP"
#define COOKIE_IGNOREPVP "ignorePairPVP"

#define IsGlobalPvP(%1) (globalPvP[%1]||forcePvP[%1])

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
public void OnPluginStart() {
	LoadTranslations("common.phrases");
	LoadTranslations("pvpoptin.phrases");
	
	//to find this signature you can go up Spawn function through powerups to bonuspacks.
	//that has a call to GetTeamNumber and IsEnemy is basically a function with that call twice.
	//The first 20-something bytes of the signature are unlikely to change, just chip from the end and you should find it.
	GameData nbdata = new GameData("pvpoptin.games");
	if (nbdata != INVALID_HANDLE) {
		hdl_INextBot_IsEnemy = DHookCreateFromConf(nbdata, "INextBot_IsEnemy");
		hdl_CTFPlayer_ApplyGenericPushbackImpulse = DHookCreateFromConf(nbdata, "CTFPlayer_ApplyGenericPushbackImpulse");
		hdl_CObjectSentrygun_ValidTargetPlayer = DHookCreateFromConf(nbdata, "CObjectSentrygun_ValidTargetPlayer");
		delete nbdata;
	}
	
	RegClientCookie(COOKIE_GLOBALPVP, "Client has opted into global PvP", CookieAccess_Private);
	RegClientCookie(COOKIE_IGNOREPVP, "Client wants to ignore pair PvP", CookieAccess_Private);
	
	RegConsoleCmd("sm_pvp", Command_TogglePvP, "Usage: [name|userid] - If you specify a user, request pair PvP, otherwise toggle global PvP");
	RegConsoleCmd("sm_stoppvp", Command_StopPvP, "End all pair PvP or toggle pair PvP ignore state if you're not in pair PvP");
	RegAdminCmd("sm_forcepvp", Command_ForcePvP, ADMFLAG_SLAY, "Usage: <target|'map'> <1/0> - Force the targets into global PvP; 'map' applies to players that will join as well; Resets on map change");
	
	AddMultiTargetFilter("@pvp", TargetSelector_PVP, "all PvPer", false);
	AddMultiTargetFilter("@!pvp", TargetSelector_PVP, "all Non-PvPer", false);
	
	HookEvent("post_inventory_application", OnInventoryApplicationPost);
	
	HookEvent("teamplay_waiting_begins", OnRoundStateChange);
	HookEvent("teamplay_waiting_ends", OnRoundStateChange);
	HookEvent("teamplay_round_start", OnRoundStateChange);
	HookEvent("teamplay_overtime_begin", OnRoundStateChange);
	HookEvent("teamplay_overtime_end", OnRoundStateChange);
	HookEvent("teamplay_suddendeath_begin", OnRoundStateChange);
	HookEvent("teamplay_suddendeath_end", OnRoundStateChange);
	HookEvent("teamplay_game_over", OnRoundStateChange);
	HookEvent("teamplay_round_win", OnRoundStateChange);
	HookEvent("teamplay_round_stalemate", OnRoundStateChange);
	
	cvar_Version = CreateConVar( "pvp_optin_version", PLUGIN_VERSION, "PvP Opt-In Version", FCVAR_NOTIFY | FCVAR_DONTRECORD);
	cvar_JoinForceState = CreateConVar( "pvp_joinoverride", "0", "Define global PvP State when player joins. 0 = Load player choice, 1 = Force out of PvP, -1 = Force enable PvP", FCVAR_ARCHIVE, true, -1.0, true, 1.0);
	cvar_NoCollide = CreateConVar( "pvp_nocollide", "1", "Can be used to disable player collision between enemies. 0 = Don't change, 1 = with global pvp disabled, 2 = never collied", FCVAR_ARCHIVE, true, 0.0, true, 2.0);
	cvar_NoTarget = CreateConVar( "pvp_notarget", "0", "Add NOTARGET to players outside global pvp. This will probably break stuff!", FCVAR_ARCHIVE, true, 0.0, true, 1.0);
	cvar_ActiveStates = CreateConVar( "pvp_gamestates", "all", "Games states where this plugin should be active. Possible values: all, waiting, pregame, running, overtime, suddendeath, gameover", FCVAR_ARCHIVE);
	cvar_UsePlayerColors = CreateConVar( "pvp_playertaint_enable", "1", "Can be used to disable player tainting based on pvp state", FCVAR_ARCHIVE, true, 0.0, true, 1.0);
	cvar_ColorGlobalOnRed = CreateConVar( "pvp_playertaint_redon", "125 125 255", "Color for players on RED with global PvP enabled. Argument is R G B A from 0 to 255 or web color #RRGGBBAA. Alpha is optional.", FCVAR_ARCHIVE);
	cvar_ColorGlobalOnBlu = CreateConVar( "pvp_playertaint_bluon", "255 125 125", "Color for players on BLU with global PvP enabled. Argument is R G B A from 0 to 255 or web color #RRGGBBAA. Alpha is optional.", FCVAR_ARCHIVE);
	cvar_ColorGlobalOffRed = CreateConVar( "pvp_playertaint_redoff", "255 255 225", "Color for players on RED with global PvP disabled. Argument is R G B A from 0 to 255 or web color #RRGGBBAA. Alpha is optional.", FCVAR_ARCHIVE);
	cvar_ColorGlobalOffBlu = CreateConVar( "pvp_playertaint_bluoff", "255 255 225", "Color for players on BLU with global PvP disabled. Argument is R G B A from 0 to 255 or web color #RRGGBBAA. Alpha is optional.", FCVAR_ARCHIVE);
	//hook cvars and load current values
	hookAndLoadCvar(cvar_Version, OnCVarChanged_Version);
	hookAndLoadCvar(cvar_JoinForceState, OnCVarChanged_JoinForceState);
	hookAndLoadCvar(cvar_NoCollide, OnCVarChanged_NoCollision);
	hookAndLoadCvar(cvar_NoTarget, OnCVarChanged_NoTarget);
	hookAndLoadCvar(cvar_ActiveStates, OnCVarChanged_ActiveStates);
	hookAndLoadCvar(cvar_UsePlayerColors, OnCVarChanged_UsePlayerTaint);
	hookAndLoadCvar(cvar_ColorGlobalOnRed, OnCVarChanged_PlayerTaint);
	hookAndLoadCvar(cvar_ColorGlobalOnBlu, OnCVarChanged_PlayerTaint);
	hookAndLoadCvar(cvar_ColorGlobalOffRed, OnCVarChanged_PlayerTaint);
	hookAndLoadCvar(cvar_ColorGlobalOffBlu, OnCVarChanged_PlayerTaint);
	//create fancy plugin config - should be sourcemod/pvpoptin.cfg
	AutoExecConfig();
	
	SetCookieMenuItem(HandleCookieMenu, 0, "PvP");
	bool hotload;
	for (int i=1;i<=MaxClients;i++) {
		if(IsClientConnected(i)) {
			OnClientConnected(i);
			if (IsClientInGame(i))
				SDKHookClient(i);
			if (AreClientCookiesCached(i))
				OnClientCookiesCached(i);
			if (IsPlayerAlive(i)) {
				OnClientSpawnPost(i);
				hotload = true;
			}
		}
	}
	if (hotload) RequestFrame(HotloadGameState);
}
public void OnPluginEnd() {
	DHooksDetach();
}

static void DHooksAttach() {
	if (hdl_INextBot_IsEnemy != INVALID_HANDLE && !detoured_INextBot_IsEnemy) {
		detoured_INextBot_IsEnemy = DHookEnableDetour(hdl_INextBot_IsEnemy, false, Detour_INextBot_IsEnemy);
	} else {
		PrintToServer("Could not hook INextBot::IsEnemy(this,CBaseEntity*). Bots will shoot at protected players!");
	}
	if (hdl_CTFPlayer_ApplyGenericPushbackImpulse != INVALID_HANDLE && !detoured_CTFPlayer_ApplyGenericPushbackImpulse) {
		detoured_CTFPlayer_ApplyGenericPushbackImpulse = DHookEnableDetour(hdl_CTFPlayer_ApplyGenericPushbackImpulse, false, Detour_CTFPlayer_ApplyGenericPushbackImpulse);
	} else {
		PrintToServer("Could not hook CTFPlayer::ApplyGenericPushbackImpulse(Vector*,CTFPlayer*). This will be pushy!");
	}
	if (hdl_CObjectSentrygun_ValidTargetPlayer != INVALID_HANDLE && !detoured_CObjectSentrygun_ValidTargetPlayer) {
		detoured_CObjectSentrygun_ValidTargetPlayer = DHookEnableDetour(hdl_CObjectSentrygun_ValidTargetPlayer, false, Detour_CObjectSentrygun_ValidTargetPlayer);
	} else {
		PrintToServer("Could not hook CObjectSentrygun::ValidTargetPlayer(CTFPlayer*,Vector*,Vector*). Whack!");
	}
}
static void DHooksDetach() {
	if (hdl_INextBot_IsEnemy != INVALID_HANDLE && detoured_INextBot_IsEnemy)
		detoured_INextBot_IsEnemy ^= DHookDisableDetour(hdl_INextBot_IsEnemy, false, Detour_INextBot_IsEnemy);
	if (hdl_CTFPlayer_ApplyGenericPushbackImpulse != INVALID_HANDLE && detoured_CTFPlayer_ApplyGenericPushbackImpulse)
		detoured_CTFPlayer_ApplyGenericPushbackImpulse ^= DHookDisableDetour(hdl_CTFPlayer_ApplyGenericPushbackImpulse, false, Detour_CTFPlayer_ApplyGenericPushbackImpulse);
	if (hdl_CObjectSentrygun_ValidTargetPlayer != INVALID_HANDLE && detoured_CObjectSentrygun_ValidTargetPlayer)
		detoured_CObjectSentrygun_ValidTargetPlayer ^= DHookDisableDetour(hdl_CObjectSentrygun_ValidTargetPlayer, false, Detour_CObjectSentrygun_ValidTargetPlayer);
}

public void OnMapEnd() {
	forcePvP[0] = false;
}

public void OnMapStart() {
	UpdateActiveState(GameState_PreGame);
}
public void OnRoundStateChange(Event event, const char[] name, bool dontBroadcast) {
	if (StrEqual(name, "teamplay_waiting_begins")) { //pregame, waiting for players
		UpdateActiveState(GameState_PreGame|GameState_Waiting);
	} else if (StrEqual(name, "teamplay_waiting_ends")) { //pregame
		UpdateActiveState(GameState_PreGame);
	} else if (StrEqual(name, "teamplay_round_start") ||
			StrEqual(name, "teamplay_overtime_end") ||
			StrEqual(name, "teamplay_suddendeath_end")) { //running
		UpdateActiveState(GameState_Running);
	} else if (StrEqual(name, "teamplay_overtime_begin")) { //overtime
		UpdateActiveState(GameState_Overtime);
	} else if (StrEqual(name, "teamplay_suddendeath_begin")) { //sudden death
		UpdateActiveState(GameState_SuddenDeath);
	} else if (StrEqual(name, "teamplay_game_over") ||
			StrEqual(name, "teamplay_round_stalemate") ||
			StrEqual(name, "teamplay_round_win")) { //game over
		UpdateActiveState(GameState_GameOver);
	}
}
static void HotloadGameState() {
	RoundState round = GameRules_GetRoundState();
	if (round == RoundState_GameOver || round == RoundState_TeamWin || round == RoundState_Stalemate) {
		UpdateActiveState(GameState_GameOver);
	} else if (round == RoundState_Pregame || round == RoundState_Preround) {
		UpdateActiveState(GameState_PreGame);
	} else {
		UpdateActiveState(GameState_Running);
	}
}
static void UpdateActiveState(eGameState gameState) {
	bool wasActive = isActive;
	isActive = (activeGameStates & (currentGameState=gameState))!=GameState_Never;
	if (isActive != wasActive) {
		if (isActive) {
			CPrintToChatAll("%t", "Plugin now active");
			DHooksAttach();
		} else {
			CPrintToChatAll("%t", "Plugin now inactive");
			DHooksDetach();
		}
		for (int i=1;i<MaxClients;i++) {
			if (Client_IsIngame(i))
				UpdateEntityFlagsGlobalPvP(i, IsGlobalPvP(i));
		}
	}
}

public void OnClientConnected(int client) {
	globalPvP[client] = false;
	forcePvP[client] = false;
	SetPairPvPClient(client);
	pairPvPrequest[client]=0;
	pairPvPignored[client]=false;
	clientFirstSpawn[client]=true;
}
public void OnClientDisconnect(int client) {
	globalPvP[client] = false;
	forcePvP[client] = false;
	SetPairPvPClient(client);
	pairPvPrequest[client]=0;
	pairPvPignored[client]=false;
	clientFirstSpawn[client]=true;
	for (int i=1;i<=MaxClients;i++)
		if (pairPvPrequest[i]==client)
			pairPvPrequest[i]=0;
}

//region pretty much cookies
public void OnClientCookiesCached(int client) {
	if (IsFakeClient(client)) {
		//Bot cookies
		globalPvP[client] = true;
		pairPvPignored[client] = true;
		UpdateEntityFlagsGlobalPvP(client, true);
		return;
	}
	char buffer[2];
	Handle cookie;
	if (joinForceState!=0) {
		SetGlobalPvP(client, joinForceState<0);
	} else if((cookie = FindClientCookie(COOKIE_GLOBALPVP)) != null && GetClientCookie(client, cookie, buffer, sizeof(buffer)) && !StrEqual(buffer, "")) {
		globalPvP[client] = view_as<bool>(StringToInt(buffer));
		UpdateEntityFlagsGlobalPvP(client, IsGlobalPvP(client));
	}
	if((cookie = FindClientCookie(COOKIE_IGNOREPVP)) != null && GetClientCookie(client, cookie, buffer, sizeof(buffer)) && !StrEqual(buffer, "")) {
		pairPvPignored[client] = view_as<bool>(StringToInt(buffer));
	}
	delete cookie;
}

public void HandleCookieMenu(int client, CookieMenuAction action, any info, char[] buffer, int maxlen) {
	if(action == CookieMenuAction_SelectOption) {
		ShowCookieSettingsMenu(client);
	}
}
static void ShowCookieSettingsMenu(int client) {
	Menu menu = new Menu(HandlePvPCookieMenu);
	char buffer[MAX_MESSAGE_LENGTH];
	menu.SetTitle("%T", "SettingsMenuTitle", client);
	if (globalPvP[client]) {
		Format(buffer, sizeof(buffer), "[X] %T", "SettingsMenuGlobal", client);
		menu.AddItem("globalpvp", buffer);
	} else {
		Format(buffer, sizeof(buffer), "[ ] %T", "SettingsMenuGlobal", client);
		menu.AddItem("globalpvp", buffer);
	}
	if (pairPvPignored[client]) {
		Format(buffer, sizeof(buffer), "[X] %T", "SettingsMenuIgnorePair", client);
		menu.AddItem("ignorepvp", buffer);
	} else {
		Format(buffer, sizeof(buffer), "[ ] %T", "SettingsMenuIgnorePair", client);
		menu.AddItem("ignorepvp", buffer);
	}
	menu.ExitBackButton = true;
	menu.Display(client, 60);
}
public int HandlePvPCookieMenu(Menu menu, MenuAction action, int param1, int param2) {
	if (action == MenuAction_Select) {
		char info[32];
		menu.GetItem(param2, info, sizeof(info));
		if(StrEqual(info, "globalpvp")) {
			SetGlobalPvP(param1, !globalPvP[param1]);
		}
		if(StrEqual(info, "ignorepvp")) {
			SetPairPvPIgnored(param1, !pairPvPignored[param1]);
		}
		ShowCookieSettingsMenu(param1);
	} else if(action == MenuAction_Cancel && param2 == MenuCancel_ExitBack) {
		ShowCookieMenu(param1);
	} else if(action == MenuAction_End) {
		delete menu;
	}
}

//endregion

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
public void OnCVarChanged_NoTarget(ConVar convar, const char[] oldValue, const char[] newValue) {
	noTargetPlayers = convar.BoolValue;
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
		if (Client_IsIngame(i)&&IsPlayerAlive(i)) {
			UpdateEntityFlagsGlobalPvP(i, IsGlobalPvP(i));
		}
	}
}
//enregion

//region command and toggling/requesting pvp
bool TargetSelector_PVP(const char[] pattern, ArrayList clients) {
	bool invert = pattern[1]=='!';
	for (int i=1;i<=MaxClients;i++) {
		if (Client_IsIngame(i)) {
			if (globalPvP[i] ^ invert) {
				clients.Push(i);
			}
		}
	}
	return true;
}

public Action Command_TogglePvP(int client, int args) {
	if (GetCmdArgs()==0) {
		SetGlobalPvP(client, !globalPvP[client]);
	} else {
		char pattern[MAX_NAME_LENGTH+1], tname[MAX_NAME_LENGTH+1];
		GetCmdArgString(pattern, sizeof(pattern));
		int target[1];
		bool tn_is_ml;
		int matches = ProcessTargetString(pattern, client, target, 1, COMMAND_FILTER_CONNECTED|COMMAND_FILTER_NO_IMMUNITY|COMMAND_FILTER_NO_MULTI, tname, sizeof(tname), tn_is_ml);
		if (matches != 1 || tn_is_ml || target[0] == client) {
			//ReplyToTargetError(client, matches);
			ShowPlayerPairPvPMenu(client);
		} else {
			RequestPairPvP(client, target[0]);
		}
	}
	return Plugin_Handled;
}
static void ShowPlayerPairPvPMenu(int client) {
	Menu menu = new Menu(HandlePickPlayerMenu);
	menu.SetTitle("%T", "Pick player for pvp", client);
	char buid[6], bnick[65];
	for (int i=1;i<MaxClients;i++) {
		if (i==client || !Client_IsIngame(i)) continue;
		Format(buid, sizeof(buid), "%d", GetClientUserId(i));
		Format(bnick, sizeof(bnick), "%N", i);
		menu.AddItem(buid, bnick);
	}
	menu.Pagination = 7;
	menu.ExitButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}
public int HandlePickPlayerMenu(Menu menu, MenuAction action, int param1, int param2) {
	if (action == MenuAction_End) {
		delete menu;
	} else if (action == MenuAction_Select) {
		char buid[6];
		menu.GetItem(param2, buid, sizeof(buid));
		int target = GetClientOfUserId(StringToInt(buid));
		if (!Client_IsIngame(target)) {
			CPrintToChat(param1, "%t", "Player no longer available");
			ShowPlayerPairPvPMenu(param1);
		} else {
			RequestPairPvP(param1, target);
		}
	}
}

public Action Command_ForcePvP(int client, int args) {
	if (GetCmdArgs()!=2) {
		char name[16];
		GetCmdArg(0, name, sizeof(name));
		ReplyToCommand(client, "Usage: %s <target|'map'> <1/0>", name);
	} else {
		char pattern[MAX_NAME_LENGTH+1], tname[MAX_NAME_LENGTH+1];
		GetCmdArg(2,pattern, sizeof(pattern));
		bool pvpon = StringToInt(pattern) != 0;
		GetCmdArg(1,pattern, sizeof(pattern));
		if (StrEqual(pattern, "map", false)) {
			forcePvP[0] = pvpon;
			for (int i=1;i<=MaxClients;i++) {
				if (!Client_IsIngame(i) || IsFakeClient(i)) continue;
				if (!pvpon) forcePvP[i] = false; //turn off previously individually set flags
				UpdateEntityFlagsGlobalPvP(i, pvpon||globalPvP[i]);
			}
			CSkipNextClient(client);
			if (pvpon) {
				CPrintToChatAll("%t", "Someone forced map pvp", client);
				CReplyToCommand(client, "%t", "You forced map pvp");
			} else {
				CPrintToChatAll("%t", "Someone reset map pvp", client);
				CReplyToCommand(client, "%t", "You reset map pvp");
			}
		} else {
			int target[MAXPLAYERS];
			bool tn_is_ml;
			int matches = ProcessTargetString(pattern, client, target, 1, COMMAND_FILTER_CONNECTED|COMMAND_FILTER_NO_IMMUNITY, tname, sizeof(tname), tn_is_ml);
			if (matches < 1) {
				ReplyToTargetError(client, matches);
			} else {
				CSkipNextClient(client);
				if (pvpon) {
					CPrintToChatAll("%t","Someone forced your global pvp", client);
					CReplyToCommand(client, "%t", "You forced someones global pvp", tname);
				} else {
					CPrintToChatAll("%t","Someone reset your global pvp", client);
					CReplyToCommand(client, "%t", "You reset someones global pvp", tname);
				}
				for (int i;i<matches;i++) {
					int player = target[i];
					if (!Client_IsIngame(i) ||IsFakeClient(player)) continue;
					forcePvP[player] = pvpon;
					UpdateEntityFlagsGlobalPvP(player, IsGlobalPvP(player));
				}
			}
		}
	}
	return Plugin_Handled;
}

public Action Command_StopPvP(int client, int args) {
	if (HasAnyPairPvP(client)) {
		EndAllPairPvPFor(client);
		CPrintToChat(client, "%t", "Use command again to toggle ignore");
	} else {
		SetPairPvPIgnored(client, !pairPvPignored[client]);
	}
	return Plugin_Handled;
}

static void RequestPairPvP(int requester, int requestee) {
	if (requester == requestee) {
		//silent fail
	} else if (IsFakeClient(requestee)) {
		CPrintToChat(requester, "%t", "Bots can not use pair pvp");
	} else if (pairPvP[requester][requestee]) {
		CPrintToChat(requestee, "%t", "Someone disengaged pair pvp", requester);
		CPrintToChat(requester, "%t", "You disengaged pair pvp", requestee);
		pairPvPrequest[requester]=pairPvPrequest[requestee]=0;
		SetPairPvP(requester,requestee,false);
	} else if (pairPvPrequest[requestee]==requester) {
		CPrintToChat(requestee, "%t", "You engaged pair pvp", requester);
		CPrintToChat(requester, "%t", "You engaged pair pvp", requestee);
		pairPvPrequest[requester]=pairPvPrequest[requestee]=0;
		SetPairPvP(requester,requestee,true);
	} else if (globalPvP[requester] && globalPvP[requestee]) {
		CPrintToChat(requester, "%t", "You are both global pvp");
	} else if (pairPvPrequest[requester]==requestee) {
		CPrintToChat(requester, "%t", "Already requested pvp with", requestee);
	} else {
		if (Client_IsValid(pairPvPrequest[requester])) {
			CPrintToChat(pairPvPrequest[requester], "%t", "Someone cancelled pvp request for another", requester);
			CPrintToChat(requester, "%t", "You cancelled pvp request", pairPvPrequest[requester]);
		}
		CPrintToChat(requestee, "%t", "Someone requested pvp, confirm", requester, requester);
		CPrintToChat(requester, "%t", "You requested pvp", requestee);
		pairPvPrequest[requester] = requestee;
	}
}
static void DeclinePairPvP(int requestee) {
	int declined,someRequester=0;
	for (int requester=1; requester<=MaxClients; requester++) {
		if (Client_IsValid(requester) && pairPvPrequest[requester]==requestee) {
			CPrintToChat(requester, "%t", "Your pvp request was declined", requestee);
			pairPvPrequest[requester] = 0;
			someRequester = requester;
			declined++;
		}
	}
	if (declined>1) {
		CPrintToChat(requestee, "%t", "You declined multiple pvp requests", declined);
	} else if (declined==1) {
		CPrintToChat(requestee, "%t", "You declined single pvp request", someRequester);
	}
}
static void EndAllPairPvPFor(int client) {
	for (int i=1;i<=MaxClients;i++) {
		if (pairPvP[client][i]) {
			CPrintToChat(i, "%t", "Someone disengaged pair pvp", client);
		}
	}
	SetPairPvPClient(client, false);
	CPrintToChat(client, "%t", "You disengaged all pair pvp");
}
//endregion

//region utilities to set and check pvp flags
static void PrintGlobalPvpState(int client) {
	if (!IsClientInGame(client) || IsFakeClient(client) || GetClientTime(client)<2.0) return;
	if (globalPvP[client]) {
		CPrintToChat(client, "%t", "Global pvp state on line1");
		CPrintToChat(client, "%t", "Global pvp state on line2");
	} else {
		CPrintToChat(client, "%t", "Global pvp state off line1");
		CPrintToChat(client, "%t", "Global pvp state off line2");
	}
	CPrintToChat(client, "%t", "Hey there's also pair pvp");
}
static void SetGlobalPvP(int client, bool pvp) {
	Handle cookie;
	globalPvP[client] = pvp;
	if((cookie = FindClientCookie(COOKIE_GLOBALPVP)) != null) {
		char value[2]="0";
		if (pvp) value[0]='1';
		SetClientCookie(client, cookie, value);
	}
	delete cookie;
	UpdateEntityFlagsGlobalPvP(client, IsGlobalPvP(client));
	PrintGlobalPvpState(client);
}
static void SetPairPvPIgnored(int client, bool ignore) {
	Handle cookie;
	pairPvPignored[client] = ignore;
	if((cookie = FindClientCookie(COOKIE_IGNOREPVP)) != null) {
		char value[2]="0";
		if (ignore) value[0]='1';
		SetClientCookie(client, cookie, value);
	}
	delete cookie;
	if (ignore) {
		DeclinePairPvP(client);
		CPrintToChat(client, "%t", "You are ignoring pair pvp");
	} else {
		CPrintToChat(client, "%t", "You are allowing pair pvp");
	}
}
static void SetPairPvP(int client1, int client2, bool pvp) {
	pairPvP[client1][client2] = pairPvP[client2][client1] = pvp;
}
static void SetPairPvPClient(int client, bool pvp=false) {
	for (int i=1;i<=MaxClients;i++) {
		pairPvP[client][i] = pairPvP[i][client] = pvp;
	}
}
static bool HasAnyPairPvP(int client) {
	for (int i=1;i<=MaxClients;i++) {
		if (pairPvP[client][i]) return true;
	}
	return false;
}
/**
 * if the entity is a client, return the client. otherwise try to resolve m_hBuilder
 * @return the player associated with this entity or INVALID_ENT_REFERENCE if none
 */
static int GetPlayerEntity(int entity) {
	if (1<=entity<=MaxClients) {
		return entity;
	} else if (HasEntProp(entity, Prop_Send, "m_hBuilder")) {
		int tmp=GetEntPropEnt(entity, Prop_Send, "m_hBuilder");
		if (1<=tmp<=MaxClients)
			return tmp;
	}
	return INVALID_ENT_REFERENCE;
}
static bool CanClientsPvP(int client1, int client2) {
	return client1==client2 || forcePvP[0] || (IsGlobalPvP(client1) && IsGlobalPvP(client2)) || pairPvP[client1][client2];
}
//static bool CanEntitiesPvP(int entity1, int entity2) {
//	int tmp,client1=GetPlayerEntity(entity1),client2=GetPlayerEntity(entity2);
//	return client1 != INVALID_ENT_REFERENCE && client2 != INVALID_ENT_REFERENCE && CanClientsPvP(client1, client2);
//}
//endregion

//region actual damage blocking and entity stuff

// this dhook simply makes bots ignore players that dont want to pvp
public MRESReturn Detour_INextBot_IsEnemy(Address pThis, DHookReturn hReturn, DHookParam hParams) {
	int target = hParams.Get(1);
	int player = GetPlayerEntity(target);
	if (player != INVALID_ENT_REFERENCE && !IsGlobalPvP(player) && !forcePvP[0]) {
		hReturn.Value = false;
		return MRES_Override;
	}
	return MRES_Ignored;
}

public MRESReturn Detour_CTFPlayer_ApplyGenericPushbackImpulse(int player, DHookParam hParams) {
//	float impulse[3]; hParams.GetVector(1, impulse);
	if (hParams.IsNull(2)) return MRES_Ignored;
	int source = hParams.Get(2);
	if (Client_IsValid(source) && !CanClientsPvP(source,player))
		return MRES_Supercede;//don't call original to apply force
	return MRES_Ignored;
}

public MRESReturn Detour_CObjectSentrygun_ValidTargetPlayer(int building, DHookReturn hReturn, DHookParam hParams) {
//	float impulse[3]; hParams.GetVector(1, impulse);
	if (hParams.IsNull(1)) return MRES_Ignored;
	int player = hParams.Get(1);
	int engi = GetPlayerEntity(building);
	if (Client_IsValid(player) && Client_IsValid(engi) && !CanClientsPvP(engi,player)) {
		hReturn.Value = false;
		return MRES_Override;//idk what whacky stuff valve is doing there
	}
	return MRES_Ignored;
}

//keep as simple and quick as possible
//don't check result, that does NOT pass the previous result!
public Action CH_PassFilter(int ent1, int ent2, bool &result) {
	if (noCollideState && 1<=ent1<=MaxClients && 1<=ent2<=MaxClients) {
		//pass 1, collision mod is on and we have clients
		int team1 = GetClientTeam(ent1);
		int team2 = GetClientTeam(ent2);
		if (team1 != team2 && team1 > 1 && team2 > 1 && (noCollideState > 1 || !CanClientsPvP(ent1, ent2))) {
			//pass2, clients are on different teams and can not pvp (or override): treat as same team (aka friendly)
			result = false;
			return Plugin_Changed;
		}
	}
	return Plugin_Continue;
}

public void OnEntityCreated(int entity, const char[] classname) {
	if (StrEqual(classname, "player")) {
		SDKHookClient(entity);
	}
}

static void SDKHookClient(int client) {
	SDKHook(client, SDKHook_OnTakeDamage, OnClientTakeDamage);
	SDKHook(client, SDKHook_SpawnPost, OnClientSpawnPost);
}

public Action OnClientTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &weapon, float damageForce[3], float damagePosition[3]) {
	if (!isActive || !Client_IsValid(attacker) || CanClientsPvP(victim, attacker)) {
		//allow damage
		return Plugin_Continue;
	}
	//block damage
	damage = 0.0;
	ScaleVector(damageForce, 0.0);
	return Plugin_Handled;
}
static void OnClientSpawnPost(int client) {
	if (GetClientTeam(client)<=1 || IsFakeClient(client)) return;
	UpdateEntityFlagsGlobalPvP(client, globalPvP[client]);
	if (clientFirstSpawn[client]) {
		clientFirstSpawn[client] = false;
		PrintGlobalPvpState(client);
	}
}
public void OnInventoryApplicationPost(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	UpdateEntityFlagsGlobalPvP(client, globalPvP[client]);
}

public void TF2_OnConditionAdded(int client, TFCond condition) {
	int provider;
	if (!isActive) return;
	if (ArrayFind(condition, pvpConditions, sizeof(pvpConditions))>=0 &&
		(provider = TF2Util_GetPlayerConditionProvider(client, condition))>0 &&
		!CanClientsPvP(client, provider)) {
		TF2_RemoveCondition(client, condition);
	}
}

static void UpdateEntityFlagsGlobalPvP(int client, bool pvp) {
	if (!Client_IsIngame(client)) return;
	int ci;
	if (TF2_GetClientTeam(client)==TFTeam_Blue) ci++;
	if (pvp || !isActive) {
		if (noTargetPlayers)
			SetEntityFlags(client, GetEntityFlags(client) &~ (FL_NOTARGET));
	} else {
		if (noTargetPlayers)
			SetEntityFlags(client, GetEntityFlags(client) | FL_NOTARGET);
		ci+=2;
	}
	if (usePlayerStateColors)
		SetPlayerColor(client, playerStateColors[ci][0], playerStateColors[ci][1], playerStateColors[ci][2], playerStateColors[ci][3]);
}

//endregion

//region natives

//TODO

//endregion

//region other trash

static void SetPlayerColor(int client, int r=255, int g=255, int b=255, int a=255) {
	for (int entity=1; entity<2048; entity++) {
		if (IsValidEntity(entity) && (entity == client || (HasEntProp(entity, Prop_Send, "m_hOwnerEntity") && GetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity")==client)) ) {
			if (a==255) {
				SetEntityRenderMode(entity, RENDER_NORMAL);
			} else {
				SetEntityRenderMode(entity, RENDER_TRANSALPHA);
			}
			SetEntityRenderColor(entity, r,g,b,a);
		}
	}
}
/**
 * Use -1 for haystacksize if the array is 0-terminated, -2 if it is negative-terminated
 */
static int ArrayFind(any needle, const any[] haystack, int haystacksize=0) {
	for (int i=0;i<haystacksize;i++) {
		any val = haystack[i];
		if (val == 0 && haystacksize == -1) break;
		else if ((val&0x80000000) && haystacksize == -2) break; //negative signum bit for 2comp integers and ieee floats
		else if (val == needle) return i;
	}
	return -1;
}

//endregion
