# PalOdysseyAudioPlayer

Lightweight native-AOT playback bridge for `PalOdysseyAudioEvents`.

Publish with:

```powershell
dotnet publish PalOdysseyAudioPlayer.csproj -c Release -r win-x64 `
  -o ..\..\Pal\Binaries\Win64\ue4ss\Mods\PalOdysseyAudioEvents\bin
```

The player uses Windows MCI for MP3/WAV playback, polls the companion's atomic
JSON state file, maintains separate BGM and SFX aliases, and has a Palworld
process watchdog plus a single-instance mutex.
