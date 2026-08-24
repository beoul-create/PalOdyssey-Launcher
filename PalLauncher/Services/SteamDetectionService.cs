using System;
using System.IO;
using System.Text.RegularExpressions;
using Microsoft.Win32;
using PalLauncher.Services.Interfaces;

namespace PalLauncher.Services
{
    public class SteamProfileInfo
    {
        public bool IsDetected { get; set; }
        public string SteamId64 { get; set; } = string.Empty;
        public uint AccountId32 { get; set; }
        public string PersonaName { get; set; } = "Steam Pioneer";
        public string AccountName { get; set; } = string.Empty;
        public string SteamPath { get; set; } = string.Empty;
        public string ProfileUrl => !string.IsNullOrEmpty(SteamId64) ? $"https://steamcommunity.com/profiles/{SteamId64}" : string.Empty;
        public string FormattedSummary => IsDetected ? $"{PersonaName} ({SteamId64})" : "Steam Not Detected";
    }

    public interface ISteamDetectionService
    {
        SteamProfileInfo DetectActiveSteamUser();
    }

    public class SteamDetectionService : ISteamDetectionService
    {
        private readonly ILogService _logService;
        private const ulong Steam64Base = 76561197960265728UL;

        public SteamDetectionService(ILogService logService)
        {
            _logService = logService;
        }

        public SteamProfileInfo DetectActiveSteamUser()
        {
            var profile = new SteamProfileInfo();

            try
            {
                // 1. Check Steam installation path from registry
                string steamPath = GetSteamPathFromRegistry();
                profile.SteamPath = steamPath;

                // 2. Query active user account ID from HKCU\Software\Valve\Steam\ActiveProcess
                uint activeUser32 = GetActiveUserFromRegistry();
                if (activeUser32 > 0)
                {
                    profile.AccountId32 = activeUser32;
                    profile.SteamId64 = (Steam64Base + activeUser32).ToString();
                    profile.IsDetected = true;
                }

                // 3. Inspect loginusers.vdf for PersonaName & AccountName
                if (!string.IsNullOrEmpty(steamPath))
                {
                    string vdfPath = Path.Combine(steamPath, "config", "loginusers.vdf");
                    if (File.Exists(vdfPath))
                    {
                        ParseLoginUsersVdf(vdfPath, profile);
                    }
                }

                if (profile.IsDetected)
                {
                    _logService.LogSuccess($"[STEAM] Active Steam User Detected: '{profile.PersonaName}' (Steam64: {profile.SteamId64})", "SteamDetection");
                }
                else
                {
                    _logService.LogInfo("No active Steam session currently detected.", "SteamDetection");
                }
            }
            catch (Exception ex)
            {
                _logService.LogWarning($"Failed to detect active Steam profile: {ex.Message}", "SteamDetection");
            }

            return profile;
        }

        private static string GetSteamPathFromRegistry()
        {
            try
            {
                using var key = Registry.CurrentUser.OpenSubKey(@"Software\Valve\Steam");
                if (key != null)
                {
                    string? path = key.GetValue("SteamPath") as string;
                    if (!string.IsNullOrEmpty(path))
                    {
                        return path.Replace('/', '\\');
                    }
                }
            }
            catch { }

            try
            {
                using var key64 = Registry.LocalMachine.OpenSubKey(@"SOFTWARE\WOW6432Node\Valve\Steam");
                if (key64 != null)
                {
                    string? path = key64.GetValue("InstallPath") as string;
                    if (!string.IsNullOrEmpty(path)) return path;
                }
            }
            catch { }

            string defaultPath = @"C:\Program Files (x86)\Steam";
            return Directory.Exists(defaultPath) ? defaultPath : string.Empty;
        }

        private static uint GetActiveUserFromRegistry()
        {
            try
            {
                using var key = Registry.CurrentUser.OpenSubKey(@"Software\Valve\Steam\ActiveProcess");
                if (key != null)
                {
                    object? val = key.GetValue("ActiveUser");
                    if (val is int intVal && intVal > 0)
                    {
                        return (uint)intVal;
                    }
                    if (val is long longVal && longVal > 0)
                    {
                        return (uint)longVal;
                    }
                }
            }
            catch { }
            return 0;
        }

        private static void ParseLoginUsersVdf(string vdfPath, SteamProfileInfo profile)
        {
            try
            {
                string text = File.ReadAllText(vdfPath);

                // If we already know the SteamId64, look for that specific section
                if (!string.IsNullOrEmpty(profile.SteamId64))
                {
                    var match = Regex.Match(text, $"\"{profile.SteamId64}\"[\\s\\S]*?\\{{([\\s\\S]*?)\\}}", RegexOptions.Multiline);
                    if (match.Success)
                    {
                        ExtractPropertiesFromBlock(match.Groups[1].Value, profile);
                        return;
                    }
                }

                // Fallback: Look for the most recent or autologin user in loginusers.vdf
                var userBlocks = Regex.Matches(text, "\"(\\d{17})\"[\\s\\S]*?\\{([\\s\\S]*?)\\}", RegexOptions.Multiline);
                foreach (Match m in userBlocks)
                {
                    string steamId = m.Groups[1].Value;
                    string block = m.Groups[2].Value;

                    if (block.Contains("\"MostRecent\"\t\t\"1\"") || block.Contains("\"AutoLogin\"\t\t\"1\""))
                    {
                        profile.SteamId64 = steamId;
                        if (ulong.TryParse(steamId, out ulong id64) && id64 > Steam64Base)
                        {
                            profile.AccountId32 = (uint)(id64 - Steam64Base);
                        }
                        ExtractPropertiesFromBlock(block, profile);
                        profile.IsDetected = true;
                        return;
                    }
                }

                // Fallback: Take the first user in the file
                if (userBlocks.Count > 0)
                {
                    profile.SteamId64 = userBlocks[0].Groups[1].Value;
                    ExtractPropertiesFromBlock(userBlocks[0].Groups[2].Value, profile);
                    profile.IsDetected = true;
                }
            }
            catch { }
        }

        private static void ExtractPropertiesFromBlock(string block, SteamProfileInfo profile)
        {
            var personaMatch = Regex.Match(block, "\"PersonaName\"\\s+\"([^\"]+)\"");
            if (personaMatch.Success)
            {
                profile.PersonaName = personaMatch.Groups[1].Value;
            }

            var accountMatch = Regex.Match(block, "\"AccountName\"\\s+\"([^\"]+)\"");
            if (accountMatch.Success)
            {
                profile.AccountName = accountMatch.Groups[1].Value;
            }
        }
    }
}
