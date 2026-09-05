import os
import hashlib
import json
from datetime import datetime, timezone
import urllib.parse

# ----------------- CONFIGURATION -----------------
MODPACK_STAGING_PATH = r"c:\PalOdyssey-ModpackStaging"
BASE_DOWNLOAD_URL = "https://raw.githubusercontent.com/your-repo/palworld-modpack/main/files"
OUTPUT_PATH = r"c:\PalOdyssey-ModpackStaging\manifest.json"
# -------------------------------------------------

def compute_sha256(file_path: str) -> str:
    """Computes SHA-256 in 64KB chunks to prevent RAM overhead on large files."""
    hasher = hashlib.sha256()
    with open(file_path, "rb") as f:
        while chunk := f.read(65536):
            hasher.update(chunk)
    return hasher.hexdigest().lower()

def generate_manifest(staging_path: str = MODPACK_STAGING_PATH, base_url: str = BASE_DOWNLOAD_URL, output_path: str = OUTPUT_PATH):
    if not os.path.exists(staging_path):
        raise FileNotFoundError(f"Staging path not found: {staging_path}")

    print(f"Scanning directory: {staging_path}")
    files_manifest = []

    for root, _, files in os.walk(staging_path):
        for file in files:
            if file == "manifest.json" or file.endswith(".tmp"):
                continue

            full_path = os.path.join(root, file)
            rel_path = os.path.relpath(full_path, staging_path).replace("\\", "/")
            
            file_size = os.path.getsize(full_path)
            file_hash = compute_sha256(full_path)
            
            # Construct download URL with proper URL encoding
            encoded_rel_path = urllib.parse.quote(rel_path)
            download_url = f"{base_url.rstrip('/')}/{encoded_rel_path}"

            print(f"  -> Processed: {rel_path} ({file_size:,} bytes) [{file_hash[:8]}...]")

            files_manifest.append({
                "RelativePath": rel_path,
                "Hash": file_hash,
                "Size": file_size,
                "DownloadUrl": download_url
            })

    manifest_data = {
        "Version": datetime.now(timezone.utc).strftime("%Y.%m.%d.%H%M%S"),
        "GeneratedAt": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "TotalFiles": len(files_manifest),
        "Files": files_manifest
    }

    out_dir = os.path.dirname(output_path)
    if out_dir and not os.path.exists(out_dir):
        os.makedirs(out_dir, exist_ok=True)

    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(manifest_data, f, indent=2, ensure_ascii=False)

    print(f"\nSuccessfully generated: {output_path}")
    print(f"Total Files Indexed: {len(files_manifest)}")

if __name__ == "__main__":
    generate_manifest()
