# GitLab Workflow Ripgrep (rg) Architecture Fixer & Junk Cleaner
### GitLab Workflow 擴充套件 Ripgrep (rg) 架構修復與異常檔案清理工具

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-Linux%20ARM64%20%7C%20x86__64-orange.svg)](#)
[![IDE](https://img.shields.io/badge/IDE-VS%20Code%20%7C%20Antigravity-purple.svg)](#)

[繁體中文 (Traditional Chinese)](#繁體中文) | [English](#english)

---

<a id="繁體中文"></a>
## 繁體中文

### 📌 這是什麼？針對什麼狀況發生？

本工具旨在解決在 **Linux ARM64 / aarch64** 環境（如 AWS Graviton、Oracle ARM、Raspberry Pi 4/5、Apple Silicon 上的 Linux 虛擬機等）使用 **VS Code** 或 **Google Antigravity IDE** 時，GitLab Workflow 擴充套件所引發的相容性錯誤與終端垃圾檔案問題。

#### 1. GitLab Workflow 內建 `rg` 架構不相容 (Architecture Mismatch)
* **發生原因**：GitLab Workflow 擴充套件在打包時，其 Language Server (`assets/language-server/rg`) 預先打包了 **x86-64 (amd64)** 架構的 `ripgrep` 二進位檔。
* **症狀**：在 ARM64 主機上，Language Server 嘗試呼叫 `rg` 時會直接失敗（報 `Exec format error` 或無聲卡死），導致 **GitLab Duo Code Suggestions**、代碼搜尋與相關語言服務功能異常。
* **解決方式**：本工具會檢查主機架構，若發現不相容的 `rg`，自動將其替換為系統原生編譯的相容 `rg`（通常位於 `/usr/bin/rg`）的符號連結（Symlink）。

#### 2. 終端控制序列洩漏導致怪異符號檔案 (Terminal Sequence Leak Files)
* **發生原因**：在遠端 SSH 或 PTY 終端環境中，若執行過程中有轉義序列（如游標位置回報 `ESC[6n`、設備狀態報告等）未被正常消費，或在執行未封閉引號的指令時，可能在工作目錄下產生含有 ASCII 控制字元與非 UTF-8 位元組的 0-byte 異常檔案（例如 `\0014\253\006@W@8`，終端常顯示為 `4@W@8` 或亂碼）。
* **症狀**：會造成一般工具在處理目錄時出錯（如 Python `UnicodeEncodeError: 'utf-8' codec can't encode character '\udcab'`）、檔案總管顯示亂碼。
* **解決方式**：本腳本提供智慧型掃描，精確比對 ASCII 控制字元 (`[[:cntrl:]]`)、非列印字元 (`[^[:print:]]`) 與洩漏特徵檔，自動且安全地清理這些垃圾檔案，**絕不影響**正常的中文字元或 UTF-8 檔案。

#### 3. 擴充套件殘留備份檔清理 (.disabled Clean-up)
* 自動清理以往手動或自動備份留下的 `*.disabled` 大二進位檔案，避免無謂消耗磁碟空間。

---

### ✨ 主要特點與腳本列表

專案包含兩個互相搭配的工具腳本：

1. **`check_rg.sh` (確認系統是否安裝 rg)**
   - 檢查系統是否已安裝 `ripgrep (rg)`、其所在路徑、程式版本與二進位架構。
   - 驗證該 `rg` 是否能與當前主機 CPU 架構完全相容。
   - 若未安裝，自動偵測發行版套件管理員（`apt`、`dnf`、`pacman`、`zypper`、`apk`、`brew`、`cargo`）並提供安裝指令，亦支援 `--install` 一鍵自動安裝。

2. **`fix_gitlab-workflow-rg.sh` (主修復與清理腳本)**
   - 自動搜尋所有 VS Code (`.vscode-server`、`.vscode-server-insiders`、`.vscode`) 與 Antigravity IDE (`.antigravity-ide-server`、`.antigravity-server`) 的 GitLab 擴充套件目錄。
   - 自動備份並替換不相容的 `rg` 為系統原生版本。
   - 清理殘留備份與異常怪異符號檔案。
   - 支援 `--check` 乾跑檢查模式與 `--install-rg` 自動輔助安裝模式。

---

### 🚀 快速開始

#### 步驟 1：確認系統是否已安裝 ripgrep
```bash
# 賦予執行權限
chmod +x check_rg.sh fix_gitlab-workflow-rg.sh

# 檢查安裝狀態與架構相容性
./check_rg.sh

# 若尚未安裝，可直接由腳本自動透過包管理器安裝：
./check_rg.sh --install
```

或者您也可以手動安裝：
```bash
# Debian / Ubuntu
sudo apt update && sudo apt install -y ripgrep

# Arch Linux
sudo pacman -S ripgrep

# Fedora
sudo dnf install ripgrep
```

#### 步驟 2：執行修復與垃圾檔清理
```bash
# 模式 A：乾跑檢查 (只檢查，不修改檔案)
./fix_gitlab-workflow-rg.sh --check

# 模式 B：正式執行修復與清理
./fix_gitlab-workflow-rg.sh

# 模式 C：若系統缺少 rg，自動安裝並修復
./fix_gitlab-workflow-rg.sh --install-rg
```

#### 步驟 3：重載 IDE 視窗
修復完成後，請至 VS Code 或 Antigravity IDE 按下 `F1` 或 `Ctrl+Shift+P`，執行：
> **Developer: Reload Window**

即可重載 Language Server 使修復生效。

---

<a id="english"></a>
## English

### 📌 Overview & Target Scenarios

This utility is designed for developers running **VS Code** or **Google Antigravity IDE** on **Linux ARM64 / aarch64** architectures (e.g., AWS Graviton, Oracle Cloud Ampere, Raspberry Pi 4/5, Apple Silicon Linux VMs), addressing compatibility failures and terminal leakage junk files caused by the GitLab Workflow extension.

#### 1. Architecture Incompatibility with Bundled `rg`
* **Root Cause**: The GitLab Workflow extension packages an **x86-64 (amd64)** binary of `ripgrep` in `assets/language-server/rg`.
* **Symptom**: On ARM64 Linux hosts, the Language Server fails to execute the bundled binary (triggering `Exec format error` or silent crashes). As a result, **GitLab Duo Code Suggestions**, code searches, and related language features stop working.
* **Resolution**: This tool detects host architecture and replaces the incompatible bundled binary with a symlink to your system's native ARM64 `rg` (`/usr/bin/rg`).

#### 2. Corrupted / Strange Character Junk Files from Leaked Terminal Sequences
* **Root Cause**: In remote SSH / PTY environments, unhandled terminal escape sequences (such as cursor query responses or device attributes) can accidentally write 0-byte files with raw control characters and non-UTF-8 bytes (e.g. `\0014\253\006@W@8`, often rendered on screen as `4@W@8` or strange glyphs).
* **Symptom**: Python scripts crash with `UnicodeEncodeError: 'utf-8' codec can't encode character '\udcab'`, file pickers fail, and directory listings show corrupted names.
* **Resolution**: The script safely detects and removes these control-character files (`[[:cntrl:]]`, `[^[:print:]]`) across workspaces without touching legitimate UTF-8 or CJK files.

#### 3. Residual `.disabled` Binaries Cleanup
* Automatically purges old leftover `.disabled` binary backups inside extension folders to reclaim disk space.

---

### ✨ Scripts in this Repository

1. **`check_rg.sh` (Verify ripgrep installation)**
   - Verifies whether `ripgrep (rg)` is installed, executable, and architecture-compatible.
   - Detects the system package manager (`apt`, `dnf`, `pacman`, `zypper`, `apk`, `brew`, `cargo`).
   - Supports `--install` flag for 1-click automatic installation.

2. **`fix_gitlab-workflow-rg.sh` (Core Fixer & Cleaner)**
   - Discovers all GitLab Workflow installations across VS Code and Antigravity IDEs.
   - Safely backs up incompatible binaries and symlinks them to the native `rg`.
   - Cleans old `.disabled` binaries and corrupted terminal-leak files.
   - Supports `--check` (dry run) and `--install-rg` (auto-install missing `rg`).

---

### 🚀 Quick Start

#### Step 1: Check or Install ripgrep
```bash
chmod +x check_rg.sh fix_gitlab-workflow-rg.sh

# Check status
./check_rg.sh

# Auto-install if missing:
./check_rg.sh --install
```

#### Step 2: Run Fix & Cleanup
```bash
# Dry run (check only)
./fix_gitlab-workflow-rg.sh --check

# Execute fix and cleanup
./fix_gitlab-workflow-rg.sh

# Execute fix with auto-install if rg is missing
./fix_gitlab-workflow-rg.sh --install-rg
```

#### Step 3: Reload IDE Window
After execution, open the command palette (`Ctrl+Shift+P` or `F1`) in your IDE and run:
> **Developer: Reload Window**

---

### 📄 License

This project is licensed under the [MIT License](LICENSE) - free for everyone to use, modify, and share!
