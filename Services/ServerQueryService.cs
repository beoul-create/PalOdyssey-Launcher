using System;
using System.IO;
using System.Net;
using System.Net.NetworkInformation;
using System.Net.Sockets;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;

namespace PalLauncher.Services
{
    public class ServerStatusInfo
    {
        public bool IsOnline { get; set; }
        public int PlayerCount { get; set; }
        public int MaxPlayers { get; set; } = 32;
        public long PingMs { get; set; } = -1;
        public string StatusText { get; set; } = "OFFLINE";
        public string ColorHex { get; set; } = "#EF4444";
        public string PingText => PingMs >= 0 ? $"{PingMs} ms" : "-- ms";
        public string PlayersText => $"{PlayerCount} / {MaxPlayers} Players";
    }

    public class LiveboardJsonState
    {
        public bool ServerOnline { get; set; }
        public int PlayerCount { get; set; }
        public int MaxPlayers { get; set; } = 32;
        public long Timestamp { get; set; }
    }

    public class ServerQueryService : IDisposable
    {
        private readonly Timer _pollTimer;
        private readonly string _host;
        private readonly int _port;
        private readonly string? _localServerDir;
        private int _isQuerying;
        private CancellationTokenSource _cts = new();

        public event Action<ServerStatusInfo>? ServerStatusUpdated;

        public ServerStatusInfo CurrentStatus { get; private set; } = new();

        public ServerQueryService(
            string host = "palodyssey.duckdns.org",
            int port = 8211,
            string? localServerDir = null)
        {
            _host = host;
            _port = port;
            _localServerDir = localServerDir;
            // Poll every 8 seconds
            _pollTimer = new Timer(
                async _ => await QueryServerAsync(_host, _port, _localServerDir, _cts.Token),
                null,
                500,
                8000);
        }

        public void SetPollingEnabled(bool enabled)
        {
            _pollTimer.Change(enabled ? 500 : Timeout.Infinite, enabled ? 8000 : Timeout.Infinite);
        }

        private static readonly System.Net.Http.HttpClient _httpClient = new() { Timeout = TimeSpan.FromSeconds(3) };
        private static readonly JsonSerializerOptions _jsonOpts = new() { PropertyNameCaseInsensitive = true };

        public async Task<ServerStatusInfo> QueryServerAsync(
            string host = "palodyssey.duckdns.org",
            int port = 8211,
            string? localServerDir = null,
            CancellationToken cancellationToken = default)
        {
            if (Interlocked.CompareExchange(ref _isQuerying, 1, 0) != 0) return CurrentStatus;

            var status = new ServerStatusInfo();

            try
            {
                // 1. Check local liveboard state if hosted on this machine
                LiveboardJsonState? localTelemetry = CheckLocalLiveboardState(localServerDir);
                if (localTelemetry != null && localTelemetry.ServerOnline)
                {
                    status.IsOnline = true;
                    status.PlayerCount = localTelemetry.PlayerCount;
                    status.MaxPlayers = localTelemetry.MaxPlayers > 0 ? localTelemetry.MaxPlayers : 32;
                    status.StatusText = "SERVER ONLINE (Host)";
                    status.ColorHex = "#10B981";
                    status.PingMs = 1;
                    CurrentStatus = status;
                    ServerStatusUpdated?.Invoke(status);
                    return status;
                }

                // 2. Query remote Liveboard Daemon REST API
                var remoteApiCandidates = new[]
                {
                    $"http://{host}:3001",
                    "http://127.0.0.1:3001"
                };

                foreach (var apiUrl in remoteApiCandidates)
                {
                    try
                    {
                        var sw = System.Diagnostics.Stopwatch.StartNew();
                        using var res = await _httpClient.GetAsync($"{apiUrl}/api/server/status", cancellationToken);
                        sw.Stop();

                        if (res.IsSuccessStatusCode)
                        {
                            await using var stream = await res.Content.ReadAsStreamAsync(cancellationToken);
                            var doc = await JsonSerializer.DeserializeAsync<ServerStatusResponse>(stream, _jsonOpts, cancellationToken);
                            if (doc != null)
                            {
                                status.IsOnline = doc.ServerOnline || doc.IsProcessRunning;
                                status.PlayerCount = doc.PlayerCount;
                                status.MaxPlayers = doc.MaxPlayers > 0 ? doc.MaxPlayers : 32;
                                status.PingMs = Math.Max(1, sw.ElapsedMilliseconds);
                                status.StatusText = status.IsOnline ? "SERVER ONLINE" : "SERVER OFFLINE";
                                status.ColorHex = status.IsOnline ? "#10B981" : "#EF4444";

                                CurrentStatus = status;
                                ServerStatusUpdated?.Invoke(status);
                                return status;
                            }
                        }
                    }
                    catch { }
                }

                // 3. Fallback: Measure direct ping / probe network host
                long measuredPing = await MeasurePingAsync(host, port, cancellationToken);
                status.PingMs = measuredPing;

                if (measuredPing >= 0)
                {
                    status.IsOnline = true;
                    status.StatusText = "SERVER ONLINE";
                    status.ColorHex = "#10B981"; // Emerald
                }
                else
                {
                    status.IsOnline = false;
                    status.StatusText = "SERVER OFFLINE";
                    status.ColorHex = "#EF4444"; // Crimson
                    status.PlayerCount = 0;
                }
            }
            catch
            {
                status.IsOnline = false;
                status.StatusText = "SERVER OFFLINE";
                status.ColorHex = "#EF4444";
                status.PingMs = -1;
                status.PlayerCount = 0;
            }
            finally
            {
                Interlocked.Exchange(ref _isQuerying, 0);
            }

            CurrentStatus = status;
            ServerStatusUpdated?.Invoke(status);
            return status;
        }

        private static async Task<long> MeasurePingAsync(string host, int port, CancellationToken cancellationToken)
        {
            try
            {
                using var pinger = new Ping();
                var reply = await pinger.SendPingAsync(host, TimeSpan.FromMilliseconds(1200), cancellationToken: cancellationToken);
                if (reply.Status == IPStatus.Success)
                {
                    return reply.RoundtripTime;
                }
            }
            catch { }

            return -1;
        }

        private static LiveboardJsonState? CheckLocalLiveboardState(string? localServerDir)
        {
            try
            {
                string[] possiblePaths =
                {
                    "Pal/Saved/liveboard_state.json",
                    Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "Pal", "Saved", "liveboard_state.json"),
                    string.IsNullOrWhiteSpace(localServerDir) ? "" : Path.Combine(localServerDir, "Pal", "Saved", "liveboard_state.json"),
                    @"C:\SteamLibrary\steamapps\common\PalServer\Pal\Saved\liveboard_state.json"
                };

                foreach (var path in possiblePaths)
                {
                    if (!string.IsNullOrWhiteSpace(path) && File.Exists(path))
                    {
                        var info = new FileInfo(path);
                        // If modified within the last 120 seconds, it's fresh
                        if (DateTime.UtcNow - info.LastWriteTimeUtc < TimeSpan.FromMinutes(2))
                        {
                            string json = File.ReadAllText(path);
                            return JsonSerializer.Deserialize<LiveboardJsonState>(json, new JsonSerializerOptions
                            {
                                PropertyNameCaseInsensitive = true
                            });
                        }
                    }
                }
            }
            catch { }

            return null;
        }

        public void Dispose()
        {
            _cts.Cancel();
            _pollTimer.Dispose();
            _cts.Dispose();
            GC.SuppressFinalize(this);
        }
    }
}
