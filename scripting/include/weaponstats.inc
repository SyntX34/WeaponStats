#if defined _weaponstats_included
 #endinput
#endif
#define _weaponstats_included

/**
 * Checks if silent aim has been detected for the client.
 *
 * @param client        Client index.
 * @return              True if detected, false otherwise.
 */
native bool WS_IsSilentAimDetected(int client);

/**
 * Checks if aimbot has been detected for the client (based on high accuracy thresholds).
 *
 * @param client        Client index.
 * @return              True if detected, false otherwise.
 */
native bool WS_IsAimbotDetected(int client);

/**
 * Checks if no-recoil cheat has been detected for the client.
 *
 * @param client        Client index.
 * @return              True if detected, false otherwise.
 */
native bool WS_IsRecoilDetected(int client);

/**
 * Checks if aimlock has been detected for the client.
 *
 * @param client        Client index.
 * @return              True if detected, false otherwise.
 */
native bool WS_IsAimlockDetected(int client);

/**
 * Checks if triggerbot has been detected for the client.
 *
 * @param client        Client index.
 * @return              True if detected, false otherwise.
 */
native bool WS_IsTriggerbotDetected(int client);

/**
 * Checks if no-scope cheat has been detected for the client.
 *
 * @param client        Client index.
 * @return              True if detected, false otherwise.
 */
native bool WS_IsNoScopeDetected(int client);

/**
 * Gets the overall suspicion level for the client (0-10).
 *
 * @param client        Client index.
 * @return              Suspicion level (0-10).
 */
native int WS_GetSuspicionLevel(int client);

/**
 * Gets the total shots fired by the client.
 *
 * @param client        Client index.
 * @return              Total shots fired.
 */
native int WS_GetShotsFired(int client);

/**
 * Gets the total shots hit by the client.
 *
 * @param client        Client index.
 * @return              Total shots hit.
 */
native int WS_GetShotsHit(int client);

/**
 * Gets the total headshots by the client.
 *
 * @param client        Client index.
 * @return              Total headshots.
 */
native int WS_GetHeadshots(int client);

/**
 * Gets the client's accuracy (hits/shots).
 *
 * @param client        Client index.
 * @return              Accuracy as a float (0.0 to 1.0).
 */
native float WS_GetAccuracy(int client);

/**
 * Gets the client's headshot ratio (headshots/hits).
 *
 * @param client        Client index.
 * @return              Headshot ratio as a float (0.0 to 1.0).
 */
native float WS_GetHeadshotRatio(int client);

/**
 * Gets the total kills by the client.
 *
 * @param client        Client index.
 * @return              Total kills.
 */
native int WS_GetKills(int client);

/**
 * Gets the total headshot kills by the client.
 *
 * @param client        Client index.
 * @return              Total headshot kills.
 */
native int WS_GetHeadshotKills(int client);

/**
 * Gets the number of weapons tracked for the client.
 *
 * @param client        Client index.
 * @return              Number of weapons tracked.
 */
native int WS_GetWeaponCount(int client);

/**
 * Gets the name of a weapon at the specified index for the client.
 *
 * @param client        Client index.
 * @param index         Weapon index (0 to WS_GetWeaponCount-1).
 * @param weaponName    Buffer to store the weapon name.
 * @param maxlen        Maximum length of the buffer.
 * @return              True if the weapon index is valid, false otherwise.
 */
native bool WS_GetWeaponName(int client, int index, char[] weaponName, int maxlen);

/**
 * Gets the shots fired for a specific weapon.
 *
 * @param client        Client index.
 * @param index         Weapon index (0 to WS_GetWeaponCount-1).
 * @return              Shots fired for the weapon, or -1 if invalid index.
 */
native int WS_GetWeaponShots(int client, int index);

/**
 * Gets the shots hit for a specific weapon.
 *
 * @param client        Client index.
 * @param index         Weapon index (0 to WS_GetWeaponCount-1).
 * @return              Shots hit for the weapon, or -1 if invalid index.
 */
native int WS_GetWeaponHits(int client, int index);

/**
 * Gets the headshots for a specific weapon.
 *
 * @param client        Client index.
 * @param index         Weapon index (0 to WS_GetWeaponCount-1).
 * @return              Headshots for the weapon, or -1 if invalid index.
 */
native int WS_GetWeaponHeadshots(int client, int index);