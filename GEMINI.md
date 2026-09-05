# Workspace File Handling Rules
- Never attempt to open, read, parse, or compute line counts on binary media files (.mp3, .wav, .ogg, .pak, .dll).
- Treat all files inside music/audio folders as static binaries.
- If referencing audio assets for code, reference only the file path string without inspecting its contents.
