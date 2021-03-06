#if defined _pvpoptin_dtours
 #endinput
#endif
#define _pvpoptin_dtours
#if !defined PLUGIN_VERSION
 #error Please compile the main file
#endif

#include <dhooks>

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
static DHookSetup hdl_CWeaponMedigun_AllowedToHealTarget;
static bool detoured_CWeaponMedigun_AllowedToHealTarget;

void Plugin_SetupDHooks() {
	GameData pvpfundata = new GameData("pvpoptin.games");
	if (pvpfundata != INVALID_HANDLE) {
		//to find this signature you can go up Spawn function through powerups to bonuspacks.
		//that has a call to GetTeamNumber and IsEnemy is basically a function with that call twice.
		//The first 20-something bytes of the signature are unlikely to change, just chip from the end and you should find it.
		hdl_INextBot_IsEnemy = DHookCreateFromConf(pvpfundata, "INextBot_IsEnemy");
		hdl_CZombieAttack_IsPotentiallyChaseable = DHookCreateFromConf(pvpfundata, "CZombieAttack_IsPotentiallyChaseable");
		hdl_CHeadlessHatmanAttack_IsPotentiallyChaseable = DHookCreateFromConf(pvpfundata, "CHeadlessHatmanAttack_IsPotentiallyChaseable");
		hdl_CMerasmusAttack_IsPotentiallyChaseable = DHookCreateFromConf(pvpfundata, "CMerasmusAttack_IsPotentiallyChaseable");
		hdl_CEyeballBoss_FindClosestVisibleVictim = DHookCreateFromConf(pvpfundata, "CEyeballBoss_FindClosestVisibleVictim");
		hdl_CTFPlayer_ApplyGenericPushbackImpulse = DHookCreateFromConf(pvpfundata, "CTFPlayer_ApplyGenericPushbackImpulse");
		hdl_CObjectSentrygun_ValidTargetPlayer = DHookCreateFromConf(pvpfundata, "CObjectSentrygun_ValidTargetPlayer");
		hdl_CObjectSentrygun_FoundTarget = DHookCreateFromConf(pvpfundata, "CObjectSentrygun_FoundTarget");
		//for windows, find a function with the string "weapon_blocks_healing" where the callee has the string "MedigunHealTargetThink" for i think CWeaponMedigun::FindNewTargetForSlot
		hdl_CWeaponMedigun_AllowedToHealTarget = DHookCreateFromConf(pvpfundata, "CWeaponMedigun_AllowedToHealTarget");
		delete pvpfundata;
	}
}

void DHooksAttach() {
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
	if (hdl_CWeaponMedigun_AllowedToHealTarget != INVALID_HANDLE && !detoured_CWeaponMedigun_AllowedToHealTarget) {
		detoured_CWeaponMedigun_AllowedToHealTarget = DHookEnableDetour(hdl_CWeaponMedigun_AllowedToHealTarget, false, Detour_CWeaponMedigun_AllowedToHealTarget);
	} else {
		PrintToServer("Could not hook CWeaponMedigun::AllowedToHealTarget(CBaseEntity*). Medic can grief PvP duels!");
	}
}
void DHooksDetach() {
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
	if (hdl_CWeaponMedigun_AllowedToHealTarget != INVALID_HANDLE && detoured_CWeaponMedigun_AllowedToHealTarget)
		detoured_CWeaponMedigun_AllowedToHealTarget ^= DHookDisableDetour(hdl_CWeaponMedigun_AllowedToHealTarget, false, Detour_CWeaponMedigun_AllowedToHealTarget);
}

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

public MRESReturn Detour_CWeaponMedigun_AllowedToHealTarget(int weapon, DHookReturn hReturn, DHookParam hParams) {
	int target = hParams.Get(1);
	if (!(1<=target<=MaxClients))
		return MRES_Ignored;
	int medic = GetEntPropEnt(weapon, Prop_Send, "m_hOwner");
	if (!(1<=medic<=MaxClients))
		return MRES_Ignored; //no owner?!
	
	if (IsGlobalPvP(medic) && IsGlobalPvP(target))
		return MRES_Ignored; //healing is allowed in global pvp
	
	clientInvalidHealNotif[medic] = true;
	hReturn.Value = false;
	return MRES_Supercede;
}

//keep as simple and quick as possible
//don't check result, that does NOT pass the previous result!
public Action CH_PassFilter(int ent1, int ent2, bool &result) {
	if (isActive && noCollideState && 1<=ent1<=MaxClients && 1<=ent2<=MaxClients) {
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

