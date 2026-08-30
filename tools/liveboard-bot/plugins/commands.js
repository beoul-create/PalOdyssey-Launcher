import { PermissionFlagsBits, SlashCommandBuilder } from 'discord.js';

const command = new SlashCommandBuilder()
    .setName('server')
    .setDescription('Manage the PalOdyssey server')
    .setDefaultMemberPermissions(PermissionFlagsBits.ManageGuild)
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

export async function initCommands(client, options = {}) {
    const commandChannelId = options.channelId || process.env.DISCORD_COMMAND_CHANNEL_ID;
    if (!commandChannelId) {
        console.warn('[Commands Plugin] DISCORD_COMMAND_CHANNEL_ID not set. Skipping commands.');
        return;
    }

    try {
        for (const guild of client.guilds.cache.values()) {
            await guild.commands.set([]);
            console.log(`[Commands Plugin] Cleared guild commands for ${guild.name} (${guild.id}).`);
        }

        await client.application.commands.set([command.toJSON()]);
        console.log('[Commands Plugin] Replaced global commands with /server successfully.');
    } catch (err) {
        console.error('[Commands Plugin] Registration error:', err.message);
        return;
    }

    client.on('interactionCreate', async interaction => {
        if (!interaction.isChatInputCommand() || interaction.commandName !== 'server') return;

        if (interaction.channelId !== commandChannelId) {
            await interaction.reply({
                content: `Use this command in <#${commandChannelId}>.`,
                ephemeral: true
            });
            return;
        }

        if (!interaction.memberPermissions?.has(PermissionFlagsBits.ManageGuild)) {
            await interaction.reply({ content: 'You need Manage Server permission to use this command.', ephemeral: true });
            return;
        }

        const action = interaction.options.getSubcommand();
        await interaction.deferReply({ ephemeral: true });

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
