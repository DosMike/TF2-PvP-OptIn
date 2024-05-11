#if defined _pvpoptin_dtours
 #endinput
#endif
#define _pvpoptin_dtours
#if !defined PLUGIN_VERSION
 #error Please compile the main file
#endif

#include <dhooks>

static DynamicDetour hdl_INextBot_IsEnemy;
static bool detoured_INextBot_IsEnemy;
static DynamicDetour hdl_CZombieAttack_IsPotentiallyChaseable;
static bool detoured_CZombieAttack_IsPotentiallyChaseable;
static DynamicDetour hdl_CHeadlessHatmanAttack_IsPotentiallyChaseable;
static bool detoured_CHeadlessHatmanAttack_IsPotentiallyChaseable;
static DynamicDetour hdl_CMerasmusAttack_IsPotentiallyChaseable;
static bool detoured_CMerasmusAttack_IsPotentiallyChaseable;
static DynamicHook hdl_CEyeballBoss_IsLineOfSightClear;
static DynamicDetour hdl_CTFPlayer_ApplyGenericPushbackImpulse;
static bool detoured_CTFPlayer_ApplyGenericPushbackImpulse;
static DynamicDetour hdl_CObjectSentrygun_ValidTargetPlayer;
static bool detoured_CObjectSentrygun_ValidTargetPlayer;
static DynamicDetour hdl_CObjectSentrygun_ValidTargetBot;
static bool detoured_CObjectSentrygun_ValidTargetBot;
static DynamicDetour hdl_CObjectSentrygun_ValidTargetObject;
static bool detoured_CObjectSentrygun_ValidTargetObject;
static DynamicDetour hdl_CWeaponMedigun_AllowedToHealTarget;
static bool detoured_CWeaponMedigun_AllowedToHealTarget;
static DynamicDetour hdl_CTFProjectile_HealingBolt_ImpactTeamPlayer;
static bool detoured_CTFProjectile_HealingBolt_ImpactTeamPlayer;
static DynamicDetour hdl_CTFPlayerClassShared_SetCustomModel;
static bool detoured_CTFPlayerClassShared_SetCustomModel;
static int offset_CTFPlayer_m_PlayerClass;

void Plugin_SetupDHooks() {
	GameData pvpfundata = new GameData("pvpoptin.games");
	if (pvpfundata != INVALID_HANDLE) {
		//to find this signature you can go up Spawn function through powerups to bonuspacks.
		//that has a call to GetTeamNumber and IsEnemy is basically a function with that call twice.
		//The first 20-something bytes of the signature are unlikely to change, just chip from the end and you should find it.
		hdl_INextBot_IsEnemy = DynamicDetour.FromConf(pvpfundata, "INextBot::IsEnemy()");
		hdl_CZombieAttack_IsPotentiallyChaseable = DynamicDetour.FromConf(pvpfundata, "CZombieAttack::IsPotentiallyChaseable()");
		hdl_CHeadlessHatmanAttack_IsPotentiallyChaseable = DynamicDetour.FromConf(pvpfundata, "CHeadlessHatmanAttack::IsPotentiallyChaseable()");
		hdl_CMerasmusAttack_IsPotentiallyChaseable = DynamicDetour.FromConf(pvpfundata, "CMerasmusAttack::IsPotentiallyChaseable()");
		hdl_CEyeballBoss_IsLineOfSightClear = DynamicHook.FromConf(pvpfundata, "CEyeballBoss::IsLineOfSightClear()");
		hdl_CTFPlayer_ApplyGenericPushbackImpulse = DynamicDetour.FromConf(pvpfundata, "CTFPlayer::ApplyGenericPushbackImpulse()");
		hdl_CObjectSentrygun_ValidTargetPlayer = DynamicDetour.FromConf(pvpfundata, "CObjectSentrygun::ValidTargetPlayer()");
		hdl_CObjectSentrygun_ValidTargetBot = DynamicDetour.FromConf(pvpfundata, "CObjectSentrygun::ValidTargetBot()");
		hdl_CObjectSentrygun_ValidTargetObject = DynamicDetour.FromConf(pvpfundata, "CObjectSentrygun::ValidTargetObject()");
		//for windows, find a function with the string "weapon_blocks_healing" where the callee has the string "MedigunHealTargetThink" for i think CWeaponMedigun::FindNewTargetForSlot
		hdl_CWeaponMedigun_AllowedToHealTarget = DynamicDetour.FromConf(pvpfundata, "CWeaponMedigun::AllowedToHealTarget()");
		hdl_CTFProjectile_HealingBolt_ImpactTeamPlayer = DynamicDetour.FromConf(pvpfundata, "CTFProjectile_HealingBolt::ImpactTeamPlayer()");
		hdl_CTFPlayerClassShared_SetCustomModel = DynamicDetour.FromConf(pvpfundata, "CTFPlayerClassShared::SetCustomModel()");
		offset_CTFPlayer_m_PlayerClass = pvpfundata.GetOffset("CTFPlayer::m_PlayerClass");
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
	if (hdl_CTFPlayer_ApplyGenericPushbackImpulse != INVALID_HANDLE && !detoured_CTFPlayer_ApplyGenericPushbackImpulse) {
		detoured_CTFPlayer_ApplyGenericPushbackImpulse = DHookEnableDetour(hdl_CTFPlayer_ApplyGenericPushbackImpulse, false, Detour_CTFPlayer_ApplyGenericPushbackImpulse);
	} else {
		PrintToServer("Could not hook CTFPlayer::ApplyGenericPushbackImpulse(Vector*,CTFPlayer*). This will be pushy!");
	}
	if (hdl_CObjectSentrygun_ValidTargetPlayer != INVALID_HANDLE && !detoured_CObjectSentrygun_ValidTargetPlayer) {
		detoured_CObjectSentrygun_ValidTargetPlayer = DHookEnableDetour(hdl_CObjectSentrygun_ValidTargetPlayer, true, Detour_CObjectSentrygun_ValidTargetPlayer);
	} else {
		PrintToServer("Could not hook CObjectSentrygun::ValidTargetPlayer(). Turrets will always track players!");
	}
	if (hdl_CObjectSentrygun_ValidTargetBot != INVALID_HANDLE && !detoured_CObjectSentrygun_ValidTargetBot) {
		detoured_CObjectSentrygun_ValidTargetBot = DHookEnableDetour(hdl_CObjectSentrygun_ValidTargetBot, true, Detour_CObjectSentrygun_ValidTargetBot);
	} else {
		PrintToServer("Could not hook CObjectSentrygun::ValidTargetBot(). Turrets will always track zombies and bosses!");
	}
	if (hdl_CObjectSentrygun_ValidTargetObject != INVALID_HANDLE && !detoured_CObjectSentrygun_ValidTargetObject) {
		detoured_CObjectSentrygun_ValidTargetObject = DHookEnableDetour(hdl_CObjectSentrygun_ValidTargetObject, true, Detour_CObjectSentrygun_ValidTargetObject);
	} else {
		PrintToServer("Could not hook CObjectSentrygun::ValidTargetObject(). Turrets will always track objects!");
	}
	if (hdl_CWeaponMedigun_AllowedToHealTarget != INVALID_HANDLE && !detoured_CWeaponMedigun_AllowedToHealTarget) {
		detoured_CWeaponMedigun_AllowedToHealTarget = DHookEnableDetour(hdl_CWeaponMedigun_AllowedToHealTarget, false, Detour_CWeaponMedigun_AllowedToHealTarget);
	} else {
		PrintToServer("Could not hook CWeaponMedigun::AllowedToHealTarget(CBaseEntity*). Medic can grief PvP duels!");
	}
	if (hdl_CTFProjectile_HealingBolt_ImpactTeamPlayer != INVALID_HANDLE && !detoured_CTFProjectile_HealingBolt_ImpactTeamPlayer) {
		detoured_CTFProjectile_HealingBolt_ImpactTeamPlayer = DHookEnableDetour(hdl_CTFProjectile_HealingBolt_ImpactTeamPlayer, false, Detour_CTFProjectile_HealingBolt_ImpactTeamPlayer);
	} else {
		PrintToServer("Could not hook CTFProjectile_HealingBolt::ImpactTeamPlayer(CBaseEntity*). Medic can grief PvP duels!");
	}
	if (hdl_CTFPlayerClassShared_SetCustomModel != INVALID_HANDLE && !detoured_CTFPlayerClassShared_SetCustomModel) {
		detoured_CTFPlayerClassShared_SetCustomModel = DHookEnableDetour(hdl_CTFPlayerClassShared_SetCustomModel, true, Detour_CTFPlayerClassShared_SetCustomModel);
	} else {
		PrintToServer("Could not hook CTFPlayerClassShared::SetCustomModel(). Players can hide their pvp state with vanity models!");
	}
	//messages for dynamic hooks not found
	if (hdl_CTFProjectile_HealingBolt_ImpactTeamPlayer == INVALID_HANDLE) {
		PrintToServer("Could not hook eyeball_boss for CEyeballBoss::IsLineOfSightClear(). Players will be targeted by Monoculus!");
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
	if (hdl_CTFPlayer_ApplyGenericPushbackImpulse != INVALID_HANDLE && detoured_CTFPlayer_ApplyGenericPushbackImpulse)
		detoured_CTFPlayer_ApplyGenericPushbackImpulse ^= DHookDisableDetour(hdl_CTFPlayer_ApplyGenericPushbackImpulse, false, Detour_CTFPlayer_ApplyGenericPushbackImpulse);
	if (hdl_CObjectSentrygun_ValidTargetPlayer != INVALID_HANDLE && detoured_CObjectSentrygun_ValidTargetPlayer)
		detoured_CObjectSentrygun_ValidTargetPlayer ^= DHookDisableDetour(hdl_CObjectSentrygun_ValidTargetPlayer, true, Detour_CObjectSentrygun_ValidTargetPlayer);
	if (hdl_CObjectSentrygun_ValidTargetBot != INVALID_HANDLE && detoured_CObjectSentrygun_ValidTargetBot)
		detoured_CObjectSentrygun_ValidTargetBot ^= DHookDisableDetour(hdl_CObjectSentrygun_ValidTargetBot, true, Detour_CObjectSentrygun_ValidTargetBot);
	if (hdl_CObjectSentrygun_ValidTargetObject != INVALID_HANDLE && detoured_CObjectSentrygun_ValidTargetObject)
		detoured_CObjectSentrygun_ValidTargetObject ^= DHookDisableDetour(hdl_CObjectSentrygun_ValidTargetObject, true, Detour_CObjectSentrygun_ValidTargetObject);
	if (hdl_CWeaponMedigun_AllowedToHealTarget != INVALID_HANDLE && detoured_CWeaponMedigun_AllowedToHealTarget)
		detoured_CWeaponMedigun_AllowedToHealTarget ^= DHookDisableDetour(hdl_CWeaponMedigun_AllowedToHealTarget, false, Detour_CWeaponMedigun_AllowedToHealTarget);
	if (hdl_CTFProjectile_HealingBolt_ImpactTeamPlayer != INVALID_HANDLE && detoured_CTFProjectile_HealingBolt_ImpactTeamPlayer)
		detoured_CTFProjectile_HealingBolt_ImpactTeamPlayer ^= DHookDisableDetour(hdl_CTFProjectile_HealingBolt_ImpactTeamPlayer, false, Detour_CTFProjectile_HealingBolt_ImpactTeamPlayer);
	if (hdl_CTFPlayerClassShared_SetCustomModel != INVALID_HANDLE && detoured_CTFPlayerClassShared_SetCustomModel)
		detoured_CTFPlayerClassShared_SetCustomModel ^= DHookDisableDetour(hdl_CTFPlayerClassShared_SetCustomModel, true, Detour_CTFPlayerClassShared_SetCustomModel);
}
void DHooksAttachTo(int entity, const char[] classname) {
	if (StrEqual(classname, "eyeball_boss") && hdl_CEyeballBoss_IsLineOfSightClear != INVALID_HANDLE) {
		if (hdl_CEyeballBoss_IsLineOfSightClear.HookEntity(Hook_Pre, entity, Dhook_CEyeballBoss_IsLineOfSightClear) == INVALID_HOOK_ID) {
			PrintToServer("Failed to hook eyeball_boss <%i> for CEyeballBoss::IsLineOfSightClear()", entity);
		}
	}
}

// this dhook simply makes bots ignore players that dont want to pvp
public MRESReturn Detour_INextBot_IsEnemy(Address pThis, DHookReturn hReturn, DHookParam hParams) {
	int target = hParams.Get(1);
	int player = GetPlayerEntity(target);
	if (IsValidClient(player) && !IsGlobalPvP(player) && !IsGlobalPvP(0)) {
		hReturn.Value = false;
		return MRES_Override;
	}
	return MRES_Ignored;
}

public MRESReturn Detour_CZombieAttack_IsPotentiallyChaseable(DHookReturn hReturn, DHookParam hParams) {
	if (hParams.IsNull(2))
		return MRES_Ignored;// we're not changing behaviour
	int player = hParams.Get(2);
	if (CanZombieAttack(player)) return MRES_Ignored;
	hReturn.Value = false;
	return MRES_Override;
}
public MRESReturn Detour_BossAttack_IsPotentiallyChaseable(DHookReturn hReturn, DHookParam hParams) {
	if (hParams.IsNull(2))
		return MRES_Ignored;// we're not changing behaviour
	int player = hParams.Get(2);
	if (CanBossAttack(player)) return MRES_Ignored;
	hReturn.Value = false;
	return MRES_Override;
}
public MRESReturn Dhook_CEyeballBoss_IsLineOfSightClear(int eyeball, DHookReturn hReturn, DHookParam hParams) {
	if (!eyeball) return MRES_Ignored;
	if (hParams.IsNull(1))
		return MRES_Ignored;// we're not changing behaviour
	int target = hParams.Get(1);
	if (CanBossAttack(target)) return MRES_Ignored;
	hReturn.Value = false;
	return MRES_Override;
}

public MRESReturn Detour_CTFPlayer_ApplyGenericPushbackImpulse(int player, DHookParam hParams) {
//	float impulse[3]; hParams.GetVector(1, impulse);
	if (hParams.IsNull(2)) return MRES_Ignored;
	int source = hParams.Get(2);
	if (IsValidClient(source) && !CanClientsPvP(source,player))
		return MRES_Supercede;//don't call original to apply force
	return MRES_Ignored;
}

public MRESReturn Detour_CObjectSentrygun_ValidTargetPlayer(int building, DHookReturn hReturn, DHookParam hParams) {
	if (hReturn.Value == false || hParams.IsNull(1))
		return MRES_Ignored;
	int target = hParams.Get(1);
	if (UTIL_SentryIsTargetValidPlayer(building, target))
		return MRES_Ignored; //use game check
	hReturn.Value = false;
	return MRES_Override;
}
public MRESReturn Detour_CObjectSentrygun_ValidTargetBot(int building, DHookReturn hReturn, DHookParam hParams) {
	if (hReturn.Value == false || hParams.IsNull(1))
		return MRES_Ignored;
	int target = hParams.Get(1);
	if (UTIL_SentryIsTargetValidBot(building, target))
		return MRES_Ignored; //use game check
	hReturn.Value = false;
	return MRES_Override;
}
public MRESReturn Detour_CObjectSentrygun_ValidTargetObject(int building, DHookReturn hReturn, DHookParam hParams) {
	if (hReturn.Value == false || hParams.IsNull(1))
		return MRES_Ignored;
	int target = hParams.Get(1);
	if (UTIL_SentryIsTargetValidObject(building, target))
		return MRES_Ignored; //use game check
	hReturn.Value = false;
	return MRES_Override;
}

public MRESReturn Detour_CWeaponMedigun_AllowedToHealTarget(int weapon, DHookReturn hReturn, DHookParam hParams) {
	int target = hParams.Get(1);
	if (!(1<=target<=MaxClients))
		return MRES_Ignored;
	int medic = GetEntPropEnt(weapon, Prop_Send, "m_hOwner");
	if (!(1<=medic<=MaxClients))
		return MRES_Ignored; //no owner?!
	
	bool medicGlobal = IsGlobalPvP(medic);
	bool targetGlobal = IsGlobalPvP(target);
	bool targetPair = HasAnyPairPvP(target);
	//healing is allowed if both are (not) in global pvp at the same time, and the target is not dueling (if not global)
	if (medicGlobal == targetGlobal && (targetGlobal || !targetPair))
		return MRES_Ignored;
	
	clientInvalidHealNotif[medic] = true;
	hReturn.Value = false;
	return MRES_Supercede;
}

public MRESReturn Detour_CTFProjectile_HealingBolt_ImpactTeamPlayer(int healingBolt, DHookParam hParams) {
	int weapon = GetEntPropEnt(healingBolt, Prop_Send, "m_hOriginalLauncher");
	if (!IsValidEntity(weapon)) return MRES_Ignored; //no weapon?
	int medic = GetEntPropEnt(weapon, Prop_Send, "m_hOwnerEntity");
	int target = DHookGetParam(hParams, 1);
	
	if (!(1<=medic<=MaxClients) || !IsClientInGame(medic) || !(1<=target<=MaxClients))
		return MRES_Supercede; //projectile owner dced until it hit, or target not a player, dont heal
	
	bool medicGlobal = IsGlobalPvP(medic);
	bool targetGlobal = IsGlobalPvP(target);
	bool targetPair = HasAnyPairPvP(target);
	//healing is allowed if both are (not) in global pvp at the same time, and the target is not dueling (if not global)
	if (medicGlobal == targetGlobal && (targetGlobal || !targetPair))
		return MRES_Ignored;
	
	EmitSoundToClient(medic, PVP_HEALBLOCK_BOLT, SOUND_FROM_PLAYER);
	clientInvalidHealNotif[medic] = true;
	return MRES_Supercede;
}

public MRESReturn Detour_CTFPlayerClassShared_SetCustomModel(Address pThis) {
	int client = UTIL_FindPlayerForClass(pThis);
	if (!(1<=client<=MaxClients) || !IsClientInGame(client)) return MRES_Ignored;
	if (!clientCustomModelPostRequested[client]) {
		clientCustomModelPostRequested[client]=true;
		RequestFrame(OnClientModelChanged, GetClientUserId(client));
	}
	return MRES_Ignored;
}
void OnClientModelChanged(int userid) {
	int client = GetClientOfUserId(userid);
	if (!client || !IsClientInGame(client)) return;
	clientCustomModelPostRequested[client]=false;
	if (!IsPlayerModelValid(client)) {
		SetGlobalPvP(client, false);
	} else {
		if (usePvPParticle) clientForceUpdateParticle[client] = true;
		UpdateEntityFlagsGlobalPvP(client, IsGlobalPvP(client));
	}
}

//keep as simple and quick as possible
//don't check result, that does NOT pass the previous result!
public bool OnClientShouldCollide(int entity, int collisiongroup, int contentsmask, bool originalResult) {
	if (!IsClientInGame(entity)) return originalResult;
	// collision group 8 == player movement
	// inter-player collision base content mask value? 0x0201400B
	if (collisiongroup == 8 && (contentsmask & 0xFFFFE7FF) == 0x201400B && noCollideState >= 1) return false;
	return originalResult;
}

public Action CH_PassFilter(int ent1, int ent2, bool &result) {
	if (!isActive || !noCollideState || !(1<=ent1<=MaxClients) || !(1<=ent2<=MaxClients))
		return Plugin_Continue;
	if (!IsClientInGame(ent1) || !IsClientInGame(ent2))
		return Plugin_Continue;
	//pass 1, collision mod is on and we have clients
	int team1 = GetClientTeam(ent1);
	int team2 = GetClientTeam(ent2);
	if (team1 != team2 && team1 > 1 && team2 > 1 && (noCollideState > 1 || !CanClientsPvP(ent1, ent2))) {
		//pass2, clients are on different teams and can not pvp (or override): treat as same team (aka friendly)
		result = false;
		return Plugin_Changed;
	}
	return Plugin_Continue;
}

/** look up the player for a CTFPlayerClassShared instance.  */
static int UTIL_FindPlayerForClass(Address sharedClass) {
	for (int client=1; client<=MaxClients; client++) {
		if (!IsClientInGame(client)) continue;
		Address clientSharedClasss = GetEntityAddress(client)+view_as<Address>(offset_CTFPlayer_m_PlayerClass);
		if (clientSharedClasss == sharedClass) return client;
	}
	return 0;
}

static bool UTIL_SentryIsTargetValidPlayer(int sentry, int target) {
	int engi = GetPlayerEntity(sentry);
	if (engi == INVALID_ENT_REFERENCE || target == INVALID_ENT_REFERENCE) return true; //world-sentry or error
	return CanClientsPvP(engi, target)!=0;
}

static bool UTIL_SentryIsTargetValidBot(int sentry, int target) {
	int engi = GetPlayerEntity(sentry);
	if (engi == INVALID_ENT_REFERENCE || target == INVALID_ENT_REFERENCE) return true; //world-sentry or error
	if (1<=target<=MaxClients) {
		// team assigned nextbots have pvp always on, can probably skip this check
		return CanClientsPvP(engi, target)!=0;
	} else {
		char classname[64];
		GetEntityClassname(target, classname, sizeof(classname));
		if (IsEntityZombie(classname)) {
			//we are trying to target a zombie, are we allowed to do at all?
			return CanZombieAttack(sentry);
		} else if (IsEntityBoss(classname)) {
			//we are trying to target a boss, are we allowed to do at all?
			return CanBossAttack(sentry);
		}
	}
	return true; //error?
}

static bool UTIL_SentryIsTargetValidObject(int sentry, int target) {
	int engi = GetPlayerEntity(sentry);
	char classname[64];
	if (engi == INVALID_ENT_REFERENCE || target == INVALID_ENT_REFERENCE) return true; //world-sentry or error
	GetEntityClassname(target, classname, sizeof(classname));
	if (IsEntityBuilding(classname)) {
		//hey ho, we target another building
		int otherEngi = GetPlayerEntity(target);
		if (IsValidClient(otherEngi)) return CanClientsPvP(engi,otherEngi)!=0;
	}
	return true; //error?
}
