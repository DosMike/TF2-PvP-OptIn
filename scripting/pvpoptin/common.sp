#if defined _pvpoptin_common
 #endinput
#endif
#define _pvpoptin_common
#if !defined PLUGIN_VERSION
 #error Please compile the main file
#endif
//for shared data&types


// will be double checked with TF2Util_GetPlayerConditionProvider
TFCond pvpConditions[] = {
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
bool pvpConditionTrivial[] = { //true for conditions in pvpConditions that do not affect gameplay too much
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

enum eGameState {
	GameState_Never = 0,
	GameState_Waiting = (1<<0),
	GameState_PreGame = (1<<1),
	GameState_Running = (1<<2),
	GameState_Overtime = (1<<3),
	GameState_SuddenDeath = (1<<4),
	GameState_GameOver = (1<<5)
}

enum eEnabledState {
	State_Disabled = 0,
	State_Enabled = (1<<0),
	State_Forced = (1<<1),
	State_ExternalOn = (1<<2), //a plugin placed an override
	State_ExternalOff = (1<<3), //a plugin placed an override
	State_BotAlways = (1<<4), //force-enabled in a way that can't turn off because bots
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
enum ParticleAttachment_t { // particle_parse.h
	PATTACH_INVALID = -1,			// Not in original, indicates invalid initial value
	PATTACH_ABSORIGIN = 0,			// Create at absorigin, but don't follow
	PATTACH_ABSORIGIN_FOLLOW,		// Create at absorigin, and update to follow the entity
	PATTACH_CUSTOMORIGIN,			// Create at a custom origin, but don't follow
	PATTACH_POINT,					// Create on attachment point, but don't follow
	PATTACH_POINT_FOLLOW,			// Create on attachment point, and update to follow the entity
	PATTACH_WORLDORIGIN,			// Used for control points that don't attach to an entity
	PATTACH_ROOTBONE_FOLLOW,		// Create at the root bone of the entity, and update to follow
};

//"super globals"
int joinForceState;
int noCollideState;
eGameState activeGameStates;
int pairPvPRequestMenu;
bool usePlayerStateColors;
int playerStateColors[4][4];
bool usePvPParticle;
ePlayerVsAiFlags pvaBuildings;
ePlayerVsAiFlags pvaPlayers;
float spawnKill_maxTime; //max time [s] for "spawn protection"
int spawnKill_minIncrease; //always score this if within maxTime
float spawnKill_maxIncreaseRoot; //because this is a quadratic falloff over maxTime (= root(maxIncrease-minIncrease))
int spawnKill_threashold; //accumulative points after which to ban
int spawnKill_banTime; //time to ban for [m] 