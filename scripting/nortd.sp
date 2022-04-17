#include <sourcemod>
#include <pvpoptin>
#include <rtd2>

public Action RTD2_CanRollDice(int client)
{
	if(!pvp_GetPlayerGlobal(client))
	{
		PrintToChat(client, "关闭PvP不可使用RTD");
		return Plugin_Handled;
	}

	return Plugin_Continue;
}

public Action pvp_OnGlobalChanged(int client, pvpEnabledState oldState, pvpEnabledState& newState)
{
	if(newState == PVPState_Disabled)
	{
	  RTD2_Remove(client, RTDRemove_Custom, "PvP关闭")
	}
	return Plugin_Continue;
}
