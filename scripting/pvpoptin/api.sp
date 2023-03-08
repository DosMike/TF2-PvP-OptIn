#if defined _pvpoptin_api
 #endinput
#endif
#define _pvpoptin_api
#if !defined PLUGIN_VERSION
 #error Please compile the main file
#endif

static GlobalForward fwdGlobalChanged;
static GlobalForward fwdPairInvited;
static GlobalForward fwdPairChanged;
static GlobalForward fwdBanAdded;
static GlobalForward fwdBanRemoved;

void Plugin_SetupForwards() {
	fwdGlobalChanged = new GlobalForward("pvp_OnGlobalChanged", ET_Event, Param_Cell, Param_Cell, Param_CellByRef);
	fwdPairInvited = new GlobalForward("pvp_OnPairInvite", ET_Event, Param_Cell, Param_Cell);
	fwdPairChanged = new GlobalForward("pvp_OnPairChanged", ET_Event, Param_Cell, Param_Cell, Param_Cell);
	fwdBanAdded = new GlobalForward("pvp_OnBanAdded", ET_Ignore, Param_Cell, Param_Cell, Param_Cell, Param_String);
	fwdBanRemoved = new GlobalForward("pvp_OnBanRemoved", ET_Ignore, Param_Cell, Param_Cell);
}

//region natives

public APLRes AskPluginLoad2(Handle plugin, bool late, char[] error, int err_max) {
    CreateNative("pvp_IsActive",        Native_IsActive);
    CreateNative("pvp_GetPlayerGlobal", Native_GetPlayerGlobal);
    CreateNative("pvp_SetPlayerGlobal", Native_SetPlayerGlobal);
    CreateNative("pvp_GetPlayerPair",   Native_GetPlayerPair);
    CreateNative("pvp_GetPlayersPaired",Native_GetPlayersPaired);
    CreateNative("pvp_ForcePlayerPair", Native_ForcePlayerPair);
    CreateNative("pvp_CanAttack",       Native_CanAttack);
    CreateNative("pvp_IsMirrored",      Native_IsMirrored);
    CreateNative("pvp_SetMirrored",     Native_SetMirrored);
    CreateNative("pvp_BanPlayer",       Native_BanPlayer);
    CreateNative("pvp_UnbanPlayer",     Native_UnbanPlayer);
    
    RegPluginLibrary("pvpoptin");
    return APLRes_Success;
}

//native bool pvp_IsActive();
public any Native_IsActive(Handle plugin, int numParams) {
	return isActive;
}
//native bool pvp_GetPlayerGlobal(int client, pvpEnabledState& pvpState = PVPState_Disabled);
public any Native_GetPlayerGlobal(Handle plugin, int numParams) {
	int client = GetNativeCell(1);
	if (!IsClientInGame(client)) ThrowNativeError(SP_ERROR_PARAM, "Invalid client index or client not ingame (%i)", client);
	SetNativeCellRef(2, globalPvP[client]);
	return IsGlobalPvP(client);
}
//native void pvp_SetPlayerGlobal(int client, int value=-1);
public any Native_SetPlayerGlobal(Handle plugin, int numParams) {
	int client = GetNativeCell(1);
	if (!IsClientInGame(client)) ThrowNativeError(SP_ERROR_PARAM, "Invalid client index or client not ingame (%i)", client);
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
	return 0;
}
//native bool pvp_GetPlayerPair(int client1, int client2);
public any Native_GetPlayerPair(Handle plugin, int numParams) {
	int client1 = GetNativeCell(1);
	int client2 = GetNativeCell(2);
	if (!IsClientInGame(client1)) ThrowNativeError(SP_ERROR_PARAM, "Invalid client index or client not ingame for arg1 (%i)", client1);
	if (!IsClientInGame(client2)) ThrowNativeError(SP_ERROR_PARAM, "Invalid client index or client not ingame for arg2 (%i)", client2);
	return pairPvP[client1][client2];
}
//native int pvp_GetPlayersPaired(int client, int[] targets, int max_targets);
public any Native_GetPlayersPaired(Handle plugin, int numParams) {
	int client = GetNativeCell(1);
	int max = GetNativeCell(3);
	int[] hits = new int[max];
	int results;
	if (!IsClientInGame(client)) ThrowNativeError(SP_ERROR_PARAM, "Invalid client index or client not ingame for arg1 (%i)", client);
	for (int other=1; other<=MaxClients; other+=1) {
		if (pairPvP[client][other]) {
			hits[results] = other;
			results += 1;
			if (results == max) break;
		}
	}
	if (results) SetNativeArray(2, hits, max);
	return results;
}
//native void pvp_ForcePlayerPair(int client1, int client2, bool value);
public any Native_ForcePlayerPair(Handle plugin, int numParams) {
	int client1 = GetNativeCell(1);
	int client2 = GetNativeCell(2);
	bool force = GetNativeCell(3);
	if (!IsClientInGame(client1)) ThrowNativeError(SP_ERROR_PARAM, "Invalid client inde or client not ingame for arg1 (%i)", client1);
	if (!IsClientInGame(client2)) ThrowNativeError(SP_ERROR_PARAM, "Invalid client inde or client not ingame for arg2 (%i)", client2);
	bool oldValue = pairPvP[client1][client2];
	if (oldValue != force && client1!=client2 && Notify_OnPairChanged(client1, client2, force)) {
		SetPairPvP(client1,client2,force);
	}
	return 0;
}
//native bool pvp_CanAttack(int client1, int client2);
public any Native_CanAttack(Handle plugin, int numParams) {
	int client1 = GetNativeCell(1);
	int client2 = GetNativeCell(2);
	if (!IsClientInGame(client1)) ThrowNativeError(SP_ERROR_PARAM, "Invalid client inde or client not ingame for arg1 (%i)", client1);
	if (!IsClientInGame(client2)) ThrowNativeError(SP_ERROR_PARAM, "Invalid client inde or client not ingame for arg2 (%i)", client2);
	return CanClientsPvP(client1, client2);
}
//native bool pvp_IsMirrored(int client, pvpEnabledState& pvpState = PVPState_Disabled );
public any Native_IsMirrored(Handle plugin, int numParams) {
	int client = GetNativeCell(1);
	if (!IsClientInGame(client)) ThrowNativeError(SP_ERROR_PARAM, "Invalid client index or client not ingame (%i)", client);
	SetNativeCellRef(2, mirrorDamage[client]);
	return IsMirrored(client);
}
//native void pvp_SetMirrored(int client, int value=-1);
public any Native_SetMirrored(Handle plugin, int numParams) {
	int client = GetNativeCell(1);
	if (!IsClientInGame(client)) ThrowNativeError(SP_ERROR_PARAM, "Invalid client index or client not ingame (%i)", client);
	int value = GetNativeCell(2);
	
	eEnabledState sflag = State_Disabled;
	if (value > 0) sflag = State_ExternalOn;
	else if (value == 0) sflag = State_ExternalOff;
	sflag = (mirrorDamage[client] & ~ENABLEDMASK_EXTERNAL) | sflag;
	
	globalPvP[client] = sflag;
	return 0;
}
//native void pvp_BanPlayer(int admin, int target, int time, const char[] reason);
public any Native_BanPlayer(Handle plugin, int numParams) {
	int admin = GetNativeCell(1);
	if (!IsClientInGame(admin)) ThrowNativeError(SP_ERROR_PARAM, "Invalid admin index or admin not ingame (%i)", admin);
	int target = GetNativeCell(2);
	if (!IsClientInGame(target) || IsFakeClient(target)) ThrowNativeError(SP_ERROR_PARAM, "Invalid target index, target not ingame or target is bot (%i)", target);
	int minutes = GetNativeCell(3);
	if (minutes < 1) ThrowNativeError(SP_ERROR_PARAM, "Ban time has to be positive");
	char reason[256];
	GetNativeString(4, reason, sizeof(reason));
	TrimString(reason);
	if (reason[0] != 0) strcopy(reason, sizeof(reason), "<No Reason>");
	
	BanClientPvP(admin, target, minutes, reason);
	return 0;
}
//native void pvp_BanPlayer(int admin, int target, int time, const char[] reason);
public any Native_UnbanPlayer(Handle plugin, int numParams) {
	int admin = GetNativeCell(1);
	if (!IsClientInGame(admin)) ThrowNativeError(SP_ERROR_PARAM, "Invalid admin index or admin not ingame (%i)", admin);
	int target = GetNativeCell(2);
	if (!IsClientInGame(target)) ThrowNativeError(SP_ERROR_PARAM, "Invalid target index, target not ingame or target is bot (%i)", target);
	if (IsFakeClient(target) || GetTime() >= clientPvPBannedUntil[target]) return 0; //not banned
	
	BanClientPvP(admin, target, 0, "");
	return 0;
}

//return true to continue
bool Notify_OnGlobalChanged(int client, eEnabledState& value) {
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
bool Notify_OnPairInvited(int requester, int requestee) {
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
bool Notify_OnPairChanged(int client1, int client2, bool changedOn) {
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
//return true to continue
void Notify_OnBanAdded(int admin, int client, int minutes, const char[] reason) {
	Call_StartForward(fwdBanAdded);
	Call_PushCell(admin);
	Call_PushCell(client);
	Call_PushCell(minutes);
	Call_PushString(reason);
	Call_Finish();
}
//return true to continue
void Notify_OnBanRemoved(int admin, int client) {
	Call_StartForward(fwdBanRemoved);
	Call_PushCell(admin);
	Call_PushCell(client);
	Call_Finish();
}

//endregion
