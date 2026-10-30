# How I prepare tracks for clinical streaming - MadMoozeMusic / FreeEd4Med

This guide describes a repeatable workflow for preparing music assets for clinician-approved use and digital distribution. It covers exports, stems, metadata, loudness measurement, and packaging. Music is a supportive resource, not a substitute for medical care; follow the care team's direction and the listener's preferences.

1) File formats and sample rates
   - Deliver WAV or FLAC (lossless) at 44.1 kHz or 48 kHz and 24-bit depth.
   - Include one low-bitrate preview MP3 (128-192 kbps) for quick auditioning in apps that don't need lossless files.

2) Loudness and mastering
   - There is no universal -14 LUFS delivery target for every streaming platform or clinical playback system. Check the recipient's current delivery specification rather than treating one loudness value as mandatory.
   - Preserve an unclipped, high-quality master. Measure and document integrated loudness and maximum true peak; create platform-specific versions only when a delivery specification calls for them.
   - LUFS describes the audio file, not the sound pressure reaching a listener. Set playback level according to the care team's or facility's guidance; do not use a mastering target to set a patient's listening volume.
   - When helpful, include an unprocessed master alongside a clearly labeled delivery master.

3) Create multiple edits
   - Full track (3-5 minutes typical)
   - Short version (30-60s) for cueing or apps
   - Loopable micro-sections (10-40s) for repeatable background use

4) Stems & stems packaging
   - Provide stems in WAV/FLAC (e.g., vocals.wav, pads.wav, perc.wav, bass.wav).
   - Include a stems_info.json and README describing usage, tempo (BPM), and suggested sync points.

5) Metadata & discoverability
   - Include Title, Artist, ISRC (if available), Year, BPM, Genre, and descriptive tags (e.g., 'preoperative waiting' or 'relaxation').
   - Add a short intended-use note, such as "instrumental background for a waiting area; loopable." Avoid claims that a track treats a condition or is suitable for every listener.

6) Licensing & distribution
   - Provide a simple license file describing allowed uses (clinical, non-commercial, redistribution rights), or contact info for licensing inquiries.
   - If you want to grant public clinical use, consider a permissive license or a clear per-use license.

7) Packaging and delivery
   - Zip the stems and metadata together and provide a short README and a low-bitrate preview for quick checking.
   - Share via cloud storage, or embed a download link on your site; include clear attribution/credits.

8) Clinical review and feedback
   - Ask clinical partners to review tracks in the intended context and iterate on tempo, timbre, transitions, and delivery.
   - Offer listener choice where practical, allow the track to be paused or stopped, and check accessibility and playback-device requirements with the care team.

9) Final delivery check
   - Confirm file names, metadata, license, attribution, and destination links before sharing.
   - Keep a copy of the exact approved master and the delivery notes for later updates.
