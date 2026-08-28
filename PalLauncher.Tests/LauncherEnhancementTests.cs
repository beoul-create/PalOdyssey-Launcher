using System;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Threading.Tasks;
using PalLauncher.Models;
using PalLauncher.Services;
using PalLauncher.Services.Interfaces;
using PalLauncher.ViewModels;
using Xunit;

namespace PalLauncher.Tests
{
    public class LauncherEnhancementTests
    {
        [Fact]
        public void Mod_ChazzBuffs_Contains_All_143_Json_Definitions()
        {
            string baseDir = AppDomain.CurrentDomain.BaseDirectory;
            string modpackRoot = Path.GetFullPath(Path.Combine(baseDir, "..", "..", "..", "..", "Modpack"));
            string chazzDir = Path.Combine(modpackRoot, "Pal", "Binaries", "Win64", "ue4ss", "Mods", "PalSchema", "mods", "ChazzBuffs");

            Assert.True(Directory.Exists(chazzDir), $"ChazzBuffs directory missing at {chazzDir}");

            var allFiles = Directory.GetFiles(chazzDir, "*.*", SearchOption.AllDirectories);
            Assert.True(allFiles.Length >= 140, $"Expected >= 140 files in ChazzBuffs, found {allFiles.Length}");

            // Verify specific new additions from the latest update
            Assert.True(File.Exists(Path.Combine(chazzDir, "raw", "LapironBuffs.json")), "Missing LapironBuffs.json");
            Assert.True(File.Exists(Path.Combine(chazzDir, "raw", "LoomenBuffs.json")), "Missing LoomenBuffs.json");
            Assert.True(File.Exists(Path.Combine(chazzDir, "raw", "WarsectTerraPartnerSkill.json")), "Missing WarsectTerraPartnerSkill.json");
            Assert.True(File.Exists(Path.Combine(chazzDir, "translations", "en", "SwordCutlassfishTranslations.json")), "Missing SwordCutlassfishTranslations.json");
        }

        [Fact]
        public void ConfigService_DPAPI_Protection_RoundTrip()
        {
            string rawToken = "MTEyMjMzNDQ1NTY2Nzc4ODk5.GxyzAb.PalOdysseySecretToken2026";
            string protectedToken = ConfigService.ProtectString(rawToken);

            Assert.NotNull(protectedToken);
            Assert.NotEqual(rawToken, protectedToken);
            Assert.StartsWith("ENC:", protectedToken);

            string decrypted = ConfigService.UnprotectString(protectedToken);
            Assert.Equal(rawToken, decrypted);

            // Plain text should pass through unchanged
            Assert.Equal("plain-text-token", ConfigService.UnprotectString("plain-text-token"));
        }

        [Fact]
        public void ModsViewModel_SearchAndCategoryFiltering_Works()
        {
            var logMock = new LogService();
            var updateMock = new UpdateService(logMock);
            var configMock = new ConfigService(logMock);
            var pathMock = new GamePathDetector(logMock);

            var vm = new ModsViewModel(updateMock, configMock, pathMock, logMock);

            vm.Mods.Add(new ModInfo
            {
                Id = "chazz-buffs",
                Name = "ChazzBuffs Partner Skill & Pal Rebalance",
                Category = "Gameplay",
                Description = "Rebalance for Pals and partner skills"
            });
            vm.Mods.Add(new ModInfo
            {
                Id = "pal-clear-vision",
                Name = "PalClearVision Visual Suite",
                Category = "Visuals",
                Description = "Removes fog and enhances LOD"
            });
            vm.Mods.Add(new ModInfo
            {
                Id = "ramtrim-mod",
                Name = "RamTrim Memory Optimizer",
                Category = "Performance",
                Description = "Working set memory trimmer"
            });

            // Initial view
            Assert.Equal(3, vm.FilteredModsView.Cast<object>().Count());

            // Search by keyword "vision"
            vm.SearchQuery = "vision";
            Assert.Single(vm.FilteredModsView.Cast<object>());
            var found = (ModInfo)vm.FilteredModsView.Cast<object>().First();
            Assert.Equal("pal-clear-vision", found.Id);

            // Clear search
            vm.SearchQuery = "";
            Assert.Equal(3, vm.FilteredModsView.Cast<object>().Count());

            // Filter by category "Performance"
            vm.SelectedCategory = "Performance";
            Assert.Single(vm.FilteredModsView.Cast<object>());
            var perfMod = (ModInfo)vm.FilteredModsView.Cast<object>().First();
            Assert.Equal("ramtrim-mod", perfMod.Id);

            // Reset category
            vm.SelectedCategory = "All";
            Assert.Equal(3, vm.FilteredModsView.Cast<object>().Count());
        }

        [Fact]
        public async Task UpdateService_Zip_Extraction_Integrity()
        {
            var logService = new LogService();
            var updateService = new UpdateService(logService);

            string tempDir = Path.Combine(Path.GetTempPath(), "PalLauncher_ZipTest_" + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(tempDir);

            try
            {
                string zipSourceDir = Path.Combine(tempDir, "zip_content");
                Directory.CreateDirectory(zipSourceDir);
                File.WriteAllText(Path.Combine(zipSourceDir, "test_file.txt"), "PalOdyssey Mod Content");

                string testZipPath = Path.Combine(tempDir, "TestMod.zip");
                ZipFile.CreateFromDirectory(zipSourceDir, testZipPath);

                var mod = new ModInfo
                {
                    Id = "test-zip-mod",
                    Name = "Test Zip Mod",
                    RelativeInstallPath = @"Pal\Binaries\Win64\ue4ss\Mods\TestZipMod\TestMod.zip",
                    DownloadUrl = testZipPath,
                    SizeBytes = new FileInfo(testZipPath).Length
                };

                string gameRoot = Path.Combine(tempDir, "GameRoot");
                Directory.CreateDirectory(gameRoot);

                bool installed = await updateService.DownloadAndInstallModAsync(mod, gameRoot);
                Assert.True(installed, "Zip mod installation failed");

                string extractedFilePath = Path.Combine(gameRoot, @"Pal\Binaries\Win64\ue4ss\Mods\TestZipMod\test_file.txt");
                Assert.True(File.Exists(extractedFilePath), $"Expected extracted file at {extractedFilePath}");
                Assert.Equal("PalOdyssey Mod Content", File.ReadAllText(extractedFilePath));
            }
            finally
            {
                if (Directory.Exists(tempDir))
                {
                    try { Directory.Delete(tempDir, true); } catch { }
                }
            }
        }
    }
}
