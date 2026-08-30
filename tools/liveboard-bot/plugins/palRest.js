import fs from 'fs';

const defaultSettingsPath = 'C:/SteamLibrary/steamapps/common/PalServer/Pal/Saved/Config/WindowsServer/PalWorldSettings.ini';
const defaultBaseUrl = 'http://127.0.0.1:8212/v1/api';
const idleTimeoutMs = 15 * 60 * 1000;

let cachedSnapshot = null;
let cachedAt = 0;
let requestInFlight = null;

function getAdminPassword() {
    if (process.env.PAL_REST_PASSWORD) return process.env.PAL_REST_PASSWORD;

    const settingsPath = process.env.PAL_SETTINGS_PATH || defaultSettingsPath;
    const raw = fs.readFileSync(settingsPath, 'utf8');
    const match = raw.match(/AdminPassword="([^"]*)"/);
    if (!match || !match[1]) {
        throw new Error(`AdminPassword was not found in ${settingsPath}`);
    }
    return match[1];
}

function firstValue(source, keys, fallback = undefined) {
    for (const key of keys) {
        if (source && source[key] !== undefined && source[key] !== null) return source[key];
    }
    return fallback;
}

function normalizePlayer(player) {
    const name = String(firstValue(player, ['name', 'Name', 'playerName', 'PlayerName'], 'Unknown'));
    const levelValue = Number(firstValue(player, ['level', 'Level'], 1));
    const guildName = String(firstValue(player, ['guildName', 'GuildName', 'guild_name'], 'None'));
    return {
        Name: name || 'Unknown',
        Level: Number.isFinite(levelValue) && levelValue > 0 ? levelValue : 1,
        GuildName: guildName || 'None'
    };
}

async function requestJson(path, options = {}) {
    const baseUrl = (process.env.PAL_REST_BASE_URL || defaultBaseUrl).replace(/\/$/, '');
    const password = getAdminPassword();
    const auth = Buffer.from(`admin:${password}`, 'utf8').toString('base64');
    const response = await fetch(`${baseUrl}${path}`, {
        ...options,
        headers: {
            Authorization: `Basic ${auth}`,
            Accept: 'application/json',
            ...(options.body ? { 'Content-Type': 'application/json' } : {}),
            ...(options.headers || {})
        },
        signal: AbortSignal.timeout(5000)
    });
    if (!response.ok) throw new Error(`Pal REST ${path} returned HTTP ${response.status}`);
    const text = await response.text();
    return text ? JSON.parse(text) : {};
}

export async function getPalRestSnapshot({ maxCacheAgeMs = 2000 } = {}) {
    const now = Date.now();
    if (cachedSnapshot && now - cachedAt <= maxCacheAgeMs) return cachedSnapshot;
    if (requestInFlight) return requestInFlight;

    requestInFlight = (async () => {
        try {
            const [info, playersPayload] = await Promise.all([
                requestJson('/info'),
                requestJson('/players')
            ]);
            const rawPlayers = Array.isArray(playersPayload)
                ? playersPayload
                : (Array.isArray(playersPayload.players) ? playersPayload.players : []);
            cachedSnapshot = {
                reachable: true,
                online: true,
                serverName: firstValue(info, ['servername', 'serverName', 'ServerName'], undefined),
                version: firstValue(info, ['version', 'Version'], undefined),
                players: rawPlayers.map(normalizePlayer)
            };
        } catch (error) {
            cachedSnapshot = {
                reachable: false,
                online: false,
                players: [],
                error: error instanceof Error ? error.message : String(error)
            };
        } finally {
            cachedAt = Date.now();
            requestInFlight = null;
        }
        return cachedSnapshot;
    })();

    return requestInFlight;
}

export async function requestPalShutdown(waittime = 5, message = '15 minutes of inactivity') {
    cachedAt = 0;
    return requestJson('/shutdown', {
        method: 'POST',
        body: JSON.stringify({ waittime, message })
    });
}

export function initInactivityWatchdog(options = {}) {
    const configuredSeconds = Number.parseInt(process.env.IDLE_SHUTDOWN_SECONDS || '', 10);
    const timeoutMs = Number.isFinite(configuredSeconds) && configuredSeconds >= 60
        ? configuredSeconds * 1000
        : (options.timeoutMs || idleTimeoutMs);
    const intervalMs = options.intervalMs || 15000;
    let emptySince = null;
    let lastMilestone = 0;
    let shutdownRequested = false;

    async function tick() {
        const snapshot = await getPalRestSnapshot({ maxCacheAgeMs: 0 });
        if (!snapshot.reachable) {
            emptySince = null;
            lastMilestone = 0;
            shutdownRequested = false;
            return;
        }

        if (snapshot.players.length > 0) {
            if (emptySince !== null) console.log('[AutoShutdown] Connected player detected. Idle timer reset.');
            emptySince = null;
            lastMilestone = 0;
            shutdownRequested = false;
            return;
        }

        if (emptySince === null) emptySince = Date.now();
        const idleMs = Date.now() - emptySince;
        const milestone = Math.floor(idleMs / (3 * 60 * 1000));
        if (milestone > lastMilestone) {
            lastMilestone = milestone;
            console.log(`[AutoShutdown] Server empty. Idle: ${Math.floor(idleMs / 1000)}s / ${Math.floor(timeoutMs / 1000)}s.`);
        }

        if (!shutdownRequested && idleMs >= timeoutMs) {
            shutdownRequested = true;
            console.log('[AutoShutdown] Inactivity threshold reached. Requesting Palworld graceful shutdown.');
            try {
                await requestPalShutdown(5, 'PalOdyssey: 15 minutes with no connected players');
                console.log('[AutoShutdown] Palworld accepted the graceful shutdown request.');
            } catch (error) {
                shutdownRequested = false;
                console.error('[AutoShutdown] Shutdown request failed:', error instanceof Error ? error.message : String(error));
            }
        }
    }

    console.log(`[AutoShutdown] REST-backed inactivity watchdog armed (${Math.floor(timeoutMs / 1000)} seconds).`);
    void tick();
    return setInterval(() => void tick(), intervalMs);
}
