#!/bin/bash

# ==============================================================================
# FreeEd4Med Media Station v10.19 [The "Complete" Update]
# Evidence-Based Med Ed + Music For Healing
# Features: Pro Fonts, Grid Alignment, Fixed Aegisub, AI Whisper, Visualizers
# ==============================================================================

# --- Branding Colors ---
PURPLE='\033[1;35m'
CYAN='\033[0;36m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# --- AUTO-ACTIVATE CONDA ---
source ~/miniconda3/etc/profile.d/conda.sh
conda activate audio_tools 2>/dev/null

# --- Dependencies Check ---
check_dependencies() {
    local missing=0
    for cmd in ffmpeg ffprobe bc; do
        if ! command -v $cmd &> /dev/null; then
            echo -e "${RED}Error: $cmd is not installed.${NC}"
            missing=1
        fi
    done
    if [ $missing -eq 1 ]; then
        echo "Please install dependencies: sudo apt install ffmpeg bc"
        exit 1
    fi
}

# --- Helper Functions ---
pause(){
    read -p "Press [Enter] key to continue..."
}

get_input_file(){
    local prompt_text="${1:-Drag and drop your INPUT file here (or type path):}"
    echo -e "${CYAN}$prompt_text${NC}"
    read -r input_file
    input_file="${input_file%\'}"
    input_file="${input_file#\'}"
    input_file="${input_file%\"}"
    input_file="${input_file#\"}"
    if [[ ! -f "$input_file" ]]; then
        echo -e "${RED}Error: File not found!${NC}"
        pause
        return 1
    fi
    return 0
}

get_second_file(){
    local prompt_text="$1"
    echo -e "${CYAN}$prompt_text${NC}"
    read -r second_file
    second_file="${second_file%\'}"
    second_file="${second_file#\'}"
    second_file="${second_file%\"}"
    second_file="${second_file#\"}"
    if [[ ! -f "$second_file" ]]; then
        echo -e "${RED}Error: File not found!${NC}"
        pause
        return 1
    fi
    return 0
}

get_output_name(){
    read -p "Enter name for output file (e.g., video.mp4): " output_name
}

escape_subtitles_path(){
    local value="$1"
    value="${value//\\/\\\\}"
    value="${value//\'/\\\'}"
    echo "$value"
}

# --- NEW: Combined Typography & Alignment Engine ---
get_lyric_style(){
    echo -e "${PURPLE}--- Lyric Customization ---${NC}"

    # 1. Font Face
    echo -e "${CYAN}--- Font Family ---${NC}"
    echo "1. Arial (Standard Sans)"
    echo "2. Times New Roman (Serif)"
    echo "3. Courier New (Typewriter)"
    echo "4. Comic Sans MS (Comic)"
    echo "5. Impact (Bold Meme)"
    echo "6. Custom Name"
    read -p "Select Font [1]: " font_sel
    case $font_sel in
        2) font_name="Times New Roman" ;;
        3) font_name="Courier New" ;;
        4) font_name="Comic Sans MS" ;;
        5) font_name="Impact" ;;
        6) read -p "Enter Exact Font Name: " font_name ;;
        *) font_name="Arial" ;;
    esac
    font_size="28"

    # 2. Font Color
    echo -e "${CYAN}--- Font Color ---${NC}"
    echo "1. White"
    echo "2. Yellow"
    echo "3. Cyan"
    echo "4. Purple"
    echo "5. Black"
    read -p "Select Color [1]: " col_sel
    case $col_sel in
        2) font_color="&H0000FFFF" ;;
        3) font_color="&H00FFFF00" ;;
        4) font_color="&H00800080" ;;
        5) font_color="&H00000000" ;;
        *) font_color="&H00FFFFFF" ;;
    esac

    # 3. Outline & Shadow
    echo -e "${CYAN}--- Effects ---${NC}"
    echo "1. Standard (Black Outline + Shadow)"
    echo "2. Clean (No Outline, No Shadow)"
    echo "3. Hard Outline Only"
    echo "4. Soft Shadow Only"
    read -p "Select Effect [1]: " eff_sel
    case $eff_sel in
        2) outline_width="0"; shadow_depth="0" ;;
        3) outline_width="3"; shadow_depth="0" ;;
        4) outline_width="0"; shadow_depth="3" ;;
        *) outline_width="2"; shadow_depth="2" ;;
    esac
    outline_color="&H00000000"
    shadow_color="&H80000000"

    # 4. Positioning & Text Alignment
    echo -e "${CYAN}--- Positioning & Text Alignment ---${NC}"
    echo "Vertical Position:"
    echo "1. Bottom (Standard)"
    echo "2. Middle (Center Screen)"
    echo "3. Top (Header)"
    read -p "Select Vertical [1]: " vert_sel

    echo "Horizontal Position:"
    echo "1. Left"
    echo "2. Center"
    echo "3. Right"
    read -p "Select Horizontal [2]: " horiz_pos

    echo "Text Justification:"
    echo "1. Left"
    echo "2. Center"
    echo "3. Right"
    echo "4. Justified"
    read -p "Select Justification [2]: " justify_sel

    [[ -z "$vert_sel" ]] && vert_sel="1"
    [[ -z "$horiz_pos" ]] && horiz_pos="2"
    [[ -z "$justify_sel" ]] && justify_sel="2"

    # Set horizontal mode from position
    horiz_mode="center"
    case $horiz_pos in
        1) horiz_mode="left" ;;
        2) horiz_mode="center" ;;
        3) horiz_mode="right" ;;
    esac

    # Set wrap style from justification
    wrap_style="1"
    case $justify_sel in
        1) wrap_style="0" ;;
        2) wrap_style="1" ;;
        3) wrap_style="2" ;;
        4) wrap_style="3" ;;
    esac

    margin_l="0"
    margin_r="0"

    if [[ "$vert_sel" == "3" ]]; then
        margin_v="0"
        case $horiz_mode in
            left) align=7 ;;
            right) align=9 ;;
            *) align=8 ;;
        esac
    elif [[ "$vert_sel" == "2" ]]; then
        margin_v="0"
        case $horiz_mode in
            left) align=4 ;;
            right) align=6 ;;
            *) align=5 ;;
        esac
    else
        margin_v="0"
        case $horiz_mode in
            left) align=1 ;;
            right) align=3 ;;
            *) align=2 ;;
        esac
    fi

    echo -e "${YELLOW}Vertical: $vert_sel | Horizontal: $horiz_pos | Justification: $justify_sel | ASS Code: $align | MarginV: $margin_v | WrapStyle: $wrap_style${NC}"
}

get_waveform_color(){
    echo -e "${CYAN}--- Choose Waveform Color ---${NC}"
    echo "1. White (Default)"
    echo "2. Black"
    echo "3. MadMooze Purple (violet)"
    echo "4. Cyan"
    echo "5. Custom"
    read -p "Select Color [1-5]: " col_choice
    case $col_choice in
        2) wave_color="black" ;;
        3) wave_color="violet" ;;
        4) wave_color="cyan" ;;
        5) read -p "Enter Color Name or Hex: " wave_color ;;
        *) wave_color="white" ;;
    esac
}

# ==============================================================================
# MODULE 1: Creation & Lyric Videos (v10.19)
# ==============================================================================
menu_standard_video(){
    clear
    echo -e "${PURPLE}--- Creation Module v10.19 ---${NC}"
    echo "1. Generate Subtitles (AI Whisper - Auto Sync)"
    echo "2. Edit Subtitles (Launch Aegisub)"
    echo "3. Render Lyric Video (Burn Lyrics)"
    echo "4. Static Image + Song (Full Length)"
    echo "5. Loop Short Clip + Song"
    echo "6. Slideshow from Folder"
    echo "7. Return"
    echo
    read -p "Select: " choice
    case $choice in
        1)
            # AI WHISPER GENERATOR
            echo -e "${CYAN}--- AI Lyric Generator (Whisper) ---${NC}"
            if ! command -v whisper &> /dev/null; then
                echo -e "${RED}Error: OpenAI Whisper not found.${NC}"
                echo "Run: pip install openai-whisper"
                pause; return
            fi
            
            get_input_file "Drag Audio File (Vocals/Song):"
            echo -e "${PURPLE}Listening and transcribing... (This may take a minute)${NC}"
            
            output_dir=$(dirname "$input_file")
            whisper "$input_file" --model small --output_format srt --output_dir "$output_dir"
            
            srt_name="$(basename "${input_file%.*}").srt"
            full_srt_path="$output_dir/$srt_name"
            
            echo -e "${GREEN}Success! Created: $full_srt_path${NC}"
            pause
            ;;
        2)
            # AEGISUB LAUNCHER (Bulletproof Mode)
            echo -e "${CYAN}Launching Aegisub Editor...${NC}"
            export WXSUPPRESS_SIZER_FLAGS_CHECK=1
            
            if dpkg -L aegisub 2>/dev/null | grep -E "bin/aegisub" | head -n 1 > /tmp/aegisub_path; then
                exe_path=$(cat /tmp/aegisub_path)
                if [ -x "$exe_path" ]; then
                    "$exe_path" &
                    return
                fi
            fi
            
            # Fallbacks
            if [ -x "/usr/bin/aegisub-3.2" ]; then
                /usr/bin/aegisub-3.2 &
            elif command -v aegisub &> /dev/null; then
                aegisub &
            else
                echo -e "${RED}Aegisub executable not found.${NC}"
                echo "Try reinstalling: sudo apt install --reinstall aegisub"
                pause
            fi
            ;;
        3)
            # RENDER LYRIC VIDEO
            echo -e "${CYAN}--- Render Lyric Video ---${NC}"
            get_input_file "Drag Background IMAGE:"
            img_f="$input_file"
            get_second_file "Drag SONG Audio:"
            aud_f="$second_file"
            
            echo -e "${CYAN}Drag the .SRT file:${NC}"
            read -r srt_f
            srt_f="${srt_f%\'}"; srt_f="${srt_f#\'}"; srt_f="${srt_f%\"}"; srt_f="${srt_f#\"}"
            
            # GET FULL STYLES
            get_lyric_style
            
            output_dir=$(dirname "$img_f")
            read -p "Enter output filename (e.g. video.mp4): " fname
            output_name="$output_dir/$fname"
            
            echo -e "${PURPLE}Rendering to $output_name...${NC}"
            
            escaped_srt=$(escape_subtitles_path "$srt_f")
            style_font_name="${font_name//\\/\\\\}"
            style_font_name="${style_font_name//\'/\\\'}"
            style_string="Format=ASS,FontName=${style_font_name},FontSize=${font_size},PrimaryColour=${font_color},SecondaryColour=&H00000000,OutlineColour=${outline_color},BackColour=${shadow_color},BorderStyle=1,Outline=${outline_width},Shadow=${shadow_depth},Alignment=${align},MarginV=${margin_v},MarginL=${margin_l},MarginR=${margin_r},WrapStyle=${wrap_style}"
            filter_graph="subtitles=${escaped_srt}:force_style='${style_string}'"
            
            if ffmpeg -loop 1 -i "$img_f" -i "$aud_f" \
                -vf "$filter_graph" \
                -c:v libx264 -tune stillimage -c:a aac -b:a 320k -pix_fmt yuv420p -shortest "$output_name"; then
                echo -e "${GREEN}Video Saved!${NC}"
                rm "$temp_ass"
            else
                echo -e "${RED}ffmpeg rendering failed. Check the filter options above for clues.${NC}"
                rm "$temp_ass"
            fi
            pause
            ;;
        4)
            get_input_file "Drag Background IMAGE:"
            get_second_file "Drag SONG:"
            get_output_name
            ffmpeg -loop 1 -i "$input_file" -i "$second_file" -c:v libx264 -tune stillimage -c:a aac -b:a 320k -pix_fmt yuv420p -shortest "$output_name"
            pause
            ;;
        5)
            echo -e "${CYAN}Select SHORT VIDEO loop:${NC}"
            get_input_file 
            get_second_file "Drag SONG:"
            get_output_name
            vid_dur=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$input_file")
            aud_dur=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$second_file")
            loop_count=$(echo "$aud_dur / $vid_dur" | bc)
            ffmpeg -stream_loop "$loop_count" -i "$input_file" -i "$second_file" -map 0:v -map 1:a -c:v libx264 -shortest -pix_fmt yuv420p "$output_name"
            pause
            ;;
        6)
            echo -e "${CYAN}Folder must contain img001.jpg, img002.jpg...${NC}"
            read -p "Enter folder path: " img_dir
            get_output_name
            ffmpeg -framerate 0.5 -pattern_type glob -i "$img_dir/*.jpg" -c:v libx264 -pix_fmt yuv420p "$output_name"
            pause
            ;;
        7) return ;;
    esac
}

# ==============================================================================
# MODULE 2: Visualizer Lab
# ==============================================================================
menu_visualizers(){
    clear
    echo -e "${PURPLE}--- Visualizer Lab v10.19 ---${NC}"
    echo "1. The Portal (Circular Waveform)"
    echo "2. Symmetrical Waves (Cline Mode)"
    echo "3. MadMooze Master (Spectrum + Waves)"
    echo "4. Scrolling Spectrum (Heatmap)"
    echo "5. Mandelbrot Zoom (Fractal)"
    echo "6. Static Thumbnails (BBC & FFmpeg)"
    echo "7. Return"
    echo
    read -p "Select: " choice
    case $choice in
        1)
            echo -e "${CYAN}--- The Portal (Circular) ---${NC}"
            get_input_file "Drag Background IMAGE:"
            bg_file="$input_file"
            get_second_file "Drag AUDIO:"
            aud_file="$second_file"
            get_waveform_color
            get_output_name
            echo -e "${PURPLE}Warping space-time...${NC}"
            ffmpeg -i "$aud_file" -loop 1 -i "$bg_file" \
            -filter_complex "[1:v]scale=1280:720:force_original_aspect_ratio=increase,crop=1280:720[bg]; \
             [0:a]aformat=channel_layouts=mono,showwaves=s=1280x720:mode=cline:colors=${wave_color}:draw=full,geq='p(mod(W/PI*(PI+atan2(H/2-Y,X-W/2)),W), H-2*hypot(H/2-Y,X-W/2))':a='alpha(mod(W/PI*(PI+atan2(H/2-Y,X-W/2)),W), H-2*hypot(H/2-Y,X-W/2))'[a]; \
             [bg][a]overlay=(W-w)/2:(H-h)/2:shortest=1" \
            -c:v libx264 -pix_fmt yuv420p -preset fast -c:a copy "$output_name"
            ;;
        2)
            echo -e "${CYAN}--- Symmetrical Visualizer ---${NC}"
            get_input_file "Drag Background IMAGE:"
            bg_file="$input_file"
            get_second_file "Drag AUDIO:"
            aud_file="$second_file"
            get_waveform_color
            get_output_name
            ffmpeg -i "$aud_file" -loop 1 -i "$bg_file" \
            -filter_complex "[0:a]aformat=channel_layouts=mono,showwaves=s=1280x720:mode=cline:rate=30:colors=${wave_color}[waveform]; \
             [1:v]scale=1280:720:force_original_aspect_ratio=increase,crop=1280:720[bg]; \
             [bg][waveform]overlay=shortest=1" \
            -pix_fmt yuv420p -r 30 -tune fastdecode -c:a copy "$output_name"
            ;;
        3)
            get_input_file "Drag AUDIO:"
            read -p "Song Title: " v_title
            read -p "Artist: " v_artist
            get_output_name
            ffmpeg -i "$input_file" -filter_complex \
            "[0:a]avectorscope=s=640x518,pad=1280:720[vs]; \
             [0:a]showspectrum=mode=separate:color=magma:scale=cbrt:s=640x518[ss]; \
             [0:a]showwaves=s=1280x202:mode=line:colors=violet[sw]; \
             [vs][ss]overlay=w[bg]; \
             [bg][sw]overlay=0:H-h,drawtext=fontcolor=white:fontsize=24:x=20:y=20:text='${v_title} - ${v_artist}'[out]" \
            -map "[out]" -map 0:a -c:v libx264 -preset fast -crf 18 -c:a copy "$output_name"
            ;;
        4)
            get_input_file "Drag AUDIO:"
            get_output_name
            ffmpeg -i "$input_file" -filter_complex \
            "[0:a]showspectrum=slide=scroll:mode=combined:color=magma:fscale=log:scale=sqrt:legend=1:s=1920x1080[v]" \
            -map "[v]" -map 0:a -c:v libx264 -preset fast -crf 18 -c:a copy "$output_name"
            ;;
        5)
            get_input_file "Drag AUDIO:"
            get_output_name
            ffmpeg -i "$input_file" -f lavfi -i mandelbrot=s=1280x720:rate=25 -filter_complex \
            "[0:a]showwaves=mode=line:s=1280x720:colors=violet@0.6|cyan@0.6:scale=sqrt[waves]; \
             [1:v][waves]overlay=format=auto[out]" \
            -map "[out]" -map 0:a -c:v libx264 -preset ultrafast -c:a copy -shortest "$output_name"
            ;;
        6)
            get_input_file "Drag AUDIO:"
            base_name="${input_file%.*}"
            get_waveform_color
            if command -v audiowaveform &> /dev/null; then
                echo -e "${PURPLE}Using BBC Audiowaveform...${NC}"
                case $wave_color in "white") h="ffffff";; "black") h="000000";; "violet") h="8A2BE2";; "cyan") h="00FFFF";; *) h="ffffff";; esac
                [[ "$wave_color" == \#* ]] && h="${wave_color#\#}"
                audiowaveform -i "$input_file" -o "${base_name}_bbc_wave.png" -w 1280 -h 720 --no-axis-labels --background-color 00000000 --waveform-color "$h"
                echo -e "${GREEN}Generated: ${base_name}_bbc_wave.png${NC}"
            fi
            echo -e "${PURPLE}Generating FFmpeg Transparent Wave...${NC}"
            ffmpeg -y -i "$input_file" -filter_complex "aformat=channel_layouts=mono,showwavespic=s=1280x720:colors=${wave_color}" -frames:v 1 "${base_name}_transparent.png"
            echo -e "${GREEN}Generated: ${base_name}_transparent.png${NC}"
            pause
            ;;
        7) return ;;
    esac
    if [ "$choice" != "6" ]; then
        echo -e "${GREEN}Rendering Complete!${NC}"
        pause
    fi
}

# ==============================================================================
# MODULE 3: Branding & Metadata
# ==============================================================================
menu_branding(){
    clear
    echo -e "${PURPLE}--- Branding & Post-Production ---${NC}"
    echo "1. Stitch Intro + Main + Outro"
    echo "2. Pro Metadata Editor (Format Aware)"
    echo "3. Add Smart Logo / Watermark (Resize & Position)"
    echo "4. Return"
    echo
    read -p "Select: " choice
    case $choice in
        1)
            get_input_file "Select INTRO video:"
            intro="$input_file"
            get_input_file "Select MAIN video:"
            main="$input_file"
            get_input_file "Select OUTRO video:"
            outro="$input_file"
            get_output_name
            echo "Stitching..."
            ffmpeg -i "$intro" -i "$main" -i "$outro" \
            -filter_complex "[0:v]scale=1920:1080:force_original_aspect_ratio=decrease,pad=1920:1080:(ow-iw)/2:(oh-ih)/2,setsar=1[v0]; \
            [1:v]scale=1920:1080:force_original_aspect_ratio=decrease,pad=1920:1080:(ow-iw)/2:(oh-ih)/2,setsar=1[v1]; \
            [2:v]scale=1920:1080:force_original_aspect_ratio=decrease,pad=1920:1080:(ow-iw)/2:(oh-ih)/2,setsar=1[v2]; \
            [v0][0:a][v1][1:a][v2][2:a]concat=n=3:v=1:a=1[v][a]" \
            -map "[v]" -map "[a]" -c:v libx264 -c:a aac "$output_name"
            ;;
        2)
            get_input_file "Drag AUDIO FILE:"
            ext="${input_file##*.}"
            ext=$(echo "$ext" | tr '[:upper:]' '[:lower:]')
            if [[ "$ext" == "wav" ]]; then
                echo -e "${RED}[!] WARNING: WAV detected. Tags may not save.${NC}"
                read -p "Convert to FLAC for better tags? (y/n): " conv
                if [[ "$conv" == "y" ]]; then
                    new_f="${input_file%.*}.flac"
                    ffmpeg -i "$input_file" -compression_level 5 "$new_f"
                    input_file="$new_f"
                fi
            fi
            read -p "Title: " m_title
            read -p "Artist: " m_artist
            read -p "Album: " m_album
            read -p "Year: " m_year
            read -p "Composer (Producer): " m_composer
            read -p "Copyright: " m_copyright
            read -p "Comment (Website): " m_comment
            get_output_name
            cmd="ffmpeg -i \"$input_file\" -map_metadata 0"
            if [[ "$output_name" == *".mp3" ]]; then cmd+=" -id3v2_version 3"; fi
            [ -n "$m_title" ] && cmd+=" -metadata title=\"$m_title\""
            [ -n "$m_artist" ] && cmd+=" -metadata artist=\"$m_artist\""
            [ -n "$m_album" ] && cmd+=" -metadata album=\"$m_album\""
            [ -n "$m_year" ] && cmd+=" -metadata date=\"$m_year\""
            [ -n "$m_composer" ] && cmd+=" -metadata composer=\"$m_composer\""
            [ -n "$m_copyright" ] && cmd+=" -metadata copyright=\"$m_copyright\""
            if [ -n "$m_comment" ]; then
                cmd+=" -metadata comment=\"$m_comment\" -metadata description=\"$m_comment\""
            fi
            cmd+=" -c copy \"$output_name\""
            eval "$cmd"
            ;;
        3)
            get_input_file "Drag VIDEO file:"
            vid_file="$input_file"
            get_second_file "Drag LOGO/IMAGE file:"
            logo_file="$second_file"
            echo -e "${CYAN}Select Logo Size:${NC}"
            echo "1. Small (10%)"
            echo "2. Medium (20%)"
            echo "3. Large (30%)"
            echo "4. XL (40%)"
            echo "5. Giant (50%)"
            read -p "Choice [2]: " sz_choice
            case $sz_choice in
                1) scale_factor="0.10" ;;
                3) scale_factor="0.30" ;;
                4) scale_factor="0.40" ;;
                5) scale_factor="0.50" ;;
                *) scale_factor="0.20" ;;
            esac
            echo -e "${CYAN}Select Position:${NC}"
            echo "1. Bottom-Right"
            echo "2. Bottom-Left"
            echo "3. Top-Right"
            echo "4. Top-Left"
            echo "5. Center"
            read -p "Choice [1]: " pos_choice
            case $pos_choice in
                2) overlay_cmd="x=20:y=H-h-20" ;;
                3) overlay_cmd="x=W-w-20:y=20" ;;
                4) overlay_cmd="x=20:y=20" ;;
                5) overlay_cmd="x=(W-w)/2:y=(H-h)/2" ;;
                *) overlay_cmd="x=W-w-20:y=H-h-20" ;;
            esac
            echo -e "${CYAN}Select Style:${NC}"
            echo "1. Solid Logo (100% visible)"
            echo "2. Watermark (50% transparent)"
            echo "3. Ghost (30% transparent)"
            read -p "Choice [1]: " op_choice
            case $op_choice in
                2) opacity="0.5" ;;
                3) opacity="0.3" ;;
                *) opacity="1.0" ;;
            esac
            get_output_name
            ffmpeg -i "$vid_file" -i "$logo_file" \
            -filter_complex "[1:v][0:v]scale2ref=w=iw*${scale_factor}:h=-1[logo][main]; \
             [logo]format=rgba,colorchannelmixer=aa=${opacity}[transp_logo]; \
             [main][transp_logo]overlay=${overlay_cmd}" \
            -c:v libx264 -c:a copy "$output_name"
            ;;
        4) return ;;
    esac
    echo -e "${GREEN}Done!${NC}"
    pause
}

# ==============================================================================
# MODULE 5: Social Media Batch
# ==============================================================================
menu_social_utils(){
    clear
    echo -e "${PURPLE}--- Social Media Batch Generator ---${NC}"
    echo "1. Generate TikTok + YouTube + X (Twitter) Versions"
    echo "2. Return"
    read -p "Select: " choice
    case $choice in
        1)
            get_input_file
            base_name="${input_file%.*}"
            echo -e "${PURPLE}1/3 Generating TikTok Version...${NC}"
            ffmpeg -i "$input_file" -vf "split[original][copy];[copy]scale=-1:1920,boxblur=20:20[blurred];[blurred]crop=1080:1920[bg];[bg][original]overlay=(W-w)/2:(H-h)/2" -c:a copy "${base_name}_TikTok.mp4"
            echo -e "${PURPLE}2/3 Generating YouTube Version...${NC}"
            ffmpeg -y -i "$input_file" -c:v libx264 -preset slow -crf 18 -pix_fmt yuv420p -c:a aac -b:a 320k "${base_name}_YouTube.mp4"
            echo -e "${PURPLE}3/3 Generating X (Twitter) Version...${NC}"
            ffmpeg -i "$input_file" -c:v libx264 -pix_fmt yuv420p -preset medium -b:v 3500k -maxrate 3500k -bufsize 7000k -c:a aac -b:a 160k "${base_name}_X.mp4"
            ;;
        2) return ;;
    esac
    echo -e "${GREEN}Batch Complete!${NC}"
    pause
}

# ==============================================================================
# MODULE 6: Diagnostics
# ==============================================================================
menu_analysis(){
    clear
    echo -e "${PURPLE}--- Diagnostics & Validation ---${NC}"
    echo "1. Stream Info (JSON)"
    echo "2. Detect Silence/Black Frames"
    echo "3. DistroKid/Streaming Validator (WAV Check)"
    echo "4. Return"
    read -p "Select: " choice
    case $choice in
        1)
            get_input_file
            ffprobe -loglevel quiet -show_format -show_streams -i "$input_file" -print_format json | less
            ;;
        2)
            get_input_file
            echo "Scanning silence > 2s..."
            ffmpeg -i "$input_file" -af "silencedetect=noise=-50dB:d=2" -f null - 2>&1 | grep "silence_start"
            pause
            ;;
        3)
            get_input_file "Drag WAV Master:"
            sr=$(ffprobe -v error -select_streams a:0 -show_entries stream=sample_rate -of default=noprint_wrappers=1:nokey=1 "$input_file")
            bd=$(ffprobe -v error -select_streams a:0 -show_entries stream=bits_per_raw_sample -of default=noprint_wrappers=1:nokey=1 "$input_file")
            [ "$bd" == "N/A" ] && bd=$(ffprobe -v error -select_streams a:0 -show_entries stream=sample_fmt -of default=noprint_wrappers=1:nokey=1 "$input_file")
            echo -e "\n${CYAN}--- Report ---${NC}"
            echo "Sample Rate: $sr"
            echo "Bit Depth:   $bd"
            if [ "$sr" -lt 44100 ]; then echo -e "${RED}[FAIL] Rate too low.${NC}"; else echo -e "${GREEN}[OK] Rate valid.${NC}"; fi
            if [[ "$bd" == *"flt"* ]]; then 
                echo -e "${YELLOW}[WARNING] 32-bit Float detected. DistroKid prefers 24-bit Integer.${NC}";
            else 
                echo -e "${GREEN}[OK] Bit depth safe.${NC}"
            fi
            pause
            ;;
        4) return ;;
    esac
}

# ==============================================================================
# MODULE 7: Notation Studio (AI)
# ==============================================================================
menu_notation_studio(){
    clear
    echo -e "${PURPLE}--- Notation Studio (AI Audio -> MIDI -> Sheet) ---${NC}"
    if ! command -v demucs &> /dev/null || ! command -v basic-pitch &> /dev/null; then
        echo -e "${RED}Error: AI modules missing.${NC}"
        echo "Make sure you activated your environment: conda activate audio_tools"
        pause
        return
    fi
    echo "1. Full Workflow (Audio -> Separate -> MIDI -> PDF)"
    echo "2. Quick Convert (MIDI -> PDF)"
    echo "3. Guitar Tabs Helper (TuxGuitar)"
    echo "4. Return"
    read -p "Select: " choice
    case $choice in
        1)
            get_input_file "Drag Audio File:"
            echo -e "${PURPLE}Step 1: Separating Stems (Demucs GPU)...${NC}"
            base_name=$(basename "$input_file" | cut -d. -f1)
            proj_dir="./notation_${base_name}"
            mkdir -p "$proj_dir"
            demucs -n htdemucs_ft "$input_file" -o "$proj_dir"
            stem_dir=$(find "$proj_dir" -type d -name "$base_name" | head -n 1)
            [ -z "$stem_dir" ] && { echo "Separation failed."; pause; return; }
            echo -e "${CYAN}--- Select Stem ---${NC}"
            files=("$stem_dir"/*.wav)
            select stem in "${files[@]}"; do
                [ -n "$stem" ] && break
            done
            echo -e "${PURPLE}Step 2: Transcribing to MIDI...${NC}"
            basic-pitch "$proj_dir" "$stem"
            stem_base=$(basename "$stem" .wav)
            midi_file="$proj_dir/${stem_base}_basic_pitch.mid"
            if [ -f "$midi_file" ]; then
                echo -e "${PURPLE}Step 3: Rendering PDF...${NC}"
                mscore_cmd=$(command -v musescore3 || command -v mscore)
                if [ -n "$mscore_cmd" ]; then
                    "$mscore_cmd" -o "$proj_dir/${stem_base}.pdf" "$midi_file"
                    echo -e "${GREEN}Success: $proj_dir/${stem_base}.pdf${NC}"
                else
                    echo "MuseScore not found. MIDI saved."
                fi
            fi
            ;;
        2)
            get_input_file; get_output_name
            mscore_cmd=$(command -v musescore3 || command -v mscore)
            "$mscore_cmd" -o "$output_name" "$input_file"
            ;;
        3)
            echo -e "${CYAN}Launching TuxGuitar...${NC}"
            if command -v tuxguitar &> /dev/null; then
                tuxguitar &
            else
                echo -e "${RED}Install with: sudo apt install tuxguitar${NC}"
            fi
            ;;
        4) return ;;
    esac
    pause
}

# --- Main Loop ---
check_dependencies
while true; do
    clear
    echo -e "${PURPLE}=======================================${NC}"
    echo -e "${PURPLE}   FreeEd4Med Media SuperTool v10.19      ${NC}"
    echo -e "${PURPLE}=======================================${NC}"
    echo "1. Creation Module (Lyrics, AI Whisper, Loop)"
    echo "2. Visualizer Lab (Color Picker, Circular, etc.)"
    echo "3. Branding & Metadata (Smart Logo, Tags)"
    echo "4. Audio Lab (Convert, Normalize)"
    echo "5. Social Media Batch (TikTok + YT + X)"
    echo "6. Diagnostics (DistroKid Check)"
    echo "7. Notation Studio (AI Transcription)"
    echo "8. Exit"
    echo
    read -p "Enter choice [1-8]: " main_choice
    case $main_choice in
        1) menu_standard_video ;;
        2) menu_visualizers ;;
        3) menu_branding ;;
        4) menu_audio_tools ;;
        5) menu_social_utils ;;
        6) menu_analysis ;;
        7) menu_notation_studio ;;
        8) echo "Exiting..."; exit 0 ;;
        *) echo -e "${RED}Invalid selection.${NC}"; sleep 1 ;;
    esac
done
