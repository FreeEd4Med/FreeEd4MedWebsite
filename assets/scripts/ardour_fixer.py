import os
import subprocess
import re
import argparse
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

# --- Dependency Check (Colorama) ---
try:
    import colorama
    from colorama import Fore, Style
    colorama.init(autoreset=True)
    CYAN = Fore.CYAN
    GREEN = Fore.GREEN
    YELLOW = Fore.YELLOW
    RED = Fore.RED
    RESET = Style.RESET_ALL
except ImportError:
    CYAN = GREEN = YELLOW = RED = RESET = ""

# --- Smart Path Configuration ---
MICHAEL_PATH = Path("/media/Multimedia/Music4Pub/PRE-Mastered/Digital Renegade")
MICHAEL_OUT = Path("/media/Multimedia/Music4Pub/scripts/outputs")
HOME = Path.home()
STUDENT_PATH = HOME / "Music" / "PRE-Mastered"
STUDENT_OUT = HOME / "Music" / "Mastering_Reports"

if MICHAEL_PATH.exists():
    DEFAULT_DIR = MICHAEL_PATH
    OUTPUT_DIR_BASE = MICHAEL_OUT
else:
    DEFAULT_DIR = STUDENT_PATH
    OUTPUT_DIR_BASE = STUDENT_OUT

# --- Mastering Targets ---
TEMPLATE_TARGET_LUFS = -14.0
TEMPLATE_TARGET_TP = -1.0
MIN_DYNAMIC_RANGE = 9.0

# --- Ardour Template Defaults ---
KNOB_CALF_THRESH = -13.0
KNOB_LSP_INPUT = 1.4
KNOB_LOUDMAX_THRESH = -1.0

# Global list for report
report_lines = []

def log(text, color_code=None):
    if color_code:
        print(f"{color_code}{text}{RESET}")
    else:
        print(text)
    clean_text = re.sub(r'\x1b\[[0-9;]*m', '', str(text)) 
    report_lines.append(clean_text)

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
    
    # Stats Line (Added Phase)
    lufs_str = f"{lufs_color}{cur_lufs:>5.1f} LUFS{RESET}"
    dr_str = f"{dr_color}{dr_msg:>4} dB{RESET}"
    phase_str = f"{phase_color}{phase_msg} {phase_action}{RESET}"
    print(f"   STATS: {lufs_str} | Crest: {dr_str} | Phase: {phase_str}")
    report_lines.append(f"   STATS: {cur_lufs:>5.1f} LUFS | Crest: {dr_msg:>4} dB | Phase: {phase_msg} {phase_action}")

    # Spectrum Line
    log(f"   SPECTRUM CHECK:", CYAN)
    log(f"     Sub:{spec['Sub']:.0f} | Bass:{spec['Bass']:.0f} | LoMid:{spec['LowMid']:.0f} | Mid:{spec['Mid']:.0f}", RESET)
    log(f"     UpMid:{spec['UpMid']:.0f} | Pres:{spec['Pres']:.0f} | Treb:{spec['Treble']:.0f} | Air:{spec['Air']:.0f}", RESET)
    
    # Recommendations
    log(f"   RECOMMENDATIONS:", CYAN)
    log(f"   ├─ LSP Input Gain:    {rec_lsp_input:>5.1f} dB   (Set this knob)", GREEN)
    log(f"   ├─ Calf EQ Actions:   {eq_action}", eq_color)
    log(f"   ├─ Calf Saturator:    {saturator_msg}", sat_color)
    log(f"   ├─ Calf Comp Thresh:  {rec_calf_thresh:>5.1f} dB   (Targeting Peaks)", YELLOW)
    log(f"   └─ LoudMax GR:        {limit_msg}", limit_color)

def main():
    parser = argparse.ArgumentParser(description="Ardour Mastering Assistant 8-Band + Phase")
    parser.add_argument("directory", nargs="?", default=str(DEFAULT_DIR), help="WAV Folder")
    args = parser.parse_args()
    search_path = Path(args.directory)
    
    if not search_path.exists():
        log(f"Error: Directory not found: {search_path}", RED)
        return

    log("=" * 60)
    log(f"MASTERING REPORT FOR: {search_path.name}")
    log("=" * 60)

    files = sorted(list(search_path.glob("*.wav")))
    if not files:
        log("No .wav files found.", YELLOW)
        return

    for file in files:
        analyze_and_report(file)

    OUTPUT_DIR_BASE.mkdir(parents=True, exist_ok=True)
    report_filename = f"mastering_report_{search_path.name}.txt"
    final_report_path = OUTPUT_DIR_BASE / report_filename

    try:
        with open(final_report_path, "w", encoding='utf-8') as f:
            f.write("\n".join(report_lines))
        print(f"\n{GREEN}[SUCCESS] Report saved to:{RESET} {final_report_path}")
    except Exception as e:
        print(f"\n{RED}[ERR] Could not save report: {e}{RESET}")

if __name__ == "__main__":
    main()
