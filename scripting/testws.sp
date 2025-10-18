#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <multicolors>
#include <weaponstats>

public Plugin myinfo = 
{
    name = "WeaponStats Test Plugin",
    author = "+SyntX34",
    description = "Tests the WeaponStats plugin natives and API",
    version = "1.0",
    url = "https://github.com/SyntX34 && https://steamcommunity.com/id/SyntX34"
};

public void OnPluginStart()
{
    RegConsoleCmd("sm_testws", Command_TestWeaponStats, "Test WeaponStats natives and display player stats");
}

public Action Command_TestWeaponStats(int client, int args)
{
    if (client <= 0 || !IsClientInGame(client))
    {
        ReplyToCommand(client, "[TestWS] This command must be run by a valid client.");
        return Plugin_Handled;
    }

    int target = client;
    char arg[64];
    
    if (args >= 1)
    {
        GetCmdArg(1, arg, sizeof(arg));
        target = FindTarget(client, arg, true, false);
        
        if (target == -1 || !IsClientInGame(target))
        {
            CReplyToCommand(client, "{fullred}[TestWS] {default}Invalid target or target not found: %s", arg);
            return Plugin_Handled;
        }
    }
    char pluginName[128], pluginAuthor[64], pluginVersion[32];
    Handle weaponStatsPlugin = FindPluginByFile("weaponstats.smx");
    if (weaponStatsPlugin == null)
    {
        CReplyToCommand(client, "{fullred}[TestWS] {default}WeaponStats plugin not found!");
        return Plugin_Handled;
    }
    
    GetPluginInfo(weaponStatsPlugin, PlInfo_Name, pluginName, sizeof(pluginName));
    GetPluginInfo(weaponStatsPlugin, PlInfo_Author, pluginAuthor, sizeof(pluginAuthor));
    GetPluginInfo(weaponStatsPlugin, PlInfo_Version, pluginVersion, sizeof(pluginVersion));
    PrintToConsole(client, " ");
    PrintToConsole(client, "══════════════════════════════════════════════");
    PrintToConsole(client, "WeaponStats Test for %N", target);
    PrintToConsole(client, "══════════════════════════════════════════════");
    PrintToConsole(client, "Plugin Info:");
    PrintToConsole(client, "  Name: %s", pluginName);
    PrintToConsole(client, "  Author: %s", pluginAuthor);
    PrintToConsole(client, "  Version: %s", pluginVersion);
    PrintToConsole(client, " ");
    PrintToConsole(client, "Detection Statuses:");
    PrintToConsole(client, "  IsClientAimbotDetected: %s", WS_IsAimbotDetected(target) ? "True" : "False");
    PrintToConsole(client, "  IsClientSilentAimDetected: %s", WS_IsSilentAimDetected(target) ? "True" : "False");
    PrintToConsole(client, "  IsClientRecoilDetected: %s", WS_IsRecoilDetected(target) ? "True" : "False");
    PrintToConsole(client, "  IsClientAimlockDetected: %s", WS_IsAimlockDetected(target) ? "True" : "False");
    PrintToConsole(client, "  IsClientTriggerbotDetected: %s", WS_IsTriggerbotDetected(target) ? "True" : "False");
    PrintToConsole(client, "  IsClientNoScopeDetected: %s", WS_IsNoScopeDetected(target) ? "True" : "False");
    PrintToConsole(client, "  Overall Suspicion Level: %d/10", WS_GetSuspicionLevel(target));
    PrintToConsole(client, " ");
    PrintToConsole(client, "Overall Statistics:");
    PrintToConsole(client, "  Shots Fired: %d", WS_GetShotsFired(target));
    PrintToConsole(client, "  Shots Hit: %d", WS_GetShotsHit(target));
    PrintToConsole(client, "  Headshots: %d", WS_GetHeadshots(target));
    PrintToConsole(client, "  Accuracy: %.1f%%", WS_GetAccuracy(target) * 100.0);
    PrintToConsole(client, "  Headshot Ratio: %.1f%%", WS_GetHeadshotRatio(target) * 100.0);
    PrintToConsole(client, "  Total Kills: %d", WS_GetKills(target));
    PrintToConsole(client, "  Headshot Kills: %d", WS_GetHeadshotKills(target));
    PrintToConsole(client, " ");
    int weaponCount = WS_GetWeaponCount(target);
    PrintToConsole(client, "Weapon Statistics:");
    if (weaponCount == 0)
    {
        PrintToConsole(client, "  No weapon data available");
    }
    else
    {
        for (int i = 0; i < weaponCount; i++)
        {
            char weaponName[64];
            if (WS_GetWeaponName(target, i, weaponName, sizeof(weaponName)))
            {
                int shots = WS_GetWeaponShots(target, i);
                int hits = WS_GetWeaponHits(target, i);
                int headshots = WS_GetWeaponHeadshots(target, i);
                float weaponAccuracy = shots > 0 ? float(hits) / float(shots) * 100.0 : 0.0;
                float weaponHSRatio = hits > 0 ? float(headshots) / float(hits) * 100.0 : 0.0;
                
                PrintToConsole(client, "  Weapon: %s", weaponName);
                PrintToConsole(client, "    Shots: %d | Hits: %d | Headshots: %d", shots, hits, headshots);
                PrintToConsole(client, "    Accuracy: %.1f%% | Headshot Ratio: %.1f%%", weaponAccuracy, weaponHSRatio);
            }
        }
    }
    PrintToConsole(client, " ");
    PrintToConsole(client, "══════════════════════════════════════════════");
    CReplyToCommand(client, "{green}[TestWS] {default}WeaponStats test results printed to console for %N", target);

    return Plugin_Handled;
}