#if defined _pvpoptin_utils
 #endinput
#endif
#define _pvpoptin_utils
#if !defined PLUGIN_VERSION
 #error Please compile the main file
#endif

#if SOURCEMOD_V_MAJOR == 1 && SOURCEMOD_V_MINOR <= 10
#include "pvpoptin/common.sp"
#else //pretty sure this got fixed in sm 1.11
#include "common.sp"
#endif

void SetPlayerColor(int client, int r=255, int g=255, int b=255, int a=255) {
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
public Action Timer_EverySecond(Handle timer) {
	for (int client=1;client<=MaxClients;client++) {
		// accidents happen, slowly decay score
		if (clientSpawnKillScore[client] > 0)
			clientSpawnKillScore[client] -= 1;
		if (clientInvalidHealNotif[client]) {
			clientInvalidHealNotif[client] = false;
			if (Client_IsIngame(client) && !IsFakeClient(client) && GetClientTime(client) - clientInvalidHealNotifLast[client] > 5.0) {
				clientInvalidHealNotifLast[client] = GetClientTime(client);
				CPrintToChat(client, "%t", "Healing only allowed in global PvP");
			}
		}
	}
	
	return Plugin_Continue;
}
// this timer is kinda required for players that join late, disguise, ect...
public Action Timer_PvPParticles(Handle timer) {
	if (usePvPParticle) {
		for (int client=1;client<=MaxClients;client++) {
			if (Client_IsIngame(client) && IsPlayerAlive(client))
				UpdatePvPParticles(client);
		}
	}
	
	return Plugin_Continue;
}
void UpdatePvPParticles(int client) {
	//head attachment points, sourcemod has no builtin to lookup so i just hardcode
	// count from "(none)"==0 in HLMV
	static int AttachPoint_Head[10]={ 0,
		/* scout */ 12, /* sniper */ 8, /* soldier */ 8,
		/* demo  */  7, /* medic  */ 8, /* heavy   */ 8,
		/* pyro  */  1, /* spy    */ 10, /* engi    */ 5,
	};
	int targets[MAXPLAYERS], tcount, tmask;
	if (!Client_IsIngame(client)) return;
	if (!TF2_IsPlayerInCondition(client, TFCond_Cloaked)) {
		if (IsGlobalPvP(client)) {
			for (int c=1;c<=MaxClients;c++) {
				if( //c != client &&
					Client_IsIngameAuthorized(c) )
					targets[tcount++]=c;
			}
			tmask = -1; //visible to all
		} else {
			for (int c=1;c<=MaxClients;c++) {
				if( //c != client &&
					pairPvP[client][c] ) {
					targets[tcount++]=c;
					tmask |= (1<<(c-1));
				}
			}
		}
	}
	
	TFClassType effectiveClass;
	if (TF2_IsPlayerInCondition(client, TFCond_Disguised)) effectiveClass = view_as<TFClassType>(GetEntProp(client, Prop_Send, "m_nDisguiseClass"));
	if (effectiveClass == TFClass_Unknown) effectiveClass = TF2_GetPlayerClass(client);
	
	if (tmask != clientParticleAttached[client] || clientForceUpdateParticle[client]) {
		clientForceUpdateParticle[client] = false;
		// if particles tunred off for some clients, we have to restart them
		// we will also simply restart them for everyone if some new gets to see it
		if (tmask==0 || (tmask ^ clientParticleAttached[client]) & clientParticleAttached[client]) {// check for "falling edges" -> was set and changed
			ParticleEffectStop(client);
		}
		// just restart the particle for everyone that can see it (will "blink" shadow if it was already playing)
		if (tmask) {
			float angles[3];
			float zero[3];
			float offset[3]={0.0, 0.0, PVP_PARTICLE_OFFSET};
			GetClientEyeAngles(client, angles);
			TE_StartParticle(PVP_PARTICLE,zero,offset,angles,client,PATTACH_POINT_FOLLOW,AttachPoint_Head[effectiveClass],true);
			TE_Send(targets, tcount);
		}
		clientParticleAttached[client] = tmask;
	}
}
void ParticleEffectStop(int entity) {
	SetVariantString("ParticleEffectStop");
	AcceptEntityInput(entity, "DispatchEffect");
}

//https://forums.alliedmods.net/showthread.php?t=75102
void TE_StartParticle(const char[] name, float pos[3], float offset[3], float angles[3], int parentTo=-1, ParticleAttachment_t attachType=PATTACH_INVALID, int attachPoint=-1, bool reset=false) {
	static int table = INVALID_STRING_TABLE;
	if (table == INVALID_STRING_TABLE) {
		if ((table=FindStringTable("ParticleEffectNames"))==INVALID_STRING_TABLE)
			ThrowError("Could not find string table for particles");
	}
	char tmp[64];
	int count = GetStringTableNumStrings(table);
	int index = INVALID_STRING_INDEX;
	for (int i;i<count;i++) {
		ReadStringTable(table, i, tmp, sizeof(tmp));
		if (StrEqual(tmp, name)) {
			index = i; break;
		}
//		PrintToServer("Particle: %s", tmp);
	}
	if (index == INVALID_STRING_INDEX) {
		ThrowError("Could not find particle in string table");
	}
	TE_Start("TFParticleEffect");
	TE_WriteFloat("m_vecOrigin[0]", pos[0]);
	TE_WriteFloat("m_vecOrigin[1]", pos[1]);
	TE_WriteFloat("m_vecOrigin[2]", pos[2]);
	TE_WriteFloat("m_vecStart[0]", offset[0]);
	TE_WriteFloat("m_vecStart[1]", offset[1]);
	TE_WriteFloat("m_vecStart[2]", offset[2]);
	TE_WriteVector("m_vecAngles", angles);
	TE_WriteNum("m_iParticleSystemIndex", index);
	if (parentTo!=-1) TE_WriteNum("entindex", parentTo);
	if (attachType!=PATTACH_INVALID) TE_WriteNum("m_iAttachType", view_as<int>(attachType));
	if (attachPoint!=-1) TE_WriteNum("m_iAttachmentPointIndex", attachPoint);
	TE_WriteNum("m_bResetParticles", reset?1:0);
}

/**
 * Use -1 for haystacksize if the array is 0-terminated, -2 if it is negative-terminated
 */
int ArrayFind(any needle, const any[] haystack, int haystacksize=0) {
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
int GetPlayerEntity(int entity) {
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

bool IsEntityZombie(const char[] classname) {
	return StrEqual(classname,"tf_zombie");
}
bool IsEntityBoss(const char[] classname) {
	return (StrEqual(classname, "merasmus") || StrEqual(classname, "headless_hatman") || StrEqual(classname, "eyeball_boss"));
}
bool IsEntityBuilding(const char[] classname) {
	return (StrEqual(classname, "obj_sentrygun") || StrEqual(classname, "obj_dispenser") || StrEqual(classname, "obj_teleporter"));
}

int GetPlayerDamageSource(int attacker, int inflictor) {
	int source;
	if (IsValidEntity(attacker) && 1 <= attacker <= MaxClients) 
		return attacker;
	// Sometimes the attacker won't be a player
	// try to resolve the attacker first:
	//  if someone shoots a vehicle, vehicle redirects the damage to the driver with the vehicle as inflictor
	else if (IsValidEntity(attacker) && 1 <= (source = GetPlayerEntity(attacker)) <= MaxClients)
		// if that's not a player, we try to get the damage source from the attacker entity. this will mostly be npcs tho
		return source;
	else if (IsValidEntity(inflictor) && 1 <= (source = GetPlayerEntity(inflictor)) <= MaxClients) 
		// so we try to determin the player damage source from the inflictor. mostly projectiles
		return source;
	else
		// if we still couldn't find a player, we give up
		return INVALID_ENT_REFERENCE;
}

/** Why the heck is this not a stock? filenames dont tell me anything and can
 * easily be changed. Anyways: this finds a plugin by name exactly.
 * @param pluginName the name to look for case sensitive
 * @param pluginAuthor, if not NULL_STRING, has to match as well
 * @return plugin handle or INVALID_HANDLE if not found
 */
Handle FindPluginByName(const char[] pluginName, const char[] pluginAuthor=NULL_STRING) {
	Handle plugins = GetPluginIterator();
	Handle result = INVALID_HANDLE;
	char buffer[128];
	while (MorePlugins(plugins)) {
		Handle plugin = ReadPlugin(plugins);
		if (GetPluginInfo(plugin, PlInfo_Name, buffer, sizeof(buffer)) && StrEqual(pluginName, buffer) &&
			(IsNullString(pluginAuthor) || (GetPluginInfo(plugin, PlInfo_Author, buffer, sizeof(buffer)) && StrEqual(pluginAuthor, buffer)))) {
			result = plugin;
			break;
		}
	}
	delete plugins;
	return result;
}