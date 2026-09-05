import { PermissionFlagsBits, SlashCommandBuilder } from 'discord.js';

const command = new SlashCommandBuilder()
    .setName('server')
    .setDescription('Manage the PalOdyssey server')
    .setDMPermission(false)
    .addSubcommand(subcommand =>
        subcommand.setName('status').setDescription('Show the current server status'))
    .addSubcommand(subcommand =>
        subcommand.setName('start').setDescription('Start the PalOdyssey server'))
    .addSubcommand(subcommand =>
        subcommand.setName('stop').setDescription('Stop the PalOdyssey server'));

function getApiConfiguration() {
    const port = process.env.HTTP_PORT || '3001';
    return {
        baseUrl: process.env.SERVER_API_URL || `http://127.0.0.1:${port}`,
        adminKey: process.env.REMOTE_ADMIN_KEY || 'DefaultSecretKey'
    };
}

async function requestServerApi(action) {
    const { baseUrl, adminKey } = getApiConfiguration();
    const isStatus = action === 'status';
    const response = await fetch(`${baseUrl.replace(/\/$/, '')}/api/server/${action}`, {
        method: isStatus ? 'GET' : 'POST',
        headers: isStatus ? {} : { Authorization: `Bearer ${adminKey}` }
    });

    const body = await response.json().catch(() => ({}));
    if (!response.ok) {
        throw new Error(body.message || body.error || `Server API returned HTTP ${response.status}`);
    }

    return body;
}

export function canRunServerAction(action, memberPermissions) {
    if (action === 'start') return true;
    return Boolean(memberPermissions?.has(PermissionFlagsBits.ManageGuild));
}

export async function initCommands(client, options = {}) {
    const commandChannelId = options.channelId || process.env.DISCORD_COMMAND_CHANNEL_ID;

    try {
        for (const guild of client.guilds.cache.values()) {
            await guild.commands.set([command.toJSON()]);
            console.log(`[Commands Plugin] Set guild command for ${guild.name} (${guild.id}).`);
        }

        await client.application.commands.set([command.toJSON()]);
        console.log('[Commands Plugin] Registered /server slash commands successfully.');
    } catch (err) {
        console.error('[Commands Plugin] Registration error:', err.message);
        return;
    }

    client.on('interactionCreate', async interaction => {
        if (!interaction.isChatInputCommand() || interaction.commandName !== 'server') return;

        // Immediately acknowledge the interaction to beat Discord's 3-second timeout window
        try {
            await interaction.deferReply({ ephemeral: true });
        } catch (deferErr) {
            console.error('[Commands Plugin] Defer error:', deferErr.message);
            return;
        }

        if (commandChannelId && interaction.channelId !== commandChannelId) {
            await interaction.editReply(`Use this command in <#${commandChannelId}>.`);
            return;
        }

        const action = interaction.options.getSubcommand();

        if (!canRunServerAction(action, interaction.memberPermissions)) {
            await interaction.editReply('You need Manage Server permission to use this command.');
            return;
        }

        try {
            const result = await requestServerApi(action);
            if (action === 'status') {
                const state = result.serverOnline ? 'online' : 'offline';
                const processState = result.isProcessRunning ? 'running' : 'stopped';
                await interaction.editReply(
                    `Server is **${state}** (${result.playerCount}/${result.maxPlayers} players); process is **${processState}**.`
                );
                return;
            }

            await interaction.editReply(result.message || `Server ${action} request completed.`);
        } catch (err) {
            console.error(`[Commands Plugin] /server ${action} error:`, err.message);
            await interaction.editReply(`Command failed: ${err.message}`);
        }
    });
}
