# PowerShell WPF GUI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create a single PowerShell/WPF script (`MonsterMash.ps1`) that provides a GUI frontend to `unwad.exe` with the same layout as the previous GTK4 GUI.

**Architecture:** One `.ps1` file defines WPF XAML inline, creates the window, wires event handlers to build CLI args and launch `unwad.exe` as a subprocess with real-time output streaming. No external dependencies — uses only PowerShell 5.1+ and built-in .NET/WPF assemblies.

**Tech Stack:** PowerShell 5.1+, WPF (`PresentationFramework`), `System.Diagnostics.Process`

**Spec:** `docs/superpowers/specs/2026-03-25-powershell-gui-design.md`

---

## File Structure

- **Create:** `MonsterMash/MonsterMash.ps1` — entire GUI in one file

No other files are created or modified (except `.gitignore` to allowlist the `.ps1`).

## PowerShell Scoping Notes

All widget references and path variables are declared at **script scope** using `$script:` prefix so they are accessible from functions and event handlers. `Register-ObjectEvent -Action` blocks run in a separate runspace and cannot access script-scope variables — these must receive references via `-MessageData` and access them through `$Event.MessageData`. WPF `Add_Click` handlers run on the UI thread in the same scope, so `$script:` variables are accessible.

**Important:** Never use `$args` as a variable name in PowerShell — it is a reserved automatic variable. Use `$cmdArgs` instead.

---

### Task 1: Window Shell with XAML Layout

Create the `.ps1` file with the WPF window definition containing all widgets but no event handlers yet.

**Files:**
- Create: `MonsterMash/MonsterMash.ps1`

- [ ] **Step 1: Create MonsterMash.ps1 with XAML layout and window display**

```powershell
###############################################################################
# MonsterMash.ps1 — WPF GUI frontend for unwad.exe
#
# Launches a WPF window with slider controls, options, and output display.
# Builds CLI args from widget values and runs unwad.exe as a subprocess.
#
# Usage: Right-click -> Run with PowerShell, or: powershell -File MonsterMash.ps1
###############################################################################

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

###############################################################################
# PATH RESOLUTION — all paths relative to script directory
###############################################################################

$script:scriptDir = $PSScriptRoot
$script:unwadExe  = Join-Path $script:scriptDir 'unwad.exe'
$script:sourceDir = Join-Path $script:scriptDir 'Source'
$script:iwadsDir  = Join-Path $script:scriptDir 'IWADs'

# Verify unwad.exe exists
if (-not (Test-Path $script:unwadExe)) {
    [System.Windows.MessageBox]::Show(
        "unwad.exe not found in:`n$($script:scriptDir)`n`nMonsterMash.ps1 must be in the same directory as unwad.exe.",
        "MonsterMash - Error",
        [System.Windows.MessageBoxButton]::OK,
        [System.Windows.MessageBoxImage]::Error
    )
    exit 1
}

###############################################################################
# XAML LAYOUT
###############################################################################

[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Unwad V2 -- Monster Mash WAD Processor"
        Width="720" Height="700"
        MinWidth="500" MinHeight="550"
        WindowStartupLocation="CenterScreen">
  <Grid Margin="12">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
    </Grid.RowDefinitions>

    <!-- Row 0: Folder Buttons -->
    <StackPanel Grid.Row="0" Orientation="Horizontal" Margin="0,0,0,8">
      <Button Name="btnSource" Content="Open Source Folder" Padding="12,4" Margin="0,0,8,0"/>
      <Button Name="btnIWADs" Content="Open IWADs Folder" Padding="12,4"/>
    </StackPanel>

    <!-- Row 1: Slider Defaults -->
    <GroupBox Grid.Row="1" Header="Slider Defaults" Margin="0,0,0,8" Padding="8">
      <Grid Name="sliderGrid">
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="80"/>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="50"/>
        </Grid.ColumnDefinitions>
        <Grid.RowDefinitions>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <!-- Weapon -->
        <TextBlock Grid.Row="0" Grid.Column="0" Text="Weapon:" VerticalAlignment="Center"/>
        <Slider Name="sliderWeapon" Grid.Row="0" Grid.Column="1" Minimum="0" Maximum="20"
                Value="0" TickFrequency="0.02" IsSnapToTickEnabled="True" Margin="4,2"/>
        <TextBlock Name="lblWeapon" Grid.Row="0" Grid.Column="2" Text="0.00"
                   VerticalAlignment="Center" HorizontalAlignment="Right" FontFamily="Consolas"/>

        <!-- Monster -->
        <TextBlock Grid.Row="1" Grid.Column="0" Text="Monster:" VerticalAlignment="Center"/>
        <Slider Name="sliderMonster" Grid.Row="1" Grid.Column="1" Minimum="0" Maximum="20"
                Value="1" TickFrequency="0.02" IsSnapToTickEnabled="True" Margin="4,2"/>
        <TextBlock Name="lblMonster" Grid.Row="1" Grid.Column="2" Text="1.00"
                   VerticalAlignment="Center" HorizontalAlignment="Right" FontFamily="Consolas"/>

        <!-- Ally -->
        <TextBlock Grid.Row="2" Grid.Column="0" Text="Ally:" VerticalAlignment="Center"/>
        <Slider Name="sliderAlly" Grid.Row="2" Grid.Column="1" Minimum="0" Maximum="20"
                Value="1" TickFrequency="0.02" IsSnapToTickEnabled="True" Margin="4,2"/>
        <TextBlock Name="lblAlly" Grid.Row="2" Grid.Column="2" Text="1.00"
                   VerticalAlignment="Center" HorizontalAlignment="Right" FontFamily="Consolas"/>

        <!-- Ammo -->
        <TextBlock Grid.Row="3" Grid.Column="0" Text="Ammo:" VerticalAlignment="Center"/>
        <Slider Name="sliderAmmo" Grid.Row="3" Grid.Column="1" Minimum="0" Maximum="20"
                Value="10" TickFrequency="0.02" IsSnapToTickEnabled="True" Margin="4,2"/>
        <TextBlock Name="lblAmmo" Grid.Row="3" Grid.Column="2" Text="10.00"
                   VerticalAlignment="Center" HorizontalAlignment="Right" FontFamily="Consolas"/>

        <!-- Nice Item -->
        <TextBlock Grid.Row="4" Grid.Column="0" Text="Nice Item:" VerticalAlignment="Center"/>
        <Slider Name="sliderNiceItem" Grid.Row="4" Grid.Column="1" Minimum="0" Maximum="20"
                Value="0.3" TickFrequency="0.02" IsSnapToTickEnabled="True" Margin="4,2"/>
        <TextBlock Name="lblNiceItem" Grid.Row="4" Grid.Column="2" Text="0.30"
                   VerticalAlignment="Center" HorizontalAlignment="Right" FontFamily="Consolas"/>

        <!-- Pickup -->
        <TextBlock Grid.Row="5" Grid.Column="0" Text="Pickup:" VerticalAlignment="Center"/>
        <Slider Name="sliderPickup" Grid.Row="5" Grid.Column="1" Minimum="0" Maximum="20"
                Value="0.3" TickFrequency="0.02" IsSnapToTickEnabled="True" Margin="4,2"/>
        <TextBlock Name="lblPickup" Grid.Row="5" Grid.Column="2" Text="0.30"
                   VerticalAlignment="Center" HorizontalAlignment="Right" FontFamily="Consolas"/>
      </Grid>
    </GroupBox>

    <!-- Row 2: Options -->
    <StackPanel Grid.Row="2" Orientation="Horizontal" Margin="0,0,0,8">
      <CheckBox Name="chkSkipCleanup" Content="Skip post-run cleanup" VerticalAlignment="Center" Margin="0,0,16,0"/>
      <TextBlock Text="Verbosity:" VerticalAlignment="Center" Margin="0,0,8,0"/>
      <ComboBox Name="cmbVerbosity" Width="120" SelectedIndex="0">
        <ComboBoxItem Content="Errors only"/>
        <ComboBoxItem Content="Warnings"/>
        <ComboBoxItem Content="Info"/>
        <ComboBoxItem Content="Debug"/>
      </ComboBox>
    </StackPanel>

    <!-- Row 3: Action Buttons -->
    <StackPanel Grid.Row="3" Orientation="Horizontal" Margin="0,0,0,8">
      <Button Name="btnRun" Content="Run Unwad" Padding="16,6" Margin="0,0,8,0"
              FontWeight="Bold" Background="#0078D4" Foreground="White"/>
      <Button Name="btnClean" Content="Clean Only" Padding="16,6"/>
    </StackPanel>

    <!-- Row 4: Output Label -->
    <TextBlock Grid.Row="4" Text="Output" Margin="0,0,0,4"/>

    <!-- Row 5: Output TextBox -->
    <TextBox Grid.Row="5" Name="txtOutput" IsReadOnly="True"
             FontFamily="Consolas" FontSize="12"
             VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto"
             TextWrapping="Wrap" AcceptsReturn="True"/>
  </Grid>
</Window>
"@

###############################################################################
# CREATE WINDOW FROM XAML
###############################################################################

$reader = New-Object System.Xml.XmlNodeReader $xaml
$script:window = [System.Windows.Markup.XamlReader]::Load($reader)

# Get widget references (script-scoped for access from functions/handlers)
$script:btnSource      = $script:window.FindName("btnSource")
$script:btnIWADs       = $script:window.FindName("btnIWADs")
$script:sliderWeapon   = $script:window.FindName("sliderWeapon")
$script:sliderMonster  = $script:window.FindName("sliderMonster")
$script:sliderAlly     = $script:window.FindName("sliderAlly")
$script:sliderAmmo     = $script:window.FindName("sliderAmmo")
$script:sliderNiceItem = $script:window.FindName("sliderNiceItem")
$script:sliderPickup   = $script:window.FindName("sliderPickup")
$script:lblWeapon      = $script:window.FindName("lblWeapon")
$script:lblMonster     = $script:window.FindName("lblMonster")
$script:lblAlly        = $script:window.FindName("lblAlly")
$script:lblAmmo        = $script:window.FindName("lblAmmo")
$script:lblNiceItem    = $script:window.FindName("lblNiceItem")
$script:lblPickup      = $script:window.FindName("lblPickup")
$script:chkSkipCleanup = $script:window.FindName("chkSkipCleanup")
$script:cmbVerbosity   = $script:window.FindName("cmbVerbosity")
$script:btnRun         = $script:window.FindName("btnRun")
$script:btnClean       = $script:window.FindName("btnClean")
$script:txtOutput      = $script:window.FindName("txtOutput")

###############################################################################
# SHOW WINDOW
###############################################################################

$script:window.ShowDialog() | Out-Null
```

- [ ] **Step 2: Test the window displays correctly**

Run from PowerShell in the MonsterMash directory:
```powershell
powershell -ExecutionPolicy Bypass -File MonsterMash.ps1
```
Expected: Window appears with all widgets visible — folder buttons, 6 sliders with labels and readouts, checkbox, dropdown, Run/Clean buttons, and an empty output area. Closing the window exits cleanly.

- [ ] **Step 3: Commit**

```bash
git add MonsterMash/MonsterMash.ps1
git commit -m "feat: add PowerShell WPF GUI window with full widget layout"
```

---

### Task 2: Slider Value Readout Updates

Wire each slider's `ValueChanged` event to update its corresponding label with 2 decimal places.

**Files:**
- Modify: `MonsterMash/MonsterMash.ps1`

- [ ] **Step 1: Add slider ValueChanged handlers**

Insert this block after the widget references section (before `$script:window.ShowDialog()`):

```powershell
###############################################################################
# SLIDER VALUE READOUT HANDLERS
###############################################################################

$sliderNames = @("Weapon", "Monster", "Ally", "Ammo", "NiceItem", "Pickup")
foreach ($name in $sliderNames) {
    $slider = $script:window.FindName("slider$name")
    $slider.Add_ValueChanged({
        param($sender, $e)
        $lbl = $script:window.FindName("lbl" + $sender.Name.Replace("slider", ""))
        if ($lbl) { $lbl.Text = $sender.Value.ToString("F2") }
    }.GetNewClosure())
}
```

- [ ] **Step 2: Test slider readouts update**

Run `MonsterMash.ps1`. Drag each slider and verify the value label to the right updates in real-time showing 2 decimal places (e.g., "0.30", "10.00", "5.46").

- [ ] **Step 3: Commit**

```bash
git add MonsterMash/MonsterMash.ps1
git commit -m "feat: wire slider value readout labels"
```

---

### Task 3: Folder Buttons

Wire the "Open Source Folder" and "Open IWADs Folder" buttons to open `explorer.exe`.

**Files:**
- Modify: `MonsterMash/MonsterMash.ps1`

- [ ] **Step 1: Add folder button click handlers**

Insert after the slider handlers section:

```powershell
###############################################################################
# FOLDER BUTTON HANDLERS
###############################################################################

$script:btnSource.Add_Click({
    if (-not (Test-Path $script:sourceDir)) { New-Item -ItemType Directory -Path $script:sourceDir -Force | Out-Null }
    Start-Process explorer.exe -ArgumentList $script:sourceDir
})

$script:btnIWADs.Add_Click({
    if (-not (Test-Path $script:iwadsDir)) { New-Item -ItemType Directory -Path $script:iwadsDir -Force | Out-Null }
    Start-Process explorer.exe -ArgumentList $script:iwadsDir
})
```

- [ ] **Step 2: Test folder buttons**

Run `MonsterMash.ps1`. Click "Open Source Folder" — Explorer should open to `MonsterMash/Source/`. Click "Open IWADs Folder" — Explorer should open to `MonsterMash/IWADs/`. Both directories should be created if they don't exist.

- [ ] **Step 3: Commit**

```bash
git add MonsterMash/MonsterMash.ps1
git commit -m "feat: wire folder open buttons"
```

---

### Task 4: Subprocess Execution (Run Unwad and Clean Only)

Wire both action buttons to build CLI args, launch `unwad.exe`, and stream output to the TextBox in real-time. Uses `Register-ObjectEvent` with `-MessageData` to pass UI references into the separate runspace where event handlers execute.

**Files:**
- Modify: `MonsterMash/MonsterMash.ps1`

- [ ] **Step 1: Add the Start-Unwad function and both button handlers**

Insert after the folder button handlers:

```powershell
###############################################################################
# SUBPROCESS EXECUTION
###############################################################################

# Track event subscriptions so we can clean them up between runs
$script:eventJobs = @()

# Launches unwad.exe with the given argument list, streams output to txtOutput.
# Disables buttons during execution, re-enables on completion.
function Start-Unwad {
    param([string[]]$Arguments)

    # Disable buttons and clear output
    $script:btnRun.IsEnabled = $false
    $script:btnClean.IsEnabled = $false
    $script:txtOutput.Text = ""

    # Clean up any previous event subscriptions
    foreach ($job in $script:eventJobs) {
        Unregister-Event -SourceIdentifier $job.Name -ErrorAction SilentlyContinue
        Remove-Job -Id $job.Id -Force -ErrorAction SilentlyContinue
    }
    $script:eventJobs = @()

    # Build ProcessStartInfo
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $script:unwadExe
    $psi.Arguments = $Arguments -join ' '
    $psi.WorkingDirectory = $script:scriptDir
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $psi.StandardErrorEncoding = [System.Text.Encoding]::UTF8

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $psi
    $process.EnableRaisingEvents = $true

    # Bundle UI references for event handlers (they run in a separate runspace
    # and cannot access $script: variables — must use $Event.MessageData)
    $handlerData = @{
        Window    = $script:window
        TxtOutput = $script:txtOutput
        BtnRun    = $script:btnRun
        BtnClean  = $script:btnClean
    }

    # Async output handler — dispatches to UI thread via Dispatcher.Invoke
    $script:eventJobs += Register-ObjectEvent -InputObject $process `
        -EventName OutputDataReceived -MessageData $handlerData -Action {
        if ($null -ne $EventArgs.Data) {
            $d = $Event.MessageData
            $d.Window.Dispatcher.Invoke([Action]{
                $d.TxtOutput.AppendText($EventArgs.Data + "`r`n")
                $d.TxtOutput.ScrollToEnd()
            })
        }
    }

    $script:eventJobs += Register-ObjectEvent -InputObject $process `
        -EventName ErrorDataReceived -MessageData $handlerData -Action {
        if ($null -ne $EventArgs.Data) {
            $d = $Event.MessageData
            $d.Window.Dispatcher.Invoke([Action]{
                $d.TxtOutput.AppendText($EventArgs.Data + "`r`n")
                $d.TxtOutput.ScrollToEnd()
            })
        }
    }

    # Process exit handler — re-enable buttons, show status
    $script:eventJobs += Register-ObjectEvent -InputObject $process `
        -EventName Exited -MessageData $handlerData -Action {
        $proc = $sender
        $proc.WaitForExit()
        $exitCode = $proc.ExitCode
        $d = $Event.MessageData
        $d.Window.Dispatcher.Invoke([Action]{
            if ($exitCode -ne 0) {
                $d.TxtOutput.AppendText("`r`n[ERROR] unwad.exe exited with code $exitCode`r`n")
            }
            $d.TxtOutput.AppendText("`r`n=== Process finished ===`r`n")
            $d.TxtOutput.ScrollToEnd()
            $d.BtnRun.IsEnabled = $true
            $d.BtnClean.IsEnabled = $true
        })
    }

    # Start the process and begin async reads
    $process.Start() | Out-Null
    $process.BeginOutputReadLine()
    $process.BeginErrorReadLine()
}

###############################################################################
# ACTION BUTTON HANDLERS
###############################################################################

$script:btnRun.Add_Click({
    # Build argument list (use $cmdArgs — never use $args, it's a reserved variable)
    $cmdArgs = @()

    # Slider values — format to 2 decimal places to pass CLI validation
    $cmdArgs += "--weapon-default="    + $script:sliderWeapon.Value.ToString("F2")
    $cmdArgs += "--monster-default="   + $script:sliderMonster.Value.ToString("F2")
    $cmdArgs += "--ally-default="      + $script:sliderAlly.Value.ToString("F2")
    $cmdArgs += "--ammo-default="      + $script:sliderAmmo.Value.ToString("F2")
    $cmdArgs += "--nice-item-default=" + $script:sliderNiceItem.Value.ToString("F2")
    $cmdArgs += "--pickup-default="    + $script:sliderPickup.Value.ToString("F2")

    # Cleanup checkbox
    if ($script:chkSkipCleanup.IsChecked -eq $true) { $cmdArgs += "--no-cleanup" }

    # Verbosity
    switch ($script:cmbVerbosity.SelectedIndex) {
        1 { $cmdArgs += "-v" }
        2 { $cmdArgs += "-vv" }
        3 { $cmdArgs += "-vvv" }
    }

    Start-Unwad -Arguments $cmdArgs
})

$script:btnClean.Add_Click({
    # Clean Only: only --clean-only + verbosity (no slider values, no --no-cleanup)
    $cmdArgs = @("--clean-only")

    switch ($script:cmbVerbosity.SelectedIndex) {
        1 { $cmdArgs += "-v" }
        2 { $cmdArgs += "-vv" }
        3 { $cmdArgs += "-vvv" }
    }

    Start-Unwad -Arguments $cmdArgs
})
```

- [ ] **Step 2: Test Run Unwad button**

Run `MonsterMash.ps1`. Ensure `Source/` and `IWADs/` have at least one WAD file each (or it will trigger the tutorial output). Click "Run Unwad". Verify:
- Both buttons become disabled
- Output streams line-by-line into the text area in real-time
- Buttons re-enable when processing completes
- "=== Process finished ===" appears at the end

- [ ] **Step 3: Test Clean Only button**

Click "Clean Only". Verify output shows cleanup messages and buttons re-enable after completion.

- [ ] **Step 4: Test multiple consecutive runs**

Click "Run Unwad", wait for completion, then click it again. Verify output lines are NOT duplicated (event subscriptions are cleaned up between runs).

- [ ] **Step 5: Commit**

```bash
git add MonsterMash/MonsterMash.ps1
git commit -m "feat: wire action buttons with async subprocess output streaming"
```

---

### Task 5: First-Run Tutorial Dialog

Show a setup dialog when `Source/` or `IWADs/` is empty on launch.

**Files:**
- Modify: `MonsterMash/MonsterMash.ps1`

- [ ] **Step 1: Add tutorial check and dialog**

Insert after the `unwad.exe` existence check and before the XAML definition:

```powershell
###############################################################################
# FIRST-RUN TUTORIAL CHECK
###############################################################################

# Ensure directories exist
if (-not (Test-Path $script:sourceDir)) { New-Item -ItemType Directory -Path $script:sourceDir -Force | Out-Null }
if (-not (Test-Path $script:iwadsDir))  { New-Item -ItemType Directory -Path $script:iwadsDir -Force | Out-Null }

$sourceEmpty = @(Get-ChildItem -Path $script:sourceDir -File -ErrorAction SilentlyContinue).Count -eq 0
$iwadsEmpty  = @(Get-ChildItem -Path $script:iwadsDir -File -ErrorAction SilentlyContinue |
                  Where-Object { $_.Name -ne '.gitkeep' }).Count -eq 0

if ($sourceEmpty -or $iwadsEmpty) {
    # Step 1: Obsidian installation check (3 levels up from script dir)
    $obsidianExe = Join-Path $script:scriptDir '..\..\..\obsidian.exe'
    $obsidianFound = Test-Path $obsidianExe

    if ($obsidianFound) {
        $step1Text = "MonsterMash is correctly installed inside your Obsidian folder."
    } else {
        $step1Text = @"
MonsterMash is running in STANDALONE mode.

If you plan to use MonsterMash with Obsidian, the addon must be placed at:
  obsidian-<version>\addons\MonsterMash\MonsterMash\unwad.exe

Running standalone is fine for processing WADs/PK3s, but the generated
monster_mash.lua will need to be copied to Obsidian manually afterwards.
"@
    }

    # Step 2: File placement instructions
    $step2Text = @"
SOURCE DIRECTORY (PWADs, mods, custom content):
  $($script:sourceDir)

Copy your custom WAD and PK3 files here. These are third-party mods,
monster packs, and weapon packs.

Supported formats: .wad .pk3 .pk7 .zip .ipk3 .ipk7


IWADs DIRECTORY (base game WADs):
  $($script:iwadsDir)

Copy your official id Software IWAD files here. MonsterMash uses these
to read built-in actor definitions.

Supported IWADs: DOOM.WAD, DOOM2.WAD, TNT.WAD, PLUTONIA.WAD,
HERETIC.WAD, HEXEN.WAD, CHEX.WAD
"@

    $fullMessage = @"
MonsterMash -- First-Time Setup

Step 1: Obsidian Check
$step1Text

Step 2: Where To Put Your Files
$step2Text

Click OK, then use the folder buttons in the main window to add your files.
"@

    [System.Windows.MessageBox]::Show(
        $fullMessage,
        "MonsterMash - First-Time Setup",
        [System.Windows.MessageBoxButton]::OK,
        [System.Windows.MessageBoxImage]::Information
    )
}
```

- [ ] **Step 2: Test tutorial dialog**

Temporarily empty the `Source/` and `IWADs/` directories. Run `MonsterMash.ps1`. Verify:
- A setup dialog appears before the main window
- It shows the Obsidian check result (found or standalone mode)
- It shows file placement instructions with correct directory paths
- After clicking OK, the main window appears normally

- [ ] **Step 3: Commit**

```bash
git add MonsterMash/MonsterMash.ps1
git commit -m "feat: add first-run tutorial dialog"
```

---

### Task 6: Gitignore and Final Commit

Add the `.ps1` file to the gitignore allowlist and push.

**Files:**
- Modify: `.gitignore`

- [ ] **Step 1: Add MonsterMash.ps1 to gitignore allowlist**

Add this line after the `!MonsterMash/unwad.exe` line in `.gitignore`:

```
!MonsterMash/MonsterMash.ps1
```

- [ ] **Step 2: Verify MonsterMash.ps1 is visible to git**

```bash
git status
```

Expected: `.gitignore` and `MonsterMash/MonsterMash.ps1` (if not already committed) show as trackable.

- [ ] **Step 3: Commit and push**

```bash
git add .gitignore
git commit -m "chore: add MonsterMash.ps1 to gitignore allowlist"
git push origin main
```

---

## Testing Checklist (Manual)

After all tasks are complete, run through this end-to-end:

1. **Launch:** `powershell -ExecutionPolicy Bypass -File MonsterMash.ps1`
2. **First-run:** With empty Source/IWADs — tutorial dialog appears with correct paths
3. **Sliders:** Drag each slider, verify readout updates to 2 decimal places
4. **Folder buttons:** Both open Explorer to correct directories
5. **Run Unwad:** With WADs in Source/ and IWADs/ — output streams in real-time, buttons disable/re-enable
6. **Clean Only:** Runs cleanup, output shows in text area
7. **Verbosity:** Change dropdown to Debug, run again — verify more verbose output
8. **Skip cleanup:** Check the box, run — verify Processing/ etc. are preserved after run
9. **Window resize:** Verify output area expands, sliders stretch
10. **Multiple runs:** Click Run twice in a row — verify no duplicate output lines on second run
