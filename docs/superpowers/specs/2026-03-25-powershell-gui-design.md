# PowerShell WPF GUI for MonsterMash

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the GTK4 GUI with a zero-dependency PowerShell/WPF GUI that launches instantly on Windows and wraps the existing `unwad.exe` CLI.

**Architecture:** A single `MonsterMash.ps1` file using WPF (built into Windows) that presents the same layout as the previous GTK4 GUI. It constructs CLI flags from widget values and runs `unwad.exe` as a subprocess, streaming output in real-time.

**Tech Stack:** PowerShell 5.1+ (ships with Windows 10/11), WPF via `PresentationFramework` assembly, `System.Diagnostics.Process` for subprocess management.

---

## File

- `MonsterMash/MonsterMash.ps1` — the entire GUI in a single file
- Script must reside alongside `unwad.exe` in the same directory

## Path Resolution

- All paths are relative to `$PSScriptRoot` (the directory containing `MonsterMash.ps1`)
- `unwad.exe` path: `Join-Path $PSScriptRoot 'unwad.exe'`
- `Source/` path: `Join-Path $PSScriptRoot 'Source'`
- `IWADs/` path: `Join-Path $PSScriptRoot 'IWADs'`
- Folder buttons open `explorer.exe` with the resolved absolute path

## Layout (matches GTK4 version)

### Row 1 — Folder Buttons
- "Open Source Folder" button — runs `explorer.exe` on `$PSScriptRoot\Source`
- "Open IWADs Folder" button — runs `explorer.exe` on `$PSScriptRoot\IWADs`

### Row 2 — Slider Defaults Frame
Six sliders in a labeled group box, each with: label | slider | value readout

| Slider     | Default | Range | Step |
|------------|---------|-------|------|
| Weapon     | 0.0     | 0-20  | 0.02 |
| Monster    | 1.0     | 0-20  | 0.02 |
| Ally       | 1.0     | 0-20  | 0.02 |
| Ammo       | 10.0    | 0-20  | 0.02 |
| Nice Item  | 0.3     | 0-20  | 0.02 |
| Pickup     | 0.3     | 0-20  | 0.02 |

Value readout displays 2 decimal places, updates as slider moves.

### Row 3 — Options Row
- "Skip post-run cleanup" checkbox
- "Verbosity" label + dropdown: Errors only (default), Warnings, Info, Debug

### Row 4 — Action Buttons
- "Run Unwad" button (accent/primary style)
- "Clean Only" button

### Row 5 — Output
- Scrollable, read-only, monospace TextBox
- Real-time line-by-line output from subprocess
- Auto-scrolls to bottom
- Clears when Run or Clean is clicked
- No scrollback limit needed (subprocess output is bounded by the run)

## Window Properties
- Title: "Unwad V2 -- Monster Mash WAD Processor" (copy from unwad.cr line 26)
- Default size: 720x700
- Resizable: yes

## Subprocess Execution

When "Run Unwad" is clicked:

1. Build CLI args from current widget values:
   - Format each slider value to exactly 2 decimal places (`$value.ToString('F2')`) before constructing the arg string
   - Slider values: `--weapon-default=N --monster-default=N --ally-default=N --ammo-default=N --nice-item-default=N --pickup-default=N`
   - Cleanup checkbox: `--no-cleanup` if checked
   - Verbosity: nothing (Errors only), `-v` (Warnings), `-vv` (Info), `-vvv` (Debug)
2. Disable both buttons
3. Clear the output text box
4. Start `unwad.exe` using `System.Diagnostics.Process`:
   - Set `FileName` to `Join-Path $PSScriptRoot 'unwad.exe'`
   - Set `WorkingDirectory` to `$PSScriptRoot`
   - Set `RedirectStandardOutput = $true`, `RedirectStandardError = $true`, `UseShellExecute = $false`
   - Set `StandardOutputEncoding` and `StandardErrorEncoding` to `[System.Text.Encoding]::UTF8`
   - Register async `OutputDataReceived` / `ErrorDataReceived` event handlers
   - Dispatch each line to the TextBox via `$window.Dispatcher.Invoke()` (thread-safe)
   - Set `EnableRaisingEvents = $true` and use the `Exited` event for completion detection — do NOT call `WaitForExit()` on the UI thread
5. On process exit: re-enable buttons, append completion/error message

When "Clean Only" is clicked:

1. Build CLI args: `--clean-only` plus verbosity flag only (no slider values, no `--no-cleanup`)
2. Same subprocess flow as above (steps 2-5)

## First-Run Tutorial

On launch, before showing the main window:
- Check if `Source/` directory is empty (no files)
- Check if `IWADs/` directory is empty, excluding `.gitkeep` files (matches CLI logic at unwad.cr line 135)
- If either is empty, show a setup dialog:
  - Step 1: Check if MonsterMash is inside an Obsidian directory by looking for `obsidian.exe` exactly 3 levels up from `$PSScriptRoot` (i.e., `$PSScriptRoot\..\..\..\obsidian.exe`), matching the logic in `tutorial.cr`
  - Step 2: Explain where to place WAD/PK3 and IWAD files, with buttons to open those folders
- After dialog closes, show main window regardless (user may want to add files and then click Run without restarting)

## Error Handling

- If `unwad.exe` not found at `Join-Path $PSScriptRoot 'unwad.exe'`: show error MessageBox and exit
- Non-zero exit code: append error line to output area
- Buttons stay disabled during processing to prevent double-runs

## Out of Scope

- Linux/macOS support (PowerShell/WPF is Windows-only; cross-platform frontends deferred)
- No changes to `unwad.exe` or any Crystal source files
