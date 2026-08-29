using System;
using System.Collections.Generic;
using System.IO;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace PalLauncher.Models
{
    public class CacheFileEntry
    {
        [JsonPropertyName("relativePath")]
        public string RelativePath { get; set; } = string.Empty;

        [JsonPropertyName("resolvedFullPath")]
        public string ResolvedFullPath { get; set; } = string.Empty;

        [JsonPropertyName("lastWriteTimeUtc")]
        public DateTime LastWriteTimeUtc { get; set; }

        [JsonPropertyName("fileSize")]
        public long FileSize { get; set; }

        [JsonPropertyName("sha256")]
        public string Sha256 { get; set; } = string.Empty;
    }

    public class LocalCache
    {
        [JsonPropertyName("version")]
        public int Version { get; set; } = 1;

        [JsonPropertyName("entries")]
        public Dictionary<string, CacheFileEntry> Entries { get; set; } = new(StringComparer.OrdinalIgnoreCase);

        private static readonly JsonSerializerOptions JsonOptions = new()
        {
            WriteIndented = true,
            DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull
        };

        public static LocalCache Load(string filePath)
        {
            try
            {
                if (File.Exists(filePath))
                {
                    string json = File.ReadAllText(filePath);
                    return JsonSerializer.Deserialize<LocalCache>(json, JsonOptions) ?? new LocalCache();
                }
            }
            catch (Exception)
            {
                // Return clean cache on parse or read failure
            }

            return new LocalCache();
        }

        public void Save(string filePath)
        {
            try
            {
                string? dir = Path.GetDirectoryName(filePath);
                if (!string.IsNullOrEmpty(dir) && !Directory.Exists(dir))
                {
                    Directory.CreateDirectory(dir);
                }

                string json = JsonSerializer.Serialize(this, JsonOptions);
                string tempPath = filePath + ".tmp." + Guid.NewGuid().ToString("N");
                File.WriteAllText(tempPath, json);
                File.Move(tempPath, filePath, overwrite: true);
            }
            catch (Exception)
            {
                // Silently handle save failures so the launcher does not crash
            }
        }
    }
}
