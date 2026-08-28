using System.Text.Json.Serialization;
using PalLauncher.ViewModels.Common;

namespace PalLauncher.Models
{
    public class ModInfo : ViewModelBase
    {
        private string _id = string.Empty;
        private string _name = string.Empty;
        private string _description = string.Empty;
        private string _category = "Gameplay";
        private bool _enabledByDefault = true;
        private string _version = "1.0.0";
        private string _author = "Community";
        private string _downloadUrl = string.Empty;
        private string _relativeInstallPath = string.Empty; // e.g. "Pal/Content/Paks/ExampleMod.pak" or "~mods/Custom.pak"
        private string _sha256Checksum = string.Empty;
        private long _sizeBytes;
        private bool _isRequired = true;
        private string _changelog = string.Empty;

        // Runtime state (Observable for UI)
        private string _localVersion = "Not Installed";
        private ModStatus _status = ModStatus.Unknown;
        private double _downloadProgress;
        private string _statusMessage = string.Empty;
        private string _localSha256 = string.Empty;
        private bool _isSelected = true;

        [JsonPropertyName("id")]
        public string Id
        {
            get => _id;
            set => SetProperty(ref _id, value);
        }

        [JsonPropertyName("name")]
        public string Name
        {
            get => _name;
            set => SetProperty(ref _name, value);
        }

        [JsonPropertyName("description")]
        public string Description
        {
            get => _description;
            set => SetProperty(ref _description, value);
        }

        [JsonPropertyName("category")]
        public string Category
        {
            get => _category;
            set => SetProperty(ref _category, value);
        }

        [JsonPropertyName("enabledByDefault")]
        public bool EnabledByDefault
        {
            get => _enabledByDefault;
            set => SetProperty(ref _enabledByDefault, value);
        }

        [JsonPropertyName("version")]
        public string Version
        {
            get => _version;
            set => SetProperty(ref _version, value);
        }

        [JsonPropertyName("author")]
        public string Author
        {
            get => _author;
            set => SetProperty(ref _author, value);
        }

        [JsonPropertyName("downloadUrl")]
        public string DownloadUrl
        {
            get => _downloadUrl;
            set => SetProperty(ref _downloadUrl, value);
        }

        [JsonPropertyName("relativeInstallPath")]
        public string RelativeInstallPath
        {
            get => _relativeInstallPath;
            set => SetProperty(ref _relativeInstallPath, value);
        }

        [JsonPropertyName("sha256")]
        public string Sha256Checksum
        {
            get => _sha256Checksum;
            set => SetProperty(ref _sha256Checksum, value);
        }

        [JsonPropertyName("sizeBytes")]
        public long SizeBytes
        {
            get => _sizeBytes;
            set => SetProperty(ref _sizeBytes, value);
        }

        [JsonPropertyName("isRequired")]
        public bool IsRequired
        {
            get => _isRequired;
            set => SetProperty(ref _isRequired, value);
        }

        [JsonPropertyName("changelog")]
        public string Changelog
        {
            get => _changelog;
            set => SetProperty(ref _changelog, value);
        }

        [JsonIgnore]
        public string LocalVersion
        {
            get => _localVersion;
            set => SetProperty(ref _localVersion, value);
        }

        [JsonIgnore]
        public ModStatus Status
        {
            get => _status;
            set
            {
                if (SetProperty(ref _status, value))
                {
                    OnPropertyChanged(nameof(StatusDisplayName));
                    OnPropertyChanged(nameof(IsUpToDate));
                    OnPropertyChanged(nameof(CanUpdate));
                }
            }
        }

        [JsonIgnore]
        public double DownloadProgress
        {
            get => _downloadProgress;
            set => SetProperty(ref _downloadProgress, value);
        }

        [JsonIgnore]
        public string StatusMessage
        {
            get => _statusMessage;
            set => SetProperty(ref _statusMessage, value);
        }

        [JsonIgnore]
        public string LocalSha256
        {
            get => _localSha256;
            set => SetProperty(ref _localSha256, value);
        }

        [JsonIgnore]
        public bool IsSelected
        {
            get => _isSelected;
            set => SetProperty(ref _isSelected, value);
        }

        [JsonIgnore]
        public bool IsUpToDate => Status == ModStatus.UpToDate;

        [JsonIgnore]
        public bool CanUpdate => Status == ModStatus.UpdateAvailable || Status == ModStatus.Missing || Status == ModStatus.Error;

        [JsonIgnore]
        public string StatusDisplayName => Status switch
        {
            ModStatus.UpToDate => "Verified & Up to Date",
            ModStatus.UpdateAvailable => "Update Available",
            ModStatus.Missing => "Missing",
            ModStatus.Downloading => "Downloading...",
            ModStatus.Installing => "Installing...",
            ModStatus.Checking => "Verifying Hash...",
            ModStatus.Error => "Hash Mismatch / Error",
            _ => "Not Checked"
        };
    }
}
