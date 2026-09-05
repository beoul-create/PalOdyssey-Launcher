using System;
using System.IO;
using System.Security.Cryptography;
using System.Threading;
using System.Threading.Tasks;
using PalLauncher.Models;

namespace PalLauncher.Services
{
    public class HashService
    {
        private const int ChunkBufferSize = 256 * 1024;

        /// <summary>
        /// Computes the SHA-256 hash of a file asynchronously in chunks to prevent memory spikes.
        /// </summary>
        public async Task<string> ComputeSha256Async(string filePath, CancellationToken cancellationToken = default)
        {
            if (!File.Exists(filePath))
                return string.Empty;

            await using var stream = new FileStream(
                filePath,
                FileMode.Open,
                FileAccess.Read,
                FileShare.Read,
                ChunkBufferSize,
                FileOptions.Asynchronous | FileOptions.SequentialScan);
            byte[] hashBytes = await SHA256.HashDataAsync(stream, cancellationToken);
            return Convert.ToHexString(hashBytes).ToLowerInvariant();
        }

        /// <summary>
        /// Fast verification against local cache; if timestamp and size match, full hash is skipped.
        /// Otherwise computes hash and updates local cache.
        /// </summary>
        public async Task<(bool IsValid, string ComputedHash)> VerifyFileWithCacheAsync(
            string resolvedFullPath,
            string relativeKey,
            long expectedSize,
            string expectedSha256,
            LocalCache cache,
            CancellationToken cancellationToken = default)
        {
            if (!File.Exists(resolvedFullPath))
                return (false, string.Empty);

            var fileInfo = new FileInfo(resolvedFullPath);

            // Fast size check
            if (expectedSize > 0 && fileInfo.Length != expectedSize)
                return (false, string.Empty);

            DateTime lastWriteUtc = fileInfo.LastWriteTimeUtc;

            // Fast-path: Check local cache
            CacheFileEntry? cachedEntry;
            lock (cache.Entries)
            {
                cache.Entries.TryGetValue(relativeKey, out cachedEntry);
            }
            if (cachedEntry != null &&
                string.Equals(cachedEntry.ResolvedFullPath, resolvedFullPath, StringComparison.OrdinalIgnoreCase) &&
                cachedEntry.LastWriteTimeUtc == lastWriteUtc &&
                cachedEntry.FileSize == fileInfo.Length &&
                !string.IsNullOrWhiteSpace(cachedEntry.Sha256))
            {
                bool cachedMatch = string.Equals(cachedEntry.Sha256, expectedSha256, StringComparison.OrdinalIgnoreCase);
                return (cachedMatch, cachedEntry.Sha256);
            }

            // Slow-path: Cryptographic hashing
            string computedHash = await ComputeSha256Async(resolvedFullPath, cancellationToken);
            bool isMatch = string.Equals(computedHash, expectedSha256, StringComparison.OrdinalIgnoreCase);

            if (!isMatch && IsTextFile(resolvedFullPath))
            {
                try
                {
                    string textContent = await File.ReadAllTextAsync(resolvedFullPath, cancellationToken);
                    string normalized = textContent.Replace("\r\n", "\n").Replace("\r", "\n");
                    byte[] normalizedBytes = System.Text.Encoding.UTF8.GetBytes(normalized);
                    byte[] normalizedHashBytes = SHA256.HashData(normalizedBytes);
                    string normalizedHash = Convert.ToHexString(normalizedHashBytes).ToLowerInvariant();
                    if (string.Equals(normalizedHash, expectedSha256, StringComparison.OrdinalIgnoreCase))
                    {
                        isMatch = true;
                        computedHash = expectedSha256;
                    }
                }
                catch { }
            }

            if (isMatch)
            {
                // Update local cache
                lock (cache.Entries)
                {
                    cache.Entries[relativeKey] = new CacheFileEntry
                    {
                        RelativePath = relativeKey,
                        ResolvedFullPath = resolvedFullPath,
                        LastWriteTimeUtc = lastWriteUtc,
                        FileSize = fileInfo.Length,
                        Sha256 = computedHash
                    };
                }
            }

            return (isMatch, computedHash);
        }

        public bool IsTextFile(string filePath)
        {
            string ext = Path.GetExtension(filePath).ToLowerInvariant();
            return ext switch
            {
                ".txt" or ".lua" or ".json" or ".jsonc" or ".ini" or ".cfg" or ".md" or ".xml" or ".csv" => true,
                _ => false
            };
        }
    }
}
