#include <sourcemod>
#include <tf2_stocks>
#include <sdkhooks>
#include <clientprefs>
#include <morecolors>
#include <smlib>
#include <collisionhook>
#include <dhooks>
#include <tf2utils>
#undef REQUIRE_PLUGIN
#include <nativevotes>
#define REQUIRE_PLUGIN

#define PLUGIN_VERSION "22w14a"
#pragma newdecls required
#pragma semicolon 1

// Credits in steamIDs:
//  reBane [U:1:62840121] - code
//  Fuffeh [U:1:5214002] - relations
//  FancyNight [U:1:160000225] - sprite work
//  sigmarune [U:1:154407981] - particle effect
// even tho the particle can't be used for normal servers I'll keep you listed :)
public Plugin myinfo = {
	name = "[TF2] Opt In PvP",
	author = "reBane, Fuffeh, FancyNight, sigmarune",
	description = "Opt In PvP for LazyPurple Silly Servers",
	version = PLUGIN_VERSION,
	url = "https://github.com/DosMike/TF2-PvP-OptIn"
}

// ----- setting type defines here, you can probably change the values -----

#define PvP_DISENGAGE_COOLDOWN 30.0
#define PvP_PAIRREQUEST_COOLDOWN 15.0
#define PvP_PAIRVOTE_DISPLAYTIME 10

//#define PVP_PARTICLE "pvpoptin_indicator"
#define PVP_PARTICLE "mark_for_death"
// the offset should be 0.0 for the custom particle, 16.0 is good for marked for death
#define PVP_PARTICLE_OFFSET 16.0

// ----------      other stuff below - better don''t touch ;)      ----------

#include "pvpoptin/common.sp"

bool depNativeVotes; //is NativeVotes loaded?

bool isActive; //plugin active flag changed depending on game state
eGameState currentGameState;
eEnabledState globalPvP[MAXPLAYERS+1]; //have turned global pvp on
eEnabledState mirrorDamage[MAXPLAYERS+1]; //will never mirror if CanClientsPvP returns true
bool allowTauntKilled[MAXPLAYERS+1];
bool allowLimitedConditions[MAXPLAYERS+1]; //stuff like jarated, etc is ok for this player
bool pairPvP[MAXPLAYERS+1][MAXPLAYERS+1]; //double reffed so order doesn't matter for quicker lookups
int pairPvPrequest[MAXPLAYERS+1]; //invite requests
bool pairPvPignored[MAXPLAYERS+1]; //invites disabled
bool clientFirstSpawn[MAXPLAYERS+1]; //delay reminder message untill first actual spawn
float clientLatestPvPAction[MAXPLAYERS+1]; //prevent "dodgeing" damage with pvp toggles by blocking leaving pvp for some time. (entering, attacking, getting attacked)
float clientLatestPvPRequest[MAXPLAYERS+1]; //prevent spamming people with too many pair pvp requests by blocking requests for some time
int clientParticleAttached[MAXPLAYERS+1]; //simple tracking for players that should currently be playing the pvp particle
bool clientForceUpdateParticle[MAXPLAYERS+1];
int clientPvPBannedUntil[MAXPLAYERS+1]; //int max value requires 10 chars
char clientPvPBannedReason[MAXPLAYERS+1][90]; //client prefs values are a varchar(100)
//maybe have client settings overwrite zombie/boss behaviour (force attack me)
float clientSpawnTime[MAXPLAYERS+1]; //game time the client last spawned (to allow bots)
int clientSpawnKillScore[MAXPLAYERS+1]; //score tracker for spawn killers - slowly decay over time, count up base on client alive time

#define COOKIE_GLOBALPVP "enableGlobalPVP"
#define COOKIE_IGNOREPVP "ignorePairPVP"
#define COOKIE_TAUNTKILL "canBeTauntKilled"
#define COOKIE_MIRRORME "mirrorPvPDamage"
#define COOKIE_CONDITIONS "allowConditions"
#define COOKIE_BANDATA "pvpBanned"

#define IsGlobalPvP(%1) (globalPvP[%1]!=State_Disabled && !(globalPvP[%1]&State_ExternalOff))
#define IsMirrored(%1) (mirrorDamage[%1]!=State_Disabled && !(mirrorDamage[%1]&State_ExternalOff))

#include "pvpoptin/utils.sp"
#include "pvpoptin/config.sp"
#include "pvpoptin/dtours.sp"
#include "pvpoptin/api.sp"

public void OnPluginStart() {
	LoadTranslations("common.phrases");
	LoadTranslations("pvpoptin.phrases");
	
	Plugin_SetupDHooks();
	
	delete RegClientCookie(COOKIE_GLOBALPVP, "Client has opted into global PvP", CookieAccess_Private);
	delete RegClientCookie(COOKIE_IGNOREPVP, "Client wants to ignore pair PvP", CookieAccess_Private);
	delete RegClientCookie(COOKIE_MIRRORME, "Mirror all damage out of PvP back to self", CookieAccess_Private);
	delete RegClientCookie(COOKIE_TAUNTKILL, "Client is fine with being taunt-killed for funnies", CookieAccess_Private);
	delete RegClientCookie(COOKIE_CONDITIONS, "Client is fine with being jarated, etc for funnies", CookieAccess_Private);
	delete RegClientCookie(COOKIE_BANDATA, "Formatted <Timestamp> <Reason> if banned from pvp", CookieAccess_Private);
	
	RegConsoleCmd("sm_pvp", Command_TogglePvP, "Usage: [name|userid] - If you specify a user, request pair PvP, otherwise toggle global PvP");
	RegConsoleCmd("sm_stoppvp", Command_StopPvP, "Decline pair PvP requests, end all pair PvP or toggle pair PvP ignore state if you're not in pair PvP");
	RegConsoleCmd("sm_rejectpvp", Command_StopPvP, "Decline pair PvP requests, end all pair PvP or toggle pair PvP ignore state if you're not in pair PvP");
	RegConsoleCmd("sm_declinepvp", Command_StopPvP, "Decline pair PvP requests, end all pair PvP or toggle pair PvP ignore state if you're not in pair PvP");
	RegConsoleCmd("sm_mirrorme", Command_MirrorMe, "Turn on mirror damage for attacking non-PvP players");
	RegAdminCmd("sm_forcepvp", Command_ForcePvP, ADMFLAG_SLAY, "Usage: <target|'map'> <1/0> - Force the targets into global PvP; 'map' applies to players that will join as well; Resets on map change");
	RegAdminCmd("sm_mirror", Command_Mirror, ADMFLAG_SLAY, "Usage: <target> <1/0> - Force mirror with non-PvP players for the target");
	RegAdminCmd("sm_fakepvprequest", Command_ForceRequest, ADMFLAG_CHEATS, "Usage: <requester|userid> <requestee|userid> - Force request pvp from another users perspective");
	RegAdminCmd("sm_banpvp", Command_BanPvP, ADMFLAG_BAN, "Usage: <name|userid> [<minutes> [reason]] - Ban a player from taking part in pvp");
	RegAdminCmd("sm_unbanpvp", Command_UnbanPvP, ADMFLAG_BAN, "Usage: <name|userid> - Unban a player from pvp");
	
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
	
	Plugin_SetupConvars();
	
	Plugin_SetupForwards();
	
	SetCookieMenuItem(HandleCookieMenu, 0, "PvP");
	bool hotload;
	for (int i=1;i<=MaxClients;i++) {
		if(IsClientConnected(i)) {
			OnClientConnected(i);
			if (IsClientInGame(i)) {
				SDKHookClient(i);
				if (AreClientCookiesCached(i))
					OnClientCookiesCached(i);
				if (IsPlayerAlive(i)) {
					OnClientSpawnPost(i);
					hotload = true;
				}
			}
		}
	}
	if (hotload) RequestFrame(HotloadGameState);
}
public void OnAllPluginsLoaded() {
	depNativeVotes = LibraryExists("nativevotes");
}

public void OnPluginEnd() {
	DHooksDetach();
	for (int client=1;client<=MaxClients;client++) {
		if (Client_IsIngameAuthorized(client)) {
			ParticleEffectStop(client);
		}
	}
}

public void OnLibraryAdded(const char[] name) {
	if (StrEqual(name, "nativevotes")) depNativeVotes = true;
}

public void OnLibraryRemoved(const char[] name) {
	if (StrEqual(name, "nativevotes")) depNativeVotes = false;
}

public void OnMapEnd() {
	globalPvP[0] = State_Disabled;
}

public void OnMapStart() {
	UpdateActiveState(GameState_PreGame);
	
//	PrecacheGeneric("particles/pvpoptin_pvpicon.pcf", true);
	PrecacheParticleSystem(PVP_PARTICLE);
	CreateTimer(5.0, Timer_PvPParticles, _, TIMER_FLAG_NO_MAPCHANGE|TIMER_REPEAT);
	CreateTimer(1.0, Timer_SpawnKillScoreDecay, _, TIMER_FLAG_NO_MAPCHANGE|TIMER_REPEAT);
}
public void TF2_OnWaitingForPlayersStart() {
	UpdateActiveState(GameState_Waiting);
}
public void TF2_OnWaitingForPlayersEnd() {
	UpdateActiveState(GameState_PreGame);
}
public void OnRoundStateChange(Event event, const char[] name, bool dontBroadcast) {
	if (StrEqual(name, "teamplay_round_start") ||
			StrEqual(name, "teamplay_overtime_end") ||
			StrEqual(name, "teamplay_suddendeath_end")) { //running
		if (currentGameState&GameState_Waiting != GameState_Waiting)
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
	//load actual game state
	RoundState round = GameRules_GetRoundState();
	if (round == RoundState_GameOver || round == RoundState_TeamWin || round == RoundState_Stalemate) {
		UpdateActiveState(GameState_GameOver);
	} else if (round == RoundState_Pregame || round == RoundState_Preround) {
		UpdateActiveState(GameState_PreGame);
	} else {
		UpdateActiveState(GameState_Running);
	}
	//hook all non-player entities again
	char classname[96];
	for (int i=MaxClients+1;i<2048;i++) {
		if (IsValidEdict(i)) {
			GetEntityClassname(i, classname, sizeof(classname));
			OnEntityCreated(i, classname);
		}
	}
}
void UpdateActiveState(eGameState gameState) {
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
	globalPvP[client] = State_Disabled;
	SetPairPvPClient(client);
	pairPvPrequest[client] = 0;
	pairPvPignored[client] = false;
	clientFirstSpawn[client] = true;
	allowTauntKilled[client] = false;
	allowLimitedConditions[client] = false;
	mirrorDamage[client] = State_Disabled;
	clientLatestPvPAction[client] = -PvP_DISENGAGE_COOLDOWN;
	clientLatestPvPRequest[client] = -PvP_PAIRREQUEST_COOLDOWN;
	clientParticleAttached[client] = 0;
	clientPvPBannedUntil[client] = 0;
	clientPvPBannedReason[client][0] = 0;
	clientForceUpdateParticle[client] = false;
	clientSpawnTime[client] = 0.0;
	clientSpawnKillScore[client] = 0;
	for (int i=1;i<=MaxClients;i++) {
		clientParticleAttached[i] &=~ (1<<(client-1));
	}
}
public void OnClientDisconnect(int client) {
	OnClientConnected(client);
	for (int i=1;i<=MaxClients;i++)
		if (pairPvPrequest[i]==client)
			pairPvPrequest[i]=0;
}

//region pretty much cookies
public void OnClientCookiesCached(int client) {
	if (IsFakeClient(client)) {
		//Bot cookies
		globalPvP[client] = State_BotAlways;
		pairPvPignored[client] = true;
		mirrorDamage[client] = State_Disabled;
		allowTauntKilled[client] = true;
		UpdateEntityFlagsGlobalPvP(client, true);
		return;
	}
	char buffer[128];
	Handle cookie;
	if (joinForceState!=0) {
		SetGlobalPvP(client, joinForceState<0);
	} else if((cookie = FindClientCookie(COOKIE_GLOBALPVP)) != null && GetClientCookie(client, cookie, buffer, sizeof(buffer)) && !StrEqual(buffer, "")) {
		bool pvp = view_as<bool>(StringToInt(buffer));
		if (pvp) globalPvP[client] |= State_Enabled;
		else globalPvP[client] &=~ State_Enabled;
		UpdateEntityFlagsGlobalPvP(client, IsGlobalPvP(client));
		delete cookie;
	}
	if((cookie = FindClientCookie(COOKIE_IGNOREPVP)) != null && GetClientCookie(client, cookie, buffer, sizeof(buffer)) && !StrEqual(buffer, "")) {
		pairPvPignored[client] = view_as<bool>(StringToInt(buffer));
		delete cookie;
	}
	if((cookie = FindClientCookie(COOKIE_MIRRORME)) != null && GetClientCookie(client, cookie, buffer, sizeof(buffer)) && !StrEqual(buffer, "")) {
		bool mirror = view_as<bool>(StringToInt(buffer));
		if (mirror) mirrorDamage[client] |= State_Enabled;
		else mirrorDamage[client] &=~ State_Enabled;
		delete cookie;
	}
	if((cookie = FindClientCookie(COOKIE_TAUNTKILL)) != null && GetClientCookie(client, cookie, buffer, sizeof(buffer)) && !StrEqual(buffer, "")) {
		allowTauntKilled[client] = view_as<bool>(StringToInt(buffer));
		delete cookie;
	}
	if((cookie = FindClientCookie(COOKIE_BANDATA)) != null && GetClientCookie(client, cookie, buffer, sizeof(buffer)) && !StrEqual(buffer, "")) {
		int read = StringToIntEx(buffer,clientPvPBannedUntil[client]);
		clientPvPBannedUntil[client] *= 60;
		strcopy(clientPvPBannedReason[client], sizeof(clientPvPBannedReason[]), buffer[read]);
		delete cookie;
		BanClientPvP(-1,client,0,"");//reload
	}
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
	if (globalPvP[client] & State_Enabled) {
		Format(buffer, sizeof(buffer), "[X] %T", "SettingsMenuGlobal", client);
		menu.AddItem("globalpvp", buffer);
	} else {
		Format(buffer, sizeof(buffer), "[  ] %T", "SettingsMenuGlobal", client);
		menu.AddItem("globalpvp", buffer);
	}
	if (pairPvPignored[client]) {
		Format(buffer, sizeof(buffer), "[X] %T", "SettingsMenuIgnorePair", client);
		menu.AddItem("ignorepvp", buffer);
	} else {
		Format(buffer, sizeof(buffer), "[  ] %T", "SettingsMenuIgnorePair", client);
		menu.AddItem("ignorepvp", buffer);
	}
	if (mirrorDamage[client] & State_Enabled) {
		Format(buffer, sizeof(buffer), "[X] %T", "SettingsMenuMirrorDamage", client);
		menu.AddItem("mirror", buffer);
	} else {
		Format(buffer, sizeof(buffer), "[  ] %T", "SettingsMenuMirrorDamage", client);
		menu.AddItem("mirror", buffer);
	}
	if (allowTauntKilled[client]) {
		Format(buffer, sizeof(buffer), "[X] %T", "SettingsMenuTauntKills", client);
		menu.AddItem("tauntkill", buffer);
	} else {
		Format(buffer, sizeof(buffer), "[  ] %T", "SettingsMenuTauntKills", client);
		menu.AddItem("tauntkill", buffer);
	}
	if (allowLimitedConditions[client]) {
		Format(buffer, sizeof(buffer), "[X] %T", "SettingsMenuConditions", client);
		menu.AddItem("conditions", buffer);
	} else {
		Format(buffer, sizeof(buffer), "[  ] %T", "SettingsMenuConditions", client);
		menu.AddItem("conditions", buffer);
	}
	menu.ExitBackButton = true;
	menu.Display(client, 60);
}
public int HandlePvPCookieMenu(Menu menu, MenuAction action, int param1, int param2) {
	if (action == MenuAction_Select) {
		char info[32];
		menu.GetItem(param2, info, sizeof(info));
		if(StrEqual(info, "globalpvp")) {
			SetGlobalPvP(param1, !(globalPvP[param1]&State_Enabled));
		}
		if(StrEqual(info, "ignorepvp")) {
			SetPairPvPIgnored(param1, !pairPvPignored[param1]);
		}
		if(StrEqual(info, "mirror")) {
			SetMirroredState(param1, !(mirrorDamage[param1]&State_Enabled));
		}
		if(StrEqual(info, "tauntkill")) {
			SetTauntKillable(param1, !allowTauntKilled[param1]);
		}
		if(StrEqual(info, "conditions")) {
			SetLimitedConditionsAllowed(param1, !allowLimitedConditions[param1]);
		}
		ShowCookieSettingsMenu(param1);
	} else if(action == MenuAction_Cancel && param2 == MenuCancel_ExitBack) {
		ShowCookieMenu(param1);
	} else if(action == MenuAction_End) {
		delete menu;
	}
}
//endregion

//region command and toggling/requesting pvp
bool TargetSelector_PVP(const char[] pattern, ArrayList clients) {
	bool invert = pattern[1]=='!';
	for (int i=1;i<=MaxClients;i++) {
		if (Client_IsIngame(i)) {
			if (IsGlobalPvP(i) ^ invert) {
				clients.Push(i);
			}
		}
	}
	return true;
}

public Action Command_BanPvP(int client, int args) {
	if (args < 1) {
		ReplyToCommand(client, "Usage: sm_banpvp <#user|name> [<minutes> [Reason]]");
		return Plugin_Handled;
	}
	
	int len, next_len;
	char argstring[256];
	GetCmdArgString(argstring, sizeof(argstring));
	
	char arg[65];
	len = BreakString(argstring, arg, sizeof(arg));
	
	int target = FindTarget(client, arg, true);
	if (target == -1) {
		return Plugin_Handled;
	}
	
	if (args == 1) {
		int restTime = clientPvPBannedUntil[target]-GetTime();
		if (restTime>0) {
			ReplyToCommand(client, "[PvP] '%L' was banned from PvP for %i more minutes (Reason: %s)", target, RoundToCeil(restTime/60.0), clientPvPBannedReason[target]);
		} else {
			ReplyToCommand(client, "[PvP] '%L' is not banned from PvP", target);
		}
		return Plugin_Handled;
	}
	
	char stime[12];
	char reason[128];
	if ((next_len = BreakString(argstring[len], stime, sizeof(stime))) != -1) {
		len += next_len;
		strcopy(reason, sizeof(reason), argstring[len]);
	} else {
		strcopy(reason, sizeof(reason), "<No Reason>");
	}
	int time = StringToInt(stime);
	if (time <= 0) {
		time = 1025280; //2 years
	}
	
	
	BanClientPvP(client, target, time, reason);

	return Plugin_Handled;
}
public Action Command_UnbanPvP(int client, int args) {
	if (GetCmdArgs() < 1) {
		ReplyToCommand(client, "Usage: sm_unbanpvp <#user|name>");
	}
	
	char arg[65];
	GetCmdArgString(arg, sizeof(arg));
	
	int target = FindTarget(client, arg, true);
	if (target == -1) {
		return Plugin_Handled;
	}
	
	BanClientPvP(client, target, 0, "");

	return Plugin_Handled;
}

public Action Command_ForceRequest(int client, int args) {
	char pattern[MAX_NAME_LENGTH+1], tname[MAX_NAME_LENGTH+1];
	int target[1], matches, fakesource, faketarget;
	bool tn_is_ml;
	
	if (GetCmdArgs() != 2) {
		GetCmdArg(0, pattern, sizeof(pattern));
		ReplyToCommand(client, "Usage: %s <requester> <requestee>", pattern);
		return Plugin_Handled;
	}
	
	GetCmdArg(1, pattern, sizeof(pattern));
	matches = ProcessTargetString(pattern, client, target, 1, COMMAND_FILTER_CONNECTED|COMMAND_FILTER_NO_IMMUNITY|COMMAND_FILTER_NO_BOTS|COMMAND_FILTER_NO_MULTI, tname, sizeof(tname), tn_is_ml);
	if (matches <= 0) {
		ReplyToTargetError(client, matches);
		return Plugin_Handled;
	} else {
		fakesource = target[0];
	}
	GetCmdArg(2, pattern, sizeof(pattern));
	matches = ProcessTargetString(pattern, client, target, 1, COMMAND_FILTER_CONNECTED|COMMAND_FILTER_NO_IMMUNITY|COMMAND_FILTER_NO_BOTS|COMMAND_FILTER_NO_MULTI, tname, sizeof(tname), tn_is_ml);
	if (matches <= 0) {
		ReplyToTargetError(client, matches);
		return Plugin_Handled;
	} else {
		faketarget = target[0];
	}
	
	if (fakesource == faketarget) {
		ReplyToCommand(client, "%t", "Requester is Requestee");
	} else {
		RequestPairPvP(fakesource, faketarget);
	}
	return Plugin_Handled;
}
public Action Command_TogglePvP(int client, int args) {
	if (clientPvPBannedUntil[client] > GetTime()) {
		CPrintToChat(client, "%t", "You have been banned from pvp", RoundToCeil((clientPvPBannedUntil[client]-GetTime())/60.0), clientPvPBannedReason[client]);
		return Plugin_Handled;
	}
	if (GetCmdArgs()==0) {
		bool enterPvP = !(globalPvP[client]&State_Enabled);
		//timeLeft = cooldown - time spent in pvp
		float timeLeft = PvP_DISENGAGE_COOLDOWN - (GetClientTime(client) - clientLatestPvPAction[client]);
		if (!enterPvP && timeLeft > 0.0) {
			CPrintToChat(client, "%t", "Entered global pvp too recently", RoundToCeil(timeLeft));
			return Plugin_Handled;
		}
		if (enterPvP) clientLatestPvPAction[client] = GetClientTime(client);
		SetGlobalPvP(client, enterPvP);
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
			RequestPairPvP(client, target[0], true);
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
			RequestPairPvP(param1, target, true);
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
			if (pvpon) globalPvP[0] |= State_Forced;
			else globalPvP[0] &=~ State_Forced;
			for (int i=1;i<=MaxClients;i++) {
				if (!Client_IsIngame(i) || IsFakeClient(i)) continue;
				if (clientPvPBannedUntil[client] > GetTime()) continue; //is banned
				if (!pvpon) globalPvP[i] &=~ State_Forced; //turn off previously individually set flags
				UpdateEntityFlagsGlobalPvP(i, IsGlobalPvP(i));
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
			int matches = ProcessTargetString(pattern, client, target, MAXPLAYERS, COMMAND_FILTER_CONNECTED|COMMAND_FILTER_NO_BOTS|COMMAND_FILTER_NO_IMMUNITY, tname, sizeof(tname), tn_is_ml);
			if (matches < 1) {
				ReplyToTargetError(client, matches);
			} else {
				for (int i;i<matches;i++) {
					int player = target[i];
					if (!Client_IsIngame(player)) continue;
					if (clientPvPBannedUntil[client] > GetTime()) continue; //is banned
					if (pvpon) {
						globalPvP[player] |= State_Forced;
						CPrintToChat(player, "%t","Someone forced your global pvp", client);
					} else {
						globalPvP[player] &=~ State_Forced;
						CPrintToChat(player, "%t","Someone reset your global pvp", client);
					}
					UpdateEntityFlagsGlobalPvP(player, IsGlobalPvP(player));
				}
				if (pvpon) {
					CReplyToCommand(client, "%t", "You forced someones global pvp", tname);
				} else {
					CReplyToCommand(client, "%t", "You reset someones global pvp", tname);
				}
			}
		}
	}
	return Plugin_Handled;
}

public Action Command_Mirror(int client, int args) {
	if (GetCmdArgs()!=2) {
		char name[16];
		GetCmdArg(0, name, sizeof(name));
		ReplyToCommand(client, "Usage: %s <target> <1/0>", name);
	} else {
		char pattern[MAX_NAME_LENGTH+1], tname[MAX_NAME_LENGTH+1];
		GetCmdArg(2,pattern, sizeof(pattern));
		bool force = StringToInt(pattern) != 0;
		GetCmdArg(1,pattern, sizeof(pattern));
		
		int target[MAXPLAYERS];
		bool tn_is_ml;
		int matches = ProcessTargetString(pattern, client, target, MAXPLAYERS, COMMAND_FILTER_CONNECTED|COMMAND_FILTER_NO_BOTS|COMMAND_FILTER_NO_IMMUNITY, tname, sizeof(tname), tn_is_ml);
		if (matches < 1) {
			ReplyToTargetError(client, matches);
		} else {
			for (int i;i<matches;i++) {
				int player = target[i];
				if (!Client_IsIngame(i)) continue;
				if (force) {
					mirrorDamage[player] |= State_Forced;
					CPrintToChat(player, "%t","Someone forced your mirror damage", client);
				} else {
					mirrorDamage[player] &=~ State_Forced;
					CPrintToChat(player, "%t","Someone reset your mirror damage", client);
				}
			}
			if (force) {
				CReplyToCommand(client, "%t", "You forced someones mirror damage", tname);
			} else {
				CReplyToCommand(client, "%t", "You reset someones mirror damage", tname);
			}
		}
	}
	return Plugin_Handled;
}

public Action Command_MirrorMe(int client, int args) {
	SetMirroredState(client, !(mirrorDamage[client]&State_Enabled));
	return Plugin_Handled;
}

public Action Command_StopPvP(int client, int args) {
	bool primary;
	if (ArrayFind(client, pairPvPrequest, sizeof(pairPvPrequest))) {
		DeclinePairPvP(client);
		primary = true;
	}
	if (HasAnyPairPvP(client)) {
		EndAllPairPvPFor(client);
		primary = true;
	}
	if (primary) {
		CPrintToChat(client, "%t", "Use command again to toggle ignore");
	} else {
		SetPairPvPIgnored(client, !pairPvPignored[client]);
	}
	return Plugin_Handled;
}

static void RequestPairPvP(int requester, int requestee, bool antiSpam=false) {
	float tmp;
	if (requester == requestee || pairPvPignored[requestee] || clientPvPBannedUntil[requestee] > GetTime()) {
		//silent fail
	} else if (clientPvPBannedUntil[requester] > GetTime()) {
		CPrintToChat(requester, "%t", "You have been banned from pvp", RoundToCeil((clientPvPBannedUntil[requester]-GetTime())/60.0), clientPvPBannedReason[requester]);
	} else if (antiSpam && (tmp = (PvP_PAIRREQUEST_COOLDOWN - (GetClientTime(requester) - clientLatestPvPRequest[requester]))) > 0.0) {
		CPrintToChat(requester, "%t", "Last pair pvp request too recent", RoundToCeil(tmp));
	} else if (IsFakeClient(requestee)) {
		CPrintToChat(requester, "%t", "Bots can not use pair pvp");
	} else if (pairPvP[requester][requestee]) { //already paired, leave
		CPrintToChat(requestee, "%t", "Someone disengaged pair pvp", requester);
		CPrintToChat(requester, "%t", "You disengaged pair pvp", requestee);
		pairPvPrequest[requester]=pairPvPrequest[requestee]=0;
		SetPairPvP(requester,requestee,false);
	} else if (pairPvPrequest[requestee]==requester) { //response / accept
		CPrintToChat(requestee, "%t", "You engaged pair pvp", requester);
		CPrintToChat(requester, "%t", "You engaged pair pvp", requestee);
		pairPvPrequest[requester]=pairPvPrequest[requestee]=0;
		SetPairPvP(requester,requestee,true);
	} else if (IsGlobalPvP(requester) && IsGlobalPvP(requestee)) {
		CPrintToChat(requester, "%t", "You are both global pvp");
	} else if (pairPvPrequest[requester]==requestee) {
		CPrintToChat(requester, "%t", "Already requested pvp with", requestee);
	} else if (pairPvPRequestMenu && ArrayFind(requestee, pairPvPrequest, sizeof(pairPvPrequest))>0) {
		//menus are kinda iffy 
		CPrintToChat(requester, "%t", "There is a pending request with menus");
	} else {
		if (Notify_OnPairInvited(requester, requestee)) {
			if (Client_IsValid(pairPvPrequest[requester])) {
				CPrintToChat(pairPvPrequest[requester], "%t", "Someone cancelled pvp request for another", requester);
				CPrintToChat(requester, "%t", "You cancelled pvp request", pairPvPrequest[requester]);
			}
			CPrintToChat(requestee, "%t", "Someone requested pvp, confirm", requester, requester);
			CPrintToChat(requester, "%t", "You requested pvp", requestee);
			if (antiSpam) clientLatestPvPRequest[requester] = GetClientTime(requester);
			pairPvPrequest[requester] = requestee;
			if (pairPvPRequestMenu) {
				if (depNativeVotes && pairPvPRequestMenu == 1) VotePairPvPRequest(requester, requestee);
				else MenuPairPvPRequest(requester, requestee);
			}
		}
	}
}
static void DeclinePairPvP(int requestee, bool CloseMenus=true) {
	int declined,someRequester=0;
	for (int requester=1; requester<=MaxClients; requester++) {
		if (Client_IsValid(requester) && pairPvPrequest[requester]==requestee) {
			CPrintToChat(requester, "%t", "Your pvp request was declined", requestee);
			if (CloseMenus && depNativeVotes && pairPvPRequestMenu == 1) ForceEndNativeVote(requester);
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

static ArrayList pairPvPVoteData;
static void VotePairPvPRequest(int requester, int requestee) {
	if (pairPvPVoteData == null) pairPvPVoteData = new ArrayList(4);
	NativeVote vote = NativeVotes_Create(PairPvPNativeVote, NativeVotesType_Custom_YesNo);
	vote.SetTitle("%T", "Vote Title PvP Request", requestee, requester);
	vote.Initiator = requester;
	vote.SetTarget(requestee);
	int clients[1];clients[0]=requestee;
	vote.DisplayVote(clients, 1, PvP_PAIRVOTE_DISPLAYTIME, VOTEFLAG_NO_REVOTES);
	
	ForceEndNativeVote(requester);
	any vdata[4];
	vdata[0] = vote;
	vdata[1] = requester;
	vdata[2] = requestee;
	vdata[3] = 1; //1 for in use
	pairPvPVoteData.PushArray(vdata);
}
static void ForceEndNativeVote(int requester) {
	int at = pairPvPVoteData.FindValue(requester, 1);
	if (at >= 0) {
		view_as<NativeVote>(pairPvPVoteData.Get(at)).Close(); //will decline requests if not done yet
		pairPvPVoteData.Erase(at); //late erase to allow cancelling of ui
	}
}
public int PairPvPNativeVote(NativeVote vote, MenuAction action, int param1, int param2) {
	int at = pairPvPVoteData.FindValue(vote);
	any vdata[4];
	if (at >= 0) pairPvPVoteData.GetArray(at, vdata);
	if (action == MenuAction_End) {
		if (at >= 0) {
			pairPvPVoteData.Erase(at); //we've read the data, remove from list
			if (vdata[3]) {//bugged or timed out, close for both
				vote.DisplayPassCustomToOne(vdata[1], "The Pair PvP invite failed!");
				vote.DisplayPassCustomToOne(vdata[2], "The Pair PvP invite failed!");
				DeclinePairPvP(vdata[2], false); //and decline if not done yet
			}
		}
		vote.Close();
	} else if (action == MenuAction_VoteEnd) {
		if (!param1) {
			if (vdata[3]) {
				vote.DisplayPassCustomToOne(vdata[1], "Pair PvP invite was accepted!");
				vote.DisplayPassCustomToOne(vdata[2], "Pair PvP invite was accepted!");
			}
			RequestPairPvP(vdata[2], vdata[1]); //request reverse to confirm
		} else {
			if (vdata[3]) {
				vote.DisplayPassCustomToOne(vdata[1], "Pair PvP invite was declined!");
				vote.DisplayPassCustomToOne(vdata[2], "Pair PvP invite was declined!");
			}
			DeclinePairPvP(vdata[2], false);
		}
		pairPvPVoteData.Set(at, 0, 3); //should now be unused, no further display calls requred
	}
}
static void MenuPairPvPRequest(int requester, int requestee) {
	if (pairPvPVoteData == null) pairPvPVoteData = new ArrayList(3);
	Menu menu = new Menu(PairPvPSourcemodVote);
	char buffer[16];
	menu.SetTitle("%T", "Vote Title PvP Request", requestee, requester);
	Format(buffer, sizeof(buffer), "%T", "Yes", requestee);
	menu.AddItem("0", buffer);
	Format(buffer, sizeof(buffer), "%T", "No", requestee);
	menu.AddItem("1", buffer);
	menu.Display(requestee, PvP_PAIRVOTE_DISPLAYTIME);
	
	any vdata[3];
	vdata[0] = menu;
	vdata[1] = requester;
	vdata[2] = requestee;
	pairPvPVoteData.PushArray(vdata);
}
public int PairPvPSourcemodVote(Menu menu, MenuAction action, int param1, int param2) {
	int at = pairPvPVoteData.FindValue(menu);
	int selection;
	if (action == MenuAction_End) {
		if (at >= 0) pairPvPVoteData.Erase(at);
		delete menu;
		return;
	} else if (action == MenuAction_Select) {
		char buffer[4];
		menu.GetItem(param2, buffer, sizeof(buffer));
		if (StrEqual(buffer,"0")) selection = 0;
		else selection = 1;
	} else if (action == MenuAction_Cancel) {
		selection=-1;
	}
	any vdata[3];
	if (at >= 0) pairPvPVoteData.GetArray(at, vdata);
	if (!selection) {
		RequestPairPvP(vdata[2], vdata[1]); //request reverse to confirm
	} else {
		DeclinePairPvP(vdata[2]);
	}
}
//endregion

//region utilities to set and check pvp flags
void PrintGlobalPvpState(int client) {
	if (!IsClientInGame(client) || IsFakeClient(client) || GetClientTime(client)<2.0) return;
	if (IsGlobalPvP(client)) {
		CPrintToChat(client, "%t", "Global pvp state on line1");
		CPrintToChat(client, "%t", "Global pvp state on line2");
	} else {
		CPrintToChat(client, "%t", "Global pvp state off line1");
		CPrintToChat(client, "%t", "Global pvp state off line2");
	}
	CPrintToChat(client, "%t", "Hey there's also pair pvp");
}
//return false if cancelled
static bool SetGlobalPvP(int client, bool pvp) {
	Handle cookie;
	eEnabledState newState;
	if (pvp) newState |= State_Enabled;
	else newState &=~ State_Enabled;
	
	if (Notify_OnGlobalChanged(client, newState) && newState != globalPvP[client]) {
		globalPvP[client] = newState;
		pvp = (newState & State_Enabled) == State_Enabled;
	} else return false; //nothing changed, what do you want? :D
	
	if((cookie = FindClientCookie(COOKIE_GLOBALPVP)) != null) {
		char value[2]="0";
		if (pvp) value[0]='1';
		SetClientCookie(client, cookie, value);
		delete cookie;
	}
	UpdateEntityFlagsGlobalPvP(client, IsGlobalPvP(client));
	PrintGlobalPvpState(client);
	return true;
}
static void SetPairPvPIgnored(int client, bool ignore) {
	Handle cookie;
	pairPvPignored[client] = ignore;
	if((cookie = FindClientCookie(COOKIE_IGNOREPVP)) != null) {
		char value[2]="0";
		if (ignore) value[0]='1';
		SetClientCookie(client, cookie, value);
		delete cookie;
	}
	if (ignore) {
		DeclinePairPvP(client);
		CPrintToChat(client, "%t", "You are ignoring pair pvp");
	} else {
		CPrintToChat(client, "%t", "You are allowing pair pvp");
	}
}
//return false if cancelled
bool SetPairPvP(int client1, int client2, bool pvp) {
	if (Notify_OnPairChanged(client1, client2, pvp)) {
		pairPvP[client1][client2] = pairPvP[client2][client1] = pvp;
		UpdatePvPParticles(client1);
		UpdatePvPParticles(client2);
		return true;
	} else return false;
}
static void SetPairPvPClient(int client, bool pvp=false) {
	for (int i=1;i<=MaxClients;i++) {
		pairPvP[client][i] = pairPvP[i][client] = pvp;
	}
	for (int i=1;i<=MaxClients;i++) {
		UpdatePvPParticles(i);
	}
}
static bool HasAnyPairPvP(int client) {
	for (int i=1;i<=MaxClients;i++) {
		if (pairPvP[client][i]) return true;
	}
	return false;
}
static void SetMirroredState(int client, bool mirrored) {
	Handle cookie;
	if (mirrored) mirrorDamage[client] |= State_Enabled;
	else mirrorDamage[client] &=~ State_Enabled;
	if((cookie = FindClientCookie(COOKIE_MIRRORME)) != null) {
		char value[2]="0";
		if (mirrored) value[0]='1';
		SetClientCookie(client, cookie, value);
		delete cookie;
	}
	if (mirrored) CPrintToChat(client, "%t", "Mirror Damage Enabled");
	else if (IsMirrored(client)) CPrintToChat(client, "%t", "Mirror Damage not Disabled, Forced");
	else CPrintToChat(client, "%t", "Mirror Damage Disabled");
}
static void SetTauntKillable(int client, bool enabled) {
	Handle cookie;
	allowTauntKilled[client] = enabled;
	if((cookie = FindClientCookie(COOKIE_TAUNTKILL)) != null) {
		char value[2]="0";
		if (enabled) value[0]='1';
		SetClientCookie(client, cookie, value);
		delete cookie;
	}
	if (enabled) CPrintToChat(client, "%t", "Taunt Kills Enabled");
	else CPrintToChat(client, "%t", "Taunt Kills Disabled");
}
static void SetLimitedConditionsAllowed(int client, bool enabled) {
	Handle cookie;
	allowLimitedConditions[client] = enabled;
	if((cookie = FindClientCookie(COOKIE_CONDITIONS)) != null) {
		char value[2]="0";
		if (enabled) value[0]='1';
		SetClientCookie(client, cookie, value);
		delete cookie;
	}
	if (enabled) CPrintToChat(client, "%t", "Limited Conditions Enabled");
	else CPrintToChat(client, "%t", "Limited Conditions Disabled");
}

int CanClientsPvP(int client1, int client2) {
	int canpvp;
	if (client1==client2) canpvp |= 1;
	if (globalPvP[0]!=State_Disabled) canpvp |= 2;
	if (IsGlobalPvP(client1) && IsGlobalPvP(client2)) canpvp |= 4;
	if (pairPvP[client1][client2]) canpvp |= 8;
	return canpvp;
	//duels should be checked here, can't real tho, that's GC stuff
}
/** 
 * admin < 0 to "reload", time and reason will be ignored
 * time <= 0 to unban, reason will be ignored
 * @param time in minutes
 */
void BanClientPvP(int admin, int client, int time, const char[] reason) {
	bool banned;
	if (admin >= 0) {
		Cookie cookie = Cookie.Find(COOKIE_BANDATA);
		if (time > 0) {
			banned = true;
			ShowActivity2(admin, "[PvP] ", "%L banned %L from PvP for %i minutes (Reason: %s)", admin, client, time, reason);
			clientPvPBannedUntil[client] = GetTime()+(time*60);
			strcopy(clientPvPBannedReason[client], sizeof(clientPvPBannedReason[]), reason);
			char buffer[100];
			Format(buffer, sizeof(buffer), "%i %s", (clientPvPBannedUntil[client]+59)/60 /* round up */, clientPvPBannedReason[client]);
			if (cookie != null) {
				cookie.Set(client, buffer);
				delete cookie;
			}
			Notify_OnBanAdded(admin, client, time, reason);
		} else {
			ShowActivity2(admin, "[PvP] ", "%L unbanned %L from PvP", admin, client);
			clientPvPBannedUntil[client] = 0;
			if (cookie != null) {
				cookie.Set(client, "");
				delete cookie;
			}
			Notify_OnBanRemoved(admin, client);
		}
	} else if (clientPvPBannedUntil[client]) {
		if (GetTime() > clientPvPBannedUntil[client]) { //we loaded a ban, but the ban is over?
			clientPvPBannedUntil[client] = 0;
			//clear cookie
			Cookie cookie = Cookie.Find(COOKIE_BANDATA);
			if (cookie != null) {
				cookie.Set(client, "");
				delete cookie;
			}
		} else {
			banned = true;
		}
	}
	if (banned) {
		EndAllPairPvPFor(client);
		globalPvP[client] &=~ ENABLEDMASK_EXTERNAL|State_Forced;
		SetGlobalPvP(client, false);
		CreateTimer(1.0, BannedFromPvPNotice, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
	}
}
public Action BannedFromPvPNotice(Handle timer, int user) {
	int client = GetClientOfUserId(user);
	if (!client || !IsClientInGame(client)) return Plugin_Stop;
	CPrintToChat(client, "%t", "You have been banned from pvp", RoundToCeil((clientPvPBannedUntil[client]-GetTime())/60.0), clientPvPBannedReason[client]);
	return Plugin_Stop;
}
//endregion

//region actual damage blocking and entity stuff

public void OnEntityCreated(int entity, const char[] classname) {
	if (StrEqual(classname, "player")||StrEqual(classname, "tf_bot")) {
		SDKHookClient(entity);
	} else if (IsEntityZombie(classname)) {
		SDKHook(entity, SDKHook_OnTakeDamage, OnZombieTakeDamage);
	} else if (IsEntityBoss(classname)) {
		SDKHook(entity, SDKHook_OnTakeDamage, OnBossTakeDamage);
	} else if (IsEntityBuilding(classname)) {
		SDKHook(entity, SDKHook_OnTakeDamage, OnBuildingTakeDamage);
	}
}

static void SDKHookClient(int client) {
	SDKHook(client, SDKHook_OnTakeDamageAlive, OnClientTakeDamage);
	SDKHook(client, SDKHook_OnTakeDamagePost, OnClientTakeDamagePost);
	SDKHook(client, SDKHook_SpawnPost, OnClientSpawnPost);
}

public Action OnZombieTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &weapon, float damageForce[3], float damagePosition[3], int damagecustom) {
	if (!isActive)
		return Plugin_Continue;
	
	//Sometimes the attacker won't be a player directly, try to resolve this
	int source = GetPlayerDamageSource(attacker, inflictor);
	if (1<=source<=MaxClients && (pvaPlayers&PvA_ZOMBIES)==PvA_Zombies_Ignored) {
		return Plugin_Handled;
	}
	return Plugin_Continue;
}
public Action OnBossTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &weapon, float damageForce[3], float damagePosition[3], int damagecustom) {
	if (!isActive)
		return Plugin_Continue;
	
	//Sometimes the attacker won't be a player directly, try to resolve this
	int source = GetPlayerDamageSource(attacker, inflictor);
	if (1<=source<=MaxClients && (pvaPlayers&PvA_BOSSES)==PvA_Bosses_Ignored) {
		return Plugin_Handled;
	}
	return Plugin_Continue;
}
public Action OnBuildingTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &weapon, float damageForce[3], float damagePosition[3], int damagecustom) {
	if (!isActive)
		return Plugin_Continue;
	
	//Sometimes the attacker won't be a player directly, try to resolve this
	int source = GetPlayerDamageSource(attacker, inflictor);
	if (!Client_IsValid(source))
		return Plugin_Continue;
	
	int owner = GetPlayerEntity(victim);
	if (Client_IsValid(owner) && !CanClientsPvP(source, owner)) {
		damage = 0.0;
		return Plugin_Handled;
	}
	return Plugin_Continue;
}
public Action OnClientTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &weapon, float damageForce[3], float damagePosition[3], int damagecustom) {
	// zombies and clients should not even target players
	// but stray projectiles / spray might still hit them
	if (!isActive)
		return Plugin_Continue;
	
	int pvpGrant;
	//Sometimes the attacker won't be a player directly, try to resolve this
	int source = GetPlayerDamageSource(attacker, inflictor);
	if (!Client_IsValid(source)) { //didnt bring your hazardous environment suit?
		return Plugin_Continue;
	} else if (IsMirrored(source)) {
		if (damagecustom == TF_CUSTOM_BACKSTAB)
			damage = GetClientHealth(source) * 6.0;
		SDKHooks_TakeDamage(source, inflictor, source, damage, damagetype, weapon, damageForce, damagePosition);
		//damage was mirrored
	} else if (allowTauntKilled[victim] && TF2_IsPlayerInCondition(source, TFCond_Taunting)) {
		return Plugin_Continue; //allow taunt-kill explicitly
	} else if ((pvpGrant=CanClientsPvP(victim,source))) {
		//don't update cooldowns if we're forced into pvp or damage is self-inflicted
		// for now reset cooldowns on any pvp
		if (pvpGrant&3 == 0 && pvpGrant&12 != 0) {
			if (!IsFakeClient(victim)) clientLatestPvPAction[victim] = GetClientTime(victim);
			if (!IsFakeClient(source)) clientLatestPvPAction[source] = GetClientTime(source);
		}
		return Plugin_Continue; //pvp is on, go nuts
	}
		
	//block damage on victim
	damage = 0.0;
	ScaleVector(damageForce, 0.0);
	return Plugin_Handled;
}
public void OnClientTakeDamagePost(int victim, int attacker, int inflictor, float damage, int damagetype) {
	//tracking spawnkilling here, so only react to human attackers and when the victim died
	if (!isActive)
		return;
	if (!Client_IsIngame(attacker) || IsFakeClient(attacker) || GetClientHealth(victim)>0) {
		return;
	}
	if (!IsFakeClient(victim)) { //again, bots don't leave pvp
		clientLatestPvPAction[victim] = GetClientTime(victim)-PvP_DISENGAGE_COOLDOWN;
	}
	
	if (spawnKill_maxTime > 0.01 && spawnKill_minIncrease > 0 && spawnKill_maxIncreaseRoot >= 0.0 && spawnKill_threashold > 0 && spawnKill_banTime > 0) {
		float timeAlive = GetGameTime() - clientSpawnTime[victim];
		if (timeAlive > spawnKill_maxTime) return; //idk, just bad?
		int score = spawnKill_minIncrease;
		if (spawnKill_maxIncreaseRoot > 0.0001)
			score += RoundToNearest(Pow((1.0-(timeAlive/spawnKill_maxTime))*spawnKill_maxIncreaseRoot,2.0)); //quadratic fall off
		clientSpawnKillScore[attacker] += score;
		
		if (clientSpawnKillScore[attacker] >= spawnKill_threashold) { //5 near instant kills
			BanClientPvP(0, attacker, spawnKill_banTime, "Spawn Killing [Automatic]");
		} else if (score > 0) {
			CPrintToChat(attacker, "%t", "Spawn Killing is not allowed");
			ShowActivity2(0, "[PvP] ", "Warned %N about Spawn Killing (Killed %N within %.2fs)", attacker, victim, timeAlive);
		}
	}
}
public void OnClientSpawnPost(int client) {
	if (GetClientTeam(client)<=1) return;
	clientSpawnTime[client] = GetGameTime();
	
	if (IsFakeClient(client)) return;
	clientLatestPvPAction[client] = GetClientTime(client)-PvP_DISENGAGE_COOLDOWN;
	UpdateEntityFlagsGlobalPvP(client, IsGlobalPvP(client));
	if (clientFirstSpawn[client]) {
		clientFirstSpawn[client] = false;
		PrintGlobalPvpState(client);
	}
}
public void OnInventoryApplicationPost(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (usePvPParticle) clientForceUpdateParticle[client] = true;
	UpdateEntityFlagsGlobalPvP(client, IsGlobalPvP(client));
}

public void TF2_OnConditionAdded(int client, TFCond condition) {
	int provider, at;
	if (!isActive) return;
	
	//hide particle effect when cloaking
	if (usePvPParticle) {
		if (condition == TFCond_Cloaked) ParticleEffectStop(client);
		if (condition == TFCond_Disguised) clientForceUpdateParticle[client] = true;
	}
	
	if ((at = ArrayFind(condition, pvpConditions, sizeof(pvpConditions)))<0)
		return; //not a condition we manage
	if ((provider = TF2Util_GetPlayerConditionProvider(client, condition))<=0)
		return; //provider is no player
	if (CanClientsPvP(client,provider))
		return; //allow conditions
	if (allowLimitedConditions[client] && pvpConditionTrivial[at])
		return; //target is fine with conditions
	TF2_RemoveCondition(client, condition);
}

public void TF2_OnConditionRemoved(int client, TFCond condition) {
	if (!isActive) return;
	if (usePvPParticle && condition == TFCond_Disguised) clientForceUpdateParticle[client] = true;
}


void UpdateEntityFlagsGlobalPvP(int client, bool pvp) {
	if (!Client_IsIngame(client)) return;
	int ci;
	if (TF2_GetClientTeam(client)==TFTeam_Blue) ci++;
	if (!pvp && isActive) ci+=2;
	if (usePlayerStateColors)
		SetPlayerColor(client, playerStateColors[ci][0], playerStateColors[ci][1], playerStateColors[ci][2], playerStateColors[ci][3]);
	if (usePvPParticle) UpdatePvPParticles(client);
}

//endregion
