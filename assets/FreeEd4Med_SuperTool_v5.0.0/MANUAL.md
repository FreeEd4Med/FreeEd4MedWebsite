Version 5.0.0

FreeEd4Med Media SuperTool — v5.0.0

This manual documents the command-line SuperTool (`freeed_media_super_tool.sh`) and related helpers.

Quick start
- **Option A (Native)**: Install `ffmpeg`, `python3`, `pip install -r requirements.txt`. Run `bash freeed_media_super_tool.sh`.
- **Option B (Docker)**: Install Docker. Run `run_docker.bat` (Windows) or `./run_docker.sh` (Mac/Linux). No other dependencies needed.
- Config (optional): `~/.freeed_media_super_tool/config.json` can set `audio_output_folder`, `default_output_folder`, `report_output_folder`, API keys, etc.
- Temp/logs: per-export logs write to `/tmp/<base>_<tag>.log`. Outputs follow the naming noted below.

Menu map (high level)
- **Creation Module**: Lyric videos, AI Whisper subtitles, Static Videos, and **Songwriting Assistant**.
- **Visualizer Lab**: 40+ Audio Visualizers including Python-based engines (Lava Lamp, Fire, Radial Spectrum).
- **Audio Lab**: Mastering analysis (`ardour_fixer.py`), conversion, normalization.
- **Notation Studio**: AI Audio-to-MIDI-to-Sheet Music.
- **Social Media Batch**: Multi-format exports (Tok, YT, X, IG, META).
- **YouTube Upload**: Local OAuth upload with metadata and captions.

New Features in v5.0
--------------------

### 1. Songwriting Assistant (Creation Module -> Option 7)
A new utility to help write lyrics:
- **Rhyme Finder**: Finds perfect and near rhymes using Datamuse API.
- **Thesaurus**: Finds synonyms and related words.
- **AI Lyric Generator**:
    - **OpenAI**: Requires API Key (Paid).
    - **Ollama**: Runs locally (Free, requires `ollama` installed).

### 2. Enhanced Visualizers (Visualizer Lab)
We have expanded the Python-based visualizer engine (`viz_master.py`):

*   **Radial Spectrum (Option 36)**:
    *   **Background Image**: Now supports a full-screen background image behind the spectrum.
    *   **Logo Overlay**: Add a logo on top of or behind the waveform.
    *   **Logo Sizing**: Choose from Small (20%) to Extra Large (80%).
*   **Reactive Text/Logo (Option 38)**:
    *   Displays a user-provided image (Logo) or Text that pulses with the bass beat.
*   **Realistic Fire (Option 39)**:
    *   Doom-style procedural fire effect that reacts to audio intensity.
*   **3D Terrain (Option 37)**:
    *   Wireframe retro-style terrain that moves with the music.
*   **Static Waveform (Option 40)**:
    *   Generates a high-res PNG image of the entire song's waveform.

### 3. Social Media Batch (Core Workflow)
1) Choose Social Media Batch → pick outputs (`a` for all or comma list like `1,3,4`).
2) Drag/drop input; tool auto-detects type (Video, Image, Audio).
3) Pick quality preset (Low/Medium/High/Custom).
4) Outputs (per platform): `<base>_video_Tok.mp4`, `_YT.mp4`, `_X.mp4`, `_IG.mp4`, `_META.mp4`.

### 4. AI Captions & Subtitles
- **Backends**: `auto`, `ollama` (local), `openai`, `anthropic`.
- **Styling**: Full ASS styling support (Fonts, Colors, Shadows).
- **Whisper**: Auto-transcribe audio to SRT with high accuracy.

### 5. Audio Mastering (ardour_fixer.py)
- **Targets**: Spotify, YouTube, Apple, CD, Vinyl.
- **Analysis**: LUFS, True Peak, LRA, Phase, Spectrum.
- **Auto-Master**: Experimental one-pass mastering.

Resources & Images Needed
-------------------------
To complete the documentation, please add the following images to the `images/` folder:
1.  `menu_main_v5.png` - Screenshot of the new Main Menu.
2.  `viz_radial_logo.png` - Screenshot of Radial Spectrum with Logo Overlay.
3.  `viz_fire.png` - Screenshot of the Realistic Fire visualizer.
4.  `songwriting_assistant.png` - Screenshot of the Lyric Assistant in action.
5.  `social_batch_output.png` - Screenshot of the batch export results.

Current release
- **v5.0.0**
- Highlights: Songwriting Assistant, Advanced Radial Visualizer (Logos/Images), Realistic Fire, 3D Terrain.
