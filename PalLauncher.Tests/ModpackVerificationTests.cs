using System;
using System.IO;
using System.Security.Cryptography;
using System.Text.Json;
using PalLauncher.Models;
using Xunit;

namespace PalLauncher.Tests
{
    public class ModpackVerificationTests
    {
        [Fact]
        public void BaseModpack_AllManifestFiles_ExistAndMatchChecksums()
        {
            string manifestPath = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "..", "..", "..", "..", "PalLauncher", "SampleData", "version.json");
            string fullManifestPath = Path.GetFullPath(manifestPath);

            string modpackRoot = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "..", "..", "..", "..", "Modpack");
            string fullModpackRoot = Path.GetFullPath(modpackRoot);

            Assert.True(File.Exists(fullManifestPath), $"Manifest not found at {fullManifestPath}");
            Assert.True(Directory.Exists(fullModpackRoot), $"Modpack directory not found at {fullModpackRoot}");

            string json = File.ReadAllText(fullManifestPath);
            var manifest = JsonSerializer.Deserialize<ModManifest>(json, new JsonSerializerOptions { PropertyNameCaseInsensitive = true });

            Assert.NotNull(manifest);
            Assert.Equal(10, manifest.Mods.Count);

            using var sha256 = SHA256.Create();

            foreach (var mod in manifest.Mods)
            {
                string targetFile = Path.Combine(fullModpackRoot, mod.RelativeInstallPath);
                Assert.True(File.Exists(targetFile), $"Mod '{mod.Name}' expected file at '{targetFile}' does not exist!");

                byte[] bytes = File.ReadAllBytes(targetFile);
                string computedSha = Convert.ToHexString(sha256.ComputeHash(bytes)).ToLowerInvariant();

                Assert.Equal(mod.Sha256Checksum.ToLowerInvariant(), computedSha);
                Assert.Equal(bytes.Length, mod.SizeBytes);
            }
        }

        [Fact]
        public void BaseModpack_ModsTxt_ContainsEnabledCoreMods()
        {
            string modsTxtPath = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "..", "..", "..", "..", "Modpack", "Pal", "Binaries", "Win64", "Mods", "mods.txt");
            string fullModsTxtPath = Path.GetFullPath(modsTxtPath);

            Assert.True(File.Exists(fullModsTxtPath));

            string content = File.ReadAllText(fullModsTxtPath);
            Assert.Contains("ExpeditionXP : 1", content);
            Assert.Contains("DarnMenu : 1", content);
            Assert.Contains("DarnToasts : 1", content);
            Assert.Contains("LevelLock : 1", content);
            Assert.Contains("WeaponProficiency : 1", content);
            Assert.Contains("PalworldBorealisEngineFix : 1", content);
            Assert.Contains("PalOlympicsFPSBooster : 1", content);
            Assert.Contains("RawMouseInput : 1", content);
            Assert.Contains("PlayerCustomizationSuite : 1", content);
        }
    }
}
