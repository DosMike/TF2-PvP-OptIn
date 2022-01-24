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

#define PLUGIN_VERSION "22w03a"
#pragma newdecls required
#pragma semicolon 1

public Plugin myinfo = {
	name = "[TF2] Opt In PvP",
	author = "reBane",
	description = "Opt In PvP for LazyPurple Silly Servers",
	version = PLUGIN_VERSION,
	url = "https://github.com/DosMike/TF2-PvP-OptIn"
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
static bool pvpConditionTrivial[] = { //true for conditions in pvpConditions that do not affect gameplay too much
	false,
	false,
	false,
	false,
	true,
	false,
	true,
	true,
	false,
	true,
	true,
	false,
	false,
	false,
	true,
	false,
	false,
	false
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

enum eEnabledState(<<=1) {
	State_Disabled = 0,
	State_Enabled = 1,
	State_Forced,
	State_ExternalOn, //a plugin placed an override
	State_ExternalOff, //a plugin placed an override
	State_BotAlways, //force-enabled in a way that can't turn off because bots
}
#define ENABLEDMASK_EXTERNAL  (State_ExternalOn|State_ExternalOff)

enum ePlayerVsAiFlags {
	PvA_Zombies_Ignored = 0, //players cant hurt zombies, zombies ignore players
	PvA_Zombies_Never = 0x01, //player/buildings are no target, but players can hurt zombies
	PvA_Zombies_GlobalPvP = 0x02, //Zombies will track down players in global pvp
	PvA_Zombies_Always = 0x03, //this counts as PvE and thus zombies vs players is always on
	PvA_Bosses_Ignored = 0, //bosses ignore humans, players can't hurt bosses
	PvA_Bosses_Never = 0x10, //player/buildings are no target, but players can hurt bosses
	PvA_Bosses_GlobalPvP = 0x20, //bosses will track down players in global pvp
	PvA_Bosses_Always = 0x30, //this counts as PvE and this bosses vs players is always on
	PvA_ZOMBIES = 0x0f,
	PvA_BOSSES = 0xf0,
}

static bool depNativeVotes; //is NativeVotes loaded?

static bool isActive; //plugin active flag changed depending on game state
static eGameState currentGameState;
static eEnabledState globalPvP[MAXPLAYERS+1]; //have turned global pvp on
static eEnabledState mirrorDamage[MAXPLAYERS+1]; //will never mirror if CanClientsPvP returns true
static bool allowTauntKilled[MAXPLAYERS+1];
static bool allowLimitedConditions[MAXPLAYERS+1]; //stuff like jarated, etc is ok for this player
static bool pairPvP[MAXPLAYERS+1][MAXPLAYERS+1]; //double reffed so order doesn't matter for quicker lookups
static int pairPvPrequest[MAXPLAYERS+1]; //invite requests
static bool pairPvPignored[MAXPLAYERS+1]; //invites disabled
static bool clientFirstSpawn[MAXPLAYERS+1]; //delay reminder message untill first actual spawn
static float clientLatestPvPStart[MAXPLAYERS+1]; //prevent "dodgeing" damage with pvp toggles by blocking leaving pvp for some time
static float clientLatestPvPRequest[MAXPLAYERS+1]; //prevent spamming people with too many pair pvp requests by blocking requests for some time
//maybe have client settings overwrite zombie/boss behaviour (force attack me)

static DHookSetup hdl_INextBot_IsEnemy;
static bool detoured_INextBot_IsEnemy;
static DHookSetup hdl_CZombieAttack_IsPotentiallyChaseable;
static bool detoured_CZombieAttack_IsPotentiallyChaseable;
static DHookSetup hdl_CHeadlessHatmanAttack_IsPotentiallyChaseable;
static bool detoured_CHeadlessHatmanAttack_IsPotentiallyChaseable;
static DHookSetup hdl_CMerasmusAttack_IsPotentiallyChaseable;
static bool detoured_CMerasmusAttack_IsPotentiallyChaseable;
static DHookSetup hdl_CEyeballBoss_FindClosestVisibleVictim;
static bool detoured_CEyeballBoss_FindClosestVisibleVictim;
static DHookSetup hdl_CTFPlayer_ApplyGenericPushbackImpulse;
static bool detoured_CTFPlayer_ApplyGenericPushbackImpulse;
static DHookSetup hdl_CObjectSentrygun_ValidTargetPlayer;
static bool detoured_CObjectSentrygun_ValidTargetPlayer;
static DHookSetup hdl_CObjectSentrygun_FoundTarget;
static bool detoured_CObjectSentrygun_FoundTarget;

static ConVar cvar_Version;
static ConVar cvar_JoinForceState;
static int joinForceState;
static ConVar cvar_NoCollide;
static int noCollideState;
static ConVar cvar_ActiveStates;
static eGameState activeGameStates;
static ConVar cvar_PairPvPRequestMenu;
static int pairPvPRequestMenu;
static ConVar cvar_UsePlayerColors;
static bool usePlayerStateColors;
static ConVar cvar_ColorGlobalOnRed;
static ConVar cvar_ColorGlobalOnBlu;
static ConVar cvar_ColorGlobalOffRed;
static ConVar cvar_ColorGlobalOffBlu;
static int playerStateColors[4][4];
static ConVar cvar_BuildingsVersusZombies;
static ConVar cvar_BuildingsVersusBosses;
static ePlayerVsAiFlags pvaBuildings;
static ConVar cvar_PlayersVersusZombies;
static ConVar cvar_PlayersVersusBosses;
static ePlayerVsAiFlags pvaPlayers;

static GlobalForward fwdGlobalChanged;
static GlobalForward fwdPairInvited;
static GlobalForward fwdPairChanged;

#define COOKIE_GLOBALPVP "enableGlobalPVP"
#define COOKIE_IGNOREPVP "ignorePairPVP"
#define COOKIE_TAUNTKILL "canBeTauntKilled"
#define COOKIE_MIRRORME "mirrorPvPDamage"
#define COOKIE_CONDITIONS "allowConditions"

#define IsGlobalPvP(%1) (globalPvP[%1]!=State_Disabled && !(globalPvP[%1]&State_ExternalOff))
#define IsMirrored(%1) (mirrorDamage[%1]!=State_Disabled && !(mirrorDamage[%1]&State_ExternalOff))

#define PvP_DISENGAGE_COOLDOWN 30.0
#define PvP_PAIRREQUEST_COOLDOWN 15.0
#define PvP_PAIRVOTE_DISPLAYTIME 10

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
	GameData pvpfundata = new GameData("pvpoptin.games");
	if (pvpfundata != INVALID_HANDLE) {
		hdl_INextBot_IsEnemy = DHookCreateFromConf(pvpfundata, "INextBot_IsEnemy");
		hdl_CZombieAttack_IsPotentiallyChaseable = DHookCreateFromConf(pvpfundata, "CZombieAttack_IsPotentiallyChaseable");
		hdl_CHeadlessHatmanAttack_IsPotentiallyChaseable = DHookCreateFromConf(pvpfundata, "CHeadlessHatmanAttack_IsPotentiallyChaseable");
		hdl_CMerasmusAttack_IsPotentiallyChaseable = DHookCreateFromConf(pvpfundata, "CMerasmusAttack_IsPotentiallyChaseable");
		hdl_CEyeballBoss_FindClosestVisibleVictim = DHookCreateFromConf(pvpfundata, "CEyeballBoss_FindClosestVisibleVictim");
		hdl_CTFPlayer_ApplyGenericPushbackImpulse = DHookCreateFromConf(pvpfundata, "CTFPlayer_ApplyGenericPushbackImpulse");
		hdl_CObjectSentrygun_ValidTargetPlayer = DHookCreateFromConf(pvpfundata, "CObjectSentrygun_ValidTargetPlayer");
		hdl_CObjectSentrygun_FoundTarget = DHookCreateFromConf(pvpfundata, "CObjectSentrygun_FoundTarget");
		delete pvpfundata;
	}
	
	RegClientCookie(COOKIE_GLOBALPVP, "Client has opted into global PvP", CookieAccess_Private);
	RegClientCookie(COOKIE_IGNOREPVP, "Client wants to ignore pair PvP", CookieAccess_Private);
	RegClientCookie(COOKIE_MIRRORME, "Mirror all damage out of PvP back to self", CookieAccess_Private);
	RegClientCookie(COOKIE_TAUNTKILL, "Client is find with being taunt-killed for funnies", CookieAccess_Private);
	RegClientCookie(COOKIE_CONDITIONS, "Client is find with being jarated, etc for funnies", CookieAccess_Private);
	
	RegConsoleCmd("sm_pvp", Command_TogglePvP, "Usage: [name|userid] - If you specify a user, request pair PvP, otherwise toggle global PvP");
	RegConsoleCmd("sm_stoppvp", Command_StopPvP, "Decline pair PvP requests, end all pair PvP or toggle pair PvP ignore state if you're not in pair PvP");
	RegConsoleCmd("sm_rejectpvp", Command_StopPvP, "Decline pair PvP requests, end all pair PvP or toggle pair PvP ignore state if you're not in pair PvP");
	RegConsoleCmd("sm_declinepvp", Command_StopPvP, "Decline pair PvP requests, end all pair PvP or toggle pair PvP ignore state if you're not in pair PvP");
	RegConsoleCmd("sm_mirrorme", Command_MirrorMe, "Turn on mirror damage for attacking non-PvP players");
	RegAdminCmd("sm_forcepvp", Command_ForcePvP, ADMFLAG_SLAY, "Usage: <target|'map'> <1/0> - Force the targets into global PvP; 'map' applies to players that will join as well; Resets on map change");
	RegAdminCmd("sm_mirror", Command_Mirror, ADMFLAG_SLAY, "Usage: <target> <1/0> - Force mirror with non-PvP players for the target");
	RegAdminCmd("sm_fakepvprequest", Command_ForceRequest, ADMFLAG_CHEATS, "Usage: <requester|userid> <requestee|userid> - Force request pvp from another users perspective");
	
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
	//create fancy plugin config - should be sourcemod/pvpoptin.cfg
	AutoExecConfig();
	
	fwdGlobalChanged = new GlobalForward("pvp_OnGlobalChanged", ET_Event, Param_Cell, Param_Cell, Param_CellByRef);
	fwdPairInvited = new GlobalForward("pvp_OnPairInvite", ET_Event, Param_Cell, Param_Cell);
	fwdPairChanged = new GlobalForward("pvp_OnPairChanged", ET_Event, Param_Cell, Param_Cell, Param_Cell);
	
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
public void OnAllPluginsLoaded() {
	depNativeVotes = LibraryExists("nativevotes");
}

public void OnPluginEnd() {
	DHooksDetach();
}

public void OnLibraryAdded(const char[] name) {
	if (StrEqual(name, "nativevotes")) depNativeVotes = true;
}

public void OnLibraryRemoved(const char[] name) {
	if (StrEqual(name, "nativevotes")) depNativeVotes = false;
}

static void DHooksAttach() {
	if (hdl_INextBot_IsEnemy != INVALID_HANDLE && !detoured_INextBot_IsEnemy) {
		detoured_INextBot_IsEnemy = DHookEnableDetour(hdl_INextBot_IsEnemy, true, Detour_INextBot_IsEnemy);
	} else {
		PrintToServer("Could not hook INextBot::IsEnemy(this,CBaseEntity*). Bots will shoot at protected players!");
	}
	if (hdl_CZombieAttack_IsPotentiallyChaseable != INVALID_HANDLE && !detoured_CZombieAttack_IsPotentiallyChaseable) {
		detoured_CZombieAttack_IsPotentiallyChaseable = DHookEnableDetour(hdl_CZombieAttack_IsPotentiallyChaseable, true, Detour_CZombieAttack_IsPotentiallyChaseable);
	} else {
		PrintToServer("Could not hook CZombieAttack::IsPotentiallyChaseable(this,CZombie*,CBaseCombatCharacter*)");
	}
	if (hdl_CHeadlessHatmanAttack_IsPotentiallyChaseable != INVALID_HANDLE && !detoured_CHeadlessHatmanAttack_IsPotentiallyChaseable) {
		detoured_CHeadlessHatmanAttack_IsPotentiallyChaseable = DHookEnableDetour(hdl_CHeadlessHatmanAttack_IsPotentiallyChaseable, true, Detour_BossAttack_IsPotentiallyChaseable);
	} else {
		PrintToServer("Could not hook CHeadlessHatmanAttack::IsPotentiallyChaseable(this,CZombie*,CBaseCombatCharacter*)");
	}
	if (hdl_CMerasmusAttack_IsPotentiallyChaseable != INVALID_HANDLE && !detoured_CMerasmusAttack_IsPotentiallyChaseable) {
		detoured_CMerasmusAttack_IsPotentiallyChaseable = DHookEnableDetour(hdl_CMerasmusAttack_IsPotentiallyChaseable, true, Detour_BossAttack_IsPotentiallyChaseable);
	} else {
		PrintToServer("Could not hook CMerasmusAttack::IsPotentiallyChaseable(this,CZombie*,CBaseCombatCharacter*)");
	}
	if (hdl_CEyeballBoss_FindClosestVisibleVictim != INVALID_HANDLE && !detoured_CEyeballBoss_FindClosestVisibleVictim) {
		detoured_CEyeballBoss_FindClosestVisibleVictim = DHookEnableDetour(hdl_CEyeballBoss_FindClosestVisibleVictim, true, Detour_CEyeballBoss_FindClosestVisibleVictim);
	} else {
		PrintToServer("Could not hook CEyeballBoss::FindClosestVisibleVictim(this)");
	}
	if (hdl_CTFPlayer_ApplyGenericPushbackImpulse != INVALID_HANDLE && !detoured_CTFPlayer_ApplyGenericPushbackImpulse) {
		detoured_CTFPlayer_ApplyGenericPushbackImpulse = DHookEnableDetour(hdl_CTFPlayer_ApplyGenericPushbackImpulse, false, Detour_CTFPlayer_ApplyGenericPushbackImpulse);
	} else {
		PrintToServer("Could not hook CTFPlayer::ApplyGenericPushbackImpulse(Vector*,CTFPlayer*). This will be pushy!");
	}
	if (hdl_CObjectSentrygun_ValidTargetPlayer != INVALID_HANDLE && !detoured_CObjectSentrygun_ValidTargetPlayer) {
		detoured_CObjectSentrygun_ValidTargetPlayer = DHookEnableDetour(hdl_CObjectSentrygun_ValidTargetPlayer, true, Detour_CObjectSentrygun_ValidTargetPlayer);
	} else {
		PrintToServer("Could not hook CObjectSentrygun::ValidTargetPlayer(CTFPlayer*,Vector*,Vector*). Whack!");
	}
	if (hdl_CObjectSentrygun_FoundTarget != INVALID_HANDLE && !detoured_CObjectSentrygun_FoundTarget) {
		detoured_CObjectSentrygun_FoundTarget = DHookEnableDetour(hdl_CObjectSentrygun_FoundTarget, false, Detour_CObjectSentrygun_FoundTarget);
	} else {
		PrintToServer("Could not hook CObjectSentrygun::FoundTarget(CTFPlayer*,Vector*,bool). Turrets will always track zombies and bosses!");
	}
}
static void DHooksDetach() {
	if (hdl_INextBot_IsEnemy != INVALID_HANDLE && detoured_INextBot_IsEnemy)
		detoured_INextBot_IsEnemy ^= DHookDisableDetour(hdl_INextBot_IsEnemy, true, Detour_INextBot_IsEnemy);
	if (hdl_CZombieAttack_IsPotentiallyChaseable != INVALID_HANDLE && detoured_CZombieAttack_IsPotentiallyChaseable)
		detoured_CZombieAttack_IsPotentiallyChaseable ^= DHookDisableDetour(hdl_CZombieAttack_IsPotentiallyChaseable, true, Detour_CZombieAttack_IsPotentiallyChaseable);
	if (hdl_CHeadlessHatmanAttack_IsPotentiallyChaseable != INVALID_HANDLE && detoured_CHeadlessHatmanAttack_IsPotentiallyChaseable)
		detoured_CHeadlessHatmanAttack_IsPotentiallyChaseable ^= DHookDisableDetour(hdl_CHeadlessHatmanAttack_IsPotentiallyChaseable, true, Detour_BossAttack_IsPotentiallyChaseable);
	if (hdl_CMerasmusAttack_IsPotentiallyChaseable != INVALID_HANDLE && detoured_CMerasmusAttack_IsPotentiallyChaseable)
		detoured_CMerasmusAttack_IsPotentiallyChaseable ^= DHookDisableDetour(hdl_CMerasmusAttack_IsPotentiallyChaseable, true, Detour_BossAttack_IsPotentiallyChaseable);
	if (hdl_CEyeballBoss_FindClosestVisibleVictim != INVALID_HANDLE && detoured_CEyeballBoss_FindClosestVisibleVictim)
		detoured_CEyeballBoss_FindClosestVisibleVictim ^= DHookDisableDetour(hdl_CEyeballBoss_FindClosestVisibleVictim, true, Detour_CEyeballBoss_FindClosestVisibleVictim);
	if (hdl_CTFPlayer_ApplyGenericPushbackImpulse != INVALID_HANDLE && detoured_CTFPlayer_ApplyGenericPushbackImpulse)
		detoured_CTFPlayer_ApplyGenericPushbackImpulse ^= DHookDisableDetour(hdl_CTFPlayer_ApplyGenericPushbackImpulse, false, Detour_CTFPlayer_ApplyGenericPushbackImpulse);
	if (hdl_CObjectSentrygun_ValidTargetPlayer != INVALID_HANDLE && detoured_CObjectSentrygun_ValidTargetPlayer)
		detoured_CObjectSentrygun_ValidTargetPlayer ^= DHookDisableDetour(hdl_CObjectSentrygun_ValidTargetPlayer, true, Detour_CObjectSentrygun_ValidTargetPlayer);
	if (hdl_CObjectSentrygun_FoundTarget != INVALID_HANDLE && detoured_CObjectSentrygun_FoundTarget)
		detoured_CObjectSentrygun_FoundTarget ^= DHookDisableDetour(hdl_CObjectSentrygun_FoundTarget, false, Detour_CObjectSentrygun_FoundTarget);
}

public void OnMapEnd() {
	globalPvP[0] = State_Disabled;
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
	globalPvP[client] = State_Disabled;
	SetPairPvPClient(client);
	pairPvPrequest[client]=0;
	pairPvPignored[client]=false;
	clientFirstSpawn[client]=true;
	allowTauntKilled[client]=false;
	allowLimitedConditions[client]=false;
	mirrorDamage[client] = State_Disabled;
	clientLatestPvPStart[client] = -PvP_DISENGAGE_COOLDOWN;
	clientLatestPvPRequest[client] = -PvP_PAIRREQUEST_COOLDOWN;
}
public void OnClientDisconnect(int client) {
	globalPvP[client] = State_Disabled;
	SetPairPvPClient(client);
	pairPvPrequest[client]=0;
	pairPvPignored[client]=false;
	clientFirstSpawn[client]=true;
	allowTauntKilled[client]=false;
	allowLimitedConditions[client]=false;
	mirrorDamage[client] = State_Disabled;
	clientLatestPvPStart[client] = -PvP_DISENGAGE_COOLDOWN;
	clientLatestPvPRequest[client] = -PvP_PAIRREQUEST_COOLDOWN;
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
	char buffer[2];
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
			if (IsGlobalPvP(i) ^ invert) {
				clients.Push(i);
			}
		}
	}
	return true;
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
	if (GetCmdArgs()==0) {
		bool enterPvP = !(globalPvP[client]&State_Enabled);
		//timeLeft = cooldown - time spent in pvp
		float timeLeft = PvP_DISENGAGE_COOLDOWN - (GetClientTime(client) - clientLatestPvPStart[client]);
		if (!enterPvP && timeLeft > 0.0) {
			CPrintToChat(client, "%t", "Entered global pvp too recently", RoundToCeil(timeLeft));
			return Plugin_Handled;
		}
		if (enterPvP) clientLatestPvPStart[client] = GetClientTime(client);
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
					if (!Client_IsIngame(i)) continue;
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
	if (requester == requestee) {
		//silent fail
	} else if (antiSpam && (tmp = (PvP_PAIRREQUEST_COOLDOWN - (GetClientTime(requester) - clientLatestPvPRequest[requester]))) > 0.0) {
		CPrintToChat(requester, "%t", "Last pair pvp request too recent", RoundToCeil(tmp));
//	} else if (IsFakeClient(requestee)) {
//		CPrintToChat(requester, "%t", "Bots can not use pair pvp");
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
		PrintToServer("NativeVote Interrupted");
		view_as<NativeVote>(pairPvPVoteData.Get(at)).Close(); //will decline requests if not done yet
		pairPvPVoteData.Erase(at); //late erase to allow cancelling of ui
	}
}
public int PairPvPNativeVote(NativeVote vote, MenuAction action, int param1, int param2) {
	int at = pairPvPVoteData.FindValue(vote);
	any vdata[4];
	if (at >= 0) pairPvPVoteData.GetArray(at, vdata);
	if (action == MenuAction_End) {
		PrintToServer("NativeVote END");
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
		PrintToServer("NativeVote VoteEnd");
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
static void PrintGlobalPvpState(int client) {
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
static bool SetPairPvP(int client1, int client2, bool pvp) {
	if (Notify_OnPairChanged(client1, client2, pvp)) {
		pairPvP[client1][client2] = pairPvP[client2][client1] = pvp;
		return true;
	} else return false;
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

static bool CanClientsPvP(int client1, int client2) {
	return client1==client2 ||
		globalPvP[0]!=State_Disabled ||
		(IsGlobalPvP(client1) && IsGlobalPvP(client2)) ||
		pairPvP[client1][client2];
		//duels should be checked here
}
//endregion

//region actual damage blocking and entity stuff

// this dhook simply makes bots ignore players that dont want to pvp
public MRESReturn Detour_INextBot_IsEnemy(Address pThis, DHookReturn hReturn, DHookParam hParams) {
	int target = hParams.Get(1);
	int player = GetPlayerEntity(target);
	if (Client_IsValid(player) && !IsGlobalPvP(player) && !IsGlobalPvP(0)) {
		hReturn.Value = false;
		return MRES_Override;
	}
	return MRES_Ignored;
}

public MRESReturn Detour_CZombieAttack_IsPotentiallyChaseable(DHookReturn hReturn, DHookParam hParams) {
	if (hParams.IsNull(2))
		return MRES_Ignored;// we're not changing behaviour
	int player = hParams.Get(2);
	ePlayerVsAiFlags targetMode = pvaPlayers & PvA_ZOMBIES;
	bool blocked;
	if (targetMode == PvA_Zombies_Always) return MRES_Ignored;
	else if (targetMode != PvA_Zombies_GlobalPvP) blocked = true;
	else blocked = Client_IsValid(player) && !IsGlobalPvP(player) && !IsGlobalPvP(0);
	if (blocked) {
		hReturn.Value = false;
		return MRES_Override;
	}
	return MRES_Ignored;
}
public MRESReturn Detour_BossAttack_IsPotentiallyChaseable(DHookReturn hReturn, DHookParam hParams) {
	if (hParams.IsNull(2))
		return MRES_Ignored;// we're not changing behaviour
	int player = hParams.Get(2);
	ePlayerVsAiFlags targetMode = pvaPlayers & PvA_BOSSES;
	bool blocked;
	if (targetMode == PvA_Bosses_Always) return MRES_Ignored;
	else if (targetMode != PvA_Bosses_GlobalPvP) blocked = true;
	else blocked = Client_IsValid(player) && !IsGlobalPvP(player) && !IsGlobalPvP(0);
	if (blocked) {
		hReturn.Value = false;
		return MRES_Override;
	}
	return MRES_Ignored;
}
public MRESReturn Detour_CEyeballBoss_FindClosestVisibleVictim(int eyeball, DHookReturn hReturn) {
	int target = hReturn.Value;
	if (1 > target > MaxClients) return MRES_Ignored; //not targeting a player
	ePlayerVsAiFlags targetMode = pvaPlayers & PvA_BOSSES;
	bool blocked;
	if (targetMode == PvA_Bosses_Always) return MRES_Ignored;
	else if (targetMode != PvA_Bosses_GlobalPvP) blocked = true;
	else blocked = Client_IsValid(target) && !IsGlobalPvP(target) && !IsGlobalPvP(0);
	if (blocked) {
		hReturn.Value = INVALID_ENT_REFERENCE;
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
	int target = hParams.Get(1);
	int engi = GetPlayerEntity(building);
	if (Client_IsValid(target) && Client_IsValid(engi) && !CanClientsPvP(engi,target)) {
		hReturn.Value = false;
		return MRES_Override; //idk what whacky stuff valve is doing there
	}
	return MRES_Ignored;
}

public MRESReturn Detour_CObjectSentrygun_FoundTarget(int building, DHookParam hParams) {
	if (hParams.IsNull(1)) return MRES_Ignored;
	int target = hParams.Get(1);
	int engi = GetPlayerEntity(building);
	bool blocked;
	char classname[64];
	if (target == INVALID_ENT_REFERENCE) return MRES_Ignored; //error, do whatever you want
	GetEntityClassname(target, classname, sizeof(classname));
	if (IsEntityZombie(classname)) {
		//we are trying to target a zombie, are we allowed to do at all?
		ePlayerVsAiFlags mode = pvaBuildings & PvA_ZOMBIES;
		if (mode == PvA_Zombies_Always) blocked = false;
		else if (mode != PvA_Zombies_GlobalPvP) blocked = true;
		else blocked = Client_IsValid(engi) && !IsGlobalPvP(engi) && !IsGlobalPvP(0);
	} else if (IsEntityBoss(classname)) {
		//we are trying to target a boss, are we allowed to do at all?
		ePlayerVsAiFlags mode = pvaBuildings & PvA_BOSSES;
		if (mode == PvA_Bosses_Always) blocked = false;
		else if (mode != PvA_Bosses_GlobalPvP) blocked = true;
		else blocked = Client_IsValid(engi) && !IsGlobalPvP(engi) && !IsGlobalPvP(0);
	} else if (IsEntityBuilding(classname)) {
		//hey ho, we target another building
		int otherEngi = GetPlayerEntity(target);
		blocked = Client_IsValid(otherEngi) && !CanClientsPvP(engi,otherEngi);
	}
	return blocked ? MRES_Supercede: MRES_Ignored; //skip setting the target if blocked
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
	} else if (IsEntityZombie(classname)) {
		SDKHook(entity, SDKHook_OnTakeDamage, OnZombieTakeDamage);
	} else if (IsEntityBoss(classname)) {
		SDKHook(entity, SDKHook_OnTakeDamage, OnBossTakeDamage);
	} else if (IsEntityBuilding(classname)) {
		SDKHook(entity, SDKHook_OnTakeDamage, OnBuildingTakeDamage);
	}
}

static void SDKHookClient(int client) {
	SDKHook(client, SDKHook_OnTakeDamage, OnClientTakeDamage);
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
	
	//Sometimes the attacker won't be a player directly, try to resolve this
	int source = GetPlayerDamageSource(attacker, inflictor);
	if (!Client_IsValid(source))
		return Plugin_Continue;
	
	else if (victim == source || CanClientsPvP(victim, source))
		return Plugin_Continue; //pvp is on, go nuts
	else if (IsMirrored(source)) {
		if (damagecustom == TF_CUSTOM_BACKSTAB)
			damage = GetClientHealth(source) * 6.0;
		SDKHooks_TakeDamage(source, inflictor, source, damage, damagetype, weapon, damageForce, damagePosition);
		//damage was mirrored
	} else if (allowTauntKilled[victim] && TF2_IsPlayerInCondition(source, TFCond_Taunting))
		return Plugin_Continue; //allow taunt-kill explicitly
		
	//block damage on victim
	damage = 0.0;
	ScaleVector(damageForce, 0.0);
	return Plugin_Handled;
}
static void OnClientSpawnPost(int client) {
	if (GetClientTeam(client)<=1 || IsFakeClient(client)) return;
	UpdateEntityFlagsGlobalPvP(client, IsGlobalPvP(client));
	if (clientFirstSpawn[client]) {
		clientFirstSpawn[client] = false;
		PrintGlobalPvpState(client);
	}
}
public void OnInventoryApplicationPost(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	UpdateEntityFlagsGlobalPvP(client, IsGlobalPvP(client));
}

public void TF2_OnConditionAdded(int client, TFCond condition) {
	int provider, at;
	if (!isActive) return;
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

static void UpdateEntityFlagsGlobalPvP(int client, bool pvp) {
	if (!Client_IsIngame(client)) return;
	int ci;
	if (TF2_GetClientTeam(client)==TFTeam_Blue) ci++;
	if (!pvp && isActive) ci+=2;
	if (usePlayerStateColors)
		SetPlayerColor(client, playerStateColors[ci][0], playerStateColors[ci][1], playerStateColors[ci][2], playerStateColors[ci][3]);
}

//endregion

//region natives

public APLRes AskPluginLoad2(Handle plugin, bool late, char[] error, int err_max) {
    CreateNative("pvp_IsActive",        Native_IsActive);
    CreateNative("pvp_GetPlayerGlobal", Native_GetPlayerGlobal);
    CreateNative("pvp_SetPlayerGlobal", Native_SetPlayerGlobal);
    CreateNative("pvp_GetPlayerPair",   Native_GetPlayerPair);
    CreateNative("pvp_ForcePlayerPair", Native_ForcePlayerPair);
    CreateNative("pvp_CanAttack",       Native_CanAttack);
    CreateNative("pvp_IsMirrored",      Native_IsMirrored);
    CreateNative("pvp_SetMirrored",     Native_SetMirrored);
    
    RegPluginLibrary("pvpoptin");
}

//native bool pvp_IsActive();
public any Native_IsActive(Handle plugin, int numParams) {
	return isActive;
}
//native bool pvp_GetPlayerGlobal(int client, pvpEnabledState& pvpState = PVPState_Disabled);
public any Native_GetPlayerGlobal(Handle plugin, int numParams) {
	int client = GetNativeCell(1);
	if (!Client_IsIngame(client)) ThrowNativeError(SP_ERROR_PARAM, "Invalid client index or client not ingame (%i)", client);
	SetNativeCellRef(2, globalPvP[client]);
	return IsGlobalPvP(client);
}
//native void pvp_SetPlayerGlobal(int client, int value=-1);
public any Native_SetPlayerGlobal(Handle plugin, int numParams) {
	int client = GetNativeCell(1);
	if (!Client_IsIngame(client)) ThrowNativeError(SP_ERROR_PARAM, "Invalid client index or client not ingame (%i)", client);
	int value = GetNativeCell(2);
	bool wasGlobalPvP = IsGlobalPvP(client);
	
	eEnabledState sflag = State_Disabled;
	if (value > 0) sflag = State_ExternalOn;
	else if (value == 0) sflag = State_ExternalOff;
	sflag = (globalPvP[client] & ~ENABLEDMASK_EXTERNAL) | sflag;
	
	if (Notify_OnGlobalChanged(client, sflag)) {
		globalPvP[client] = sflag;
		if (wasGlobalPvP != IsGlobalPvP(client)) {
			UpdateEntityFlagsGlobalPvP(client, IsGlobalPvP(client));
			PrintGlobalPvpState(client);
		}
	}
}
//native bool pvp_GetPlayerPair(int client1, int client2);
public any Native_GetPlayerPair(Handle plugin, int numParams) {
	int client1 = GetNativeCell(1);
	int client2 = GetNativeCell(2);
	if (!Client_IsIngame(client1)) ThrowNativeError(SP_ERROR_PARAM, "Invalid client inde or client not ingame for arg1 (%i)", client1);
	if (!Client_IsIngame(client2)) ThrowNativeError(SP_ERROR_PARAM, "Invalid client inde or client not ingame for arg2 (%i)", client2);
	return pairPvP[client1][client2];
}
//native void pvp_ForcePlayerPair(int client1, int client2, bool value);
public any Native_ForcePlayerPair(Handle plugin, int numParams) {
	int client1 = GetNativeCell(1);
	int client2 = GetNativeCell(2);
	bool force = GetNativeCell(3);
	if (!Client_IsIngame(client1)) ThrowNativeError(SP_ERROR_PARAM, "Invalid client inde or client not ingame for arg1 (%i)", client1);
	if (!Client_IsIngame(client2)) ThrowNativeError(SP_ERROR_PARAM, "Invalid client inde or client not ingame for arg2 (%i)", client2);
	bool oldValue = pairPvP[client1][client2];
	if (oldValue != force && client1!=client2 && Notify_OnPairChanged(client1, client2, force)) {
		SetPairPvP(client1,client2,force);
	}
}
//native bool pvp_CanAttack(int client1, int client2);
public any Native_CanAttack(Handle plugin, int numParams) {
	int client1 = GetNativeCell(1);
	int client2 = GetNativeCell(2);
	if (!Client_IsIngame(client1)) ThrowNativeError(SP_ERROR_PARAM, "Invalid client inde or client not ingame for arg1 (%i)", client1);
	if (!Client_IsIngame(client2)) ThrowNativeError(SP_ERROR_PARAM, "Invalid client inde or client not ingame for arg2 (%i)", client2);
	return CanClientsPvP(client1, client2);
}
//native bool pvp_IsMirrored(int client, pvpEnabledState& pvpState = PVPState_Disabled );
public any Native_IsMirrored(Handle plugin, int numParams) {
	int client = GetNativeCell(1);
	if (!Client_IsIngame(client)) ThrowNativeError(SP_ERROR_PARAM, "Invalid client index or client not ingame (%i)", client);
	SetNativeCellRef(2, mirrorDamage[client]);
	return IsMirrored(client);
}
//native void pvp_SetMirrored(int client, int value=-1);
public any Native_SetMirrored(Handle plugin, int numParams) {
	int client = GetNativeCell(1);
	if (!Client_IsIngame(client)) ThrowNativeError(SP_ERROR_PARAM, "Invalid client index or client not ingame (%i)", client);
	int value = GetNativeCell(2);
	
	eEnabledState sflag = State_Disabled;
	if (value > 0) sflag = State_ExternalOn;
	else if (value == 0) sflag = State_ExternalOff;
	sflag = (mirrorDamage[client] & ~ENABLEDMASK_EXTERNAL) | sflag;
	
	globalPvP[client] = sflag;
}

//return true to continue
static bool Notify_OnGlobalChanged(int client, eEnabledState& value) {
	eEnabledState svalue = value;
	Action result;
	Call_StartForward(fwdGlobalChanged);
	Call_PushCell(client);
	Call_PushCell(globalPvP[client]);
	Call_PushCellRef(svalue);
	Call_Finish(result);
	switch (result) {
		case Plugin_Continue: return true;
		case Plugin_Changed: { 
			//only modify legal values (external*) in the ref value
			eEnabledState changed = (value ^ svalue) & ENABLEDMASK_EXTERNAL;
			value ^= changed;
			return true;
		}
		default: return false;
	}
}
//return true to continue
static bool Notify_OnPairInvited(int requester, int requestee) {
	Action result;
	Call_StartForward(fwdPairInvited);
	Call_PushCell(requester);
	Call_PushCell(requestee);
	Call_Finish(result);
	switch (result) {
		case Plugin_Continue: return true;
		default: return false;
	}
}
//return true to continue
static bool Notify_OnPairChanged(int client1, int client2, bool changedOn) {
	Action result;
	Call_StartForward(fwdPairChanged);
	Call_PushCell(client1);
	Call_PushCell(client2);
	Call_PushCell(changedOn);
	Call_Finish(result);
	switch (result) {
		case Plugin_Continue: return true;
		default: return false;
	}
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

/**
 * if the entity is a client, return the client. otherwise try to resolve m_hBuilder
 * @return the player associated with this entity or INVALID_ENT_REFERENCE if none
 */
static int GetPlayerEntity(int entity) {
	int tmp;
	if (1<=entity<=MaxClients)
		return entity;
	else if (HasEntProp(entity, Prop_Send, "m_hBuilder") && 1 <= (tmp=GetEntPropEnt(entity, Prop_Send, "m_hBuilder")) <= MaxClients)
		//obviously, this get's the engineer that built this entity as building
		return tmp;
	else if (HasEntProp(entity, Prop_Data, "m_hPlayer") && 1 <= (tmp=GetEntPropEnt(entity, Prop_Data, "m_hPlayer")) <= MaxClients)
		//this is the prop to look at for vehicles
		return tmp;
	else
		return INVALID_ENT_REFERENCE;
}

static bool IsEntityZombie(const char[] classname) {
	return StrEqual(classname,"tf_zombie");
}
static bool IsEntityBoss(const char[] classname) {
	return (StrEqual(classname, "merasmus") || StrEqual(classname, "headless_hatman") || StrEqual(classname, "eyeball_boss"));
}
static bool IsEntityBuilding(const char[] classname) {
	return (StrEqual(classname, "obj_sentrygun") || StrEqual(classname, "obj_dispenser") || StrEqual(classname, "obj_teleporter"));
}

static int GetPlayerDamageSource(int attacker, int inflictor) {
	int source = attacker;
	if (IsValidEntity(attacker) && 1 <= attacker <= MaxClients) 
		return attacker;
	// Sometimes the attacker won't be a player
	else if (IsValidEntity(inflictor) && 1 <= (source = GetPlayerEntity(inflictor)) <= MaxClients) 
		// so we try to determin the player damage source from the inflictor. mostly projectiles
		return source;
	else if (IsValidEntity(attacker) && 1 <= (source = GetPlayerEntity(attacker)) <= MaxClients)
		// if that's not a player, we try to get the damage source from the attacker entity. this will mostly be npcs tho
		return source;
	else
		// if we still couldn't find a player, we give up
		return INVALID_ENT_REFERENCE ;
}

//endregion
