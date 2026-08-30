import { Client, GatewayIntentBits } from 'discord.js';
import dotenv from 'dotenv';
import { initLiveboard } from './plugins/liveboard.js';
import { initCommands } from './plugins/commands.js';
import { initServerApi } from './plugins/serverApi.js';
import { initInactivityWatchdog } from './plugins/palRest.js';

dotenv.config();
initInactivityWatchdog();

const client = new Client({ intents: [GatewayIntentBits.Guilds] });

client.once('ready', () => {
    console.log(`[PalOdyssey Bot] Connected as ${client.user.tag}`);

    const configuredApplicationId = process.env.DISCORD_APPLICATION_ID;
    if (configuredApplicationId && configuredApplicationId !== client.application.id) {
        console.warn('[PalOdyssey Bot] DISCORD_APPLICATION_ID does not match the authenticated bot.');
    }

    initLiveboard(client);
    initCommands(client);
    initServerApi();
});

if (process.env.DISCORD_BOT_TOKEN) {
    client.login(process.env.DISCORD_BOT_TOKEN).catch(err => {
        console.error('[PalOdyssey Bot] Login failed:', err.message);
    });
} else {
    console.warn('[PalOdyssey Bot] DISCORD_BOT_TOKEN not provided. Starting Server API daemon only.');
    initServerApi();
}
