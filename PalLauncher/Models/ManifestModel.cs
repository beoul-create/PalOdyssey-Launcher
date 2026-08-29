using System;
using System.Collections.Generic;
using System.IO;
using System.Text.Json.Serialization;

namespace PalLauncher.Models
{
    public enum ModTargetCategory
    {
        [JsonPropertyName("pak")]
        PakMod,

        [JsonPropertyName("ue4ss")]
        Ue4ssMod,

        [JsonPropertyName("config")]
        Config,

        [JsonPropertyName("root")]
        Root
    }

    public class ModFileItem
    {
        [JsonPropertyName("relativePath")]
        [JsonInclude]
        public string RelativePath { get; set; } = string.Empty;

        // Alias support for Generator schemas using "Hash"
        private string _sha256 = string.Empty;

        [JsonPropertyName("sha256")]
        [JsonInclude]
        public string Sha256
        {
            get => _sha256;
            set => _sha256 = value;
        }

        [JsonPropertyName("hash")]
        [JsonInclude]
        public string Hash
        {
            get => _sha256;
            set
            {
                if (!string.IsNullOrWhiteSpace(value))
                    _sha256 = value;
            }
        }

        // Alias support for Generator schemas using "Size"
        private long _fileSize;

        [JsonPropertyName("fileSize")]
        [JsonInclude]
        public long FileSize
        {
            get => _fileSize;
            set => _fileSize = value;
        }

        [JsonPropertyName("size")]
        [JsonInclude]
        public long Size
        {
            get => _fileSize;
            set
            {
                if (value > 0)
                    _fileSize = value;
            }
        }

        [JsonPropertyName("downloadUrl")]
        [JsonInclude]
        public string? DownloadUrl { get; set; }

        [JsonPropertyName("targetCategory")]
        [JsonConverter(typeof(JsonStringEnumConverter))]
        public ModTargetCategory? TargetCategory { get; set; }

        [JsonPropertyName("isRequired")]
        public bool IsRequired { get; set; } = true;

        [JsonPropertyName("description")]
        public string? Description { get; set; }

        /// <summary>
        /// Resolves the absolute path where this file should reside within the Palworld game installation directory.
        /// Handles both full relative game paths (e.g. Pal/Content/Paks/~mods/mod.pak) and sub-relative paths.
        /// </summary>
        public string GetResolvedPath(string gameRootPath)
        {
            if (string.IsNullOrWhiteSpace(gameRootPath))
                throw new ArgumentException("Game root directory path cannot be empty.", nameof(gameRootPath));

            string normalizedRel = RelativePath.TrimStart('/', '\\').Replace('\\', '/');

            // If the relative path already starts with the Pal game folder structure, resolve directly from game root
            if (normalizedRel.StartsWith("Pal/", StringComparison.OrdinalIgnoreCase))
            {
                return Path.GetFullPath(Path.Combine(gameRootPath, normalizedRel.Replace('/', Path.DirectorySeparatorChar)));
            }

            // Determine or infer category
            var category = TargetCategory ?? InferCategoryFromPath(normalizedRel);

            string baseDir = category switch
            {
                ModTargetCategory.PakMod => Path.Combine(gameRootPath, "Pal", "Content", "Paks", "~mods"),
                ModTargetCategory.Ue4ssMod => Path.Combine(gameRootPath, "Pal", "Binaries", "Win64", "ue4ss", "Mods"),
                ModTargetCategory.Config => Path.Combine(gameRootPath, "Pal", "Saved", "Config", "Windows"),
                ModTargetCategory.Root => gameRootPath,
                _ => Path.Combine(gameRootPath, "Pal", "Content", "Paks", "~mods")
            };

            return Path.GetFullPath(Path.Combine(baseDir, normalizedRel.Replace('/', Path.DirectorySeparatorChar)));
        }

        private static ModTargetCategory InferCategoryFromPath(string path)
        {
            string lower = path.ToLowerInvariant();
            if (lower.Contains("paks/~mods") || lower.EndsWith(".pak"))
                return ModTargetCategory.PakMod;
            if (lower.Contains("ue4ss") || lower.EndsWith(".lua") || lower.EndsWith(".dll"))
                return ModTargetCategory.Ue4ssMod;
            if (lower.Contains("config") || lower.EndsWith(".ini"))
                return ModTargetCategory.Config;

            return ModTargetCategory.PakMod;
        }
    }

    public class ServerNewsItem
    {
        [JsonPropertyName("title")]
        public string Title { get; set; } = string.Empty;

        [JsonPropertyName("date")]
        public string Date { get; set; } = string.Empty;

        [JsonPropertyName("summary")]
        public string Summary { get; set; } = string.Empty;

        [JsonPropertyName("linkUrl")]
        public string? LinkUrl { get; set; }
    }

    public class ManifestModel
    {
        private string _version = "1.0.0";

        [JsonPropertyName("manifestVersion")]
        [JsonInclude]
        public string ManifestVersion
        {
            get => _version;
            set => _version = value;
        }

        [JsonPropertyName("version")]
        [JsonInclude]
        public string Version
        {
            get => _version;
            set
            {
                if (!string.IsNullOrWhiteSpace(value))
                    _version = value;
            }
        }

        [JsonPropertyName("generatedAt")]
        public string? GeneratedAt { get; set; }

        [JsonPropertyName("totalFiles")]
        public int? TotalFiles { get; set; }

        [JsonPropertyName("serverName")]
        public string ServerName { get; set; } = "PalOdyssey Official Modded Realm";

        [JsonPropertyName("serverAddress")]
        public string ServerAddress { get; set; } = "palodyssey.duckdns.org";

        [JsonPropertyName("serverPort")]
        public int ServerPort { get; set; } = 8211;

        [JsonPropertyName("gameVersion")]
        public string GameVersion { get; set; } = "v0.3.5 Modded";

        [JsonPropertyName("bannerUrl")]
        public string? BannerUrl { get; set; }

        [JsonPropertyName("news")]
        public List<ServerNewsItem> News { get; set; } = new();

        [JsonPropertyName("files")]
        public List<ModFileItem> Files { get; set; } = new();
    }
}
