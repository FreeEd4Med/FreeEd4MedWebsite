# How I prepare tracks for clinical streaming — MadMoozeMusic / FreeEd4Med

This short guide describes a repeatable workflow to prepare music for clinical and streaming use: exports, stems, metadata, loudness, and packaging.

1) File formats and sample rates
   - Deliver WAV or FLAC (lossless) at 44.1 kHz or 48 kHz and 24-bit depth.
   - Include one low-bitrate preview MP3 (128–192 kbps) for quick auditioning in apps that don't need lossless files.

2) Loudness and mastering
   - For streaming and clinical systems target a -14 LUFS (integrated) master as a good middle ground for calmer content; include true peak < -1 dBTP.
   - Provide a dry master and an optional mastered version so host systems can apply consistent processing.

3) Create multiple edits
   - Full track (3–5 minutes typical)
   - Short version (30–60s) for cueing or apps
   - Loopable micro-sections (10–40s) for repeatable background use

4) Stems & stems packaging
   - Provide stems in WAV/FLAC (e.g., vocals.wav, pads.wav, perc.wav, bass.wav).
   - Include a stems_info.json and README describing usage, tempo (BPM), and suggested sync points.

5) Metadata & discoverability
   - Include Title, Artist, ISRC (if you have one), Year, BPM, Genre, and suggested tags (e.g., 'preoperative', 'relaxation', 'pain‑reduction').
   - Add a short 'intended use' note in metadata: e.g., "Calm background for preoperative waiting, loopable".

6) Licensing & distribution
   - Provide a simple license file describing allowed uses (clinical, non-commercial, redistribution rights), or contact info for licensing inquiries.
   - If you want to grant public clinical use, consider a permissive license or a clear per-use license.

7) Packaging and delivery
   - Zip the stems and metadata together and provide a short README and a low-bitrate preview for quick checking.
   - Share via cloud storage, or embed a download link on your site; include clear attribution/credits.

8) Testing and feedback
   - Ask clinical partners to test the tracks in context (e.g., preop waiting, rehab app) and iterate on tempo, timbre, and event structure.

If you want, I can produce a printable checklist PDF or a short infographic for artist distribution.
