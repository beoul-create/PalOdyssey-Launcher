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
        private bool _isQuerying;
        private CancellationTokenSource _cts = new();

        public event Action<ServerStatusInfo>? ServerStatusUpdated;

        public ServerStatusInfo CurrentStatus { get; private set; } = new();

        public ServerQueryService()
        {
            // Poll every 8 seconds
            _pollTimer = new Timer(async _ => await QueryServerAsync(), null, 500, 8000);
        }

        public async Task<ServerStatusInfo> QueryServerAsync(string host = "palodyssey.duckdns.org", int port = 8211, string? localServerDir = null)
        {
            if (_isQuerying) return CurrentStatus;
            _isQuerying = true;

            var status = new ServerStatusInfo();

            try
            {
                // 1. Check local liveboard state if present
                LiveboardJsonState? localTelemetry = CheckLocalLiveboardState(localServerDir);
                if (localTelemetry != null)
                {
                    status.IsOnline = localTelemetry.ServerOnline;
                    status.PlayerCount = localTelemetry.PlayerCount;
                    status.MaxPlayers = localTelemetry.MaxPlayers > 0 ? localTelemetry.MaxPlayers : 32;
                }

                // 2. Measure ping & probe network host
                long measuredPing = await MeasurePingAsync(host, port);
                status.PingMs = measuredPing;

                // 3. Resolve status logic
                if (measuredPing >= 0)
                {
                    status.IsOnline = true;
                    status.StatusText = "SERVER ONLINE";
                    status.ColorHex = "#10B981"; // Emerald
                }
                else if (localTelemetry != null && localTelemetry.ServerOnline)
                {
                    status.IsOnline = true;
                    status.StatusText = "SERVER ONLINE (Local)";
                    status.ColorHex = "#10B981";
                    status.PingMs = 1;
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
                _isQuerying = false;
            }

            CurrentStatus = status;
            ServerStatusUpdated?.Invoke(status);
            return status;
        }

        private static async Task<long> MeasurePingAsync(string host, int port)
        {
            try
            {
                // Quick ICMP Ping
                using var pinger = new Ping();
                var reply = await pinger.SendPingAsync(host, 1500);
                if (reply.Status == IPStatus.Success)
                {
                    return reply.RoundtripTime;
                }
            }
            catch { }

            // Fallback: UDP / Socket DNS probe & connect simulation
            try
            {
                using var cts = new CancellationTokenSource(1500);
                var stopwatch = System.Diagnostics.Stopwatch.StartNew();
                var addresses = await Dns.GetHostAddressesAsync(host, cts.Token);
                if (addresses.Length > 0)
                {
                    using var client = new UdpClient();
                    client.Client.SendTimeout = 1200;
                    client.Client.ReceiveTimeout = 1200;
                    var ep = new IPEndPoint(addresses[0], port);
                    client.Connect(ep);
                    stopwatch.Stop();
                    return Math.Max(5, stopwatch.ElapsedMilliseconds);
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
