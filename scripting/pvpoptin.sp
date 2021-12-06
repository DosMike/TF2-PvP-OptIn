#include <sourcemod>
#include <tf2_stocks>
#include <sdkhooks>
#include <clientprefs>
#include <morecolors>
#include <smlib>
#include <collisionhook>
#include <dhooks>
#include <tf2utils>

#define PLUGIN_VERSION "21w49a"
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

static bool globalPvP[MAXPLAYERS+1];
static bool pairPvP[MAXPLAYERS+1][MAXPLAYERS+1];
static int pairPvPrequest[MAXPLAYERS+1];
static bool pairPvPignored[MAXPLAYERS+1];
static bool clientFirstSpawn[MAXPLAYERS+1];
static DHookSetup hdl_INextBot_IsEnemy;

static ConVar cvar_JoinForceState;
static int joinForceState;
static ConVar cvar_NoCollide;
static int noCollideState;
static ConVar cvar_NoTarget;
static bool noTargetPlayers;
static ConVar cvar_UsePlayerColors;
static bool usePlayerStateColors;
static ConVar cvar_ColorGlobalOnRed;
static ConVar cvar_ColorGlobalOnBlu;
static ConVar cvar_ColorGlobalOffRed;
static ConVar cvar_ColorGlobalOffBlu;
static int playerStateColors[4][4];

#define COOKIE_GLOBALPVP "enableGlobalPVP"
#define COOKIE_IGNOREPVP "ignorePairPVP"

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
		delete nbdata;
	}
	if (hdl_INextBot_IsEnemy != INVALID_HANDLE) {
		DHookEnableDetour(hdl_INextBot_IsEnemy, true, Detour_INextBot_IsEnemy);
	} else {
		PrintToServer("Could not hook INextBot::IsEnemy(this,CBaseEntity*). Bots will shoot at protected players!");
	}
	
	RegClientCookie(COOKIE_GLOBALPVP, "Client has opted into global PvP", CookieAccess_Public);
	
	RegConsoleCmd("sm_pvp", Command_TogglePvP, "Usage: [name|userid] - If you specify a user, request pair PvP, otherwise toggle global PvP");
	RegConsoleCmd("sm_stoppvp", Command_StopPvP, "End all pair PvP or toggle pair PvP ignore state if you're not in pair PvP");
	
	HookEvent("post_inventory_application", OnInventoryApplicationPost);
	
	cvar_JoinForceState = CreateConVar( "pvp_joinoverride", "0", "Define global PvP State when player joins. 0 = Load player choice, 1 = Force out of PvP, -1 = Force enable PvP", FCVAR_ARCHIVE, true, -1.0, true, 1.0);
	cvar_NoCollide = CreateConVar( "pvp_nocollide", "1", "Can be used to disable player collision between enemies. 0 = Don't change, 1 = with global pvp disabled, 2 = never collied", FCVAR_ARCHIVE, true, 0.0, true, 2.0);
	cvar_NoTarget = CreateConVar( "pvp_notarget", "1", "Add NOTARGET to players outside global pvp for sentries. Bots ignore this! Can be disabled for compatibility", FCVAR_ARCHIVE, true, 0.0, true, 1.0);
	cvar_UsePlayerColors = CreateConVar( "pvp_playertaint_enable", "1", "Can be used to disable player tainting based on pvp state", FCVAR_ARCHIVE, true, 0.0, true, 1.0);
	cvar_ColorGlobalOnRed = CreateConVar( "pvp_playertaint_redon", "125 125 255", "Color for players on RED with global PvP enabled. Argument is R G B A from 0 to 255 or web color #RRGGBBAA. Alpha is optional.", FCVAR_ARCHIVE);
	cvar_ColorGlobalOnBlu = CreateConVar( "pvp_playertaint_bluon", "255 125 125", "Color for players on BLU with global PvP enabled. Argument is R G B A from 0 to 255 or web color #RRGGBBAA. Alpha is optional.", FCVAR_ARCHIVE);
	cvar_ColorGlobalOffRed = CreateConVar( "pvp_playertaint_redoff", "255 255 225", "Color for players on RED with global PvP disabled. Argument is R G B A from 0 to 255 or web color #RRGGBBAA. Alpha is optional.", FCVAR_ARCHIVE);
	cvar_ColorGlobalOffBlu = CreateConVar( "pvp_playertaint_bluoff", "255 255 225", "Color for players on BLU with global PvP disabled. Argument is R G B A from 0 to 255 or web color #RRGGBBAA. Alpha is optional.", FCVAR_ARCHIVE);
	//hook cvars and load current values
	hookAndLoadCvar(cvar_JoinForceState, OnCVarChanged_JoinForceState);
	hookAndLoadCvar(cvar_NoCollide, OnCVarChanged_NoCollision);
	hookAndLoadCvar(cvar_NoTarget, OnCVarChanged_NoTarget);
	hookAndLoadCvar(cvar_UsePlayerColors, OnCVarChanged_UsePlayerTaint);
	hookAndLoadCvar(cvar_ColorGlobalOnRed, OnCVarChanged_PlayerTaint);
	hookAndLoadCvar(cvar_ColorGlobalOnBlu, OnCVarChanged_PlayerTaint);
	hookAndLoadCvar(cvar_ColorGlobalOffRed, OnCVarChanged_PlayerTaint);
	hookAndLoadCvar(cvar_ColorGlobalOffBlu, OnCVarChanged_PlayerTaint);
	//create fancy plugin config - should be sourcemod/pvpoptin.cfg
	AutoExecConfig();
	
	SetCookieMenuItem(HandleCookieMenu, 0, "PvP");
	for (int i=1;i<=MaxClients;i++) {
		if(IsClientConnected(i)) {
			OnClientConnected(i);
			if (IsClientInGame(i))
				SDKHookClient(i);
			if (AreClientCookiesCached(i))
				OnClientCookiesCached(i);
			if (IsPlayerAlive(i))
				OnClientSpawnPost(i);
		}
	}
}
public void OnPluginEnd() {
	if (hdl_INextBot_IsEnemy != INVALID_HANDLE)
		DHookDisableDetour(hdl_INextBot_IsEnemy, true, Detour_INextBot_IsEnemy);
}

public void OnClientConnected(int client) {
	globalPvP[client] = false;
	SetPairPvPClient(client);
	pairPvPrequest[client]=0;
	pairPvPignored[client]=false;
	clientFirstSpawn[client]=true;
}
public void OnClientDisconnect(int client) {
	globalPvP[client] = false;
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
		UpdateEntityFlagsGlobalPvP(client, globalPvP[client]);
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
	menu.SetTitle("%T", client, "SettingsMenuTitle");
	if (globalPvP[client]) {
		Format(buffer, sizeof(buffer), "[X] %T", client, "SettingsMenuGlobal");
		menu.AddItem("globalpvp", buffer);
	} else {
		Format(buffer, sizeof(buffer), "[ ] %T", client, "SettingsMenuGlobal");
		menu.AddItem("globalpvp", buffer);
	}
	if (pairPvPignored[client]) {
		Format(buffer, sizeof(buffer), "[X] %T", client, "SettingsMenuIgnorePair");
		menu.AddItem("ignorepvp", buffer);
	} else {
		Format(buffer, sizeof(buffer), "[ ] %T", client, "SettingsMenuIgnorePair");
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
public void OnCVarChanged_JoinForceState(ConVar convar, const char[] oldValue, const char[] newValue) {
	joinForceState = convar.IntValue;
}
public void OnCVarChanged_NoCollision(ConVar convar, const char[] oldValue, const char[] newValue) {
	noCollideState = convar.IntValue;
}
public void OnCVarChanged_NoTarget(ConVar convar, const char[] oldValue, const char[] newValue) {
	noTargetPlayers = convar.BoolValue;
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
			UpdateEntityFlagsGlobalPvP(i, globalPvP[i]);
		}
	}
}
//enregion

//region command and toggling/requesting pvp
public Action Command_TogglePvP(int client, int args) {
	if (GetCmdArgs()==0) {
		SetGlobalPvP(client, !globalPvP[client]);
	} else {
		char pattern[MAX_NAME_LENGTH+1], tname[MAX_NAME_LENGTH+1];
		GetCmdArgString(pattern, sizeof(pattern));
		int target[1];
		bool tn_is_ml;
		int matches = ProcessTargetString(pattern, client, target, 1, COMMAND_FILTER_CONNECTED|COMMAND_FILTER_NO_IMMUNITY|COMMAND_FILTER_NO_MULTI, tname, sizeof(tname), tn_is_ml);
		if (matches != 1 || tn_is_ml) {
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
	menu.SetTitle("%T",client,"Pick player for pvp");
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

public Action Command_StopPvP(int client, int args) {
	if (HasAnyPairPvP(client)) {
		EndAllPairPvPFor(client);
		CPrintToChat(client, "{darkviolet}[PvP]{default} Use the command again to ignore further requests");
	} else {
		SetPairPvPIgnored(client, !pairPvPignored[client]);
	}
	return Plugin_Handled;
}

static void RequestPairPvP(int requester, int requestee) {
	if (IsFakeClient(requestee)) {
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
		CPrintToChat(requestee, "You declined multiple pvp requests", declined);
	} else if (declined==1) {
		CPrintToChat(requestee, "You declined single pvp request", someRequester);
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
	UpdateEntityFlagsGlobalPvP(client, pvp);
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
static bool CanClientsPvP(int client1, int client2) {
	return (globalPvP[client1] && globalPvP[client2]) || pairPvP[client1][client2];
}
//endregion

//region actual damage blocking and entity stuff

// this dhook simply makes bots ignore players that dont want to pvp
public MRESReturn Detour_INextBot_IsEnemy(Address pThis, DHookReturn hReturn, DHookParam hParams) {
	int target = hParams.Get(1);
	if (hReturn.Value) {
		int player;
		if ((1<=target<=MaxClients)) {
			player = target;
		} else if (HasEntProp(target, Prop_Send, "m_hBuilder")) {
			int owner = GetEntPropEnt(target, Prop_Send, "m_hBuilder");
			if ((1<= owner <=MaxClients)) player = owner;
		}
		if (player && !globalPvP[player]) {
			hReturn.Value = false;
			return MRES_Override;
		}
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
	if (!Client_IsValid(attacker) || CanClientsPvP(victim, attacker)) {
		return Plugin_Continue;
	}
	damage = 0.0;
	ScaleVector(damageForce, 0.0);
	return Plugin_Handled;
}
static void OnClientSpawnPost(int client) {
	if (GetClientTeam(client)<=1) return;
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
	if (ArrayFind(condition, pvpConditions, sizeof(pvpConditions))>=0 &&
		(provider = TF2Util_GetPlayerConditionProvider(client, condition))>0 &&
		provider != client && !CanClientsPvP(client, provider)) {
		TF2_RemoveCondition(client, condition);
	}
}

static void UpdateEntityFlagsGlobalPvP(int client, bool pvp) {
	if (!Client_IsIngame(client)) return;
	int ci;
	if (TF2_GetClientTeam(client)==TFTeam_Blue) ci++;
	if (pvp) {
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
