#!/bin/bash

NODE_DIR="/home/container/node"
BUN_DIR="/usr/local/bun"
GO_DIR="/usr/local/go"

export HOME="/home/container"
export PLAYWRIGHT_BROWSERS_PATH="/usr/local/share/playwright"

mkdir -p "$NODE_DIR"
export PATH="$NODE_DIR/bin:$BUN_DIR/bin:$GO_DIR/bin:$PATH"

cat > /home/container/.bashrc <<EOF
export PATH="$NODE_DIR/bin:$BUN_DIR/bin:$GO_DIR/bin:\$PATH"
export NODE_PATH="$NODE_DIR/lib/node_modules"
export PLAYWRIGHT_BROWSERS_PATH="$PLAYWRIGHT_BROWSERS_PATH"
EOF

# =========================
# ANSI COLORS
# =========================
RESET="\033[0m"
BOLD="\033[1m"
CYAN="\033[1;36m"
BLUE="\033[1;34m"
GREEN="\033[1;32m"
YELLOW="\033[1;33m"
RED="\033[1;31m"
PURPLE="\033[1;35m"
WHITE="\033[1;37m"
GRAY="\033[0;37m"

loading() {
    local message="${1:-Loading}"
    local duration="${2:-2}"
    local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    local start=$SECONDS
    local i=0

    while (( SECONDS - start < duration )); do
        printf "\r${CYAN}%s${RESET} ${WHITE}%s${RESET}" "${frames[$i]}" "$message"
        i=$(( (i + 1) % ${#frames[@]} ))
        sleep 0.08
    done

    printf "\r${GREEN}✓${RESET} ${WHITE}%s${RESET}\n" "$message"
}

# ==========================================================
# Node.js runtime
# ==========================================================
if [ -n "${NODE_VERSION}" ]; then
    if [ -x "$NODE_DIR/bin/node" ]; then
        CURRENT_VER="$("$NODE_DIR/bin/node" -v 2>/dev/null || true)"
    else
        CURRENT_VER="none"
    fi

    TARGET_VER="$(curl -fsSL https://nodejs.org/dist/index.json 2>/dev/null | jq -r --arg prefix "v${NODE_VERSION}" '.[] | select(.version | startswith($prefix)) | .version' | head -n 1)"

    if [ -z "$TARGET_VER" ] || [ "$TARGET_VER" = "null" ]; then
        if [[ "${NODE_VERSION}" == v* ]]; then
            TARGET_VER="${NODE_VERSION}"
        else
            TARGET_VER="v${NODE_VERSION}.0.0"
        fi
    fi

    if [ "$CURRENT_VER" != "$TARGET_VER" ]; then
        echo -e "${BLUE}[Runtime]${RESET} Installing Node.js ${WHITE}$TARGET_VER${RESET} ..."
        rm -rf "$NODE_DIR"/*
        cd /tmp || exit 1

        if curl -fL "https://nodejs.org/dist/${TARGET_VER}/node-${TARGET_VER}-linux-x64.tar.gz" -o node.tar.gz; then
            tar -xf node.tar.gz --strip-components=1 -C "$NODE_DIR"
            rm -f node.tar.gz
            "$NODE_DIR/bin/npm" install -g pm2 pnpm yarn playwright nodemon --loglevel=error || true
        else
            echo -e "${RED}[Runtime]${RESET} Failed to download Node.js $TARGET_VER."
        fi

        cd /home/container || exit 1
    fi
fi

# ==========================================================
# GitHub auto update on every Pterodactyl start/restart
# ==========================================================
cd /home/container || exit 1
git config --global --add safe.directory /home/container >/dev/null 2>&1 || true

echo -e "${CYAN}╔════════════════════════════════════════════════════╗${RESET}"
echo -e "${CYAN}║${WHITE}                GITHUB AUTO UPDATE                  ${CYAN}║${RESET}"
echo -e "${CYAN}╠════════════════════════════════════════════════════╣${RESET}"

if [ "${AUTO_UPDATE:-1}" = "1" ]; then
    BRANCH_NAME="${BRANCH:-main}"

    # Auto-bootstrap .git jika belum ada dan GIT_ADDRESS tersedia.
    if [ ! -d "/home/container/.git" ] && [ -n "${GIT_ADDRESS}" ]; then
        echo -e "${CYAN}║${RESET} ${PURPLE}⚙${RESET} .git belum ada, membuat repository..."

        GIT_URL="${GIT_ADDRESS}"
        case "$GIT_URL" in
            *.git) ;;
            *) GIT_URL="${GIT_URL}.git" ;;
        esac

        if [ -n "${USERNAME}" ] && [ -n "${ACCESS_TOKEN}" ]; then
            REPO_PATH="$(echo "$GIT_URL" | sed -E 's#^https?://##')"
            GIT_URL="https://${USERNAME}:${ACCESS_TOKEN}@${REPO_PATH}"
        fi

        git init >/dev/null 2>&1 || true

        if git remote get-url origin >/dev/null 2>&1; then
            git remote set-url origin "$GIT_URL"
        else
            git remote add origin "$GIT_URL"
        fi

        if git fetch --force --prune origin "$BRANCH_NAME"; then
            git checkout -B "$BRANCH_NAME" "origin/$BRANCH_NAME" --force >/dev/null 2>&1 || true
            git reset --hard "origin/$BRANCH_NAME" >/dev/null 2>&1 || true
            echo -e "${CYAN}║${RESET} ${GREEN}✓${RESET} .git berhasil dibuat dan disinkronkan."
        else
            echo -e "${CYAN}║${RESET} ${RED}✗${RESET} Gagal membuat/sinkronisasi .git."
        fi
    fi

    if [ -d "/home/container/.git" ]; then
        OLD_COMMIT="$(git rev-parse --short HEAD 2>/dev/null || echo UNKNOWN)"
        BEFORE_DEPS="$(cat package.json package-lock.json pnpm-lock.yaml yarn.lock 2>/dev/null | sha256sum | awk '{print $1}')"

        echo -e "${CYAN}║${RESET} ${GREEN}●${RESET} Auto Update : ${GREEN}ENABLED${RESET}"
        echo -e "${CYAN}║${RESET} ${BLUE}↻${RESET} Branch      : ${WHITE}$BRANCH_NAME${RESET}"
        echo -e "${CYAN}║${RESET} ${YELLOW}◆${RESET} Commit Lama : ${YELLOW}$OLD_COMMIT${RESET}"
        echo -e "${CYAN}║${RESET} ${BLUE}↻${RESET} Fetching origin/$BRANCH_NAME ..."

        rm -f .git/index.lock

        if git fetch --force --prune origin "$BRANCH_NAME"; then
            if git reset --hard "origin/$BRANCH_NAME"; then
                NEW_COMMIT="$(git rev-parse --short HEAD 2>/dev/null || echo UNKNOWN)"
                AFTER_DEPS="$(cat package.json package-lock.json pnpm-lock.yaml yarn.lock 2>/dev/null | sha256sum | awk '{print $1}')"

                if [ "$OLD_COMMIT" = "$NEW_COMMIT" ]; then
                    echo -e "${CYAN}║${RESET} ${GREEN}✓${RESET} Status      : ${GREEN}UP TO DATE${RESET} ${GRAY}($NEW_COMMIT)${RESET}"
                else
                    echo -e "${CYAN}║${RESET} ${GREEN}✓${RESET} Status      : ${GREEN}UPDATED SUCCESSFULLY${RESET}"
                    echo -e "${CYAN}║${RESET}   ${GRAY}$OLD_COMMIT${RESET} ${WHITE}→${RESET} ${GREEN}$NEW_COMMIT${RESET}"
                fi

                if [ "${AUTO_INSTALL_DEPS:-1}" = "1" ] && [ -f package.json ] && { [ ! -d node_modules ] || [ "$BEFORE_DEPS" != "$AFTER_DEPS" ]; }; then
                    echo -e "${CYAN}║${RESET} ${PURPLE}⚙${RESET} Dependencies changed, installing..."
                    if [ -f pnpm-lock.yaml ] && command -v pnpm >/dev/null 2>&1; then
                        pnpm install || echo -e "${CYAN}║${RESET} ${RED}✗ pnpm install gagal${RESET}"
                    elif [ -f yarn.lock ] && command -v yarn >/dev/null 2>&1; then
                        yarn install || echo -e "${CYAN}║${RESET} ${RED}✗ yarn install gagal${RESET}"
                    else
                        npm install || echo -e "${CYAN}║${RESET} ${RED}✗ npm install gagal${RESET}"
                    fi
                fi
            else
                echo -e "${CYAN}║${RESET} ${RED}✗ git reset gagal${RESET}"
            fi
        else
            echo -e "${CYAN}║${RESET} ${RED}✗ git fetch gagal. File lokal tetap digunakan.${RESET}"
        fi
    else
        echo -e "${CYAN}║${RESET} ${YELLOW}! .git tidak ditemukan di /home/container${RESET}"
        echo -e "${CYAN}║${RESET} ${GRAY}  Auto update dilewati.${RESET}"
    fi
else
    echo -e "${CYAN}║${RESET} ${RED}● Auto Update : DISABLED${RESET}"
fi

echo -e "${CYAN}╚════════════════════════════════════════════════════╝${RESET}"

# ==========================================================
# Cloudflare Tunnel
# ==========================================================
CF_STATUS="OFF"
CF_COLOR="$RED"

if [[ "${ENABLE_CF_TUNNEL}" == "true" ]] || [[ "${ENABLE_CF_TUNNEL}" == "1" ]]; then
    if [ -n "${CF_TOKEN}" ]; then
        pkill -f cloudflared 2>/dev/null || true
        nohup cloudflared tunnel run --token "${CF_TOKEN}" > /home/container/.cloudflared.log 2>&1 &
        CF_STATUS="ACTIVE"
        CF_COLOR="$GREEN"
    fi
fi

clear
loading "Menyiapkan QOUPAY INDONESIA..." 1
loading "Memuat informasi server..." 1
loading "Memeriksa runtime & packages..." 1

COMMIT_NOW="$(git rev-parse --short HEAD 2>/dev/null || echo UNKNOWN)"
BRANCH_NOW="${BRANCH:-main}"
NODE_NOW="$(node -v 2>/dev/null || echo 'Not Installed')"
BUN_NOW="$(bun -v 2>/dev/null || echo 'Not Installed')"
GO_NOW="$(go version 2>/dev/null | awk '{print $3}' | sed 's/go//' || echo 'Not Installed')"
PY_NOW="$(python3 --version 2>/dev/null | awk '{print $2}' || echo 'Not Installed')"
FFMPEG_NOW="$(ffmpeg -version 2>/dev/null | head -n 1 | awk '{print $3}' || echo 'Not Installed')"
REDIS_NOW="$(redis-server --version 2>/dev/null | awk '{print $3}' | sed 's/v=//' || redis-cli --version 2>/dev/null | awk '{print $2}' || echo 'Not Installed')"
MARIADB_NOW="$(mariadb --version 2>/dev/null | sed -E 's/.*Distrib ([^,]+).*/\1/' || echo 'Not Installed')"
PM2_NOW="$(pm2 -v 2>/dev/null | tail -n 1 || echo 'Not Installed')"
PNPM_NOW="$(pnpm -v 2>/dev/null || echo 'Not Installed')"
SPEEDTEST_NOW="$(speedtest-cli --version 2>/dev/null | head -n 1 | awk '{print $2}' || echo 'Not Installed')"
NODEMON_NOW="$(nodemon -v 2>/dev/null || echo 'Not Installed')"
CHROMIUM_NOW="$(chromium --version 2>/dev/null | awk '{print $2}' || echo 'Not Installed')"
YTDLP_NOW="$(yt-dlp --version 2>/dev/null || echo 'Not Installed')"

LOCATION_NOW="$(curl -s ipinfo.io/country 2>/dev/null || echo 'Unknown')"
PUBLIC_IP_NOW="$(curl -s ipinfo.io/ip 2>/dev/null || echo 'Unknown')"
ISP_NOW="$(curl -s ipinfo.io/org 2>/dev/null | sed -E 's/^AS[0-9]+[[:space:]]*//' || echo 'Unknown')"
OS_NOW="$(grep -oP '(?<=^PRETTY_NAME=).+' /etc/os-release | tr -d '\"')"
KERNEL_NOW="$(uname -sr)"
ARCH_NOW="$(uname -m)"
CPU_NOW="$(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2 | sed 's/^ //')"
CORES_NOW="$(grep -c '^processor' /proc/cpuinfo)"
UPTIME_NOW="$(uptime -p | sed 's/up //')"
RAM_NOW="$(free -m | awk '/Mem:/ {print $3" MB / "$2" MB"}')"
DISK_NOW="$(df -h / | awk 'NR==2 {print $3" / "$2" ("$5")"}')"
SERVER_TIME="$(date '+%Y-%m-%d %H:%M:%S')"

clear

echo -e "${RED}${BOLD}"
echo '  ██████╗  ██████╗ ██╗   ██╗██████╗  █████╗ ██╗   ██╗'
echo ' ██╔═══██╗██╔═══██╗██║   ██║██╔══██╗██╔══██╗╚██╗ ██╔╝'
echo ' ██║   ██║██║   ██║██║   ██║██████╔╝███████║ ╚████╔╝ '
echo ' ██║▄▄ ██║██║   ██║██║   ██║██╔═══╝ ██╔══██║  ╚██╔╝  '
echo ' ╚██████╔╝╚██████╔╝╚██████╔╝██║     ██║  ██║   ██║   '
echo '  ╚══▀▀═╝  ╚═════╝  ╚═════╝ ╚═╝     ╚═╝  ╚═╝   ╚═╝   '
echo -e "${RESET}${WHITE}${BOLD}                    I N D O N E S I A${RESET}"
echo -e "${GRAY}                Qoupay Runtime Environment${RESET}"
echo -e "${CYAN}────────────────────────────────────────────────────────────${RESET}"

echo -e "${YELLOW}                     【 SYSTEM INFO 】${RESET}"
echo -e "${CYAN}➢${RESET} ${WHITE}ISP         :${RESET} ${CYAN}$ISP_NOW${RESET}"
echo -e "${CYAN}➢${RESET} ${WHITE}IPv4        :${RESET} ${CYAN}$PUBLIC_IP_NOW${RESET}"
echo -e "${CYAN}➢${RESET} ${WHITE}Country     :${RESET} ${RED}$LOCATION_NOW${RESET}"
echo -e "${CYAN}➢${RESET} ${WHITE}OS          :${RESET} ${PURPLE}$OS_NOW${RESET}"
echo -e "${CYAN}➢${RESET} ${WHITE}Kernel      :${RESET} ${PURPLE}$KERNEL_NOW${RESET}"
echo -e "${CYAN}➢${RESET} ${WHITE}Arch        :${RESET} ${PURPLE}$ARCH_NOW${RESET}"
echo -e "${CYAN}➢${RESET} ${WHITE}Uptime      :${RESET} ${RED}$UPTIME_NOW${RESET}"
echo -e "${CYAN}────────────────────────────────────────────────────────────${RESET}"

echo -e "${CYAN}➢${RESET} ${WHITE}NodeJS Ver  :${RESET} ${YELLOW}$NODE_NOW${RESET}"
echo -e "${CYAN}➢${RESET} ${WHITE}Python Ver  :${RESET} ${GREEN}$PY_NOW${RESET}"
echo -e "${CYAN}➢${RESET} ${WHITE}Bun Ver     :${RESET} ${PURPLE}v$BUN_NOW${RESET}"
echo -e "${CYAN}➢${RESET} ${WHITE}Golang Ver  :${RESET} ${BLUE}v$GO_NOW${RESET}"
echo -e "${CYAN}────────────────────────────────────────────────────────────${RESET}"

echo -e "${YELLOW}                     【 SERVER USAGE 】${RESET}"
echo -e "${CYAN}➢${RESET} ${WHITE}CPU Cores   :${RESET} ${PURPLE}$CORES_NOW Core(s) [$ARCH_NOW]${RESET}"
echo -e "${CYAN}➢${RESET} ${WHITE}CPU Model   :${RESET} ${GRAY}$CPU_NOW${RESET}"
echo -e "${CYAN}➢${RESET} ${WHITE}Memory      :${RESET} ${GREEN}$RAM_NOW${RESET}"
echo -e "${CYAN}➢${RESET} ${WHITE}Disk Space  :${RESET} ${GREEN}$DISK_NOW${RESET}"
echo -e "${CYAN}➢${RESET} ${WHITE}Server Time :${RESET} ${CYAN}$SERVER_TIME${RESET}"
echo -e "${CYAN}────────────────────────────────────────────────────────────${RESET}"

echo -e "${YELLOW}                       【 GITHUB 】${RESET}"
echo -e "${CYAN}➢${RESET} ${WHITE}Auto Update :${RESET} ${GREEN}${AUTO_UPDATE:-1}${RESET}"
echo -e "${CYAN}➢${RESET} ${WHITE}Branch      :${RESET} ${BLUE}$BRANCH_NOW${RESET}"
echo -e "${CYAN}➢${RESET} ${WHITE}Commit      :${RESET} ${YELLOW}$COMMIT_NOW${RESET}"
echo -e "${CYAN}────────────────────────────────────────────────────────────${RESET}"

echo -e "${YELLOW}                      【 PACKAGES 】${RESET}"
echo -e "${WHITE}  BUN, PYTHON, NODEJS, FFMPEG, GOLANG, REDIS, MARIADB${RESET}"
echo -e "${WHITE}  PM2, PNPM, SPEEDTEST-CLI, NODEMON, CHROMIUM, YT-DLP${RESET}"
echo -e "${GRAY}  Redis $REDIS_NOW | MariaDB $MARIADB_NOW | FFmpeg $FFMPEG_NOW${RESET}"
echo -e "${GRAY}  PM2 $PM2_NOW | PNPM $PNPM_NOW | Nodemon $NODEMON_NOW${RESET}"
echo -e "${GRAY}  Chromium $CHROMIUM_NOW | yt-dlp $YTDLP_NOW | Speedtest $SPEEDTEST_NOW${RESET}"
echo -e "${CYAN}────────────────────────────────────────────────────────────${RESET}"

if [ "$CF_STATUS" = "ACTIVE" ]; then
    echo -e "${GREEN}✓ Cloudflare Tunnel aktif.${RESET}"
else
    echo -e "${YELLOW}• Cloudflare Tunnel nonaktif.${RESET}"
fi

echo -e "${CYAN}────────────────────────────────────────────────────────────${RESET}"
echo -e "${GREEN}✓ QOUPAY INDONESIA siap digunakan.${RESET}"
echo ""

exec /bin/bash
