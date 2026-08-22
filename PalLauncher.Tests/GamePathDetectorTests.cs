using System;
using System.IO;
using PalLauncher.Services;
using Xunit;

namespace PalLauncher.Tests
{
    public class GamePathDetectorTests : IDisposable
    {
        private readonly string _mockGameDir;
        private readonly LogService _logService;
        private readonly GamePathDetector _detector;

        public GamePathDetectorTests()
        {
            _mockGameDir = Path.Combine(Path.GetTempPath(), "PalworldMock_" + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(_mockGameDir);

            _logService = new LogService();
            _detector = new GamePathDetector(_logService);
        }

        public void Dispose()
        {
            try
            {
                if (Directory.Exists(_mockGameDir))
                {
                    Directory.Delete(_mockGameDir, true);
                }
            }
            catch { }
        }

        [Fact]
        public void ValidatePath_WithValidPalworldStructure_ReturnsValidInfo()
        {
            // Arrange: create mock structure
            string exePath = Path.Combine(_mockGameDir, "Palworld.exe");
            File.WriteAllText(exePath, "mock binary");

            string paksDir = Path.Combine(_mockGameDir, "Pal", "Content", "Paks");
            Directory.CreateDirectory(paksDir);

            // Act
            var info = _detector.ValidatePath(_mockGameDir);

            // Assert
            Assert.True(info.IsValid);
            Assert.Equal(_mockGameDir, info.GameRootPath);
            Assert.Equal(exePath, info.ClientExecutablePath);
            Assert.Equal(paksDir, info.PaksDirectoryPath);
        }

        [Fact]
        public void ValidatePath_WithInvalidDirectory_ReturnsInvalid()
        {
            // Arrange
            string nonExistentDir = Path.Combine(_mockGameDir, "NonExistentFolder");

            // Act
            var info = _detector.ValidatePath(nonExistentDir);

            // Assert
            Assert.False(info.IsValid);
        }
    }
}
