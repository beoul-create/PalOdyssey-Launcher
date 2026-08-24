using System;
using System.Diagnostics;
using System.IO;
using System.Net;
using System.Text.RegularExpressions;
using System.Threading;
using System.Threading.Tasks;
using PalLauncher.Services.Interfaces;

namespace PalLauncher.Services
{
    public class SteamAuthService : ISteamAuthService
    {
        private readonly ILogService _logService;
        private readonly object _lock = new();

        public SteamAuthService(ILogService logService)
        {
            _logService = logService;
        }

        public async Task<SteamProfileInfo> InitiateSteamLoginAsync(
            int localPort = 8766,
            TimeSpan? timeout = null,
            CancellationToken ct = default)
        {
            var profile = new SteamProfileInfo();
            HttpListener? listener = null;
            string redirectUri = $"http://127.0.0.1:{localPort}/callback/";

            try
            {
                listener = new HttpListener();
                listener.Prefixes.Add(redirectUri);
                listener.Start();
                _logService.LogInfo($"Steam OpenID Loopback listener active on {redirectUri}", "SteamAuth");

                string authUrl = "https://steamcommunity.com/openid/login" +
                                 "?openid.ns=http://specs.openid.net/auth/2.0" +
                                 "&openid.mode=checkid_setup" +
                                 $"&openid.return_to={Uri.EscapeDataString(redirectUri)}" +
                                 $"&openid.realm={Uri.EscapeDataString($"http://127.0.0.1:{localPort}")}" +
                                 "&openid.identity=http://specs.openid.net/auth/2.0/identifier_select" +
                                 "&openid.claimed_id=http://specs.openid.net/auth/2.0/identifier_select";

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
                    _logService.LogWarning($"Failed to launch browser: {ex.Message}", "SteamAuth");
                    return profile;
                }

                var tcs = new TaskCompletionSource<SteamProfileInfo>();
                using var registration = ct.Register(() => tcs.TrySetCanceled());

                var timeoutSpan = timeout ?? TimeSpan.FromMinutes(2);
                using var timeoutCts = new CancellationTokenSource(timeoutSpan);
                using var timeoutReg = timeoutCts.Token.Register(() => tcs.TrySetCanceled());

                _ = Task.Run(async () =>
                {
                    try
                    {
                        var context = await listener.GetContextAsync();
                        var request = context.Request;
                        var response = context.Response;

                        string? claimedId = request.QueryString["openid.claimed_id"];
                        
                        string responseString = "";
                        if (!string.IsNullOrEmpty(claimedId))
                        {
                            var match = Regex.Match(claimedId, @"^https?://steamcommunity\.com/openid/id/(\d{17,20})$");
                            if (match.Success)
                            {
                                string steamId = match.Groups[1].Value;
                                profile.SteamId64 = steamId;
                                profile.IsDetected = true;
                                profile.PersonaName = "Steam Pioneer"; // Fetching real name requires Steam Web API, this is a fallback.
                                
                                responseString = "<html><head><style>body{background:#0b1120;color:#fff;font-family:sans-serif;text-align:center;padding:50px;} h2{color:#00F0FF;}</style></head><body><h2>Steam Authorized!</h2><p>You can close this window and return to PalOdyssey Launcher.</p><script>setTimeout(()=>window.close(),3000);</script></body></html>";
                                _logService.LogSuccess($"Successfully received Steam OpenID auth for Steam64: {steamId}", "SteamAuth");
                            }
                            else
                            {
                                responseString = "<html><body><h2>Invalid Steam ID received.</h2></body></html>";
                                _logService.LogWarning("Steam OpenID callback contained invalid claimed_id.", "SteamAuth");
                            }
                        }
                        else
                        {
                            responseString = "<html><body><h2>Steam Authentication Failed.</h2></body></html>";
                            _logService.LogWarning("Steam OpenID callback missing claimed_id.", "SteamAuth");
                        }

                        byte[] buffer = System.Text.Encoding.UTF8.GetBytes(responseString);
                        response.ContentLength64 = buffer.Length;
                        response.ContentType = "text/html";
                        await response.OutputStream.WriteAsync(buffer, 0, buffer.Length);
                        response.Close();

                        tcs.TrySetResult(profile);
                    }
                    catch (Exception ex)
                    {
                        if (!tcs.Task.IsCanceled)
                        {
                            _logService.LogWarning($"Listener error: {ex.Message}", "SteamAuth");
                            tcs.TrySetResult(profile);
                        }
                    }
                });

                return await tcs.Task;
            }
            catch (OperationCanceledException)
            {
                _logService.LogWarning("Steam authentication timed out or was canceled.", "SteamAuth");
                return profile;
            }
            catch (Exception ex)
            {
                _logService.LogWarning($"Steam authentication error: {ex.Message}", "SteamAuth");
                return profile;
            }
            finally
            {
                if (listener != null)
                {
                    try { listener.Stop(); } catch { }
                    try { listener.Close(); } catch { }
                }
            }
        }
    }
}
