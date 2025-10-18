#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <cstrike>
#include <multicolors>
#include <discordWebhookAPI>
#include <weaponstats>

#define PLUGIN_VERSION "1.8"
#define MAX_TRACKED_SHOTS 1000
#define SAMPLE_SIZE 50
#define MAX_WEAPONS 32
#define FLOAT_EPSILON 0.001

public Plugin myinfo = 
{
    name = "Advanced Aimbot Detection & Weapon Stats (CS:S)",
    author = "+SyntX34",
    description = "Detects aimbot usage and tracks detailed weapon statistics for CS:Source",
    version = PLUGIN_VERSION,
    url = ""
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

float g_fLastShotTime[MAXPLAYERS+1];
float g_fLastHitTime[MAXPLAYERS+1];
float g_fLastNotifyTime[MAXPLAYERS+1];
float g_vLastAngles[MAXPLAYERS+1][3];
float g_vHitPositions[MAXPLAYERS+1][SAMPLE_SIZE][3];
int g_iHitPositionIndex[MAXPLAYERS+1];
bool g_bIsZoomed[MAXPLAYERS+1];
bool g_bIsTracking[MAXPLAYERS+1];
bool g_bPendingMelee[MAXPLAYERS+1];
int g_iHitGroupStats[MAXPLAYERS+1][8];
char g_sWeaponNames[MAXPLAYERS+1][MAX_WEAPONS][64];
int g_iWeaponShots[MAXPLAYERS+1][MAX_WEAPONS];
int g_iWeaponHits[MAXPLAYERS+1][MAX_WEAPONS];
int g_iWeaponHeadshots[MAXPLAYERS+1][MAX_WEAPONS];
int g_iWeaponCount[MAXPLAYERS+1];

bool g_bSilentAimDetected[MAXPLAYERS+1];
bool g_bAimbotDetected[MAXPLAYERS+1];
bool g_bRecoilDetected[MAXPLAYERS+1];
bool g_bAimlockDetected[MAXPLAYERS+1];
bool g_bTriggerbotDetected[MAXPLAYERS+1];
bool g_bNoScopeDetected[MAXPLAYERS+1];

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

ArrayList g_ShotHistory[MAXPLAYERS+1];

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
    "g3sg1"
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
    RegPluginLibrary("WeaponStats");
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
    
    g_cvEnabled = CreateConVar("sm_weaponstats_enable", "1", "Enable/Disable the aimbot detection plugin", FCVAR_NONE, true, 0.0, true, 1.0);
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

    AutoExecConfig(true);
    
    RegConsoleCmd("sm_wstats", Command_WeaponStats, "Show weapon statistics for a player");
    RegConsoleCmd("sm_weaponstats", Command_WeaponStats, "Show weapon statistics for a player");
    RegConsoleCmd("sm_wresetstats", Command_ResetStats, "Reset weapon statistics for a player");
    RegConsoleCmd("sm_resetweaponstats", Command_ResetStats, "Reset weapon statistics for a player");
    
    HookEvent("weapon_fire", Event_WeaponFire);
    HookEvent("player_hurt", Event_PlayerHurt);
    HookEvent("player_death", Event_PlayerDeath);
    HookEvent("bullet_impact", Event_BulletImpact);
    HookEvent("weapon_zoom", Event_WeaponZoom);
    
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

    CreateTimer(1.0, Timer_CheckEyeAngles, _, TIMER_REPEAT);

    CreateNative("WS_IsSilentAimDetected", Native_IsSilentAimDetected);
    CreateNative("WS_IsAimbotDetected", Native_IsAimbotDetected);
    CreateNative("WS_IsRecoilDetected", Native_IsRecoilDetected);
    CreateNative("WS_IsAimlockDetected", Native_IsAimlockDetected);
    CreateNative("WS_IsTriggerbotDetected", Native_IsTriggerbotDetected);
    CreateNative("WS_IsNoScopeDetected", Native_IsNoScopeDetected);
    CreateNative("WS_GetSuspicionLevel", Native_GetSuspicionLevel);
}

public void OnConfigsExecuted()
{
    // Hook ConVar changes
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
    
    // Update initial thresholds from ConVars
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
    }
}

public void OnClientPutInServer(int client)
{
    if (IsFakeClient(client)) return;
    
    ResetPlayerData(client);
    
    g_ShotHistory[client] = new ArrayList(sizeof(ShotData));
    g_bIsTracking[client] = true;
}

public void OnClientDisconnect(int client)
{
    if (g_ShotHistory[client] != null)
    {
        delete g_ShotHistory[client];
    }
    
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
    
    // CHANGED: Only check if ATTACKER is a bot, victim can be anything
    if (attacker <= 0 || attacker > MaxClients || !IsClientInGame(attacker) || IsFakeClient(attacker) || 
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
    
    // CHANGED: Track consecutive hits even against bots
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
    
    // CHANGED: Silent aim detection now works against bots too
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
    
    // Add aim snap and velocity checks from SMAC/LILAC/KigenAC logic
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
    
    // CHANGED: Run detection checks regardless of victim being bot
    PerformDetectionChecks(attacker);
    
    if (g_cvDebug.BoolValue)
    {
        PrintToServer("[WeaponStats] %N hit %N with %s (Hitgroup: %d, Headshot: %s, Total Hits: %d, Distance: %.1f)", 
            attacker, victim, weapon, hitgroup, isHeadshot ? "Yes" : "No", g_iShotsHit[attacker], distance);
    }
}

public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
    if (!g_cvEnabled.BoolValue) return;
    
    int attacker = GetClientOfUserId(event.GetInt("attacker"));
    int victim = GetClientOfUserId(event.GetInt("userid"));
    
    // CHANGED: Only check if ATTACKER is a bot, victim can be anything
    if (attacker <= 0 || attacker > MaxClients || !IsClientInGame(attacker) || IsFakeClient(attacker) || 
        victim <= 0 || victim > MaxClients || !IsClientInGame(victim) || attacker == victim) return;
    if (!g_bIsTracking[attacker]) return;
    
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
    
    if (g_cvDebug.BoolValue)
    {
        PrintToServer("[WeaponStats] %N killed %N (Hitgroup: %d, Headshot: %s, Total Kills: %d)", 
            attacker, victim, hitgroup, isHeadshot ? "Yes" : "No", g_iKills[attacker]);
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

public void Event_BulletImpact(Event event, const char[] name, bool dontBroadcast)
{
    if (!g_cvEnabled.BoolValue) return;
    
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (client <= 0 || client > MaxClients || !IsClientInGame(client) || IsFakeClient(client) || !g_bIsTracking[client]) return;
    
    float startPos[3], endPos[3];
    GetClientEyePosition(client, startPos);
    endPos[0] = event.GetFloat("x");
    endPos[1] = event.GetFloat("y");
    endPos[2] = event.GetFloat("z");
    
    Handle trace = TR_TraceRayFilterEx(startPos, endPos, MASK_SHOT, RayType_EndPoint, Filter_Self, client);
    
    bool isMiss = true;
    if (TR_DidHit(trace))
    {
        int hitEntity = TR_GetEntityIndex(trace);
        // CHANGED: Accept hits on bots too
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
    
    if (g_cvDebug.BoolValue)
    {
        PrintToServer("[WeaponStats] Bullet impact by %N at (%.1f, %.1f, %.1f), Miss: %s", 
            client, endPos[0], endPos[1], endPos[2], isMiss ? "Yes" : "No");
    }
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

float GetAngleDelta(const float ang1[3], const float ang2[3])
{
    float diff[3];
    for (int i = 0; i < 2; i++) // Ignore roll
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
    
    if (g_iShotsHit[client] > g_iShotsFired[client])
    {
        ReportSuspicion(client, "StatAnomaly", "Stat anomaly detected (Hits: %d, Shots: %d)", g_iShotsHit[client], g_iShotsFired[client]);
        g_iSuspicionLevel[client] += 5;
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
    
    float aimbotThreshold = highAccuracyWeapon ? g_cvShotgunAimbotPerf.FloatValue : g_cvAimbotPerf.FloatValue;
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

    if (g_iConsecutiveHits[client] >= 5)
    {
        ReportSuspicion(client, "ConsecutiveHits", "High consecutive hits: %d", g_iConsecutiveHits[client]);
        g_iSuspicionLevel[client] += 2;
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

float CalculateHeadshotRatio(int client)
{
    if (g_iShotsHit[client] == 0) return 0.0;
    return fmin(1.0, float(g_iHeadshots[client]) / float(g_iShotsHit[client]));
}

float AnalyzeRecoilControl(int client)
{
    if (g_ShotHistory[client] == null || g_ShotHistory[client].Length < 10) return 0.0;
    
    int validSamples = 0;
    int perfectControl = 0;
    
    for (int i = 1; i < g_ShotHistory[client].Length; i++)
    {
        ShotData current, previous;
        g_ShotHistory[client].GetArray(i, current);
        g_ShotHistory[client].GetArray(i-1, previous);
        
        if (current.ShotTime - previous.ShotTime < 0.5 && current.HitEntity > 0)
        {
            validSamples++;
            
            float angleDiff = GetVectorDistance(current.ShotAngles, previous.ShotAngles);
            
            if (angleDiff < 0.5)
            {
                perfectControl++;
            }
        }
    }
    
    if (validSamples == 0) return 0.0;
    return fmin(1.0, float(perfectControl) / float(validSamples));
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

 * Version 1.8 - Added Native Support and Optimized Detection.
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
*/