#!/bin/bash
# ============================================================
# MiliUI_ChatBar 自動同步 + 打包 + 上傳腳本
# 雙擊執行，輸入版本號（格式 1.0.0）後：
#   1. 先更新遊戲目錄 MiliUI_ChatBar.toc 的 ## Version，並在該 repo 單獨 commit + 打 tag
#   2. 從遊戲目錄同步 MiliUI_ChatBar 到本專案（本專案是平鋪結構，插件檔案直接放在根目錄）
#   3. 更新本專案 MiliUI_ChatBar.toc 的 ## Version
#   4. git commit（訊息就是版本號）+ 打 tag
#   5. 打包成 MiliUI_ChatBar_<版本>.zip 並上傳
# ============================================================

# === 切換到腳本所在目錄 ===
cd "$(dirname "$0")" || {
    echo "❌ 無法切換到腳本所在目錄"
    read -p "按 Enter 關閉..."
    exit 1
}

# === 讀取 .env ===
if [ ! -f ".env" ]; then
    echo "❌ 找不到 .env 檔案"
    read -p "按 Enter 關閉..."
    exit 1
fi

set -a
source .env
set +a

if [ -z "${API_TOKEN}" ] || [ -z "${ADDON_NAME}" ]; then
    echo "❌ .env 缺少 API_TOKEN 或 ADDON_NAME"
    read -p "按 Enter 關閉..."
    exit 1
fi

API_URL="https://addons.miliui.com/api/uifile/upload"
UI_ID="${ADDON_NAME}"

ADDON_DIR="MiliUI_ChatBar"
LAST_VER_FILE=".last_version"
TOC_FILES="MiliUI_ChatBar.toc"
SOURCE_DIR="/Applications/World of Warcraft/_retail_/Interface/AddOns/MiliUI_ChatBar"
SOURCE_TOC="${SOURCE_DIR}/MiliUI_ChatBar.toc"

# 只屬於本專案、不是插件內容的檔案：同步時不會被刪、打包時不會放進去
# 開頭的 / 代表只比對根目錄（Libs/MiliUIWidgets/README.md 是插件內容，要照常同步與打包）
REPO_ONLY=(
    --exclude='/.git'
    --exclude='/.gitignore'
    --exclude='/.gitattributes'
    --exclude='/.env'
    --exclude='/.last_version'
    --exclude='/.vscode'
    --exclude='/package.command'
    --exclude='/package.sh'
    --exclude='/README.md'
    --exclude='/logo.png'
    --exclude='/*.zip'
)
# macOS 垃圾：不從遊戲目錄帶過來、也不放進壓縮檔
JUNK=(
    --exclude='.DS_Store'
    --exclude='._*'
    --exclude='luac.out'
    --exclude='__MACOSX'
)

is_version() {
    echo "$1" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'
}

toc_version() {
    grep -m1 '^## Version:' "$1" 2>/dev/null \
        | sed -E 's/^## Version:[[:space:]]*//' | tr -d '[:space:]'
}

# === 取得上次輸入的版本（優先讀記錄檔，其次由 .toc 反推） ===
# 本專案舊的 .toc 是 {version} 佔位符，反推不到時改讀遊戲目錄那份
DEFAULT_VER=""
if [ -f "${LAST_VER_FILE}" ]; then
    DEFAULT_VER=$(head -1 "${LAST_VER_FILE}" | tr -d '[:space:]')
fi
if ! is_version "${DEFAULT_VER}"; then
    DEFAULT_VER=$(toc_version "${TOC_FILES}")
fi
if ! is_version "${DEFAULT_VER}"; then
    DEFAULT_VER=$(toc_version "${SOURCE_TOC}")
fi
is_version "${DEFAULT_VER}" || DEFAULT_VER=""

# === 互動：版本號 ===
echo "================================================"
echo "  MiliUI_ChatBar 自動上傳"
echo "================================================"
echo ""
if [ -n "${DEFAULT_VER}" ]; then
    read -e -p "🏷️ 版本號 (格式 1.0.0) [上次: ${DEFAULT_VER}]: " VER
    VER=$(echo "${VER}" | tr -d '[:space:]')
    if [ -z "${VER}" ]; then
        VER="${DEFAULT_VER}"
        echo "   ↪ 沿用上次: ${VER}"
    fi
else
    read -e -p "🏷️ 版本號 (格式 1.0.0): " VER
    VER=$(echo "${VER}" | tr -d '[:space:]')
fi

if [ -z "${VER}" ]; then
    echo "❌ 必須輸入版本號"
    read -p "按 Enter 關閉..."
    exit 1
fi

if ! is_version "${VER}"; then
    echo "❌ 版本號格式錯誤: ${VER}（必須是 1.0.0 這種三段數字）"
    read -p "按 Enter 關閉..."
    exit 1
fi

TAG_NAME="Miliui_ChatBar-${VER}"
TAG_MSG="MiliUI_ChatBar: ${VER}"

echo ""
echo "🏷️ 版本: ${VER}"
echo "🏷️ tag: ${TAG_NAME}"
echo ""

# === 打 annotated tag ===
make_tag() {
    local REPO="$1"
    local TAG="$2"
    local MSG="$3"
    if git -C "${REPO}" rev-parse -q --verify "refs/tags/${TAG}" >/dev/null 2>&1; then
        if git -C "${REPO}" tag -f -a "${TAG}" -m "${MSG}" >/dev/null 2>&1; then
            echo "🏷️ tag 已存在，已改指向最新 commit: ${TAG}"
        else
            echo "⚠️ 更新 tag 失敗: ${TAG}"
        fi
    else
        if git -C "${REPO}" tag -a "${TAG}" -m "${MSG}" >/dev/null 2>&1; then
            echo "🏷️ 已建立 tag: ${TAG}"
        else
            echo "⚠️ 建立 tag 失敗: ${TAG}"
        fi
    fi
}

# === 從遊戲目錄同步 ===
if [ ! -d "${SOURCE_DIR}" ]; then
    echo "❌ 找不到來源資料夾: ${SOURCE_DIR}"
    read -p "按 Enter 關閉..."
    exit 1
fi

# === 先更新遊戲目錄的版本號，並在該 repo 單獨 commit ===
if [ ! -f "${SOURCE_TOC}" ]; then
    echo "❌ 找不到 ${SOURCE_TOC}"
    read -p "按 Enter 關閉..."
    exit 1
fi
if ! grep -q '^## Version:' "${SOURCE_TOC}"; then
    echo "❌ ${SOURCE_TOC} 內找不到 ## Version: 欄位"
    read -p "按 Enter 關閉..."
    exit 1
fi

sed -i '' -E "s|^## Version:.*|## Version: ${VER}|" "${SOURCE_TOC}"
echo "📝 遊戲目錄 MiliUI_ChatBar.toc → ## Version: ${VER}"

SOURCE_REPO=$(git -C "${SOURCE_DIR}" rev-parse --show-toplevel 2>/dev/null)
if [ -n "${SOURCE_REPO}" ]; then
    ADDON_REL="${SOURCE_DIR#${SOURCE_REPO}/}"
    TOC_REL="${SOURCE_TOC#${SOURCE_REPO}/}"

    # 提醒：插件其他檔案還有未 commit 的變更時，tag 不會包含它們
    DIRTY=$(git -C "${SOURCE_REPO}" status --porcelain -- "${ADDON_REL}" | grep -v -- "${TOC_REL}$")
    if [ -n "${DIRTY}" ]; then
        echo "⚠️ 遊戲目錄 repo 內插件還有未 commit 的變更（tag 不會包含這些）："
        echo "${DIRTY}" | sed 's/^/     /'
    fi

    # 只 commit 這個檔案，不動該 repo 其他的變更
    if [ -z "$(git -C "${SOURCE_REPO}" status --porcelain -- "${TOC_REL}")" ]; then
        echo "ℹ️ 遊戲目錄版本號無變更，略過 commit"
    else
        git -C "${SOURCE_REPO}" commit -q -m "chore: bump MiliUI_ChatBar version to ${VER}" -- "${TOC_REL}"
        echo "✅ 已在遊戲目錄 repo 單獨 commit: chore: bump MiliUI_ChatBar version to ${VER}"
    fi
    make_tag "${SOURCE_REPO}" "${TAG_NAME}" "${TAG_MSG}"
else
    echo "⚠️ 遊戲目錄不是 git 倉庫，略過 commit"
fi
echo ""

echo "📥 從遊戲目錄同步 MiliUI_ChatBar..."
echo "   ${SOURCE_DIR}"

# 本專案的插件檔案直接放在根目錄，沒辦法像子資料夾那樣整包刪掉重來；
# 改用 rsync --delete 鏡射：遊戲目錄沒有的檔案會被刪掉，REPO_ONLY 那幾個不受影響
rsync -a --delete "${REPO_ONLY[@]}" "${JUNK[@]}" "${SOURCE_DIR}/" ./
if [ $? -ne 0 ] || [ ! -f "${TOC_FILES}" ]; then
    echo "❌ 同步失敗！（${TOC_FILES} 不存在）"
    read -p "按 Enter 關閉..."
    exit 1
fi
echo "✅ 同步完成"

# === 清掉 macOS 垃圾（本專案裡殘留的；.git 不碰）===
find . -path ./.git -prune -o \( -name '.DS_Store' -o -name '._*' -o -name 'luac.out' \) -type f -exec rm -f {} + 2>/dev/null
echo "🧹 已清除 .DS_Store / ._ 檔 / luac.out"
echo ""

# === 更新 .toc 的版本號 ===
for TOC in ${TOC_FILES}; do
    if [ ! -f "${TOC}" ]; then
        echo "❌ 找不到 ${TOC}"
        read -p "按 Enter 關閉..."
        exit 1
    fi
    if ! grep -q '^## Version:' "${TOC}"; then
        echo "❌ ${TOC} 內找不到 ## Version: 欄位"
        read -p "按 Enter 關閉..."
        exit 1
    fi
    sed -i '' -E "s|^## Version:.*|## Version: ${VER}|" "${TOC}"
    echo "📝 ${TOC} → ## Version: ${VER}"
done

# 記錄本次輸入的版本，供下次帶入預設值
echo "${VER}" > "${LAST_VER_FILE}"

# === git commit ===
echo ""
if git rev-parse --git-dir >/dev/null 2>&1; then
    git add -A
    if git diff --cached --quiet; then
        echo "ℹ️ 沒有變更，略過 commit"
    else
        git commit -q -m "${VER}"
        echo "✅ 已 commit: ${VER}"
    fi
    make_tag "." "${TAG_NAME}" "${TAG_MSG}"
else
    echo "⚠️ 這裡不是 git 倉庫，略過 commit"
fi

# === 打包 ===
FILENAME="MiliUI_ChatBar_${VER}.zip"
FILEPATH="/tmp/${FILENAME}"
BUILD_DIR=$(mktemp -d "/tmp/${ADDON_DIR}_build.XXXXXX")

echo ""
echo "📦 正在打包 MiliUI_ChatBar..."
rm -f "${FILEPATH}"

# 根目錄是平鋪的，先把插件內容複製到暫存的 MiliUI_ChatBar/ 底下，壓縮檔頂層才會是插件資料夾
rsync -a "${REPO_ONLY[@]}" "${JUNK[@]}" ./ "${BUILD_DIR}/${ADDON_DIR}/"
xattr -cr "${BUILD_DIR}/${ADDON_DIR}" 2>/dev/null
# -X = 不寫入 macOS 延伸屬性／資源分支，避免解壓出 __MACOSX
(cd "${BUILD_DIR}" && zip -rqX "${FILEPATH}" "${ADDON_DIR}" -x "*.DS_Store" "*/._*" "__MACOSX/*")
rm -rf "${BUILD_DIR}"

if [ ! -f "${FILEPATH}" ]; then
    echo "❌ 打包失敗！"
    read -p "按 Enter 關閉..."
    exit 1
fi

# === 驗證壓縮檔結構：頂層只能有 MiliUI_ChatBar，且 .toc 要在 ===
TOP_LEVEL=$(unzip -Z1 "${FILEPATH}" | cut -d/ -f1 | sort -u)
if [ "${TOP_LEVEL}" != "${ADDON_DIR}" ]; then
    echo "❌ 壓縮檔頂層不只有 ${ADDON_DIR} 資料夾："
    echo "${TOP_LEVEL}" | sed 's/^/     /'
    rm -f "${FILEPATH}"
    read -p "按 Enter 關閉..."
    exit 1
fi
if ! unzip -Z1 "${FILEPATH}" | grep -qx "${ADDON_DIR}/${TOC_FILES}"; then
    echo "❌ 壓縮檔內找不到 ${ADDON_DIR}/${TOC_FILES}"
    rm -f "${FILEPATH}"
    read -p "按 Enter 關閉..."
    exit 1
fi

FILESIZE=$(du -h "${FILEPATH}" | cut -f1)
FILECOUNT=$(unzip -Z1 "${FILEPATH}" | wc -l | tr -d ' ')
echo "✅ 打包完成: ${FILENAME} (${FILESIZE}, ${FILECOUNT} 個項目)"
echo "   結構: ${ADDON_DIR}/ → MiliUI_ChatBar.toc ✓"

# === 上傳 ===
echo "🚀 正在上傳到插件補給站..."
RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "${API_URL}" \
    -H "Authorization: Bearer ${API_TOKEN}" \
    -F "file=@${FILEPATH}" \
    -F "ui_id=${UI_ID}" \
    -F "ui_version=${VER}")

HTTP_CODE=$(echo "${RESPONSE}" | tail -1)
BODY=$(echo "${RESPONSE}" | sed '$d')

echo ""
if [ "${HTTP_CODE}" = "201" ]; then
    echo "✅ 上傳成功！"
    echo "${BODY}" | python3 -m json.tool 2>/dev/null || echo "${BODY}"
else
    echo "❌ 上傳失敗 (HTTP ${HTTP_CODE})"
    echo "${BODY}"
fi

# === 清理 ===
rm -f "${FILEPATH}"
echo ""
echo "🎉 完成！"
read -p "按 Enter 關閉..."
