using System;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text.Json;
using System.Threading;

namespace PalOdysseyAudioPlayer;

internal static partial class Program
{
    private const string MutexName = "PalOdysseyAudioPlayer.SingleInstance";
    private const int TickMilliseconds = 25;
    private static readonly AudioChannel Bgm = new("PalOdysseyEventBgm");
    private static readonly AudioChannel Sfx = new("PalOdysseyEventSfx");
    private static string _root = "";
    private static string _audioDirectory = "";
    private static string _statePath = "";
    private static string _heartbeatPath = "";
    private static DateTime _lastStateWrite = DateTime.MinValue;
    private static DateTime _lastHeartbeat = DateTime.MinValue;
    private static DateTime _lastProcessCheck = DateTime.MinValue;
    private static readonly DateTime StartedAt = DateTime.UtcNow;
    private static int _missingGameChecks;
    private static long _lastSfxSequence = -1;

    [LibraryImport("winmm.dll", EntryPoint = "mciSendStringW", StringMarshalling = StringMarshalling.Utf16)]
    private static partial int MciSendString(string command, nint returnValue, uint returnLength, nint callback);

    [STAThread]
    private static void Main()
    {
        using var mutex = new Mutex(true, MutexName, out bool createdNew);
        if (!createdNew)
            return;

        _root = AppContext.BaseDirectory.TrimEnd(Path.DirectorySeparatorChar);
        _audioDirectory = Path.GetFullPath(Path.Combine(_root, "..", "audio"));
        _statePath = Path.GetFullPath(Path.Combine(_root, "..", "audio_state.json"));
        _heartbeatPath = Path.GetFullPath(Path.Combine(_root, "..", "player_heartbeat.txt"));

        AppDomain.CurrentDomain.ProcessExit += (_, _) => Shutdown();
        while (true)
        {
            DateTime now = DateTime.UtcNow;
            ReadStateIfChanged();
            Bgm.Tick(TickMilliseconds);
            WriteHeartbeat(now);
            if (ShouldExit(now))
                break;
            Thread.Sleep(TickMilliseconds);
        }

        Shutdown();
    }

    private static void ReadStateIfChanged()
    {
        try
        {
            if (!File.Exists(_statePath))
                return;
            DateTime writeTime = File.GetLastWriteTimeUtc(_statePath);
            if (writeTime == _lastStateWrite)
                return;

            using JsonDocument document = JsonDocument.Parse(File.ReadAllText(_statePath));
            JsonElement root = document.RootElement;
            string state = GetString(root, "bgm_state", "stop");
            string track = GetString(root, "bgm_track", "");
            bool loop = GetBoolean(root, "bgm_loop", true);
            double volume = GetDouble(root, "bgm_volume", 0.65);
            int fadeMilliseconds = (int)Math.Round(GetDouble(root, "fade_seconds", 1.0) * 1000.0);

            if (state.Equals("play", StringComparison.OrdinalIgnoreCase) && track.Length > 0)
                Bgm.Play(ResolveAudioPath(track), loop, volume, fadeMilliseconds);
            else
                Bgm.Stop(fadeMilliseconds);

            long sequence = GetLong(root, "sfx_sequence", 0);
            if (sequence != _lastSfxSequence)
            {
                _lastSfxSequence = sequence;
                string sfxTrack = GetString(root, "sfx_track", "");
                if (sequence > 0 && sfxTrack.Length > 0)
                    Sfx.PlayOneShot(ResolveAudioPath(sfxTrack), GetDouble(root, "sfx_volume", 0.75));
            }

            _lastStateWrite = writeTime;
        }
        catch
        {
            // Atomic state replacement can still race antivirus/file indexing; retry next tick.
        }
    }

    private static string ResolveAudioPath(string track)
    {
        string safeName = Path.GetFileName(track);
        return Path.Combine(_audioDirectory, safeName);
    }

    private static string GetString(JsonElement root, string name, string fallback) =>
        root.TryGetProperty(name, out JsonElement value) && value.ValueKind == JsonValueKind.String
            ? value.GetString() ?? fallback
            : fallback;

    private static bool GetBoolean(JsonElement root, string name, bool fallback) =>
        root.TryGetProperty(name, out JsonElement value) &&
        (value.ValueKind == JsonValueKind.True || value.ValueKind == JsonValueKind.False)
            ? value.GetBoolean()
            : fallback;

    private static double GetDouble(JsonElement root, string name, double fallback) =>
        root.TryGetProperty(name, out JsonElement value) && value.TryGetDouble(out double result)
            ? result
            : fallback;

    private static long GetLong(JsonElement root, string name, long fallback) =>
        root.TryGetProperty(name, out JsonElement value) && value.TryGetInt64(out long result)
            ? result
            : fallback;

    private static void WriteHeartbeat(DateTime now)
    {
        if (now - _lastHeartbeat < TimeSpan.FromSeconds(2))
            return;
        try
        {
            File.WriteAllText(_heartbeatPath, DateTimeOffset.UtcNow.ToUnixTimeSeconds().ToString());
            _lastHeartbeat = now;
        }
        catch { }
    }

    private static bool ShouldExit(DateTime now)
    {
        if (now - _lastProcessCheck < TimeSpan.FromSeconds(1))
            return false;
        _lastProcessCheck = now;
        bool running = IsRunning("Palworld-Win64-Shipping") || IsRunning("Pal-Win64-Shipping") ||
                       IsRunning("Palworld") || IsRunning("Pal");
        if (running)
        {
            _missingGameChecks = 0;
            return false;
        }
        if (now - StartedAt < TimeSpan.FromSeconds(60))
            return false;
        return ++_missingGameChecks >= 10;
    }

    private static bool IsRunning(string processName)
    {
        Process[] processes = Process.GetProcessesByName(processName);
        foreach (Process process in processes)
            process.Dispose();
        return processes.Length > 0;
    }

    private static void Shutdown()
    {
        Bgm.Close();
        Sfx.Close();
        try { File.Delete(_heartbeatPath); } catch { }
    }

    private sealed class AudioChannel(string alias)
    {
        private string _track = "";
        private double _volume;
        private double _targetVolume;
        private int _fadeMilliseconds = 1000;
        private bool _stopWhenSilent;

        public void Play(string path, bool loop, double volume, int fadeMilliseconds)
        {
            if (!File.Exists(path))
                return;
            volume = Math.Clamp(volume, 0.0, 1.0);
            _fadeMilliseconds = Math.Clamp(fadeMilliseconds, 0, 10_000);
            if (!path.Equals(_track, StringComparison.OrdinalIgnoreCase))
            {
                Close();
                string deviceType = Path.GetExtension(path).Equals(".wav", StringComparison.OrdinalIgnoreCase)
                    ? "waveaudio"
                    : "mpegvideo";
                if (MciSendString($"open \"{path}\" type {deviceType} alias {alias}", 0, 0, 0) != 0)
                    return;
                _track = path;
                _volume = _fadeMilliseconds == 0 ? volume : 0.0;
                SetVolume(_volume);
                MciSendString(loop ? $"play {alias} repeat" : $"play {alias}", 0, 0, 0);
            }
            _targetVolume = volume;
            _stopWhenSilent = false;
            if (_fadeMilliseconds == 0)
            {
                _volume = _targetVolume;
                SetVolume(_volume);
            }
        }

        public void PlayOneShot(string path, double volume)
        {
            // A repeated SFX commonly uses the same file; reopen it so playback
            // restarts from the beginning instead of merely updating volume.
            Close();
            Play(path, false, volume, 0);
        }

        public void Stop(int fadeMilliseconds)
        {
            if (_track.Length == 0)
                return;
            _fadeMilliseconds = Math.Clamp(fadeMilliseconds, 0, 10_000);
            _targetVolume = 0.0;
            _stopWhenSilent = true;
            if (_fadeMilliseconds == 0)
                Close();
        }

        public void Tick(int elapsedMilliseconds)
        {
            if (_track.Length == 0 || Math.Abs(_volume - _targetVolume) < 0.001)
            {
                if (_stopWhenSilent && _volume <= 0.001)
                    Close();
                return;
            }
            double step = _fadeMilliseconds <= 0 ? 1.0 : (double)elapsedMilliseconds / _fadeMilliseconds;
            _volume += Math.Clamp(_targetVolume - _volume, -step, step);
            _volume = Math.Clamp(_volume, 0.0, 1.0);
            SetVolume(_volume);
            if (_stopWhenSilent && _volume <= 0.001)
                Close();
        }

        private void SetVolume(double value) =>
            MciSendString($"setaudio {alias} volume to {(int)Math.Round(value * 1000.0)}", 0, 0, 0);

        public void Close()
        {
            if (_track.Length > 0)
            {
                MciSendString($"stop {alias}", 0, 0, 0);
                MciSendString($"close {alias}", 0, 0, 0);
            }
            _track = "";
            _volume = 0.0;
            _targetVolume = 0.0;
            _stopWhenSilent = false;
        }
    }
}
