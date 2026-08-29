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
        private const int ChunkBufferSize = 64 * 1024; // 64 KB streaming buffer

        /// <summary>
        /// Computes the SHA-256 hash of a file asynchronously in chunks to prevent memory spikes.
        /// </summary>
        public async Task<string> ComputeSha256Async(string filePath, CancellationToken cancellationToken = default)
        {
            if (!File.Exists(filePath))
                return string.Empty;

            using var sha256 = SHA256.Create();
            byte[] buffer = new byte[ChunkBufferSize];

            await using var stream = new FileStream(
                filePath,
                FileMode.Open,
                FileAccess.Read,
                FileShare.Read,
                ChunkBufferSize,
                FileOptions.Asynchronous | FileOptions.SequentialScan);

            int bytesRead;
            while ((bytesRead = await stream.ReadAsync(buffer.AsMemory(0, buffer.Length), cancellationToken)) > 0)
            {
                cancellationToken.ThrowIfCancellationRequested();
                sha256.TransformBlock(buffer, 0, bytesRead, null, 0);
            }

            sha256.TransformFinalBlock(Array.Empty<byte>(), 0, 0);
            byte[]? hashBytes = sha256.Hash;

            return hashBytes != null
                ? Convert.ToHexString(hashBytes).ToLowerInvariant()
                : string.Empty;
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
            if (cache.Entries.TryGetValue(relativeKey, out var cachedEntry))
            {
                if (cachedEntry.LastWriteTimeUtc == lastWriteUtc &&
                    cachedEntry.FileSize == fileInfo.Length &&
                    !string.IsNullOrWhiteSpace(cachedEntry.Sha256))
                {
                    bool cachedMatch = string.Equals(cachedEntry.Sha256, expectedSha256, StringComparison.OrdinalIgnoreCase);
                    return (cachedMatch, cachedEntry.Sha256);
                }
            }

            // Slow-path: Cryptographic hashing
            string computedHash = await ComputeSha256Async(resolvedFullPath, cancellationToken);
            bool isMatch = string.Equals(computedHash, expectedSha256, StringComparison.OrdinalIgnoreCase);

            if (isMatch)
            {
                // Update local cache
                cache.Entries[relativeKey] = new CacheFileEntry
                {
                    RelativePath = relativeKey,
                    ResolvedFullPath = resolvedFullPath,
                    LastWriteTimeUtc = lastWriteUtc,
                    FileSize = fileInfo.Length,
                    Sha256 = computedHash
                };
            }

            return (isMatch, computedHash);
        }
    }
}
