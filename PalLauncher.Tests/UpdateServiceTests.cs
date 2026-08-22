using System;
using System.IO;
using System.Security.Cryptography;
using System.Text;
using System.Threading.Tasks;
using PalLauncher.Models;
using PalLauncher.Services;
using Xunit;

namespace PalLauncher.Tests
{
    public class UpdateServiceTests : IDisposable
    {
        private readonly string _testDirectory;
        private readonly LogService _logService;
        private readonly UpdateService _updateService;

        public UpdateServiceTests()
        {
            _testDirectory = Path.Combine(Path.GetTempPath(), "PalLauncherTests_" + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(_testDirectory);

            _logService = new LogService();
            _updateService = new UpdateService(_logService);
        }

        public void Dispose()
        {
            try
            {
                if (Directory.Exists(_testDirectory))
                {
                    Directory.Delete(_testDirectory, true);
                }
            }
            catch { }
        }

        [Fact]
        public void ComputeFileSha256_CalculatesAccurateHash()
        {
            // Arrange
            string filePath = Path.Combine(_testDirectory, "test.pak");
            string testContent = "Palworld Mod Pak Content Example 12345";
            byte[] bytes = Encoding.UTF8.GetBytes(testContent);
            File.WriteAllBytes(filePath, bytes);

            using var sha = SHA256.Create();
            byte[] expectedBytes = sha.ComputeHash(bytes);
            string expectedHex = Convert.ToHexString(expectedBytes).ToLowerInvariant();

            // Act
            string actualHex = _updateService.ComputeFileSha256(filePath);

            // Assert
            Assert.Equal(expectedHex, actualHex);
        }

        [Fact]
        public async Task CheckForUpdates_DetectsMissingAndUpToDateMods()
        {
            // Arrange
            string paksDir = Path.Combine(_testDirectory, "Pal", "Content", "Paks", "~mods");
            Directory.CreateDirectory(paksDir);

            // Create an up to date file
            string upToDateModPath = Path.Combine(paksDir, "InstalledMod.pak");
            string modContent = "Verified Mod Content";
            await File.WriteAllTextAsync(upToDateModPath, modContent, Encoding.UTF8);
            string modSha = _updateService.ComputeFileSha256(upToDateModPath);

            // Create a manifest JSON pointing to installed mod and a missing mod
            string manifestPath = Path.Combine(_testDirectory, "version.json");
            string manifestJson = $$"""
            {
                "manifestVersion": "1.0.0",
                "gameVersion": "0.3.x",
                "mods": [
                    {
                        "id": "installed-mod",
                        "name": "Installed Mod",
                        "version": "1.0.0",
                        "downloadUrl": "https://example.com/installed.pak",
                        "relativeInstallPath": "Pal\\Content\\Paks\\~mods\\InstalledMod.pak",
                        "sha256": "{{modSha}}",
                        "sizeBytes": 100,
                        "isRequired": true
                    },
                    {
                        "id": "missing-mod",
                        "name": "Missing Mod",
                        "version": "1.1.0",
                        "downloadUrl": "https://example.com/missing.pak",
                        "relativeInstallPath": "Pal\\Content\\Paks\\~mods\\MissingMod.pak",
                        "sha256": "1234567890abcdef",
                        "sizeBytes": 200,
                        "isRequired": true
                    }
                ]
            }
            """;
            await File.WriteAllTextAsync(manifestPath, manifestJson);

            // Act
            var mods = await _updateService.CheckForUpdatesAsync(manifestPath, _testDirectory);

            // Assert
            Assert.Equal(2, mods.Count);
            
            var mod1 = mods.Find(m => m.Id == "installed-mod");
            Assert.NotNull(mod1);
            Assert.Equal(ModStatus.UpToDate, mod1.Status);

            var mod2 = mods.Find(m => m.Id == "missing-mod");
            Assert.NotNull(mod2);
            Assert.Equal(ModStatus.Missing, mod2.Status);
        }
    }
}
