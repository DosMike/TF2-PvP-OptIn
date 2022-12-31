#if defined __pvp_optin
#endinput
#endif
#define __pvp_optin

enum pvpEnabledState(<<=1) {
	PVPState_Disabled = 0, //player disabled
	PVPState_Enabled = 1,  //player enabled
	PVPState_Forced,       //admin enforced (enabled)
	PVPState_ExternalOn,   //a plugin placed an enabled override
	PVPState_ExternalOff,  //a plugin placed a disabled override
	PVPState_BotAlways,    //force-enabled in a way that can't turn off because this is a bot
}

/**
 * The plugin can be configures to be active only during certain
 * game stages. While the plugin is inactive, gameplay is unaffected
 * by the plugins (almost as if unloaded).
 *
 * @return true if the plugin is active
 */
native bool pvp_IsActive();

/**
 * Get the players pvp state. The second parameter will give more
 * information about the effective pvp state returned.
 *
 * @param client the client to check
 * @param pvpState the current pvp state
 * @return !(state & ExternalOff) && state != Disabled
 */
native bool pvp_GetPlayerGlobal(int client, pvpEnabledState& pvpState = PVPState_Disabled);

/**
 * Sets the players global pvp override state.
 * A value > 0 will set PVPState_ExternalOn,
 * The value 0 will set PVPState_ExternalOff,
 * A value < 0 will unset PVPState_External*
 *
 * @param client the client to check
 * @param value the new override state
 */
native void pvp_SetPlayerGlobal(int client, int value=-1);

/**
 * Check if two players have initiated pair pvp
 *
 * @param client1
 * @param client2
 * @return true if the players started pair pvp
 */
native bool pvp_GetPlayerPair(int client1, int client2);

/**
 * Get all players that are currenlty in pair pvp with this player
 * 
 * @param client - the client to check
 * @param targets - buffer for targets to be written
 * @param max_targets - size of targets buffer
 * @return number of elements written in target buffer
 */
native int pvp_GetPlayersPaired(int client, int[] targets, int max_targets);

/**
 * Can be used to bypass the pair pvp invite system and
 * set the players pvp state
 *
 * @param client1
 * @param client2
 * @param value changes the paired pvp state 
 */
native void pvp_ForcePlayerPair(int client1, int client2, bool value);

/**
 * Check if client1 and client2 can pvp each other.
 * Will first check if both player are in global pvp, then checks
 * if both players have started pair pvp.
 *
 * @param client1 
 * @param client2
 * @return true if both players can hurt each other
 */
native bool pvp_CanAttack(int client1, int client2);

/**
 * Check if this player has mirrored damage. Mirrored damage within this plugin
 * is only effective when pvp_CanAttack would return false.
 *
 * @param client player to check
 * @param pvpState returns more information about why the player is mirrored
 * @return the effective mirror state
 */
native bool pvp_IsMirrored(int client, pvpEnabledState& pvpState = PVPState_Disabled );

/**
 * As with the global pvp state, this can be used to set the 
 * mirrored state override.
 * A value > 0 will set PVPState_ExternalOn,
 * The value 0 will set PVPState_ExternalOff,
 * A value < 0 will unset PVPState_External*
 *
 * @param client
 * @param value the new override value
 */
native void pvp_SetMirrored(int client, int value=-1);

/**
 * Ban a player from participating in PvP. The player needs to be ingame.
 *
 * @param admin admin that bans the target or 0 for server
 * @param target client to ban
 * @param time time in minutes to ban from pvp
 * @param reason for banning
 * @error if admin invalid, target invalid or fake, time <= 0
 */
native void pvp_BanPlayer(int admin, int target, int time, const char[] reason);

/**
 * Unban a player, and allow them to PvP again.
 * If the player wasn't banned, nothing happens.
 *
 * @param admin the admin that unbanned
 * @param target client to unban
 * @error if admin invalid, target invalid
 */
native void pvp_UnbanPlayer(int admin, int target);

/**
 * Called when a players global pvp state changes.
 * You can only modify the PVPState_External* bits in newState!
 *
 * @param client the player whose global state changed
 * @param oldState the state before
 * @param newState the state after
 * @return changed if changed, handled to cancel
 */
forward Action pvp_OnGlobalChanged(int client, pvpEnabledState oldState, pvpEnabledState& newState);

/**
 * Called when a player invited another player to pair pvp.
 * In case you want to monitor or limit who can request pair pvp with whom
 * you can use this. If the requestee ignores invites, this will not be called.
 *
 * @param requester the client requesting pair pvp
 * @param requestee the client requester requested pair pvp with
 * @return changed if changed, handled to cancel
 */
forward Action pvp_OnPairInvite(int requester, int requestee);

/**
 * Called when player pair pvp relation changes.
 *
 * @param client1 usually the requester if value
 * @param client2 usually the requestee if value
 * @param value true if pair pvp will be enabled
 * @return !continue to cancel
 */
forward Action pvp_OnPairChanged(int client1, int client2, bool value);

/**
 * Called when player gets banned from pvp.
 *
 * @param admin admin issueing the ban or 0 for console
 * @param target client being banned
 * @param minutes time in minutes this ban lasts
 * @param reason reason message
 * @noreturn
 */
forward Action pvp_OnBanAdded(int admin, int target, int minutes, const char[] reason);

/**
 * Called when a player ban is manually undone (not when the ban times out)
 *
 * @param admin the admin that unbanned
 * @param target client to unban
 * @noreturn
 */
forward Action pvp_OnBanRemoved(int admin, int target);


public SharedPlugin __pl_pvpoptin =  {
    name = "pvpoptin",
    file = "pvpoptin.smx",
#if defined REQUIRE_PLUGIN
    required = 1,
#else
    required = 0,
#endif
};

#if !defined REQUIRE_PLUGIN
public void __pl_pvpoptin_SetNTVOptional() {
	MarkNativeAsOptional("pvp_IsActive");
    MarkNativeAsOptional("pvp_GetPlayerGlobal");
    MarkNativeAsOptional("pvp_SetPlayerGlobal");
    MarkNativeAsOptional("pvp_GetPlayerPair");
    MarkNativeAsOptional("pvp_GetPlayersPaired");
    MarkNativeAsOptional("pvp_ForcePlayerPair");
    MarkNativeAsOptional("pvp_CanAttack");
    MarkNativeAsOptional("pvp_IsMirrored");
    MarkNativeAsOptional("pvp_SetMirrored");
    MarkNativeAsOptional("pvp_BanPlayer");
    MarkNativeAsOptional("pvp_UnbanPlayer");
}
#endif
