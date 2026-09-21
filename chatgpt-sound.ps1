Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type -AssemblyName WindowsBase

Add-Type @"
using System;
using System.Runtime.InteropServices;

public static class NativeInputV63 {
    [DllImport("user32.dll")]
    public static extern short GetAsyncKeyState(int vKey);

    [DllImport("user32.dll")]
    public static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll")]
    public static extern bool GetCursorPos(out POINT lpPoint);

    [StructLayout(LayoutKind.Sequential)]
    public struct POINT {
        public int X;
        public int Y;
    }
}
"@

Write-Host "ChatGPT Monitor v6.3 STARTED"
Write-Host "Press Ctrl+C to stop."
Write-Host ""

# =========================================================
# UNICODE STRINGS
# =========================================================

function Make-UnicodeString {
    param([int[]]$Codes)

    return -join (
        $Codes | ForEach-Object {
            [char]$_
        }
    )
}

# "Остановить"
$stopRu = Make-UnicodeString @(
    0x041E,0x0441,0x0442,0x0430,0x043D,
    0x043E,0x0432,0x0438,0x0442,0x044C
)

# "Отправить"
$sendRu = Make-UnicodeString @(
    0x041E,0x0442,0x043F,0x0440,0x0430,
    0x0432,0x0438,0x0442,0x044C
)

# "Расшифровать и отправить"
$transcribeSendRu = Make-UnicodeString @(
    0x0420,0x0430,0x0441,0x0448,0x0438,
    0x0444,0x0440,0x043E,0x0432,0x0430,
    0x0442,0x044C,0x0020,0x0438,0x0020,
    0x043E,0x0442,0x043F,0x0440,0x0430,
    0x0432,0x0438,0x0442,0x044C
)

$stopButtonNames = @(
    $stopRu,
    "Stop",
    "Stop generating"
)

$sendButtonNames = @(
    $sendRu,
    $transcribeSendRu,
    "Send"
)

# =========================================================
# SOUND
# =========================================================

$soundPath = Join-Path $PSScriptRoot "sound.wav"
$soundPlayer = $null

if (Test-Path $soundPath) {

    Write-Host "Sound file found:"
    Write-Host $soundPath

    try {

        $soundPlayer =
            New-Object System.Media.SoundPlayer

        $soundPlayer.SoundLocation =
            $soundPath

        $soundPlayer.Load()

        Write-Host "Sound loaded successfully."
    }
    catch {

        Write-Host "WARNING: sound could not be loaded."
        Write-Host $_.Exception.Message

        $soundPlayer = $null
    }
}
else {

    Write-Host "WARNING: sound.wav not found!"
    Write-Host $soundPath
}

Write-Host ""

# =========================================================
# SETTINGS
# =========================================================

$pollMilliseconds = 75

# Fast probing immediately after send.
$fastProbeMilliseconds = 2500
$fastProbeSleepMilliseconds = 25

# Normal Stop-based completion.
$finishConfirmSeconds = 1.5

# Fallback for background case.
# We do not trust Send returning immediately after send.
$fallbackMinimumSeconds = 5.0

# Send must remain visible for this long.
$fallbackStableSendSeconds = 2.0

$startTimeoutSeconds = 90
$totalTimeoutSeconds = 600

$cooldownSeconds = 4

$sendIconClasses = @(
    "icon-primary-action text-composer-primary",
    "icon-xs text-primary-solid"
)

# =========================================================
# STATE
# =========================================================

$armed = $false
$armedAt = $null

$stopSeen = $false
$stopMissingSince = $null

$sendWasMissing = $false
$stableSendSince = $null

$cooldownUntil = Get-Date

$lastEnterDown = $false
$lastMouseDown = $false

# =========================================================
# CHATGPT WINDOW
# =========================================================

function Get-ChatGPTProcess {

    Get-Process -ErrorAction SilentlyContinue |
        Where-Object {
            $_.MainWindowHandle -ne 0 -and
            (
                $_.ProcessName -like "*ChatGPT*" -or
                $_.MainWindowTitle -like "*ChatGPT*"
            )
        } |
        Select-Object -First 1
}

function Get-ChatGPTRoot {

    $p = Get-ChatGPTProcess

    if (-not $p) {
        return $null
    }

    try {

        return [System.Windows.Automation.AutomationElement]::FromHandle(
            $p.MainWindowHandle
        )
    }
    catch {

        return $null
    }
}

function Test-ChatGPTForeground {

    $p = Get-ChatGPTProcess

    if (-not $p) {
        return $false
    }

    $foreground =
        [NativeInputV63]::GetForegroundWindow()

    return (
        $foreground -eq
        [IntPtr]$p.MainWindowHandle
    )
}

# =========================================================
# BUTTON SEARCH
# =========================================================

function Test-ButtonNameExists {

    param(
        [string[]]$Names
    )

    $root = Get-ChatGPTRoot

    if (-not $root) {
        return $false
    }

    foreach ($targetName in $Names) {

        try {

            $nameCondition =
                New-Object System.Windows.Automation.PropertyCondition(
                    [System.Windows.Automation.AutomationElement]::NameProperty,
                    $targetName
                )

            $element =
                $root.FindFirst(
                    [System.Windows.Automation.TreeScope]::Descendants,
                    $nameCondition
                )

            if ($element) {

                try {

                    if (
                        $element.Current.ControlType -eq
                        [System.Windows.Automation.ControlType]::Button
                    ) {
                        return $true
                    }

                }
                catch {}
            }
        }
        catch {}
    }

    return $false
}

function Test-StopButton {

    return Test-ButtonNameExists `
        -Names $stopButtonNames
}

function Test-SendButton {

    return Test-ButtonNameExists `
        -Names $sendButtonNames
}

# =========================================================
# MOUSE SEND DETECTION
# =========================================================

function Test-SendButtonUnderCursor {

    try {

        $point =
            New-Object NativeInputV63+POINT

        [void][NativeInputV63]::GetCursorPos(
            [ref]$point
        )

        $automationPoint =
            New-Object System.Windows.Point(
                $point.X,
                $point.Y
            )

        $element =
            [System.Windows.Automation.AutomationElement]::FromPoint(
                $automationPoint
            )

        if (-not $element) {
            return $false
        }

        $walker =
            [System.Windows.Automation.TreeWalker]::ControlViewWalker

        $current = $element

        for ($i = 0; $i -lt 5; $i++) {

            if (-not $current) {
                break
            }

            try {

                $name =
                    $current.Current.Name

                if ($stopButtonNames -contains $name) {
                    return $false
                }

                if ($sendButtonNames -contains $name) {
                    return $true
                }

                $current =
                    $walker.GetParent($current)
            }
            catch {

                break
            }
        }

        return $false
    }
    catch {

        return $false
    }
}

# =========================================================
# SOUND
# =========================================================

function Play-DoneSound {

    Write-Host ""
    Write-Host "================================="
    Write-Host ">>> CHATGPT ANSWER FINISHED"
    Write-Host "================================="
    Write-Host ""

    if ($null -eq $script:soundPlayer) {

        Write-Host ">>> SOUND PLAYER NOT AVAILABLE"
        return
    }

    try {

        Write-Host ">>> PLAYING SOUND..."

        $script:soundPlayer.PlaySync()

        Write-Host ">>> SOUND PLAYBACK COMPLETE"
    }
    catch {

        Write-Host ">>> SOUND PLAYBACK ERROR:"
        Write-Host $_.Exception.Message
    }
}

# =========================================================
# RESET
# =========================================================

function Reset-Monitor {

    $script:armed = $false
    $script:armedAt = $null

    $script:stopSeen = $false
    $script:stopMissingSince = $null

    $script:sendWasMissing = $false
    $script:stableSendSince = $null
}

# =========================================================
# COMPLETE
# =========================================================

function Complete-Monitor {

    $now = Get-Date

    if ($now -ge $script:cooldownUntil) {

        Play-DoneSound

        $script:cooldownUntil =
            (Get-Date).AddSeconds(
                $cooldownSeconds
            )
    }
    else {

        Write-Host ">>> SOUND SKIPPED BY COOLDOWN"
    }

    Reset-Monitor

    Write-Host ">>> MONITOR DISARMED"
    Write-Host ">>> Waiting for next message send..."
}

# =========================================================
# FAST PROBE
# =========================================================

function Fast-ProbeForState {

    $started = Get-Date

    while (
        ((Get-Date) - $started).TotalMilliseconds -lt
        $fastProbeMilliseconds
    ) {

        if (Test-StopButton) {

            if (-not $script:stopSeen) {

                $script:stopSeen = $true
                $script:stopMissingSince = $null

                Write-Host ""
                Write-Host ">>> STOP BUTTON DETECTED"
                Write-Host ">>> CHATGPT IS WORKING"
                Write-Host ">>> FAST PROBE SUCCESS"
            }

            return
        }

        $sendExists =
            Test-SendButton

        if (-not $sendExists) {

            if (-not $script:sendWasMissing) {

                $script:sendWasMissing = $true

                Write-Host ""
                Write-Host ">>> SEND BUTTON NOT VISIBLE"
            }

            $script:stableSendSince = $null
        }

        Start-Sleep -Milliseconds $fastProbeSleepMilliseconds
    }

    Write-Host ">>> Fast probe ended"
    Write-Host ">>> Background monitoring continues"
}

# =========================================================
# ARM
# =========================================================

function Arm-Monitor {

    $script:armed = $true
    $script:armedAt = Get-Date

    $script:stopSeen = $false
    $script:stopMissingSince = $null

    $script:sendWasMissing = $false
    $script:stableSendSince = $null

    Write-Host ""
    Write-Host ">>> SEND ACTION DETECTED"
    Write-Host ">>> NEW MONITOR CYCLE"
    Write-Host ">>> FAST PROBE STARTED"

    Fast-ProbeForState
}

# =========================================================
# START
# =========================================================

Write-Host "Waiting for message send..."
Write-Host ""

while ($true) {

    $now = Get-Date

    # =====================================================
    # ENTER
    # =====================================================

    $enterState =
        [NativeInputV63]::GetAsyncKeyState(0x0D)

    $enterDown =
        ($enterState -band 0x8000) -ne 0

    $enterPressed =
        ($enterState -band 0x0001) -ne 0

    $shiftDown =
        (
            [NativeInputV63]::GetAsyncKeyState(0x10) -band
            0x8000
        ) -ne 0

    $newEnterPress =
        (
            $enterPressed -or
            (
                $enterDown -and
                -not $lastEnterDown
            )
        )

    if (
        $newEnterPress -and
        -not $shiftDown -and
        (Test-ChatGPTForeground)
    ) {

        Write-Host ""
        Write-Host ">>> ENTER PRESS DETECTED"

        Arm-Monitor
    }

    $lastEnterDown = $enterDown

    # =====================================================
    # MOUSE
    # =====================================================

    $mouseState =
        [NativeInputV63]::GetAsyncKeyState(0x01)

    $mouseDown =
        ($mouseState -band 0x8000) -ne 0

    $mousePressed =
        ($mouseState -band 0x0001) -ne 0

    $newMousePress =
        (
            $mousePressed -or
            (
                $mouseDown -and
                -not $lastMouseDown
            )
        )

    if (
        $newMousePress -and
        (Test-ChatGPTForeground)
    ) {

        if (Test-SendButtonUnderCursor) {

            Write-Host ""
            Write-Host ">>> SEND BUTTON CLICK DETECTED"

            Arm-Monitor
        }
    }

    $lastMouseDown = $mouseDown

    # =====================================================
    # IDLE
    # =====================================================

    if (-not $armed) {

        Start-Sleep -Milliseconds $pollMilliseconds
        continue
    }

    # =====================================================
    # TOTAL TIMEOUT
    # =====================================================

    if (
        (($now - $armedAt).TotalSeconds -ge
            $totalTimeoutSeconds)
    ) {

        Write-Host ""
        Write-Host ">>> TOTAL TIMEOUT"
        Write-Host ">>> MONITOR RESET"

        Reset-Monitor

        Start-Sleep -Milliseconds $pollMilliseconds
        continue
    }

    # =====================================================
    # CURRENT STATE
    # =====================================================

    $stopExists =
        Test-StopButton

    $sendExists =
        Test-SendButton

    # =====================================================
    # STOP MODE
    # =====================================================

    if ($stopExists) {

        $stableSendSince = $null
        $stopMissingSince = $null

        if (-not $stopSeen) {

            $stopSeen = $true

            Write-Host ""
            Write-Host ">>> STOP BUTTON DETECTED"
            Write-Host ">>> CHATGPT IS WORKING"
        }

        Start-Sleep -Milliseconds $pollMilliseconds
        continue
    }

    # =====================================================
    # STOP WAS SEEN AND NOW DISAPPEARED
    # =====================================================

    if ($stopSeen) {

        if ($null -eq $stopMissingSince) {

            $stopMissingSince = $now

            Write-Host ""
            Write-Host ">>> STOP BUTTON DISAPPEARED"
            Write-Host ">>> CONFIRMING COMPLETION..."
        }

        $missingTime =
            ($now - $stopMissingSince).TotalSeconds

        if (
            $missingTime -ge
            $finishConfirmSeconds
        ) {

            Complete-Monitor

            Start-Sleep -Milliseconds $pollMilliseconds
            continue
        }

        Start-Sleep -Milliseconds $pollMilliseconds
        continue
    }

    # =====================================================
    # FALLBACK MODE
    # No Stop was ever seen.
    # =====================================================

    $elapsed =
        ($now - $armedAt).TotalSeconds

    if (-not $sendExists) {

        $stableSendSince = $null

        if (-not $sendWasMissing) {

            $sendWasMissing = $true

            Write-Host ""
            Write-Host ">>> SEND BUTTON NOT VISIBLE"
            Write-Host ">>> FALLBACK WORK STATE"
        }

        Start-Sleep -Milliseconds $pollMilliseconds
        continue
    }

    # Do not accept Send immediately after message send.
    if (
        $elapsed -lt
        $fallbackMinimumSeconds
    ) {

        $stableSendSince = $null

        Start-Sleep -Milliseconds $pollMilliseconds
        continue
    }

    # Send is visible after minimum fallback time.
    if ($null -eq $stableSendSince) {

        $stableSendSince = $now

        Write-Host ""
        Write-Host ">>> SEND BUTTON VISIBLE"
        Write-Host ">>> FALLBACK STABILITY CHECK..."
    }

    $stableTime =
        ($now - $stableSendSince).TotalSeconds

    if (
        $stableTime -ge
        $fallbackStableSendSeconds
    ) {

        Write-Host ">>> FALLBACK COMPLETION CONFIRMED"

        Complete-Monitor

        Start-Sleep -Milliseconds $pollMilliseconds
        continue
    }

    # =====================================================
    # START TIMEOUT
    # =====================================================

    if (
        $elapsed -ge
        $startTimeoutSeconds
    ) {

        Write-Host ""
        Write-Host ">>> NO USABLE GENERATION STATE"
        Write-Host ">>> MONITOR RESET"

        Reset-Monitor
    }

    Start-Sleep -Milliseconds $pollMilliseconds
}