using System;
using DiscordRPC;
using DiscordRPC.Logging;

namespace PalLauncher.Services
{
    public class DiscordRpcService : IDisposable
    {
        private DiscordRpcClient? _client;
        private bool _isInitialized;
        private const string DefaultDiscordAppId = "1202359489234858025"; // Palworld community presence ID

        public void Initialize(string? appId = null)
        {
            if (_isInitialized) return;

            try
            {
                _client = new DiscordRpcClient(appId ?? DefaultDiscordAppId)
                {
                    Logger = new ConsoleLogger { Level = LogLevel.Warning }
                };

                _client.OnReady += (sender, e) =>
                {
                    Console.WriteLine($"Discord RPC ready for user: {e.User.Username}");
                };

                _client.Initialize();
                _isInitialized = true;
                SetLauncherPresence();
            }
            catch (Exception ex)
            {
                Console.WriteLine($"Discord RPC initialization failed: {ex.Message}");
            }
        }

        public void SetLauncherPresence(string serverName = "PalOdyssey Official")
        {
            if (_client == null || !_isInitialized || _client.IsDisposed) return;

            try
            {
                _client.SetPresence(new RichPresence
                {
                    Details = "Server Online",
                    State = "Browsing Launcher",
                    Assets = new Assets
                    {
                        LargeImageKey = "pal_logo",
                        LargeImageText = $"{serverName} (Modded)",
                        SmallImageKey = "online_icon",
                        SmallImageText = "Ready to Play"
                    }
                });
            }
            catch (Exception)
            {
                // Silently ignore RPC update errors
            }
        }

        public void SetInGamePresence(string serverName = "PalOdyssey Official")
        {
            if (_client == null || !_isInitialized || _client.IsDisposed) return;

            try
            {
                _client.SetPresence(new RichPresence
                {
                    Details = "Exploring Palpagos / Boss Raid",
                    State = $"Playing on {serverName}",
                    Timestamps = Timestamps.Now,
                    Assets = new Assets
                    {
                        LargeImageKey = "pal_logo",
                        LargeImageText = $"{serverName} Dedicated Server",
                        SmallImageKey = "battle_icon",
                        SmallImageText = "Level 55 - In Game"
                    }
                });
            }
            catch (Exception)
            {
                // Silently ignore RPC update errors
            }
        }

        public void Dispose()
        {
            if (_client != null)
            {
                try
                {
                    _client.ClearPresence();
                    _client.Dispose();
                }
                catch { }
                _client = null;
            }
            _isInitialized = false;
            GC.SuppressFinalize(this);
        }
    }
}
