#!/usr/bin/env bash

# 若由 sh / dash 執行，自動切換以 bash 執行
if [ -z "${BASH_VERSION:-}" ]; then
    exec bash "$0" "$@"
fi

set -Eeuo pipefail

# 支援由一般使用者或 sudo 執行時皆能正確找到使用者目錄
target_home="${HOME}"
if [[ -n "${SUDO_USER:-}" ]]; then
    sudo_user_home="$(getent passwd "$SUDO_USER" 2>/dev/null | cut -d: -f6)"
    if [[ -n "$sudo_user_home" && -d "$sudo_user_home" ]]; then
        target_home="$sudo_user_home"
    fi
fi

readonly SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0" 2>/dev/null || echo "$0")")" && pwd)"
readonly TARGET_HOME="$target_home"
SYSTEM_RG="${SYSTEM_RG:-$(command -v rg 2>/dev/null || true)}"

mode="fix"
auto_install_rg=0

usage() {
    cat <<'EOF'
用法：
  fix_gitlab-workflow-rg.sh               檢查並修復 GitLab Workflow extension 的 rg，並清除殘留備份與怪異符號檔案
  fix_gitlab-workflow-rg.sh --check       只檢查，不修改檔案
  fix_gitlab-workflow-rg.sh --install-rg  若系統缺少相容 rg，自動嘗試透過包管理器安裝
  fix_gitlab-workflow-rg.sh --help        顯示說明

可選環境變數：
  VSCODE_EXTENSIONS_DIR      VS Code extensions 根目錄
  ANTIGRAVITY_EXTENSIONS_DIR Antigravity extensions 根目錄
  SYSTEM_RG                  要使用的相容 ripgrep 路徑
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --check)
            mode="check"
            shift
            ;;
        --install-rg)
            auto_install_rg=1
            shift
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            printf '不支援的參數：%s\n' "$1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

# 確認系統 ripgrep
if [[ -z "$SYSTEM_RG" || ! -x "$SYSTEM_RG" ]]; then
    if [[ $auto_install_rg -eq 1 ]]; then
        if [[ -x "${SCRIPT_DIR}/check_rg.sh" ]]; then
            printf '偵測到缺少系統 ripgrep，正在嘗試自動安裝...\n'
            "${SCRIPT_DIR}/check_rg.sh" --install || true
            SYSTEM_RG="$(command -v rg 2>/dev/null || true)"
        fi
    fi
fi

if [[ -z "$SYSTEM_RG" || ! -x "$SYSTEM_RG" ]]; then
    printf '找不到可執行的系統 ripgrep (rg)！\n' >&2
    if [[ -x "${SCRIPT_DIR}/check_rg.sh" ]]; then
        printf '建議執行以下指令進行檢查與安裝：\n  %s/check_rg.sh --install\n' "$SCRIPT_DIR" >&2
    else
        printf '請先安裝 ripgrep 或指定 SYSTEM_RG 環境變數。\n' >&2
    fi
    exit 2
fi

host_arch="$(uname -m)"
system_description="$(file -Lb "$SYSTEM_RG")"

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

if is_compatible "$system_description"; then
    :
else
    result=$?
    if [[ $result -eq 2 ]]; then
        printf '尚未支援主機架構：%s\n' "$host_arch" >&2
    else
        printf '系統 rg 與主機架構不相容：%s\n' "$system_description" >&2
    fi
    exit 2
fi

# 擴充功能搜尋目錄列表 (支援 VS Code 與 Antigravity)
candidate_roots=()
[[ -n "${VSCODE_EXTENSIONS_DIR:-}" ]] && candidate_roots+=("$VSCODE_EXTENSIONS_DIR")
[[ -n "${ANTIGRAVITY_EXTENSIONS_DIR:-}" ]] && candidate_roots+=("$ANTIGRAVITY_EXTENSIONS_DIR")

candidate_roots+=(
    "${TARGET_HOME}/.vscode-server/extensions"
    "${TARGET_HOME}/.vscode-server-insiders/extensions"
    "${TARGET_HOME}/.antigravity-ide-server/extensions"
    "${TARGET_HOME}/.antigravity-server/extensions"
    "${TARGET_HOME}/.vscode/extensions"
)

extension_roots=()
declare -A seen_roots=()
for root in "${candidate_roots[@]}"; do
    if [[ -d "$root" && -z "${seen_roots["$root"]:-}" ]]; then
        seen_roots["$root"]=1
        extension_roots+=("$root")
    fi
done

if [[ ${#extension_roots[@]} -eq 0 ]]; then
    printf '找不到任何 VS Code 或 Antigravity extensions 目錄。\n' >&2
    exit 2
fi

shopt -s nullglob
bundled_binaries=()
for ext_root in "${extension_roots[@]}"; do
    for rg_bin in "$ext_root"/gitlab.gitlab-workflow-*/assets/language-server/rg; do
        bundled_binaries+=("$rg_bin")
    done
done

if [[ ${#bundled_binaries[@]} -eq 0 ]]; then
    printf '找不到任何 GitLab Workflow extension 的 bundled rg。\n'
else
    printf '=== 檢查與修復 GitLab Workflow ripgrep (rg) ===\n'
fi

problem_count=0
fixed_count=0

for bundled_rg in "${bundled_binaries[@]}"; do
    version_dir="${bundled_rg%/assets/language-server/rg}"
    version_name="${version_dir##*/}"
    ext_parent="$(dirname "$version_dir")"
    env_dir="$(dirname "$ext_parent")"
    env_name="$(basename "$env_dir")"
    display_name="${env_name}/${version_name}"
    resolved_path="$(readlink -f "$bundled_rg" 2>/dev/null || true)"

    if [[ -x "$bundled_rg" ]] && is_compatible "$(file -Lb "$bundled_rg")"; then
        printf '[正常] %s -> %s\n' "$display_name" "${resolved_path:-$bundled_rg}"
        continue
    fi

    problem_count=$((problem_count + 1))
    description="$(file -Lb "$bundled_rg" 2>/dev/null || printf '無法辨識')"
    printf '[架構不符] %s：%s\n' "$display_name" "$description"

    if [[ "$mode" == "check" ]]; then
        continue
    fi

    checksum="$(sha256sum "$bundled_rg" 2>/dev/null | awk '{print $1}' || echo "unknown")"
    backup_path="${bundled_rg}.vendor-${checksum:0:12}.disabled"

    if [[ ! -e "$backup_path" ]]; then
        mv "$bundled_rg" "$backup_path"
        printf '  已備份：%s\n' "$backup_path"
    else
        rm -f "$bundled_rg"
        printf '  已存在相同備份：%s\n' "$backup_path"
    fi

    ln -sf "$SYSTEM_RG" "$bundled_rg"

    if [[ -n "${SUDO_USER:-}" ]]; then
        chown -h "${SUDO_USER}:" "$bundled_rg" 2>/dev/null || true
        if [[ -e "$backup_path" ]]; then
            chown "${SUDO_USER}:" "$backup_path" 2>/dev/null || true
        fi
    fi

    if ! "$bundled_rg" --version >/dev/null 2>&1; then
        printf '修補後的 rg 無法執行：%s\n' "$bundled_rg" >&2
        exit 2
    fi

    fixed_count=$((fixed_count + 1))
    printf '  已修復：%s -> %s\n' "$display_name" "$SYSTEM_RG"
done

# 清理舊的 .disabled 垃圾檔案
cleaned_backup_count=0
if [[ ${#bundled_binaries[@]} -gt 0 ]]; then
    printf '\n=== 清理 Extension 殘留備份檔 (.disabled) ===\n'
    for bundled_rg in "${bundled_binaries[@]}"; do
        bundled_dir="$(dirname "$bundled_rg")"
        for disabled_file in "$bundled_dir"/*.disabled; do
            if [[ -f "$disabled_file" ]]; then
                if [[ "$mode" == "check" ]]; then
                    printf '[備份垃圾檔待清理] %s\n' "$disabled_file"
                    cleaned_backup_count=$((cleaned_backup_count + 1))
                else
                    rm -f "$disabled_file"
                    cleaned_backup_count=$((cleaned_backup_count + 1))
                    printf '  已清理備份檔：%s\n' "$disabled_file"
                fi
            fi
        done
    done
    if [[ $cleaned_backup_count -eq 0 ]]; then
        printf '無殘留 .disabled 備份檔。\n'
    fi
fi

# 移除怪異符號/非列印控制字元的異常垃圾檔案 (例如 \0014\253\006@W@8 等終端洩漏暫存檔)
printf '\n=== 檢查與移除怪異符號檔案 ===\n'
candidate_scan_dirs=(
    "$PWD"
    "$SCRIPT_DIR"
    "$TARGET_HOME"
)

if [[ -d "${TARGET_HOME}/JackySystem" ]]; then
    candidate_scan_dirs+=("${TARGET_HOME}/JackySystem")
    for subdir in "${TARGET_HOME}/JackySystem"/*; do
        if [[ -d "$subdir" ]]; then
            candidate_scan_dirs+=("$subdir")
        fi
    done
fi

declare -A seen_scan_dirs=()
scan_dirs=()
for sdir in "${candidate_scan_dirs[@]}"; do
    if [[ -d "$sdir" && -z "${seen_scan_dirs["$sdir"]:-}" ]]; then
        seen_scan_dirs["$sdir"]=1
        scan_dirs+=("$sdir")
    fi
done

junk_files_cleaned=0
for scan_dir in "${scan_dirs[@]}"; do
    for f in "$scan_dir"/* "$scan_dir"/.*; do
        # 忽略 . 與 ..
        base_name="$(basename "$f")"
        [[ "$base_name" == "." || "$base_name" == ".." ]] && continue
        
        # 必須是普通檔案或符號連結
        if [[ -f "$f" || -L "$f" ]]; then
            # 判斷是否包含 ASCII 控制字元、非列印字元，或終端序列洩漏特徵檔 (例如包含 @W@8 且為 0 byte)
            is_weird=0
            if [[ "$base_name" =~ [[:cntrl:]] || "$base_name" =~ [^[:print:]] ]]; then
                is_weird=1
            elif [[ "$base_name" == *"@W@8"* && ! -s "$f" ]]; then
                is_weird=1
            fi

            if [[ $is_weird -eq 1 ]]; then
                if [[ "$mode" == "check" ]]; then
                    printf '[怪異符號檔案待清理] %q (%s)\n' "$f" "$scan_dir"
                    junk_files_cleaned=$((junk_files_cleaned + 1))
                else
                    rm -f "$f"
                    junk_files_cleaned=$((junk_files_cleaned + 1))
                    printf '  已清理怪異符號檔案：%q\n' "$f"
                fi
            fi
        fi
    done
done

if [[ $junk_files_cleaned -eq 0 ]]; then
    printf '無發現怪異符號檔案。\n'
fi

printf '\n=== 處理結果總結 ===\n'
if [[ "$mode" == "check" ]]; then
    printf '檢查完成：發現 %d 個架構不符 rg，%d 個待清理備份檔，%d 個怪異符號檔案。\n' \
        "$problem_count" "$cleaned_backup_count" "$junk_files_cleaned"
    if [[ $problem_count -gt 0 || $junk_files_cleaned -gt 0 ]]; then
        exit 1
    fi
else
    printf '處理完成：修復 %d 個 rg，清理 %d 個備份檔，清理 %d 個怪異符號檔案。\n' \
        "$fixed_count" "$cleaned_backup_count" "$junk_files_cleaned"
fi

if [[ $fixed_count -gt 0 ]]; then
    printf '提示：請在 VS Code 或 Antigravity 中執行「Developer: Reload Window」以重載 Language Server。\n'
fi
