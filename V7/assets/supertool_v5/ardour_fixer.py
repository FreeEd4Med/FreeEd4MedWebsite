import os
def analyze_and_report(file_path, ref_spec=None, ref_name="", options=None, out_dir=None):
    filename = file_path.name
    is_mp3 = file_path.suffix.lower() == ".mp3"

    stats = get_main_stats(file_path)
    spec = get_spectrum(file_path)

    cur_lufs = stats["LUFS"]
    cur_tp = stats["TP"]
    lra = stats["LRA"]
    phase = stats["Phase"]

    # --- CALCULATIONS ---
    lufs_diff = TEMPLATE_TARGET_LUFS - cur_lufs
    rec_lsp_input = KNOB_LSP_INPUT + lufs_diff
    rec_calf_thresh = KNOB_CALF_THRESH - lufs_diff

    projected_peak = cur_tp + lufs_diff
    limiter_load = 0.0
    if projected_peak > KNOB_LOUDMAX_THRESH:
        limiter_load = projected_peak - KNOB_LOUDMAX_THRESH

    # --- COLOR LOGIC ---
    if -15.0 <= cur_lufs <= -14.0:
        lufs_color = GREEN
    elif abs(cur_lufs - TEMPLATE_TARGET_LUFS) < 2.5:
        lufs_color = YELLOW
    else:
        lufs_color = RED

    crest_factor = cur_tp - cur_lufs
    dr_msg = f"{crest_factor:.1f}"
    if crest_factor < MIN_DYNAMIC_RANGE:
        dr_color = RED
    elif crest_factor < 11.0:
        dr_color = YELLOW
    else:
        dr_color = GREEN

    # LRA guidance (low LRA suggests over-compression)
    if lra < 4.0:
        lra_color = RED
    elif lra < 7.0:
        lra_color = YELLOW
    else:
        lra_color = GREEN

    phase_msg = f"{phase:.2f}"
    phase_action = ""
    if phase < 0:
        phase_color = RED
        phase_action = " [PHASE ISSUES: Narrow Width!]"
    elif phase < 0.3:
        phase_color = YELLOW
        phase_action = " [Very Wide: Check Mono]"
    else:
        phase_color = GREEN
        phase_action = ""

    # --- EQ LOGIC ---
    eq_notes = []

    if spec["LowMid"] > spec["Bass"]:
        diff = spec["LowMid"] - spec["Bass"]
        eq_notes.append(f"Cut 200Hz -{diff:.1f}dB (Mud)")
    if spec["Mid"] > spec["UpMid"] + 3.0:
        diff = spec["Mid"] - (spec["UpMid"] + 3.0)
        eq_notes.append(f"Cut 400Hz -{diff:.1f}dB (Boxy)")
    if spec["Sub"] > spec["Bass"] + 6.0:
        diff = spec["Sub"] - (spec["Bass"] + 6.0)
        eq_notes.append(f"Cut 40Hz -{diff:.1f}dB (Boomy)")
    if spec["Pres"] > spec["UpMid"] + 2.0:
        diff = spec["Pres"] - (spec["UpMid"] + 2.0)
        eq_notes.append(f"Cut 3kHz -{diff:.1f}dB (Bite)")
    if spec["Air"] < spec["Treble"] - 12.0:
        diff = (spec["Treble"] - 12.0) - spec["Air"]
        eq_notes.append(f"Boost 10kHz+ +{diff:.1f}dB (Dull)")
    elif spec["Air"] > spec["Treble"]:
        diff = spec["Air"] - spec["Treble"]
        eq_notes.append(f"Cut 12kHz -{diff:.1f}dB (Hiss)")

    if eq_notes:
        eq_action = " | ".join(eq_notes)
        eq_color = YELLOW
    else:
        eq_action = "Balanced (Leave EQ Flat)"
        eq_color = GREEN

    # Reference comparison (tonal diff per band)
    ref_notes = []
    if ref_spec:
        for band in ["Sub", "Bass", "LowMid", "Mid", "UpMid", "Pres", "Treble", "Air"]:
            diff = spec.get(band, 0.0) - ref_spec.get(band, 0.0)
            if diff > 2.5:
                ref_notes.append(f"Cut {band} {diff:+.1f}dB")
            elif diff < -2.5:
                ref_notes.append(f"Boost {band} {diff:+.1f}dB")

    # --- PLUGIN LOGIC ---
    saturator_msg = "OFF"
    sat_color = CYAN
    if limiter_load > 2.0:
        saturator_msg = "ON (Drive ~2.0)"
        sat_color = RED
    elif limiter_load > 1.0:
        saturator_msg = "Optional"
        sat_color = YELLOW

    limit_msg = "Clean"
    limit_color = GREEN
    if limiter_load > 0:
        limit_color = RED if limiter_load > 2.0 else YELLOW
        limit_msg = f"-{limiter_load:<4.1f} dB"

    # --- REPORT ---
    log("-" * 60)
    log(f"SONG: {filename:<30}", CYAN)

    if is_mp3:
        log("   [WARN] MP3 input detected; metering is slightly less precise than WAV.", YELLOW)

    lufs_tag = status_tag(lufs_color)
    dr_tag = status_tag(dr_color)
    lra_tag = status_tag(lra_color)
    phase_tag = status_tag(phase_color)

    lufs_str = f"{lufs_color}{lufs_tag} {cur_lufs:>5.1f} LUFS{RESET}"
    dr_str = f"{dr_color}{dr_tag} {dr_msg:>4} dB{RESET}"
    lra_str = f"{lra_color}{lra_tag} {lra:>4.1f} LRA{RESET}"
    phase_str = f"{phase_color}{phase_tag} {phase_msg} {phase_action}{RESET}"

    print(f"   STATS: {lufs_str} | Crest: {dr_str} | LRA: {lra_str} | Phase: {phase_str}")
    report_lines.append(
        f"   STATS: {lufs_tag} {cur_lufs:>5.1f} LUFS | Crest: {dr_tag} {dr_msg:>4} dB | LRA: {lra_tag} {lra:>4.1f} LU | Phase: {phase_tag} {phase_msg} {phase_action}"
    )

    log(f"   SPECTRUM CHECK:", CYAN)
    log(f"     Sub:{spec['Sub']:.0f} | Bass:{spec['Bass']:.0f} | LoMid:{spec['LowMid']:.0f} | Mid:{spec['Mid']:.0f}", RESET)
    log(f"     UpMid:{spec['UpMid']:.0f} | Pres:{spec['Pres']:.0f} | Treb:{spec['Treble']:.0f} | Air:{spec['Air']:.0f}", RESET)

    if ref_spec:
        log(f"   REFERENCE ({ref_name}):", MAGENTA)
        if ref_notes:
            for i in range(0, len(ref_notes), 3):
                log(f"     {' | '.join(ref_notes[i:i+3])}", YELLOW)
        else:
            log("     [OK] Tonal balance matches reference", GREEN)

    log(f"   RECOMMENDATIONS:", CYAN)
    lsp_tag = status_tag(lufs_color)
    eq_tag = status_tag(eq_color)
    sat_tag = status_tag(sat_color)
    comp_tag = status_tag(YELLOW)
    limit_tag = status_tag(limit_color)
    log(f"   ├─ {lsp_tag} LSP Input Gain:    {rec_lsp_input:>5.1f} dB   (Set this knob)", GREEN)
    log(f"   ├─ {eq_tag} Calf EQ Actions:   {eq_action}", eq_color)
    log(f"   ├─ {sat_tag} Calf Saturator:    {saturator_msg}", sat_color)
    log(f"   ├─ {comp_tag} Calf Comp Thresh:  {rec_calf_thresh:>5.1f} dB   (Targeting Peaks)", YELLOW)
    log(f"   └─ {limit_tag} LoudMax GR:        {limit_msg}", limit_color)

    if options:
        if getattr(options, "plot", False):
            generate_plot(spec, ref_spec, file_path.stem, out_dir or OUTPUT_DIR_BASE)
        if getattr(options, "xray", False):
            run_mid_side_extraction(file_path, out_dir or OUTPUT_DIR_BASE)
        if getattr(options, "master", False):
            run_auto_master(file_path, out_dir or OUTPUT_DIR_BASE)

def generate_plot(target_spec, ref_spec, filename, out_dir):
    if not MATPLOTLIB_AVAIL:
        return

    bands = ["Sub", "Bass", "LowMid", "Mid", "UpMid", "Pres", "Treble", "Air"]
    t_vals = [target_spec.get(b, 0.0) for b in bands]

    plt.style.use('dark_background')
    fig, ax = plt.subplots(figsize=(10, 6))
    fig.patch.set_facecolor('black')
    ax.set_facecolor('black')

    ax.plot(bands, t_vals, label='Track', color='white', linewidth=2.4, marker='o', markersize=4)
    if ref_spec:
        r_vals = [ref_spec.get(b, 0.0) for b in bands]
        ax.plot(bands, r_vals, label='Reference', color='#9b59b6', linestyle='--', linewidth=2)
        ax.fill_between(bands, t_vals, r_vals, alpha=0.15, color='#8e44ad')

    ax.set_title(f"Spectrum: {filename}", color='white', fontsize=12, fontweight='bold')
    ax.set_ylabel("RMS Energy (dBFS)", color='gray')
    ax.grid(True, color='#8e44ad', alpha=0.2)

    legend = ax.legend(frameon=True, facecolor='black', edgecolor='#8e44ad')
    for text in legend.get_texts():
        text.set_color("white")

    out_path = out_dir / f"{filename}_spectrum.png"
    plt.savefig(out_path, dpi=100, bbox_inches='tight')
    plt.close()
    log(f"   [GRAPH] Saved visual report: {out_path.name}", MAGENTA)


def run_mid_side_extraction(file_path, out_dir):
    mid_file = out_dir / f"{file_path.stem}_MID.wav"
    side_file = out_dir / f"{file_path.stem}_SIDE.wav"
    log("   [X-RAY] Extracting Mid/Side layers...", MAGENTA)

    cmd = [
        "ffmpeg", "-y", "-nostats", "-i", str(file_path),
        "-filter_complex",
        "[0:a]asplit=2[a][b];[a]pan=mono|c0=0.5*c0+0.5*c1[mid];[b]pan=mono|c0=0.5*c0-0.5*c1[side]",
        "-map", "[mid]", str(mid_file), "-map", "[side]", str(side_file)
    ]
    try:
        subprocess.run(cmd, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        log(f"     └─ [OK] Created {mid_file.name} & {side_file.name}", GREEN)
    except Exception as e:
        log(f"     └─ [ERR] X-Ray failed: {e}", RED)


def run_auto_master(file_path, out_dir):
    out_file = out_dir / f"{file_path.stem}_MASTERED.wav"
    log(f"   [MASTER] Processing to {TEMPLATE_TARGET_LUFS} LUFS...", MAGENTA)

    cmd = [
        "ffmpeg", "-y", "-i", str(file_path),
        "-af", f"loudnorm=I={TEMPLATE_TARGET_LUFS}:TP={TEMPLATE_TARGET_TP}:LRA=11:print_format=summary",
        "-ar", "48000", "-c:a", "pcm_s24le",
        "-metadata", "comment=Mastered via ardour_fixer",
        str(out_file)
    ]
    try:
        subprocess.run(cmd, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        log(f"     └─ [OK] Exported: {out_file.name}", GREEN)
    except Exception as e:
        log(f"     └─ [ERR] Mastering failed: {e}", RED)

def get_ffmpeg_value(cmd):
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, encoding='utf-8', errors='replace')
        output = result.stderr
        i_matches = re.findall(r"I:\s+([-\d\.]+)", output)
        if i_matches:
            return float(i_matches[-1])
        return -99.0 
    except Exception:
        return -99.0

def get_phase_correlation(file_path):
    """Checks for phase issues using aphasemeter."""
    # We parse the mean phase correlation from the output
    cmd = [
        "ffmpeg", "-nostats", "-i", str(file_path),
        "-filter_complex", "aphasemeter=video=0", "-f", "null", "-"
    ]
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, encoding='utf-8', errors='replace')
        output = result.stderr
        # Look for "mean_phase" in the output line (often near end)
        # Output format example: "mean_phase: 0.854321"
        match = re.search(r"mean_phase:\s+([-\d\.]+)", output)
        if match:
            return float(match.group(1))
        return 1.0 # Default to perfect if failed
    except Exception:
        return 1.0

def analyze_8_bands(file_path):
    bands = {
        "Sub":       "lowpass=f=60",
        "Bass":      "highpass=f=60,lowpass=f=125",
        "LowMid":    "highpass=f=125,lowpass=f=250",
        "Mid":       "highpass=f=250,lowpass=f=500",
        "UpMid":     "highpass=f=500,lowpass=f=2000",
        "Pres":      "highpass=f=2000,lowpass=f=4000",
        "Treble":    "highpass=f=4000,lowpass=f=8000",
        "Air":       "highpass=f=8000"
    }
    results = {}
    for name, filter_str in bands.items():
        cmd = [
            "ffmpeg", "-nostats", "-i", str(file_path),
            "-filter_complex", f"{filter_str},ebur128=peak=true", "-f", "null", "-"
        ]
        results[name] = get_ffmpeg_value(cmd)
    return results

def analyze_and_report(file_path):
    filename = file_path.name
    is_mp3 = file_path.suffix.lower() == ".mp3"
    
    # 1. Main Analysis
    cmd_main = [
        "ffmpeg", "-nostats", "-i", str(file_path),
        "-filter_complex", "ebur128=peak=true", "-f", "null", "-"
    ]
    try:
        result = subprocess.run(cmd_main, capture_output=True, text=True, encoding='utf-8', errors='replace')
        output = result.stderr
        i_matches = re.findall(r"I:\s+([-\d\.]+)", output)
        tp_matches = re.findall(r"(?:TP|Peak):\s+([-\d\.]+)", output)
        
        if not i_matches: raise ValueError("Analysis Failed")
        cur_lufs = float(i_matches[-1])
        cur_tp = float(tp_matches[-1])
    except Exception:
        log(f"[ERR] {filename}: Analysis Failed", RED)
        return

    # 2. 8-Band Spectrum
    spec = analyze_8_bands(file_path)
    
    # 3. Phase Analysis
    phase = get_phase_correlation(file_path)

    # --- CALCULATIONS ---
    lufs_diff = TEMPLATE_TARGET_LUFS - cur_lufs
    rec_lsp_input = KNOB_LSP_INPUT + lufs_diff
    rec_calf_thresh = KNOB_CALF_THRESH - lufs_diff
    
    projected_peak = cur_tp + lufs_diff
    limiter_load = 0.0
    if projected_peak > KNOB_LOUDMAX_THRESH:
        limiter_load = projected_peak - KNOB_LOUDMAX_THRESH

    # --- COLOR LOGIC ---
    
    # LUFS (Strict -14 to -15)
    if -15.0 <= cur_lufs <= -14.0:
        lufs_color = GREEN
    elif abs(cur_lufs - TEMPLATE_TARGET_LUFS) < 2.5:
        lufs_color = YELLOW
    else:
        lufs_color = RED

    # Dynamics
    crest_factor = cur_tp - cur_lufs
    dr_msg = f"{crest_factor:.1f}"
    if crest_factor < MIN_DYNAMIC_RANGE:
        dr_color = RED
    elif crest_factor < 11.0:
        dr_color = YELLOW
    else:
        dr_color = GREEN

    # Phase Color & Msg
    # Range: +1 (Mono) to 0 (Wide) to -1 (Out of Phase)
    phase_msg = f"{phase:.2f}"
    phase_action = ""
    if phase < 0:
        phase_color = RED
        phase_action = " [PHASE ISSUES: Narrow Width!]"
    elif phase < 0.3:
        phase_color = YELLOW
        phase_action = " [Very Wide: Check Mono]"
    else:
        phase_color = GREEN
        phase_action = ""

    # --- EQ LOGIC ---
    eq_notes = []
    
    if spec["LowMid"] > spec["Bass"]:
        diff = spec["LowMid"] - spec["Bass"]
        eq_notes.append(f"Cut 200Hz -{diff:.1f}dB (Mud)")
    if spec["Mid"] > spec["UpMid"] + 3.0:
        diff = spec["Mid"] - (spec["UpMid"] + 3.0)
        eq_notes.append(f"Cut 400Hz -{diff:.1f}dB (Boxy)")
    if spec["Sub"] > spec["Bass"] + 6.0:
        diff = spec["Sub"] - (spec["Bass"] + 6.0)
        eq_notes.append(f"Cut 40Hz -{diff:.1f}dB (Boomy)")
    if spec["Pres"] > spec["UpMid"] + 2.0:
        diff = spec["Pres"] - (spec["UpMid"] + 2.0)
        eq_notes.append(f"Cut 3kHz -{diff:.1f}dB (Bite)")
    if spec["Air"] < spec["Treble"] - 12.0:
        diff = (spec["Treble"] - 12.0) - spec["Air"]
        eq_notes.append(f"Boost 10kHz+ +{diff:.1f}dB (Dull)")
    elif spec["Air"] > spec["Treble"]:
        diff = spec["Air"] - spec["Treble"]
        eq_notes.append(f"Cut 12kHz -{diff:.1f}dB (Hiss)")

    if eq_notes:
        eq_action = " | ".join(eq_notes)
        eq_color = YELLOW
    else:
        eq_action = "Balanced (Leave EQ Flat)"
        eq_color = GREEN

    # --- PLUGIN LOGIC ---
    saturator_msg = "OFF"
    sat_color = CYAN
    if limiter_load > 2.0:
        saturator_msg = "ON (Drive ~2.0)"
        sat_color = RED
    elif limiter_load > 1.0:
        saturator_msg = "Optional"
        sat_color = YELLOW

    limit_msg = "Clean"
    limit_color = GREEN
    if limiter_load > 0:
        limit_color = RED if limiter_load > 2.0 else YELLOW
        limit_msg = f"-{limiter_load:<4.1f} dB"

    # --- REPORT ---
    log("-" * 60)
    log(f"SONG: {filename:<30}", CYAN)

    if is_mp3:
        log("   [WARN] MP3 input detected; metering is slightly less precise than WAV.", YELLOW)

    # Stats Line (Added Phase)
    lufs_tag = status_tag(lufs_color)
    dr_tag = status_tag(dr_color)
    phase_tag = status_tag(phase_color)
    lufs_str = f"{lufs_color}{lufs_tag} {cur_lufs:>5.1f} LUFS{RESET}"
    dr_str = f"{dr_color}{dr_tag} {dr_msg:>4} dB{RESET}"
    phase_str = f"{phase_color}{phase_tag} {phase_msg} {phase_action}{RESET}"
    print(f"   STATS: {lufs_str} | Crest: {dr_str} | Phase: {phase_str}")
    report_lines.append(f"   STATS: {lufs_tag} {cur_lufs:>5.1f} LUFS | Crest: {dr_tag} {dr_msg:>4} dB | Phase: {phase_tag} {phase_msg} {phase_action}")

    # Spectrum Line
    log(f"   SPECTRUM CHECK:", CYAN)
    log(f"     Sub:{spec['Sub']:.0f} | Bass:{spec['Bass']:.0f} | LoMid:{spec['LowMid']:.0f} | Mid:{spec['Mid']:.0f}", RESET)
    log(f"     UpMid:{spec['UpMid']:.0f} | Pres:{spec['Pres']:.0f} | Treb:{spec['Treble']:.0f} | Air:{spec['Air']:.0f}", RESET)
    
    # Recommendations with tags for color coding in saved report
    log(f"   RECOMMENDATIONS:", CYAN)
    lsp_tag = status_tag(lufs_color)
    eq_tag = status_tag(eq_color)
    sat_tag = status_tag(sat_color)
    comp_tag = status_tag(YELLOW)
    limit_tag = status_tag(limit_color)
    log(f"   ├─ {lsp_tag} LSP Input Gain:    {rec_lsp_input:>5.1f} dB   (Set this knob)", GREEN)
    log(f"   ├─ {eq_tag} Calf EQ Actions:   {eq_action}", eq_color)
    log(f"   ├─ {sat_tag} Calf Saturator:    {saturator_msg}", sat_color)
    log(f"   ├─ {comp_tag} Calf Comp Thresh:  {rec_calf_thresh:>5.1f} dB   (Targeting Peaks)", YELLOW)
    log(f"   └─ {limit_tag} LoudMax GR:        {limit_msg}", limit_color)

def main():
    global TEMPLATE_TARGET_LUFS, TEMPLATE_TARGET_TP, MIN_DYNAMIC_RANGE, OUTPUT_DIR_BASE, DEFAULT_DIR

    parser = argparse.ArgumentParser(description="Ardour Mastering Assistant 8-Band + Phase + LRA")
    parser.add_argument("directory", nargs="?", default=str(DEFAULT_DIR), help="WAV/MP3 folder (ignored if --file is used)")
    parser.add_argument("--file", dest="single_file", default=None, help="Analyze a single WAV or MP3 file (WAV recommended)")
    parser.add_argument("--ref", dest="ref_file", default=None, help="Reference WAV/MP3 to compare spectrum")
    parser.add_argument("--out", dest="out_dir", default=None, help="Report/output folder")
    parser.add_argument("--target-lufs", type=float, default=TEMPLATE_TARGET_LUFS, help="Target integrated LUFS (default -14.0)")
    parser.add_argument("--target-tp", type=float, default=TEMPLATE_TARGET_TP, help="Target true peak dBFS (default -1.0)")
    parser.add_argument("--platform", choices=PLATFORMS.keys(), default="custom", help="Use a platform preset for targets")
    parser.add_argument("--min-dr", type=float, default=MIN_DYNAMIC_RANGE, help="Minimum crest factor/dynamic range (default 9.0)")
    parser.add_argument("--plot", action="store_true", help="Save PNG spectrum plot (requires matplotlib)")
    parser.add_argument("--xray", action="store_true", help="Export Mid/Side diagnostic WAVs")
    parser.add_argument("--master", action="store_true", help="Auto-master to target (experimental)")
    args = parser.parse_args()

    if args.platform != "custom":
        preset = PLATFORMS.get(args.platform, {})
        TEMPLATE_TARGET_LUFS = preset.get("lufs", TEMPLATE_TARGET_LUFS)
        TEMPLATE_TARGET_TP = preset.get("tp", TEMPLATE_TARGET_TP)
    else:
        TEMPLATE_TARGET_LUFS = args.target_lufs
        TEMPLATE_TARGET_TP = args.target_tp

    MIN_DYNAMIC_RANGE = args.min_dr

    if args.out_dir:
        OUTPUT_DIR_BASE = Path(args.out_dir).expanduser()

    files = []
    report_tag = ""

    if args.single_file:
        fpath = Path(args.single_file)
        if not fpath.exists():
            log(f"Error: File not found: {fpath}", RED)
            return
        if fpath.suffix.lower() not in (".wav", ".mp3"):
            log("Error: Only .wav or .mp3 supported (WAV recommended for accuracy).", RED)
            return
        files = [fpath]
        report_tag = fpath.stem
    else:
        search_path = Path(args.directory)
        if not search_path.exists():
            log(f"Error: Directory not found: {search_path}", RED)
            return
        files = sorted(list(search_path.glob("*.wav")) + list(search_path.glob("*.mp3")))
        report_tag = search_path.name

    if not files:
        log("No .wav or .mp3 files found.", YELLOW)
        return

    log("=" * 60)
    log(f"MASTERING REPORT FOR: {report_tag} | Target {TEMPLATE_TARGET_LUFS} LUFS / {TEMPLATE_TARGET_TP} dBTP")
    log("=" * 60)

    contains_mp3 = any(f.suffix.lower() == ".mp3" for f in files)
    if contains_mp3:
        log("[WARN] MP3 detected in set; LUFS/phase estimates slightly less precise than WAV.", YELLOW)

    log("Legend: [OK]=on target, [WARN]=check, [ISSUE]=fix", CYAN)

    ref_spec = None
    ref_name = ""
    if args.ref_file:
        ref_path = Path(args.ref_file)
        if ref_path.exists():
            log(f"[REF] Analyzing reference: {ref_path.name}", MAGENTA)
            ref_spec = get_spectrum(ref_path)
            ref_name = ref_path.name
        else:
            log(f"[WARN] Reference not found: {ref_path}", YELLOW)

    for file in files:
        analyze_and_report(file, ref_spec=ref_spec, ref_name=ref_name, options=args, out_dir=OUTPUT_DIR_BASE)

    OUTPUT_DIR_BASE.mkdir(parents=True, exist_ok=True)
    report_filename = f"mastering_report_{report_tag}.txt"
    final_report_path = OUTPUT_DIR_BASE / report_filename

    try:
        with open(final_report_path, "w", encoding='utf-8') as f:
            f.write("\n".join(report_lines))
        print(f"\n{GREEN}[SUCCESS] Report saved to:{RESET} {final_report_path}")
    except Exception as e:
        print(f"\n{RED}[ERR] Could not save report: {e}{RESET}")

if __name__ == "__main__":
    main()
