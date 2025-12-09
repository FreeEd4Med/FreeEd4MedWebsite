#!/bin/bash

# Determine the directory where this script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

# ==============================================================================
# FreeEd4Med Media Station beta 0.3.0 [Auto-detect + AI Captions Update]
# Evidence-Based Med Ed + Music For Healing
# Features: Pro Fonts, Subtitle Composer, Hard/Soft Subs, AI Whisper, Visualizers
# ==============================================================================

# --- Branding Colors ---
PURPLE='\033[1;35m'
CYAN='\033[0;36m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

declare -A SOCIAL_SUFFIX_MAP=([tok]='Tok' [yt]='YT' [x]='X' [ig]='IG' [meta]='META')

declare -A SOCIAL_NAME_MAP=([tok]='TikTok (9:16 vertical)' [yt]='YouTube (16:9)' [x]='X / Twitter (Landscape)' [ig]='Instagram Feed (4:5)' [meta]='Facebook / META (720p)')

# Paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STYLE_SCRIPT="$SCRIPT_DIR/style_subtitles.py"

# --- Lightweight helper functions (so this script can run standalone) ---
pause(){
    read -p "Press [Enter] key to continue..."
}

clean_path_input(){
    # remove matching single-quotes around a path and trim whitespace
    local raw="$1"
    raw="${raw%\'}"
    raw="${raw#\'}"
    # trim leading/trailing whitespace
    raw="$(echo -e "$raw" | sed -e 's/^\s*//' -e 's/\s*$//')"
    echo "$raw"
}

get_input_file(){
    local prompt_text="${1:-Drag and drop your INPUT file here (or type path):}"
    echo -e "${CYAN}$prompt_text${NC}"
    read -r input_file
    input_file=$(clean_path_input "$input_file")
    if [[ -z "$input_file" || ! -f "$input_file" ]]; then
        echo -e "${RED}Error: File not found!${NC}"
        pause
        return 1
    fi
    return 0
}

get_second_file(){
    local prompt_text="${1:-Drag the SECOND file (e.g., audio/logo):}"
    echo -e "${CYAN}$prompt_text${NC}"
    read -r second_file
    second_file=$(clean_path_input "$second_file")
    if [[ -z "$second_file" || ! -f "$second_file" ]]; then
        echo -e "${RED}Error: File not found!${NC}"
        pause
        return 1
    fi
    return 0
}

get_optional_background(){
    echo -e "${CYAN}Optional: Drag a BACKGROUND IMAGE (Enter to use black/default):${NC}"
    read -r bg_input
    bg_image=$(clean_path_input "$bg_input")
    if [[ -n "$bg_image" && ! -f "$bg_image" ]]; then
        echo -e "${YELLOW}File not found. Using default background.${NC}"
        bg_image=""
    fi
}

get_output_name(){
    # Usage: get_output_name [default_ext]
    # If user omits extension, appends default_ext (default: mp4)
    local default_ext="${1:-mp4}"
    read -p "Enter name for output file (e.g., output.${default_ext}): " output_name
    # Ensure extension if missing
    if [[ -n "$output_name" && ! "$output_name" =~ \.[a-zA-Z0-9]+$ ]]; then
        output_name="${output_name}.${default_ext}"
    fi
}

check_dependencies(){
    local missing=()
    command -v ffmpeg >/dev/null 2>&1 || missing+=("ffmpeg")
    command -v ffprobe >/dev/null 2>&1 || missing+=("ffprobe")
    command -v python3 >/dev/null 2>&1 || missing+=("python3")
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo -e "${YELLOW}Warning: Missing dependencies: ${missing[*]}${NC}"
        echo -e "${YELLOW}Some features may not work correctly.${NC}"
        sleep 2
    fi
}

# Helper to find a python interpreter with pygame/numpy
get_python_viz_cmd(){
    # Try standard commands first
    if python3 -c "import pygame; import numpy" >/dev/null 2>&1; then
        echo "python3"
        return 0
    fi
    if python -c "import pygame; import numpy" >/dev/null 2>&1; then
        echo "python"
        return 0
    fi
    
    # Try common conda paths
    local conda_paths=(
        "$HOME/miniconda3/bin/python"
        "$HOME/anaconda3/bin/python"
        "/opt/miniconda3/bin/python"
        "/opt/anaconda3/bin/python"
    )
    
    for p in "${conda_paths[@]}"; do
        if [[ -x "$p" ]]; then
            if "$p" -c "import pygame; import numpy" >/dev/null 2>&1; then
                echo "$p"
                return 0
            fi
        fi
    done
    
    return 1
}

# Upload a video (and optional captions) to YouTube using OAuth refresh token
menu_youtube_upload(){
    clear
    echo -e "${PURPLE}--- YouTube Upload (Video + Captions) ---${NC}"
    get_input_file "Drag VIDEO file to upload:" || return

    local cap_path=""
    read -p "Optional captions file (.vtt/.srt) [Enter to skip]: " cap_path
    cap_path=$(clean_path_input "$cap_path")
    if [[ -n "$cap_path" && ! -f "$cap_path" ]]; then
        echo -e "${YELLOW}Captions file not found; skipping captions.${NC}"
        cap_path=""
    fi

    local base_name="$(basename "$input_file")"
    local default_title="${base_name%.*}"
    read -p "Title [${default_title}]: " yt_title
    [[ -z "$yt_title" ]] && yt_title="$default_title"
    read -p "Description (optional): " yt_desc
    read -p "Privacy (public/unlisted/private) [unlisted]: " yt_priv
    [[ -z "$yt_priv" ]] && yt_priv="unlisted"
    read -p "Is this made for kids? (y/N): " yt_kids
    local yt_made_for_kids="false"
    [[ "$yt_kids" =~ ^[Yy] ]] && yt_made_for_kids="true"

    local cid=$(get_setting "social_accounts.youtube.oauth_client_id")
    local csecret=$(get_setting "social_accounts.youtube.oauth_client_secret")
    local refresh=$(get_setting "social_accounts.youtube.oauth_refresh_token")
    if [[ -z "$cid" || -z "$csecret" || -z "$refresh" ]]; then
        echo -e "${RED}Missing YouTube OAuth credentials. Set Client ID/Secret/Refresh in Settings > Social > YouTube.${NC}"
        pause
        return
    fi

    local filesize
    filesize=$(stat -c%s "$input_file")
    local ext=${input_file##*.}
    ext=$(echo "$ext" | tr '[:upper:]' '[:lower:]')
    local mime="video/mp4"
    case "$ext" in
        mov) mime="video/quicktime" ;;
        mkv) mime="video/x-matroska" ;;
        webm) mime="video/webm" ;;
    esac

    echo -e "${CYAN}Exchanging refresh token for access token...${NC}"
    local token_json access_token
    token_json=$(curl -s \
        -d "client_id=$cid" \
        -d "client_secret=$csecret" \
        -d "refresh_token=$refresh" \
        -d "grant_type=refresh_token" \
        https://oauth2.googleapis.com/token)
    access_token=$(python3 -c "import json,sys; data=json.loads(sys.stdin.read()); print(data.get('access_token',''))" <<<"$token_json")
    if [[ -z "$access_token" ]]; then
        echo -e "${RED}Failed to obtain access token. Check refresh token and scopes.${NC}"
        echo "$token_json"
        pause
        return
    fi

    # Prepare metadata JSON
    local meta_json
    meta_json=$(YT_TITLE="$yt_title" YT_DESC="$yt_desc" YT_PRIV="$yt_priv" YT_KIDS="$yt_made_for_kids" python3 -c "import json,os; meta={'snippet':{'title':os.environ.get('YT_TITLE',''),'description':os.environ.get('YT_DESC',''),'categoryId':'10'},'status':{'privacyStatus':os.environ.get('YT_PRIV','unlisted'),'selfDeclaredMadeForKids': os.environ.get('YT_KIDS','false')=='true'}}; print(json.dumps(meta))")

    echo -e "${CYAN}Initiating resumable upload...${NC}"
    local init_resp upload_url
    init_resp=$(curl -s -D - -o /dev/null \
        -H "Authorization: Bearer $access_token" \
        -H "Content-Type: application/json; charset=UTF-8" \
        -H "X-Upload-Content-Length: $filesize" \
        -H "X-Upload-Content-Type: $mime" \
        -X POST \
        -d "$meta_json" \
        "https://www.googleapis.com/upload/youtube/v3/videos?uploadType=resumable&part=snippet,status")
    upload_url=$(echo "$init_resp" | awk '/[Ll]ocation:/ {print $2}' | tr -d '\r')
    if [[ -z "$upload_url" ]]; then
        echo -e "${RED}Failed to get upload URL:${NC}"
        echo "$init_resp"
        pause
        return
    fi

    echo -e "${CYAN}Uploading video (this may take a while)...${NC}"
    local upload_resp
    upload_resp=$(curl -s \
        -H "Authorization: Bearer $access_token" \
        -H "Content-Type: $mime" \
        -H "Content-Length: $filesize" \
        --upload-file "$input_file" \
        "$upload_url")
    local video_id
    video_id=$(python3 -c "import json,sys;\ntry:\n    data=json.loads(sys.stdin.read())\n    print(data.get('id',''))\nexcept Exception:\n    print('')" <<<"$upload_resp")
    if [[ -z "$video_id" ]]; then
        echo -e "${RED}Upload response did not return a video ID:${NC}"
        echo "$upload_resp"
        pause
        return
    fi

    echo -e "${GREEN}✅ Video uploaded. ID: $video_id${NC}"

    # Optional captions upload
    if [[ -n "$cap_path" ]]; then
        local cap_mime="text/vtt"
        [[ "$cap_path" == *.srt ]] && cap_mime="application/x-subrip"
        local cap_lang="en"
        read -p "Caption language code [en]: " cap_lang_in
        [[ -n "$cap_lang_in" ]] && cap_lang="$cap_lang_in"
        echo -e "${CYAN}Uploading captions...${NC}"
        local cap_resp
        cap_resp=$(curl -s -X POST \
            -H "Authorization: Bearer $access_token" \
            -F "snippet={\"videoId\":\"$video_id\",\"language\":\"$cap_lang\",\"name\":\"Captions\",\"isDraft\":false};type=application/json" \
            -F "file=@$cap_path;type=$cap_mime" \
            "https://www.googleapis.com/upload/youtube/v3/captions?part=snippet&uploadType=multipart")
        local cap_id
        cap_id=$(python3 -c "import json,sys;\ntry:\n    data=json.loads(sys.stdin.read())\n    print(data.get('id',''))\nexcept Exception:\n    print('')" <<<"$cap_resp")
        if [[ -n "$cap_id" ]]; then
            echo -e "${GREEN}✅ Captions uploaded (ID: $cap_id).${NC}"
        else
            echo -e "${YELLOW}Captions upload response:${NC}"
            echo "$cap_resp"
        fi
    fi

    pause
}

# Upload hub for multiple platforms
menu_uploads(){
    while true; do
        clear
        echo -e "${PURPLE}--- Uploads Hub ---${NC}"
        echo "1. Upload to YouTube (video + captions)"
        echo "2. Upload to TikTok"
        echo "3. Return"
        read -p "Select: " up_choice
        case $up_choice in
            1) menu_youtube_upload ;;
            2) menu_tiktok_upload ;;
            3) return ;;
            *) echo -e "${RED}Invalid selection.${NC}"; sleep 1 ;;
        esac
    done
}

# Social media toolkit aggregator
menu_social_tools(){
    while true; do
        clear
        echo -e "${PURPLE}--- Social Media Tools ---${NC}"
        echo "1. Social Media Batch (multi-format renders)"
        echo "2. Format Converter (Resize/Crop for Socials)"
        echo "3. AI Caption Generator"
        echo "4. Social Media Post Tool (YouTube/TikTok uploads)"
        echo "5. Return"
        read -p "Select: " sm_choice
        case $sm_choice in
            1) menu_social_batch ;;
            2) menu_format_converter ;;
            3) menu_caption_generator ;;
            4) menu_uploads ;;
            5) return ;;
            *) echo -e "${RED}Invalid selection.${NC}"; sleep 1 ;;
        esac
    done
}

# Upload a video to TikTok using a developer access token (chunked upload + publish)
menu_tiktok_upload(){
    clear
    echo -e "${PURPLE}--- TikTok Upload (video) ---${NC}"
    echo -e "${YELLOW}Requires TikTok developer access token and open_id (Settings > Social > TikTok).${NC}"
    get_input_file "Drag VIDEO file to upload (vertical 9:16 recommended):" || return

    local tiktok_token=$(get_setting "social_accounts.tiktok.access_token")
    local tiktok_open_id=$(get_setting "social_accounts.tiktok.open_id")
    if [[ -z "$tiktok_token" || -z "$tiktok_open_id" ]]; then
        echo -e "${RED}Missing TikTok access_token or open_id. Configure in settings/config first.${NC}"
        pause
        return
    fi

    local default_title="${input_file##*/}"
    default_title="${default_title%.*}"
    read -p "Title [${default_title}]: " tt_title
    [[ -z "$tt_title" ]] && tt_title="$default_title"
    read -p "Privacy (PUBLIC/FRIENDS/PRIVATE) [PUBLIC]: " tt_priv
    [[ -z "$tt_priv" ]] && tt_priv="PUBLIC"

    echo -e "${CYAN}Requesting upload URL...${NC}"
    local init_resp upload_url upload_id
    init_resp=$(curl -s -X GET \
        -H "Authorization: Bearer $tiktok_token" \
        "https://open.tiktokapis.com/v2/upload/video/")
    upload_url=$(python3 -c "import json,sys;d=json.load(sys.stdin);print(d.get('data',{}).get('upload_url',''))" <<<"$init_resp")
    upload_id=$(python3 -c "import json,sys;d=json.load(sys.stdin);print(d.get('data',{}).get('upload_id',''))" <<<"$init_resp")
    if [[ -z "$upload_url" || -z "$upload_id" ]]; then
        echo -e "${RED}Failed to get upload URL:${NC}"
        echo "$init_resp"
        pause
        return
    fi

    echo -e "${CYAN}Uploading video to TikTok...${NC}"
    if ! curl -s -X PUT -H "Content-Type: video/mp4" --upload-file "$input_file" "$upload_url" >/dev/null; then
        echo -e "${RED}Video upload failed.${NC}"
        pause
        return
    fi

    echo -e "${CYAN}Publishing post...${NC}"
    local publish_body
    publish_body=$(python3 - <<'PY'
import json, os, sys
upload_id = os.environ.get('UPLOAD_ID','')
open_id = os.environ.get('OPEN_ID','')
title = os.environ.get('POST_TITLE','')[:150]
privacy = os.environ.get('PRIV','PUBLIC')
body = {
    "open_id": open_id,
    "upload_id": upload_id,
    "post_info": {
        "title": title,
        "privacy_level": privacy,
        "disable_duet": False,
        "disable_stitch": False
    }
}
print(json.dumps(body))
PY
    )

    local publish_resp
    publish_resp=$(UPLOAD_ID="$upload_id" OPEN_ID="$tiktok_open_id" POST_TITLE="$tt_title" PRIV="$tt_priv" curl -s -X POST \
        -H "Authorization: Bearer $tiktok_token" \
        -H "Content-Type: application/json" \
        -d "$publish_body" \
        "https://open.tiktokapis.com/v2/post/publish/video/")

    local video_id
    video_id=$(python3 -c "import json,sys;d=json.load(sys.stdin);print(d.get('data',{}).get('video_id',''))" <<<"$publish_resp")
    if [[ -n "$video_id" ]]; then
        echo -e "${GREEN}✅ TikTok upload published. Video ID: $video_id${NC}"
    else
        echo -e "${RED}Publish failed or no video_id returned:${NC}"
        echo "$publish_resp"
    fi
    pause
}

# ============================================================
# SETTINGS SYSTEM - Persistent Configuration
# Stored in ~/.freeed_media_super_tool/config.json
# ============================================================
CONFIG_DIR="$HOME/.freeed_media_super_tool"
CONFIG_FILE="$CONFIG_DIR/config.json"

# Initialize config directory and file if needed
init_config(){
    mkdir -p "$CONFIG_DIR"
    if [[ ! -f "$CONFIG_FILE" ]]; then
        cat > "$CONFIG_FILE" << 'DEFAULTCONFIG'
{
  "version": "1.0",
  "user": {
    "name": "",
        "default_output_folder": "",
        "audio_output_folder": "",
        "video_output_folder": "",
        "report_output_folder": ""
  },
  "social_accounts": {
    "tiktok": {
      "username": "",
      "connected": false
    },
    "youtube": {
      "channel_name": "",
            "oauth_refresh_token": "",
            "oauth_client_id": "",
            "oauth_client_secret": "",
      "connected": false
    },
    "x_twitter": {
      "username": "",
      "api_key": "",
      "api_secret": "",
      "connected": false
    },
    "instagram": {
      "username": "",
      "connected": false
    },
    "facebook": {
      "page_name": "",
      "access_token": "",
      "connected": false
    }
  },
  "ai_settings": {
    "preferred_backend": "auto",
    "openai_api_key": "",
    "anthropic_api_key": "",
    "ollama_model": "llama3"
  },
  "export_defaults": {
    "quality_preset": "medium",
        "default_platforms": ["tiktok", "youtube", "instagram"]
  },
  "advanced": {
    "ffmpeg_threads": 0,
    "temp_folder": "/tmp",
    "keep_temp_files": false,
    "verbose_logging": false
  }
}
DEFAULTCONFIG
        echo -e "${GREEN}Created new settings file at $CONFIG_FILE${NC}"
    fi
}

# Read a setting from config (uses Python for JSON parsing)
get_setting(){
    local key_path="$1"
    python3 -c "
import json
try:
    with open('$CONFIG_FILE') as f:
        data = json.load(f)
    keys = '$key_path'.split('.')
    val = data
    for k in keys:
        val = val.get(k, '')
    print(val if val else '')
except:
    print('')
" 2>/dev/null
}

# Write a setting to config
set_setting(){
    local key_path="$1"
    local value="$2"
    python3 << PYSET
import json
try:
    with open('$CONFIG_FILE', 'r') as f:
        data = json.load(f)
except:
    data = {}

keys = '$key_path'.split('.')
current = data
for k in keys[:-1]:
    if k not in current:
        current[k] = {}
    current = current[k]
current[keys[-1]] = '$value'

with open('$CONFIG_FILE', 'w') as f:
    json.dump(data, f, indent=2)
PYSET
}

# Set a boolean setting
set_setting_bool(){
    local key_path="$1"
    local value="$2"  # "true" or "false"
    python3 << PYSET
import json
try:
    with open('$CONFIG_FILE', 'r') as f:
        data = json.load(f)
except:
    data = {}

keys = '$key_path'.split('.')
current = data
for k in keys[:-1]:
    if k not in current:
        current[k] = {}
    current = current[k]
current[keys[-1]] = True if '$value' == 'true' else False

with open('$CONFIG_FILE', 'w') as f:
    json.dump(data, f, indent=2)
PYSET
}

# Settings Menu
menu_legal(){
    clear
    echo -e "${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${PURPLE}              ⚖️  LEGAL & INFO                 ${NC}"
    echo -e "${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo
    echo "Please refer to the following documents located in the 'Legal' folder:"
    echo
    if [ -d "Legal" ]; then
        ls -1 Legal
    else
        echo -e "${RED}Legal folder not found.${NC}"
    fi
    echo
    echo "These documents contain important information regarding:"
    echo "- Terms of Use"
    echo "- Privacy Policy"
    echo "- End User License Agreement (EULA)"
    echo
    pause
}

menu_settings(){
    while true; do
        clear
        echo -e "${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${PURPLE}              ⚙️  SETTINGS                     ${NC}"
        echo -e "${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo
        echo "1. 👤 Profile & Preferences"
        echo "2. 📱 Social Media Accounts"
        echo "3. 🤖 AI & Caption Settings"
        echo "4. 🎬 Export Defaults"
        echo "5. 🔧 Advanced Options"
        echo "6. 📋 View All Settings"
        echo "7. 🔄 Reset to Defaults"
        echo "r. Return to Main Menu"
        echo
        read -p "Choose an option: " settings_choice

        case "$settings_choice" in
            1) settings_profile ;;
            2) settings_social_accounts ;;
            3) settings_ai ;;
            4) settings_export_defaults ;;
            5) settings_advanced ;;
            6) settings_view_all ;;
            7) settings_reset ;;
            r|R) return ;;
            *) echo -e "${RED}Invalid choice${NC}"; sleep 1 ;;
        esac
    done
}

settings_profile(){
    clear
    echo -e "${PURPLE}--- 👤 Profile & Preferences ---${NC}"
    echo
    local current_name=$(get_setting "user.name")
    local current_folder=$(get_setting "user.default_output_folder")
    local current_audio_out=$(get_setting "user.audio_output_folder")
    local current_video_out=$(get_setting "user.video_output_folder")
    local current_report_out=$(get_setting "user.report_output_folder")
    
    echo "Current name: ${current_name:-Not set}"
    echo "Default output folder (general fallback): ${current_folder:-Not set}"
    echo "Audio output folder:   ${current_audio_out:-Not set}"
    echo "Video output folder:   ${current_video_out:-Not set}"
    echo "Report output folder:  ${current_report_out:-Not set}"
    echo
    
    read -p "Enter your name (or press Enter to keep): " new_name
    if [[ -n "$new_name" ]]; then
        set_setting "user.name" "$new_name"
        echo -e "${GREEN}✓ Name updated${NC}"
    fi
    
    read -p "Default output folder (general fallback; drag folder or press Enter to keep): " new_folder
    new_folder=$(clean_path_input "$new_folder")
    if [[ -n "$new_folder" && -d "$new_folder" ]]; then
        set_setting "user.default_output_folder" "$new_folder"
        echo -e "${GREEN}✓ Output folder updated${NC}"
    fi

    read -p "Audio output folder (drag or Enter to keep, blank=skip): " new_audio
    new_audio=$(clean_path_input "$new_audio")
    if [[ -n "$new_audio" && -d "$new_audio" ]]; then
        set_setting "user.audio_output_folder" "$new_audio"
        echo -e "${GREEN}✓ Audio output folder updated${NC}"
    fi

    read -p "Video output folder (drag or Enter to keep, blank=skip): " new_video
    new_video=$(clean_path_input "$new_video")
    if [[ -n "$new_video" && -d "$new_video" ]]; then
        set_setting "user.video_output_folder" "$new_video"
        echo -e "${GREEN}✓ Video output folder updated${NC}"
    fi

    read -p "Report output folder (drag or Enter to keep, blank=skip): " new_report
    new_report=$(clean_path_input "$new_report")
    if [[ -n "$new_report" && -d "$new_report" ]]; then
        set_setting "user.report_output_folder" "$new_report"
        echo -e "${GREEN}✓ Report output folder updated${NC}"
    fi

    echo
    read -p "Press Enter to return to Settings: " _return
    
    pause
}

settings_social_accounts(){
    while true; do
        clear
        echo -e "${PURPLE}--- 📱 Social Media Accounts ---${NC}"
        echo -e "${CYAN}Connect your accounts to enable auto-posting (coming soon)${NC}"
        echo
        
        # Show connection status
        local tiktok_user=$(get_setting "social_accounts.tiktok.username")
        local yt_channel=$(get_setting "social_accounts.youtube.channel_name")
        local x_user=$(get_setting "social_accounts.x_twitter.username")
        local ig_user=$(get_setting "social_accounts.instagram.username")
        local fb_page=$(get_setting "social_accounts.facebook.page_name")
        
        echo "1. TikTok     ${tiktok_user:+✓ @$tiktok_user}"
        echo "2. YouTube    ${yt_channel:+✓ $yt_channel}"
        echo "3. X/Twitter  ${x_user:+✓ @$x_user}"
        echo "4. Instagram  ${ig_user:+✓ @$ig_user}"
        echo "5. Facebook   ${fb_page:+✓ $fb_page}"
        echo "r. Return"
        echo
        read -p "Select platform to configure: " plat_choice
        
        case "$plat_choice" in
            1) configure_tiktok ;;
            2) configure_youtube ;;
            3) configure_x_twitter ;;
            4) configure_instagram ;;
            5) configure_facebook ;;
            r|R) return ;;
        esac
    done
}

configure_tiktok(){
    clear
    echo -e "${PURPLE}--- TikTok Configuration ---${NC}"
    echo
    local current=$(get_setting "social_accounts.tiktok.username")
    echo "Current username: ${current:-Not set}"
    echo
    echo -e "${YELLOW}Note: TikTok API requires a developer account.${NC}"
    echo -e "${YELLOW}Visit: https://developers.tiktok.com${NC}"
    echo
    read -p "TikTok username (without @): " tiktok_user
    if [[ -n "$tiktok_user" ]]; then
        set_setting "social_accounts.tiktok.username" "$tiktok_user"
        echo -e "${GREEN}✓ TikTok username saved${NC}"
    fi
    pause
}

configure_youtube(){
    clear
    echo -e "${PURPLE}--- YouTube Configuration ---${NC}"
    echo
    local current_channel=$(get_setting "social_accounts.youtube.channel_name")
    local current_refresh=$(get_setting "social_accounts.youtube.oauth_refresh_token")
    local current_client=$(get_setting "social_accounts.youtube.oauth_client_id")
    local current_secret=$(get_setting "social_accounts.youtube.oauth_client_secret")
    echo "Channel: ${current_channel:-Not set}"
    echo "OAuth Refresh Token: ${current_refresh:+••••••••${current_refresh: -4}}"
    echo "OAuth Client ID:     ${current_client:+••••${current_client: -4}}"
    echo "OAuth Client Secret: ${current_secret:+••••${current_secret: -4}}"
    echo
    echo -e "${YELLOW}Use OAuth 2.0 for uploads. Keep your client secret local by using the built-in localhost flow.${NC}"
    echo -e "${YELLOW}Steps: In Google Cloud Console create an OAuth Client ID (Web application) and add redirect URI:${NC}"
    echo -e "${YELLOW}        http://localhost:8080/oauth2callback${NC}"
    echo -e "${YELLOW}Then run the local flow below to capture the refresh token directly on your machine.${NC}"
    echo
    read -er -p "Channel name: " yt_channel
    [[ -n "$yt_channel" ]] && set_setting "social_accounts.youtube.channel_name" "$yt_channel"

    read -er -p "OAuth Client ID (Enter to skip): " yt_client
    if [[ -n "$yt_client" ]]; then
        set_setting "social_accounts.youtube.oauth_client_id" "$yt_client"
        echo -e "${GREEN}✓ Client ID saved${NC}"
    fi

    read -er -p "OAuth Client Secret (Enter to skip): " yt_secret
    if [[ -n "$yt_secret" ]]; then
        set_setting "social_accounts.youtube.oauth_client_secret" "$yt_secret"
        echo -e "${GREEN}✓ Client Secret saved${NC}"
    fi

    read -er -p "OAuth Refresh Token (Enter to skip): " yt_refresh
    if [[ -n "$yt_refresh" ]]; then
        set_setting "social_accounts.youtube.oauth_refresh_token" "$yt_refresh"
        echo -e "${GREEN}✓ Refresh token saved${NC}"
    fi
    echo
    echo "Local browser flow (recommended; keeps secret local):"
    echo "- Opens http://localhost:8080, captures the redirect, and exchanges the code on your machine."
    echo "- Make sure the redirect URI is registered exactly as shown above."
    read -p "Run local browser flow now? (y/N): " run_local
    if [[ "$run_local" =~ ^[Yy]$ ]]; then
        local cid=$(get_setting "social_accounts.youtube.oauth_client_id")
        local csecret=$(get_setting "social_accounts.youtube.oauth_client_secret")
        if [[ -z "$cid" || -z "$csecret" ]]; then
            echo -e "${RED}Set Client ID and Client Secret first.${NC}"
        else
            echo -e "${CYAN}Starting local OAuth helper on http://localhost:8080 ...${NC}"
            python3 ""$SCRIPT_DIR"/youtube_local_oauth.py" --client-id "$cid" --client-secret "$csecret"
            echo "If you saw a refresh token above, copy/paste it here to save it:"
            read -p "Paste refresh token (or Enter to skip): " new_rt_local
            if [[ -n "$new_rt_local" ]]; then
                set_setting "social_accounts.youtube.oauth_refresh_token" "$new_rt_local"
                echo -e "${GREEN}✓ Refresh token saved${NC}"
            fi
        fi
    fi

    # If we already captured a refresh token above, skip the device flow prompt
    refresh_after_local=$(get_setting "social_accounts.youtube.oauth_refresh_token")
    if [[ -z "$refresh_after_local" ]]; then
        echo
        echo "Device flow (alternate, works without redirect but exposes secret in app config):"
        echo "This opens a URL and asks for a code."
        read -p "Run device flow instead? (y/N): " run_flow
        if [[ "$run_flow" =~ ^[Yy]$ ]]; then
            local cid=$(get_setting "social_accounts.youtube.oauth_client_id")
            local csecret=$(get_setting "social_accounts.youtube.oauth_client_secret")
            if [[ -z "$cid" || -z "$csecret" ]]; then
                echo -e "${RED}Set Client ID and Client Secret first.${NC}"
            else
                python3 ""$SCRIPT_DIR"/youtube_device_flow.py" --client-id "$cid" --client-secret "$csecret"
                echo "If you saw a refresh token above, copy/paste it here to save it:"
                read -p "Paste refresh token (or Enter to skip): " new_rt
                if [[ -n "$new_rt" ]]; then
                    set_setting "social_accounts.youtube.oauth_refresh_token" "$new_rt"
                    echo -e "${GREEN}✓ Refresh token saved${NC}"
                fi
            fi
        fi
    else
        echo -e "${CYAN}Refresh token already saved; skipping device flow prompt.${NC}"
    fi
    echo -e "${GREEN}✓ YouTube OAuth settings saved${NC}"
    pause
}

configure_x_twitter(){
    clear
    echo -e "${PURPLE}--- X (Twitter) Configuration ---${NC}"
    echo
    local current=$(get_setting "social_accounts.x_twitter.username")
    echo "Current username: ${current:-Not set}"
    echo
    echo -e "${YELLOW}Get API keys from: https://developer.twitter.com${NC}"
    echo
    read -p "X/Twitter username (without @): " x_user
    [[ -n "$x_user" ]] && set_setting "social_accounts.x_twitter.username" "$x_user"
    
    read -p "API Key (or Enter to skip): " x_key
    [[ -n "$x_key" ]] && set_setting "social_accounts.x_twitter.api_key" "$x_key"
    
    read -p "API Secret (or Enter to skip): " x_secret
    [[ -n "$x_secret" ]] && set_setting "social_accounts.x_twitter.api_secret" "$x_secret"
    
    echo -e "${GREEN}✓ X/Twitter settings saved${NC}"
    pause
}

configure_instagram(){
    clear
    echo -e "${PURPLE}--- Instagram Configuration ---${NC}"
    echo
    local current=$(get_setting "social_accounts.instagram.username")
    echo "Current username: ${current:-Not set}"
    echo
    echo -e "${YELLOW}Instagram API requires a Facebook Business account.${NC}"
    echo -e "${YELLOW}Visit: https://developers.facebook.com${NC}"
    echo
    read -p "Instagram username (without @): " ig_user
    if [[ -n "$ig_user" ]]; then
        set_setting "social_accounts.instagram.username" "$ig_user"
        echo -e "${GREEN}✓ Instagram username saved${NC}"
    fi
    pause
}

configure_facebook(){
    clear
    echo -e "${PURPLE}--- Facebook Configuration ---${NC}"
    echo
    local current_page=$(get_setting "social_accounts.facebook.page_name")
    local current_token=$(get_setting "social_accounts.facebook.access_token")
    echo "Page: ${current_page:-Not set}"
    echo "Token: ${current_token:+••••••••${current_token: -4}}"
    echo
    echo -e "${YELLOW}Get access token from: https://developers.facebook.com${NC}"
    echo
    read -p "Facebook Page name: " fb_page
    [[ -n "$fb_page" ]] && set_setting "social_accounts.facebook.page_name" "$fb_page"
    
    read -p "Access Token (or Enter to skip): " fb_token
    if [[ -n "$fb_token" ]]; then
        set_setting "social_accounts.facebook.access_token" "$fb_token"
        echo -e "${GREEN}✓ Facebook settings saved${NC}"
    fi
    pause
}

settings_ai(){
    clear
    echo -e "${PURPLE}--- 🤖 AI & Caption Settings ---${NC}"
    echo
    local current_backend=$(get_setting "ai_settings.preferred_backend")
    local openai_key=$(get_setting "ai_settings.openai_api_key")
    local anthropic_key=$(get_setting "ai_settings.anthropic_api_key")
    local ollama_model=$(get_setting "ai_settings.ollama_model")
    
    echo "Current AI mode: ${current_backend:-auto}"
    echo "OpenAI API Key: ${openai_key:+✓ Set (${openai_key: -4})}"
    echo "Anthropic API Key: ${anthropic_key:+✓ Set (${anthropic_key: -4})}"
    echo "Ollama model: ${ollama_model:-llama3}"
    echo
    echo "Choose default AI mode:"
    echo "  1) Auto (tries best available)"
    echo "  2) OpenAI (ChatGPT)"
    echo "  3) Anthropic (Claude)"
    echo "  4) Ollama (local, free)"
    echo "  5) Basic templates (no AI)"
    read -p "Choice [current]: " ai_choice
    
    case "$ai_choice" in
        1) set_setting "ai_settings.preferred_backend" "auto" ;;
        2) set_setting "ai_settings.preferred_backend" "openai" ;;
        3) set_setting "ai_settings.preferred_backend" "anthropic" ;;
        4) set_setting "ai_settings.preferred_backend" "ollama" ;;
        5) set_setting "ai_settings.preferred_backend" "local" ;;
    esac
    
    echo
    read -p "OpenAI API Key (Enter to skip, 'clear' to remove): " new_openai
    if [[ "$new_openai" == "clear" ]]; then
        set_setting "ai_settings.openai_api_key" ""
        echo -e "${YELLOW}OpenAI key cleared${NC}"
    elif [[ -n "$new_openai" ]]; then
        set_setting "ai_settings.openai_api_key" "$new_openai"
        echo -e "${GREEN}✓ OpenAI key saved${NC}"
    fi
    
    read -p "Anthropic API Key (Enter to skip, 'clear' to remove): " new_anthropic
    if [[ "$new_anthropic" == "clear" ]]; then
        set_setting "ai_settings.anthropic_api_key" ""
        echo -e "${YELLOW}Anthropic key cleared${NC}"
    elif [[ -n "$new_anthropic" ]]; then
        set_setting "ai_settings.anthropic_api_key" "$new_anthropic"
        echo -e "${GREEN}✓ Anthropic key saved${NC}"
    fi
    
    read -p "Ollama model name [llama3]: " new_ollama
    if [[ -n "$new_ollama" ]]; then
        set_setting "ai_settings.ollama_model" "$new_ollama"
    fi
    
    echo -e "${GREEN}✓ AI settings saved${NC}"
    pause
}

settings_export_defaults(){
    clear
    echo -e "${PURPLE}--- 🎬 Export Defaults ---${NC}"
    echo
    local current_quality=$(get_setting "export_defaults.quality_preset")
    
    echo "Current quality preset: ${current_quality:-medium}"
    echo
    echo "Default quality for exports:"
    echo "  1) Low (fast, smaller files)"
    echo "  2) Medium (balanced)"
    echo "  3) High (best quality)"
    read -p "Choice [current]: " qual_choice
    
    case "$qual_choice" in
        1) set_setting "export_defaults.quality_preset" "low" ;;
        2) set_setting "export_defaults.quality_preset" "medium" ;;
        3) set_setting "export_defaults.quality_preset" "high" ;;
    esac
    
    echo -e "${GREEN}✓ Export defaults saved${NC}"
    pause
}

settings_advanced(){
    clear
    echo -e "${PURPLE}--- 🔧 Advanced Options ---${NC}"
    echo -e "${YELLOW}These settings are for power users.${NC}"
    echo
    
    local threads=$(get_setting "advanced.ffmpeg_threads")
    local temp=$(get_setting "advanced.temp_folder")
    local keep_temp=$(get_setting "advanced.keep_temp_files")
    local verbose=$(get_setting "advanced.verbose_logging")
    
    echo "FFmpeg threads: ${threads:-0 (auto)}"
    echo "Temp folder: ${temp:-/tmp}"
    echo "Keep temp files: ${keep_temp:-false}"
    echo "Verbose logging: ${verbose:-false}"
    echo
    
    read -p "FFmpeg threads (0=auto): " new_threads
    [[ -n "$new_threads" ]] && set_setting "advanced.ffmpeg_threads" "$new_threads"
    
    read -p "Temp folder path: " new_temp
    new_temp=$(clean_path_input "$new_temp")
    [[ -n "$new_temp" && -d "$new_temp" ]] && set_setting "advanced.temp_folder" "$new_temp"
    
    read -p "Keep temp files? (y/n): " keep_choice
    [[ "$keep_choice" =~ ^[Yy] ]] && set_setting_bool "advanced.keep_temp_files" "true"
    [[ "$keep_choice" =~ ^[Nn] ]] && set_setting_bool "advanced.keep_temp_files" "false"
    
    read -p "Verbose logging? (y/n): " verbose_choice
    [[ "$verbose_choice" =~ ^[Yy] ]] && set_setting_bool "advanced.verbose_logging" "true"
    [[ "$verbose_choice" =~ ^[Nn] ]] && set_setting_bool "advanced.verbose_logging" "false"
    
    echo -e "${GREEN}✓ Advanced settings saved${NC}"
    pause
}

settings_view_all(){
    clear
    echo -e "${PURPLE}--- 📋 Current Settings ---${NC}"
    echo
    if [[ -f "$CONFIG_FILE" ]]; then
        python3 -c "
import json
with open('$CONFIG_FILE') as f:
    data = json.load(f)

def print_dict(d, indent=0):
    for k, v in d.items():
        prefix = '  ' * indent
        if isinstance(v, dict):
            print(f'{prefix}{k}:')
            print_dict(v, indent + 1)
        elif 'key' in k.lower() or 'token' in k.lower() or 'secret' in k.lower():
            # Mask sensitive values
            if v:
                print(f'{prefix}{k}: ••••••••{str(v)[-4:]}')
            else:
                print(f'{prefix}{k}: (not set)')
        else:
            print(f'{prefix}{k}: {v}')

print_dict(data)
"
    else
        echo "No settings file found."
    fi
    echo
    pause
}

settings_reset(){
    clear
    echo -e "${RED}--- 🔄 Reset Settings ---${NC}"
    echo
    echo -e "${YELLOW}This will delete all your settings and start fresh.${NC}"
    read -p "Are you sure? Type 'RESET' to confirm: " confirm
    if [[ "$confirm" == "RESET" ]]; then
        rm -f "$CONFIG_FILE"
        init_config
        echo -e "${GREEN}✓ Settings reset to defaults${NC}"
    else
        echo "Reset cancelled."
    fi
    pause
}

# Load API keys from config into environment (call at startup)
load_api_keys_from_config(){
    init_config
    local openai_key=$(get_setting "ai_settings.openai_api_key")
    local anthropic_key=$(get_setting "ai_settings.anthropic_api_key")
    
    [[ -n "$openai_key" ]] && export OPENAI_API_KEY="$openai_key"
    [[ -n "$anthropic_key" ]] && export ANTHROPIC_API_KEY="$anthropic_key"
}

# --- AUTO-ACTIVATE CONDA ---
source ~/miniconda3/etc/profile.d/conda.sh
conda activate audio_tools 2>/dev/null
menu_social_batch(){
    clear
    echo -e "${PURPLE}--- Social Media Batch Generator ---${NC}"
    echo "You can create any combination of outputs for a single input file."
    echo "Available formats:"
    echo "  1) TikTok (vertical 1080x1920) -> video_Tok"
    echo "  2) YouTube (1920x1080)          -> video_YT"
    echo "  3) X / Twitter (landscape)       -> video_X"
    echo "  4) Instagram (square 1080x1080)  -> video_IG"
    echo "  5) Facebook / META (1280x720)    -> video_META"
    echo "  a) ALL formats"
    echo "  r) Return"
    read -p "Choose one or more (comma-separated), e.g. 1,4 or a for ALL: " choice_list
    [[ -z "$choice_list" ]] && { echo -e "${YELLOW}No selection received.${NC}"; sleep 1; return; }
    if [[ "$choice_list" =~ ^[Rr]$ ]]; then
        return
    fi
    # Ask for an input path and auto-detect whether it's a video, image or audio
    tmp_input_video=""
    echo -e "${CYAN}Drag & drop the INPUT file (video OR image OR audio):${NC}"
    read -r raw_input
    inpath=$(clean_path_input "$raw_input")
    if [[ -z "$inpath" ]]; then
        echo -e "${YELLOW}No input received — returning.${NC}"
        return
    fi
    # determine type based on extension
    ext="${inpath##*.}"
    ext="$(echo "$ext" | tr '[:upper:]' '[:lower:]')"
    case "$ext" in
        png|jpg|jpeg|webp|bmp|tiff)
            input_kind="image"
            ;;
        mp4|mov|mkv|webm|avi|flv|m4v)
            input_kind="video"
            ;;
        mp3|wav|flac|aac|m4a)
            input_kind="audio"
            ;;
        *)
            read -p "Couldn't detect type; is this video (v), image (i), or audio (a)? [v]: " t
            [[ -z "$t" ]] && t=v
            if [[ "$t" =~ ^[Ii]$ ]]; then input_kind=image; elif [[ "$t" =~ ^[Aa]$ ]]; then input_kind=audio; else input_kind=video; fi
            ;;
    esac

    if [[ "$input_kind" == "image" ]]; then
        # Image path already in $inpath -> ask for audio to pair
        img="$inpath"
        echo -e "${CYAN}Image detected. Drag/Drop the AUDIO file:${NC}"
        read -r raw_audio
        audio=$(clean_path_input "$raw_audio")
        if [[ -z "$audio" || ! -f "$audio" ]]; then
            echo -e "${RED}Audio not found. Aborting.${NC}"
            pause
            return
        fi

        # create a temporary video from the image+audio
        tmp_input_video=$(mktemp /tmp/supertool_input_XXXX.mp4)
        echo -e "${PURPLE}Rendering temporary source video from image + audio...${NC}"
        if ! ffmpeg -y -loop 1 -i "$img" -i "$audio" -c:v libx264 -tune stillimage -pix_fmt yuv420p -c:a aac -b:a 192k -shortest "$tmp_input_video" >/dev/null 2>&1; then
            echo -e "${RED}Failed to build temporary source video.${NC}"
            rm -f "$tmp_input_video" 2>/dev/null || true
            pause
            return
        fi
        input_file="$tmp_input_video"
        base_name="$(basename "${audio%.*}")"

    elif [[ "$input_kind" == "audio" ]]; then
        # If user dropped an audio file first, prompt for image
        audio="$inpath"
        echo -e "${CYAN}Audio detected. Drag & drop the IMAGE (background) file:${NC}"
        read -r raw_img
        img=$(clean_path_input "$raw_img")
        if [[ -z "$img" || ! -f "$img" ]]; then
            echo -e "${RED}Image not found — aborting.${NC}"
            pause
            return
        fi
        tmp_input_video=$(mktemp /tmp/supertool_input_XXXX.mp4)
        echo -e "${PURPLE}Rendering temporary source video from image + audio...${NC}"
        if ! ffmpeg -y -loop 1 -i "$img" -i "$audio" -c:v libx264 -tune stillimage -pix_fmt yuv420p -c:a aac -b:a 192k -shortest "$tmp_input_video" >/dev/null 2>&1; then
            echo -e "${RED}Failed to build temporary source video.${NC}"
            rm -f "$tmp_input_video" >/dev/null 2>&1 || true
            pause
            return
        fi
        input_file="$tmp_input_video"
        base_name="$(basename "${audio%.*}")"

    else
        # video chosen/provided
        input_file="$inpath"
        if [[ ! -f "$input_file" ]]; then
            echo -e "${RED}File not found: $input_file${NC}"
            pause
            return
        fi
        base_name="$(basename "${input_file%.*}")"
    fi

    # normalize selection to an array of codes
    if [[ "$choice_list" =~ ^[Aa]$ ]]; then
        choices=(1 2 3 4 5)
    else
        IFS=',' read -ra raw_choices <<< "$choice_list"
        choices=()
        for c in "${raw_choices[@]}"; do
            c_trim=$(echo "$c" | tr -d '[:space:]')
            [[ -n "$c_trim" ]] && choices+=("$c_trim")
        done
    fi

    # Choose a preset quality profile for this batch (affects bitrates/CRF)
    echo -e "${CYAN}Choose an export quality preset for this batch:${NC}"
    echo "1) Low (fast, smaller files)"
    echo "2) Medium (balanced)"
    echo "3) High (quality, larger files)"
    echo "4) Custom (set values manually)"
    read -p "Preset [2]: " preset_choice
    [[ -z "$preset_choice" ]] && preset_choice=2

    # default values per preset (media-specific tunes)
    case $preset_choice in
        1)
            TOK_VBIT=2000k; TOK_A='copy'; TOK_EXTRA='-preset fast -crf 23'
            YT_CR=24; YT_A='-b:a 192k'; YT_PRESET='-preset fast -crf 24'
            # note: no ffmpeg run here — just default preset values for META
            IG_VBIT=2000k; IG_A='-b:a 160k'; IG_PRESET='-preset medium -crf 22'
            META_VBIT=2000k; META_A='-b:a 192k'
            ;;
        3)
            TOK_VBIT=6000k; TOK_A='-b:a 320k'; TOK_EXTRA='-preset slow -crf 16'
            YT_CR=16; YT_A='-b:a 320k'; YT_PRESET='-preset slow -crf 16'
            X_VBIT=5500k; X_A='-b:a 160k'
            IG_VBIT=4500k; IG_A='-b:a 160k'; IG_PRESET='-preset slow -crf 18'
            META_VBIT=6000k; META_A='-b:a 192k'
            ;;
        2|*)
            # Medium defaults
            TOK_VBIT=3500k; TOK_A='-b:a 192k'; TOK_EXTRA='-preset medium -crf 20'
            YT_CR=18; YT_A='-b:a 320k'; YT_PRESET='-preset medium -crf 18'
            X_VBIT=3500k; X_A='-b:a 160k'
            IG_VBIT=3000k; IG_A='-b:a 160k'; IG_PRESET='-preset medium -crf 20'
            META_VBIT=4000k; META_A='-b:a 192k'
            ;;
    esac

    if [[ "$preset_choice" == "4" ]]; then
        echo -e "${YELLOW}Custom mode: you can specify per-platform bitrate or CRF (press Enter to keep default).${NC}"
        read -p "TikTok video bitrate (e.g. 3500k) [${TOK_VBIT}]: " v
        [[ -n "$v" ]] && TOK_VBIT="$v"
        read -p "TikTok audio flags (e.g. -b:a 192k or copy) [${TOK_A}]: " a
        [[ -n "$a" ]] && TOK_A="$a"

        read -p "YouTube CRF (lower is better quality) [${YT_CR}]: " ytcr
        [[ -n "$ytcr" ]] && YT_CR="$ytcr"
        read -p "YouTube audio flags [${YT_A}]: " yta
        [[ -n "$yta" ]] && YT_A="$yta"

        read -p "X video bitrate [${X_VBIT}]: " xvb
        [[ -n "$xvb" ]] && X_VBIT="$xvb"
        read -p "X audio flags [${X_A}]: " xa
        [[ -n "$xa" ]] && X_A="$xa"

        read -p "Instagram video bitrate [${IG_VBIT}]: " ivb
        [[ -n "$ivb" ]] && IG_VBIT="$ivb"
        read -p "Instagram audio flags [${IG_A}]: " ia
        [[ -n "$ia" ]] && IG_A="$ia"

        read -p "Facebook/META video bitrate [${META_VBIT}]: " mvb
        [[ -n "$mvb" ]] && META_VBIT="$mvb"
        read -p "Facebook/META audio flags [${META_A}]: " ma
        [[ -n "$ma" ]] && META_A="$ma"
    fi

    # execute selected
    for sel in "${choices[@]}"; do
        case "$sel" in
            1) make_tok ;;
            2) make_yt ;;
            3) make_x ;;
            4) make_ig ;;
            5) make_meta ;;
            *) echo -e "${YELLOW}Skipping invalid selection: $sel${NC}" ;;
        esac
    done

    # wait for jobs and show summary
    echo -e "${CYAN}Waiting for ${#pids[@]} export job(s) to finish...${NC}"
    idx=0
    failures=0
    for pid in "${pids[@]}"; do
        wait "$pid" || { failures=$((failures+1)); }
        outfile=${outfiles[$idx]}
        logfile=${logs[$idx]}
        if [[ -f "$outfile" ]]; then
            echo -e "${GREEN}Saved: $outfile (log: $logfile)${NC}"
        else
            echo -e "${RED}Failed: $outfile (see log: $logfile)${NC}"
        fi
        idx=$((idx+1))
    done
    if [[ "$failures" -eq 0 ]]; then
        echo -e "${GREEN}All exports completed successfully.${NC}"
    else
        echo -e "${RED}$failures export(s) failed. Check the logs in /tmp/ for details.${NC}"
    fi
    # Offer to generate platform-specific captions using the helper script
    if command -v python3 >/dev/null 2>&1 && [[ -f "$SCRIPT_DIR/generate_captions.py" ]]; then
        read -p "Generate captions for your posts? [Y/n]: " gen_caps
        if [[ -z "$gen_caps" || "$gen_caps" =~ ^[Yy] ]]; then
            echo -e "${CYAN}How should I write your captions?${NC}"
            echo "  1) ✨ Smart (uses best AI available - recommended)"
            echo "  2) 📝 Basic (simple templates, works offline)"
            read -p "Choice [1]: " backend_choice
            case "$backend_choice" in
                2) caption_backend="local" ;;
                *) caption_backend="auto" ;;
            esac
            echo
            echo -e "${CYAN}Describe your content in a few words:${NC}"
            read -p "> " idea_in
            echo -e "${CYAN}What's your goal? (e.g., go viral, get followers, promote my music):${NC}"
            read -p "[get engagement] > " goal_in
            [[ -z "$goal_in" ]] && goal_in="get engagement"
            echo -e "${CYAN}What vibe? (casual, funny, inspiring, professional):${NC}"
            read -p "[casual] > " tone_in
            [[ -z "$tone_in" ]] && tone_in="casual"
            # Build platforms CSV from choices
            platform_codes=()
            for sel in "${choices[@]}"; do
                case "$sel" in
                    1) platform_codes+=(tok) ;;
                    2) platform_codes+=(yt) ;;
                    3) platform_codes+=(x) ;;
                    4) platform_codes+=(ig) ;;
                    5) platform_codes+=(meta) ;;
                esac
            done
            pf_csv=$(IFS=, ; echo "${platform_codes[*]}")
            echo -e "${PURPLE}Creating viral captions for: $pf_csv (backend: $caption_backend)${NC}"
            python3 "$SCRIPT_DIR/generate_captions.py" "$base_name" --platforms "$pf_csv" --idea "$idea_in" --goal "$goal_in" --tone "$tone_in" --backend "$caption_backend" --save
            echo -e "${GREEN}Caption generation finished!${NC}"
            echo -e "${CYAN}JSON saved: ${base_name}_captions.json${NC}"
            echo -e "${CYAN}History: ~/.freeed_media_super_tool/captions_history.json${NC}"
            read -p "Copy captions to clipboard now? [y/N]: " push_choice
            if [[ "$push_choice" =~ ^[Yy] ]]; then
                cap_path="${base_name}_captions.json"
                python3 - <<'PY'
import json, os, shutil, subprocess, sys
cap_path = os.path.abspath("${cap_path}")
if not os.path.exists(cap_path):
    print(f"[ERR] Captions file not found: {cap_path}")
    sys.exit(1)
with open(cap_path, "r", encoding="utf-8") as fh:
    data = json.load(fh)
caps = data.get("captions", {})
if not caps:
    print("[ERR] No captions found in JSON")
    sys.exit(1)

combined = []
for item in caps.values():
    platform = item.get("platform", "?")
    body = item.get("full_text") or f"{item.get('caption','')}\n{item.get('hashtags','')}"
    combined.append(f"[{platform}]\n{body}\n")

payload = "\n".join(combined)

def try_copy(cmd, input_text):
    try:
        p = subprocess.run(cmd, input=input_text.encode("utf-8"), stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        return p.returncode == 0
    except FileNotFoundError:
        return False

copied = False
if shutil.which("wl-copy"):
    copied = try_copy(["wl-copy"], payload)
elif shutil.which("xclip"):
    copied = try_copy(["xclip", "-selection", "clipboard"], payload)
elif shutil.which("pbcopy"):
    copied = try_copy(["pbcopy"], payload)

print(f"📁 Captions file: {cap_path}")
if copied:
    print("✅ Copied all captions to clipboard.")
else:
    print("⚠️ Could not copy to clipboard (missing pbcopy/xclip/wl-copy). Captions printed below:\n")
    print(payload)
PY
            fi
        fi
    fi

    # Offer YouTube upload flow (reuses main uploader)
    read -p "Upload a rendered file to YouTube now? [y/N]: " do_yt
    if [[ "$do_yt" =~ ^[Yy]$ ]]; then
        menu_youtube_upload
    fi

    # Offer TikTok upload (requires dev access token + open_id)
    read -p "Upload a rendered file to TikTok now? [y/N]: " do_tt
    if [[ "$do_tt" =~ ^[Yy]$ ]]; then
        menu_tiktok_upload
    fi

    # cleanup temporary input video if we created one
    if [[ -n "$tmp_input_video" && -f "$tmp_input_video" ]]; then
        rm -f "$tmp_input_video" || true
    fi
    pause
}

# ============================================================
# STANDALONE CAPTION GENERATOR
# Generate AI-powered captions for any video/content
# ============================================================
menu_caption_generator(){
    clear
    echo -e "${PURPLE}--- AI Caption Generator ---${NC}"
    echo -e "${CYAN}Generate viral, platform-specific captions for any content.${NC}"
    echo -e "${CYAN}Use this for videos from other tools or reposts with new captions.${NC}"
    echo

    # Check if the Python script exists
    if ! command -v python3 >/dev/null 2>&1 || [[ ! -f "$SCRIPT_DIR/generate_captions.py" ]]; then
        echo -e "${RED}Error: generate_captions.py not found or python3 unavailable.${NC}"
        pause
        return
    fi

    # Get a base name for the output
    echo -e "${CYAN}Enter a base name for your captions (e.g., 'summer_remix', 'jazz_cover'):${NC}"
    read -p "> " cap_base_name
    if [[ -z "$cap_base_name" ]]; then
        cap_base_name="captions_$(date +%Y%m%d_%H%M%S)"
        echo -e "${YELLOW}Using default: $cap_base_name${NC}"
    fi

    # Select platforms
    echo
    echo -e "${CYAN}Select platforms to generate captions for:${NC}"
    echo "  1) TikTok (9:16 vertical, trendy)"
    echo "  2) YouTube (16:9, SEO-friendly)"
    echo "  3) X / Twitter (280 chars max)"
    echo "  4) Instagram (aesthetic, hashtag-heavy)"
    echo "  5) Facebook / META (conversational)"
    echo "  a) All platforms"
    echo "  r) Return"
    read -p "Choose (comma-separated, e.g. 1,3,4 or 'a' for all): " plat_choice

    [[ -z "$plat_choice" ]] && { echo -e "${YELLOW}No selection.${NC}"; pause; return; }
    [[ "$plat_choice" =~ ^[Rr]$ ]] && return

    # Build platform list
    if [[ "$plat_choice" =~ ^[Aa]$ ]]; then
        platforms="tok,yt,x,ig,meta"
    else
        platforms=""
        IFS=',' read -ra sel_arr <<< "$plat_choice"
        for s in "${sel_arr[@]}"; do
            s_trim=$(echo "$s" | tr -d '[:space:]')
            case "$s_trim" in
                1) platforms="${platforms}tok," ;;
                2) platforms="${platforms}yt," ;;
                3) platforms="${platforms}x," ;;
                4) platforms="${platforms}ig," ;;
                5) platforms="${platforms}meta," ;;
            esac
        done
        platforms="${platforms%,}"  # remove trailing comma
    fi

    if [[ -z "$platforms" ]]; then
        echo -e "${RED}No valid platforms selected.${NC}"
        pause
        return
    fi

    # Choose AI quality level (simplified for all users)
    echo
    echo -e "${CYAN}How should I write your captions?${NC}"
    echo "  1) ✨ Smart (uses best AI available - recommended)"
    echo "  2) 📝 Basic (simple templates, works offline)"
    read -p "Choice [1]: " backend_choice
    case "$backend_choice" in
        2) caption_backend="local" ;;
        *) caption_backend="auto" ;;
    esac

    # Get content details (friendly prompts)
    echo
    echo -e "${CYAN}What's your video/song about? (a few words is fine):${NC}"
    read -p "> " idea_in
    [[ -z "$idea_in" ]] && idea_in="My new content"

    echo -e "${CYAN}What do you want to happen? (e.g., go viral, get followers, promote my music):${NC}"
    read -p "[get engagement] > " goal_in
    [[ -z "$goal_in" ]] && goal_in="get engagement"

    echo -e "${CYAN}What vibe? (casual, funny, inspiring, professional):${NC}"
    read -p "[casual] > " tone_in
    [[ -z "$tone_in" ]] && tone_in="casual"

    # Generate captions
    echo
    echo -e "${PURPLE}✨ Creating your captions...${NC}"
    python3 "$SCRIPT_DIR/generate_captions.py" "$cap_base_name" \
        --platforms "$platforms" \
        --idea "$idea_in" \
        --goal "$goal_in" \
        --tone "$tone_in" \
        --backend "$caption_backend" \
        --save

    echo
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}Done! Your captions are ready.${NC}"
    echo -e "${CYAN}Saved to: ${cap_base_name}_captions.json${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    # Show generated captions
    if [[ -f "${cap_base_name}_captions.json" ]]; then
        echo
        read -p "View generated captions? [Y/n]: " view_caps
        if [[ -z "$view_caps" || "$view_caps" =~ ^[Yy] ]]; then
            echo
            python3 -c "
import json
with open('${cap_base_name}_captions.json') as f:
    data = json.load(f)
for k, v in data.get('captions', {}).items():
    print(f\"\\n{'─'*50}\")
    print(f\"📱 {v.get('platform', k)} [{v.get('source', 'unknown')}]\")
    print('─'*50)
    if v.get('full_text'):
        print(v['full_text'])
    else:
        print(v.get('caption', ''))
        print(v.get('hashtags', ''))
"
        fi
    fi

    # Offer to copy captions to clipboard for quick posting
    echo
    read -p "Copy captions to clipboard now? [y/N]: " push_choice
    if [[ "$push_choice" =~ ^[Yy] ]]; then
        cap_path="${cap_base_name}_captions.json"
        python3 - <<'PY'
import json, os, shutil, subprocess, sys
cap_path = os.path.abspath("${cap_path}")
if not os.path.exists(cap_path):
    print(f"[ERR] Captions file not found: {cap_path}")
    sys.exit(1)
with open(cap_path, "r", encoding="utf-8") as fh:
    data = json.load(fh)
caps = data.get("captions", {})
if not caps:
    print("[ERR] No captions found in JSON")
    sys.exit(1)

combined = []
for item in caps.values():
    platform = item.get("platform", "?")
    body = item.get("full_text") or f"{item.get('caption','')}\n{item.get('hashtags','')}"
    combined.append(f"[{platform}]\n{body}\n")

payload = "\n".join(combined)

def try_copy(cmd, input_text):
    try:
        p = subprocess.run(cmd, input=input_text.encode("utf-8"), stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        return p.returncode == 0
    except FileNotFoundError:
        return False

copied = False
if shutil.which("wl-copy"):
    copied = try_copy(["wl-copy"], payload)
elif shutil.which("xclip"):
    copied = try_copy(["xclip", "-selection", "clipboard"], payload)
elif shutil.which("pbcopy"):
    copied = try_copy(["pbcopy"], payload)

print(f"📁 Captions file: {cap_path}")
if copied:
    print("✅ Copied all captions to clipboard.")
else:
    print("⚠️ Could not copy to clipboard (missing pbcopy/xclip/wl-copy). Captions printed below:\n")
    print(payload)
PY
    fi

    pause
}

ensure_style_script(){
    if [[ -f "$STYLE_SCRIPT" ]]; then
        return 0
    fi
    echo -e "${RED}Missing subtitle styling helper at $STYLE_SCRIPT.${NC}"
    echo "Please make sure style_subtitles.py is present in the Scripts folder."
    return 1
}

ensure_pysubs2(){
    if python3 -c "import pysubs2" >/dev/null 2>&1; then
        return 0
    fi
    echo -e "${CYAN}Installing pysubs2 (styled lyric engine)...${NC}"
    if python3 -m pip install --user pysubs2 >/dev/null 2>&1; then
        return 0
    fi
    echo -e "${RED}Failed to install pysubs2. Please install manually: pip install pysubs2${NC}"
    return 1
}

convert_srt_to_ass(){
    local srt_path="$1"
    local ass_path="$2"
    shift 2
    ensure_style_script || return 1
    ensure_pysubs2 || return 1
    local cmd=(python3 "$STYLE_SCRIPT" "$srt_path" "$ass_path")
    if (( $# )); then
        cmd+=("$@")
    fi
    if "${cmd[@]}"; then
        echo -e "${GREEN}Styled lyrics ready: $ass_path${NC}"
        return 0
    fi
    echo -e "${RED}Subtitle styling failed. Check the SRT file.${NC}"
    return 1
}

prompt_for_srt_file(){
    local prompt_text="${1:-Drag the .SRT file:}"
    echo -e "${CYAN}$prompt_text${NC}"
    read -r raw_srt
    local cleaned
    cleaned=$(clean_path_input "$raw_srt")
    if [[ -z "$cleaned" || ! -f "$cleaned" ]]; then
        echo -e "${RED}Subtitle file not found.${NC}"
        return 1
    fi
    srt_file="$cleaned"
    return 0
}

style_args=()

prompt_style_profile(){
    style_args=()
    echo -e "${PURPLE}--- Lyric Styling Profile ---${NC}"

    echo -e "${CYAN}Font Family:${NC}"
    echo "1. Arial"
    echo "2. Times New Roman"
    echo "3. Montserrat"
    echo "4. Bebas Neue"
    echo "5. Impact"
    echo "6. Custom"
    read -p "Select Font [1]: " font_sel
    case $font_sel in
        2) style_font_name="Times New Roman" ;;
        3) style_font_name="Montserrat" ;;
        4) style_font_name="Bebas Neue" ;;
        5) style_font_name="Impact" ;;
        6) read -p "Enter Font Name: " style_font_name ;;
        *) style_font_name="Arial" ;;
    esac

    read -p "Font Size [48]: " style_font_size
    if [[ -z "$style_font_size" || ! $style_font_size =~ ^[0-9]+$ ]]; then
        style_font_size=48
    fi

    normalize_hex(){
        local raw="$1"
        raw="${raw//#/}"
        raw=$(echo "$raw" | tr '[:lower:]' '[:upper:]')
        if [[ ! $raw =~ ^[0-9A-F]{6}$ ]]; then
            raw="FFFFFF"
        fi
        echo "#$raw"
    }

    echo -e "${CYAN}Primary Text Color:${NC}"
    echo "1. MadMooze Purple (#9D00FF)"
    echo "2. White (#FFFFFF)"
    echo "3. Yellow (#F4E409)"
    echo "4. Cyan (#00FFFF)"
    echo "5. Custom"
    read -p "Select Color [1]: " primary_sel
    case $primary_sel in
        2) style_primary_color="#FFFFFF" ;;
        3) style_primary_color="#F4E409" ;;
        4) style_primary_color="#00FFFF" ;;
        5) read -p "Enter HEX (e.g. #FFAA00): " user_hex; style_primary_color=$(normalize_hex "$user_hex") ;;
        *) style_primary_color="#9D00FF" ;;
    esac

    echo -e "${CYAN}Outline Color:${NC}"
    echo "1. Black"
    echo "2. White"
    echo "3. Custom"
    read -p "Select Outline [1]: " outline_sel
    case $outline_sel in
        2) style_outline_color="#FFFFFF" ;;
        3) read -p "Enter HEX: " outline_hex; style_outline_color=$(normalize_hex "$outline_hex") ;;
        *) style_outline_color="#000000" ;;
    esac

    echo -e "${CYAN}Backdrop Style:${NC}"
    echo "1. Transparent"
    echo "2. Soft Shadow Box"
    echo "3. Solid Banner"
    echo "4. Custom"
    read -p "Select Backdrop [2]: " back_sel
    case $back_sel in
        1)
            style_back_color="#000000"
            style_back_alpha=0
            ;;
        3)
            style_back_color="#000000"
            style_back_alpha=200
            ;;
        4)
            read -p "Enter HEX for backdrop: " back_hex
            style_back_color=$(normalize_hex "$back_hex")
            read -p "Alpha 0-255 [128]: " back_alpha_in
            if [[ -z "$back_alpha_in" || ! $back_alpha_in =~ ^[0-9]+$ ]]; then
                back_alpha_in=128
            fi
            (( back_alpha_in > 255 )) && back_alpha_in=255
            style_back_alpha=$back_alpha_in
            ;;
        *)
            style_back_color="#000000"
            style_back_alpha=128
            ;;
    esac

    echo -e "${CYAN}Bold / Italic Settings:${NC}"
    read -p "Bold text? [Y/n]: " bold_choice
    [[ "$bold_choice" =~ ^[Nn]$ ]] && style_bold="off" || style_bold="on"
    read -p "Italic accent? [y/N]: " italic_choice
    [[ "$italic_choice" =~ ^[Yy]$ ]] && style_italic="on" || style_italic="off"

    echo -e "${CYAN}Vertical Placement:${NC}"
    echo "1. Bottom"
    echo "2. Middle"
    echo "3. Top"
    read -p "Choose [1]: " vert_sel
    case $vert_sel in
        2)
            vert_word="middle"
            style_margin_v=0
            ;;
        3)
            vert_word="top"
            style_margin_v=60
            ;;
        *)
            vert_word="bottom"
            style_margin_v=60
            ;;
    esac

    echo -e "${CYAN}Horizontal Anchor:${NC}"
    echo "1. Left"
    echo "2. Center"
    echo "3. Right"
    read -p "Choose [2]: " horiz_sel
    case $horiz_sel in
        1)
            horiz_word="left"
            style_margin_l=80
            style_margin_r=20
            ;;
        3)
            horiz_word="right"
            style_margin_l=20
            style_margin_r=80
            ;;
        *)
            horiz_word="center"
            style_margin_l=40
            style_margin_r=40
            ;;
    esac
    style_alignment="${vert_word}:${horiz_word}"

    echo -e "${CYAN}Wrap Mode:${NC}"
    echo "1. Balanced (WrapStyle=1)"
    echo "2. No Wrap (0)"
    echo "3. Top-Down (2)"
    echo "4. Karaoke Smart (3)"
    read -p "Choose [1]: " wrap_sel
    case $wrap_sel in
        2) style_wrap_style=0 ;;
        3) style_wrap_style=2 ;;
        4) style_wrap_style=3 ;;
        *) style_wrap_style=1 ;;
    esac

    read -p "Outline Thickness [3]: " style_outline_width
    if [[ -z "$style_outline_width" || ! $style_outline_width =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        style_outline_width=3
    fi

    read -p "Shadow Depth [2]: " style_shadow_depth
    if [[ -z "$style_shadow_depth" || ! $style_shadow_depth =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        style_shadow_depth=2
    fi

    style_args=(
        --font "$style_font_name"
        --size "$style_font_size"
        --primary "$style_primary_color"
        --outline "$style_outline_color"
        --back "$style_back_color"
        --back-alpha "$style_back_alpha"
        --bold "$style_bold"
        --italic "$style_italic"
        --alignment "$style_alignment"
        --margin-v "$style_margin_v"
        --margin-l "$style_margin_l"
        --margin-r "$style_margin_r"
        --wrap-style "$style_wrap_style"
        --outline-width "$style_outline_width"
        --shadow-depth "$style_shadow_depth"
    )
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

launch_subtitle_composer(){
    echo -e "${CYAN}Launching Subtitle Composer...${NC}"
    if ! command -v subtitlecomposer &> /dev/null; then
        echo -e "${RED}Subtitle Composer is not installed.${NC}"
        echo "Install on Debian/Ubuntu: sudo apt install subtitlecomposer"
        pause
        return
    fi

    echo -e "${CYAN}Optional: drag an audio guide for timing (Enter to skip).${NC}"
    read -r composer_audio_raw
    local composer_audio
    composer_audio=$(clean_path_input "$composer_audio_raw")
    if [[ -n "$composer_audio" && ! -f "$composer_audio" ]]; then
        echo -e "${YELLOW}Audio reference not found. Launching without it.${NC}"
        composer_audio=""
    fi

    if [[ -n "$composer_audio" ]]; then
        subtitlecomposer --audio "$composer_audio"
    else
        subtitlecomposer
    fi

    echo -e "${GREEN}Subtitle Composer closed. Remember to save as .srt!${NC}"
    pause
}

create_static_video(){
    echo -e "${CYAN}--- 🖼️ Simple Image + Audio Video ---${NC}"
    get_input_file "Drag AUDIO file:"
    local audio_file="$input_file"
    get_second_file "Drag IMAGE file:"
    local image_file="$second_file"
    
    echo -e "${CYAN}Select Target Format (Crop/Pad):${NC}"
    echo "1. Original Image Ratio"
    echo "2. YouTube (16:9 Landscape)"
    echo "3. TikTok/Shorts (9:16 Vertical)"
    echo "4. Instagram Post (1:1 Square)"
    echo "5. Instagram Portrait (4:5)"
    read -p "Select [1]: " fmt_choice
    
    local scale_filter=""
    case $fmt_choice in
        2) scale_filter="scale=1920:1080:force_original_aspect_ratio=decrease,pad=1920:1080:(ow-iw)/2:(oh-ih)/2" ;;
        3) scale_filter="scale=1080:1920:force_original_aspect_ratio=decrease,pad=1080:1920:(ow-iw)/2:(oh-ih)/2" ;;
        4) scale_filter="scale=1080:1080:force_original_aspect_ratio=decrease,pad=1080:1080:(ow-iw)/2:(oh-ih)/2" ;;
        5) scale_filter="scale=1080:1350:force_original_aspect_ratio=decrease,pad=1080:1350:(ow-iw)/2:(oh-ih)/2" ;;
        *) scale_filter="scale=trunc(iw/2)*2:trunc(ih/2)*2" ;; # Ensure even dimensions
    esac
    
    get_output_name
    echo -e "${PURPLE}Rendering video...${NC}"
    
    ffmpeg -loop 1 -i "$image_file" -i "$audio_file" \
    -vf "$scale_filter,format=yuv420p" \
    -c:v libx264 -preset fast -crf 18 \
    -c:a aac -b:a 192k \
    -shortest "$output_name"
    
    echo -e "${GREEN}✓ Video created: $output_name${NC}"
    pause
}

menu_format_converter(){
    echo -e "${CYAN}--- 📱 Social Media Format Converter ---${NC}"
    get_input_file "Drag VIDEO file:"
    
    echo -e "${CYAN}Select Target Format:${NC}"
    echo "1. TikTok/Shorts (9:16 Vertical - 1080x1920)"
    echo "2. YouTube (16:9 Landscape - 1920x1080)"
    echo "3. Instagram Square (1:1 - 1080x1080)"
    echo "4. Instagram Portrait (4:5 - 1080x1350)"
    read -p "Select [1]: " fmt_choice
    
    local scale_filter=""
    case $fmt_choice in
        2) scale_filter="scale=1920:1080:force_original_aspect_ratio=decrease,pad=1920:1080:(ow-iw)/2:(oh-ih)/2" ;;
        3) scale_filter="scale=1080:1080:force_original_aspect_ratio=decrease,pad=1080:1080:(ow-iw)/2:(oh-ih)/2" ;;
        4) scale_filter="scale=1080:1350:force_original_aspect_ratio=decrease,pad=1080:1350:(ow-iw)/2:(oh-ih)/2" ;;
        *) scale_filter="scale=1080:1920:force_original_aspect_ratio=decrease,pad=1080:1920:(ow-iw)/2:(oh-ih)/2" ;;
    esac
    
    get_output_name
    echo -e "${PURPLE}Converting video...${NC}"
    
    ffmpeg -i "$input_file" \
    -vf "$scale_filter" \
    -c:v libx264 -preset fast -crf 20 \
    -c:a copy \
    "$output_name"
    
    echo -e "${GREEN}✓ Conversion complete: $output_name${NC}"
    pause
}

render_hardsub_lyric_video(){
    echo -e "${CYAN}--- Lyric Video (HardSub) ---${NC}"
    get_input_file "Drag Background IMAGE:"
    local bg_image="$input_file"
    get_second_file "Drag SONG Audio:"
    local song_audio="$second_file"

    if ! prompt_for_srt_file "Drag the .SRT file (plain lyrics):"; then
        pause
        return
    fi

    prompt_style_profile

    local styled_ass
    styled_ass=$(mktemp /tmp/madmooze_hardsubXXXX.ass)
    if ! convert_srt_to_ass "$srt_file" "$styled_ass" "${style_args[@]}"; then
        rm -f "$styled_ass"
        pause
        return
    fi

    get_output_name
    [[ -z "$output_name" ]] && output_name="$(dirname "$song_audio")/lyric_video.mp4"

    echo -e "${PURPLE}Rendering HardSub video...${NC}"
    if ffmpeg -loop 1 -i "$bg_image" -i "$song_audio" \
        -vf "ass=$styled_ass" \
        -c:v libx264 -preset fast -crf 18 \
        -c:a aac -b:a 192k \
        -shortest -pix_fmt yuv420p "$output_name"; then
        echo -e "${GREEN}Video saved to $output_name${NC}"
    else
        echo -e "${RED}ffmpeg failed while creating the HardSub video.${NC}"
    fi

    rm -f "$styled_ass"
    pause
}

render_softsub_video(){
    echo -e "${CYAN}--- Lyric Video (SoftSub / Toggleable) ---${NC}"
    get_input_file "Drag Background IMAGE:"
    local bg_image="$input_file"
    get_second_file "Drag SONG Audio:"
    local song_audio="$second_file"

    if ! prompt_for_srt_file "Drag the .SRT file to embed as soft subtitles:"; then
        pause
        return
    fi

    echo -e "${YELLOW}Note: Soft subtitles follow the viewer's player theme, so font/color choices are not burned in.${NC}"

    get_output_name
    [[ -z "$output_name" ]] && output_name="$(dirname "$song_audio")/softsub_video.mp4"

    echo -e "${PURPLE}Rendering SoftSub video (mov_text)...${NC}"
    if ffmpeg -loop 1 -i "$bg_image" -i "$song_audio" -i "$srt_file" \
        -c:v libx264 -preset fast -crf 18 \
        -c:a copy \
        -c:s mov_text -metadata:s:s:0 language=eng \
        -shortest -pix_fmt yuv420p "$output_name"; then
        echo -e "${GREEN}SoftSub video saved to $output_name${NC}"
    else
        echo -e "${RED}ffmpeg failed while creating the SoftSub video.${NC}"
    fi
    pause
}

render_slideshow_lyrics(){
    echo -e "${CYAN}--- Lyric Slideshow (Multi-Image) ---${NC}"
    echo -e "${CYAN}Drag the folder containing your images (img001.jpg, img002.jpg, ...):${NC}"
    read -r raw_dir
    local img_dir
    img_dir=$(clean_path_input "$raw_dir")
    if [[ -z "$img_dir" || ! -d "$img_dir" ]]; then
        echo -e "${RED}Folder not found.${NC}"
        pause
        return
    fi

    read -p "Seconds per image [5]: " seconds_per_image
    [[ -z "$seconds_per_image" ]] && seconds_per_image="5"
    if ! [[ "$seconds_per_image" =~ ^[0-9]+([.][0-9]+)?$ ]] || [[ "$seconds_per_image" == "0" ]]; then
        echo -e "${YELLOW}Invalid duration. Using 5 seconds per image.${NC}"
        seconds_per_image="5"
    fi
    local frame_rate="1/$seconds_per_image"

    read -p "Image extension [jpg]: " img_ext
    [[ -z "$img_ext" ]] && img_ext="jpg"
    img_ext="${img_ext#.}"
    local img_pattern="$img_dir/*.${img_ext}"
    if ! compgen -G "$img_pattern" >/dev/null; then
        echo -e "${RED}No *.$img_ext files found in $img_dir.${NC}"
        pause
        return
    fi

    get_second_file "Drag SONG Audio:"
    local song_audio="$second_file"

    if ! prompt_for_srt_file "Drag the .SRT file for the slideshow:"; then
        pause
        return
    fi

    prompt_style_profile

    local styled_ass
    styled_ass=$(mktemp /tmp/madmooze_slideshowXXXX.ass)
    if ! convert_srt_to_ass "$srt_file" "$styled_ass" "${style_args[@]}"; then
        rm -f "$styled_ass"
        pause
        return
    fi

    get_output_name
    [[ -z "$output_name" ]] && output_name="$(dirname "$song_audio")/slideshow_video.mp4"

    echo -e "${PURPLE}Rendering slideshow with lyrics...${NC}"
    if ffmpeg -framerate "$frame_rate" -pattern_type glob -i "$img_pattern" -i "$song_audio" \
        -vf "ass=$styled_ass" \
        -c:v libx264 -r 30 -pix_fmt yuv420p \
        -c:a aac -b:a 192k \
        -shortest "$output_name"; then
        echo -e "${GREEN}Slideshow video saved to $output_name${NC}"
    else
        echo -e "${RED}ffmpeg failed while creating the slideshow.${NC}"
    fi

    rm -f "$styled_ass"
    pause
}

# ==============================================================================
# MODULE 1: Creation & Lyric Videos (beta 0.3.0)
# ==============================================================================
menu_standard_video(){
    while true; do
        clear
        echo -e "${PURPLE}--- Creation Module v5.0 ---${NC}"
        echo "1. Simple Image + Audio Video (Static)"
        echo "2. Generate Subtitles (AI Whisper - Auto Sync)"
        echo "3. Subtitle Composer (Pro Editor)"
        echo "4. Lyric Video (HardSub / Burned)"
        echo "5. Lyric Video (SoftSub / Toggleable)"
        echo "6. Lyric Slideshow (Multi Images)"
        echo "7. Songwriting Assistant (Rhymes, Synonyms, AI Lyrics)"
        echo "8. Return"
        echo
        read -p "Select: " choice
        case $choice in
        1) create_static_video ;;
        2)
            # AI WHISPER GENERATOR
            echo -e "${CYAN}--- AI Lyric Generator (Whisper) ---${NC}"
            if ! command -v whisper &> /dev/null; then
                echo -e "${RED}Error: OpenAI Whisper not found.${NC}"
                echo "Run: pip install openai-whisper"
                pause; return
            fi
            
            get_input_file "Drag Audio File (Vocals/Song):"
            echo -e "${CYAN}Optional: force a language (e.g. English, en, Spanish). Leave blank for auto-detect.${NC}"
            read -p "Language [auto]: " whisper_lang
            echo -e "${PURPLE}Listening and transcribing... (This may take a minute)${NC}"
            
            output_dir=$(dirname "$input_file")
            whisper_cmd=(whisper "$input_file" --model small --output_format srt --output_dir "$output_dir")
            if [[ -n "$whisper_lang" ]]; then
                whisper_cmd+=(--language "$whisper_lang")
            fi
            if ! "${whisper_cmd[@]}"; then
                echo -e "${RED}Whisper failed. Verify the audio path and language (${whisper_lang:-auto}).${NC}"
                pause
                return
            fi
            
            srt_name="$(basename "${input_file%.*}").srt"
            full_srt_path="$output_dir/$srt_name"
            
            echo -e "${GREEN}Success! Created: $full_srt_path${NC}"
            pause
            ;;
        3) launch_subtitle_composer ;;
        4) render_hardsub_lyric_video ;;
        5) render_softsub_video ;;
        6) render_slideshow_lyrics ;;
        7) python3 ""$SCRIPT_DIR"/lyric_assistant.py"; pause ;;
        8) return ;;
        *) echo -e "${RED}Invalid selection.${NC}"; sleep 1 ;;
        esac
    done
}

# ==============================================================================
# MODULE 2: Visualizer Lab - MEGA EDITION
# ==============================================================================

# Helper: Get color palette for visualizers
get_color_palette(){
    echo -e "${CYAN}--- Choose Color Palette ---${NC}"
    echo "1. Fire (red/orange/yellow)"
    echo "2. Ocean (blue/cyan/teal)"
    echo "3. Neon (pink/purple/cyan)"
    echo "4. Nature (green/lime/forest)"
    echo "5. Sunset (orange/pink/purple)"
    echo "6. Ice (white/blue/cyan)"
    echo "7. Rainbow (full spectrum)"
    echo "8. Monochrome (white/gray)"
    read -p "Select palette [1-8]: " palette_choice
    case $palette_choice in
        1) color_palette="fire"; primary_color="0xFF4500"; secondary_color="0xFFD700"; tertiary_color="0xFF0000" ;;
        2) color_palette="ocean"; primary_color="0x0066FF"; secondary_color="0x00FFFF"; tertiary_color="0x004488" ;;
        3) color_palette="neon"; primary_color="0xFF00FF"; secondary_color="0x00FFFF"; tertiary_color="0x8800FF" ;;
        4) color_palette="nature"; primary_color="0x00FF00"; secondary_color="0x88FF00"; tertiary_color="0x006600" ;;
        5) color_palette="sunset"; primary_color="0xFF6600"; secondary_color="0xFF0066"; tertiary_color="0x8800FF" ;;
        6) color_palette="ice"; primary_color="0xFFFFFF"; secondary_color="0x88CCFF"; tertiary_color="0x0088FF" ;;
        7) color_palette="rainbow"; primary_color="channel"; secondary_color="rainbow"; tertiary_color="spectrum" ;;
        *) color_palette="mono"; primary_color="0xFFFFFF"; secondary_color="0xAAAAAA"; tertiary_color="0x666666" ;;
    esac
}

# Helper: Get resolution
get_resolution(){
    echo -e "${CYAN}--- Choose Resolution ---${NC}"
    echo "1. 1080p (1920x1080) - Full HD"
    echo "2. 720p (1280x720) - HD"
    echo "3. 4K (3840x2160) - Ultra HD"
    echo "4. Square (1080x1080) - Instagram"
    echo "5. Vertical (1080x1920) - TikTok/Reels"
    read -p "Select [1-5]: " res_choice
    case $res_choice in
        1) vid_width=1920; vid_height=1080 ;;
        2) vid_width=1280; vid_height=720 ;;
        3) vid_width=3840; vid_height=2160 ;;
        4) vid_width=1080; vid_height=1080 ;;
        5) vid_width=1080; vid_height=1920 ;;
        *) vid_width=1920; vid_height=1080 ;;
    esac
}

menu_visualizers(){
    while true; do
        clear
        echo -e "${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${PURPLE}    🎨 VISUALIZER LAB MEGA EDITION v1.1 🎨               ${NC}"
        echo -e "${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo
        echo -e "${CYAN}=== 1. BASIC WAVEFORMS & LINES ===${NC}"
        echo " 1. 〰️  Symmetrical Waves"
        echo " 2. 🪞 Mirrored Bars"
        echo " 3. 🎮 Pixel Art Bars (8-bit)"
        echo " 4. ⭕ Circular Waves v2"
        echo " 5. 🌀 The Portal (Classic Circular)"
        echo
        echo -e "${CYAN}=== 2. FREQUENCY & SPECTRUM ===${NC}"
        echo " 6. 🎚️  Frequency Bands (EQ Style)"
        echo " 7. 📊 Scrolling Spectrum (Heatmap)"
        echo " 8. 📉 Audio Histogram"
        echo " 9. 🎛️  MadMooze Master (Spec + Waves)"
        echo "10. 📈 Waveform + Spectrum Combo"
        echo
        echo -e "${CYAN}=== 3. CIRCULAR & RADIAL ===${NC}"
        echo "11. 🌀 Spiral Spectrum"
        echo "12. 👑 Crown Burst"
        echo "13. 🔷 Kaleidoscope Mirror"
        echo "14. 🌐 Plasma Globe"
        echo "15. 🎪 Circus Lights"
        echo
        echo -e "${CYAN}=== 4. TECH, RETRO & SCOPES ===${NC}"
        echo "16. 📐 Vectorscope (Phase)"
        echo "17. ➰ Lissajous Curves"
        echo "18. 📟 Classic Oscilloscope"
        echo "19. 📺 VU Meter Array"
        echo "20. 💻 Matrix Rain"
        echo
        echo -e "${CYAN}=== 5. PARTICLES, FLUIDS & NATURE ===${NC}"
        echo "21. ✨ Particle Explosion"
        echo "22. 🫧 Liquid Waveform (Neon Goo)"
        echo "23. 🧬 Voronoi Diagram"
        echo "24. 💧 Water Ripples"
        echo "25. 🌊 WaveFall (Cascade)"
        echo "26. 🌊 Aurora Borealis"
        echo "27. ⭐ Reactive Starfield"
        echo
        echo -e "${CYAN}=== 6. 3D & IMMERSIVE TUNNELS ===${NC}"
        echo "28. 🏔️  3D Terrain Mesh"
        echo "29. 🌈 Rainbow Tunnel"
        echo "30. 🔲 Cube Tunnel"
        echo "31. 🔮 Mandelbrot Zoom"
        echo
        echo -e "${CYAN}=== 7. PYTHON POWERED (NEW) ===${NC}"
        echo "32. 🌋 Lava Lamp (Physics)"
        echo "33. 📊 Smooth Bars (Gradient)"
        echo "34. 〰️  Stabilized Waveform"
        echo "35. ✨ Reactive Particles"
        echo "36. 🌀 Radial Spectrum (AudioMotion Style)"
        echo "37. 🏔️  3D Terrain (Wireframe)"
        echo "38. 💜 Reactive Text/Logo"
        echo "39. 🔥 Realistic Fire (Doom Style)"
        echo "40. 🖼️  Static Waveform Image"
        echo
        echo " r. Return to Main Menu"
        echo
        read -p "Select visualizer [1-40]: " viz_choice
        
        case $viz_choice in
            # === 1. WAVEFORMS ===
            1) viz_symmetrical_waves ;;
            2) viz_mirrored_bars ;;
            3) viz_pixel_bars ;;
            4) viz_circular_waves_v2 ;;
            5) viz_portal ;;
            # === 2. SPECTRUM ===
            6) viz_frequency_bands ;;
            7) viz_scrolling_spectrum ;;
            8) viz_histogram ;;
            9) viz_madmooze_master ;;
            10) viz_combo_wave_spectrum ;;
            # === 3. RADIAL ===
            11) viz_spiral_spectrum ;;
            12) viz_crown_burst ;;
            13) viz_kaleidoscope ;;
            14) viz_plasma_globe ;;
            15) viz_circus_lights ;;
            # === 4. TECH/RETRO ===
            16) viz_vectorscope ;;
            17) viz_lissajous ;;
            18) viz_oscilloscope ;;
            19) viz_vu_meters ;;
            20) viz_matrix_rain ;;
            # === 5. PARTICLES/NATURE ===
            21) viz_particle_explosion ;;
            22) viz_metaballs ;;
            23) viz_voronoi ;;
            24) viz_water_ripples ;;
            25) viz_wavefall ;;
            26) viz_aurora ;;
            27) viz_starfield ;;
            # === 6. 3D/TUNNELS ===
            28) viz_terrain ;;
            29) viz_rainbow_tunnel ;;
            30) viz_cube_tunnel ;;
            31) viz_mandelbrot_zoom ;;
            # === 7. PYTHON ===
            32) viz_lava_lamp ;;
            33) viz_bars_smooth ;;
            34) viz_wave_stabilized ;;
            35) viz_particles_reactive ;;
            36) viz_spectrum_radial ;;
            37) viz_terrain_3d ;;
            38) viz_reactive_text ;;
            39) viz_fire_realistic ;;
            40) viz_static_thumbnails ;;
            r|R) return ;;
            *) echo -e "${RED}Invalid selection.${NC}"; sleep 1 ;;
        esac
    done
}

# ============================================================================
# CLASSIC VISUALIZERS
# ============================================================================

viz_portal(){
    echo -e "${CYAN}--- 🌀 The Portal (Circular Waveform) ---${NC}"
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
    echo -e "${GREEN}✓ Rendering Complete!${NC}"
    pause
}

viz_symmetrical_waves(){
    echo -e "${CYAN}--- 〰️ Symmetrical Waves ---${NC}"
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
    echo -e "${GREEN}✓ Rendering Complete!${NC}"
    pause
}

viz_madmooze_master(){
    echo -e "${CYAN}--- 🎛️ MadMooze Master (Spectrum + Waves) ---${NC}"
    get_input_file "Drag AUDIO:"
    read -p "Song Title: " v_title
    read -p "Artist: " v_artist
    get_optional_background
    get_output_name

    local inputs=("-i" "$input_file")
    local bg_filter=""
    local final_chain=""
    local viz_out="[out]"

    if [[ -n "$bg_image" ]]; then
        inputs+=("-loop" "1" "-i" "$bg_image")
        bg_filter="[1:v]scale=1280:720:force_original_aspect_ratio=increase,crop=1280:720[bg_img];"
        # Blend the viz onto the background
        final_chain=";[bg_img][out]blend=all_mode=screen:shortest=1[v]"
        viz_out="[out]"
    else
        final_chain=""
        viz_out="[out]"
    fi

    # If we have a final chain, we map [v], otherwise [out]
    local map_out="[out]"
    if [[ -n "$bg_image" ]]; then map_out="[v]"; fi

    ffmpeg "${inputs[@]}" -filter_complex \
    "${bg_filter}[0:a]avectorscope=s=640x518,pad=1280:720[vs]; \
     [0:a]showspectrum=mode=separate:color=magma:scale=cbrt:s=640x518[ss]; \
     [0:a]showwaves=s=1280x202:mode=line:colors=violet[sw]; \
     [vs][ss]overlay=w[bg]; \
     [bg][sw]overlay=0:H-h,drawtext=fontcolor=white:fontsize=24:x=20:y=20:text='${v_title} - ${v_artist}'${viz_out}${final_chain}" \
    -map "$map_out" -map 0:a -c:v libx264 -preset fast -crf 18 -c:a copy -shortest "$output_name"
    echo -e "${GREEN}✓ Rendering Complete!${NC}"
    pause
}

viz_scrolling_spectrum(){
    echo -e "${CYAN}--- 📊 Scrolling Spectrum (Heatmap) ---${NC}"
    get_input_file "Drag AUDIO:"
    get_optional_background
    get_output_name
    echo "Choose color scheme:"
    echo "1. Magma (fiery)"
    echo "2. Viridis (green-blue)"
    echo "3. Plasma (purple-yellow)"
    echo "4. Inferno (black-orange)"
    echo "5. Cool (blue-cyan)"
    echo "6. Channel (rainbow)"
    read -p "Select [1-6]: " color_scheme
    case $color_scheme in
        1) spec_color="magma" ;;
        2) spec_color="viridis" ;;
        3) spec_color="plasma" ;;
        4) spec_color="inferno" ;;
        5) spec_color="cool" ;;
        6) spec_color="channel" ;;
        *) spec_color="magma" ;;
    esac

    local inputs=("-i" "$input_file")
    local bg_filter=""
    local final_chain=""
    local viz_out="[v]"

    if [[ -n "$bg_image" ]]; then
        inputs+=("-loop" "1" "-i" "$bg_image")
        bg_filter="[1:v]scale=1920:1080:force_original_aspect_ratio=increase,crop=1920:1080[bg];"
        viz_out="[v_raw]"
        final_chain=";[bg][v_raw]blend=all_mode=screen:shortest=1[v]"
    fi

    ffmpeg "${inputs[@]}" -filter_complex \
    "${bg_filter}[0:a]showspectrum=slide=scroll:mode=combined:color=${spec_color}:fscale=log:scale=sqrt:legend=1:s=1920x1080${viz_out}${final_chain}" \
    -map "[v]" -map 0:a -c:v libx264 -preset fast -crf 18 -c:a copy -shortest "$output_name"
    echo -e "${GREEN}✓ Rendering Complete!${NC}"
    pause
}

viz_mandelbrot_zoom(){
    echo -e "${CYAN}--- 🔮 Mandelbrot Zoom (Fractal) ---${NC}"
    get_input_file "Drag AUDIO:"
    get_output_name
    ffmpeg -i "$input_file" -f lavfi -i mandelbrot=s=1280x720:rate=25 -filter_complex \
    "[0:a]showwaves=mode=line:s=1280x720:colors=violet@0.6|cyan@0.6:scale=sqrt[waves]; \
     [1:v][waves]overlay=format=auto[out]" \
    -map "[out]" -map 0:a -c:v libx264 -preset ultrafast -c:a copy -shortest "$output_name"
    echo -e "${GREEN}✓ Rendering Complete!${NC}"
    pause
}

viz_static_thumbnails(){
    echo -e "${CYAN}--- 🖼️ Static Thumbnails ---${NC}"
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
}

# ============================================================================
# GEOMETRIC VISUALIZERS
# ============================================================================

viz_kaleidoscope(){
    echo -e "${CYAN}--- 🔷 Kaleidoscope Mirror ---${NC}"
    get_input_file "Drag AUDIO file:"
    get_resolution
    get_waveform_color
    get_optional_background
    get_output_name
    echo "Choose style:"
    echo "1. 4-way mirror (classic)"
    echo "2. Radial blend"
    echo "3. Diamond pattern"
    read -p "Select [1-3]: " seg_choice
    echo -e "${PURPLE}Creating kaleidoscope effect...${NC}"

    local inputs=("-i" "$input_file")
    local bg_filter=""
    local final_chain=""
    local viz_out="[v]"

    if [[ -n "$bg_image" ]]; then
        inputs+=("-loop" "1" "-i" "$bg_image")
        # Scale background to video size
        bg_filter="[1:v]scale=${vid_width}:${vid_height}:force_original_aspect_ratio=increase,crop=${vid_width}:${vid_height}[bg];"
        # Blend viz onto background
        viz_out="[v_raw]"
        final_chain=";[bg][v_raw]blend=all_mode=screen:shortest=1[v]"
    fi

    case $seg_choice in
        2)
            ffmpeg "${inputs[@]}" -filter_complex \
            "${bg_filter}[0:a]showwaves=s=${vid_width}x${vid_height}:mode=p2p:rate=30:colors=${wave_color}[wave]; \
             [wave]split[a][b]; \
             [a]hflip[aflip]; \
             [b][aflip]blend=all_mode=average${viz_out}${final_chain}" \
            -map "[v]" -map 0:a -c:v libx264 -preset fast -crf 18 -c:a copy -shortest "$output_name"
            ;;
        3)
            ffmpeg "${inputs[@]}" -filter_complex \
            "${bg_filter}[0:a]showwaves=s=${vid_width}x${vid_height}:mode=p2p:rate=30:colors=${wave_color}, \
             split[a][b]; \
             [a]transpose=1[at]; \
             [b]transpose=2[bt]; \
             [at][bt]blend=all_mode=screen${viz_out}${final_chain}" \
            -map "[v]" -map 0:a -c:v libx264 -preset fast -crf 18 -c:a copy -shortest "$output_name"
            ;;
        *)
            ffmpeg "${inputs[@]}" -filter_complex \
            "${bg_filter}[0:a]showwaves=s=${vid_width}x${vid_height}:mode=p2p:rate=30:colors=${wave_color}[wave]; \
             [wave]split=4[w1][w2][w3][w4]; \
             [w1]crop=iw/2:ih/2:0:0[q1]; \
             [w2]crop=iw/2:ih/2:0:0,hflip[q2]; \
             [w3]crop=iw/2:ih/2:0:0,vflip[q3]; \
             [w4]crop=iw/2:ih/2:0:0,hflip,vflip[q4]; \
             [q1][q2]hstack[top]; \
             [q3][q4]hstack[bottom]; \
             [top][bottom]vstack${viz_out}${final_chain}" \
            -map "[v]" -map 0:a -c:v libx264 -preset fast -crf 18 -c:a copy -shortest "$output_name"
            ;;
    esac
    echo -e "${GREEN}✓ Kaleidoscope Complete!${NC}"
    pause
}

viz_spiral_spectrum(){
    echo -e "${CYAN}--- 🌀 Spiral Spectrum ---${NC}"
    get_input_file "Drag AUDIO file:"
    get_optional_background
    get_output_name
    echo -e "${PURPLE}Creating spiral spectrum...${NC}"

    local inputs=("-i" "$input_file")
    local bg_filter=""
    local final_chain=""
    local viz_out="[v]"

    if [[ -n "$bg_image" ]]; then
        inputs+=("-loop" "1" "-i" "$bg_image")
        bg_filter="[1:v]scale=1280:720:force_original_aspect_ratio=increase,crop=1280:720[bg];"
        viz_out="[v_raw]"
        final_chain=";[bg][v_raw]blend=all_mode=screen:shortest=1[v]"
    fi

    # Use avectorscope in polar mode for true spiral effect
    ffmpeg "${inputs[@]}" -filter_complex \
    "${bg_filter}[0:a]avectorscope=s=720x720:mode=polar:draw=line:scale=sqrt:rc=40:gc=200:bc=170:rf=15:gf=40:bf=25[scope]; \
     [scope]pad=1280:720:(ow-iw)/2:(oh-ih)/2:black@0, \
     colorbalance=bs=0.3:gs=0.2${viz_out}${final_chain}" \
    -map "[v]" -map 0:a -c:v libx264 -preset fast -crf 18 -c:a copy -shortest "$output_name"
    echo -e "${GREEN}✓ Spiral Spectrum Complete!${NC}"
    pause
}

viz_lissajous(){
    echo -e "${CYAN}--- ➰ Lissajous Curves (Oscilloscope XY) ---${NC}"
    get_input_file "Drag STEREO AUDIO file:"
    get_optional_background
    get_output_name
    echo "Choose style:"
    echo "1. Classic (green phosphor)"
    echo "2. Modern (rainbow)"
    echo "3. Neon (pink/cyan)"
    read -p "Select [1-3]: " liss_style
    case $liss_style in
        1) liss_color="0x00FF00"; liss_mode="lissajous" ;;
        2) liss_color="0xFFFFFF"; liss_mode="lissajous_xy" ;;
        3) liss_color="0xFF00FF"; liss_mode="lissajous" ;;
        *) liss_color="0x00FF00"; liss_mode="lissajous" ;;
    esac
    echo -e "${PURPLE}Generating Lissajous curves...${NC}"

    local inputs=("-i" "$input_file")
    local bg_filter=""
    local final_chain=""
    local viz_out="[v]"

    if [[ -n "$bg_image" ]]; then
        inputs+=("-loop" "1" "-i" "$bg_image")
        bg_filter="[1:v]scale=1280:720:force_original_aspect_ratio=increase,crop=1280:720[bg];"
        viz_out="[v_raw]"
        final_chain=";[bg][v_raw]blend=all_mode=screen:shortest=1[v]"
    fi

    ffmpeg "${inputs[@]}" -filter_complex \
    "${bg_filter}[0:a]avectorscope=s=1280x720:mode=${liss_mode}:draw=line:scale=sqrt:rc=40:gc=160:bc=80:rf=15:gf=40:bf=20${viz_out}${final_chain}" \
    -map "[v]" -map 0:a -c:v libx264 -preset fast -crf 18 -c:a copy -shortest "$output_name"
    echo -e "${GREEN}✓ Lissajous Complete!${NC}"
    pause
}

viz_crown_burst(){
    echo -e "${CYAN}--- 👑 Crown Burst (Radial) ---${NC}"
    get_input_file "Drag AUDIO file:"
    get_resolution
    get_waveform_color
    get_optional_background
    get_output_name
    echo "Choose crown style:"
    echo "1. Royal (purple/gold)"
    echo "2. Crystal (cyan/white)"
    echo "3. Custom (your color)"
    read -p "Select [1-3]: " crown_style
    case $crown_style in
        1) c_rc="180"; c_gc="120"; c_bc="255"; c_bal="rs=0.3:bs=0.4" ;;
        2) c_rc="100"; c_gc="220"; c_bc="255"; c_bal="gs=0.3:bs=0.4" ;;
        *) c_rc="200"; c_gc="200"; c_bc="200"; c_bal="rs=0.1:gs=0.1:bs=0.1" ;;
    esac
    echo -e "${PURPLE}Creating crown burst visualization...${NC}"

    local inputs=("-i" "$input_file")
    local bg_filter=""
    local final_chain=""
    local viz_out="[v]"

    if [[ -n "$bg_image" ]]; then
        inputs+=("-loop" "1" "-i" "$bg_image")
        bg_filter="[1:v]scale=${vid_width}:${vid_height}:force_original_aspect_ratio=increase,crop=${vid_width}:${vid_height}[bg];"
        viz_out="[v_raw]"
        final_chain=";[bg][v_raw]blend=all_mode=screen:shortest=1[v]"
    fi

    ffmpeg "${inputs[@]}" -filter_complex \
    "${bg_filter}[0:a]avectorscope=s=${vid_width}x${vid_height}:mode=polar:draw=line:scale=sqrt:rc=${c_rc}:gc=${c_gc}:bc=${c_bc}:rf=30:gf=20:bf=40[scope]; \
     [scope]lagfun=decay=0.93, \
     gblur=sigma=3, \
     colorbalance=${c_bal}, \
     eq=contrast=1.3:saturation=1.5${viz_out}${final_chain}" \
    -map "[v]" -map 0:a -c:v libx264 -preset fast -crf 18 -c:a copy -shortest "$output_name"
    echo -e "${GREEN}✓ Crown Burst Complete!${NC}"
    pause
}

viz_mirrored_bars(){
    echo -e "${CYAN}--- 🪞 Mirrored Bars (Reflection) ---${NC}"
    get_input_file "Drag AUDIO file:"
    get_resolution
    get_optional_background
    get_output_name
    echo "Choose mirror style:"
    echo "1. Top-Bottom (classic)"
    echo "2. Left-Right"
    echo "3. Four-way"
    read -p "Select [1-3]: " mirror_style
    echo -e "${PURPLE}Creating mirrored bars...${NC}"

    local inputs=("-i" "$input_file")
    local bg_filter=""
    local final_chain=""
    local viz_out="[v]"

    if [[ -n "$bg_image" ]]; then
        inputs+=("-loop" "1" "-i" "$bg_image")
        bg_filter="[1:v]scale=${vid_width}:${vid_height}:force_original_aspect_ratio=increase,crop=${vid_width}:${vid_height}[bg];"
        viz_out="[v_raw]"
        final_chain=";[bg][v_raw]blend=all_mode=screen:shortest=1[v]"
    fi

    case $mirror_style in
        1)
            ffmpeg "${inputs[@]}" -filter_complex \
            "${bg_filter}[0:a]showwaves=s=${vid_width}x$((vid_height/2)):mode=cline:rate=30:colors=violet|cyan,split[w1][w2]; \
             [w2]vflip[w2f]; \
             [w1][w2f]vstack,format=yuv420p${viz_out}${final_chain}" \
            -map "[v]" -map 0:a -c:v libx264 -preset fast -crf 18 -c:a copy -shortest "$output_name"
            ;;
        2)
            ffmpeg "${inputs[@]}" -filter_complex \
            "${bg_filter}[0:a]showwaves=s=$((vid_width/2))x${vid_height}:mode=cline:rate=30:colors=violet|cyan,split[w1][w2]; \
             [w2]hflip[w2f]; \
             [w1][w2f]hstack,format=yuv420p${viz_out}${final_chain}" \
            -map "[v]" -map 0:a -c:v libx264 -preset fast -crf 18 -c:a copy -shortest "$output_name"
            ;;
        3)
            ffmpeg "${inputs[@]}" -filter_complex \
            "${bg_filter}[0:a]showwaves=s=$((vid_width/2))x$((vid_height/2)):mode=cline:rate=30:colors=violet|cyan,split=4[w1][w2][w3][w4]; \
             [w2]hflip[w2f]; [w3]vflip[w3f]; [w4]hflip,vflip[w4f]; \
             [w1][w2f]hstack[top]; [w3f][w4f]hstack[bot]; \
             [top][bot]vstack,format=yuv420p${viz_out}${final_chain}" \
            -map "[v]" -map 0:a -c:v libx264 -preset fast -crf 18 -c:a copy -shortest "$output_name"
            ;;
    esac
    echo -e "${GREEN}✓ Mirrored Bars Complete!${NC}"
    pause
}

# ============================================================================
# NATURE-INSPIRED VISUALIZERS
# ============================================================================

viz_wavefall(){
    echo -e "${CYAN}--- 🌊 WaveFall (Cascade) ---${NC}"
    get_input_file "Drag AUDIO file:"
    get_resolution
    get_waveform_color
    get_optional_background
    get_output_name
    echo "Choose cascade intensity:"
    echo "1. Gentle (soft, flowing)"
    echo "2. Steady (balanced cascade)"
    echo "3. Torrent (intense, rapid)"
    read -p "Select [1-3]: " fall_style
    case $fall_style in
        1) f_decay="0.92"; f_blur="8"; f_sat="2"; f_speed="-0.010" ;;
        2) f_decay="0.95"; f_blur="5"; f_sat="3"; f_speed="-0.015" ;;
        3) f_decay="0.97"; f_blur="3"; f_sat="4"; f_speed="-0.025" ;;
        *) f_decay="0.95"; f_blur="5"; f_sat="3"; f_speed="-0.015" ;;
    esac
    echo -e "${PURPLE}Generating wavefall cascade...${NC}"

    local inputs=("-i" "$input_file")
    local bg_filter=""
    local final_chain=""
    local viz_out="[v]"

    if [[ -n "$bg_image" ]]; then
        inputs+=("-loop" "1" "-i" "$bg_image")
        bg_filter="[1:v]scale=${vid_width}:${vid_height}:force_original_aspect_ratio=increase,crop=${vid_width}:${vid_height}[bg];"
        viz_out="[v_raw]"
        final_chain=";[bg][v_raw]blend=all_mode=screen:shortest=1[v]"
    fi

    ffmpeg "${inputs[@]}" -filter_complex \
    "${bg_filter}[0:a]showwaves=s=${vid_width}x${vid_height}:mode=p2p:rate=30:colors=${wave_color}:scale=sqrt[wave]; \
     [wave]vflip, \
     scroll=v=${f_speed}:h=0, \
     lagfun=decay=${f_decay}, \
     gblur=sigma=${f_blur}, \
     eq=contrast=1.4:saturation=${f_sat}:brightness=0.05, \
     vignette=angle=PI/3${viz_out}${final_chain}" \
    -map "[v]" -map 0:a -c:v libx264 -preset fast -crf 18 -c:a copy -shortest "$output_name"
    echo -e "${GREEN}✓ WaveFall Complete!${NC}"
    pause
}

viz_water_ripples(){
    echo -e "${CYAN}--- 💧 Water Ripples ---${NC}"
    get_input_file "Drag AUDIO file:"
    get_resolution
    get_optional_background
    get_output_name
    echo "Choose water style:"
    echo "1. Ocean (deep blue, slow waves)"
    echo "2. Pool (cyan, medium ripples)"
    echo "3. Pond (teal, subtle reflections)"
    read -p "Select [1-3]: " water_style
    case $water_style in
        1) w_colors="0x001133@0.9|0x0044AA@0.7|0x0088DD@0.5"; w_speed="8"; w_blur="4" ;;
        2) w_colors="0x00AACC@0.8|0x00DDFF@0.6|0x88FFFF@0.4"; w_speed="5"; w_blur="2" ;;
        3) w_colors="0x004444@0.8|0x006666@0.6|0x00AAAA@0.5"; w_speed="12"; w_blur="6" ;;
        *) w_colors="0x00AACC@0.8|0x00DDFF@0.6|0x88FFFF@0.4"; w_speed="5"; w_blur="2" ;;
    esac
    echo -e "${PURPLE}Creating water ripple effect...${NC}"

    local inputs=("-i" "$input_file")
    local bg_filter=""
    local final_chain=""
    local viz_out="[v]"

    if [[ -n "$bg_image" ]]; then
        inputs+=("-loop" "1" "-i" "$bg_image")
        bg_filter="[1:v]scale=${vid_width}:${vid_height}:force_original_aspect_ratio=increase,crop=${vid_width}:${vid_height}[bg];"
        viz_out="[v_raw]"
        final_chain=";[bg][v_raw]blend=all_mode=screen:shortest=1[v]"
    fi

    ffmpeg "${inputs[@]}" -filter_complex \
    "${bg_filter}[0:a]showwaves=s=${vid_width}x${vid_height}:mode=p2p:rate=30:colors=${w_colors}:scale=sqrt[wave]; \
     [wave]split[w1][w2]; \
     [w1]gblur=sigma=${w_blur},geq=lum='lum(X,Y)':cb='cb(X,Y)+15*sin(hypot(X-W/2,Y-H/2)/25-t*${w_speed})':cr='cr(X,Y)+15*cos(hypot(X-W/2,Y-H/2)/25-t*${w_speed})'[ripple]; \
     [w2]vflip,format=rgba,colorchannelmixer=aa=0.3[reflect]; \
     [ripple][reflect]blend=all_mode=addition, \
     eq=brightness=-0.05:contrast=1.2:saturation=1.3, \
     vignette=angle=PI/4${viz_out}${final_chain}" \
    -map "[v]" -map 0:a -c:v libx264 -preset fast -crf 18 -c:a copy -shortest "$output_name"
    echo -e "${GREEN}✓ Water Ripples Complete!${NC}"
    pause
}

viz_aurora(){
    echo -e "${CYAN}--- 🌊 Aurora Borealis ---${NC}"
    get_input_file "Drag AUDIO file:"
    get_resolution
    get_optional_background
    get_output_name
    echo -e "${PURPLE}Creating aurora effect...${NC}"

    local inputs=("-i" "$input_file")
    local bg_filter=""
    local final_chain=""
    local viz_out="[v]"

    if [[ -n "$bg_image" ]]; then
        inputs+=("-loop" "1" "-i" "$bg_image")
        bg_filter="[1:v]scale=${vid_width}:${vid_height}:force_original_aspect_ratio=increase,crop=${vid_width}:${vid_height}[bg];"
        viz_out="[v_raw]"
        final_chain=";[bg][v_raw]blend=all_mode=screen:shortest=1[v]"
    fi

    ffmpeg "${inputs[@]}" -filter_complex \
    "${bg_filter}[0:a]showspectrum=s=${vid_width}x${vid_height}:slide=scroll:mode=combined:color=cool:scale=sqrt:saturation=3[spec]; \
     [spec]hue=h=t*15:s=2,colorbalance=bs=0.4:gs=0.3${viz_out}${final_chain}" \
    -map "[v]" -map 0:a -c:v libx264 -preset fast -crf 18 -c:a copy -shortest "$output_name"
    echo -e "${GREEN}✓ Aurora Complete!${NC}"
    pause
}

viz_starfield(){
    echo -e "${CYAN}--- ⭐ Reactive Starfield ---${NC}"
    get_input_file "Drag AUDIO file:"
    get_resolution
    get_optional_background
    get_output_name
    echo -e "${PURPLE}Creating starfield visualization...${NC}"

    local inputs=("-i" "$input_file")
    local bg_filter=""
    local final_chain=""
    local viz_out="[v]"

    if [[ -n "$bg_image" ]]; then
        inputs+=("-loop" "1" "-i" "$bg_image")
        bg_filter="[2:v]scale=${vid_width}:${vid_height}:force_original_aspect_ratio=increase,crop=${vid_width}:${vid_height}[bg];"
        viz_out="[v_raw]"
        final_chain=";[bg][v_raw]blend=all_mode=screen:shortest=1[v]"
    fi

    # Note: starfield uses lavfi as input 1, so background will be input 2 if present
    ffmpeg "${inputs[@]}" -f lavfi -i "life=s=${vid_width}x${vid_height}:mold=10:r=30:ratio=0.1:death_color=black:life_color=white,negate" \
    -filter_complex \
    "${bg_filter}[0:a]showwaves=s=${vid_width}x${vid_height}:mode=cline:rate=30:colors=white@0.3,format=rgba[wave]; \
     [1:v][wave]blend=all_mode=screen:shortest=1${viz_out}${final_chain}" \
    -map "[v]" -map 0:a -c:v libx264 -preset fast -crf 18 -c:a copy -shortest "$output_name"
    echo -e "${GREEN}✓ Starfield Complete!${NC}"
    pause
}

# ============================================================================
# RETRO / ARTISTIC VISUALIZERS
# ============================================================================

viz_vu_meters(){
    echo -e "${CYAN}--- 📺 VU Meter Array (Analog Style) ---${NC}"
    get_input_file "Drag AUDIO file:"
    get_optional_background
    get_output_name
    echo -e "${PURPLE}Creating VU meters (green-yellow-red gradient)...${NC}"

    local inputs=("-i" "$input_file")
    local bg_filter=""
    local final_chain=""
    local viz_out="[v]"

    if [[ -n "$bg_image" ]]; then
        inputs+=("-loop" "1" "-i" "$bg_image")
        # Scale background to 1280x720
        bg_filter="[1:v]scale=1280:720:force_original_aspect_ratio=increase,crop=1280:720[bg];"
        # Instead of padding with black, we overlay the meters on the background
        final_chain=";[bg][tmp]overlay=(W-w)/2:(H-h)/2:shortest=1[v]"
        viz_out="[tmp]" # The stack is now intermediate
    else
        # Original behavior: pad with black
        final_chain=";[tmp]pad=w='max(iw,1280)':h='max(ih,720)':x='(ow-iw)/2':y='(oh-ih)/2':color=black[v]"
        viz_out="[tmp]"
    fi

    ffmpeg "${inputs[@]}" -filter_complex \
    "${bg_filter}[0:a]showvolume=f=0.9:b=4:w=1280:h=100:t=0[vol]; \
     [0:a]showspectrum=s=1280x520:mode=combined:color=channel:slide=replace:scale=sqrt[spec]; \
     [spec][vol]vstack=inputs=2${viz_out}${final_chain}" \
    -map "[v]" -map 0:a -c:v libx264 -preset fast -crf 18 -c:a copy -shortest "$output_name"
    echo -e "${GREEN}✓ VU Meters Complete!${NC}"
    pause
}

viz_oscilloscope(){
    echo -e "${CYAN}--- 📟 Classic Oscilloscope (Green Screen) ---${NC}"
    get_input_file "Drag AUDIO file:"
    get_optional_background
    get_output_name
    echo -e "${PURPLE}Creating oscilloscope display...${NC}"

    local inputs=("-i" "$input_file")
    local bg_source="color=black:s=1280x720:r=30[bg];"

    if [[ -n "$bg_image" ]]; then
        inputs+=("-loop" "1" "-i" "$bg_image")
        bg_source="[1:v]scale=1280:720:force_original_aspect_ratio=increase,crop=1280:720[bg];"
    fi

    ffmpeg "${inputs[@]}" -filter_complex \
    "${bg_source} \
     [0:a]showwaves=s=1200x680:mode=line:rate=30:colors=0x00FF00@0.9:scale=sqrt[wave]; \
     [bg][wave]overlay=(W-w)/2:(H-h)/2, \
     drawgrid=width=80:height=68:thickness=1:color=0x00FF00@0.2, \
     drawtext=fontcolor=0x00FF00:fontsize=14:x=10:y=10:text='OSCILLOSCOPE':font=mono, \
     vignette=angle=PI/4:mode=backward[v]" \
    -map "[v]" -map 0:a -c:v libx264 -preset fast -crf 18 -c:a copy -shortest "$output_name"
    echo -e "${GREEN}✓ Oscilloscope Complete!${NC}"
    pause
}

viz_matrix_rain(){
    echo -e "${CYAN}--- 💻 Matrix Rain (Audio Reactive) ---${NC}"
    get_input_file "Drag AUDIO file:"
    get_resolution
    get_optional_background
    get_output_name
    echo "Choose Matrix style:"
    echo "1. Classic (green code)"
    echo "2. Hacker (cyan/blue)"
    echo "3. Corrupted (red glitch)"
    read -p "Select [1-3]: " matrix_style
    case $matrix_style in
        1) m_color="0x00FF00"; m_glow="gs=0.8"; m_life="0x003300" ;;
        2) m_color="0x00FFFF"; m_glow="bs=0.8"; m_life="0x003333" ;;
        3) m_color="0xFF3333"; m_glow="rs=0.8"; m_life="0x330000" ;;
        *) m_color="0x00FF00"; m_glow="gs=0.8"; m_life="0x003300" ;;
    esac
    echo -e "${PURPLE}Creating Matrix rain effect...${NC}"

    local inputs=("-i" "$input_file")
    local bg_filter=""
    local final_chain=""
    local viz_out="[v]"
    local rain_input="[1:v]"

    if [[ -n "$bg_image" ]]; then
        inputs+=("-loop" "1" "-i" "$bg_image")
        bg_filter="[2:v]scale=${vid_width}:${vid_height}:force_original_aspect_ratio=increase,crop=${vid_width}:${vid_height}[bg];"
        viz_out="[v_raw]"
        final_chain=";[bg][v_raw]blend=all_mode=screen:shortest=1[v]"
        rain_input="[1:v]" # Still 1 because lavfi is separate input in command
    fi

    # Note: lavfi is input 1 (after audio input 0). Background is input 2 if present.
    ffmpeg "${inputs[@]}" \
    -f lavfi -i "life=s=${vid_width}x${vid_height}:mold=8:r=30:ratio=0.03:death_color=black:life_color=${m_life}" \
    -filter_complex \
    "${bg_filter}[0:a]showspectrum=s=${vid_width}x${vid_height}:mode=combined:color=green:slide=scroll:scale=log:saturation=2[spec]; \
     [spec]colorchannelmixer=${m_glow}:aa=0.7[specglow]; \
     ${rain_input}scroll=v=0.02:h=0,lagfun=decay=0.95[rain]; \
     [rain][specglow]blend=all_mode=screen:shortest=1, \
     gblur=sigma=1, \
     eq=contrast=1.4:brightness=0.05, \
     vignette=angle=PI/5${viz_out}${final_chain}" \
    -map "[v]" -map 0:a -c:v libx264 -preset fast -crf 18 -c:a copy -shortest "$output_name"
    echo -e "${GREEN}✓ Matrix Rain Complete!${NC}"
    pause
}

viz_pixel_bars(){
    echo -e "${CYAN}--- 🎮 Pixel Art Bars (8-bit Style) ---${NC}"
    get_input_file "Drag AUDIO file:"
    get_optional_background
    get_output_name
    echo -e "${PURPLE}Creating pixelated visualization...${NC}"

    local inputs=("-i" "$input_file")
    local bg_filter=""
    local final_chain=""
    local viz_out="[v]"

    if [[ -n "$bg_image" ]]; then
        inputs+=("-loop" "1" "-i" "$bg_image")
        bg_filter="[1:v]scale=1280:720:force_original_aspect_ratio=increase,crop=1280:720[bg];"
        viz_out="[v_raw]"
        final_chain=";[bg][v_raw]blend=all_mode=screen:shortest=1[v]"
    fi

    ffmpeg "${inputs[@]}" -filter_complex \
    "${bg_filter}[0:a]showwaves=s=160x90:mode=cline:rate=30:colors=violet|cyan|green|yellow|orange|red,scale=1280:720:flags=neighbor${viz_out}${final_chain}" \
    -map "[v]" -map 0:a -c:v libx264 -preset fast -crf 18 -c:a copy -shortest "$output_name"
    echo -e "${GREEN}✓ Pixel Bars Complete!${NC}"
    pause
}

# ============================================================================
# MODERN / ABSTRACT VISUALIZERS
# ============================================================================

viz_metaballs(){
    echo -e "${CYAN}--- 🫧 Liquid Waveform (Neon Goo) ---${NC}"
    get_input_file "Drag AUDIO file:"
    get_resolution
    get_optional_background
    get_output_name
    echo -e "${PURPLE}Creating liquid waveform...${NC}"

    local inputs=("-i" "$input_file")
    local bg_filter=""
    local final_chain=""
    local viz_out="[v]"

    if [[ -n "$bg_image" ]]; then
        inputs+=("-loop" "1" "-i" "$bg_image")
        bg_filter="[1:v]scale=${vid_width}:${vid_height}:force_original_aspect_ratio=increase,crop=${vid_width}:${vid_height}[bg];"
        viz_out="[v_raw]"
        final_chain=";[bg][v_raw]blend=all_mode=screen:shortest=1[v]"
    fi

    # Fixed: Force mono and use cline mode to ensure waveform is visible enough to survive the blur/threshold
    ffmpeg "${inputs[@]}" -filter_complex \
    "${bg_filter}[0:a]aformat=channel_layouts=mono,showwaves=s=${vid_width}x${vid_height}:mode=cline:rate=30:colors=magenta:scale=sqrt, \
     gblur=sigma=20, \
     curves=all='0/0 0.3/0 0.5/1 1/1', \
     gblur=sigma=8, \
     colorbalance=rs=0.4:bs=0.5:gs=-0.2, \
     eq=contrast=1.5:brightness=0.1${viz_out}${final_chain}" \
    -map "[v]" -map 0:a -c:v libx264 -preset fast -crf 18 -c:a copy -shortest "$output_name"
    echo -e "${GREEN}✓ Liquid Waveform Complete!${NC}"
    pause
}

viz_terrain(){
    echo -e "${CYAN}--- 🏔️ 3D Terrain Mesh ---${NC}"
    get_input_file "Drag AUDIO file:"
    get_optional_background
    get_output_name
    echo -e "${PURPLE}Creating terrain visualization...${NC}"

    local inputs=("-i" "$input_file")
    local bg_filter=""
    local final_chain=""
    local viz_out="[v]"

    if [[ -n "$bg_image" ]]; then
        inputs+=("-loop" "1" "-i" "$bg_image")
        bg_filter="[1:v]scale=1280:720:force_original_aspect_ratio=increase,crop=1280:720[bg];"
        viz_out="[v_raw]"
        final_chain=";[bg][v_raw]blend=all_mode=screen:shortest=1[v]"
    fi

    ffmpeg "${inputs[@]}" -filter_complex \
    "${bg_filter}[0:a]showspectrum=s=1280x720:mode=combined:color=terrain:slide=scroll:scale=log:fscale=log:orientation=vertical[spec]; \
     [spec]perspective=x0=100:y0=50:x1=1180:y1=100:x2=0:y2=720:x3=1280:y3=720:sense=destination${viz_out}${final_chain}" \
    -map "[v]" -map 0:a -c:v libx264 -preset fast -crf 18 -c:a copy -shortest "$output_name"
    echo -e "${GREEN}✓ Terrain Complete!${NC}"
    pause
}

viz_voronoi(){
    echo -e "${CYAN}--- 🧬 Voronoi / Cell Pattern ---${NC}"
    get_input_file "Drag AUDIO file:"
    get_resolution
    get_optional_background
    get_output_name
    echo -e "${PURPLE}Creating Voronoi-style cell pattern...${NC}"

    local inputs=("-i" "$input_file")
    local bg_filter=""
    local final_chain=""
    local viz_out="[v]"

    if [[ -n "$bg_image" ]]; then
        inputs+=("-loop" "1" "-i" "$bg_image")
        bg_filter="[1:v]scale=${vid_width}:${vid_height}:force_original_aspect_ratio=increase,crop=${vid_width}:${vid_height}[bg];"
        viz_out="[v_raw]"
        final_chain=";[bg][v_raw]blend=all_mode=screen:shortest=1[v]"
    fi

    ffmpeg "${inputs[@]}" -filter_complex \
    "${bg_filter}[0:a]showwaves=s=${vid_width}x${vid_height}:mode=cline:rate=30:colors=cyan|lime|magenta[wave]; \
     [wave]split=3[a][b][c]; \
     [a]negate[neg]; \
     [b]hue=h=120[hue1]; \
     [c]hue=h=240[hue2]; \
     [neg][hue1]blend=all_mode=difference[mix1]; \
     [mix1][hue2]blend=all_mode=screen, \
     edgedetect=mode=colormix:high=0.2:low=0.05, \
     colorbalance=rs=0.3:gs=-0.2:bs=0.4, \
     eq=contrast=1.5:saturation=1.5${viz_out}${final_chain}" \
    -map "[v]" -map 0:a -c:v libx264 -preset fast -crf 18 -c:a copy -shortest "$output_name"
    echo -e "${GREEN}✓ Voronoi Complete!${NC}"
    pause
}

viz_particle_explosion(){
    echo -e "${CYAN}--- ✨ Particle Explosion ---${NC}"
    get_input_file "Drag AUDIO file:"
    get_resolution
    get_optional_background
    get_output_name
    echo "Choose particle style:"
    echo "1. Neon Burst (cyan/magenta)"
    echo "2. Ember Sparks (orange/red)"
    echo "3. Aurora Shards (blue/violet)"
    read -p "Select [1-3]: " p_style
    case $p_style in
        1) p_colors="cyan|magenta|white"; p_decay="0.93"; p_blur="2"; p_hue="210" ;;
        2) p_colors="gold|orange|red"; p_decay="0.95"; p_blur="3"; p_hue="30" ;;
        3) p_colors="blue|aqua|violet"; p_decay="0.94"; p_blur="4"; p_hue="280" ;;
        *) p_colors="cyan|magenta|white"; p_decay="0.93"; p_blur="2"; p_hue="210" ;;
    esac
    p_hue2="$((p_hue + 90))"
    echo -e "${PURPLE}Creating particle explosion...${NC}"

    local inputs=("-i" "$input_file")
    local bg_filter=""
    local final_chain=""
    local viz_out="[v]"

    if [[ -n "$bg_image" ]]; then
        inputs+=("-loop" "1" "-i" "$bg_image")
        bg_filter="[1:v]scale=${vid_width}:${vid_height}:force_original_aspect_ratio=increase,crop=${vid_width}:${vid_height}[bg];"
        viz_out="[v_raw]"
        final_chain=";[bg][v_raw]blend=all_mode=screen:shortest=1[v]"
    fi

    ffmpeg "${inputs[@]}" -filter_complex \
    "${bg_filter}[0:a]showwaves=s=${vid_width}x${vid_height}:mode=p2p:rate=30:colors=${p_colors}:scale=sqrt[wave]; \
     [wave]split=3[w1][w2][w3]; \
     [w1]lagfun=decay=${p_decay},gblur=sigma=${p_blur}[base]; \
     [w2]edgedetect=mode=colormix:high=0.35:low=0.05,hue=h=${p_hue}[edge]; \
     [w3]hue=h=${p_hue2},gblur=sigma=6[glow]; \
     [base][edge]blend=all_mode=screen[mix1]; \
     [mix1][glow]blend=all_mode=lighten, \
     eq=contrast=1.35:saturation=1.6:brightness=0.02${viz_out}${final_chain}" \
    -map "[v]" -map 0:a -c:v libx264 -preset fast -crf 18 -c:a copy -shortest "$output_name"
    echo -e "${GREEN}✓ Particle Explosion Complete!${NC}"
    pause
}

viz_plasma_globe(){
    echo -e "${CYAN}--- 🌐 Plasma Globe ---${NC}"
    get_input_file "Drag AUDIO file:"
    get_optional_background
    get_output_name
    echo "Choose plasma style:"
    echo "1. Electric (purple/blue arcs)"
    echo "2. Neon (pink/cyan glow)"
    echo "3. Fire Orb (orange/red energy)"
    read -p "Select [1-3]: " plasma_style
    case $plasma_style in
        1) p_colors="violet|blue|cyan"; p_bal="bs=0.5:gs=-0.2:rs=-0.3"; p_spec="cool" ;;
        2) p_colors="magenta|cyan|white"; p_bal="bs=0.3:gs=0.2:rs=0.3"; p_spec="rainbow" ;;
        3) p_colors="red|orange|yellow"; p_bal="rs=0.5:gs=0.2:bs=-0.3"; p_spec="fire" ;;
        *) p_colors="violet|blue|cyan"; p_bal="bs=0.5:gs=-0.2:rs=-0.3"; p_spec="cool" ;;
    esac
    echo -e "${PURPLE}Creating plasma globe effect...${NC}"

    local inputs=("-i" "$input_file")
    local bg_filter=""
    local final_chain=""
    local viz_out="[v]"

    if [[ -n "$bg_image" ]]; then
        inputs+=("-loop" "1" "-i" "$bg_image")
        bg_filter="[1:v]scale=1280:720:force_original_aspect_ratio=increase,crop=1280:720[bg];"
        viz_out="[v_raw]"
        final_chain=";[bg][v_raw]blend=all_mode=screen:shortest=1[v]"
    fi

    ffmpeg "${inputs[@]}" -filter_complex \
    "${bg_filter}color=black:s=1280x720:r=30[base_bg]; \
     [0:a]showspectrum=s=720x720:mode=combined:color=${p_spec}:slide=fullframe:scale=sqrt:saturation=3[spec]; \
     [0:a]avectorscope=s=720x720:mode=lissajous_xy:draw=line:scale=sqrt:rc=200:gc=100:bc=255:rf=40:gf=20:bf=60[scope]; \
     [spec]gblur=sigma=20[specblur]; \
     [scope]gblur=sigma=5[scopeblur]; \
     [specblur][scopeblur]blend=all_mode=screen[orb]; \
     [orb]lagfun=decay=0.94, \
     hue=h=t*20:s=1.5, \
     colorbalance=${p_bal}[plasma]; \
     [base_bg][plasma]overlay=(W-w)/2:(H-h)/2, \
     vignette=angle=PI/2:x0=0.5:y0=0.5, \
     eq=contrast=1.2:saturation=1.4${viz_out}${final_chain}" \
    -map "[v]" -map 0:a -c:v libx264 -preset fast -crf 18 -c:a copy -shortest "$output_name"
    echo -e "${GREEN}✓ Plasma Globe Complete!${NC}"
    pause
}

# ============================================================================
# PROFESSIONAL SCOPES
# ============================================================================

viz_vectorscope(){
    echo -e "${CYAN}--- 📐 Vectorscope (Phase Display) ---${NC}"
    get_input_file "Drag STEREO AUDIO file:"
    get_optional_background
    get_output_name
    echo "Choose vectorscope mode:"
    echo "1. Lissajous"
    echo "2. Lissajous XY"
    echo "3. Polar"
    read -p "Select [1-3]: " vec_mode
    case $vec_mode in
        1) v_mode="lissajous" ;;
        2) v_mode="lissajous_xy" ;;
        3) v_mode="polar" ;;
        *) v_mode="lissajous" ;;
    esac
    echo -e "${PURPLE}Creating vectorscope...${NC}"

    local inputs=("-i" "$input_file")
    local bg_filter=""
    local final_chain=""
    local viz_out="[v]"

    if [[ -n "$bg_image" ]]; then
        inputs+=("-loop" "1" "-i" "$bg_image")
        bg_filter="[1:v]scale=1280:720:force_original_aspect_ratio=increase,crop=1280:720[bg];"
        viz_out="[v_raw]"
        final_chain=";[bg][v_raw]blend=all_mode=screen:shortest=1[v]"
    fi

    ffmpeg "${inputs[@]}" -filter_complex \
    "${bg_filter}[0:a]avectorscope=s=1280x720:mode=${v_mode}:draw=line:scale=sqrt:zoom=1.5${viz_out}${final_chain}" \
    -map "[v]" -map 0:a -c:v libx264 -preset fast -crf 18 -c:a copy -shortest "$output_name"
    echo -e "${GREEN}✓ Vectorscope Complete!${NC}"
    pause
}

viz_histogram(){
    echo -e "${CYAN}--- 📉 Audio Histogram ---${NC}"
    get_input_file "Drag AUDIO file:"
    get_optional_background
    get_output_name
    echo -e "${PURPLE}Creating audio histogram...${NC}"

    local inputs=("-i" "$input_file")
    local bg_filter=""
    local final_chain=""
    local viz_out="[v]"

    if [[ -n "$bg_image" ]]; then
        inputs+=("-loop" "1" "-i" "$bg_image")
        bg_filter="[1:v]scale=1280:720:force_original_aspect_ratio=increase,crop=1280:720[bg];"
        viz_out="[v_padded]"
        final_chain=";[bg][v_padded]blend=all_mode=screen:shortest=1[v]"
    else
        viz_out="[v]"
        final_chain=""
    fi

    # Reduced height (400px) and padded to center vertically
    ffmpeg "${inputs[@]}" -filter_complex \
    "${bg_filter}[0:a]ahistogram=s=1280x400:slide=scroll:scale=log:ascale=log:rheight=0.9[hist]; \
     [hist]pad=1280:720:(ow-iw)/2:(oh-ih)/2:black${viz_out}${final_chain}" \
    -map "[v]" -map 0:a -c:v libx264 -preset fast -crf 18 -c:a copy -shortest "$output_name"
    echo -e "${GREEN}✓ Histogram Complete!${NC}"
    pause
}

viz_frequency_bands(){
    echo -e "${CYAN}--- 🎚️ Frequency Bands (EQ Style) ---${NC}"
    get_input_file "Drag AUDIO file:"
    get_optional_background
    get_output_name
    echo "Choose display style:"
    echo "1. Bar graph"
    echo "2. Line graph"
    echo "3. Dot display"
    read -p "Select [1-3]: " freq_style
    case $freq_style in
        1) f_mode="bar" ;;
        2) f_mode="line" ;;
        3) f_mode="dot" ;;
        *) f_mode="bar" ;;
    esac
    echo -e "${PURPLE}Creating frequency band display...${NC}"

    local inputs=("-i" "$input_file")
    local bg_filter=""
    local final_chain=""
    local viz_out="[v]"

    if [[ -n "$bg_image" ]]; then
        inputs+=("-loop" "1" "-i" "$bg_image")
        bg_filter="[1:v]scale=1280:720:force_original_aspect_ratio=increase,crop=1280:720[bg];"
        viz_out="[v_raw]"
        final_chain=";[bg][v_raw]blend=all_mode=screen:shortest=1[v]"
    fi

    ffmpeg "${inputs[@]}" -filter_complex \
    "${bg_filter}[0:a]showfreqs=s=1280x720:mode=${f_mode}:fscale=log:ascale=log:colors=violet|blue|cyan|green|yellow|orange|red:win_size=2048${viz_out}${final_chain}" \
    -map "[v]" -map 0:a -c:v libx264 -preset fast -crf 18 -c:a copy -shortest "$output_name"
    echo -e "${GREEN}✓ Frequency Bands Complete!${NC}"
    pause
}

viz_combo_wave_spectrum(){
    echo -e "${CYAN}--- 📈 Waveform + Spectrum Combo ---${NC}"
    get_input_file "Drag AUDIO file:"
    get_optional_background
    get_output_name
    echo -e "${PURPLE}Creating combo visualization...${NC}"

    local inputs=("-i" "$input_file")
    local bg_filter=""
    local final_chain=""
    local viz_out="[v]"

    if [[ -n "$bg_image" ]]; then
        inputs+=("-loop" "1" "-i" "$bg_image")
        bg_filter="[1:v]scale=1280:720:force_original_aspect_ratio=increase,crop=1280:720[bg];"
        viz_out="[v_raw]"
        final_chain=";[bg][v_raw]blend=all_mode=screen:shortest=1[v]"
    fi

    ffmpeg "${inputs[@]}" -filter_complex \
    "${bg_filter}[0:a]showwaves=s=1280x360:mode=cline:rate=30:colors=cyan[wave]; \
     [0:a]showspectrum=s=1280x360:mode=combined:color=viridis:slide=scroll:scale=sqrt[spec]; \
     [wave][spec]vstack, \
     drawtext=fontcolor=white:fontsize=18:x=10:y=10:text='WAVEFORM':font=mono, \
     drawtext=fontcolor=white:fontsize=18:x=10:y=370:text='SPECTRUM':font=mono${viz_out}${final_chain}" \
    -map "[v]" -map 0:a -c:v libx264 -preset fast -crf 18 -c:a copy -shortest "$output_name"
    echo -e "${GREEN}✓ Combo Display Complete!${NC}"
    pause
}

# ============================================================================
# SPECIAL EFFECTS
# ============================================================================

viz_rainbow_tunnel(){
    echo -e "${CYAN}--- 🌈 Rainbow Tunnel ---${NC}"
    get_input_file "Drag AUDIO file:"
    get_resolution
    get_optional_background
    get_output_name
    echo -e "${PURPLE}Creating rainbow tunnel...${NC}"

    local inputs=("-i" "$input_file")
    local bg_filter=""
    local final_chain=""
    local viz_out="[v]"

    if [[ -n "$bg_image" ]]; then
        inputs+=("-loop" "1" "-i" "$bg_image")
        bg_filter="[1:v]scale=${vid_width}:${vid_height}:force_original_aspect_ratio=increase,crop=${vid_width}:${vid_height}[bg];"
        viz_out="[v_raw]"
        final_chain=";[bg][v_raw]blend=all_mode=screen:shortest=1[v]"
    fi

    # Force mono to fill screen. Start with Red so Hue shift works.
    ffmpeg "${inputs[@]}" -filter_complex \
    "${bg_filter}[0:a]aformat=channel_layouts=mono,showwaves=s=${vid_width}x${vid_height}:mode=cline:rate=30:colors=red[wave]; \
     [wave]hue=h=t*60:s=2, \
     vignette=angle=PI/3:x0=0.5:y0=0.5${viz_out}${final_chain}" \
    -map "[v]" -map 0:a -c:v libx264 -preset fast -crf 18 -c:a copy -shortest "$output_name"
    echo -e "${GREEN}✓ Rainbow Tunnel Complete!${NC}"
    pause
}

viz_reactive_text(){
    echo -e "${CYAN}--- 💜 Reactive Text/Logo (Python/PyGame) ---${NC}"
    
    local py_cmd
    if ! py_cmd=$(get_python_viz_cmd); then
        echo -e "${RED}Error: Python dependencies 'pygame' and 'numpy' are required.${NC}"
        echo -e "${YELLOW}Please run: pip install pygame numpy${NC}"
        pause; return
    fi
    echo -e "${GREEN}Using Python: $py_cmd${NC}"

    get_input_file "Drag AUDIO file:"
    
    echo -e "${YELLOW}Enter Text to display OR drag an Image file (Logo):${NC}"
    read -r -p "> " text_or_image
    
    # Remove quotes if user dragged a file (Double and Single)
    text_or_image="${text_or_image%\"}"
    text_or_image="${text_or_image#\"}"
    text_or_image="${text_or_image%\'}"
    text_or_image="${text_or_image#\'}"
    
    # Handle tilde expansion
    if [[ "$text_or_image" == "~"* ]]; then
        text_or_image="${HOME}${text_or_image:1}"
    fi
    
    # Trim whitespace (safe method)
    text_or_image="$(echo "${text_or_image}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    
    local viz_args=("--mode" "text")
    
    if [[ -f "$text_or_image" ]]; then
        echo -e "${GREEN}Detected Image File.${NC}"
        viz_args+=("--image" "$text_or_image")
    else
        if [[ -z "$text_or_image" ]]; then
            text_or_image="MUSIC"
        fi
        echo -e "${GREEN}Using Text: $text_or_image${NC}"
        viz_args+=("--text" "$text_or_image")
    fi

    get_resolution
    get_output_name
    echo -e "${PURPLE}Rendering reactive text/logo...${NC}"
    
    ffmpeg -i "$input_file" -f s16le -ac 1 -ar 44100 -vn - | \
    "$py_cmd" "$(dirname "$0")/viz_master.py" "${viz_args[@]}" --width "$vid_width" --height "$vid_height" | \
    ffmpeg -y -f rawvideo -pixel_format rgb24 -video_size "${vid_width}x${vid_height}" -framerate 30 -thread_queue_size 1024 -i - \
    -i "$input_file" -map 0:v -map 1:a -c:v libx264 -preset fast -crf 18 -c:a copy -shortest "$output_name"
    echo -e "${GREEN}✓ Reactive Text/Logo Complete!${NC}"
    pause
}

viz_fire_realistic(){
    echo -e "${CYAN}--- 🔥 Realistic Fire (Python/PyGame) ---${NC}"
    local py_cmd
    if ! py_cmd=$(get_python_viz_cmd); then
        echo -e "${RED}Error: Python dependencies 'pygame' and 'numpy' are required.${NC}"
        echo -e "${YELLOW}Please run: pip install pygame numpy${NC}"
        pause; return
    fi
    echo -e "${GREEN}Using Python: $py_cmd${NC}"

    get_input_file "Drag AUDIO file:"
    get_resolution
    get_output_name
    echo -e "${PURPLE}Rendering realistic fire...${NC}"
    
    ffmpeg -i "$input_file" -f s16le -ac 1 -ar 44100 -vn - | \
    "$py_cmd" "$(dirname "$0")/viz_master.py" --mode fire --width "$vid_width" --height "$vid_height" | \
    ffmpeg -y -f rawvideo -pixel_format rgb24 -video_size "${vid_width}x${vid_height}" -framerate 30 -thread_queue_size 1024 -i - \
    -i "$input_file" -map 0:v -map 1:a -c:v libx264 -preset fast -crf 18 -c:a copy -shortest "$output_name"
    echo -e "${GREEN}✓ Realistic Fire Complete!${NC}"
    pause
}

viz_cube_tunnel(){
    echo -e "${CYAN}--- 🔲 Cube Tunnel (3D) ---${NC}"
    get_input_file "Drag AUDIO file:"
    get_optional_background
    get_output_name
    echo -e "${PURPLE}Creating cube tunnel...${NC}"

    local inputs=("-i" "$input_file")
    local bg_filter=""
    local final_chain=""
    local viz_out="[v]"

    if [[ -n "$bg_image" ]]; then
        inputs+=("-loop" "1" "-i" "$bg_image")
        bg_filter="[1:v]scale=1280:720:force_original_aspect_ratio=increase,crop=1280:720[bg];"
        viz_out="[v_raw]"
        final_chain=";[bg][v_raw]blend=all_mode=screen:shortest=1[v]"
    fi

    ffmpeg "${inputs[@]}" -filter_complex \
    "${bg_filter}[0:a]showwaves=s=1280x720:mode=cline:rate=30:colors=cyan|magenta[wave]; \
     [wave]drawgrid=width=160:height=144:thickness=2:color=white@0.5, \
     perspective=x0=200:y0=100:x1=1080:y1=100:x2=0:y2=720:x3=1280:y3=720:sense=destination, \
     hue=h=t*20${viz_out}${final_chain}" \
    -map "[v]" -map 0:a -c:v libx264 -preset fast -crf 18 -c:a copy -shortest "$output_name"
    echo -e "${GREEN}✓ Cube Tunnel Complete!${NC}"
    pause
}

viz_circus_lights(){
    echo -e "${CYAN}--- 🎪 Circus Lights ---${NC}"
    get_input_file "Drag AUDIO file:"
    get_resolution
    get_optional_background
    get_output_name
    echo -e "${PURPLE}Creating circus light show...${NC}"

    local inputs=("-i" "$input_file")
    local bg_filter=""
    local final_chain=""
    local viz_out="[v]"

    if [[ -n "$bg_image" ]]; then
        inputs+=("-loop" "1" "-i" "$bg_image")
        bg_filter="[1:v]scale=${vid_width}:${vid_height}:force_original_aspect_ratio=increase,crop=${vid_width}:${vid_height}[bg];"
        viz_out="[v_raw]"
        final_chain=";[bg][v_raw]blend=all_mode=screen:shortest=1[v]"
    fi

    ffmpeg "${inputs[@]}" -filter_complex \
    "${bg_filter}[0:a]showspectrum=s=${vid_width}x${vid_height}:mode=combined:color=rainbow:slide=replace:scale=sqrt:saturation=3[spec]; \
     [spec]hue=h=t*50:s=2, \
     eq=contrast=1.3:saturation=1.5${viz_out}${final_chain}" \
    -map "[v]" -map 0:a -c:v libx264 -preset fast -crf 18 -c:a copy -shortest "$output_name"
    echo -e "${GREEN}✓ Circus Lights Complete!${NC}"
    pause
}

viz_circular_waves_v2(){
    echo -e "${CYAN}--- ⭕ Circular Waves v2 ---${NC}"
    get_input_file "Drag AUDIO file:"
    get_resolution
    get_waveform_color
    get_optional_background
    get_output_name
    echo -e "${PURPLE}Creating circular waveform...${NC}"

    local inputs=("-i" "$input_file")
    local bg_filter=""
    local final_chain=""
    local viz_out="[v]"

    if [[ -n "$bg_image" ]]; then
        inputs+=("-loop" "1" "-i" "$bg_image")
        bg_filter="[1:v]scale=${vid_width}:${vid_height}:force_original_aspect_ratio=increase,crop=${vid_width}:${vid_height}[bg];"
        viz_out="[v_raw]"
        final_chain=";[bg][v_raw]overlay=(W-w)/2:(H-h)/2:shortest=1[v]"
    fi

    # Using the geq filter math provided by the user to wrap the waveform into a circle
    ffmpeg "${inputs[@]}" -filter_complex \
    "${bg_filter}[0:a]aformat=channel_layouts=mono,showwaves=s=${vid_width}x${vid_height}:mode=cline:colors=${wave_color}:draw=full, \
     geq='p(mod(W/PI*(PI+atan2(H/2-Y,X-W/2)),W), H-2*hypot(H/2-Y,X-W/2))':a='alpha(mod(W/PI*(PI+atan2(H/2-Y,X-W/2)),W), H-2*hypot(H/2-Y,X-W/2))'${viz_out}${final_chain}" \
    -map "[v]" -map 0:a -c:v libx264 -preset fast -crf 18 -c:a copy -shortest "$output_name"
    echo -e "${GREEN}✓ Circular Waves v2 Complete!${NC}"
    pause
}

viz_lava_lamp(){
    echo -e "${CYAN}--- 🌋 Lava Lamp (Python/PyGame) ---${NC}"
    
    local py_cmd
    if ! py_cmd=$(get_python_viz_cmd); then
        echo -e "${RED}Error: Python dependencies 'pygame' and 'numpy' are required.${NC}"
        echo -e "${YELLOW}Please run: pip install pygame numpy${NC}"
        echo -e "${RED}Debug Info: Could not find a python interpreter with these modules.${NC}"
        echo "Checked: python3, python, and standard conda paths."
        pause
        return
    fi
    echo -e "${GREEN}Using Python: $py_cmd${NC}"

    get_input_file "Drag AUDIO file:"
    get_resolution
    get_output_name
    echo -e "${PURPLE}Rendering lava lamp visualization...${NC}"

    # Pipeline:
    # 1. ffmpeg decodes audio to raw PCM (16-bit, 44.1kHz, Mono) -> Pipe
    # 2. python script reads PCM, generates frames -> Pipe
    # 3. ffmpeg reads raw video frames, muxes with original audio -> Output file
    
    ffmpeg -i "$input_file" -f s16le -ac 1 -ar 44100 -vn - | \
    "$py_cmd" "$(dirname "$0")/viz_master.py" --mode lava --width "$vid_width" --height "$vid_height" | \
    ffmpeg -y -f rawvideo -pixel_format rgb24 -video_size "${vid_width}x${vid_height}" -framerate 30 -thread_queue_size 1024 -i - \
    -i "$input_file" -map 0:v -map 1:a -c:v libx264 -preset fast -crf 18 -c:a copy -shortest "$output_name"

    echo -e "${GREEN}✓ Lava Lamp Complete!${NC}"
    pause
}

viz_bars_smooth(){
    echo -e "${CYAN}--- 📊 Smooth Bars (Python/PyGame) ---${NC}"
    local py_cmd
    if ! py_cmd=$(get_python_viz_cmd); then
        echo -e "${RED}Error: Python dependencies 'pygame' and 'numpy' are required.${NC}"
        echo -e "${YELLOW}Please run: pip install pygame numpy${NC}"
        pause; return
    fi
    echo -e "${GREEN}Using Python: $py_cmd${NC}"

    get_input_file "Drag AUDIO file:"
    get_resolution
    get_output_name
    echo -e "${PURPLE}Rendering smooth bars...${NC}"
    
    ffmpeg -i "$input_file" -f s16le -ac 1 -ar 44100 -vn - | \
    "$py_cmd" "$(dirname "$0")/viz_master.py" --mode bars --width "$vid_width" --height "$vid_height" | \
    ffmpeg -y -f rawvideo -pixel_format rgb24 -video_size "${vid_width}x${vid_height}" -framerate 30 -thread_queue_size 1024 -i - \
    -i "$input_file" -map 0:v -map 1:a -c:v libx264 -preset fast -crf 18 -c:a copy -shortest "$output_name"
    echo -e "${GREEN}✓ Smooth Bars Complete!${NC}"
    pause
}

viz_wave_stabilized(){
    echo -e "${CYAN}--- 〰️ Stabilized Waveform (Python/PyGame) ---${NC}"
    local py_cmd
    if ! py_cmd=$(get_python_viz_cmd); then
        echo -e "${RED}Error: Python dependencies 'pygame' and 'numpy' are required.${NC}"
        echo -e "${YELLOW}Please run: pip install pygame numpy${NC}"
        pause; return
    fi
    echo -e "${GREEN}Using Python: $py_cmd${NC}"

    get_input_file "Drag AUDIO file:"
    get_resolution
    get_output_name
    echo -e "${PURPLE}Rendering stabilized waveform...${NC}"
    
    ffmpeg -i "$input_file" -f s16le -ac 1 -ar 44100 -vn - | \
    "$py_cmd" "$(dirname "$0")/viz_master.py" --mode wave --width "$vid_width" --height "$vid_height" | \
    ffmpeg -y -f rawvideo -pixel_format rgb24 -video_size "${vid_width}x${vid_height}" -framerate 30 -thread_queue_size 1024 -i - \
    -i "$input_file" -map 0:v -map 1:a -c:v libx264 -preset fast -crf 18 -c:a copy -shortest "$output_name"
    echo -e "${GREEN}✓ Stabilized Waveform Complete!${NC}"
    pause
}

viz_particles_reactive(){
    echo -e "${CYAN}--- ✨ Reactive Particles (Python/PyGame) ---${NC}"
    local py_cmd
    if ! py_cmd=$(get_python_viz_cmd); then
        echo -e "${RED}Error: Python dependencies 'pygame' and 'numpy' are required.${NC}"
        echo -e "${YELLOW}Please run: pip install pygame numpy${NC}"
        pause; return
    fi
    echo -e "${GREEN}Using Python: $py_cmd${NC}"

    get_input_file "Drag AUDIO file:"
    get_resolution
    
    echo -e "${YELLOW}Select Color Palette:${NC}"
    echo "1) White (Default)"
    echo "2) Fire (Red/Orange)"
    echo "3) Ice (Blue/Cyan)"
    echo "4) Neon (Pink/Cyan/Yellow)"
    echo "5) Matrix (Green)"
    read -p "Select [1-5]: " c_choice
    local color_arg="white"
    case $c_choice in
        2) color_arg="fire" ;;
        3) color_arg="ice" ;;
        4) color_arg="neon" ;;
        5) color_arg="matrix" ;;
        *) color_arg="white" ;;
    esac
    
    get_output_name
    echo -e "${PURPLE}Rendering particles ($color_arg)...${NC}"
    
    ffmpeg -i "$input_file" -f s16le -ac 1 -ar 44100 -vn - | \
    "$py_cmd" "$(dirname "$0")/viz_master.py" --mode particles --width "$vid_width" --height "$vid_height" --color "$color_arg" | \
    ffmpeg -y -f rawvideo -pixel_format rgb24 -video_size "${vid_width}x${vid_height}" -framerate 30 -thread_queue_size 1024 -i - \
    -i "$input_file" -map 0:v -map 1:a -c:v libx264 -preset fast -crf 18 -c:a copy -shortest "$output_name"
    echo -e "${GREEN}✓ Reactive Particles Complete!${NC}"
    pause
}

viz_spectrum_radial(){
    echo -e "${CYAN}--- 🌀 Radial Spectrum (Python/PyGame) ---${NC}"
    local py_cmd
    if ! py_cmd=$(get_python_viz_cmd); then
        echo -e "${RED}Error: Python dependencies 'pygame' and 'numpy' are required.${NC}"
        echo -e "${YELLOW}Please run: pip install pygame numpy${NC}"
        pause; return
    fi
    echo -e "${GREEN}Using Python: $py_cmd${NC}"

    get_input_file "Drag AUDIO file:"
    get_resolution
    
    echo -e "${YELLOW}Select Color Palette:${NC}"
    echo "1) Rainbow (Default)"
    echo "2) Fire (Red/Orange)"
    echo "3) Ice (Blue/Cyan)"
    echo "4) Matrix (Green)"
    read -p "Select [1-4]: " c_choice
    local color_arg="rainbow"
    case $c_choice in
        2) color_arg="fire" ;;
        3) color_arg="ice" ;;
        4) color_arg="matrix" ;;
        *) color_arg="rainbow" ;;
    esac
    
    local img_arg=""
    read -p "Optional: Drag an IMAGE for the center [Enter to skip]: " img_path
    img_path=$(clean_path_input "$img_path")
    if [[ -n "$img_path" && -f "$img_path" ]]; then
        img_arg="--image \"$img_path\""
    fi

    local logo_arg=""
    read -p "Optional: Drag a LOGO/OVERLAY image [Enter to skip]: " logo_path
    logo_path=$(clean_path_input "$logo_path")
    if [[ -n "$logo_path" && -f "$logo_path" ]]; then
        logo_arg="--logo \"$logo_path\""
        
        echo "Logo Size:"
        echo "1) Small (20%)"
        echo "2) Medium (40%)"
        echo "3) Large (60%)"
        echo "4) Extra Large (80%)"
        read -p "Select [1-4]: " l_size
        case $l_size in
            1) logo_arg="$logo_arg --logo_scale 0.2" ;;
            2) logo_arg="$logo_arg --logo_scale 0.4" ;;
            3) logo_arg="$logo_arg --logo_scale 0.6" ;;
            4) logo_arg="$logo_arg --logo_scale 0.8" ;;
            *) logo_arg="$logo_arg --logo_scale 0.4" ;;
        esac

        echo "Logo Layering:"
        echo "1) In Front of Waveform (Default)"
        echo "2) Behind Waveform"
        read -p "Select [1-2]: " l_layer
        if [[ "$l_layer" == "2" ]]; then
            logo_arg="$logo_arg --logo_layer back"
        else
            logo_arg="$logo_arg --logo_layer front"
        fi
    fi

    get_output_name
    echo -e "${PURPLE}Rendering radial spectrum ($color_arg)...${NC}"
    
    # Construct command carefully to handle quotes
    local cmd_str="$py_cmd \"$(dirname "$0")/viz_master.py\" --mode radial --width \"$vid_width\" --height \"$vid_height\" --color \"$color_arg\""
    if [[ -n "$img_path" ]]; then
        cmd_str="$cmd_str --image \"$img_path\""
    fi
    if [[ -n "$logo_path" ]]; then
        cmd_str="$cmd_str $logo_arg"
    fi

    ffmpeg -i "$input_file" -f s16le -ac 1 -ar 44100 -vn - | \
    eval "$cmd_str" | \
    ffmpeg -y -f rawvideo -pixel_format rgb24 -video_size "${vid_width}x${vid_height}" -framerate 30 -thread_queue_size 1024 -i - \
    -i "$input_file" -map 0:v -map 1:a -c:v libx264 -preset fast -crf 18 -c:a copy -shortest "$output_name"
    echo -e "${GREEN}✓ Radial Spectrum Complete!${NC}"
    pause
}

viz_terrain_3d(){
    echo -e "${CYAN}--- 🏔️ 3D Terrain (Python/PyGame) ---${NC}"
    local py_cmd
    if ! py_cmd=$(get_python_viz_cmd); then
        echo -e "${RED}Error: Python dependencies 'pygame' and 'numpy' are required.${NC}"
        echo -e "${YELLOW}Please run: pip install pygame numpy${NC}"
        pause; return
    fi
    echo -e "${GREEN}Using Python: $py_cmd${NC}"

    get_input_file "Drag AUDIO file:"
    get_resolution
    
    echo -e "${YELLOW}Select Color Theme:${NC}"
    echo "1) Cyan (Default)"
    echo "2) Magenta"
    echo "3) Green"
    echo "4) Red"
    echo "5) White"
    read -p "Select [1-5]: " c_choice
    local color_arg="cyan"
    case $c_choice in
        2) color_arg="magenta" ;;
        3) color_arg="green" ;;
        4) color_arg="red" ;;
        5) color_arg="white" ;;
        *) color_arg="cyan" ;;
    esac
    
    get_output_name
    echo -e "${PURPLE}Rendering 3D terrain ($color_arg)...${NC}"
    
    ffmpeg -i "$input_file" -f s16le -ac 1 -ar 44100 -vn - | \
    "$py_cmd" "$(dirname "$0")/viz_master.py" --mode terrain --width "$vid_width" --height "$vid_height" --color "$color_arg" | \
    ffmpeg -y -f rawvideo -pixel_format rgb24 -video_size "${vid_width}x${vid_height}" -framerate 30 -thread_queue_size 1024 -i - \
    -i "$input_file" -map 0:v -map 1:a -c:v libx264 -preset fast -crf 18 -c:a copy -shortest "$output_name"
    echo -e "${GREEN}✓ 3D Terrain Complete!${NC}"
    pause
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
# MODULE 4: Audio Lab (Convert, Normalize, Creative FX)
# ==============================================================================
menu_audio_tools(){
    while true; do
        clear
        echo -e "${PURPLE}--- Audio Lab ---${NC}"
        echo "1. Convert / Transcode Audio"
        echo "2. Loudness Normalize (-14 LUFS)"
        echo "3. Vocal Cut (Instrumental Maker)"
        echo "4. Stream Info (JSON)"
        echo "5. Detect Silence/Black Frames"
        echo "6. DistroKid/Streaming Validator (WAV Check)"
        echo "7. Mastering Report (LUFS/TP/LRA/Phase, Ref/Plot/Xray)"
        echo "8. Return"
        echo
        read -p "Select: " audio_choice
        case $audio_choice in
            1)
                get_input_file "Drag SOURCE audio:"
                read -p "Target format [wav/mp3/flac/aac]: " target_fmt
                target_fmt=$(echo "${target_fmt:-wav}" | tr '[:upper:]' '[:lower:]')
                local codec_args new_ext base_name
                case $target_fmt in
                    mp3)
                        codec_args=(-c:a libmp3lame -b:a 320k)
                        new_ext="mp3"
                        ;;
                    flac)
                        codec_args=(-c:a flac)
                        new_ext="flac"
                        ;;
                    aac)
                        codec_args=(-c:a aac -b:a 256k)
                        new_ext="m4a"
                        ;;
                    wav)
                        codec_args=(-c:a pcm_s24le)
                        new_ext="wav"
                        ;;
                    *)
                        codec_args=(-c:a copy)
                        new_ext="${target_fmt:-converted}"
                        ;;
                esac
                get_output_name "$new_ext"
                if [[ -z "$output_name" ]]; then
                    base_name="$(basename "${input_file%.*}")"
                    output_name="$(dirname "$input_file")/${base_name}.${new_ext}"
                fi
                if ffmpeg -i "$input_file" "${codec_args[@]}" "$output_name"; then
                    echo -e "${GREEN}Converted audio saved to $output_name${NC}"
                else
                    echo -e "${RED}ffmpeg conversion failed.${NC}"
                fi
                pause
                ;;
            2)
                get_input_file "Drag AUDIO to normalize:"
                read -p "Target LUFS [-14]: " target_lufs
                [[ -z "$target_lufs" ]] && target_lufs="-14"
                get_output_name wav
                if [[ -z "$output_name" ]]; then
                    base_name="$(basename "${input_file%.*}")"
                    output_name="$(dirname "$input_file")/${base_name}_LN.wav"
                fi
                if ffmpeg -i "$input_file" -af "loudnorm=I=${target_lufs}:TP=-1.0:LRA=11" -c:a pcm_s24le "$output_name"; then
                    echo -e "${GREEN}Loudness-normalized master saved to $output_name${NC}"
                else
                    echo -e "${RED}Normalization failed.${NC}"
                fi
                pause
                ;;
            3)
                get_input_file "Drag STEREO audio (creates instrumental):"
                get_output_name wav
                if [[ -z "$output_name" ]]; then
                    base_name="$(basename "${input_file%.*}")"
                    output_name="$(dirname "$input_file")/${base_name}_instrumental.wav"
                fi
                if ffmpeg -i "$input_file" -af "pan=stereo|c0=.5*(c0-c1)|c1=.5*(c0-c1)" -c:a pcm_s24le "$output_name"; then
                    echo -e "${GREEN}Instrumental stem saved to $output_name${NC}"
                else
                    echo -e "${RED}Center-cut processing failed.${NC}"
                fi
                pause
                ;;
            4)
                get_input_file
                echo -e "${YELLOW}TIP: Press 'q' to return once you're done viewing the report.${NC}"
                ffprobe -loglevel quiet -show_format -show_streams -i "$input_file" -print_format json | less
                ;;
            5)
                get_input_file
                echo "Scanning silence > 2s..."
                ffmpeg -i "$input_file" -af "silencedetect=noise=-50dB:d=2" -f null - 2>&1 | grep "silence_start"
                pause
                ;;
            6)
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
            7)
                echo "Run Mastering Report (LUFS/TP/LRA/Phase + 8-band + ref compare)."
                echo "MP3 allowed (slightly less accurate than WAV)."
                echo "Choose source:"
                echo "  1) Single WAV/MP3 file"
                echo "  2) Folder of WAV/MP3 files"
                read -p "Select [1-2]: " mr_choice

                # Prefer configured report output if set
                report_dir=$(python3 - <<'PY'
import json, os
cfg_path = os.path.expanduser('~/.freeed_media_super_tool/config.json')
report = ''
if os.path.exists(cfg_path):
    try:
        with open(cfg_path) as f:
            data = json.load(f)
        report = data.get('user', {}).get('report_output_folder', '')
    except Exception:
        report = ''
print(report)
PY
)

                read -p "Platform preset [spotify/youtube/apple/cd/vinyl/custom, default spotify]: " platform_choice
                platform_choice=${platform_choice:-spotify}

                extra_args=("--platform" "$platform_choice")
                if [[ "$platform_choice" == "custom" ]]; then
                    read -p "Target LUFS (e.g. -14): " custom_lufs
                    read -p "Target True Peak dBTP (e.g. -1.0): " custom_tp
                    [[ -n "$custom_lufs" ]] && extra_args+=("--target-lufs" "$custom_lufs")
                    [[ -n "$custom_tp" ]] && extra_args+=("--target-tp" "$custom_tp")
                fi

                read -p "Optional reference file (Enter to skip): " ref_file
                if [[ -n "$ref_file" && -f "$ref_file" ]]; then
                    extra_args+=("--ref" "$ref_file")
                fi

                read -p "Save PNG spectrum plot? (y/N): " want_plot
                [[ "$want_plot" =~ ^[Yy]$ ]] && extra_args+=("--plot")

                read -p "Export Mid/Side diagnostic WAVs? (y/N): " want_xray
                [[ "$want_xray" =~ ^[Yy]$ ]] && extra_args+=("--xray")

                read -p "Auto-master to target (experimental)? (y/N): " want_master
                [[ "$want_master" =~ ^[Yy]$ ]] && extra_args+=("--master")

                if [[ "$mr_choice" == "1" ]]; then
                    get_input_file "Drag WAV/MP3 File:"
                    if [[ -n "$report_dir" ]]; then
                        python3 ""$SCRIPT_DIR"/ardour_fixer.py" --file "$input_file" --out "$report_dir" "${extra_args[@]}"
                    else
                        python3 ""$SCRIPT_DIR"/ardour_fixer.py" --file "$input_file" "${extra_args[@]}"
                    fi
                else
                    read -p "Directory to analyze (Enter for default): " analysis_dir
                    if [[ -z "$analysis_dir" ]]; then
                        if [[ -n "$report_dir" ]]; then
                            python3 ""$SCRIPT_DIR"/ardour_fixer.py" --out "$report_dir" "${extra_args[@]}"
                        else
                            python3 ""$SCRIPT_DIR"/ardour_fixer.py" "${extra_args[@]}"
                        fi
                    else
                        if [[ -n "$report_dir" ]]; then
                            python3 ""$SCRIPT_DIR"/ardour_fixer.py" "$analysis_dir" --out "$report_dir" "${extra_args[@]}"
                        else
                            python3 ""$SCRIPT_DIR"/ardour_fixer.py" "$analysis_dir" "${extra_args[@]}"
                        fi
                    fi
                fi
                pause
                ;;
            8)
                return
                ;;
            *)
                echo -e "${RED}Invalid selection.${NC}"
                sleep 1
                ;;
        esac
    done
}

# NOTE: `menu_social_batch` (defined earlier) replaces the older social helpers.
# The new batch menu supports choosing any combination of the five platforms
# (TikTok, YouTube, X, Instagram, Facebook/META) and runs them in parallel.

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
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Script is running directly (not sourced) -> run interactive main loop
    check_dependencies
    load_api_keys_from_config
    while true; do
    clear
    echo
    echo -e "${PURPLE}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║                                                      ║${NC}"
    echo -e "${PURPLE}║${NC}           ${CYAN}F R E E   E D   4   M E D${NC}                  ${PURPLE}║${NC}"
    echo -e "${PURPLE}║${NC}              ${GREEN}Music for Healing${NC}                       ${PURPLE}║${NC}"
    echo -e "${PURPLE}║                                                      ║${NC}"
    echo -e "${PURPLE}╠══════════════════════════════════════════════════════╣${NC}"
    echo -e "${PURPLE}║${NC}               ${YELLOW}MEDIA SUPERTOOL${NC}                        ${PURPLE}║${NC}"
    echo -e "${PURPLE}║${NC}                   v5.0.0                             ${PURPLE}║${NC}"
    echo -e "${PURPLE}║${NC}            ✨ Enhanced by AI ✨                      ${PURPLE}║${NC}"
    echo -e "${PURPLE}╚══════════════════════════════════════════════════════╝${NC}"
    echo
    echo "  1. 🎬 Creation Module (Lyrics, AI Whisper, Loop)"
    echo "  2. 🎨 Visualizer Lab (Color Picker, Circular)"
    echo "  3. 🎧 Audio Lab (Convert, Normalize, Diagnostics)"
    echo "  4. 🎼 Notation Studio (AI Transcription)"
    echo "  5. 🏷️  Branding & Metadata (Smart Logo, Tags)"
    echo "  6. 📱 Social Media Tools (Batch, Captions, Post)"
    echo "  7. ⚙️  Settings"
    echo "  8. ⚖️  Legal & Info"
    echo "  0. 🚪 Exit"
    echo
    read -p "  Enter choice [0-8]: " main_choice
    case $main_choice in
        1) menu_standard_video ;;
        2) menu_visualizers ;;
        3) menu_audio_tools ;;
        4) menu_notation_studio ;;
        5) menu_branding ;;
        6) menu_social_tools ;;
        7) menu_settings ;;
        8) menu_legal ;;
        0) echo "Exiting..."; exit 0 ;;
        *) echo -e "${RED}Invalid selection.${NC}"; sleep 1 ;;
    esac
    done
fi
