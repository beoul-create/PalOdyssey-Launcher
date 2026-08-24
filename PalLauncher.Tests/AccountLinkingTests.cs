using System;
using System.Collections.Generic;
using System.IO;
using System.Net;
using System.Net.Http;
using System.Text;
using System.Text.Json;
using System.Threading.Tasks;
using PalLauncher.Models;
using PalLauncher.Services;
using PalLauncher.Services.Interfaces;
using PalLauncher.ViewModels;
using Xunit;

namespace PalLauncher.Tests
{
    public class AccountLinkingTests
    {
        private readonly ILogService _logService = new LogService();

        [Fact]
        public void SteamDetectionService_CanDetectOrHandleLocalSteam()
        {
            var service = new SteamDetectionService(_logService);
            var profile = service.DetectActiveSteamUser();

            Assert.NotNull(profile);
            // In a machine with Steam installed, IsDetected will be true
            if (profile.IsDetected)
            {
                Assert.False(string.IsNullOrEmpty(profile.SteamId64));
                Assert.False(string.IsNullOrEmpty(profile.PersonaName));
                Assert.StartsWith("7656119", profile.SteamId64);
            }
            else
            {
                Assert.Equal("Steam Not Detected", profile.FormattedSummary);
            }
        }

        [Fact]
        public async Task AccountLink_PersistsAndLoadsCorrectly()
        {
            string tempDir = Path.Combine(Path.GetTempPath(), "PalAccountLinkTest_" + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(tempDir);

            try
            {
                var authService = new DiscordAuthService(_logService);
                var steamProfile = new SteamProfileInfo
                {
                    IsDetected = true,
                    SteamId64 = "76561198095071863",
                    PersonaName = "Beoul"
                };

                // Initiate link (will fall back cleanly without interactive browser in unit tests)
                var link = await authService.InitiateDiscordLinkAsync(steamProfile, localPort: 8769, timeout: TimeSpan.FromMilliseconds(200));

                Assert.NotNull(link);
                Assert.True(link.IsLinked);
                Assert.Equal("76561198095071863", link.SteamId64);
                Assert.Equal("Beoul", link.SteamPersonaName);
                Assert.Contains("Linked", link.DisplayBadge);

                // Check cached retrieval
                var current = authService.GetCurrentLinkInfo();
                Assert.NotNull(current);
                Assert.True(current.IsLinked);
                Assert.Equal("76561198095071863", current.SteamId64);

                // Clear link
                authService.ClearLinkInfo();
                var cleared = authService.GetCurrentLinkInfo();
                Assert.False(cleared.IsLinked);
            }
            finally
            {
                if (Directory.Exists(tempDir)) Directory.Delete(tempDir, true);
            }
        }

        [Fact]
        public async Task RemoteServerDaemon_LinkAccountEndpoint_StoresAccountLinks()
        {
            var launchService = new LaunchService(_logService);
            var daemon = new RemoteServerDaemon(_logService, launchService);

            int testPort = 20850;
            await daemon.StartDaemonAsync(testPort, "test-key", () => Task.FromResult(true), () => Task.FromResult(true));

            try
            {
                using var client = new HttpClient { BaseAddress = new Uri($"http://127.0.0.1:{testPort}/") };

                var linkReq = new AccountLinkRequest
                {
                    DiscordId = "1444053471178264627",
                    SteamId = "76561198095071863",
                    DiscordName = "TestUser",
                    SteamName = "Beoul",
                    PlayerUid = "9EDC20A9000000000000000000000000"
                };

                var content = new StringContent(JsonSerializer.Serialize(linkReq), Encoding.UTF8, "application/json");
                var resp = await client.PostAsync("api/link-account", content);

                Assert.Equal(HttpStatusCode.OK, resp.StatusCode);
                string json = await resp.Content.ReadAsStringAsync();
                Assert.Contains("stored successfully", json);
            }
            finally
            {
                await daemon.StopDaemonAsync();
            }
        }

        [Fact]
        public async Task EconomyService_AutomaticallyResolvesLinkedAccountWithoutManualInput()
        {
            string tempDir = Path.Combine(Path.GetTempPath(), "PalEcoAutoLink_" + Guid.NewGuid().ToString("N"));
            string playersDir = Path.Combine(tempDir, "Players");
            Directory.CreateDirectory(playersDir);

            try
            {
                string playerUid = "9EDC20A9000000000000000000000000";
                string savePath = Path.Combine(playersDir, $"{playerUid}.sav");

                byte[] mockSave = CreateMockPalworldSave(unusedTechPoints: 20, level: 15);
                await File.WriteAllBytesAsync(savePath, mockSave);

                var saveService = new PalSaveService(_logService, tempDir);
                string statePath = Path.Combine(tempDir, "state.json");
                string accountLinksPath = Path.Combine(tempDir, "account-links.json");

                // Write account links dictionary
                var links = new Dictionary<string, AccountLinkInfo>
                {
                    ["discord_user_999"] = new AccountLinkInfo
                    {
                        DiscordId = "discord_user_999",
                        DiscordUsername = "PioneerExplorer",
                        SteamId64 = "76561198095071863",
                        PlayerUid = playerUid,
                        IsLinked = true
                    }
                };
                await File.WriteAllTextAsync(accountLinksPath, JsonSerializer.Serialize(links));

                var economyService = new EconomyService(_logService, saveService, customStateFilePath: statePath);

                // Query linked player UID using only Discord User ID
                string resolvedUid = economyService.GetLinkedPlayerUid("discord_user_999");
                Assert.Equal(playerUid, resolvedUid);

                // Execute exchange seamlessly using resolved UID
                var receipt = await economyService.ExecuteExchangeAsync(resolvedUid, "dog_coin", 2);
                Assert.True(receipt.Success);
                Assert.Equal(4, receipt.TotalCost); // 2 dog coins * 2 pts = 4 pts
                Assert.Equal(16, receipt.NewTechPoints);
            }
            finally
            {
                if (Directory.Exists(tempDir)) Directory.Delete(tempDir, true);
            }
        }

        private static byte[] CreateMockPalworldSave(int unusedTechPoints, int level)
        {
            using var ms = new MemoryStream();
            using var writer = new BinaryWriter(ms, Encoding.ASCII);

            writer.Write(Encoding.ASCII.GetBytes("GVAS"));
            writer.Write(3);
            writer.Write(new byte[16]);

            string propName = "UnusedTechnologyPoint";
            writer.Write(Encoding.ASCII.GetBytes(propName));
            writer.Write((byte)0);

            string propType = "IntProperty";
            writer.Write(Encoding.ASCII.GetBytes(propType));
            writer.Write((byte)0);

            writer.Write((long)4);
            writer.Write((byte)0);
            writer.Write(unusedTechPoints);

            string lvlProp = "Level";
            writer.Write(Encoding.ASCII.GetBytes(lvlProp));
            writer.Write((byte)0);
            writer.Write(Encoding.ASCII.GetBytes(propType));
            writer.Write((byte)0);
            writer.Write((long)4);
            writer.Write((byte)0);
            writer.Write(level);

            writer.Flush();
            byte[] decompressed = ms.ToArray();

            return PalSaveService.CompressPalSave(decompressed);
        }
    }
}



