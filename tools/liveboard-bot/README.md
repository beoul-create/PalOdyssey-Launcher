# PalOdyssey Liveboard Bot

The bot maintains the server liveboard and registers these slash commands:

- `/server start` — available to every member of the Discord server
- `/server status` — requires Discord's **Manage Server** permission
- `/server stop` — requires Discord's **Manage Server** permission

Commands only run in the channel configured by `DISCORD_COMMAND_CHANNEL_ID`.

## Setup

1. Reset the bot token in the Discord Developer Portal. Any token pasted into a chat or committed to a file must be treated as compromised.
2. Copy `.env.example` to `.env`.
3. Put the newly generated token in `.env` as `DISCORD_BOT_TOKEN`. Never add `.env` to source control.
4. Replace `REMOTE_ADMIN_KEY` with a long random value and verify `PAL_SERVER_EXE` and `LIVEBOARD_STATE_PATH`.
5. From this directory, run `npm install` and then `npm start`.

The bot needs the `bot` and `applications.commands` OAuth scopes. It needs View Channel, Send Messages, Embed Links, and Read Message History in the liveboard channel.

Player names and levels are read from Palworld's authenticated REST API. By default the bot reads `AdminPassword` from the local `PalWorldSettings.ini`; set `PAL_SETTINGS_PATH` only when the server uses a different location. The same REST player list drives the 15-minute inactivity shutdown, avoiding stale `PlayerState` actors.
