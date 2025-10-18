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