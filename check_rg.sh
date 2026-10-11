#!/usr/bin/env bash

# 若由 sh / dash 執行，自動切換以 bash 執行
if [ -z "${BASH_VERSION:-}" ]; then
    exec bash "$0" "$@"
fi

set -Eeuo pipefail

host_arch="$(uname -m)"
rg_path="$(command -v rg 2>/dev/null || true)"
auto_install=0

usage() {
    cat <<'EOF'
用法：
  check_rg.sh            檢查系統是否已安裝 ripgrep (rg) 及其架構相容性
  check_rg.sh --install  若未安裝或不相容，嘗試透過系統包管理器自動安裝
  check_rg.sh --help     顯示說明
EOF
}

case "${1:-}" in
    "") ;;
    --install|-i) auto_install=1 ;;
    --help|-h)
        usage
        exit 0
        ;;
    *)
        printf '不支援的參數：%s
' "$1" >&2
        usage >&2
        exit 2
        ;;
esac

get_install_cmd() {
    if command -v apt-get >/dev/null 2>&1; then
        echo "sudo apt update && sudo apt install -y ripgrep"
    elif command -v dnf >/dev/null 2>&1; then
        echo "sudo dnf install -y ripgrep"
    elif command -v pacman >/dev/null 2>&1; then
        echo "sudo pacman -S --noconfirm ripgrep"
    elif command -v zypper >/dev/null 2>&1; then
        echo "sudo zypper install -y ripgrep"
    elif command -v apk >/dev/null 2>&1; then
        echo "sudo apk add ripgrep"
    elif command -v brew >/dev/null 2>&1; then
        echo "brew install ripgrep"
    elif command -v cargo >/dev/null 2>&1; then
        echo "cargo install ripgrep"
    else
        echo ""
    fi
}

is_compatible() {
    local description="$1"
    case "$host_arch" in
        aarch64|arm64)
            [[ "$description" == *"ARM aarch64"* || "$description" == *"ARM64"* ]]
            ;;
        x86_64|amd64)
            [[ "$description" == *"x86-64"* || "$description" == *"x86_64"* ]]
            ;;
        *)
            return 2
            ;;
    esac
}

printf '=== 檢查系統 ripgrep (rg) 安裝與相容性 ===
'
printf '主機架構 (Host Architecture)：%s
' "$host_arch"

if [[ -n "$rg_path" && -x "$rg_path" ]]; then
    rg_ver="$("$rg_path" --version 2>/dev/null | head -n 1 || echo "無法取得版本")"
    file_desc="$(file -Lb "$rg_path" 2>/dev/null || echo "無法辨識")"

    printf '安裝狀態：✅ 已安裝 (Installed)
'
    printf '執行路徑：%s
' "$rg_path"
    printf '程式版本：%s
' "$rg_ver"
    printf '二進位檔：%s
' "$file_desc"

    if is_compatible "$file_desc"; then
        printf '相容性評估：✅ 架構相容 (Compatible) - 可供 GitLab Workflow 擴充套件使用。
'
        exit 0
    else
        printf '相容性評估：❌ 架構不相容 (Incompatible)！目前的 rg 二進位檔無法於此主機架構正常運行。
'
    fi
else
    printf '安裝狀態：❌ 未安裝 (Not Installed)
'
fi

install_cmd="$(get_install_cmd)"

if [[ -n "$install_cmd" ]]; then
    printf '
建議安裝指令：
  %s
' "$install_cmd"
else
    printf '
未偵測到常見的包管理器，請手動編譯或自 GitHub Releases 下載對應架構的 ripgrep。
'
fi

if [[ $auto_install -eq 1 ]]; then
    if [[ -n "$install_cmd" ]]; then
        printf '
正在執行自動安裝：%s
' "$install_cmd"
        eval "$install_cmd"
        # 重新檢查
        new_rg="$(command -v rg 2>/dev/null || true)"
        if [[ -n "$new_rg" && -x "$new_rg" ]]; then
            printf '安裝成功！重新驗證：%s
' "$("$new_rg" --version | head -n 1)"
            exit 0
        else
            printf '安裝完成但仍無法找到 rg，請確認 PATH 設定。
' >&2
            exit 1
        fi
    else
        printf '無法自動安裝，無支援的包管理器。
' >&2
        exit 1
    fi
else
    printf '
提示：若需自動執行安裝，請加上 --install 參數，例如：
  %s --install
' "$0"
    exit 1
fi
