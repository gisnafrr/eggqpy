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
            "$NODE_DIR/bin/npm" install -g pm2 pnpm yarn playwright --loglevel=error || true
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
    if [ -d "/home/container/.git" ]; then
        BRANCH_NAME="${BRANCH:-main}"
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

COMMIT_NOW="$(git rev-parse --short HEAD 2>/dev/null || echo UNKNOWN)"
BRANCH_NOW="${BRANCH:-main}"
NODE_NOW="$(node -v 2>/dev/null || echo 'Not Installed')"
BUN_NOW="$(bun -v 2>/dev/null || echo 'Not Installed')"
GO_NOW="$(go version 2>/dev/null | awk '{print $3}' | sed 's/go//' || echo 'Not Installed')"
PY_NOW="$(python3 --version 2>/dev/null | awk '{print $2}' || echo 'Not Installed')"
PW_NOW="$(playwright --version 2>/dev/null | head -n 1 || echo 'Not Installed')"
LOCATION_NOW="$(curl -s ipinfo.io/country 2>/dev/null || echo 'Unknown')"
OS_NOW="$(grep -oP '(?<=^PRETTY_NAME=).+' /etc/os-release | tr -d '\"')"
CPU_NOW="$(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2 | sed 's/^ //')"
CORES_NOW="$(grep -c '^processor' /proc/cpuinfo)"
UPTIME_NOW="$(uptime -p | sed 's/up //')"
RAM_NOW="$(free -m | awk '/Mem:/ {print $3" MB / "$2" MB"}')"
DISK_NOW="$(df -h / | awk 'NR==2 {print $3" / "$2" ("$5")"}')"

echo -e "${CYAN}╔════════════════════════════════════════════════════╗${RESET}"
echo -e "${CYAN}║${WHITE}${BOLD}                   Q O U P A Y                      ${CYAN}║${RESET}"
echo -e "${CYAN}║${GRAY}              Cloud Runtime Environment             ${CYAN}║${RESET}"
echo -e "${CYAN}╠════════════════════════════════════════════════════╣${RESET}"

echo -e "${CYAN}║ ${PURPLE}${BOLD}GITHUB${RESET}"
echo -e "${CYAN}║${RESET}  ${GREEN}✓${RESET} Auto Update   : ${GREEN}${AUTO_UPDATE:-1}${RESET}"
echo -e "${CYAN}║${RESET}  ${BLUE}↻${RESET} Branch        : ${WHITE}$BRANCH_NOW${RESET}"
echo -e "${CYAN}║${RESET}  ${YELLOW}◆${RESET} Commit        : ${YELLOW}$COMMIT_NOW${RESET}"

echo -e "${CYAN}╠════════════════════════════════════════════════════╣${RESET}"
echo -e "${CYAN}║ ${PURPLE}${BOLD}RUNTIME${RESET}"
echo -e "${CYAN}║${RESET}  ${GREEN}●${RESET} Node.js       : ${WHITE}$NODE_NOW${RESET}"
echo -e "${CYAN}║${RESET}  ${GREEN}●${RESET} Bun           : ${WHITE}v$BUN_NOW${RESET}"
echo -e "${CYAN}║${RESET}  ${GREEN}●${RESET} Python        : ${WHITE}v$PY_NOW${RESET}"
echo -e "${CYAN}║${RESET}  ${GREEN}●${RESET} Golang        : ${WHITE}v$GO_NOW${RESET}"
echo -e "${CYAN}║${RESET}  ${GREEN}●${RESET} Playwright    : ${WHITE}$PW_NOW${RESET}"

echo -e "${CYAN}╠════════════════════════════════════════════════════╣${RESET}"
echo -e "${CYAN}║ ${PURPLE}${BOLD}SYSTEM${RESET}"
echo -e "${CYAN}║${RESET}  ${BLUE}●${RESET} Location      : ${WHITE}$LOCATION_NOW${RESET}"
echo -e "${CYAN}║${RESET}  ${BLUE}●${RESET} OS            : ${WHITE}$OS_NOW${RESET}"
echo -e "${CYAN}║${RESET}  ${BLUE}●${RESET} CPU           : ${WHITE}$CPU_NOW ($CORES_NOW Cores)${RESET}"
echo -e "${CYAN}║${RESET}  ${BLUE}●${RESET} Uptime        : ${WHITE}$UPTIME_NOW${RESET}"
echo -e "${CYAN}║${RESET}  ${BLUE}●${RESET} RAM           : ${WHITE}$RAM_NOW${RESET}"
echo -e "${CYAN}║${RESET}  ${BLUE}●${RESET} Disk          : ${WHITE}$DISK_NOW${RESET}"

echo -e "${CYAN}╠════════════════════════════════════════════════════╣${RESET}"
echo -e "${CYAN}║${RESET}  ${CF_COLOR}● Cloudflare Tunnel : $CF_STATUS${RESET}"
echo -e "${CYAN}╚════════════════════════════════════════════════════╝${RESET}"

exec /bin/bash
