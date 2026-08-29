using System;
using System.IO;
using System.Media;
using System.Threading.Tasks;

namespace PalLauncher.Services
{
    public class AudioService : IDisposable
    {
        private SoundPlayer? _hoverPlayer;
        private SoundPlayer? _clickPlayer;
        private MemoryStream? _hoverStream;
        private MemoryStream? _clickStream;
        private bool _isLoaded;

        public bool IsSoundEnabled { get; set; } = true;
        public float Volume { get; set; } = 0.20f; // 20% Volume limit

        public void Initialize()
        {
            if (_isLoaded) return;

            try
            {
                string baseDir = AppDomain.CurrentDomain.BaseDirectory;
                string hoverPath = Path.Combine(baseDir, "Assets", "hover.wav");
                string clickPath = Path.Combine(baseDir, "Assets", "click.wav");

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
                    short sample = BitConverter.ToInt16(bytes, i);
                    short scaledSample = (short)Math.Clamp(sample * volume, short.MinValue, short.MaxValue);
                    byte[] sampleBytes = BitConverter.GetBytes(scaledSample);
                    bytes[i] = sampleBytes[0];
                    bytes[i + 1] = sampleBytes[1];
                }
            }

            return new MemoryStream(bytes);
        }

        public void PlayHover()
        {
            if (!IsSoundEnabled || _hoverPlayer == null) return;

            Task.Run(() =>
            {
                try
                {
                    if (_hoverStream != null && _hoverStream.CanSeek)
                    {
                        _hoverStream.Position = 0;
                    }
                    _hoverPlayer.Play();
                }
                catch { }
            });
        }

        public void PlayClick()
        {
            if (!IsSoundEnabled || _clickPlayer == null) return;

            Task.Run(() =>
            {
                try
                {
                    if (_clickStream != null && _clickStream.CanSeek)
                    {
                        _clickStream.Position = 0;
                    }
                    _clickPlayer.Play();
                }
                catch { }
            });
        }

        public void Dispose()
        {
            _hoverPlayer?.Dispose();
            _clickPlayer?.Dispose();
            _hoverStream?.Dispose();
            _clickStream?.Dispose();
            _hoverPlayer = null;
            _clickPlayer = null;
            _hoverStream = null;
            _clickStream = null;
            _isLoaded = false;
            GC.SuppressFinalize(this);
        }
    }
}
