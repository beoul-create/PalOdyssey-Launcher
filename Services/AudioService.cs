using System;
using System.Buffers.Binary;
using System.IO;
using System.Media;
using System.Windows.Media;
using System.Windows.Threading;

namespace PalLauncher.Services
{
    public class AudioService : IDisposable
    {
        private SoundPlayer? _hoverPlayer;
        private SoundPlayer? _clickPlayer;
        private MediaPlayer? _bgmPlayer;
        private DispatcherTimer? _fadeTimer;
        private MemoryStream? _hoverStream;
        private MemoryStream? _clickStream;
        private bool _isLoaded;

        public bool IsSoundEnabled { get; set; } = true;
        public float Volume { get; set; } = 0.15f; // 15% Sound effect volume
        public float BgmVolume { get; set; } = 0.20f; // 20% Launcher BGM volume (clearly audible background)
        public void Initialize()
        {
            if (_isLoaded) return;

            try
            {
                string baseDir = AppDomain.CurrentDomain.BaseDirectory;
                string hoverPath = Path.Combine(baseDir, "Assets", "hover.wav");
                string clickPath = Path.Combine(baseDir, "Assets", "click.wav");
                string bgmPath = Path.Combine(baseDir, "Assets", "launcher_bgm.mp3");

                if (File.Exists(hoverPath))
                {
                    _hoverStream = LoadScaledWavStream(hoverPath, Volume);
                    _hoverPlayer = new SoundPlayer(_hoverStream);
                    _hoverPlayer.LoadAsync();
                }

                if (File.Exists(clickPath))
                {
                    _clickStream = LoadScaledWavStream(clickPath, Volume);
                    _clickPlayer = new SoundPlayer(_clickStream);
                    _clickPlayer.LoadAsync();
                }

                if (File.Exists(bgmPath))
                {
                    _bgmPlayer = new MediaPlayer();
                    _bgmPlayer.Open(new Uri(bgmPath));
                    _bgmPlayer.Volume = BgmVolume;
                    _bgmPlayer.MediaEnded += (s, e) =>
                    {
                        if (IsSoundEnabled && _bgmPlayer != null)
                        {
                            _bgmPlayer.Position = TimeSpan.Zero;
                            _bgmPlayer.Play();
                        }
                    };
                }

                _isLoaded = true;
            }
            catch (Exception)
            {
                // Non-critical audio init failure
            }
        }

        private static MemoryStream LoadScaledWavStream(string filePath, float volume)
        {
            byte[] bytes = File.ReadAllBytes(filePath);

            // Locate 'data' subchunk in RIFF WAV
            int dataPos = -1;
            for (int i = 0; i < bytes.Length - 4; i++)
            {
                if (bytes[i] == 'd' && bytes[i + 1] == 'a' && bytes[i + 2] == 't' && bytes[i + 3] == 'a')
                {
                    dataPos = i + 8;
                    break;
                }
            }

            if (dataPos != -1 && Math.Abs(volume - 1.0f) > 0.01f)
            {
                // Scale 16-bit PCM samples
                for (int i = dataPos; i < bytes.Length - 1; i += 2)
                {
                    short sample = BinaryPrimitives.ReadInt16LittleEndian(bytes.AsSpan(i, 2));
                    short scaledSample = (short)Math.Clamp(sample * volume, short.MinValue, short.MaxValue);
                    BinaryPrimitives.WriteInt16LittleEndian(bytes.AsSpan(i, 2), scaledSample);
                }
            }

            return new MemoryStream(bytes);
        }

        public void PlayHover()
        {
            if (!IsSoundEnabled || _hoverPlayer == null) return;

            try { _hoverPlayer.Play(); } catch { }
        }

        public void PlayClick()
        {
            if (!IsSoundEnabled || _clickPlayer == null) return;

            try { _clickPlayer.Play(); } catch { }
        }

        public void StartBgm()
        {
            if (!IsSoundEnabled || _bgmPlayer == null) return;

            try
            {
                _fadeTimer?.Stop();
                _bgmPlayer.Volume = BgmVolume;
                _bgmPlayer.Position = TimeSpan.Zero;
                _bgmPlayer.Play();
            }
            catch { }
        }

        public void SetBgmVolume(float volume)
        {
            BgmVolume = Math.Clamp(volume, 0.0f, 1.0f);
            if (_bgmPlayer != null)
            {
                _bgmPlayer.Volume = BgmVolume;
            }
        }

        public void StopBgm()
        {
            try
            {
                _fadeTimer?.Stop();
                _bgmPlayer?.Stop();
            }
            catch { }
        }

        public void FadeOutBgm(double durationSeconds = 1.5)
        {
            if (_bgmPlayer == null) return;

            try
            {
                _fadeTimer?.Stop();
                double startVol = _bgmPlayer.Volume;
                int steps = 25;
                double stepDurationMs = (durationSeconds * 1000.0) / steps;
                double volDelta = startVol / steps;

                _fadeTimer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(stepDurationMs) };
                _fadeTimer.Tick += (s, e) =>
                {
                    if (_bgmPlayer == null)
                    {
                        _fadeTimer?.Stop();
                        return;
                    }

                    double next = _bgmPlayer.Volume - volDelta;
                    if (next <= 0.01)
                    {
                        _bgmPlayer.Volume = 0;
                        _bgmPlayer.Stop();
                        _fadeTimer?.Stop();
                    }
                    else
                    {
                        _bgmPlayer.Volume = next;
                    }
                };
                _fadeTimer.Start();
            }
            catch
            {
                StopBgm();
            }
        }

        public void Dispose()
        {
            _fadeTimer?.Stop();
            _bgmPlayer?.Close();
            _hoverPlayer?.Dispose();
            _clickPlayer?.Dispose();
            _hoverStream?.Dispose();
            _clickStream?.Dispose();
            _bgmPlayer = null;
            _fadeTimer = null;
            _hoverPlayer = null;
            _clickPlayer = null;
            _hoverStream = null;
            _clickStream = null;
            _isLoaded = false;
            GC.SuppressFinalize(this);
        }
    }
}
