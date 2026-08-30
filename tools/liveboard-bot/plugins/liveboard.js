import { EmbedBuilder } from 'discord.js';
import fs from 'fs';
import { spawn } from 'child_process';
import { getPalRestSnapshot } from './palRest.js';

let liveboardMessageId = null;
let updateInFlight = false;
let cachedChannel = null;

export function initLiveboard(client, options = {}) {
    const channelId = options.channelId || process.env.DISCORD_LIVEBOARD_CHANNEL_ID || process.env.DISCORD_CHANNEL_ID;
    const statePath = options.statePath || process.env.LIVEBOARD_STATE_PATH || 'Pal/Saved/liveboard_state.json';
    const configuredInterval = Number.parseInt(process.env.POLL_INTERVAL_MS || '', 10);
    const intervalMs = options.intervalMs || (Number.isFinite(configuredInterval) && configuredInterval >= 5000 ? configuredInterval : 15000);
    const connectAddress = options.connectAddress || process.env.SERVER_CONNECT_ADDRESS || 'play.palodyssey.com:8211';
    const launcherReleaseUrl = options.launcherReleaseUrl || process.env.LAUNCHER_RELEASE_URL || 'https://github.com/beoul-create/PalOdyssey-Launcher/releases/latest';
    const launcherVersion = options.launcherVersion || process.env.LAUNCHER_VERSION || 'v2.0.1';

    if (!channelId) {
        console.warn('[Liveboard Plugin] DISCORD_LIVEBOARD_CHANNEL_ID not set. Skipping liveboard.');
        return;
    }

    async function update() {
        if (updateInFlight) return;
        updateInFlight = true;
        try {
            let state = {
                ServerOnline: false,
                PlayerCount: 0,
                MaxPlayers: 32,
                Players: [],
                ActiveBosses: []
            };

            if (fs.existsSync(statePath)) {
                const rawData = await fs.promises.readFile(statePath, 'utf-8');
                state = { ...state, ...JSON.parse(rawData) };
            }

            // Palworld's authenticated REST endpoint is authoritative for
            // connected users. Lua's state file remains authoritative for
            // world-boss data, which the REST API does not expose.
            const palSnapshot = await getPalRestSnapshot();
            if (palSnapshot.reachable) {
                state.ServerOnline = true;
                state.Players = palSnapshot.players;
                state.PlayerCount = palSnapshot.players.length;
                if (palSnapshot.serverName) state.ServerName = palSnapshot.serverName;
            }

            if (!palSnapshot.reachable) {
                try {
                    const isRunning = await new Promise(resolve => {
                        const child = spawn('tasklist', ['/FI', 'IMAGENAME eq PalServer*'], {
                            windowsHide: true,
                            stdio: ['ignore', 'pipe', 'ignore']
                        });
                        let out = '';
                        child.stdout?.on('data', chunk => { out += chunk; });
                        child.on('close', () => resolve(out.includes('PalServer')));
                        child.on('error', () => resolve(false));
                    });
                    if (isRunning) {
                        state.ServerOnline = true;
                    } else {
                        state.ServerOnline = false;
                        state.Players = [];
                        state.PlayerCount = 0;
                    }
                } catch {
                    state.ServerOnline = false;
                }
            }

            const channel = cachedChannel || await client.channels.fetch(channelId);
            if (!channel) return;
            cachedChannel = channel;

            const playerCount = state.PlayerCount ?? (state.Players ? state.Players.length : 0);
            const maxPlayers = state.MaxPlayers || 32;

            let playerEntries = state.Players && state.Players.length > 0
                ? state.Players.map(p => `• [Lv. ${p.Level || '?'}] ${p.Name || 'Unknown'} (Guild: ${p.GuildName || 'None'})`).join('\n')
                : 'No players online.';
            if (playerEntries.length > 1000) playerEntries = `${playerEntries.slice(0, 997)}...`;

            const bossEntries = state.ActiveBosses && state.ActiveBosses.length > 0
                ? state.ActiveBosses.map(b => {
                    const posX = b.Coords ? Math.round(b.Coords.X) : 0;
                    const posY = b.Coords ? Math.round(b.Coords.Y) : 0;
                    return `>>> **[3x Raid Boss] ${b.PalId} (${b.Aura || 'Fiery'} Aura)**\n📍 **Location:** ${b.LocationName || 'Wilderness'} (\`X: ${posX}, Y: ${posY}\`)\n❤️ **Health:** \`100x HP Pool\` | ⏱️ **Spawned:** <t:${b.SpawnTime}:R>`;
                }).join('\n\n')
                : 'No active raid bosses in Palpagos.';

            const embed = new EmbedBuilder()
                .setTitle('⚔️ PALWORLD ODYSSEY — SERVER LIVEBOARD')
                .setDescription('Live metrics and active world raid boss instances on the dedicated server.\n*Auto-updated every 15 seconds.*')
                .setColor(state.ServerOnline ? 0x00E5FF : 0xFF0055)
                .addFields(
                    { name: '🖥️ Server State', value: `\`\`\`yaml\nStatus: ${state.ServerOnline ? 'ONLINE' : 'OFFLINE'}\nPlayers: ${playerCount}/${maxPlayers}\n\`\`\``, inline: true },
                    { name: `👥 Online Players (${playerCount}/${maxPlayers})`, value: `\`\`\`css\n${playerEntries}\n\`\`\``, inline: true },
                    { name: '⚔️ Active World Boss Spawns', value: bossEntries, inline: false },
                    { name: '🔗 Quick Connect', value: `\`${connectAddress}\``, inline: true },
                    { name: '📥 Launcher Update', value: `[Download ${launcherVersion}](${launcherReleaseUrl})\nExisting launchers require a manual update.`, inline: true }
                )
                .setFooter({ text: 'PalOdyssey Live Engine • Last Polled' })
                .setTimestamp();

            if (!liveboardMessageId) {
                const messages = await channel.messages.fetch({ limit: 5 });
                const existing = messages.find(m => m.author.id === client.user.id);
                if (existing) {
                    liveboardMessageId = existing.id;
                    await existing.edit({ embeds: [embed] });
                    console.log(`[Liveboard Plugin] Updated existing message ${existing.id} in channel ${channelId}.`);
                } else {
                    const sent = await channel.send({ embeds: [embed] });
                    liveboardMessageId = sent.id;
                    console.log(`[Liveboard Plugin] Posted message ${sent.id} in channel ${channelId}.`);
                }
            } else {
                const targetMsg = await channel.messages.fetch(liveboardMessageId);
                await targetMsg.edit({ embeds: [embed] });
            }
        } catch (err) {
            console.error('[Liveboard Plugin] Update error:', err.message);
        } finally {
            updateInFlight = false;
        }
    }

    update();
    setInterval(update, intervalMs);

    // Reactive watcher on liveboard_state.json for instant join/leave updates
    try {
        const watchTarget = statePath;
        fs.watchFile(watchTarget, { interval: 1000 }, (curr, prev) => {
            if (curr.mtimeMs !== prev.mtimeMs) {
                console.log('[Liveboard Plugin] Reactive state change detected -> Updating Discord embed.');
                update();
            }
        });
    } catch (e) {
        console.warn('[Liveboard Plugin] Reactive watcher failed:', e.message);
    }

    console.log('[Liveboard Plugin] Initialized with reactive join/leave updater.');
}
