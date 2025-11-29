#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <cstrike>
#include <multicolors>
#include <discordWebhookAPI>
#include <clientprefs>

#define PLUGIN_VERSION "1.12"
#define MAX_TRACKED_SHOTS 1000
#define SAMPLE_SIZE 50
#define MAX_WEAPONS 32
#define FLOAT_EPSILON 0.001
#define MAX_TRACERS 32
#define GLOW_OFFSET 14

public Plugin myinfo = 
{
    name = "Advanced Aimbot Detection & Weapon Stats Observer (CS:S)",
    author = "+SyntX34",
    description = "Detects aimbot usage and provides advanced spectator weapon statistics with visualization for CS:Source",
    version = PLUGIN_VERSION,
    url = "https://github.com/SyntX34 && https://steamcommunity.com/id/SyntX34"
};

// ConVars
ConVar g_cvEnabled;
ConVar g_cvDebug;
ConVar g_cvAdminFlags;
ConVar g_cvSilentAimPerf;
ConVar g_cvAimbotPerf;
ConVar g_cvShotgunAimbotPerf;
ConVar g_cvShotgunHeadshotPerf;
ConVar g_cvAimlock;
ConVar g_cvRecoilPerf;
ConVar g_cvSilentAimAngle;
ConVar g_cvHeadshotPerf;
ConVar g_cvNoScopePerf;
ConVar g_cvCloseRange;
ConVar g_cvCommandFlags;
ConVar g_cvNotifyCooldown;
ConVar g_cvWebhook;
ConVar g_cvTriggerbotPerf; 
ConVar g_cvAimSnapAngle;
ConVar g_cvAimSnapDetections;
ConVar g_cvMaxAimVelocity;
ConVar g_cvTracerDuration;
ConVar g_cvGlowDistance;
ConVar g_cvObserverAdminFlag;
ConVar g_cvAimConsistency;
ConVar g_cvAimTimeThreshold;
ConVar g_cvMaxAngleChange;
ConVar g_cvSmoothnessThreshold;

// Player tracking arrays
int g_iShotsFired[MAXPLAYERS+1];
int g_iShotsHit[MAXPLAYERS+1];
int g_iHeadshots[MAXPLAYERS+1];
int g_iConsecutiveHits[MAXPLAYERS+1];
int g_iSuspicionLevel[MAXPLAYERS+1];
int g_iKills[MAXPLAYERS+1];
int g_iHeadshotKills[MAXPLAYERS+1];
int g_iKillHitGroupStats[MAXPLAYERS+1][8];
int g_iAimSnapDetections[MAXPLAYERS+1];
int g_iGlowEntity[MAXPLAYERS + 1] = {INVALID_ENT_REFERENCE, ...};
int g_bObserving[MAXPLAYERS + 1];
int g_iObservedTarget[MAXPLAYERS + 1];
int g_iTColor[4] = {255, 50, 50, 255};     
int g_iCTColor[4] = {50, 50, 255, 255};     
int g_iTracerColor[4] = {255, 255, 0, 255}; 
int g_iWeaponShots[MAXPLAYERS+1][MAX_WEAPONS];
int g_iWeaponHits[MAXPLAYERS+1][MAX_WEAPONS];
int g_iWeaponHeadshots[MAXPLAYERS+1][MAX_WEAPONS];
int g_iWeaponCount[MAXPLAYERS+1];
int g_iAimHistoryIndex[MAXPLAYERS+1];
int g_iPerfectAimFrames[MAXPLAYERS+1];
int g_iTransparentPlayers[MAXPLAYERS+1][MAXPLAYERS+1];
int g_iHitGroupStats[MAXPLAYERS+1][8];
int g_iHitPositionIndex[MAXPLAYERS+1];
float g_fLastShotTime[MAXPLAYERS+1];
float g_fLastHitTime[MAXPLAYERS+1];
float g_fLastNotifyTime[MAXPLAYERS+1];
float g_vLastAngles[MAXPLAYERS+1][3];
float g_vHitPositions[MAXPLAYERS+1][SAMPLE_SIZE][3];
float g_fLastAimCheckTime[MAXPLAYERS+1];
float g_vLastAimAngles[MAXPLAYERS+1][3];
float g_vAimHistory[MAXPLAYERS+1][10][3];
float g_fLastHitboxTime[MAXPLAYERS+1][MAXPLAYERS+1];
bool g_bIsZoomed[MAXPLAYERS+1];
bool g_bIsTracking[MAXPLAYERS+1];
bool g_bPendingMelee[MAXPLAYERS+1];
bool g_bTransparencyApplied[MAXPLAYERS+1];
bool g_bSilentAimDetected[MAXPLAYERS+1];
bool g_bAimbotDetected[MAXPLAYERS+1];
bool g_bRecoilDetected[MAXPLAYERS+1];
bool g_bAimlockDetected[MAXPLAYERS+1];
bool g_bTriggerbotDetected[MAXPLAYERS+1];
bool g_bNoScopeDetected[MAXPLAYERS+1];
bool g_bHitboxDebug[MAXPLAYERS + 1];
char g_sWeaponNames[MAXPLAYERS+1][MAX_WEAPONS][64];
ArrayList g_hObservers[MAXPLAYERS + 1];
ArrayList g_hTracers[MAXPLAYERS + 1];
ArrayList g_ShotHistory[MAXPLAYERS+1];
Handle g_hObserverCookie;
Handle g_hDamageTrie;

enum struct ShotData {
    float ShotTime;
    float ShotAngles[3];
    float EyePos[3];
    float HitPos[3];
    bool WasHit;
    bool WasHeadshot;
    int HitEntity;
    int HitGroup;
    char Weapon[64];
    bool WasZoomed;
    float Distance;
}

enum struct TracerData
{
    float startPos[3];
    float endPos[3];
    float timestamp;
}

char g_sHitgroupNames[][] = {
    "Generic",
    "Head",
    "Chest",
    "Stomach",
    "Left Arm",
    "Right Arm", 
    "Left Leg",
    "Right Leg"
};

char g_sScopedWeapons[][] = {
    "awp",
    "scout",
    "sg550",
    "g3sg1",
    "scar20"
};

char g_sHighAccuracyWeapons[][] = {
    "m3",
    "xm1014",
    "elite",
    "awp",
    "scout"
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
    EngineVersion engine = GetEngineVersion();
    if (engine != Engine_CSS)
    {
        strcopy(error, err_max, "This plugin is for Counter-Strike: Source only.");
        return APLRes_Failure;
    }
    
    RegPluginLibrary("WeaponStats");
    
    CreateNative("WS_IsSilentAimDetected", Native_IsSilentAimDetected);
    CreateNative("WS_IsAimbotDetected", Native_IsAimbotDetected);
    CreateNative("WS_IsRecoilDetected", Native_IsRecoilDetected);
    CreateNative("WS_IsAimlockDetected", Native_IsAimlockDetected);
    CreateNative("WS_IsTriggerbotDetected", Native_IsTriggerbotDetected);
    CreateNative("WS_IsNoScopeDetected", Native_IsNoScopeDetected);
    CreateNative("WS_GetSuspicionLevel", Native_GetSuspicionLevel);
    CreateNative("WS_GetShotsFired", Native_GetShotsFired);
    CreateNative("WS_GetShotsHit", Native_GetShotsHit);
    CreateNative("WS_GetHeadshots", Native_GetHeadshots);
    CreateNative("WS_GetAccuracy", Native_GetAccuracy);
    CreateNative("WS_GetHeadshotRatio", Native_GetHeadshotRatio);
    CreateNative("WS_GetKills", Native_GetKills);
    CreateNative("WS_GetHeadshotKills", Native_GetHeadshotKills);
    CreateNative("WS_GetWeaponCount", Native_GetWeaponCount);
    CreateNative("WS_GetWeaponName", Native_GetWeaponName);
    CreateNative("WS_GetWeaponShots", Native_GetWeaponShots);
    CreateNative("WS_GetWeaponHits", Native_GetWeaponHits);
    CreateNative("WS_GetWeaponHeadshots", Native_GetWeaponHeadshots);
    
    return APLRes_Success;
}

stock char[] GetCurrentServerTime()
{
    char sTime[64];
    FormatTime(sTime, sizeof(sTime), "%d/%m/%Y @ %H:%M:%S", GetTime());
    return sTime;
}

stock char[] HostIP() 
{ 
    char sIP[32], sPort[8], sResult[64];
    int ip = GetConVarInt(FindConVar("hostip"));
    if (ip == 0)
    {
        strcopy(sIP, sizeof(sIP), "Unknown");
    }
    else
    {
        Format(sIP, sizeof(sIP), "%d.%d.%d.%d",
            (ip >> 24) & 0xFF,
            (ip >> 16) & 0xFF,
            (ip >> 8) & 0xFF,
            ip & 0xFF);
    }
    GetConVarString(FindConVar("hostport"), sPort, sizeof(sPort));
    if (strlen(sPort) == 0)
    {
        strcopy(sPort, sizeof(sPort), "Unknown");
    }
    Format(sResult, sizeof(sResult), "%s:%s", sIP, sPort);
    return sResult;
}

public void OnPluginStart()
{
    LoadTranslations("weaponstats.phrases");
    
    CreateConVar("sm_weaponstats_version", PLUGIN_VERSION, "Plugin Version", FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY);
    
    g_cvEnabled = CreateConVar("sm_weaponstats_enable", "1", "Enable/Disable the plugin", FCVAR_NONE, true, 0.0, true, 1.0);
    g_cvDebug = CreateConVar("sm_weaponstats_debug", "1", "Enable debug mode", FCVAR_NONE, true, 0.0, true, 1.0);
    g_cvAdminFlags = CreateConVar("sm_weaponstats_adminflags", "z", "Admin flags to receive warnings (default: z - root)");
    g_cvSilentAimPerf = CreateConVar("sm_weaponstats_silentaim", "0.95", "Silent aim performance threshold", FCVAR_NONE, true, 0.0, true, 1.0);
    g_cvAimbotPerf = CreateConVar("sm_weaponstats_aimbot", "0.90", "Aimbot performance threshold", FCVAR_NONE, true, 0.0, true, 1.0);
    g_cvShotgunAimbotPerf = CreateConVar("sm_weaponstats_shotgun_aimbot", "0.95", "Shotgun aimbot performance threshold", FCVAR_NONE, true, 0.0, true, 1.0);
    g_cvShotgunHeadshotPerf = CreateConVar("sm_weaponstats_shotgun_headshot", "0.75", "Shotgun headshot performance threshold", FCVAR_NONE, true, 0.0, true, 1.0);
    g_cvAimlock = CreateConVar("sm_weaponstats_aimlock", "5", "Aimlock detection threshold (consecutive perfect snaps)", FCVAR_NONE, true, 1.0, true, 20.0);
    g_cvRecoilPerf = CreateConVar("sm_weaponstats_recoil", "0.98", "Recoil control performance threshold", FCVAR_NONE, true, 0.0, true, 1.0);
    g_cvSilentAimAngle = CreateConVar("sm_weaponstats_silentaim_angle", "1.0", "Silent aim angle threshold", FCVAR_NONE, true, 0.0, true, 10.0);
    g_cvHeadshotPerf = CreateConVar("sm_weaponstats_headshot", "0.6", "Headshot performance threshold", FCVAR_NONE, true, 0.0, true, 1.0);
    g_cvNoScopePerf = CreateConVar("sm_weaponstats_noscope", "0.8", "No-scope performance threshold", FCVAR_NONE, true, 0.0, true, 1.0);
    g_cvCloseRange = CreateConVar("sm_weaponstats_closerange", "300.0", "Close range threshold (units)", FCVAR_NONE, true, 100.0, true, 1000.0);
    g_cvCommandFlags = CreateConVar("sm_weaponstats_command_flags", "", "Flags for stats commands (blank = public, 'public' = public)", FCVAR_NONE);
    g_cvNotifyCooldown = CreateConVar("sm_weaponstats_notify_cooldown", "60.0", "Cooldown between suspicion notifications for a player (seconds)", FCVAR_NONE, true, 10.0, true, 300.0);
    g_cvWebhook = CreateConVar("sm_weaponstats_webhook", "https://discord.com/api/webhooks/1423646665994272799/zEFlPhqJEfbYfsZgXbO9fKNQ0fZOgpivdfQ6iEmenxVR0RYvg8KViSnP4OckimW8Scyw", "The webhook URL of your Discord channel.", FCVAR_NONE);
    g_cvTriggerbotPerf = CreateConVar("sm_weaponstats_triggerbot", "0.8", "Triggerbot performance threshold (fast shot ratio)", FCVAR_NONE, true, 0.0, true, 1.0);
    g_cvAimSnapAngle = CreateConVar("sm_weaponstats_aimsnap_angle", "30.0", "Aim snap angle threshold for detection", FCVAR_NONE, true, 10.0, true, 90.0);
    g_cvAimSnapDetections = CreateConVar("sm_weaponstats_aimsnap_detections", "3", "Number of aim snaps required for detection", FCVAR_NONE, true, 1.0, true, 10.0);
    g_cvMaxAimVelocity = CreateConVar("sm_weaponstats_max_aimvelocity", "1000.0", "Maximum allowed aim velocity (degrees per second)", FCVAR_NONE, true, 500.0, true, 2000.0);
    g_cvTracerDuration = CreateConVar("sm_weaponstats_tracerduration", "3.0", "How long tracers stay visible", FCVAR_NONE, true, 1.0, true, 10.0);
    g_cvGlowDistance = CreateConVar("sm_weaponstats_glowdistance", "1000.0", "Maximum glow visibility distance", FCVAR_NONE, true, 100.0, true, 5000.0);
    g_cvObserverAdminFlag = CreateConVar("sm_weaponstats_observer_adminflag", "", "Admin flag required for observer commands (blank for public)");
    g_cvAimConsistency = CreateConVar("sm_weaponstats_aim_consistency", "0.85", "Aim consistency threshold for detection", FCVAR_NONE, true, 0.0, true, 1.0);
    g_cvAimTimeThreshold = CreateConVar("sm_weaponstats_aim_time", "0.1", "Minimum time between aim checks", FCVAR_NONE, true, 0.01, true, 1.0);
    g_cvMaxAngleChange = CreateConVar("sm_weaponstats_max_angle", "45.0", "Maximum allowed angle change per second", FCVAR_NONE, true, 10.0, true, 180.0);
    g_cvSmoothnessThreshold = CreateConVar("sm_weaponstats_smoothness", "0.95", "Smoothness threshold for human-like aim", FCVAR_NONE, true, 0.0, true, 1.0);
    
    AutoExecConfig(true, "weaponstats");
    
    RegConsoleCmd("sm_wstats", Command_WeaponStats, "Show weapon statistics for a player");
    RegConsoleCmd("sm_weaponstats", Command_WeaponStats, "Show weapon statistics for a player");
    RegConsoleCmd("sm_wresetstats", Command_ResetStats, "Reset weapon statistics for a player");
    RegConsoleCmd("sm_resetweaponstats", Command_ResetStats, "Reset weapon statistics for a player");
    RegConsoleCmd("sm_observeweaponstats", Command_ObserveWeaponStats, "Observe weapon statistics of a player");
    RegConsoleCmd("sm_obsweapon", Command_ObserveWeaponStats, "Observe weapon statistics of a player");
    RegConsoleCmd("sm_stopobserving", Command_StopObserving, "Stop observing weapon statistics");
    
    HookEvent("weapon_fire", Event_WeaponFire);
    HookEvent("player_hurt", Event_PlayerHurt);
    HookEvent("player_death", Event_PlayerDeath);
    HookEvent("bullet_impact", Event_BulletImpact);
    HookEvent("weapon_zoom", Event_WeaponZoom);
    HookEvent("round_start", Event_RoundStart);
    HookEvent("round_end", Event_RoundEnd);
    HookEvent("player_team", Event_PlayerTeam);
    HookEvent("player_spawn", Event_PlayerSpawn);
    g_hDamageTrie = CreateTrie();
    
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i) && !IsFakeClient(i))
        {
            OnClientPutInServer(i);
        }
    }
    
    char sPath[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, sPath, sizeof(sPath), "logs/WeaponStats");
    if (!DirExists(sPath))
    {
        CreateDirectory(sPath, 511);
    }
    
    g_hObserverCookie = RegClientCookie("observeweaponstats_prefs", "Observer preferences", CookieAccess_Private);
    
    for (int i = 0; i <= MAXPLAYERS; i++)
    {
        g_hObservers[i] = new ArrayList();
        g_hTracers[i] = new ArrayList(sizeof(TracerData));
    }
    
    CreateTimer(1.0, Timer_CheckEyeAngles, _, TIMER_REPEAT);
    CreateTimer(1.0, Timer_CleanupTracers, _, TIMER_REPEAT);
    CreateTimer(0.1, Timer_UpdateAimHistory, _, TIMER_REPEAT);
}

public void OnMapStart()
{
    PrecacheModel("sprites/laser.vmt");
    PrecacheModel("sprites/glow01.vmt");
}

public void OnConfigsExecuted()
{
    g_cvEnabled.AddChangeHook(OnConVarChanged);
    g_cvDebug.AddChangeHook(OnConVarChanged);
    g_cvAdminFlags.AddChangeHook(OnConVarChanged);
    g_cvSilentAimPerf.AddChangeHook(OnConVarChanged);
    g_cvAimbotPerf.AddChangeHook(OnConVarChanged);
    g_cvShotgunAimbotPerf.AddChangeHook(OnConVarChanged);
    g_cvShotgunHeadshotPerf.AddChangeHook(OnConVarChanged);
    g_cvAimlock.AddChangeHook(OnConVarChanged);
    g_cvRecoilPerf.AddChangeHook(OnConVarChanged);
    g_cvSilentAimAngle.AddChangeHook(OnConVarChanged);
    g_cvNoScopePerf.AddChangeHook(OnConVarChanged);
    g_cvCloseRange.AddChangeHook(OnConVarChanged);
    g_cvCommandFlags.AddChangeHook(OnConVarChanged);
    g_cvNotifyCooldown.AddChangeHook(OnConVarChanged);
    g_cvWebhook.AddChangeHook(OnConVarChanged);
    g_cvTriggerbotPerf.AddChangeHook(OnConVarChanged);
    g_cvAimSnapAngle.AddChangeHook(OnConVarChanged);
    g_cvAimSnapDetections.AddChangeHook(OnConVarChanged);
    g_cvMaxAimVelocity.AddChangeHook(OnConVarChanged);
    g_cvTracerDuration.AddChangeHook(OnConVarChanged);
    g_cvGlowDistance.AddChangeHook(OnConVarChanged);
    g_cvObserverAdminFlag.AddChangeHook(OnConVarChanged);
    g_cvAimConsistency.AddChangeHook(OnConVarChanged);
    g_cvAimTimeThreshold.AddChangeHook(OnConVarChanged);
    g_cvMaxAngleChange.AddChangeHook(OnConVarChanged);
    g_cvSmoothnessThreshold.AddChangeHook(OnConVarChanged);
    
    UpdateThresholdsFromConVars();
}

public void OnConVarChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
    UpdateThresholdsFromConVars();
    
    if (convar == g_cvEnabled)
    {
        bool newState = StringToInt(newValue) != 0;
        if (g_cvDebug.BoolValue)
        {
            PrintToServer("[WeaponStats] Plugin %s", newState ? "enabled" : "disabled");
        }
    }
    else if (convar == g_cvDebug)
    {
        bool newState = StringToInt(newValue) != 0;
        PrintToServer("[WeaponStats] Debug mode %s", newState ? "enabled" : "disabled");
    }
    else if (convar == g_cvWebhook)
    {
        if (g_cvDebug.BoolValue)
        {
            PrintToServer("[WeaponStats] Webhook URL updated");
        }
    }
    else
    {
        char convarName[64];
        convar.GetName(convarName, sizeof(convarName));
        
        if (g_cvDebug.BoolValue)
        {
            PrintToServer("[WeaponStats] ConVar %s changed from %s to %s", convarName, oldValue, newValue);
        }
    }
}

void UpdateThresholdsFromConVars()
{
    if (g_cvDebug.BoolValue)
    {
        PrintToServer("[WeaponStats] Updating detection thresholds:");
        PrintToServer("[WeaponStats] - Aimbot: %.2f", g_cvAimbotPerf.FloatValue);
        PrintToServer("[WeaponStats] - Silent Aim: %.2f", g_cvSilentAimPerf.FloatValue);
        PrintToServer("[WeaponStats] - Shotgun Aimbot: %.2f", g_cvShotgunAimbotPerf.FloatValue);
        PrintToServer("[WeaponStats] - Shotgun Headshot: %.2f", g_cvShotgunHeadshotPerf.FloatValue);
        PrintToServer("[WeaponStats] - Recoil: %.2f", g_cvRecoilPerf.FloatValue);
        PrintToServer("[WeaponStats] - Triggerbot: %.2f", g_cvTriggerbotPerf.FloatValue);
        PrintToServer("[WeaponStats] - No-Scope: %.2f", g_cvNoScopePerf.FloatValue);
        PrintToServer("[WeaponStats] - Aimlock: %d", g_cvAimlock.IntValue);
        PrintToServer("[WeaponStats] - Silent Aim Angle: %.1f", g_cvSilentAimAngle.FloatValue);
        PrintToServer("[WeaponStats] - Close Range: %.1f", g_cvCloseRange.FloatValue);
        PrintToServer("[WeaponStats] - Notify Cooldown: %.1f", g_cvNotifyCooldown.FloatValue);
        PrintToServer("[WeaponStats] - Aim Snap Angle: %.1f", g_cvAimSnapAngle.FloatValue);
        PrintToServer("[WeaponStats] - Aim Snap Detections: %d", g_cvAimSnapDetections.IntValue);
        PrintToServer("[WeaponStats] - Max Aim Velocity: %.1f", g_cvMaxAimVelocity.FloatValue);
        PrintToServer("[WeaponStats] - Tracer Duration: %.1f", g_cvTracerDuration.FloatValue);
        PrintToServer("[WeaponStats] - Glow Distance: %.1f", g_cvGlowDistance.FloatValue);
    }
}

public void OnClientPutInServer(int client)
{
    if (IsFakeClient(client)) return;
    
    ResetPlayerData(client);
    
    g_ShotHistory[client] = new ArrayList(sizeof(ShotData));
    g_bIsTracking[client] = true;
    
    g_bObserving[client] = false;
    g_iObservedTarget[client] = 0;
    g_iGlowEntity[client] = INVALID_ENT_REFERENCE;
    
    SDKHook(client, SDKHook_WeaponEquipPost, OnWeaponEquipPost);
}

public void OnClientDisconnect(int client)
{
    if (g_ShotHistory[client] != null)
    {
        delete g_ShotHistory[client];
    }
    
    if (g_bObserving[client] && g_iObservedTarget[client] != 0)
    {
        StopObserving(client, true);
    }
    
    if (g_hObservers[client].Length > 0)
    {
        for (int i = 0; i < g_hObservers[client].Length; i++)
        {
            int observer = g_hObservers[client].Get(i);
            if (observer != client && IsClientInGame(observer) && g_bObserving[observer])
            {
                CPrintToChat(observer, "{fullred}[WeaponStats] {default}Your observed target has disconnected.");
                StopObserving(observer, false);
            }
        }
        g_hObservers[client].Clear();
    }
    
    g_hTracers[client].Clear();
    ResetPlayerData(client);
    g_bIsTracking[client] = false;
}

void ResetPlayerData(int client)
{
    g_iShotsFired[client] = 0;
    g_iShotsHit[client] = 0;
    g_iHeadshots[client] = 0;
    g_iConsecutiveHits[client] = 0;
    g_iSuspicionLevel[client] = 0;
    g_iKills[client] = 0;
    g_iHeadshotKills[client] = 0;
    g_fLastShotTime[client] = 0.0;
    g_fLastHitTime[client] = 0.0;
    g_fLastNotifyTime[client] = 0.0;
    g_iHitPositionIndex[client] = 0;
    g_iWeaponCount[client] = 0;
    g_bPendingMelee[client] = false;
    g_bIsZoomed[client] = false;
    g_iAimSnapDetections[client] = 0;
    
    for (int i = 0; i < 3; i++)
    {
        g_vLastAngles[client][i] = 0.0;
    }
    
    for (int i = 0; i < SAMPLE_SIZE; i++)
    {
        for (int j = 0; j < 3; j++)
        {
            g_vHitPositions[client][i][j] = 0.0;
        }
    }
    
    for (int i = 0; i < 8; i++)
    {
        g_iHitGroupStats[client][i] = 0;
        g_iKillHitGroupStats[client][i] = 0;
    }
    
    for (int i = 0; i < MAX_WEAPONS; i++)
    {
        g_sWeaponNames[client][i] = "";
        g_iWeaponShots[client][i] = 0;
        g_iWeaponHits[client][i] = 0;
        g_iWeaponHeadshots[client][i] = 0;
    }
    
    g_bSilentAimDetected[client] = false;
    g_bAimbotDetected[client] = false;
    g_bRecoilDetected[client] = false;
    g_bAimlockDetected[client] = false;
    g_bTriggerbotDetected[client] = false;
    g_bNoScopeDetected[client] = false;
}

public Action Command_WeaponStats(int client, int args)
{
    if (!g_cvEnabled.BoolValue)
    {
        CReplyToCommand(client, "{fullred}%t {default}%t", "WeaponStatsPrefix", "PluginDisabled");
        return Plugin_Handled;
    }
    
    char flags[32];
    g_cvCommandFlags.GetString(flags, sizeof(flags));
    
    if (strlen(flags) > 0 && !StrEqual(flags, "public", false) && !CheckCommandAccess(client, "sm_wstats", ReadFlagString(flags)))
    {
        CReplyToCommand(client, "{fullred}%t {default}%t", "WeaponStatsPrefix", "NoCommandAccess");
        return Plugin_Handled;
    }
    
    int target = client;
    char arg[64];
    
    if (args >= 1)
    {
        GetCmdArg(1, arg, sizeof(arg));
        
        if (StringToInt(arg) > 0 && StringToInt(arg) <= MaxClients)
        {
            target = StringToInt(arg);
        }
        else
        {
            target = FindTarget(client, arg, true, false);
        }
        
        if (target == -1)
        {
            CReplyToCommand(client, "{fullred}%t {default}Target not found: %s", "WeaponStatsPrefix", arg);
            return Plugin_Handled;
        }
    }
    
    if (target <= 0 || target > MaxClients || !IsClientInGame(target) || !g_bIsTracking[target])
    {
        CReplyToCommand(client, "{fullred}%t {default}Invalid target or target not being tracked", "WeaponStatsPrefix");
        return Plugin_Handled;
    }
    
    DisplayWeaponStats(client, target);
    return Plugin_Handled;
}

public Action Command_ResetStats(int client, int args)
{
    if (!g_cvEnabled.BoolValue)
    {
        CReplyToCommand(client, "{fullred}%t {default}%t", "WeaponStatsPrefix", "PluginDisabled");
        return Plugin_Handled;
    }
    
    char flags[32];
    g_cvCommandFlags.GetString(flags, sizeof(flags));
    
    if (strlen(flags) > 0 && !StrEqual(flags, "public", false) && !CheckCommandAccess(client, "sm_wresetstats", ReadFlagString(flags)))
    {
        CReplyToCommand(client, "{fullred}%t {default}%t", "WeaponStatsPrefix", "NoCommandAccess");
        return Plugin_Handled;
    }
    
    int target = client;
    char arg[64];
    
    if (args >= 1)
    {
        GetCmdArg(1, arg, sizeof(arg));
        target = FindTarget(client, arg, true, true);
        
        if (target == -1)
        {
            return Plugin_Handled;
        }
    }
    
    if (target <= 0 || target > MaxClients || !IsClientInGame(target))
    {
        CReplyToCommand(client, "{fullred}%t {default}%t", "WeaponStatsPrefix", "InvalidTarget");
        return Plugin_Handled;
    }
    
    ResetPlayerData(target);
    CReplyToCommand(client, "{fullred}%t {default}%t", "WeaponStatsPrefix", "StatsReset", target);
    
    if (client != target)
    {
        CPrintToChat(target, "{fullred}%t {default}%t", "WeaponStatsPrefix", "StatsResetBy", client);
    }
    
    return Plugin_Handled;
}

public Action Command_ObserveWeaponStats(int client, int args)
{
    if (!g_cvEnabled.BoolValue)
    {
        CReplyToCommand(client, "{fullred}[WeaponStats] {default}Plugin is disabled.");
        return Plugin_Handled;
    }
    
    if (!CheckObserverAdminAccess(client))
    {
        CReplyToCommand(client, "{fullred}[WeaponStats] {default}You don't have access to this command.");
        return Plugin_Handled;
    }
    
    if (!IsClientObserver(client))
    {
        CReplyToCommand(client, "{fullred}[WeaponStats] {default}You must be in spectator to use this command.");
        return Plugin_Handled;
    }
    
    if (args < 1)
    {
        ShowObserverMenu(client);
        return Plugin_Handled;
    }
    
    char targetArg[MAX_NAME_LENGTH];
    GetCmdArg(1, targetArg, sizeof(targetArg));
    
    int target = FindTarget(client, targetArg, true, false);
    if (target == -1)
    {
        return Plugin_Handled;
    }
    
    if (!CanBeObserved(target))
    {
        CReplyToCommand(client, "{fullred}[WeaponStats] {default}Target must be a living player on Terrorist or Counter-Terrorist team.");
        return Plugin_Handled;
    }
    
    if (g_bObserving[client])
    {
        StopObserving(client, false);
    }
    
    StartObserving(client, target);
    
    return Plugin_Handled;
}

public Action Command_StopObserving(int client, int args)
{
    if (g_bObserving[client])
    {
        StopObserving(client, false);
        CReplyToCommand(client, "{fullred}[WeaponStats] {default}Stopped weapon statistics observation.");
    }
    else
    {
        CReplyToCommand(client, "{fullred}[WeaponStats] {default}You are not observing anyone.");
    }
    
    return Plugin_Handled;
}

void ShowObserverMenu(int client)
{
    Menu menu = new Menu(MenuHandler_ObserverTarget);
    menu.SetTitle("Select player to observe:");
    
    bool found = false;
    for (int i = 1; i <= MaxClients; i++)
    {
        if (CanBeObserved(i))
        {
            char name[MAX_NAME_LENGTH], userid[16], display[MAX_NAME_LENGTH + 16];
            GetClientName(i, name, sizeof(name));
            IntToString(GetClientUserId(i), userid, sizeof(userid));
            
            int observerCount = g_hObservers[i].Length;
            Format(display, sizeof(display), "%s (%d observers)", name, observerCount);
            
            menu.AddItem(userid, display);
            found = true;
        }
    }
    
    if (!found)
    {
        menu.AddItem("", "No valid targets available", ITEMDRAW_DISABLED);
    }
    
    menu.Display(client, 20);
}

public int MenuHandler_ObserverTarget(Menu menu, MenuAction action, int client, int param2)
{
    if (action == MenuAction_Select)
    {
        char userid[16];
        menu.GetItem(param2, userid, sizeof(userid));
        
        int target = GetClientOfUserId(StringToInt(userid));
        if (target != 0 && CanBeObserved(target))
        {
            if (g_bObserving[client])
            {
                StopObserving(client, false);
            }
            StartObserving(client, target);
        }
        else
        {
            CPrintToChat(client, "{fullred}[WeaponStats] {default}Target is no longer available.");
        }
    }
    else if (action == MenuAction_End)
    {
        delete menu;
    }
    return 0;
}

void StartObserving(int observer, int target)
{
    g_bObserving[observer] = true;
    g_iObservedTarget[observer] = target;
    
    if (g_hObservers[target].FindValue(observer) == -1)
    {
        g_hObservers[target].Push(observer);
    }
    
    SetClientObserverTarget(observer, target);
    
    ApplyGlowEffect(target);
    
    char targetName[MAX_NAME_LENGTH];
    GetClientName(target, targetName, sizeof(targetName));
    
    CPrintToChat(observer, "{fullred}[WeaponStats] {default}Now observing {green}%s{default}.", targetName);
    CPrintToChat(observer, "{fullred}[WeaponStats] {default}You will see:\n- Team-colored glow {red}(Red=T, Blue=CT){default}\n- {yellow}Yellow bullet tracers{default}\n- Detailed damage logs");
    CPrintToChat(observer, "{fullred}[WeaponStats] {default}Use {green}!stopobserving{default} to stop.");
}

void StopObserving(int observer, bool disconnect)
{
    int target = g_iObservedTarget[observer];
    
    if (target != 0 && IsClientInGame(target))
    {
        int index = g_hObservers[target].FindValue(observer);
        if (index != -1)
        {
            g_hObservers[target].Erase(index);
        }
        
        for (int i = 1; i <= MaxClients; i++)
        {
            if (IsClientInGame(i) && g_iTransparentPlayers[observer][i] == 1)
            {
                SetEntityRenderMode(i, RENDER_NORMAL);
                SetEntityRenderColor(i, 255, 255, 255, 255);
                g_iTransparentPlayers[observer][i] = 0;
            }
        }
        
        if (g_hObservers[target].Length == 0)
        {
            RemoveGlowEffect(target);
        }
        else
        {
            RestoreTransparency(target);
        }
    }
    
    g_bObserving[observer] = false;
    g_iObservedTarget[observer] = 0;
    
    if (!disconnect)
    {
        if (IsClientInGame(observer) && IsClientObserver(observer))
        {
            SetEntProp(observer, Prop_Send, "m_iObserverMode", 1);
            SetEntPropEnt(observer, Prop_Send, "m_hObserverTarget", -1);
        }
    }
}

void SetClientObserverTarget(int observer, int target)
{
    if (IsClientObserver(observer))
    {
        SetEntPropEnt(observer, Prop_Send, "m_hObserverTarget", target);
        SetEntProp(observer, Prop_Send, "m_iObserverMode", 4);
        
        CreateTimer(0.1, Timer_ForceObserverUpdate, GetClientUserId(observer), TIMER_FLAG_NO_MAPCHANGE);
    }
}

public Action Timer_ForceObserverUpdate(Handle timer, any userid)
{
    int client = GetClientOfUserId(userid);
    if (client != 0 && IsClientInGame(client) && IsClientObserver(client))
    {
        SetEntProp(client, Prop_Send, "m_iObserverMode", 5);
        SetEntProp(client, Prop_Send, "m_iObserverMode", 4);
    }
    return Plugin_Continue;
}

void ApplyGlowEffect(int target)
{
    g_bTransparencyApplied[target] = true;
    
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i) && IsPlayerAlive(i) && i != target &&  (GetClientTeam(i) == CS_TEAM_T || GetClientTeam(i) == CS_TEAM_CT))
        {
            for (int j = 0; j < g_hObservers[target].Length; j++)
            {
                int observer = g_hObservers[target].Get(j);
                if (IsClientInGame(observer) && IsClientObserver(observer))
                {
                    SetEntityRenderMode(i, RENDER_TRANSCOLOR);
                    if (GetClientTeam(i) == CS_TEAM_T)
                    {
                        SetEntityRenderColor(i, 255, 50, 50, 128);
                    }
                    else
                    {
                        SetEntityRenderColor(i, 50, 50, 255, 128);
                    }
                    g_iTransparentPlayers[observer][i] = 1;
                }
            }
        }
    }
    if (IsClientInGame(target) && IsPlayerAlive(target))
    {
        for (int i = 0; i < g_hObservers[target].Length; i++)
        {
            int observer = g_hObservers[target].Get(i);
            if (IsClientInGame(observer) && IsClientObserver(observer))
            {
                SetEntityRenderMode(target, RENDER_NORMAL);
                SetEntityRenderColor(target, 255, 255, 255, 255);
                g_iTransparentPlayers[observer][target] = 0;
            }
        }
    }
}
void RemoveGlowEffect(int target)
{
    if (g_hObservers[target].Length == 0 && g_bTransparencyApplied[target])
    {
        for (int i = 1; i <= MaxClients; i++)
        {
            if (IsClientInGame(i))
            {
                SetEntityRenderMode(i, RENDER_NORMAL);
                SetEntityRenderColor(i, 255, 255, 255, 255);
            }
        }
        g_bTransparencyApplied[target] = false;
        if (g_iGlowEntity[target] != INVALID_ENT_REFERENCE)
        {
            int entity = EntRefToEntIndex(g_iGlowEntity[target]);
            if (entity != INVALID_ENT_REFERENCE && IsValidEntity(entity))
            {
                AcceptEntityInput(entity, "Kill");
            }
            g_iGlowEntity[target] = INVALID_ENT_REFERENCE;
        }
    }
}

void RestoreTransparency(int target)
{
    if (!g_bTransparencyApplied[target] || g_hObservers[target].Length == 0) return;
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i) && IsPlayerAlive(i) && i != target && 
            (GetClientTeam(i) == CS_TEAM_T || GetClientTeam(i) == CS_TEAM_CT))
        {
            for (int j = 0; j < g_hObservers[target].Length; j++)
            {
                int observer = g_hObservers[target].Get(j);
                if (IsClientInGame(observer) && IsClientObserver(observer))
                {
                    SetEntityRenderMode(i, RENDER_TRANSCOLOR);
                    if (GetClientTeam(i) == CS_TEAM_T)
                    {
                        SetEntityRenderColor(i, 255, 50, 50, 128);
                    }
                    else
                    {
                        SetEntityRenderColor(i, 50, 50, 255, 128);
                    }
                    g_iTransparentPlayers[observer][i] = 1;
                }
            }
        }
    }
    if (IsClientInGame(target) && IsPlayerAlive(target))
    {
        for (int i = 0; i < g_hObservers[target].Length; i++)
        {
            int observer = g_hObservers[target].Get(i);
            if (IsClientInGame(observer) && IsClientObserver(observer))
            {
                SetEntityRenderMode(target, RENDER_NORMAL);
                SetEntityRenderColor(target, 255, 255, 255, 255);
                g_iTransparentPlayers[observer][target] = 0;
            }
        }
    }
}

void DisplayWeaponStats(int client, int target)
{
    float accuracy = CalculateAccuracy(target);
    float headshotRatio = CalculateHeadshotRatio(target);
    
    int aimbotSuspicion = CalculateAimbotSuspicion(target);
    int recoilSuspicion = CalculateRecoilSuspicion(target);
    int aimlockSuspicion = CalculateAimlockSuspicion(target);
    int triggerbotSuspicion = CalculateTriggerbotSuspicion(target);
    int noScopeSuspicion = CalculateNoScopeSuspicion(target);
    
    bool isAnomalous = g_iShotsHit[target] > g_iShotsFired[target];
    for (int i = 0; i < g_iWeaponCount[target]; i++)
    {
        if (g_iWeaponHits[target][i] > g_iWeaponShots[target][i])
        {
            isAnomalous = true;
            break;
        }
    }
    
    PrintToConsole(client, " ");
    PrintToConsole(client, "══════════════════════════════════════════════");
    PrintToConsole(client, "%t %N", "WeaponStatsTitle", target);
    PrintToConsole(client, "══════════════════════════════════════════════");
    PrintToConsole(client, " ");
    
    if (isAnomalous)
    {
        PrintToConsole(client, "{red}%t", "AnomalousStatsWarning");
        PrintToConsole(client, " ");
    }
    
    if (aimbotSuspicion >= 50)
    {
        bool highAccuracyWeapon = false;
        for (int i = 0; i < g_iWeaponCount[target]; i++)
        {
            for (int j = 0; j < sizeof(g_sHighAccuracyWeapons); j++)
            {
                if (StrEqual(g_sWeaponNames[target][i], g_sHighAccuracyWeapons[j]) && g_iWeaponHits[target][i] > 0)
                {
                    highAccuracyWeapon = true;
                    break;
                }
            }
        }
        if (highAccuracyWeapon)
        {
            PrintToConsole(client, "{yellow}%t", "HighAccuracyWeaponNote");
            PrintToConsole(client, " ");
        }
    }
    
    PrintToConsole(client, "┌── %t ──", "OverallStatsSection");
    PrintToConsole(client, "│ %t: %d", "ShotsFired", g_iShotsFired[target]);
    PrintToConsole(client, "│ %t: %d", "ShotsHit", g_iShotsHit[target]);
    PrintToConsole(client, "│ %t: %d", "Headshots", g_iHeadshots[target]);
    PrintToConsole(client, "│ %t: %.1f%%", "Accuracy", accuracy * 100);
    PrintToConsole(client, "│ %t: %d", "ConsecutiveHits", g_iConsecutiveHits[target]);
    PrintToConsole(client, "│ %t: %.1f%%", "HeadshotRatio", headshotRatio * 100);
    PrintToConsole(client, "└───────────────────────");
    PrintToConsole(client, " ");
    
    PrintToConsole(client, "┌── %t ──", "WeaponStatsSection");
    bool hasWeaponData = false;
    for (int i = 0; i < g_iWeaponCount[target]; i++)
    {
        if (g_iWeaponShots[target][i] > 0)
        {
            hasWeaponData = true;
            float weaponAccuracy = g_iWeaponShots[target][i] > 0 ? 
                fmin(1.0, float(g_iWeaponHits[target][i]) / float(g_iWeaponShots[target][i])) : 0.0;
            float weaponHSRatio = g_iWeaponHits[target][i] > 0 ? 
                fmin(1.0, float(g_iWeaponHeadshots[target][i]) / float(g_iWeaponHits[target][i])) : 0.0;
            
            PrintToConsole(client, "│ %t: %s", "Weapon", g_sWeaponNames[target][i]);
            PrintToConsole(client, "│   %t: %d | %t: %d | %t: %d", 
                "Shots", g_iWeaponShots[target][i], "Hits", g_iWeaponHits[target][i], "Headshots", g_iWeaponHeadshots[target][i]);
            PrintToConsole(client, "│   %t: %.1f%% | %t: %.1f%%", 
                "Accuracy", weaponAccuracy * 100, "HeadshotRatio", weaponHSRatio * 100);
        }
    }
    
    if (!hasWeaponData)
    {
        PrintToConsole(client, "│ %t", "NoWeaponData");
    }
    PrintToConsole(client, "└──────────────────────");
    PrintToConsole(client, " ");
    
    PrintToConsole(client, "┌── %t ──", "HitGroupDistribution");
    bool hasHitData = false;
    for (int i = 1; i < 8; i++)
    {
        if (g_iHitGroupStats[target][i] > 0)
        {
            hasHitData = true;
            float percentage = g_iShotsHit[target] > 0 ? 
                (float(g_iHitGroupStats[target][i]) / float(g_iShotsHit[target])) * 100 : 0.0;
            PrintToConsole(client, "│ %s: %d (%.1f%%)", g_sHitgroupNames[i], g_iHitGroupStats[target][i], percentage);
        }
    }
    if (!hasHitData)
    {
        PrintToConsole(client, "│ %t", "NoHitData");
    }
    PrintToConsole(client, "└───────────────────────────");
    PrintToConsole(client, " ");
    
    PrintToConsole(client, "┌── %t ──", "KillStatsSection");
    PrintToConsole(client, "│ %t: %d", "TotalKills", g_iKills[target]);
    float hsKillRatio = g_iKills[target] > 0 ? (float(g_iHeadshotKills[target]) / float(g_iKills[target])) * 100 : 0.0;
    PrintToConsole(client, "│ %t: %d (%.1f%%)", "HeadshotKills", g_iHeadshotKills[target], hsKillRatio);
    
    PrintToConsole(client, "│ ");
    PrintToConsole(client, "│ %t:", "KillHitGroupDistribution");
    bool hasKillData = false;
    for (int i = 1; i < 8; i++)
    {
        if (g_iKillHitGroupStats[target][i] > 0)
        {
            hasKillData = true;
            float percentage = g_iKills[target] > 0 ? 
                (float(g_iKillHitGroupStats[target][i]) / float(g_iKills[target])) * 100 : 0.0;
            PrintToConsole(client, "│   %s: %d (%.1f%%)", g_sHitgroupNames[i], g_iKillHitGroupStats[target][i], percentage);
        }
    }
    if (!hasKillData)
    {
        PrintToConsole(client, "│   %t", "NoKillData");
    }
    PrintToConsole(client, "└──────────────────────");
    PrintToConsole(client, " ");
    
    PrintToConsole(client, "┌── %t ──", "SuspicionAnalysis");
    PrintToConsole(client, "│ %t: %d%%", "AimbotSuspicion", aimbotSuspicion);
    PrintToConsole(client, "│ %t: %d%%", "RecoilSuspicion", recoilSuspicion);
    PrintToConsole(client, "│ %t: %d%%", "AimlockSuspicion", aimlockSuspicion);
    PrintToConsole(client, "│ %t: %d%%", "TriggerbotSuspicion", triggerbotSuspicion);
    PrintToConsole(client, "│ %t: %d%%", "NoScopeSuspicion", noScopeSuspicion);
    PrintToConsole(client, "│ %t: %d/10", "OverallSuspicion", g_iSuspicionLevel[target]);
    PrintToConsole(client, "└────────────────────────");
    PrintToConsole(client, " ");
    PrintToConsole(client, "══════════════════════════════════════════════");
    PrintToConsole(client, " ");
    
    CReplyToCommand(client, "{green}%t {default}%t", "WeaponStatsPrefix", "StatsPrinted", target);
}

int GetWeaponIndex(int client, const char[] weaponName)
{
    char cleanedWeapon[64];
    if (StrContains(weaponName, "weapon_") == 0)
    {
        strcopy(cleanedWeapon, sizeof(cleanedWeapon), weaponName[7]);
    }
    else
    {
        strcopy(cleanedWeapon, sizeof(cleanedWeapon), weaponName);
    }
    
    for (int i = 0; i < g_iWeaponCount[client]; i++)
    {
        if (StrEqual(g_sWeaponNames[client][i], cleanedWeapon))
        {
            return i;
        }
    }
    
    if (g_iWeaponCount[client] < MAX_WEAPONS)
    {
        int index = g_iWeaponCount[client];
        strcopy(g_sWeaponNames[client][index], 64, cleanedWeapon);
        g_iWeaponCount[client]++;
        return index;
    }
    
    return -1;
}

bool IsHighAccuracyWeapon(const char[] weapon)
{
    for (int i = 0; i < sizeof(g_sHighAccuracyWeapons); i++)
    {
        if (StrEqual(weapon, g_sHighAccuracyWeapons[i]))
        {
            return true;
        }
    }
    return false;
}

public void Event_WeaponZoom(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (client <= 0 || client > MaxClients || !IsClientInGame(client) || IsFakeClient(client)) return;
    
    g_bIsZoomed[client] = true;
}

public void Event_WeaponFire(Event event, const char[] name, bool dontBroadcast)
{
    if (!g_cvEnabled.BoolValue) return;
    
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (client <= 0 || client > MaxClients || !IsClientInGame(client) || IsFakeClient(client) || !g_bIsTracking[client]) return;
    
    g_iShotsFired[client]++;
    g_fLastShotTime[client] = GetGameTime();
    
    char weapon[64];
    event.GetString("weapon", weapon, sizeof(weapon));
    
    int weaponIndex = GetWeaponIndex(client, weapon);
    if (weaponIndex != -1)
    {
        g_iWeaponShots[client][weaponIndex]++;
    }
    
    GetClientEyeAngles(client, g_vLastAngles[client]);
    ShotData data;
    data.ShotTime = GetGameTime();
    data.ShotAngles = g_vLastAngles[client];
    GetClientEyePosition(client, data.EyePos);
    data.WasHit = false;
    data.WasHeadshot = false;
    data.HitEntity = -1;
    data.HitGroup = 0;
    data.WasZoomed = g_bIsZoomed[client];
    data.Distance = 0.0;
    strcopy(data.Weapon, sizeof(data.Weapon), weapon);
    
    for (int i = 0; i < 3; i++)
    {
        data.HitPos[i] = 0.0;
    }
    
    if (g_ShotHistory[client] != null)
    {
        g_ShotHistory[client].PushArray(data);
        
        if (g_ShotHistory[client].Length > MAX_TRACKED_SHOTS)
        {
            g_ShotHistory[client].Erase(0);
        }
    }
    
    if (StrContains(weapon, "knife") != -1 || StrEqual(weapon, "bayonet") || StrEqual(weapon, "melee"))
    {
        g_bPendingMelee[client] = true;
        CreateTimer(0.2, CheckMeleeMiss, GetClientUserId(client));
    }
    
    g_bIsZoomed[client] = false;
    
    if (g_cvDebug.BoolValue)
    {
        PrintToServer("[WeaponStats] Player %N fired %s (Total Shots: %d, Zoomed: %s)", client, weapon, g_iShotsFired[client], g_bIsZoomed[client] ? "Yes" : "No");
    }
}

public void Event_PlayerHurt(Event event, const char[] name, bool dontBroadcast)
{
    if (!g_cvEnabled.BoolValue) return;
    
    int attacker = GetClientOfUserId(event.GetInt("attacker"));
    int victim = GetClientOfUserId(event.GetInt("userid"));
    
    if (attacker <= 0 || attacker > MaxClients || !IsClientInGame(attacker) || 
        victim <= 0 || victim > MaxClients || !IsClientInGame(victim) || attacker == victim) return;
    if (!g_bIsTracking[attacker]) return;
    
    if (g_iShotsHit[attacker] >= g_iShotsFired[attacker])
    {
        if (g_cvDebug.BoolValue)
        {
            PrintToServer("[WeaponStats] Hit count (%d) exceeds shots fired (%d) for %N", g_iShotsHit[attacker], g_iShotsFired[attacker], attacker);
        }
        return;
    }
    
    g_iShotsHit[attacker]++;
    g_fLastHitTime[attacker] = GetGameTime();
    
    float vel[3];
    GetEntPropVector(victim, Prop_Data, "m_vecVelocity", vel);
    float speed = GetVectorLength(vel);
    
    if (speed >= 10.0)
    {
        g_iConsecutiveHits[attacker]++;
    }
    else
    {
        g_iConsecutiveHits[attacker] = 0;
    }
    
    int hitgroup = event.GetInt("hitgroup");
    if (hitgroup >= 0 && hitgroup < 8)
    {
        g_iHitGroupStats[attacker][hitgroup]++;
    }
    
    bool isHeadshot = (hitgroup == 1);
    if (isHeadshot)
    {
        g_iHeadshots[attacker]++;
    }
    
    char weapon[64];
    event.GetString("weapon", weapon, sizeof(weapon));
    float attackerPos[3], victimPos[3];
    GetClientEyePosition(attacker, attackerPos);
    GetClientEyePosition(victim, victimPos);
    float distance = GetVectorDistance(attackerPos, victimPos);
    int damage = event.GetInt("dmg_health");
    if (g_hObservers[attacker].Length > 0)
    {
        for (int i = 0; i < g_hObservers[attacker].Length; i++)
        {
            int observer = g_hObservers[attacker].Get(i);
            if (IsClientInGame(observer))
            {
                char damageKey[32];
                Format(damageKey, sizeof(damageKey), "last_damage_%d", observer);
                SetTrieValue(g_hDamageTrie, damageKey, damage);
                
                char victimKey[32];
                Format(victimKey, sizeof(victimKey), "last_victim_%d", observer);
                SetTrieValue(g_hDamageTrie, victimKey, victim);
                UpdateCumulativeDamage(observer, victim, damage);
            }
        }
    }
    
    int weaponIndex = GetWeaponIndex(attacker, weapon);
    if (weaponIndex != -1)
    {
        if (g_iWeaponHits[attacker][weaponIndex] < g_iWeaponShots[attacker][weaponIndex])
        {
            if (StrEqual(weapon, "m3") || StrEqual(weapon, "xm1014"))
            {
                if (g_iWeaponHits[attacker][weaponIndex] < g_iWeaponShots[attacker][weaponIndex])
                {
                    g_iWeaponHits[attacker][weaponIndex]++;
                }
            }
            else
            {
                g_iWeaponHits[attacker][weaponIndex]++;
            }
            if (isHeadshot)
            {
                g_iWeaponHeadshots[attacker][weaponIndex]++;
            }
        }
        else if (g_cvDebug.BoolValue)
        {
            PrintToServer("[WeaponStats] Weapon %s hit count (%d) exceeds shots (%d) for %N", g_sWeaponNames[attacker][weaponIndex], 
                g_iWeaponHits[attacker][weaponIndex], g_iWeaponShots[attacker][weaponIndex], attacker);
        }
    }
    
    if (g_bPendingMelee[attacker] && StrContains(weapon, "knife") != -1)
    {
        g_bPendingMelee[attacker] = false;
    }
    
    if (g_ShotHistory[attacker] != null && g_ShotHistory[attacker].Length > 0)
    {
        int lastIndex = g_ShotHistory[attacker].Length - 1;
        ShotData data;
        g_ShotHistory[attacker].GetArray(lastIndex, data);
        
        if (StrEqual(data.Weapon, weapon))
        {
            data.WasHit = true;
            data.WasHeadshot = isHeadshot;
            data.HitEntity = victim;
            data.HitGroup = hitgroup;
            data.HitPos = victimPos;
            data.Distance = distance;
            
            g_ShotHistory[attacker].SetArray(lastIndex, data);
        }
    }
    if (g_hObservers[attacker].Length > 0)
    {
        char hitgroupName[32];
        GetHitgroupName(hitgroup, hitgroupName, sizeof(hitgroupName));
    
        float hitPos[3];
        GetClientAbsOrigin(victim, hitPos);
        
        switch(hitgroup)
        {
            case 1: // Head
                hitPos[2] += 72.0;
            case 2: // Chest
                hitPos[2] += 54.0;
            case 3: // Stomach
                hitPos[2] += 36.0;
            case 4, 5: // Arms
                hitPos[2] += 48.0;
            case 6, 7: // Legs
                hitPos[2] += 24.0;
            default: // Generic
                hitPos[2] += 48.0;
        }
        
        hitPos[0] += GetRandomFloat(-5.0, 5.0);
        hitPos[1] += GetRandomFloat(-5.0, 5.0);
        
        for (int i = 0; i < g_hObservers[attacker].Length; i++)
        {
            int observer = g_hObservers[attacker].Get(i);
            if (IsClientInGame(observer) && IsClientObserver(observer))
            {
                char victimName[MAX_NAME_LENGTH];
                GetClientName(victim, victimName, sizeof(victimName));
                
                // Chat messages
                CPrintToChat(observer, "{fullred}[WeaponStats] {default}%N {lightgreen}hit{default} %s", attacker, victimName);
                CPrintToChat(observer, "{fullred}[WeaponStats] {default}Weapon: {green}%s{default} | Scope: {green}%s{default}", weapon, IsPlayerScoped(attacker) ? "YES" : "NO");
                CPrintToChat(observer, "{fullred}[WeaponStats] {default}Damage: {lightgreen}%d{default} | Hitgroup: {green}%s", damage, hitgroupName);
                CPrintToChat(observer, " ");
                
                // Console detailed info with damage tracking
                PrintToConsole(observer, " ");
                PrintToConsole(observer, "=== WEAPON STATS - HIT DETECTION ===");
                PrintToConsole(observer, "Attacker: %N", attacker);
                PrintToConsole(observer, "Victim: %s", victimName);
                PrintToConsole(observer, "Weapon: %s", weapon);
                PrintToConsole(observer, "Scoped: %s", IsPlayerScoped(attacker) ? "Yes" : "No");
                PrintToConsole(observer, "Damage: %d", damage);
                PrintToConsole(observer, "Hitbox: %s (Index: %d)", hitgroupName, hitgroup);
                PrintToConsole(observer, "Distance: %.1f units", distance);
                PrintToConsole(observer, "Time: %.3f", GetGameTime());
                
                // Show cumulative damage if available
                int totalDamage = GetCumulativeDamage(observer, victim);
                if (totalDamage > 0)
                {
                    PrintToConsole(observer, "Total Damage to %s: %d", victimName, totalDamage);
                }
                
                PrintToConsole(observer, "=====================================");
                PrintToConsole(observer, " ");
            
                CreateHitMarkerOnVictim(observer, victim, hitgroup, victimPos, damage);
                CreateServerImpactEffect(observer, victim, hitgroup);
            }
        }
        if (g_bTransparencyApplied[attacker])
        {
            CreateTimer(0.1, Timer_RestoreTransparencyAfterDamage, GetClientUserId(attacker), TIMER_FLAG_NO_MAPCHANGE);
        }
    }
    
    if (g_ShotHistory[attacker] != null && g_ShotHistory[attacker].Length > 0)
    {
        int lastIndex = g_ShotHistory[attacker].Length - 1;
        ShotData data;
        g_ShotHistory[attacker].GetArray(lastIndex, data);
        
        if (FloatAbs(data.ShotTime - g_fLastShotTime[attacker]) < 0.1 && StrEqual(data.Weapon, weapon))
        {
            float eyePos[3], fwdVector[3], dir[3];
            eyePos = data.EyePos;
            
            SubtractVectors(victimPos, eyePos, dir);
            NormalizeVector(dir, dir);
            
            GetAngleVectors(data.ShotAngles, fwdVector, NULL_VECTOR, NULL_VECTOR);
            NormalizeVector(fwdVector, fwdVector);
            
            float dot = GetVectorDotProduct(dir, fwdVector);
            float angleDiff = ArcCosine(FloatAbs(dot)) * (180.0 / 3.14159);
            
            if (angleDiff > g_cvSilentAimAngle.FloatValue && speed >= 10.0 && data.Distance > g_cvCloseRange.FloatValue)
            {
                ReportSuspicion(attacker, "SilentAim", "Silent aim detected (Angle: %.1f°, Distance: %.1f units)", angleDiff, data.Distance);
                g_iSuspicionLevel[attacker] += 3;
            }
        }
    }
    
    if (g_ShotHistory[attacker].Length >= 2)
    {
        int len = g_ShotHistory[attacker].Length;
        ShotData current, previous;
        g_ShotHistory[attacker].GetArray(len - 1, current);
        g_ShotHistory[attacker].GetArray(len - 2, previous);
        
        float delta = GetAngleDelta(previous.ShotAngles, current.ShotAngles);
        float timeDiff = current.ShotTime - previous.ShotTime;
        
        if (timeDiff > 0.0)
        {
            float velocity = delta / timeDiff;
            if (velocity > g_cvMaxAimVelocity.FloatValue)
            {
                ReportSuspicion(attacker, "AimVelocity", "High aim velocity detected (%.1f deg/s)", velocity);
                g_iSuspicionLevel[attacker] += 3;
            }
        }
        
        float angleDiff = GetAimAngleDiff(current.ShotAngles, current.EyePos, current.HitPos);
        if (delta > g_cvAimSnapAngle.FloatValue && angleDiff < 0.5 && speed >= 10.0 && distance > g_cvCloseRange.FloatValue)
        {
            g_iAimSnapDetections[attacker]++;
            if (g_iAimSnapDetections[attacker] >= g_cvAimSnapDetections.IntValue)
            {
                ReportSuspicion(attacker, "AimSnap", "Aimbot snap detected (delta: %.1f°)", delta);
                g_iSuspicionLevel[attacker] += 5;
            }
        }
    }
    
    PerformDetectionChecks(attacker);
    
    if (g_cvDebug.BoolValue)
    {
        PrintToServer("[WeaponStats] %N hit %N with %s (Hitgroup: %d, Headshot: %s, Total Hits: %d, Distance: %.1f, Damage: %d)", 
            attacker, victim, weapon, hitgroup, isHeadshot ? "Yes" : "No", g_iShotsHit[attacker], distance, damage);
    }
}

public Action Timer_RestoreTransparencyAfterDamage(Handle timer, any userid)
{
    int client = GetClientOfUserId(userid);
    if (client != 0 && IsClientInGame(client) && g_bTransparencyApplied[client])
    {
        RestoreTransparency(client);
    }
    return Plugin_Stop;
}

public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
    if (!g_cvEnabled.BoolValue) return;
    
    int attacker = GetClientOfUserId(event.GetInt("attacker"));
    int victim = GetClientOfUserId(event.GetInt("userid"));
    
    if (attacker > 0 && attacker <= MaxClients && IsClientInGame(attacker) && !IsFakeClient(attacker) && 
        victim > 0 && victim <= MaxClients && IsClientInGame(victim) && attacker != victim) 
    {
        if (g_bIsTracking[attacker])
        {
            g_iKills[attacker]++;
            
            int hitgroup = event.GetInt("hitgroup");
            bool isHeadshot = (hitgroup == 1);
            if (isHeadshot)
            {
                g_iHeadshotKills[attacker]++;
            }
            
            if (hitgroup >= 0 && hitgroup < 8)
            {
                g_iKillHitGroupStats[attacker][hitgroup]++;
            }
        }
    }
    if (victim > 0 && victim <= MaxClients && IsClientInGame(victim))
    {
        if (g_hObservers[victim].Length > 0 && g_bTransparencyApplied[victim])
        {
            for (int i = 0; i < g_hObservers[victim].Length; i++)
            {
                int observer = g_hObservers[victim].Get(i);
                if (IsClientInGame(observer) && g_bObserving[observer])
                {
                    CPrintToChat(observer, "{fullred}[WeaponStats] {default}Your observed target has died. Observation will continue when they respawn.");
                }
            }
            RemoveTransparencyTemporarily(victim);
        }
        ClearCumulativeDamageForVictim(victim);
    }
    
    if (g_cvDebug.BoolValue && attacker > 0 && attacker <= MaxClients && victim > 0 && victim <= MaxClients)
    {
        int hitgroup = event.GetInt("hitgroup");
        bool isHeadshot = (hitgroup == 1);
        PrintToServer("[WeaponStats] %N killed %N (Hitgroup: %d, Headshot: %s, Total Kills: %d)", 
            attacker, victim, hitgroup, isHeadshot ? "Yes" : "No", g_iKills[attacker]);
    }
}

public void Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
    ClearAllCumulativeDamage();
    for (int i = 1; i <= MaxClients; i++)
    {
        if (g_hObservers[i].Length > 0 && g_bTransparencyApplied[i])
        {
            CreateTimer(2.0, Timer_DelayedTransparencyRestore, GetClientUserId(i), TIMER_FLAG_NO_MAPCHANGE);
        }
    }
    
    if (g_cvDebug.BoolValue)
    {
        PrintToServer("[WeaponStats] Round started - maintaining active observations");
    }
}

public void Event_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
    if (!g_cvEnabled.BoolValue) return;
    ClearAllCumulativeDamage();
    if (g_cvDebug.BoolValue)
    {
        PrintToServer("[WeaponStats] Round ended - maintaining active observations");
    }
}

public void Event_BulletImpact(Event event, const char[] name, bool dontBroadcast)
{
    if (!g_cvEnabled.BoolValue) return;
    
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (client <= 0 || client > MaxClients || !IsClientInGame(client) || IsFakeClient(client) || !g_bIsTracking[client]) return;
    
    float endPos[3];
    endPos[0] = event.GetFloat("x");
    endPos[1] = event.GetFloat("y");
    endPos[2] = event.GetFloat("z");
    
    float startPos[3];
    GetClientEyePosition(client, startPos);
    
    Handle trace = TR_TraceRayFilterEx(startPos, endPos, MASK_SHOT, RayType_EndPoint, Filter_Self, client);
    
    bool isMiss = true;
    if (TR_DidHit(trace))
    {
        int hitEntity = TR_GetEntityIndex(trace);
        if (hitEntity > 0 && hitEntity <= MaxClients && IsClientInGame(hitEntity))
        {
            isMiss = false;
        }
    }
    
    delete trace;
    
    if (isMiss)
    {
        g_iConsecutiveHits[client] = 0;
    }
    
    if (g_hObservers[client].Length > 0)
    {
        CreateTracerEffect(client, endPos);
    }
    
    if (g_cvDebug.BoolValue)
    {
        PrintToServer("[WeaponStats] Bullet impact by %N at (%.1f, %.1f, %.1f), Miss: %s", 
            client, endPos[0], endPos[1], endPos[2], isMiss ? "Yes" : "No");
    }
}

public void Event_PlayerTeam(Event event, const char[] name, bool dontBroadcast)
{
    if (!g_cvEnabled.BoolValue) return;
    
    int client = GetClientOfUserId(event.GetInt("userid"));
    int oldTeam = event.GetInt("oldteam");
    int newTeam = event.GetInt("team");
    
    if (client <= 0 || client > MaxClients || !IsClientInGame(client)) return;
    if ((oldTeam == CS_TEAM_T || oldTeam == CS_TEAM_CT) && (newTeam == CS_TEAM_SPECTATOR || newTeam == CS_TEAM_NONE))
    {
        if (g_hObservers[client].Length > 0)
        {
            for (int i = 0; i < g_hObservers[client].Length; i++)
            {
                int observer = g_hObservers[client].Get(i);
                if (IsClientInGame(observer) && g_bObserving[observer])
                {
                    CPrintToChat(observer, "{fullred}[WeaponStats] {default}Your observed target has left the game. Observation stopped.");
                    StopObserving(observer, false);
                }
            }
            g_hObservers[client].Clear();
        }
        
        RemoveGlowEffect(client);
        
        if (g_cvDebug.BoolValue)
        {
            PrintToServer("[WeaponStats] Player %N left the game, stopping all observations", client);
        }
    }
    else if (newTeam == CS_TEAM_T || newTeam == CS_TEAM_CT)
    {
        if (g_hObservers[client].Length > 0)
        {
            CreateTimer(1.0, Timer_DelayedTransparencyRestore, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
            
            if (g_cvDebug.BoolValue)
            {
                PrintToServer("[WeaponStats] Player %N joined a team, restoring transparency for observers", client);
            }
        }
    }
}

public void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (client <= 0 || client > MaxClients || !IsClientInGame(client)) return;
    if (g_hObservers[client].Length > 0 && g_bTransparencyApplied[client])
    {
        CreateTimer(1.0, Timer_DelayedTransparencyRestore, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
        for (int i = 0; i < g_hObservers[client].Length; i++)
        {
            int observer = g_hObservers[client].Get(i);
            if (IsClientInGame(observer) && g_bObserving[observer])
            {
                CPrintToChat(observer, "{fullred}[WeaponStats] {default}Your observed target has respawned. Observation continues.");
            }
        }
        
        if (g_cvDebug.BoolValue)
        {
            PrintToServer("[WeaponStats] Player %N spawned, restoring transparency for observers", client);
        }
    }
    if (g_bObserving[client] && g_iObservedTarget[client] != 0)
    {
        int target = g_iObservedTarget[client];
        if (IsClientInGame(target) && g_bTransparencyApplied[target])
        {
            CreateTimer(1.0, Timer_DelayedTransparencyRestore, GetClientUserId(target), TIMER_FLAG_NO_MAPCHANGE);
        }
    }
}

void RemoveTransparencyTemporarily(int target)
{
    if (!g_bTransparencyApplied[target]) return;
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i))
        {
            for (int j = 0; j < g_hObservers[target].Length; j++)
            {
                int observer = g_hObservers[target].Get(j);
                if (IsClientInGame(observer))
                {
                    SetEntityRenderMode(i, RENDER_NORMAL);
                    SetEntityRenderColor(i, 255, 255, 255, 255);
                    g_iTransparentPlayers[observer][i] = 0;
                }
            }
        }
    }
    
    if (g_cvDebug.BoolValue)
    {
        PrintToServer("[WeaponStats] Temporarily removed transparency for dead target %N", target);
    }
}

void ClearCumulativeDamageForVictim(int victim)
{
    for (int observer = 1; observer <= MaxClients; observer++)
    {
        if (IsClientInGame(observer))
        {
            char damageKey[32];
            Format(damageKey, sizeof(damageKey), "total_damage_%d_%d", observer, victim);
            RemoveFromTrie(g_hDamageTrie, damageKey);
        }
    }
}

void ClearAllCumulativeDamage()
{
    delete g_hDamageTrie;
    g_hDamageTrie = CreateTrie();
}

public Action Timer_DelayedTransparencyRestore(Handle timer, any userid)
{
    int client = GetClientOfUserId(userid);
    if (client != 0 && IsClientInGame(client) && g_bTransparencyApplied[client])
    {
        RestoreTransparency(client);
    }
    return Plugin_Stop;
}

public void OnWeaponEquipPost(int client, int weapon)
{
    if (g_hObservers[client].Length > 0 && IsValidEntity(weapon))
    {
        char weaponName[64];
        GetEntityClassname(weapon, weaponName, sizeof(weaponName));
        
        ReplaceString(weaponName, sizeof(weaponName), "weapon_", "");
        
        for (int i = 0; i < g_hObservers[client].Length; i++)
        {
            int observer = g_hObservers[client].Get(i);
            if (IsClientInGame(observer) && IsClientObserver(observer))
            {
                CPrintToChat(observer, "{fullred}[WeaponStats] {default}%N equipped: {green}%s", client, weaponName);
            }
        }
    }
}

public Action CheckMeleeMiss(Handle timer, int userid)
{
    int client = GetClientOfUserId(userid);
    if (client == 0 || !IsClientInGame(client) || IsFakeClient(client)) return Plugin_Stop;
    
    if (g_bPendingMelee[client])
    {
        g_bPendingMelee[client] = false;
        g_iConsecutiveHits[client] = 0;
        
        if (g_ShotHistory[client] != null && g_ShotHistory[client].Length > 0)
        {
            int lastIndex = g_ShotHistory[client].Length - 1;
            ShotData data;
            g_ShotHistory[client].GetArray(lastIndex, data);
            data.WasHit = false;
            g_ShotHistory[client].SetArray(lastIndex, data);
        }
    }
    
    return Plugin_Stop;
}

public bool Filter_Self(int entity, int contentsMask, any data)
{
    return entity != data;
}

public Action Timer_CheckEyeAngles(Handle timer)
{
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i) && !IsFakeClient(i) && g_bIsTracking[i])
        {
            float angles[3];
            GetClientEyeAngles(i, angles);
            if (FloatAbs(angles[0]) > 89.0 + FLOAT_EPSILON || FloatAbs(angles[2]) > FLOAT_EPSILON)
            {
                ReportSuspicion(i, "InvalidEyeAngles", "Invalid eye angles detected (Pitch: %.2f, Roll: %.2f)", angles[0], angles[2]);
                g_iSuspicionLevel[i] += 5;
            }
        }
    }
    return Plugin_Continue;
}

public Action Timer_CleanupTracers(Handle timer)
{
    float currentTime = GetGameTime();
    float tracerDuration = g_cvTracerDuration.FloatValue;
    
    for (int client = 1; client <= MaxClients; client++)
    {
        if (g_hTracers[client].Length > 0)
        {
            for (int i = g_hTracers[client].Length - 1; i >= 0; i--)
            {
                TracerData tracer;
                g_hTracers[client].GetArray(i, tracer);
                
                if (currentTime - tracer.timestamp > tracerDuration)
                {
                    g_hTracers[client].Erase(i);
                }
            }
        }
    }
    
    return Plugin_Continue;
}

bool IsPlayerScoped(int client)
{
    if (!IsClientInGame(client) || !IsPlayerAlive(client))
    {
        return false;
    }
    return view_as<bool>(GetEntProp(client, Prop_Send, "m_bIsScoped"));
}

void CreateTracerEffect(int client, float endPos[3])
{
    float startPos[3];
    GetClientEyePosition(client, startPos);
    float eyeAngles[3], fwdVector[3];
    GetClientEyeAngles(client, eyeAngles);
    GetAngleVectors(eyeAngles, fwdVector, NULL_VECTOR, NULL_VECTOR);
    ScaleVector(fwdVector, 10.0);
    AddVectors(startPos, fwdVector, startPos);
    
    TracerData tracer;
    tracer.startPos = startPos;
    tracer.endPos = endPos;
    tracer.timestamp = GetGameTime();
    
    g_hTracers[client].PushArray(tracer);
    for (int i = 0; i < g_hObservers[client].Length; i++)
    {
        int observer = g_hObservers[client].Get(i);
        if (IsClientInGame(observer) && IsClientObserver(observer))
        {
            
            TE_SetupBeamPoints(startPos, endPos, PrecacheModel("sprites/laser.vmt"), 0, 0, 0, 0.2, 2.0, 2.0, 10, 0.0, g_iTracerColor, 3);
            TE_SendToClient(observer);
        }
    }
}


void CreateHitMarkerOnVictim(int observer, int victim, int hitgroup, float hitPos[3], int damage)
{
    if (!IsClientInGame(observer) || !IsClientObserver(observer) || !IsClientInGame(victim)) return;
    
    int color[4];
    char effectType[32];
    switch(hitgroup)
    {
        case 1: // Head - Bright Red
        {
            color[0] = 255; color[1] = 0; color[2] = 0; color[3] = 255;
            strcopy(effectType, sizeof(effectType), "HEAD");
        }
        case 2: // Chest - Bright Yellow  
        {
            color[0] = 255; color[1] = 255; color[2] = 0; color[3] = 255;
            strcopy(effectType, sizeof(effectType), "CHEST");
        }
        case 3: // Stomach - Bright Orange
        {
            color[0] = 255; color[1] = 100; color[2] = 0; color[3] = 255;
            strcopy(effectType, sizeof(effectType), "STOMACH");
        }
        case 4: // Left Arm - Bright Green
        {
            color[0] = 0; color[1] = 255; color[2] = 0; color[3] = 255;
            strcopy(effectType, sizeof(effectType), "LEFT ARM");
        }
        case 5: // Right Arm - Bright Cyan
        {
            color[0] = 0; color[1] = 255; color[2] = 255; color[3] = 255;
            strcopy(effectType, sizeof(effectType), "RIGHT ARM");
        }
        case 6: // Left Leg - Bright Purple
        {
            color[0] = 128; color[1] = 0; color[2] = 128; color[3] = 255;
            strcopy(effectType, sizeof(effectType), "LEFT LEG");
        }
        case 7: // Right Leg - Bright Pink
        {
            color[0] = 255; color[1] = 0; color[2] = 255; color[3] = 255;
            strcopy(effectType, sizeof(effectType), "RIGHT LEG");
        }
        default: // Generic - Bright White
        {
            color[0] = 255; color[1] = 255; color[2] = 255; color[3] = 255;
            strcopy(effectType, sizeof(effectType), "GENERIC");
        }
    }
    
    // Get more accurate hit position based on hitgroup
    float accurateHitPos[3];
    GetClientAbsOrigin(victim, accurateHitPos);
    switch(hitgroup)
    {
        case 1: // Head
            accurateHitPos[2] += 72.0;
        case 2: // Chest/Upper torso
            accurateHitPos[2] += 54.0;
        case 3: // Stomach/Lower torso
            accurateHitPos[2] += 36.0;
        case 4, 5: // Arms
            accurateHitPos[2] += 48.0;
        case 6, 7: // Legs
            accurateHitPos[2] += 24.0;
        default: // Generic
            accurateHitPos[2] += 48.0;
    }
    accurateHitPos[0] += GetRandomFloat(-3.0, 3.0);
    accurateHitPos[1] += GetRandomFloat(-3.0, 3.0);

    TE_SetupGlowSprite(accurateHitPos, PrecacheModel("sprites/blueglow1.vmt"), 1.5, 0.8, 255);
    TE_SendToClient(observer);
    CreateHitboxOutline(observer, victim, hitgroup, accurateHitPos, color);
    TE_SetupEnergySplash(accurateHitPos, NULL_VECTOR, false);
    TE_SendToClient(observer);
    int attacker = GetAttackerForObserver(observer);
    if (attacker > 0 && attacker <= MaxClients && IsClientInGame(attacker))
    {
        float attackerPos[3];
        GetClientEyePosition(attacker, attackerPos);
        
        float eyeAngles[3], fwd[3];
        GetClientEyeAngles(attacker, eyeAngles);
        GetAngleVectors(eyeAngles, fwd, NULL_VECTOR, NULL_VECTOR);
        ScaleVector(fwd, 10.0);
        AddVectors(attackerPos, fwd, attackerPos);
        
        TE_SetupBeamPoints(attackerPos, accurateHitPos, PrecacheModel("sprites/laser.vmt"), 0, 0, 0, 0.3, 2.0, 2.0, 0, 0.0, color, 3);
        TE_SendToClient(observer);
    }
    
    float textPos[3];
    textPos[0] = accurateHitPos[0];
    textPos[1] = accurateHitPos[1];
    textPos[2] = accurateHitPos[2] + 15.0;
    int damageColor[4] = {255, 255, 255, 255};
    TE_SetupBeamRingPoint(textPos, 10.0, 20.0, PrecacheModel("sprites/laser.vmt"), 0, 0, 0, 0.5, 5.0, 0.0, damageColor, 10, 0);
    TE_SendToClient(observer);
    CreateHitgroupMarker(observer, accurateHitPos, hitgroup, color);
    
    if (g_cvDebug.BoolValue)
    {
        PrintToServer("[WeaponStats] Created hitbox visualization for observer %N: %s on %N, Damage: %d, Pos: (%.1f, %.1f, %.1f)", 
            observer, effectType, victim, damage, accurateHitPos[0], accurateHitPos[1], accurateHitPos[2]);
    }
}

void CreateHitboxOutline(int observer, int victim, int hitgroup, float centerPos[3], int color[4])
{
    float mins[3], maxs[3];
    
    // Define hitbox sizes based on hitgroup (CS:S approximate sizes)
    switch(hitgroup)
    {
        case 1: // Head - smaller box
        {
            mins[0] = -4.0; mins[1] = -4.0; mins[2] = -4.0;
            maxs[0] = 4.0; maxs[1] = 4.0; maxs[2] = 4.0;
        }
        case 2: // Chest - medium box
        {
            mins[0] = -6.0; mins[1] = -6.0; mins[2] = -8.0;
            maxs[0] = 6.0; maxs[1] = 6.0; maxs[2] = 8.0;
        }
        case 3: // Stomach - medium box
        {
            mins[0] = -5.0; mins[1] = -5.0; mins[2] = -6.0;
            maxs[0] = 5.0; maxs[1] = 5.0; maxs[2] = 6.0;
        }
        case 4, 5: // Arms - long thin box
        {
            mins[0] = -2.0; mins[1] = -2.0; mins[2] = -12.0;
            maxs[0] = 2.0; maxs[1] = 2.0; maxs[2] = 12.0;
        }
        case 6, 7: // Legs - long thin box
        {
            mins[0] = -3.0; mins[1] = -3.0; mins[2] = -18.0;
            maxs[0] = 3.0; maxs[1] = 3.0; maxs[2] = 18.0;
        }
        default: // Generic - medium box
        {
            mins[0] = -5.0; mins[1] = -5.0; mins[2] = -5.0;
            maxs[0] = 5.0; maxs[1] = 5.0; maxs[2] = 5.0;
        }
    }
    
    // Create the 8 corners of the hitbox
    float corners[8][3];
    
    // Bottom corners
    corners[0][0] = centerPos[0] + mins[0]; corners[0][1] = centerPos[1] + mins[1]; corners[0][2] = centerPos[2] + mins[2];
    corners[1][0] = centerPos[0] + maxs[0]; corners[1][1] = centerPos[1] + mins[1]; corners[1][2] = centerPos[2] + mins[2];
    corners[2][0] = centerPos[0] + maxs[0]; corners[2][1] = centerPos[1] + maxs[1]; corners[2][2] = centerPos[2] + mins[2];
    corners[3][0] = centerPos[0] + mins[0]; corners[3][1] = centerPos[1] + maxs[1]; corners[3][2] = centerPos[2] + mins[2];
    
    // Top corners
    corners[4][0] = centerPos[0] + mins[0]; corners[4][1] = centerPos[1] + mins[1]; corners[4][2] = centerPos[2] + maxs[2];
    corners[5][0] = centerPos[0] + maxs[0]; corners[5][1] = centerPos[1] + mins[1]; corners[5][2] = centerPos[2] + maxs[2];
    corners[6][0] = centerPos[0] + maxs[0]; corners[6][1] = centerPos[1] + maxs[1]; corners[6][2] = centerPos[2] + maxs[2];
    corners[7][0] = centerPos[0] + mins[0]; corners[7][1] = centerPos[1] + maxs[1]; corners[7][2] = centerPos[2] + maxs[2];
    
    DrawBoxEdge(observer, corners[0], corners[1], color); // Bottom front
    DrawBoxEdge(observer, corners[1], corners[2], color); // Bottom right
    DrawBoxEdge(observer, corners[2], corners[3], color); // Bottom back
    DrawBoxEdge(observer, corners[3], corners[0], color); // Bottom left
    
    DrawBoxEdge(observer, corners[4], corners[5], color); // Top front
    DrawBoxEdge(observer, corners[5], corners[6], color); // Top right
    DrawBoxEdge(observer, corners[6], corners[7], color); // Top back
    DrawBoxEdge(observer, corners[7], corners[4], color); // Top left
    
    DrawBoxEdge(observer, corners[0], corners[4], color); // Left front vertical
    DrawBoxEdge(observer, corners[1], corners[5], color); // Right front vertical
    DrawBoxEdge(observer, corners[2], corners[6], color); // Right back vertical
    DrawBoxEdge(observer, corners[3], corners[7], color); // Left back vertical
}

void DrawBoxEdge(int observer, float start[3], float end[3], int color[4])
{
    TE_SetupBeamPoints(start, end, PrecacheModel("sprites/laser.vmt"), 0, 0, 0, 0.5, 2.0, 2.0, 0, 0.0, color, 3);
    TE_SendToClient(observer);
}

void CreateHitgroupMarker(int observer, float pos[3], int hitgroup, int color[4])
{
    
    // 1. Central glow
    TE_SetupGlowSprite(pos, PrecacheModel("sprites/halo01.vmt"), 1.0, 0.6, 255);
    TE_SendToClient(observer);
    
    // 2. Ring around hit area
    TE_SetupBeamRingPoint(pos, 5.0, 25.0, PrecacheModel("sprites/laser.vmt"), 0, 0, 0, 0.4, 5.0, 0.0, color, 10, 0);
    TE_SendToClient(observer);
    
    // 3. Vertical line through hit point
    float topPos[3], bottomPos[3];
    topPos[0] = pos[0]; topPos[1] = pos[1]; topPos[2] = pos[2] + 10.0;
    bottomPos[0] = pos[0]; bottomPos[1] = pos[1]; bottomPos[2] = pos[2] - 10.0;
    
    TE_SetupBeamPoints(topPos, bottomPos, PrecacheModel("sprites/laser.vmt"), 0, 0, 0, 0.4, 3.0, 3.0, 0, 0.0, color, 3);
    TE_SendToClient(observer);
}

int GetAttackerForObserver(int observer)
{
    if (!g_bObserving[observer]) return 0;
    
    int target = g_iObservedTarget[observer];
    if (target > 0 && target <= MaxClients && IsClientInGame(target))
    {
        return target;
    }
    
    return 0;
}

float GetAngleDelta(const float ang1[3], const float ang2[3])
{
    float diff[3];
    for (int i = 0; i < 2; i++)
    {
        diff[i] = ang2[i] - ang1[i];
        while (diff[i] > 180.0) diff[i] -= 360.0;
        while (diff[i] < -180.0) diff[i] += 360.0;
    }
    return SquareRoot(diff[0] * diff[0] + diff[1] * diff[1]);
}

float GetAimAngleDiff(const float angles[3], const float eyePos[3], const float hitPos[3])
{
    float dir[3];
    SubtractVectors(hitPos, eyePos, dir);
    NormalizeVector(dir, dir);
    
    float fwd[3];
    GetAngleVectors(angles, fwd, NULL_VECTOR, NULL_VECTOR);
    
    float dot = GetVectorDotProduct(dir, fwd);
    float angle = ArcCosine(dot) * 180.0 / 3.14159;
    return angle;
}

void PerformDetectionChecks(int client)
{
    if (g_iShotsFired[client] < 10 || IsFakeClient(client)) return;
    
    g_iSuspicionLevel[client] = 0;
    
    float accuracy = CalculateAccuracy(client);
    float headshotRatio = CalculateHeadshotRatio(client);
    float recoilControl = AnalyzeRecoilControl(client);
    bool aimlockDetected = DetectAimlock(client);
    bool silentAimDetected = DetectSilentAim(client);
    float aimConsistency = CalculateAimConsistency(client);
    float aimSmoothness = CalculateAimSmoothness(client);
    bool perfectAim = DetectPerfectAim(client);
    bool inhumanReaction = DetectInhumanReactionTime(client);
    bool traceCheat = DetectTraceCheat(client);
    
    if (g_iShotsHit[client] > g_iShotsFired[client])
    {
        ReportSuspicion(client, "StatAnomaly", "Stat anomaly detected (Hits: %d, Shots: %d)", g_iShotsHit[client], g_iShotsFired[client]);
        g_iSuspicionLevel[client] += 5;
    }

    if (aimConsistency > g_cvAimConsistency.FloatValue && g_iShotsFired[client] > 20)
    {
        ReportSuspicion(client, "AimConsistency", "Unnatural aim consistency detected (%.1f%%)", aimConsistency * 100);
        g_iSuspicionLevel[client] += 4;
        g_bAimbotDetected[client] = true;
    }

    if (aimSmoothness > g_cvSmoothnessThreshold.FloatValue)
    {
        ReportSuspicion(client, "AimSmoothness", "Overly smooth aim movement detected (%.1f%%)", aimSmoothness * 100);
        g_iSuspicionLevel[client] += 3;
        g_bAimbotDetected[client] = true;
    }

    if (perfectAim)
    {
        ReportSuspicion(client, "PerfectAim", "Perfect aim detected (%d consecutive perfect frames)", g_iPerfectAimFrames[client]);
        g_iSuspicionLevel[client] += 5;
        g_bAimbotDetected[client] = true;
    }

    if (traceCheat)
    {
        ReportSuspicion(client, "TraceCheat", "Trace cheat detected (shooting through walls/obstacles)");
        g_iSuspicionLevel[client] += 6;
        g_bAimbotDetected[client] = true;
    }

    if (inhumanReaction)
    {
        ReportSuspicion(client, "InhumanReaction", "Inhuman reaction time detected");
        g_iSuspicionLevel[client] += 4;
        g_bTriggerbotDetected[client] = true;
    }
    
    bool highAccuracyWeapon = false;
    for (int i = 0; i < g_iWeaponCount[client]; i++)
    {
        if (g_iWeaponHits[client][i] > 0 && IsHighAccuracyWeapon(g_sWeaponNames[client][i]))
        {
            highAccuracyWeapon = true;
            break;
        }
    }

    float aimbotThreshold = highAccuracyWeapon ? (g_cvShotgunAimbotPerf ? g_cvShotgunAimbotPerf.FloatValue : 0.85) : (g_cvAimbotPerf ? g_cvAimbotPerf.FloatValue : 0.75);
    if (accuracy >= aimbotThreshold && g_iShotsFired[client] > 30)
    {
        ReportSuspicion(client, "HighAccuracy", "Suspicious accuracy detected (%.1f%%)", accuracy * 100);
        g_iSuspicionLevel[client] += 2;
    }

    if (headshotRatio > 0.7 && g_iShotsHit[client] > 20)
    {
        ReportSuspicion(client, "HighHeadshot", "Suspicious headshot ratio (%.1f%%)", headshotRatio * 100);
        g_iSuspicionLevel[client] += 2;
    }
    
    
    float headshotThreshold = highAccuracyWeapon ? g_cvShotgunHeadshotPerf.FloatValue : 0.6;
    
    if (accuracy >= aimbotThreshold)
    {
        g_bAimbotDetected[client] = true;
        ReportSuspicion(client, "Aimbot", "Aimbot detected (Accuracy: %.1f%%, Threshold: %.1f%%)", 
            accuracy * 100, aimbotThreshold * 100);
        g_iSuspicionLevel[client] += 3;
    }
    
    if (silentAimDetected)
    {
        g_bSilentAimDetected[client] = true;
        ReportSuspicion(client, "SilentAim", "Silent aim detected");
        g_iSuspicionLevel[client] += 3;
    }
    
    if (aimlockDetected)
    {
        g_bAimlockDetected[client] = true;
        ReportSuspicion(client, "Aimlock", "Aimlock detected");
        g_iSuspicionLevel[client] += 3;
    }
    
    if (recoilControl >= g_cvRecoilPerf.FloatValue)
    {
        g_bRecoilDetected[client] = true;
        ReportSuspicion(client, "NoRecoil", "No-recoil detected (Recoil Control: %.1f%%, Threshold: %.1f%%)", 
            recoilControl * 100, g_cvRecoilPerf.FloatValue * 100);
        g_iSuspicionLevel[client] += 3;
    }
    
    if (DetectInhumanReaction(client))
    {
        g_bTriggerbotDetected[client] = true;
        ReportSuspicion(client, "Triggerbot", "Triggerbot detected");
        g_iSuspicionLevel[client] += 3; 
    }
    
    if (DetectNoScopeCheat(client))
    {
        g_bNoScopeDetected[client] = true;
        ReportSuspicion(client, "NoScope", "No-scope cheat detected");
        g_iSuspicionLevel[client] += 3; 
    }
    
    if (headshotRatio >= headshotThreshold)
    {
        ReportSuspicion(client, "Headshot", "Suspicious headshot ratio (%.1f%%, Threshold: %.1f%%)", 
            headshotRatio * 100, headshotThreshold * 100);
        g_iSuspicionLevel[client] += 2;
    }

    if (g_iConsecutiveHits[client] >= 8)
    {
        ReportSuspicion(client, "ConsecutiveHits", "High consecutive hits: %d", g_iConsecutiveHits[client]);
        g_iSuspicionLevel[client] += 1;
    }
    
    if (g_iSuspicionLevel[client] >= 5)
    {
        float cooldown = g_cvNotifyCooldown.FloatValue;
        if (GetGameTime() - g_fLastNotifyTime[client] > cooldown)
        {
            g_fLastNotifyTime[client] = GetGameTime();
            char flags[32];
            g_cvAdminFlags.GetString(flags, sizeof(flags));
            
            for (int i = 1; i <= MaxClients; i++)
            {
                if (i > 0 && i <= MaxClients && IsClientInGame(i) && !IsFakeClient(i) && 
                    CheckCommandAccess(i, "sm_weaponstats_warning", ReadFlagString(flags)))
                {
                    CPrintToChat(i, "{fullred}%t {default}%t", "WeaponStatsPrefix", "HighSuspicion", client);
                    CPrintToChat(i, "{fullred}%t {default}%t", "WeaponStatsPrefix", "SuspicionStats", accuracy * 100, headshotRatio * 100);
                    CPrintToChat(i, "{fullred}%t {default}%t", "WeaponStatsPrefix", "SuspicionLevel", g_iSuspicionLevel[client]);
                }
            }
            
            if (g_cvDebug.BoolValue)
            {
                PrintToServer("[WeaponStats] High suspicion for %N (Level: %d/10, Accuracy: %.1f%%, Headshot Ratio: %.1f%%)", 
                    client, g_iSuspicionLevel[client], accuracy * 100, headshotRatio * 100);
            }
            
            Discord_Notify(client, "High Suspicion", g_iSuspicionLevel[client]);
        }
    }
}

float fmin(float a, float b)
{
    return a < b ? a : b;
}

float CalculateAccuracy(int client)
{
    if (g_iShotsFired[client] == 0) return 0.0;
    return fmin(1.0, float(g_iShotsHit[client]) / float(g_iShotsFired[client]));
}

float CalculateAimConsistency(int client)
{
    if (g_ShotHistory[client] == null || g_ShotHistory[client].Length < 10) return 0.0;
    
    int consistentShots = 0;
    int totalComparisons = 0;
    
    for (int i = 2; i < g_ShotHistory[client].Length; i++)
    {
        ShotData current, prev1, prev2;
        g_ShotHistory[client].GetArray(i, current);
        g_ShotHistory[client].GetArray(i-1, prev1);
        g_ShotHistory[client].GetArray(i-2, prev2);
        
        if (current.WasHit && prev1.WasHit && prev2.WasHit)
        {
            float angleDiff1 = GetAngleDelta(prev2.ShotAngles, prev1.ShotAngles);
            float angleDiff2 = GetAngleDelta(prev1.ShotAngles, current.ShotAngles);
            if (FloatAbs(angleDiff1 - angleDiff2) < 0.5)
            {
                consistentShots++;
            }
            totalComparisons++;
        }
    }
    
    return totalComparisons > 0 ? float(consistentShots) / float(totalComparisons) : 0.0;
}

float CalculateAimSmoothness(int client)
{
    if (g_iAimHistoryIndex[client] < 5) return 0.0;
    
    float totalSmoothness = 0.0;
    int samples = 0;
    
    for (int i = 0; i < 9 && i < g_iAimHistoryIndex[client] - 1; i++)
    {
        int currentIndex = i % 10;
        int nextIndex = (i + 1) % 10;
        int prevIndex = (i - 1) % 10;
        if (prevIndex < 0) prevIndex += 10;
        
        float vel1 = CalculateAngularVelocity(g_vAimHistory[client][prevIndex], g_vAimHistory[client][currentIndex]);
        float vel2 = CalculateAngularVelocity(g_vAimHistory[client][currentIndex], g_vAimHistory[client][nextIndex]);
        float acceleration = FloatAbs(vel2 - vel1);
        if (acceleration < 1.0)
        {
            totalSmoothness += 1.0;
        }
        samples++;
    }
    
    return samples > 0 ? totalSmoothness / float(samples) : 0.0;
}

bool DetectPerfectAim(int client)
{
    if (g_ShotHistory[client] == null || g_ShotHistory[client].Length < 5) return false;
    
    int perfectFrames = 0;
    float perfectThreshold = 0.1;
    
    for (int i = 1; i < g_ShotHistory[client].Length; i++)
    {
        ShotData current, previous;
        g_ShotHistory[client].GetArray(i, current);
        g_ShotHistory[client].GetArray(i-1, previous);
        
        if (current.WasHit && previous.WasHit)
        {
            float angleChange = GetAngleDelta(previous.ShotAngles, current.ShotAngles);
            if (angleChange < perfectThreshold)
            {
                perfectFrames++;
            }
            else
            {
                perfectFrames = 0;
            }
        }
        
        if (perfectFrames >= 5)
        {
            g_iPerfectAimFrames[client] = perfectFrames;
            return true;
        }
    }
    
    g_iPerfectAimFrames[client] = perfectFrames;
    return false;
}

float CalculateAngularVelocity(const float ang1[3], const float ang2[3])
{
    float delta[3];
    for (int i = 0; i < 3; i++)
    {
        delta[i] = ang2[i] - ang1[i];
        while (delta[i] > 180.0) delta[i] -= 360.0;
        while (delta[i] < -180.0) delta[i] += 360.0;
    }
    return SquareRoot(delta[0]*delta[0] + delta[1]*delta[1] + delta[2]*delta[2]);
}

float CalculateHeadshotRatio(int client)
{
    if (g_iShotsHit[client] == 0) return 0.0;
    return fmin(1.0, float(g_iHeadshots[client]) / float(g_iShotsHit[client]));
}

float AnalyzeRecoilControl(int client)
{
    if (g_ShotHistory[client] == null || g_ShotHistory[client].Length < 5) return 0.0;
    
    int perfectShots = 0;
    int totalShots = g_ShotHistory[client].Length;
    
    for (int i = 1; i < totalShots; i++)
    {
        ShotData current, previous;
        g_ShotHistory[client].GetArray(i, current);
        g_ShotHistory[client].GetArray(i - 1, previous);
        
        float delta = GetAngleDelta(previous.ShotAngles, current.ShotAngles);
        if (delta < 0.5 && current.WasHit)
        {
            perfectShots++;
        }
    }
    
    return totalShots > 0 ? float(perfectShots) / float(totalShots) : 0.0;
}

bool DetectInhumanReactionTime(int client)
{
    if (g_ShotHistory[client] == null || g_ShotHistory[client].Length < 8) return false;
    
    int inhumanShots = 0;
    int totalShots = 0;
    
    for (int i = 1; i < g_ShotHistory[client].Length; i++)
    {
        ShotData current, previous;
        g_ShotHistory[client].GetArray(i, current);
        g_ShotHistory[client].GetArray(i-1, previous);
        
        if (current.WasHit && previous.WasHit && current.HitEntity > 0)
        {
            float timeBetween = current.ShotTime - previous.ShotTime;
            float distance = current.Distance;
            float minReactionTime = 0.05 + (distance / 5000.0);
            
            if (timeBetween < minReactionTime && distance > 300.0)
            {
                inhumanShots++;
            }
            totalShots++;
        }
    }
    
    return totalShots > 0 && (float(inhumanShots) / float(totalShots)) > 0.3;
}

bool DetectTraceCheat(int client)
{
    if (g_ShotHistory[client] == null) return false;
    
    int wallbangHits = 0;
    int totalHits = 0;
    
    for (int i = 0; i < g_ShotHistory[client].Length; i++)
    {
        ShotData data;
        g_ShotHistory[client].GetArray(i, data);
        
        if (data.WasHit && data.HitEntity > 0 && data.HitEntity <= MaxClients)
        {
            totalHits++;
            float endPos[3];
            GetClientEyePosition(data.HitEntity, endPos);
            
            Handle trace = TR_TraceRayFilterEx(data.EyePos, endPos, MASK_SHOT, RayType_EndPoint, TraceWallFilter, client);
            
            if (TR_DidHit(trace))
            {
                int hitEntity = TR_GetEntityIndex(trace);
                if (hitEntity != data.HitEntity)
                {
                    char classname[64];
                    GetEdictClassname(hitEntity, classname, sizeof(classname));
                    if (StrContains(classname, "player") == -1 && hitEntity != 0)
                    {
                        wallbangHits++;
                    }
                }
            }
            
            delete trace;
        }
    }
    return totalHits > 5 && (float(wallbangHits) / float(totalHits)) > 0.3;
}

bool DetectAimlock(int client)
{
    if (g_iConsecutiveHits[client] >= g_cvAimlock.IntValue)
    {
        if (g_ShotHistory[client] != null && g_ShotHistory[client].Length >= g_cvAimlock.IntValue)
        {
            int consecutivePerfect = 0;
            float lastAngleChange = 0.0;
            
            for (int i = g_ShotHistory[client].Length - g_iConsecutiveHits[client]; i < g_ShotHistory[client].Length - 1; i++)
            {
                if (i < 0) continue;
                
                ShotData current, next;
                g_ShotHistory[client].GetArray(i, current);
                g_ShotHistory[client].GetArray(i+1, next);
                
                // CHANGED: Accept any hit entity (bot or human)
                if (current.HitEntity <= 0) continue;
                
                float angleChange = GetVectorDistance(current.ShotAngles, next.ShotAngles);
                
                if (FloatAbs(angleChange - lastAngleChange) < 0.01 && lastAngleChange > 0.0)
                {
                    consecutivePerfect++;
                }
                
                lastAngleChange = angleChange;
            }
            
            return consecutivePerfect >= (g_cvAimlock.IntValue / 2);
        }
    }
    
    return false;
}

bool DetectSilentAim(int client)
{
    float accuracy = CalculateAccuracy(client);
    
    if (accuracy >= g_cvSilentAimPerf.FloatValue && g_iShotsFired[client] >= 10)
    {
        if (g_ShotHistory[client] != null && g_ShotHistory[client].Length >= 10)
        {
            float totalTimeDiff = 0.0;
            int samples = 0;
            
            for (int i = 1; i < g_ShotHistory[client].Length; i++)
            {
                ShotData current, previous;
                g_ShotHistory[client].GetArray(i, current);
                g_ShotHistory[client].GetArray(i-1, previous);

                if (current.WasHit && previous.WasHit && current.HitEntity > 0 && 
                    current.HitEntity <= MaxClients && IsClientInGame(current.HitEntity) &&
                    current.Distance > g_cvCloseRange.FloatValue)
                {
                    float timeDiff = current.ShotTime - previous.ShotTime;
                    totalTimeDiff += timeDiff;
                    samples++;
                }
            }
            
            if (samples >= 5)  
            {
                float avgTimeDiff = totalTimeDiff / samples;
                float variance = 0.0;
                
                for (int i = 1; i < g_ShotHistory[client].Length; i++)
                {
                    ShotData current, previous;
                    g_ShotHistory[client].GetArray(i, current);
                    g_ShotHistory[client].GetArray(i-1, previous);
            
                    if (current.WasHit && previous.WasHit && current.HitEntity > 0 && 
                        current.HitEntity <= MaxClients && IsClientInGame(current.HitEntity) &&
                        current.Distance > g_cvCloseRange.FloatValue)
                    {
                        float timeDiff = current.ShotTime - previous.ShotTime;
                        variance += FloatAbs(timeDiff - avgTimeDiff);
                    }
                }
                
                variance /= samples;
                return variance < 0.01;
            }
        }
    }
    
    return false;
}

bool DetectInhumanReaction(int client)
{
    if (g_ShotHistory[client] == null || g_ShotHistory[client].Length < 5) return false;
    
    int fastShots = 0;
    int totalShots = 0;
    
    for (int i = 1; i < g_ShotHistory[client].Length; i++)
    {
        ShotData current, previous;
        g_ShotHistory[client].GetArray(i, current);
        g_ShotHistory[client].GetArray(i-1, previous);
        
        // CHANGED: Accept any hit entity (bot or human)
        if (current.HitEntity <= 0) continue;
        
        float timeBetweenShots = current.ShotTime - previous.ShotTime;
        
        if (timeBetweenShots > 0.0 && timeBetweenShots < 0.05 && current.Distance > g_cvCloseRange.FloatValue)
        {
            fastShots++;
        }
        totalShots++;
    }
    
    if (totalShots > 0)
    {
        float fastRatio = float(fastShots) / float(totalShots);
        return fastRatio > g_cvTriggerbotPerf.FloatValue;
    }
    
    return false;
}

bool DetectNoScopeCheat(int client)
{
    if (g_ShotHistory[client] == null || g_ShotHistory[client].Length < 10) return false;
    
    int sniperShots = 0;
    int sniperHeadshots = 0;
    int unzoomedShots = 0;
    
    for (int i = 0; i < g_ShotHistory[client].Length; i++)
    {
        ShotData data;
        g_ShotHistory[client].GetArray(i, data);
        
        // CHANGED: Accept any hit entity (bot or human)
        if (data.HitEntity <= 0) continue;
        
        bool isSniper = false;
        for (int j = 0; j < sizeof(g_sScopedWeapons); j++)
        {
            if (StrEqual(data.Weapon, g_sScopedWeapons[j]))
            {
                isSniper = true;
                break;
            }
        }
        
        if (isSniper)
        {
            sniperShots++;
            if (!data.WasZoomed)
            {
                unzoomedShots++;
            }
            if (data.WasHeadshot && data.Distance > g_cvCloseRange.FloatValue)
            {
                sniperHeadshots++;
            }
        }
    }
    
    if (sniperShots >= 10)
    {
        float unzoomedRatio = float(unzoomedShots) / float(sniperShots);
        float headshotRatio = float(sniperHeadshots) / float(sniperShots);
        return unzoomedRatio > (g_cvNoScopePerf.FloatValue * 0.9) && headshotRatio > g_cvNoScopePerf.FloatValue;
    }
    
    return false;
}

int CalculateAimbotSuspicion(int client)
{
    float accuracy = CalculateAccuracy(client);
    float headshotRatio = CalculateHeadshotRatio(client);
    
    int suspicion = 0;
    
    bool highAccuracyWeapon = false;
    for (int i = 0; i < g_iWeaponCount[client]; i++)
    {
        if (g_iWeaponHits[client][i] > 0 && IsHighAccuracyWeapon(g_sWeaponNames[client][i]))
        {
            highAccuracyWeapon = true;
            break;
        }
    }

    float aimbotThreshold = highAccuracyWeapon ? g_cvShotgunAimbotPerf.FloatValue : g_cvAimbotPerf.FloatValue;
    float headshotThreshold = highAccuracyWeapon ? g_cvShotgunHeadshotPerf.FloatValue : 0.6;
    if (accuracy > aimbotThreshold)
    {
        float excess = (accuracy - aimbotThreshold) / (1.0 - aimbotThreshold);
        suspicion += RoundToFloor(excess * 50.0);
        
        if (g_cvDebug.BoolValue)
        {
            PrintToServer("[WeaponStats] Aimbot suspicion for %N (Accuracy: %.1f%%, Threshold: %.1f%%, Excess: %.1f%%)", 
                client, accuracy * 100, aimbotThreshold * 100, excess * 100);
        }
    }
    
    if (headshotRatio > headshotThreshold)
    {
        float excess = (headshotRatio - headshotThreshold) / (1.0 - headshotThreshold);
        suspicion += RoundToFloor(excess * 30.0);
    }
    
    int movingHeadshotKills = 0;
    if (g_ShotHistory[client] != null)
    {
        for (int i = 0; i < g_ShotHistory[client].Length; i++)
        {
            ShotData data;
            g_ShotHistory[client].GetArray(i, data);
            if (data.WasHeadshot && data.HitEntity > 0 && data.HitEntity <= MaxClients && IsClientInGame(data.HitEntity))
            {
                float vel[3];
                GetEntPropVector(data.HitEntity, Prop_Data, "m_vecVelocity", vel);
                if (GetVectorLength(vel) >= 10.0)
                {
                    movingHeadshotKills++;
                }
            }
        }
    }
    
    float movingHSRatio = g_iKills[client] > 0 ? float(movingHeadshotKills) / float(g_iKills[client]) : 0.0;
    
    if (g_iKills[client] >= 5 && movingHSRatio > (headshotThreshold * 0.8))
    {
        suspicion += 20;
    }
    
    if (g_iShotsHit[client] > g_iShotsFired[client])
    {
        suspicion += 50;
    }
    
    return RoundToFloor(fmin(100.0, float(suspicion)));
}

int CalculateRecoilSuspicion(int client)
{
    float recoilControl = AnalyzeRecoilControl(client);
    
    int suspicion = 0;
    
    if (recoilControl > g_cvRecoilPerf.FloatValue)
    {
        suspicion += 30;
    }
    if (recoilControl > (g_cvRecoilPerf.FloatValue * 1.1))
    {
        suspicion += 40;
    }
    
    return RoundToFloor(fmin(100.0, float(suspicion)));
}

int CalculateAimlockSuspicion(int client)
{
    int suspicion = 0;
    int aimlockThreshold = g_cvAimlock.IntValue;
    
    if (g_iConsecutiveHits[client] >= aimlockThreshold)
    {
        suspicion += 60;
    }
    if (g_iConsecutiveHits[client] >= RoundToCeil(aimlockThreshold * 0.7))
    {
        suspicion += 30;
    }
    
    return RoundToFloor(fmin(100.0, float(suspicion)));
}

int CalculateTriggerbotSuspicion(int client)
{
    if (g_ShotHistory[client] == null || g_ShotHistory[client].Length < 5) return 0;
    
    int fastShots = 0;
    int totalShots = 0;
    
    for (int i = 1; i < g_ShotHistory[client].Length; i++)
    {
        ShotData current, previous;
        g_ShotHistory[client].GetArray(i, current);
        g_ShotHistory[client].GetArray(i-1, previous);
        
        // Check if HitEntity is valid before calling IsFakeClient
        if (current.HitEntity <= 0 || current.HitEntity > MaxClients || !IsClientConnected(current.HitEntity) || IsFakeClient(current.HitEntity)) continue;
        
        float timeBetweenShots = current.ShotTime - previous.ShotTime;
        
        if (timeBetweenShots > 0.0 && timeBetweenShots < 0.05 && current.Distance > g_cvCloseRange.FloatValue)
        {
            fastShots++;
        }
        totalShots++;
    }
    
    if (totalShots > 0)
    {
        float fastRatio = float(fastShots) / float(totalShots);
        float triggerbotThreshold = g_cvTriggerbotPerf.FloatValue;
        
        if (fastRatio > triggerbotThreshold)
        {
            return 75;
        }
        if (fastRatio > (triggerbotThreshold * 0.8))
        {
            return 50;
        }
        if (fastRatio > (triggerbotThreshold * 0.6))
        {
            return 25;
        }
    }
    
    return 0;
}

public bool TraceWallFilter(int entity, int contentsMask, any data)
{
    return entity != data;
}

public Action Timer_UpdateAimHistory(Handle timer)
{
    for (int client = 1; client <= MaxClients; client++)
    {
        if (IsClientInGame(client) && IsPlayerAlive(client) && !IsFakeClient(client))
        {
            int index = g_iAimHistoryIndex[client] % 10;
            GetClientEyeAngles(client, g_vAimHistory[client][index]);
            g_iAimHistoryIndex[client]++;
        }
    }
    return Plugin_Continue;
}

int CalculateNoScopeSuspicion(int client)
{
    if (DetectNoScopeCheat(client))
    {
        return 80;
    }
    return 0;
}

void ReportSuspicion(int client, const char[] type, const char[] format, any ...)
{
    if (g_cvDebug.BoolValue)
    {
        char buffer[256];
        VFormat(buffer, sizeof(buffer), format, 4);
        
        PrintToServer("[WeaponStats] Suspicion for %N: %s - %s", client, type, buffer);
    }

    char sPath[PLATFORM_MAX_PATH];
    char sType[64];
    Format(sType, sizeof(sType), "%s.log", type);
    ReplaceString(sType, sizeof(sType), " ", "");
    StringToLower(sType);
    BuildPath(Path_SM, sPath, sizeof(sPath), "logs/WeaponStats/%s", sType);
    
    char sLog[512];
    char sTime[64];
    FormatTime(sTime, sizeof(sTime), "%d/%m/%Y - %H:%M:%S", GetTime());
    char sName[64];
    GetClientName(client, sName, sizeof(sName));
    char sAuth[32];
    GetClientAuthId(client, AuthId_Steam2, sAuth, sizeof(sAuth), true);
    VFormat(sLog, sizeof(sLog), format, 4);
    LogToFileEx(sPath, "[%s] %s [%s] - %s: %s", sTime, sName, sAuth, type, sLog);
}

bool CanBeObserved(int client)
{
    return IsClientInGame(client) && IsPlayerAlive(client) && (GetClientTeam(client) == CS_TEAM_T || GetClientTeam(client) == CS_TEAM_CT);
}

bool CheckObserverAdminAccess(int client)
{
    char flag[32];
    g_cvObserverAdminFlag.GetString(flag, sizeof(flag));
    
    if (strlen(flag) == 0)
    {
        return true;
    }
    
    return CheckCommandAccess(client, "sm_observeweaponstats", ReadFlagString(flag));
}

void GetHitgroupName(int hitgroup, char[] buffer, int maxlen)
{
    if (hitgroup >= 0 && hitgroup < sizeof(g_sHitgroupNames))
    {
        strcopy(buffer, maxlen, g_sHitgroupNames[hitgroup]);
    }
    else
    {
        strcopy(buffer, maxlen, "Unknown");
    }
}

void AutoSendStatsToAdmins(int client, const char[] reason, int suspicionLevel)
{
    char flags[32];
    g_cvAdminFlags.GetString(flags, sizeof(flags));
    
    char sPlayerName[64];
    GetClientName(client, sPlayerName, sizeof(sPlayerName));
    
    char sAuth[32];
    GetClientAuthId(client, AuthId_Steam2, sAuth, sizeof(sAuth), true);
    
    for (int i = 1; i <= MaxClients; i++)
    {
        if (i > 0 && i <= MaxClients && IsClientInGame(i) && !IsFakeClient(i) && 
            CheckCommandAccess(i, "sm_weaponstats_warning", ReadFlagString(flags)))
        {
            PrintToConsole(i, " ");
            PrintToConsole(i, "══════════════════════════════════════════════");
            PrintToConsole(i, "🚨 AUTOMATED CHEAT DETECTION ALERT");
            PrintToConsole(i, "══════════════════════════════════════════════");
            PrintToConsole(i, "Player: %s", sPlayerName);
            PrintToConsole(i, "SteamID: %s", sAuth);
            PrintToConsole(i, "Detection: %s", reason);
            PrintToConsole(i, "Suspicion Level: %d/10", suspicionLevel);
            PrintToConsole(i, "Time: %s", GetCurrentServerTime());
            PrintToConsole(i, "══════════════════════════════════════════════");
            PrintToConsole(i, " ");
            
            DisplayWeaponStats(i, client);
            
            CPrintToChat(i, "{fullred}🚨 %s has been detected for %s (Suspicion: %d/10)", sPlayerName, reason, suspicionLevel);
            CPrintToChat(i, "{fullred}Check your console for detailed statistics!");
        }
    }
}


void SaveCompleteStatsToLog(int client, const char[] reason, int suspicionLevel)
{
    char sPath[PLATFORM_MAX_PATH];
    char sDate[32];
    FormatTime(sDate, sizeof(sDate), "%Y-%m-%d");
    BuildPath(Path_SM, sPath, sizeof(sPath), "logs/WeaponStats/Detections_%s.log", sDate);
    
    char sTime[64];
    FormatTime(sTime, sizeof(sTime), "%m/%d/%Y - %H:%M:%S", GetTime());
    
    char sPlayerName[64];
    GetClientName(client, sPlayerName, sizeof(sPlayerName));
    
    char sAuth[32];
    GetClientAuthId(client, AuthId_Steam2, sAuth, sizeof(sAuth), true);
    
    char sMap[128];
    GetCurrentMap(sMap, sizeof(sMap));
    
    char sHostName[256];
    FindConVar("hostname").GetString(sHostName, sizeof(sHostName));
    
    char sServerIP[64];
    Format(sServerIP, sizeof(sServerIP), "%s", HostIP());
    
    // Start logging with better formatting
    LogToFileEx(sPath, " ");
    LogToFileEx(sPath, "══════════════════════════════════════════════════════════════════════════════");
    LogToFileEx(sPath, "                            CHEAT DETECTION ALERT");
    LogToFileEx(sPath, "══════════════════════════════════════════════════════════════════════════════");
    LogToFileEx(sPath, "Player: %s", sPlayerName);
    LogToFileEx(sPath, "SteamID: %s", sAuth);
    LogToFileEx(sPath, "Detection: %s", reason);
    LogToFileEx(sPath, "Suspicion Level: %d/10", suspicionLevel);
    LogToFileEx(sPath, "Server: %s", sHostName);
    LogToFileEx(sPath, "Map: %s", sMap);
    LogToFileEx(sPath, "IP:Port: %s", sServerIP);
    LogToFileEx(sPath, "Time: %s", sTime);
    LogToFileEx(sPath, "══════════════════════════════════════════════════════════════════════════════");
    LogToFileEx(sPath, " ");
    
    // Overall Statistics
    float accuracy = CalculateAccuracy(client);
    float headshotRatio = CalculateHeadshotRatio(client);
    
    LogToFileEx(sPath, "OVERALL STATISTICS:");
    LogToFileEx(sPath, "├─ Shots Fired: %d", g_iShotsFired[client]);
    LogToFileEx(sPath, "├─ Shots Hit: %d", g_iShotsHit[client]);
    LogToFileEx(sPath, "├─ Headshots: %d", g_iHeadshots[client]);
    LogToFileEx(sPath, "├─ Accuracy: %.1f%%", accuracy * 100);
    LogToFileEx(sPath, "├─ Consecutive Hits: %d", g_iConsecutiveHits[client]);
    LogToFileEx(sPath, "└─ Headshot Ratio: %.1f%%", headshotRatio * 100);
    LogToFileEx(sPath, " ");
    
    // Weapon Statistics
    LogToFileEx(sPath, "WEAPON STATISTICS:");
    bool hasWeaponData = false;
    for (int i = 0; i < g_iWeaponCount[client]; i++)
    {
        if (g_iWeaponShots[client][i] > 0)
        {
            hasWeaponData = true;
            float weaponAccuracy = g_iWeaponShots[client][i] > 0 ? 
                fmin(1.0, float(g_iWeaponHits[client][i]) / float(g_iWeaponShots[client][i])) : 0.0;
            float weaponHSRatio = g_iWeaponHits[client][i] > 0 ? 
                fmin(1.0, float(g_iWeaponHeadshots[client][i]) / float(g_iWeaponHits[client][i])) : 0.0;
            
            LogToFileEx(sPath, "├─ %s:", g_sWeaponNames[client][i]);
            LogToFileEx(sPath, "│  ├─ Shots: %d", g_iWeaponShots[client][i]);
            LogToFileEx(sPath, "│  ├─ Hits: %d", g_iWeaponHits[client][i]);
            LogToFileEx(sPath, "│  ├─ Headshots: %d", g_iWeaponHeadshots[client][i]);
            LogToFileEx(sPath, "│  ├─ Accuracy: %.1f%%", weaponAccuracy * 100);
            LogToFileEx(sPath, "│  └─ Headshot Ratio: %.1f%%", weaponHSRatio * 100);
        }
    }
    if (!hasWeaponData)
    {
        LogToFileEx(sPath, "└─ No weapon data available");
    }
    else
    {
        LogToFileEx(sPath, " ");
    }
    LogToFileEx(sPath, " ");
    
    // Hit Group Distribution
    LogToFileEx(sPath, "HIT GROUP DISTRIBUTION:");
    bool hasHitData = false;
    int totalHits = 0;
    
    // Calculate total hits first
    for (int i = 1; i < 8; i++)
    {
        totalHits += g_iHitGroupStats[client][i];
    }
    
    for (int i = 1; i < 8; i++)
    {
        if (g_iHitGroupStats[client][i] > 0)
        {
            hasHitData = true;
            float percentage = totalHits > 0 ? 
                (float(g_iHitGroupStats[client][i]) / float(totalHits)) * 100 : 0.0;
            
            if (i == 7) // Last item
                LogToFileEx(sPath, "└─ %s: %d (%.1f%%)", g_sHitgroupNames[i], g_iHitGroupStats[client][i], percentage);
            else
                LogToFileEx(sPath, "├─ %s: %d (%.1f%%)", g_sHitgroupNames[i], g_iHitGroupStats[client][i], percentage);
        }
    }
    if (!hasHitData)
    {
        LogToFileEx(sPath, "└─ No hit data available");
    }
    LogToFileEx(sPath, " ");
    
    // Kill Statistics
    LogToFileEx(sPath, "KILL STATISTICS:");
    float hsKillRatio = g_iKills[client] > 0 ? (float(g_iHeadshotKills[client]) / float(g_iKills[client])) * 100 : 0.0;
    
    LogToFileEx(sPath, "├─ Total Kills: %d", g_iKills[client]);
    LogToFileEx(sPath, "└─ Headshot Kills: %d (%.1f%%)", g_iHeadshotKills[client], hsKillRatio);
    LogToFileEx(sPath, " ");
    
    // Kill Hit Group Distribution
    LogToFileEx(sPath, "KILL HIT GROUP DISTRIBUTION:");
    bool hasKillHitData = false;
    int totalKillHits = 0;
    
    // Calculate total kill hits first
    for (int i = 1; i < 8; i++)
    {
        totalKillHits += g_iKillHitGroupStats[client][i];
    }
    
    for (int i = 1; i < 8; i++)
    {
        if (g_iKillHitGroupStats[client][i] > 0)
        {
            hasKillHitData = true;
            float percentage = totalKillHits > 0 ? 
                (float(g_iKillHitGroupStats[client][i]) / float(totalKillHits)) * 100 : 0.0;
            
            if (i == 7) // Last item
                LogToFileEx(sPath, "└─ %s: %d (%.1f%%)", g_sHitgroupNames[i], g_iKillHitGroupStats[client][i], percentage);
            else
                LogToFileEx(sPath, "├─ %s: %d (%.1f%%)", g_sHitgroupNames[i], g_iKillHitGroupStats[client][i], percentage);
        }
    }
    if (!hasKillHitData)
    {
        LogToFileEx(sPath, "└─ No kill hit group data available");
    }
    LogToFileEx(sPath, " ");
    
    // Suspicion Analysis
    LogToFileEx(sPath, "SUSPICION ANALYSIS:");
    LogToFileEx(sPath, "├─ Aimbot: %d%%", CalculateAimbotSuspicion(client));
    LogToFileEx(sPath, "├─ Recoil Control: %d%%", CalculateRecoilSuspicion(client));
    LogToFileEx(sPath, "├─ Aimlock: %d%%", CalculateAimlockSuspicion(client));
    LogToFileEx(sPath, "├─ Triggerbot: %d%%", CalculateTriggerbotSuspicion(client));
    LogToFileEx(sPath, "└─ No-Scope: %d%%", CalculateNoScopeSuspicion(client));
    LogToFileEx(sPath, " ");
    
    // Current Detection Thresholds
    LogToFileEx(sPath, "DETECTION THRESHOLDS (Current Settings):");
    LogToFileEx(sPath, "├─ Aimbot: %.2f", g_cvAimbotPerf.FloatValue);
    LogToFileEx(sPath, "├─ Silent Aim: %.2f", g_cvSilentAimPerf.FloatValue);
    LogToFileEx(sPath, "├─ Shotgun Aimbot: %.2f", g_cvShotgunAimbotPerf.FloatValue);
    LogToFileEx(sPath, "├─ Shotgun Headshot: %.2f", g_cvShotgunHeadshotPerf.FloatValue);
    LogToFileEx(sPath, "├─ Recoil Control: %.2f", g_cvRecoilPerf.FloatValue);
    LogToFileEx(sPath, "├─ Triggerbot: %.2f", g_cvTriggerbotPerf.FloatValue);
    LogToFileEx(sPath, "├─ No-Scope: %.2f", g_cvNoScopePerf.FloatValue);
    LogToFileEx(sPath, "├─ Aimlock: %d", g_cvAimlock.IntValue);
    LogToFileEx(sPath, "├─ Silent Aim Angle: %.1f", g_cvSilentAimAngle.FloatValue);
    LogToFileEx(sPath, "└─ Close Range: %.1f", g_cvCloseRange.FloatValue);
    LogToFileEx(sPath, " ");
    
    LogToFileEx(sPath, "══════════════════════════════════════════════════════════════════════════════");
    LogToFileEx(sPath, " ");
    LogToFileEx(sPath, " ");
}

public void Discord_Notify(int client, const char[] reason, int suspicionLevel)
{
    char sPluginVersion[256];
    GetPluginInfo(GetMyHandle(), PlInfo_Version, sPluginVersion, sizeof(sPluginVersion));
    char sPluginAuthor[256];
    GetPluginInfo(GetMyHandle(), PlInfo_Author, sPluginAuthor, sizeof(sPluginAuthor));
    char sPluginName[256];
    GetPluginInfo(GetMyHandle(), PlInfo_Name, sPluginName, sizeof(sPluginName));

    char sAuth[32];
    GetClientAuthId(client, AuthId_Steam2, sAuth, sizeof(sAuth), true);

    char sPlayerName[64];
    GetClientName(client, sPlayerName, sizeof(sPlayerName));

    // Header with better spacing
    char sHeader[256];
    Format(sHeader, sizeof(sHeader),
        "**🔍 CHEAT DETECTION | %s**\n" ...
        "**Player:** *%s*  |  **SteamID:** *%s*\n" ...
        "**Detection:** *%s*  |  **Suspicion:** *%d/10*",
        sPlayerName, sPlayerName, sAuth, reason, suspicionLevel
    );

    // Overall Statistics with tabs
    float accuracy = CalculateAccuracy(client);
    float headshotRatio = CalculateHeadshotRatio(client);
    char sOverallStats[256];
    Format(sOverallStats, sizeof(sOverallStats), 
        "**Overall Stats**\n" ...
        "> **Shots:** *%d*  |  **Hits:** *%d*  |  **HS:** *%d*\n" ...
        "> **Accuracy:** *%.1f%%*  |  **HS Ratio:** *%.1f%%*  |  **Consecutive:** *%d*",
        g_iShotsFired[client], g_iShotsHit[client], g_iHeadshots[client],
        accuracy * 100, headshotRatio * 100, g_iConsecutiveHits[client]
    );

    // Weapon Statistics with better formatting
    char sWeaponStats[1024] = "**Weapon Stats**\n";
    bool hasWeaponData = false;
    int weaponCount = 0;
    
    for (int i = 0; i < g_iWeaponCount[client] && weaponCount < 6; i++) // Limit to 6 weapons
    {
        if (g_iWeaponShots[client][i] > 0)
        {
            hasWeaponData = true;
            weaponCount++;
            
            float weaponAccuracy = g_iWeaponShots[client][i] > 0 ? 
                fmin(1.0, float(g_iWeaponHits[client][i]) / float(g_iWeaponShots[client][i])) : 0.0;
            float weaponHSRatio = g_iWeaponHits[client][i] > 0 ? 
                fmin(1.0, float(g_iWeaponHeadshots[client][i]) / float(g_iWeaponHits[client][i])) : 0.0;
            
            char sWeaponLine[128];
            Format(sWeaponLine, sizeof(sWeaponLine), 
                "> **%s:** *%d/%d/%d • %.0f%%/%.0f%%*%s",
                g_sWeaponNames[client][i],
                g_iWeaponShots[client][i],
                g_iWeaponHits[client][i],
                g_iWeaponHeadshots[client][i],
                weaponAccuracy * 100,
                weaponHSRatio * 100,
                (weaponCount < g_iWeaponCount[client] && weaponCount < 6) ? "\n" : ""
            );
            
            if (strlen(sWeaponStats) + strlen(sWeaponLine) < sizeof(sWeaponStats) - 50)
            {
                StrCat(sWeaponStats, sizeof(sWeaponStats), sWeaponLine);
            }
        }
    }
    
    if (!hasWeaponData)
    {
        StrCat(sWeaponStats, sizeof(sWeaponStats), "> *No weapon data*");
    }
    else if (g_iWeaponCount[client] > 6)
    {
        char sMoreWeapons[64];
        Format(sMoreWeapons, sizeof(sMoreWeapons), "\n> *... and %d more*", g_iWeaponCount[client] - 6);
        StrCat(sWeaponStats, sizeof(sWeaponStats), sMoreWeapons);
    }
    // Hit Group Distribution with better spacing
    char sHitGroupStats[512] = "**Hit Group Distribution**\n";
    bool hasHitData = false;
    int hitGroupCount = 0;
    
    for (int i = 1; i < 8 && hitGroupCount < 8; i++)
    {
        if (g_iHitGroupStats[client][i] > 0)
        {
            hasHitData = true;
            hitGroupCount++;
            float percentage = g_iShotsHit[client] > 0 ? 
                (float(g_iHitGroupStats[client][i]) / float(g_iShotsHit[client])) * 100 : 0.0;
            
            char sHitLine[64];
            Format(sHitLine, sizeof(sHitLine), 
                "> **%s:** *%d (%.0f%%)*%s", 
                g_sHitgroupNames[i], 
                g_iHitGroupStats[client][i], 
                percentage,
                (i < 7 && hitGroupCount < 8) ? "  |  " : ""
            );
            
            if (strlen(sHitGroupStats) + strlen(sHitLine) < sizeof(sHitGroupStats) - 30)
            {
                StrCat(sHitGroupStats, sizeof(sHitGroupStats), sHitLine);
            }
        }
    }
    
    if (!hasHitData)
    {
        StrCat(sHitGroupStats, sizeof(sHitGroupStats), "> *No hit data*");
    }

    // Kill Statistics with better formatting
    char sKillStats[256];
    float hsKillRatio = g_iKills[client] > 0 ? (float(g_iHeadshotKills[client]) / float(g_iKills[client])) * 100 : 0.0;
    
    Format(sKillStats, sizeof(sKillStats),
        "**Kill Stats**\n" ...
        "> **Total:** *%d*  |  **HS Kills:** *%d*  |  **HS Rate:** *%.0f%%*",
        g_iKills[client], g_iHeadshotKills[client], hsKillRatio
    );

    // Suspicion Analysis with better spacing
    int aimbotSuspicion = CalculateAimbotSuspicion(client);
    int recoilSuspicion = CalculateRecoilSuspicion(client);
    int aimlockSuspicion = CalculateAimlockSuspicion(client);
    int triggerbotSuspicion = CalculateTriggerbotSuspicion(client);
    int noScopeSuspicion = CalculateNoScopeSuspicion(client);
    
    char sSuspicionAnalysis[512];
    Format(sSuspicionAnalysis, sizeof(sSuspicionAnalysis),
        "**Suspicion Analysis**\n" ...
        "> **Aimbot:** *%d%%*  |  **Recoil:** *%d%%*  |  **Aimlock:** *%d%%*\n" ...
        "> **Trigger:** *%d%%*  |  **NoScope:** *%d%%*",
        aimbotSuspicion, recoilSuspicion, aimlockSuspicion, triggerbotSuspicion, noScopeSuspicion
    );

    // Server Info with better formatting
    char sTime[32];
    FormatTime(sTime, sizeof(sTime), "%m/%d @ %H:%M", GetTime());

    char sCount[32];
    int iMaxPlayers = MaxClients;
    int iConnected = 0;
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i) && !IsFakeClient(i))
            iConnected++;
    }
    Format(sCount, sizeof(sCount), "%d/%d", iConnected, iMaxPlayers);

    char sCurrentMap[32];
    GetCurrentMap(sCurrentMap, sizeof(sCurrentMap));
    if (StrContains(sCurrentMap, "/") != -1)
    {
        char mapParts[2][32];
        ExplodeString(sCurrentMap, "/", mapParts, 2, 32);
        strcopy(sCurrentMap, sizeof(sCurrentMap), mapParts[1]);
    }

    char sHostName[64];
    FindConVar("hostname").GetString(sHostName, sizeof(sHostName));
    if (strlen(sHostName) > 40)
    {
        sHostName[40] = '\0';
        StrCat(sHostName, sizeof(sHostName), "...");
    }

    char sServerIP[32];
    Format(sServerIP, sizeof(sServerIP), "%s", HostIP());

    // Plugin Information
    char sPluginInfo[512];
    Format(sPluginInfo, sizeof(sPluginInfo),
        "**Plugin Information**\n" ...
        "> **Name:** *%s*  |  **Version:** *%s*  |  **Author:** *%s*",
        sPluginName, sPluginVersion, sPluginAuthor
    );

    // Server Information
    char sServerInfo[512];
    Format(sServerInfo, sizeof(sServerInfo),
        "**Server Information**\n" ...
        "> **Server:** *%s*  |  **Map:** *%s*  |  **Time:** *%s*\n" ...
        "> **Players:** *%s*  |  **IP:** *%s*",
        sHostName, sCurrentMap, sTime, sCount, sServerIP
    );

    // Build the final message with better spacing
    char sMessage[4096];
    Format(sMessage, sizeof(sMessage),
        "%s\n\n" ...
        "%s\n\n" ...
        "%s\n\n" ...
        "%s\n\n" ...
        "%s\n\n" ...
        "%s\n\n" ...
        "%s\n\n" ...
        "%s",
        sHeader,
        sOverallStats,
        sWeaponStats,
        sHitGroupStats,
        sKillStats,
        sSuspicionAnalysis,
        sPluginInfo,
        sServerInfo
    );
    
    // Clean up formatting
    ReplaceString(sMessage, sizeof(sMessage), "\\n", "\n");
    
    char szWebhookURL[1000];
    g_cvWebhook.GetString(szWebhookURL, sizeof(szWebhookURL));

    if (strlen(szWebhookURL) > 0)
    {
        if (strlen(sMessage) >= 2000)
        {
            // Truncate weapon stats first
            int truncatePoint = 1900;
            while (truncatePoint > 0 && sMessage[truncatePoint] != '\n')
            {
                truncatePoint--;
            }
            
            if (truncatePoint > 0)
            {
                sMessage[truncatePoint] = '\0';
                StrCat(sMessage, sizeof(sMessage), "\n> *... (message truncated)*");
            }
        }
        
        Webhook webhook = new Webhook(sMessage);
        webhook.Execute(szWebhookURL, OnWebHookExecuted);
        delete webhook;
    }

    AutoSendStatsToAdmins(client, reason, suspicionLevel);
    SaveCompleteStatsToLog(client, reason, suspicionLevel);
}

public void OnWebHookExecuted(HTTPResponse response, DataPack pack)
{
    if (response.Status != HTTPStatus_OK)
    {
        if (g_cvDebug.BoolValue)
        {
            PrintToServer("[WeaponStats] Failed to send Discord webhook");
        }
    }
}

void StringToLower(char[] str)
{
    for (int i = 0; str[i] != '\0'; i++)
    {
        str[i] = CharToLower(str[i]);
    }
}

public any Native_IsSilentAimDetected(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    if (client < 1 || client > MaxClients || !IsClientInGame(client))
    {
        ThrowNativeError(SP_ERROR_PARAM, "Invalid client index %d", client);
    }
    return g_bSilentAimDetected[client];
}

public any Native_IsAimbotDetected(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    if (client < 1 || client > MaxClients || !IsClientInGame(client))
    {
        ThrowNativeError(SP_ERROR_PARAM, "Invalid client index %d", client);
    }
    return g_bAimbotDetected[client];
}

public any Native_IsRecoilDetected(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    if (client < 1 || client > MaxClients || !IsClientInGame(client))
    {
        ThrowNativeError(SP_ERROR_PARAM, "Invalid client index %d", client);
    }
    return g_bRecoilDetected[client];
}

public any Native_IsAimlockDetected(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    if (client < 1 || client > MaxClients || !IsClientInGame(client))
    {
        ThrowNativeError(SP_ERROR_PARAM, "Invalid client index %d", client);
    }
    return g_bAimlockDetected[client];
}

public any Native_IsTriggerbotDetected(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    if (client < 1 || client > MaxClients || !IsClientInGame(client))
    {
        ThrowNativeError(SP_ERROR_PARAM, "Invalid client index %d", client);
    }
    return g_bTriggerbotDetected[client];
}

public any Native_IsNoScopeDetected(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    if (client < 1 || client > MaxClients || !IsClientInGame(client))
    {
        ThrowNativeError(SP_ERROR_PARAM, "Invalid client index %d", client);
    }
    return g_bNoScopeDetected[client];
}

public any Native_GetSuspicionLevel(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    if (client < 1 || client > MaxClients || !IsClientInGame(client))
    {
        ThrowNativeError(SP_ERROR_PARAM, "Invalid client index %d", client);
    }
    return g_iSuspicionLevel[client];
}

public any Native_GetShotsFired(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    if (client < 1 || client > MaxClients || !IsClientInGame(client))
    {
        ThrowNativeError(SP_ERROR_PARAM, "Invalid client index %d", client);
    }
    return g_iShotsFired[client];
}

public any Native_GetShotsHit(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    if (client < 1 || client > MaxClients || !IsClientInGame(client))
    {
        ThrowNativeError(SP_ERROR_PARAM, "Invalid client index %d", client);
    }
    return g_iShotsHit[client];
}

public any Native_GetHeadshots(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    if (client < 1 || client > MaxClients || !IsClientInGame(client))
    {
        ThrowNativeError(SP_ERROR_PARAM, "Invalid client index %d", client);
    }
    return g_iHeadshots[client];
}

public any Native_GetAccuracy(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    if (client < 1 || client > MaxClients || !IsClientInGame(client))
    {
        ThrowNativeError(SP_ERROR_PARAM, "Invalid client index %d", client);
    }
    return CalculateAccuracy(client);
}

public any Native_GetHeadshotRatio(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    if (client < 1 || client > MaxClients || !IsClientInGame(client))
    {
        ThrowNativeError(SP_ERROR_PARAM, "Invalid client index %d", client);
    }
    return CalculateHeadshotRatio(client);
}

public any Native_GetKills(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    if (client < 1 || client > MaxClients || !IsClientInGame(client))
    {
        ThrowNativeError(SP_ERROR_PARAM, "Invalid client index %d", client);
    }
    return g_iKills[client];
}

public any Native_GetHeadshotKills(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    if (client < 1 || client > MaxClients || !IsClientInGame(client))
    {
        ThrowNativeError(SP_ERROR_PARAM, "Invalid client index %d", client);
    }
    return g_iHeadshotKills[client];
}

public any Native_GetWeaponCount(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    if (client < 1 || client > MaxClients || !IsClientInGame(client))
    {
        ThrowNativeError(SP_ERROR_PARAM, "Invalid client index %d", client);
    }
    return g_iWeaponCount[client];
}

public any Native_GetWeaponName(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    int index = GetNativeCell(2);
    if (client < 1 || client > MaxClients || !IsClientInGame(client))
    {
        ThrowNativeError(SP_ERROR_PARAM, "Invalid client index %d", client);
    }
    if (index < 0 || index >= g_iWeaponCount[client])
    {
        ThrowNativeError(SP_ERROR_PARAM, "Invalid weapon index %d", index);
    }
    char weaponName[64];
    strcopy(weaponName, sizeof(weaponName), g_sWeaponNames[client][index]);
    SetNativeString(3, weaponName, GetNativeCell(4));
    return true;
}

public any Native_GetWeaponShots(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    int index = GetNativeCell(2);
    if (client < 1 || client > MaxClients || !IsClientInGame(client))
    {
        ThrowNativeError(SP_ERROR_PARAM, "Invalid client index %d", client);
    }
    if (index < 0 || index >= g_iWeaponCount[client])
    {
        return -1;
    }
    return g_iWeaponShots[client][index];
}

public any Native_GetWeaponHits(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    int index = GetNativeCell(2);
    if (client < 1 || client > MaxClients || !IsClientInGame(client))
    {
        ThrowNativeError(SP_ERROR_PARAM, "Invalid client index %d", client);
    }
    if (index < 0 || index >= g_iWeaponCount[client])
    {
        return -1;
    }
    return g_iWeaponHits[client][index];
}

public any Native_GetWeaponHeadshots(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    int index = GetNativeCell(2);
    if (client < 1 || client > MaxClients || !IsClientInGame(client))
    {
        ThrowNativeError(SP_ERROR_PARAM, "Invalid client index %d", client);
    }
    if (index < 0 || index >= g_iWeaponCount[client])
    {
        return -1;
    }
    return g_iWeaponHeadshots[client][index];
}

int GetCumulativeDamage(int observer, int victim)
{
    char damageKey[32];
    Format(damageKey, sizeof(damageKey), "total_damage_%d_%d", observer, victim);
    
    int totalDamage = 0;
    GetTrieValue(g_hDamageTrie, damageKey, totalDamage);
    return totalDamage;
}

void UpdateCumulativeDamage(int observer, int victim, int damage)
{
    char damageKey[32];
    Format(damageKey, sizeof(damageKey), "total_damage_%d_%d", observer, victim);
    
    int currentDamage = 0;
    GetTrieValue(g_hDamageTrie, damageKey, currentDamage);
    currentDamage += damage;
    SetTrieValue(g_hDamageTrie, damageKey, currentDamage);
}

void CreateServerImpactEffect(int observer, int victim, int hitgroup)
{
    if (!IsClientInGame(observer) || !IsClientInGame(victim)) return;
    
    float victimPos[3];
    GetClientAbsOrigin(victim, victimPos);
    
    // Adjust position based on hitgroup
    switch(hitgroup)
    {
        case 1: victimPos[2] += 72.0;
        case 2: victimPos[2] += 54.0;
        case 3: victimPos[2] += 36.0;
        case 4, 5: victimPos[2] += 48.0;
        case 6, 7: victimPos[2] += 24.0;
        default: victimPos[2] += 48.0;
    }
    
    int color[4];
    
    // Color based on hitgroup
    switch(hitgroup)
    {
        case 1: { color[0] = 255; color[1] = 0; color[2] = 0; color[3] = 255; } // Red - Head
        case 2: { color[0] = 255; color[1] = 255; color[2] = 0; color[3] = 255; } // Yellow - Chest
        case 3: { color[0] = 255; color[1] = 100; color[2] = 0; color[3] = 255; } // Orange - Stomach
        case 4, 5: { color[0] = 0; color[1] = 255; color[2] = 0; color[3] = 255; } // Green - Arms
        case 6, 7: { color[0] = 0; color[1] = 0; color[2] = 255; color[3] = 255; } // Blue - Legs
        default: { color[0] = 255; color[1] = 255; color[2] = 255; color[3] = 255; } // White - Generic
    }

    TE_SetupGlowSprite(victimPos, PrecacheModel("sprites/blueglow1.vmt"), 1.0, 0.5, 255);
    TE_SendToClient(observer);
    
    // 2. Impact ring
    TE_SetupBeamRingPoint(victimPos, 2.0, 15.0, PrecacheModel("sprites/laser.vmt"), 0, 0, 0, 0.3, 5.0, 0.0, color, 10, 0);
    TE_SendToClient(observer);
    CreateImpactCrosshair(observer, victimPos, color);
}

void CreateImpactCrosshair(int observer, float pos[3], int color[4])
{
    float crossSize = 8.0;
    
    // Horizontal line
    float hStart[3], hEnd[3];
    hStart[0] = pos[0] - crossSize; hStart[1] = pos[1]; hStart[2] = pos[2];
    hEnd[0] = pos[0] + crossSize; hEnd[1] = pos[1]; hEnd[2] = pos[2];
    TE_SetupBeamPoints(hStart, hEnd, PrecacheModel("sprites/laser.vmt"), 0, 0, 0, 0.2, 2.0, 2.0, 0, 0.0, color, 3);
    TE_SendToClient(observer);
    
    // Vertical line
    float vStart[3], vEnd[3];
    vStart[0] = pos[0]; vStart[1] = pos[1] - crossSize; vStart[2] = pos[2];
    vEnd[0] = pos[0]; vEnd[1] = pos[1] + crossSize; vEnd[2] = pos[2];
    TE_SetupBeamPoints(vStart, vEnd, PrecacheModel("sprites/laser.vmt"), 0, 0, 0, 0.2, 2.0, 2.0, 0, 0.0, color, 3);
    TE_SendToClient(observer);
}

/* Changlog
 * Version 1.00 - Initial Plugin written.
 * Version 1.1 - Added Logic for aimbots, aimlock, recoil control, triggerbots.
 * Version 1.2 - Improved Logging and Admin Notification system.
 * Version 1.3 - Added No-Scope cheat detection.
 * Version 1.4 - Added Discord Webhook Notifications.
 * Version 1.5 - Improved Discord Message Formatting.
 * Version 1.6 - Enhanced Cheat Detection Algorithms.
 * Version 1.7 - Added Bot Compatibility in Detection Logic.
 * Version 1.8 - Optimized Performance and Reduced False Positives.

        New ConVars Added (inspired by SMAC and KigenAC thresholds):
        - sm_weaponstats_aimsnap_angle "30.0": Threshold for detecting large angle changes (snaps) that result in perfect hits. Lower values catch more subtle cheats but risk false positives.
        - sm_weaponstats_aimsnap_detections "3": Number of suspicious snaps needed before flagging as aimbot. This requires multiple confirmations to avoid flagging legit quick turns.
        - sm_weaponstats_max_aimvelocity "1000.0": Max allowed aim turn speed (degrees per second). Exceeding this flags high-velocity aimbot turns (from SMAC's velocity checks).
        - These are hooked into OnConfigsExecuted and UpdateThresholdsFromConVars for dynamic updates and debugging.
        
        New Player Tracking:
        - Added g_iAimSnapDetections[MAXPLAYERS+1] to count per-player snap detections (resets in ResetPlayerData).
        
        
        New Timer for Eye Angle Checks (from KigenAC's eyetest.sp and LILAC):
        - In OnPluginStart, created Timer_CheckEyeAngles (runs every 1 second, repeating).
        - This checks all players' eye angles: If pitch > 89.0 or roll != 0.0, it reports "InvalidEyeAngles" and adds +5 suspicion. This catches many aimbots that set impossible angles (common in cheats).

        Enhanced Detection in Event_PlayerHurt (core integration from SMAC aimbot.sp):
        - After updating shot history, if there are at least 2 shots:
        - Calculate angle delta between previous and current shot angles (using new GetAngleDelta function, which ignores roll and normalizes differences).
        - Calculate time diff between shots.
        - Compute aim velocity (delta / timeDiff); if > max_aimvelocity, report "AimVelocity" and add +3 suspicion (prevents instant 180-degree snaps).
        - Calculate aim offset (using new GetAimAngleDiff): If delta > aimsnap_angle, aim offset < 0.5 (near-perfect hit), victim is moving (>=10 speed), and distance > close range, increment snap detections.
        - If snap detections >= threshold, report "AimSnap" and add +5 suspicion.
        - This logic mirrors SMAC's snap detection: Large angle change + perfect hit on moving target at distance = suspicious. It reduces false positives by requiring movement, distance, and multiple detections.
        
        New Helper Functions:
        - GetAngleDelta: Computes normalized pitch/yaw difference (ignores roll, handles 360-degree wraps).
        - GetAimAngleDiff: Computes the angular offset between shot angles and actual hit position (dot product + arccos).
        
        Other Minor Updates:
        - Updated debug prints and convar change hooks to include new vars.
        - No changes to stat tracking, commands, or notifications—focus was on detection logic only.

 * Version 1.9 - Added Native Support and Optimized Detection.
        - Added `weaponstats.inc` include file for native support, enabling other plugins to query detection statuses and suspicion levels.
        - Introduced new global natives for external plugins:
        - `WS_IsSilentAimDetected`: Checks if silent aim was detected for a client.
        - `WS_IsAimbotDetected`: Checks if aimbot was detected based on high accuracy thresholds.
        - `WS_IsRecoilDetected`: Checks if no-recoil cheat was detected.
        - `WS_IsAimlockDetected`: Checks if aimlock was detected.
        - `WS_IsTriggerbotDetected`: Checks if triggerbot was detected.
        - `WS_IsNoScopeDetected`: Checks if no-scope cheat was detected.
        - `WS_GetSuspicionLevel`: Returns the client's overall suspicion level (0-10).
        - Added new boolean arrays (`g_bSilentAimDetected`, `g_bAimbotDetected`, `g_bRecoilDetected`, `g_bAimlockDetected`, `g_bTriggerbotDetected`, `g_bNoScopeDetected`) to track detection states per player, reset in `ResetPlayerData`.
        - Registered natives in `OnPluginStart` using `CreateNative` for each native function.
        - Implemented native handlers (`Native_IsSilentAimDetected`, etc.) to validate client indices and return detection statuses or suspicion levels.
        - Updated `PerformDetectionChecks` to set detection bools (`g_bAimbotDetected`, etc.) when corresponding cheats are detected, ensuring accurate native responses.
        - Optimized detection logic by maintaining existing aimlock detection (`DetectAimlock`) without changes, as it effectively catches consecutive perfect angle snaps.
        - Reduced false positives by leveraging existing conditions (e.g., movement, distance, multiple snap detections) from version 1.7, ensuring compatibility with new native-based queries.
        - No changes to core detection algorithms or stat tracking; focus was on adding native support for interoperability with other plugins.

 * Version 1.10 - Enhanced Native Support for Detailed Stats
        - Updated `weaponstats.inc` to include new natives for accessing detailed player statistics, removing limitations on stat access:
        - `WS_GetShotsFired`: Returns total shots fired by the client.
        - `WS_GetShotsHit`: Returns total shots hit by the client.
        - `WS_GetHeadshots`: Returns total headshots by the client.
        - `WS_GetAccuracy`: Returns the client's accuracy (hits/shots).
        - `WS_GetHeadshotRatio`: Returns the client's headshot ratio (headshots/hits).
        - `WS_GetKills`: Returns total kills by the client.
        - `WS_GetHeadshotKills`: Returns total headshot kills by the client.
        - `WS_GetWeaponCount`: Returns the number of weapons tracked for the client.
        - `WS_GetWeaponName`: Retrieves the name of a weapon at a specific index.
        - `WS_GetWeaponShots`: Returns shots fired for a specific weapon.
        - `WS_GetWeaponHits`: Returns shots hit for a specific weapon.
        - `WS_GetWeaponHeadshots`: Returns headshots for a specific weapon.
        - Added native handlers for the new natives in `weaponstats.sp`, registered in `OnPluginStart`.
        - Updated the test plugin (`test_weaponstats.sp`) to version 1.1, now using the new natives to display detailed stats (shots, hits, headshots, accuracy, kills, and weapon-specific stats) in the console, eliminating the need to rely on `sm_wstats`.
        - Maintained existing detection logic and performance optimizations from version 1.8.
        - No changes to core detection algorithms or logging; focus was on enhancing API accessibility for other plugins.

 * Version 1.11 - Added Bullet Tracers
        - Added bullet tracers for silent aim and aimbot detections.
        - Added Advanced Hitbox Visualization.
        - Added Transparency system.
        - Fixed bunch of stuffs.

 * Version 1.12 - Fixed:
        - weaponstats.sp::CalculateAimSmoothness ([SM] Exception reported: Array index out-of-bounds (index 10, limit 10))
        - weaponstats.sp::PerformDetectionChecks ([SM] Exception reported: Array index out-of-bounds (index 10, limit 10))
        - weaponstats.sp::Event_PlayerHurt ([SM] Exception reported: Array index out-of-bounds (index 10, limit 10))
*/