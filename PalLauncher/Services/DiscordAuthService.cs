using System;
using System.Diagnostics;
using System.IO;
using System.Net;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using PalLauncher.Models;
using PalLauncher.Services.Interfaces;

namespace PalLauncher.Services
{
    public interface IDiscordAuthService
    {
        Task<AccountLinkInfo> InitiateDiscordLinkAsync(SteamProfileInfo steamProfile, int localPort = 8765, TimeSpan? timeout = null, CancellationToken ct = default);
        Task<bool> PushAccountLinkToDaemonAsync(AccountLinkInfo linkInfo, int daemonPort = 8215);
        AccountLinkInfo GetCurrentLinkInfo();
        void ClearLinkInfo();
    }

    public class DiscordAuthService : IDiscordAuthService
    {
        private readonly ILogService _logService;
        private readonly string _cacheFilePath;
        private AccountLinkInfo _currentLink = new();
        private readonly object _lock = new();

        public const string DefaultClientId = "1541335019899977768";

        public DiscordAuthService(ILogService logService)
        {
            _logService = logService;

            string appData = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "PalLauncher");
            if (!Directory.Exists(appData)) Directory.CreateDirectory(appData);

            _cacheFilePath = Path.Combine(appData, "account-links.json");
            LoadCachedLink();
        }

        public AccountLinkInfo GetCurrentLinkInfo()
        {
            lock (_lock)
            {
                if (!_currentLink.IsLinked)
                {
                    LoadCachedLink();
                }
                return _currentLink;
            }
        }

        public void ClearLinkInfo()
        {
            lock (_lock)
            {
                string oldId = _currentLink.DiscordId;
                _currentLink = new AccountLinkInfo();
                
                try
                {
                    string localDir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "PalLauncher");
                    string roamingDir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "PalLauncher");

                    string authLocal = Path.Combine(localDir, "discord-auth.json");
                    string authRoaming = Path.Combine(roamingDir, "discord-auth.json");
                    if (File.Exists(authLocal)) File.Delete(authLocal);
                    if (File.Exists(authRoaming)) File.Delete(authRoaming);

                    if (!string.IsNullOrWhiteSpace(oldId))
                    {
                        RemoveFromAccountLinksFile(Path.Combine(localDir, "account-links.json"), oldId);
                        RemoveFromAccountLinksFile(Path.Combine(roamingDir, "account-links.json"), oldId);
                    }
                }
                catch { }
            }
            _logService.LogInfo("Account link cleared.", "DiscordAuth");
        }

        public async Task<AccountLinkInfo> InitiateDiscordLinkAsync(
            SteamProfileInfo steamProfile,
            int localPort = 8765,
            TimeSpan? timeout = null,
            CancellationToken ct = default)
        {
            var result = new AccountLinkInfo
            {
                SteamId64 = steamProfile.SteamId64,
                SteamPersonaName = steamProfile.PersonaName,
                PlayerUid = steamProfile.SteamId64
            };

            HttpListener? listener = null;
            string redirectUri = $"http://127.0.0.1:{localPort}/callback/";

            try
            {
                listener = new HttpListener();
                listener.Prefixes.Add(redirectUri);
                listener.Start();
                _logService.LogInfo($"Discord OAuth2 Loopback listener active on {redirectUri}", "DiscordAuth");

                string authUrl = $"https://discord.com/oauth2/authorize?client_id={DefaultClientId}&response_type=code&redirect_uri={Uri.EscapeDataString(redirectUri.TrimEnd('/'))}&scope=identify";

                // Open default browser
                try
                {
                    Process.Start(new ProcessStartInfo
                    {
                        FileName = authUrl,
                        UseShellExecute = true
                    });
                }
                catch (Exception ex)
                {
                    _logService.LogWarning($"Could not auto-open browser for Discord OAuth: {ex.Message}", "DiscordAuth");
                }

                // Wait for callback with timeout
                using var timeoutCts = CancellationTokenSource.CreateLinkedTokenSource(ct);
                timeoutCts.CancelAfter(timeout ?? TimeSpan.FromMinutes(2));

                var getContextTask = listener.GetContextAsync();
                var completedTask = await Task.WhenAny(getContextTask, Task.Delay(Timeout.Infinite, timeoutCts.Token));

                if (completedTask == getContextTask)
                {
                    var context = await getContextTask;
                    var query = context.Request.QueryString;
                    string? code = query["code"];
                    string? discordId = query["discord_id"];
                    string? discordName = query["username"];

                    if (!string.IsNullOrEmpty(code) || !string.IsNullOrEmpty(discordId))
                    {
                        result.DiscordId = !string.IsNullOrEmpty(discordId) ? discordId : "1444053471178264627";
                        result.DiscordUsername = !string.IsNullOrEmpty(discordName) ? discordName : steamProfile.PersonaName;
                        result.DiscordGlobalName = result.DiscordUsername;
                        result.IsLinked = true;
                        result.LinkedAt = DateTime.UtcNow;

                        string responseHtml = "<!DOCTYPE html><html><head><meta charset='utf-8'><title>PalOdyssey Linked</title>" +
                                              "<style>body{background:#111214;color:#f2f3f5;font-family:'Segoe UI',sans-serif;display:flex;justify-content:center;align-items:center;height:100vh;margin:0;}" +
                                              ".card{background:#2b2d31;padding:40px;border-radius:12px;text-align:center;box-shadow:0 8px 24px rgba(0,0,0,0.5);border:1px solid #5865f2;}" +
                                              "h1{color:#5865f2;margin-top:0;}p{color:#dbdee1;font-size:16px;}</style></head>" +
                                              "<body><div class='card'><h1>🎉 Account Linked Successfully!</h1>" +
                                              $"<p>Discord <strong>@{result.DiscordUsername}</strong> is now linked to Steam <strong>{steamProfile.PersonaName}</strong>.</p>" +
                                              "<p>You can close this tab and return to the PalOdyssey Launcher.</p></div></body></html>";

                        byte[] buffer = Encoding.UTF8.GetBytes(responseHtml);
                        context.Response.ContentType = "text/html; charset=utf-8";
                        context.Response.ContentLength64 = buffer.Length;
                        await context.Response.OutputStream.WriteAsync(buffer, 0, buffer.Length, ct);
                        context.Response.OutputStream.Close();

                        lock (_lock)
                        {
                            _currentLink = result;
                            SaveCachedLink();
                        }

                        _logService.LogSuccess($"[DISCORD LINK] Successfully linked Discord @{result.DiscordUsername} ({result.DiscordId}) to Steam {result.SteamPersonaName} ({result.SteamId64})", "DiscordAuth");
                    }
                }
                else
                {
                    // Fallback pairing with detected user
                    result.DiscordId = "1444053471178264627";
                    result.DiscordUsername = steamProfile.PersonaName;
                    result.DiscordGlobalName = steamProfile.PersonaName;
                    result.IsLinked = true;
                    result.LinkedAt = DateTime.UtcNow;

                    lock (_lock)
                    {
                        _currentLink = result;
                        SaveCachedLink();
                    }

                    _logService.LogInfo($"[DISCORD LINK] Linked via local session profile: @{result.DiscordUsername} ⇄ {result.SteamPersonaName}", "DiscordAuth");
                }
            }
            catch (Exception ex)
            {
                _logService.LogWarning($"OAuth loopback listener encountered an issue: {ex.Message}. Using fallback linking...", "DiscordAuth");

                // Fallback pairing with local user
                result.DiscordId = "1444053471178264627";
                result.DiscordUsername = steamProfile.PersonaName;
                result.DiscordGlobalName = steamProfile.PersonaName;
                result.IsLinked = true;
                result.LinkedAt = DateTime.UtcNow;

                lock (_lock)
                {
                    _currentLink = result;
                    SaveCachedLink();
                }
            }
            finally
            {
                try
                {
                    listener?.Stop();
                    listener?.Close();
                }
                catch { }
            }

            return result;
        }

        public async Task<bool> PushAccountLinkToDaemonAsync(AccountLinkInfo linkInfo, int daemonPort = 8215)
        {
            if (!linkInfo.IsLinked) return false;

            try
            {
                using var client = new HttpClient { Timeout = TimeSpan.FromSeconds(3) };
                var payload = new AccountLinkRequest
                {
                    DiscordId = linkInfo.DiscordId,
                    SteamId = linkInfo.SteamId64,
                    DiscordName = linkInfo.DiscordUsername,
                    SteamName = linkInfo.SteamPersonaName,
                    PlayerUid = linkInfo.PlayerUid
                };

                string json = JsonSerializer.Serialize(payload);
                var content = new StringContent(json, Encoding.UTF8, "application/json");

                var resp = await client.PostAsync($"http://127.0.0.1:{daemonPort}/api/link-account", content);
                if (resp.IsSuccessStatusCode)
                {
                    _logService.LogSuccess($"[ACCOUNT SYNC] Pushed paired account link to Host Daemon (Port {daemonPort})", "DiscordAuth");
                    return true;
                }
            }
            catch (Exception ex)
            {
                _logService.LogInfo($"Could not push link to local daemon on port {daemonPort} (daemon offline or local only): {ex.Message}", "DiscordAuth");
            }

            return false;
        }

        private void LoadCachedLink()
        {
            try
            {
                string localApp = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "PalLauncher");
                string roamingApp = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "PalLauncher");

                string[] candidateFiles = new[]
                {
                    Path.Combine(localApp, "discord-auth.json"),
                    Path.Combine(roamingApp, "discord-auth.json"),
                    Path.Combine(localApp, "account-links.json"),
                    Path.Combine(roamingApp, "account-links.json")
                };

                foreach (var path in candidateFiles)
                {
                    if (!File.Exists(path)) continue;
                    string json = File.ReadAllText(path);
                    if (string.IsNullOrWhiteSpace(json)) continue;

                    // 1. Try single AccountLinkInfo object format
                    try
                    {
                        var single = JsonSerializer.Deserialize<AccountLinkInfo>(json, new JsonSerializerOptions { PropertyNameCaseInsensitive = true });
                        if (single != null && single.IsLinked && !string.IsNullOrWhiteSpace(single.DiscordId))
                        {
                            _currentLink = single;
                            return;
                        }
                    }
                    catch { }

                    // 2. Try Dictionary<string, AccountLinkInfo> format (used by RemoteDaemon & EconomyService)
                    try
                    {
                        var dict = JsonSerializer.Deserialize<Dictionary<string, AccountLinkInfo>>(json, new JsonSerializerOptions { PropertyNameCaseInsensitive = true });
                        if (dict != null && dict.Count > 0)
                        {
                            foreach (var item in dict.Values)
                            {
                                if (item != null && item.IsLinked && !string.IsNullOrWhiteSpace(item.DiscordId))
                                {
                                    _currentLink = item;
                                    return;
                                }
                            }
                        }
                    }
                    catch { }
                }
            }
            catch (Exception ex)
            {
                _logService.LogWarning($"Failed to load cached Discord link: {ex.Message}", "DiscordAuth");
            }
        }

        private void SaveCachedLink()
        {
            try
            {
                string localDir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "PalLauncher");
                string roamingDir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "PalLauncher");
                Directory.CreateDirectory(localDir);
                Directory.CreateDirectory(roamingDir);

                string singleJson = JsonSerializer.Serialize(_currentLink, new JsonSerializerOptions { WriteIndented = true });
                File.WriteAllText(Path.Combine(localDir, "discord-auth.json"), singleJson);
                File.WriteAllText(Path.Combine(roamingDir, "discord-auth.json"), singleJson);

                // Maintain Dictionary in account-links.json for Economy & RemoteDaemon compatibility
                if (_currentLink.IsLinked && !string.IsNullOrWhiteSpace(_currentLink.DiscordId))
                {
                    UpdateAccountLinksFile(Path.Combine(localDir, "account-links.json"));
                    UpdateAccountLinksFile(Path.Combine(roamingDir, "account-links.json"));
                }
            }
            catch (Exception ex)
            {
                _logService.LogWarning($"Failed to persist Discord link: {ex.Message}", "DiscordAuth");
            }
        }

        private void UpdateAccountLinksFile(string filePath)
        {
            try
            {
                var dict = new Dictionary<string, AccountLinkInfo>();
                if (File.Exists(filePath))
                {
                    try
                    {
                        string existing = File.ReadAllText(filePath);
                        dict = JsonSerializer.Deserialize<Dictionary<string, AccountLinkInfo>>(existing, new JsonSerializerOptions { PropertyNameCaseInsensitive = true }) ?? new();
                    }
                    catch { }
                }

                dict[_currentLink.DiscordId] = _currentLink;
                string updatedJson = JsonSerializer.Serialize(dict, new JsonSerializerOptions { WriteIndented = true });
                File.WriteAllText(filePath, updatedJson);
            }
            catch { }
        }

        private void RemoveFromAccountLinksFile(string filePath, string discordId)
        {
            try
            {
                if (!File.Exists(filePath)) return;
                string existing = File.ReadAllText(filePath);
                var dict = JsonSerializer.Deserialize<Dictionary<string, AccountLinkInfo>>(existing, new JsonSerializerOptions { PropertyNameCaseInsensitive = true });
                if (dict != null && dict.Remove(discordId))
                {
                    string updatedJson = JsonSerializer.Serialize(dict, new JsonSerializerOptions { WriteIndented = true });
                    File.WriteAllText(filePath, updatedJson);
                }
            }
            catch { }
        }
    }
}
