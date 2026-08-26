using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using Xunit;

namespace PalLauncher.Tests
{
    public class IndividualModIntegrityTests
    {
        private readonly string _modpackRoot;
        private readonly string _modsDir;
        private readonly string _paksDir;

        public IndividualModIntegrityTests()
        {
            _modpackRoot = Path.GetFullPath(Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "..", "..", "..", "..", "Modpack"));
            _modsDir = Path.Combine(_modpackRoot, "Pal", "Binaries", "Win64", "ue4ss", "Mods");
            _paksDir = Path.Combine(_modpackRoot, "Pal", "Content", "Paks", "~mods");
        }

        [Fact]
        public void Mod_QuickDeposit_IntegrityAndScriptArchitecture()
        {
            string quickDepositDir = Path.Combine(_modsDir, "QuickDeposit");
            Assert.True(Directory.Exists(quickDepositDir), "QuickDeposit mod directory is missing!");

            string mainLua = Path.Combine(quickDepositDir, "Scripts", "main.lua");
            Assert.True(File.Exists(mainLua), "QuickDeposit main.lua is missing!");

            string configLua = Path.Combine(quickDepositDir, "Scripts", "config.lua");
            Assert.True(File.Exists(configLua), "QuickDeposit config.lua is missing!");

            string schemaLua = Path.Combine(_modsDir, "shared", "DarnMenu_schema_QuickDeposit.lua");
            Assert.True(File.Exists(schemaLua), "QuickDeposit DarnMenu schema is missing!");

            string content = File.ReadAllText(mainLua);

            // Verify GameThread marshalling
            Assert.Contains("ExecuteInGameThread", content);

            // Verify Palworld native RPC dispatchers
            Assert.Contains("RequestQuickMoveToBelongBaseCampContainer", content);
            Assert.Contains("RequestQuickMoveItemsToBelongBaseCamp", content);

            // Verify intelligent multi-chest fallback scanner
            Assert.Contains("ScanAndDepositToNearbyChests", content);
            Assert.Contains("PalMapObjectItemChestModel", content);

            // Verify toast feedback integration
            Assert.Contains("DarnToasts", content);
            Assert.Contains("SendToast", content);
        }

        [Fact]
        public void Mod_CleanHUD_Integrity()
        {
            string mainLua = Path.Combine(_modsDir, "CleanHUD", "Scripts", "main.lua");
            Assert.True(File.Exists(mainLua), "CleanHUD main.lua missing!");

            string content = File.ReadAllText(mainLua);
            Assert.Contains("WBP_Ingame_Version", content);
            Assert.Contains("WBP_TitleScreen", content);
            Assert.Contains("WBP_InGameHUD", content);
            Assert.Contains("SetVisibility(2)", content); // Collapsed
        }

        [Fact]
        public void Mod_DarnMenu_Integrity()
        {
            string darnMenuDir = Path.Combine(_modsDir, "DarnMenu", "Scripts");
            Assert.True(Directory.Exists(darnMenuDir), "DarnMenu Scripts dir missing!");

            string[] requiredFiles = { "main.lua", "ui.lua", "schemas.lua", "say.lua", "writers.lua", "darn.lua" };
            foreach (var file in requiredFiles)
            {
                Assert.True(File.Exists(Path.Combine(darnMenuDir, file)), $"DarnMenu missing {file}!");
            }

            string mainContent = File.ReadAllText(Path.Combine(darnMenuDir, "main.lua"));
            // Verify UI.alive fix is present
            Assert.Contains("UI.alive(menu)", mainContent);
            Assert.DoesNotContain("if not alive(menu) then", mainContent);
        }

        [Fact]
        public void Mod_DarnToasts_Integrity()
        {
            string toastsDir = Path.Combine(_modsDir, "DarnToasts", "Scripts");
            Assert.True(Directory.Exists(toastsDir), "DarnToasts Scripts dir missing!");

            Assert.True(File.Exists(Path.Combine(toastsDir, "main.lua")));
            Assert.True(File.Exists(Path.Combine(toastsDir, "ToastLib.lua")));
            Assert.True(File.Exists(Path.Combine(toastsDir, "darn.lua")));
        }

        [Fact]
        public void Mod_PalClearVision_Integrity()
        {
            string scriptPath = Path.Combine(_modsDir, "PalClearVision", "Scripts", "main.lua");
            Assert.True(File.Exists(scriptPath), "PalClearVision main.lua missing!");

            string content = File.ReadAllText(scriptPath);
            Assert.Contains("r.VolumetricFog", content);
            Assert.Contains("r.SceneColorFringeQuality", content);
            Assert.Contains("r.AspectRatioAxisConstraint", content);
            Assert.Contains("r.TextureStreaming", content);
        }

        [Fact]
        public void Mod_PalboxSearchPlus_Integrity()
        {
            string scriptPath = Path.Combine(_modsDir, "PalboxSearchPlus", "Scripts", "main.lua");
            Assert.True(File.Exists(scriptPath), "PalboxSearchPlus main.lua missing!");

            string content = File.ReadAllText(scriptPath);
            Assert.Contains("PassiveSkillList", content);
            Assert.Contains("ElementType1", content);
            Assert.Contains("SetRenderOpacity", content);
        }

        [Fact]
        public void Mod_PalCinematicStudio_Integrity()
        {
            string scriptPath = Path.Combine(_modsDir, "PalCinematicStudio", "Scripts", "main.lua");
            Assert.True(File.Exists(scriptPath), "PalCinematicStudio main.lua missing!");

            string content = File.ReadAllText(scriptPath);
            Assert.Contains("ToggleDebugCamera", content);
            Assert.Contains("Slomo", content);
            Assert.Contains("ShowHUD", content);
        }

        [Fact]
        public void Mod_ShiningLuckies_Integrity()
        {
            string scriptPath = Path.Combine(_modsDir, "ShiningLuckies", "Scripts", "main.lua");
            Assert.True(File.Exists(scriptPath), "ShiningLuckies main.lua missing!");

            string content = File.ReadAllText(scriptPath);
            Assert.Contains("bRenderCustomDepth", content);
            Assert.Contains("CustomDepthStencilValue", content);
            Assert.Contains("IsRarePal", content);
        }

        [Fact]
        public void Mod_StuckPalRescuer_Integrity()
        {
            string scriptPath = Path.Combine(_modsDir, "StuckPalRescuer", "Scripts", "main.lua");
            Assert.True(File.Exists(scriptPath), "StuckPalRescuer main.lua missing!");

            string content = File.ReadAllText(scriptPath);
            Assert.Contains("K2_SetActorLocationAndRotation", content);
            Assert.Contains("CharacterMovement", content);
            Assert.Contains("StopMovementImmediately", content);
        }

        [Fact]
        public void Mod_WeaponProficiency_LivingArsenal_Integrity()
        {
            string wpDir = Path.Combine(_modsDir, "WeaponProficiency", "Scripts");
            Assert.True(Directory.Exists(wpDir), "WeaponProficiency Scripts dir missing!");

            string[] wpFiles = {
                "main.lua", "progression.lua", "damage.lua", "counting.lua",
                "prestige_ui.lua", "server_durability.lua", "rpc.lua",
                "store.lua", "ui.lua", "weapondata.lua", "adapters.lua"
            };

            foreach (var file in wpFiles)
            {
                Assert.True(File.Exists(Path.Combine(wpDir, file)), $"WeaponProficiency missing {file}!");
            }
        }

        [Fact]
        public void Mod_PalOdysseyOptimizer_Integrity()
        {
            string optDir = Path.Combine(_modsDir, "PalOdysseyOptimizer", "Scripts");
            Assert.True(Directory.Exists(optDir), "PalOdysseyOptimizer Scripts dir missing!");

            string[] optFiles = { "main.lua", "graphics.lua", "memory.lua", "network.lua", "input.lua", "server.lua", "delivery.lua" };
            foreach (var file in optFiles)
            {
                Assert.True(File.Exists(Path.Combine(optDir, file)), $"PalOdysseyOptimizer missing {file}!");
            }

            string deliveryContent = File.ReadAllText(Path.Combine(optDir, "delivery.lua"));
            Assert.Contains("grantPlayerItem", deliveryContent);
            Assert.Contains("resolveStaticItemId", deliveryContent);
            Assert.Contains("live-players.json", deliveryContent);
        }

        [Fact]
        public void Mod_PalSchema_And_ChazzBuffs_Integrity()
        {
            string palSchemaDir = Path.Combine(_modsDir, "PalSchema");
            Assert.True(Directory.Exists(palSchemaDir), "PalSchema dir missing!");

            string dllPath = Path.Combine(palSchemaDir, "dlls", "main.dll");
            Assert.True(File.Exists(dllPath), "PalSchema main.dll missing!");

            string chazzBuffsDir = Path.Combine(palSchemaDir, "mods", "ChazzBuffs");
            Assert.True(Directory.Exists(chazzBuffsDir), "ChazzBuffs dir missing!");

            var jsonFiles = Directory.GetFiles(chazzBuffsDir, "*.json*", SearchOption.AllDirectories);
            Assert.True(jsonFiles.Length >= 50, $"Expected at least 50 JSON buff files in ChazzBuffs, found {jsonFiles.Length}");
        }

        [Fact]
        public void Mod_RamTrimMod_Integrity()
        {
            string dllPath = Path.Combine(_modsDir, "RamTrimMod", "dlls", "main.dll");
            Assert.True(File.Exists(dllPath), "RamTrimMod main.dll missing!");
        }

        [Fact]
        public void Mod_CatchAllPredatorBosses_Pak_Integrity()
        {
            string pakPath = Path.Combine(_paksDir, "Catch All PREDATOR Bosses_P.pak");
            Assert.True(File.Exists(pakPath), "Catch All PREDATOR Bosses_P.pak missing from ~mods!");
            var fileInfo = new FileInfo(pakPath);
            Assert.True(fileInfo.Length > 0, "Catch All PREDATOR Bosses_P.pak is empty!");
        }

        [Fact]
        public void Mod_ModsTxt_Contains_All_Registered_Mods()
        {
            string modsTxtPath = Path.Combine(_modsDir, "mods.txt");
            Assert.True(File.Exists(modsTxtPath), "mods.txt is missing!");

            string content = File.ReadAllText(modsTxtPath);

            string[] expectedMods = {
                "QuickDeposit",
                "CleanHUD",
                "DarnMenu",
                "DarnToasts",
                "ExpeditionXP",
                "LevelLock",
                "PalboxSearchPlus",
                "PalCinematicStudio",
                "PalClearVision",
                "PalOdysseyOptimizer",
                "PalSchema",
                "PalworldTuner",
                "RamTrimMod",
                "ShiningLuckies",
                "StuckPalRescuer",
                "WeaponProficiency"
            };

            foreach (var mod in expectedMods)
            {
                Assert.Contains($"{mod} : 1", content);
            }
        }
    }
}
