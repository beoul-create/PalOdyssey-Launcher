using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.IO.Pipes;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Threading;
using System.Threading.Tasks;
using PalLauncher.Services.Interfaces;

namespace PalLauncher.Services
{
    public class DiscordRpcService : IDiscordRpcService
    {
        private const string PrimaryDefaultAppId = "1541335019899977768";
        private const string SecondaryDefaultAppId = "1540924979095408700";
        private const string FallbackAppId = "383226320970055681";

        private readonly ILogService _logService;
        private NamedPipeClientStream? _pipeClient;
        private CancellationTokenSource? _cts;
        private string _applicationId = PrimaryDefaultAppId;
        private bool _isConnected;
        private DateTime? _sessionStartTime;
        private readonly SemaphoreSlim _pipeSemaphore = new(1, 1);

        // Cached presence state for automatic re-publishing on connect/reconnect and active heartbeat
        private string _cachedDetails = "In Launcher";
        private string _cachedState = "Preparing Expedition";
        private bool _cachedIsPlaying;
        private int? _cachedTargetPid;
        private string? _cachedLargeImageKey;
        private string? _cachedLargeImageText;
        private string? _cachedSmallImageKey;
        private string? _cachedSmallImageText;
        private (string label, string url)[]? _cachedButtons;

        private static readonly JsonSerializerOptions JsonOpts = new()
        {
            DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull
        };

        public bool IsConnected => _isConnected;

        public DiscordRpcService(ILogService logService)
        {
            _logService = logService;
        }

        public Task InitializeAsync(string? applicationId = null)
        {
            if (!string.IsNullOrWhiteSpace(applicationId))
            {
                _applicationId = applicationId.Trim();
            }
            else
            {
                _applicationId = PrimaryDefaultAppId;
            }

            _cts?.Cancel();
            _cts = new CancellationTokenSource();

            _ = Task.Run(() => ConnectLoopAsync(_cts.Token));
            return Task.CompletedTask;
        }

        private async Task ConnectLoopAsync(CancellationToken ct)
        {
            while (!ct.IsCancellationRequested)
            {
                if (!_isConnected)
                {
                    bool connected = await TryConnectToDiscordPipeAsync();
                    if (connected)
                    {
                        await UpdatePresenceAsync(
                            _cachedDetails,
                            _cachedState,
                            _cachedIsPlaying,
                            _cachedTargetPid,
                            _cachedLargeImageKey,
                            _cachedLargeImageText,
                            _cachedSmallImageKey,
                            _cachedSmallImageText,
                            _cachedButtons);
                    }
                }
                else if (_cachedIsPlaying)
                {
                    // Active game heartbeat: keep Rich Presence pinned so Palworld background detection doesn't override it
                    await SendPresenceFrameAsync(
                        _cachedDetails,
                        _cachedState,
                        true,
                        _cachedTargetPid,
                        _cachedLargeImageKey,
                        _cachedLargeImageText,
                        _cachedSmallImageKey,
                        _cachedSmallImageText,
                        _cachedButtons);
                }

                try
                {
                    await Task.Delay(3500, ct); // Heartbeat check / re-broadcast every 3.5s
                }
                catch (OperationCanceledException) { break; }
            }
        }

        private async Task<bool> TryConnectToDiscordPipeAsync()
        {
            await _pipeSemaphore.WaitAsync();
            try
            {
                try { _pipeClient?.Dispose(); } catch { }
                _pipeClient = null;
                _isConnected = false;

                for (int i = 0; i < 10; i++)
                {
                    NamedPipeClientStream? pipe = null;
                    try
                    {
                        string pipeName = $"discord-ipc-{i}";
                        pipe = new NamedPipeClientStream(".", pipeName, PipeDirection.InOut, PipeOptions.Asynchronous);
                        using var connCts = new CancellationTokenSource(500);
                        await pipe.ConnectAsync(connCts.Token);

                        _pipeClient = pipe;

                        // Send Handshake (Opcode 0)
                        var handshake = new { v = 1, client_id = _applicationId };
                        await WriteFrameInternalAsync(0, handshake);

                        // Read Handshake response (Opcode 1 = Frame/Ready, Opcode 2 = Close)
                        using var readCts = new CancellationTokenSource(1500);
                        var (op, json) = await ReadFrameInternalAsync(readCts.Token);

                        if (op == 1 || (!string.IsNullOrEmpty(json) && json.Contains("READY", StringComparison.OrdinalIgnoreCase)))
                        {
                            _isConnected = true;
                            _logService.LogInfo($"Connected to Discord Rich Presence IPC ({pipeName}) [AppID: {_applicationId}].", "DiscordRPC");
                            return true;
                        }
                        else if (op == 2)
                        {
                            // App ID was invalid or rejected by Discord - fallback to alternate registered App ID
                            string fallback = _applicationId == PrimaryDefaultAppId ? SecondaryDefaultAppId : FallbackAppId;
                            if (_applicationId != fallback)
                            {
                                _logService.LogWarning($"Custom Discord AppID '{_applicationId}' rejected ({json}). Retrying with fallback AppID '{fallback}'.", "DiscordRPC");
                                _applicationId = fallback;
                                try { pipe.Dispose(); } catch { }
                                _pipeClient = null;
                                i--; // Immediately retry current pipe index
                                continue;
                            }
                            else
                            {
                                try { pipe.Dispose(); } catch { }
                                _pipeClient = null;
                            }
                        }
                        else
                        {
                            try { pipe.Dispose(); } catch { }
                            _pipeClient = null;
                        }
                    }
                    catch
                    {
                        try { pipe?.Dispose(); } catch { }
                        _pipeClient = null;
                    }
                }

                return false;
            }
            finally
            {
                _pipeSemaphore.Release();
            }
        }

        public async Task UpdatePresenceAsync(
            string details,
            string state,
            bool isPlaying = false,
            int? targetPid = null,
            string? largeImageKey = null,
            string? largeImageText = null,
            string? smallImageKey = null,
            string? smallImageText = null,
            (string label, string url)[]? buttons = null)
        {
            _cachedDetails = details;
            _cachedState = state;
            _cachedIsPlaying = isPlaying;
            if (targetPid.HasValue && targetPid.Value > 0)
            {
                _cachedTargetPid = targetPid.Value;
            }
            _cachedLargeImageKey = largeImageKey;
            _cachedLargeImageText = largeImageText;
            _cachedSmallImageKey = smallImageKey;
            _cachedSmallImageText = smallImageText;
            _cachedButtons = buttons;

            if (!_isConnected || _pipeClient == null || !_pipeClient.IsConnected)
            {
                return;
            }

            await SendPresenceFrameAsync(
                details,
                state,
                isPlaying,
                _cachedTargetPid,
                largeImageKey,
                largeImageText,
                smallImageKey,
                smallImageText,
                buttons);
        }

        private async Task SendPresenceFrameAsync(
            string details,
            string state,
            bool isPlaying,
            int? targetPid,
            string? largeImageKey,
            string? largeImageText,
            string? smallImageKey,
            string? smallImageText,
            (string label, string url)[]? buttons)
        {
            await _pipeSemaphore.WaitAsync();
            try
            {
                if (!_isConnected || _pipeClient == null || !_pipeClient.IsConnected) return;

                if (isPlaying)
                {
                    if (!_sessionStartTime.HasValue)
                    {
                        _sessionStartTime = DateTime.UtcNow;
                    }
                }
                else
                {
                    _sessionStartTime = null;
                }

                long? startUnix = _sessionStartTime.HasValue
                    ? ((DateTimeOffset)_sessionStartTime.Value).ToUnixTimeSeconds()
                    : null;

                object? timestampsObj = startUnix.HasValue ? new { start = startUnix.Value } : null;
                int activePid = (targetPid.HasValue && targetPid.Value > 0) ? targetPid.Value : Process.GetCurrentProcess().Id;

                var activityDict = new Dictionary<string, object?>
                {
                    ["details"] = details,
                    ["state"] = state,
                    ["instance"] = false,
                    ["assets"] = new
                    {
                        large_image = string.IsNullOrWhiteSpace(largeImageKey) ? "palworld" : largeImageKey,
                        large_text = string.IsNullOrWhiteSpace(largeImageText) ? (isPlaying ? "PalOdyssey Expedition" : "PalOdyssey Custom Launcher") : largeImageText,
                        small_image = string.IsNullOrWhiteSpace(smallImageKey) ? (isPlaying ? "online" : "ready") : smallImageKey,
                        small_text = string.IsNullOrWhiteSpace(smallImageText) ? (isPlaying ? "In Realm (Dedicated)" : "Ready to Launch") : smallImageText
                    }
                };

                if (timestampsObj != null)
                {
                    activityDict["timestamps"] = timestampsObj;
                }

                if (buttons != null && buttons.Length > 0)
                {
                    var buttonList = new List<object>();
                    foreach (var (label, url) in buttons)
                    {
                        if (!string.IsNullOrWhiteSpace(label) && !string.IsNullOrWhiteSpace(url) && Uri.TryCreate(url, UriKind.Absolute, out _))
                        {
                            buttonList.Add(new { label = label.Trim(), url = url.Trim() });
                            if (buttonList.Count >= 2) break; // Discord allows maximum 2 action buttons
                        }
                    }
                    if (buttonList.Count > 0)
                    {
                        activityDict["buttons"] = buttonList;
                    }
                }

                var activityPayload = new
                {
                    cmd = "SET_ACTIVITY",
                    args = new
                    {
                        pid = activePid,
                        activity = activityDict
                    },
                    nonce = Guid.NewGuid().ToString("N")
                };

                await WriteFrameInternalAsync(1, activityPayload);

                // Drain response non-fatally so pipe stays clean
                await TryDrainResponseAsync(timeoutMs: 300);
            }
            catch (Exception ex)
            {
                _isConnected = false;
                _logService.LogWarning("Discord presence update notice: " + ex.Message, "DiscordRPC");
                try { _pipeClient?.Dispose(); } catch { }
                _pipeClient = null;
            }
            finally
            {
                _pipeSemaphore.Release();
            }
        }

        private async Task TryDrainResponseAsync(int timeoutMs = 300)
        {
            try
            {
                using var readCts = new CancellationTokenSource(timeoutMs);
                await ReadFrameInternalAsync(readCts.Token);
            }
            catch (OperationCanceledException)
            {
                // Benign timeout: Discord may not respond immediately or has no event to push
            }
            catch (Exception)
            {
                // Stream error indicates connection lost
                _isConnected = false;
                try { _pipeClient?.Dispose(); } catch { }
                _pipeClient = null;
            }
        }

        public async Task ClearPresenceAsync()
        {
            if (!_isConnected || _pipeClient == null || !_pipeClient.IsConnected) return;

            await _pipeSemaphore.WaitAsync();
            try
            {
                if (!_isConnected || _pipeClient == null || !_pipeClient.IsConnected) return;

                var clearPayload = new
                {
                    cmd = "SET_ACTIVITY",
                    args = new
                    {
                        pid = Process.GetCurrentProcess().Id,
                        activity = (object?)null
                    },
                    nonce = Guid.NewGuid().ToString("N")
                };

                await WriteFrameInternalAsync(1, clearPayload);
                await TryDrainResponseAsync(timeoutMs: 300);
            }
            catch { }
            finally
            {
                _pipeSemaphore.Release();
            }
        }

        private async Task WriteFrameInternalAsync(int opcode, object payload)
        {
            if (_pipeClient == null || !_pipeClient.IsConnected) return;

            string json = JsonSerializer.Serialize(payload, JsonOpts);
            byte[] bytes = Encoding.UTF8.GetBytes(json);
            int length = bytes.Length;

            byte[] header = new byte[8];
            BitConverter.TryWriteBytes(header.AsSpan(0, 4), opcode);
            BitConverter.TryWriteBytes(header.AsSpan(4, 4), length);

            await _pipeClient.WriteAsync(header, 0, 8);
            await _pipeClient.WriteAsync(bytes, 0, length);
            await _pipeClient.FlushAsync();
        }

        private async Task<(int opcode, string json)> ReadFrameInternalAsync(CancellationToken ct = default)
        {
            if (_pipeClient == null || !_pipeClient.IsConnected) return (-1, string.Empty);

            byte[] header = new byte[8];
            int headerRead = 0;
            while (headerRead < 8)
            {
                int r = await _pipeClient.ReadAsync(header.AsMemory(headerRead, 8 - headerRead), ct);
                if (r <= 0) return (-1, string.Empty);
                headerRead += r;
            }

            int opcode = BitConverter.ToInt32(header, 0);
            int length = BitConverter.ToInt32(header, 4);

            if (length <= 0 || length > 65536) return (opcode, string.Empty);

            byte[] body = new byte[length];
            int bodyRead = 0;
            while (bodyRead < length)
            {
                int r = await _pipeClient.ReadAsync(body.AsMemory(bodyRead, length - bodyRead), ct);
                if (r <= 0) break;
                bodyRead += r;
            }

            if (bodyRead < length) return (opcode, string.Empty);

            string json = Encoding.UTF8.GetString(body, 0, bodyRead);
            return (opcode, json);
        }

        public void Dispose()
        {
            _cts?.Cancel();
            try
            {
                _ = ClearPresenceAsync();
                _pipeClient?.Dispose();
                _pipeSemaphore?.Dispose();
            }
            catch { }
        }
    }
}
