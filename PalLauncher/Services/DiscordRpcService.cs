using System;
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
        private readonly ILogService _logService;
        private NamedPipeClientStream? _pipeClient;
        private CancellationTokenSource? _cts;
        private string _applicationId = "383226320970055681"; // Registered Discord Rich Presence App ID
        private bool _isConnected;
        private DateTime? _sessionStartTime;
        private readonly SemaphoreSlim _pipeSemaphore = new(1, 1);

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
                        await UpdatePresenceAsync("Using PalOdyssey Launcher", "Preparing Expedition", isPlaying: false);
                    }
                }

                try
                {
                    await Task.Delay(10000, ct); // Reconnect / heartbeat check
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

                        // Read Handshake response (Opcode 1 = Frame/Ready)
                        using var readCts = new CancellationTokenSource(1500);
                        var (op, json) = await ReadFrameInternalAsync(readCts.Token);
                        if (op == 1 || (!string.IsNullOrEmpty(json) && json.Contains("READY")))
                        {
                            _isConnected = true;
                            _logService.LogInfo($"Connected to Discord Rich Presence IPC ({pipeName}).", "DiscordRPC");
                            return true;
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

        public async Task UpdatePresenceAsync(string details, string state, bool isPlaying = false)
        {
            if (!_isConnected || _pipeClient == null || !_pipeClient.IsConnected)
            {
                return;
            }

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

                var activityPayload = new
                {
                    cmd = "SET_ACTIVITY",
                    args = new
                    {
                        pid = Process.GetCurrentProcess().Id,
                        activity = new
                        {
                            details = details,
                            state = state,
                            timestamps = timestampsObj,
                            instance = false
                        }
                    },
                    nonce = Guid.NewGuid().ToString("N")
                };

                await WriteFrameInternalAsync(1, activityPayload);

                // Drain response frame from Discord so pipe stays clear
                using var readCts = new CancellationTokenSource(1000);
                await ReadFrameInternalAsync(readCts.Token);
            }
            catch (Exception ex)
            {
                _isConnected = false;
                _logService.LogWarning("Discord presence update notice: " + ex.Message, "DiscordRPC");
            }
            finally
            {
                _pipeSemaphore.Release();
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

                using var readCts = new CancellationTokenSource(1000);
                await ReadFrameInternalAsync(readCts.Token);
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
            int read = await _pipeClient.ReadAsync(header, 0, 8, ct);
            if (read < 8) return (-1, string.Empty);

            int opcode = BitConverter.ToInt32(header, 0);
            int length = BitConverter.ToInt32(header, 4);

            if (length <= 0 || length > 65536) return (opcode, string.Empty);

            byte[] body = new byte[length];
            int totalRead = 0;
            while (totalRead < length)
            {
                int r = await _pipeClient.ReadAsync(body, totalRead, length - totalRead, ct);
                if (r <= 0) break;
                totalRead += r;
            }

            string json = Encoding.UTF8.GetString(body, 0, totalRead);
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
