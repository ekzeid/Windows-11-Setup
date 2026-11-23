<# : batch
@echo off
setlocal DisableDelayedExpansion
set "FLN_TWEAKER_FILE=%~f0"
chcp 65001 >nul
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -Command "try { & ([scriptblock]::Create([IO.File]::ReadAllText($env:FLN_TWEAKER_FILE,[Text.Encoding]::UTF8))) $env:FLN_TWEAKER_FILE } catch { Write-Host $_.Exception.Message -ForegroundColor Red; if (-not $env:FLN_TWEAKER_TEST) { $null=Read-Host 'Enter' }; exit 1 }"
exit /b %errorlevel%
#>
param([string]$launcherPath, [string]$expectedSid)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8
if (-not $env:FLN_TWEAKER_TEST) {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    if ($expectedSid -and $identity.User.Value -ne $expectedSid) {
        throw 'Запусти утилиту с правами администратора той же учётной записи Windows.'
    }
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        if ($expectedSid) { throw 'Для изменения системных настроек нужны права администратора.' }
        $bootstrap = {
            try {
                $path = [Text.Encoding]::Unicode.GetString([Convert]::FromBase64String('__PATH__'))
                & ([scriptblock]::Create([IO.File]::ReadAllText($path, [Text.Encoding]::UTF8))) $path '__SID__'
            } catch {
                Write-Host $_.Exception.Message -ForegroundColor Red
                $null = Read-Host 'Enter'
                exit 1
            }
        }
        $path64 = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($launcherPath))
        $code = $bootstrap.ToString().Replace('__PATH__', $path64).Replace('__SID__', $identity.User.Value)
        $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($code))
        Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -ArgumentList '-NoProfile','-EncodedCommand',$encoded -Verb RunAs
        return
    }
}

# Шрифт консоли с кириллицей: на системах с en-US локалью conhost берёт растровый шрифт, и русский текст превращается в кракозябры
if (-not $env:FLN_TWEAKER_TEST) { try {
    Add-Type -Namespace FlnCon -Name Font -MemberDefinition @'
[StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
public struct CFI { public uint cbSize; public uint nFont; public short X; public short Y; public int Family; public int Weight;
  [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string Face; }
[DllImport("kernel32.dll", SetLastError = true)] public static extern IntPtr GetStdHandle(int h);
[DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)] public static extern bool SetCurrentConsoleFontEx(IntPtr h, bool max, ref CFI f);
public static void Set(string face, short size) {
  var f = new CFI(); f.cbSize = (uint)Marshal.SizeOf(f); f.Y = size; f.Family = 54; f.Weight = 400; f.Face = face;
  SetCurrentConsoleFontEx(GetStdHandle(-11), false, ref f); }
'@ -ErrorAction Stop
    [FlnCon.Font]::Set('Consolas', 16)
} catch {}
$Host.UI.RawUI.WindowTitle = 'fln tweaker'
}

function RegGet($path, $name) {
    if (-not (Test-Path -LiteralPath $path -ErrorAction Stop)) { return $null }
    $key = Get-Item -LiteralPath $path -ErrorAction Stop
    try { return ,$key.GetValue($name, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames) }
    finally { $key.Dispose() }
}
function RegSet($path, $name, $value, $type = 'DWord') {
    if (-not (Test-Path -LiteralPath $path -ErrorAction Stop)) { New-Item -Path $path -Force -ErrorAction Stop | Out-Null }
    New-ItemProperty -LiteralPath $path -Name $name -Value $value -PropertyType $type -Force -ErrorAction Stop | Out-Null
}
function RegDel($path, $name) {
    if ($null -ne (RegGet $path $name)) {
        Remove-ItemProperty -LiteralPath $path -Name $name -Force -ErrorAction Stop
    }
}

function Read-Choice($prompt) {
    return ([string](Read-Host $prompt)).Trim().ToUpperInvariant()
}

function Get-TweakState($tweak) {
    & $tweak.Test $tweak
}

function Invoke-Tweak($tweak, [switch]$EnableOnly) {
    try {
        $wasEnabled = Get-TweakState $tweak
        if ($null -eq $wasEnabled) { throw 'Настройка недоступна.' }
        if ($EnableOnly -and $wasEnabled) { return }
        if ($wasEnabled) { & $tweak.Off $tweak } else { & $tweak.On $tweak }
        if ((Get-TweakState $tweak) -ne (-not $wasEnabled)) { throw 'Проверка после изменения не подтвердила новое состояние.' }
        Write-Host "   $($tweak.Name) — изменено" -ForegroundColor Green
    } catch {
        Write-Host "   $($tweak.Name) — $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

function Show-TweakStatus($tweak, $number) {
    try {
        $status = Get-TweakState $tweak
        if ($null -eq $status) { $label = ' Н/Д  '; $color = 'DarkGray' }
        elseif ($status) { $label = ' ВКЛ  '; $color = 'Green' }
        else { $label = ' ВЫКЛ '; $color = 'Red' }
    } catch { $label = '  ?   '; $color = 'Yellow' }
    Write-Host ("   [{0,2}] " -f $number) -NoNewline
    Write-Host $label -ForegroundColor $color -NoNewline
    Write-Host ('  ' + $tweak.Name)
    Write-Host ('             ' + $tweak.Hint) -ForegroundColor DarkGray
}

$HighPerf ='8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
$Balanced = '381b4222-f694-41f0-9685-ff5bb260df2e'
$CDM      = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
$CdmKeys  = 'SubscribedContent-338388Enabled','SubscribedContent-338389Enabled','SubscribedContent-353698Enabled',
            'SystemPaneSuggestionsEnabled','SilentInstalledAppsEnabled','SoftLandingEnabled'

function Set-ActivePowerScheme($scheme, [switch]$CreateIfMissing) {
    $ErrorActionPreference = 'Continue'
    $null = powercfg /setactive $scheme 2>$null
    if ($LASTEXITCODE -eq 0) { return }
    if ($CreateIfMissing) {
        $null = powercfg /duplicatescheme $scheme $scheme 2>$null
        if ($LASTEXITCODE -eq 0) {
            $null = powercfg /setactive $scheme 2>$null
            if ($LASTEXITCODE -eq 0) { return }
        }
    }
    throw "Не удалось активировать схему питания ($scheme)."
}

$Tweaks = @(
    @{
        Name = 'Power Plan: High Performance'
        Hint = 'переключает схему питания Windows'
        Test = {
            $scheme = powercfg /getactivescheme
            if ($LASTEXITCODE -ne 0) { throw 'Не удалось прочитать активную схему питания.' }
            return ($scheme -join ' ') -match $HighPerf
        }
        On = { Set-ActivePowerScheme $HighPerf -CreateIfMissing }
        Off = { Set-ActivePowerScheme $Balanced }
    },
    @{
        Name = 'Background UWP Apps: Disabled'
        Hint = 'фоновые приложения Windows не работают'
        Test = {
            ((RegGet 'HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications' 'GlobalUserDisabled') -eq 1) -and
            ((RegGet 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' 'BackgroundAppGlobalToggle') -eq 0)
        }
        On   = {
            RegSet 'HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications' 'GlobalUserDisabled' 1
            RegSet 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' 'BackgroundAppGlobalToggle' 0
        }
        Off  = {
            RegSet 'HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications' 'GlobalUserDisabled' 0
            RegSet 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' 'BackgroundAppGlobalToggle' 1
        }
    },
    @{
        Name = 'Delivery Optimization: Disabled'
        Hint = 'выключает загрузку обновлений с других компьютеров'
        Test = { (RegGet 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization' 'DODownloadMode') -eq 0 }
        On   = { RegSet 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization' 'DODownloadMode' 0 }
        Off  = { RegDel 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization' 'DODownloadMode' }
    },
    @{
        Name = 'Diagnostics & Ads: Limited'
        Hint = 'задаёт политику диагностики и отключает DiagTrack, рекламный ID и советы'
        Test = {
            if (((RegGet 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'AllowTelemetry') -ne 0) -or
                ((RegGet 'HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo' 'Enabled') -ne 0) -or
                ((RegGet 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy' 'TailoredExperiencesWithDiagnosticDataEnabled') -ne 0) -or
                ((RegGet 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'Start_IrisRecommendations') -ne 0)) { return $false }
            foreach ($key in $CdmKeys) { if ((RegGet $CDM $key) -ne 0) { return $false } }
            $service = Get-Service DiagTrack -ErrorAction Stop
            return $service.StartType -eq 'Disabled' -and $service.Status -eq 'Stopped' 
        }
        On   = {
            RegSet 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'AllowTelemetry' 0
            RegSet 'HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo' 'Enabled' 0
            RegSet 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy' 'TailoredExperiencesWithDiagnosticDataEnabled' 0
            RegSet 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'Start_IrisRecommendations' 0
            foreach ($k in $CdmKeys) { RegSet $CDM $k 0 }
            Stop-Service DiagTrack -Force -ErrorAction Stop
            Set-Service DiagTrack -StartupType Disabled -ErrorAction Stop
        }
        Off  = {
            RegDel 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'AllowTelemetry'
            RegSet 'HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo' 'Enabled' 1
            RegSet 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy' 'TailoredExperiencesWithDiagnosticDataEnabled' 1
            RegSet 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'Start_IrisRecommendations' 1
            foreach ($k in $CdmKeys) { RegSet $CDM $k 1 }
            Set-Service DiagTrack -StartupType Automatic -ErrorAction Stop
            Start-Service DiagTrack -ErrorAction Stop
        }
    },
    @{
        Name = 'Menu Show Delay: 400ms -> 20ms'
        Hint = 'уменьшает задержку раскрытия подменю до 20 мс'
        Test = { (RegGet 'HKCU:\Control Panel\Desktop' 'MenuShowDelay') -eq '20' }
        On   = { RegSet 'HKCU:\Control Panel\Desktop' 'MenuShowDelay' '20' 'String' }
        Off  = { RegSet 'HKCU:\Control Panel\Desktop' 'MenuShowDelay' '400' 'String' }
    },
    @{
        Name = 'Wallpaper Compression: Disabled'
        Hint = 'ставит качество импорта JPEG-обоев на 100'
        Test = { (RegGet 'HKCU:\Control Panel\Desktop' 'JPEGImportQuality') -eq 100 }
        On   = { RegSet 'HKCU:\Control Panel\Desktop' 'JPEGImportQuality' 100 }
        Off  = { RegDel 'HKCU:\Control Panel\Desktop' 'JPEGImportQuality' }
    }
)

function Show-Menu {
    Clear-Host
    Write-Host ''
    Write-Host '   ███████ ██      ███    ██   ' -ForegroundColor White -NoNewline; Write-Host 'tweaker' -ForegroundColor DarkGray
    Write-Host '   ██      ██      ████   ██   ' -ForegroundColor White -NoNewline; Write-Host 'Идеальный сетап Windows 2026' -ForegroundColor DarkGray
    Write-Host '   █████   ██      ██ ██  ██' -ForegroundColor White
    Write-Host '   ██      ██      ██  ██ ██' -ForegroundColor White
    Write-Host '   ██      ███████ ██   ████' -ForegroundColor White
    Write-Host ''
    Write-Host '   ВКЛ — твик применён    ВЫКЛ — не применён полностью    Н/Д — недоступно    ? — ошибка чтения' -ForegroundColor DarkGray
    Write-Host ''
    for ($i = 0; $i -lt $Tweaks.Count; $i++) {
        Show-TweakStatus $Tweaks[$i] ($i + 1)
    }
    Write-Host ''
    Write-Host '   [F] Применить профиль оформления и приватности' -ForegroundColor Yellow
    Write-Host '   [D] Удалить встроенные приложения и компоненты' -ForegroundColor Yellow
    Write-Host '   [X] ' -ForegroundColor White -NoNewline; Write-Host 'Удалить Xbox и Game Bar' -ForegroundColor Magenta -NoNewline
    Write-Host ' — не для Ryzen 7900X3D / 7950X3D / 9900X3D / 9950X3D' -ForegroundColor DarkGray
    Write-Host '   [A] ' -ForegroundColor White -NoNewline; Write-Host 'Включить все твики' -ForegroundColor Cyan
    Write-Host '   [Q] ' -ForegroundColor White -NoNewline; Write-Host 'Выход' -ForegroundColor DarkGray
    Write-Host ''
    Write-Host '   Номер твика переключает его туда-обратно.' -ForegroundColor DarkGray
    Write-Host ''
}

function Confirm-Action($prompt) {
    return (Read-Choice "$prompt (да/нет)") -in 'ДА', 'YES'
}

function Remove-AppPackages([string[]]$names) {
    $installed = @(Get-AppxPackage -AllUsers -ErrorAction Stop | Where-Object Name -in $names)
    $provisioned = @(Get-AppxProvisionedPackage -Online -ErrorAction Stop | Where-Object DisplayName -in $names)
    $failures = 0
    foreach ($package in $installed) {
        try { Remove-AppxPackage -Package $package.PackageFullName -AllUsers -ErrorAction Stop }
        catch { Write-Warning "$($package.Name): $($_.Exception.Message)"; $failures++ }
    }
    foreach ($package in $provisioned) {
        try { Remove-AppxProvisionedPackage -PackageName $package.PackageName -Online -AllUsers -ErrorAction Stop | Out-Null }
        catch { Write-Warning "$($package.DisplayName): $($_.Exception.Message)"; $failures++ }
    }
    return $failures
}

function Invoke-RemoveWindowsApps {
    Write-Host '   Удаляются приложения всех пользователей, включая Paint, Ножницы и OneDrive.' -ForegroundColor Yellow
    Write-Host '   Также удаляются компоненты, включая клиент OpenSSH и распознавание речи.' -ForegroundColor Yellow
    if (-not (Confirm-Action '   Удалить приложения и компоненты?')) { return }
    $failures = 0
    function Step($text) { Write-Host "   > $text" -ForegroundColor DarkGray }
    Step 'Удаление встроенных приложений'
    $packages = 'Microsoft.Microsoft3DViewer','Microsoft.BingSearch','Microsoft.WindowsCamera','Clipchamp.Clipchamp',
        'Microsoft.WindowsAlarms','Microsoft.Copilot','Microsoft.549981C3F5F10','Microsoft.Windows.DevHome',
        'MicrosoftCorporationII.MicrosoftFamily','Microsoft.WindowsFeedbackHub','Microsoft.Edge.GameAssist',
        'Microsoft.GetHelp','Microsoft.Getstarted','microsoft.windowscommunicationsapps','Microsoft.WindowsMaps',
        'Microsoft.MixedReality.Portal','Microsoft.BingNews','Microsoft.MicrosoftOfficeHub','Microsoft.Office.OneNote',
        'Microsoft.OutlookForWindows','Microsoft.MSPaint','Microsoft.People','Microsoft.PowerAutomateDesktop',
        'MicrosoftCorporationII.QuickAssist','Microsoft.SkypeApp','Microsoft.ScreenSketch',
        'Microsoft.MicrosoftSolitaireCollection','Microsoft.MicrosoftStickyNotes','MicrosoftTeams','MSTeams',
        'Microsoft.Todos','Microsoft.WindowsSoundRecorder','Microsoft.Wallet','Microsoft.BingWeather',
        'Microsoft.YourPhone','Microsoft.ZuneVideo','Microsoft.Windows.Ai.Copilot.Provider'
    $failures += Remove-AppPackages $packages

    Step 'Удаление компонентов Windows (может занять несколько минут)'
    $caps = 'Language.Handwriting','Browser.InternetExplorer','MathRecognizer','OneCoreUAP.OneSync','OpenSSH.Client',
        'Microsoft.Windows.PowerShell.ISE','App.Support.QuickAssist','Microsoft.Windows.SnippingTool','Language.Speech',
        'Language.TextToSpeech','App.StepsRecorder','Hello.Face.18967','Hello.Face.Migration.18967','Hello.Face.20134',
        'Media.WindowsMediaPlayer','Microsoft.Windows.WordPad'
    $capabilities = Get-WindowsCapability -Online -ErrorAction Stop |
        Where-Object { $_.State -eq 'Installed' -and ($_.Name -split '~')[0] -in $caps }
    foreach ($capability in $capabilities) {
        try { Remove-WindowsCapability -Online -Name $capability.Name -ErrorAction Stop | Out-Null }
        catch { Write-Warning "$($capability.Name): $($_.Exception.Message)"; $failures++ }
    }
    $features = Get-WindowsOptionalFeature -Online -ErrorAction Stop |
        Where-Object { $_.State -eq 'Enabled' -and $_.FeatureName -in 'MediaPlayback','Microsoft-RemoteDesktopConnection','Recall','Microsoft-SnippingTool' }
    foreach ($feature in $features) {
        try { Disable-WindowsOptionalFeature -Online -FeatureName $feature.FeatureName -NoRestart -ErrorAction Stop | Out-Null }
        catch { Write-Warning "$($feature.FeatureName): $($_.Exception.Message)"; $failures++ }
    }

    Step 'OneDrive, Teams и Outlook'
    foreach ($exe in "$env:windir\System32\OneDriveSetup.exe", "$env:windir\SysWOW64\OneDriveSetup.exe") {
        if (-not (Test-Path -LiteralPath $exe)) { continue }
        try {
            $process = Start-Process -FilePath $exe -ArgumentList '/uninstall' -Wait -PassThru -ErrorAction Stop
            if ($process.ExitCode -ne 0) { throw "Код завершения $($process.ExitCode)." }
        } catch { Write-Warning "$($exe): $($_.Exception.Message)"; $failures++ }
    }
    RegDel 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' 'OneDrive'
    RegSet 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Communications' 'ConfigureChatAutoInstall' 0
    RegSet 'HKLM:\Software\Policies\Microsoft\Windows\CloudContent' 'DisableCloudOptimizedContent' 1

    if ($failures) { Write-Warning "Операций с ошибками: $failures" }
    else { Write-Host '   Удаление завершено.' -ForegroundColor Green }
}

function Invoke-AnswerFile {
    if (-not (Confirm-Action '   Применить настройки оформления, панели задач и приватности?')) { return }
    function Step($text) { Write-Host "   > $text" -ForegroundColor DarkGray }
    $adv = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'

    Step 'Edge, Copilot, виджеты, Bing в поиске, игровая запись'
    RegSet 'HKLM:\Software\Policies\Microsoft\Edge\Recommended' 'BackgroundModeEnabled' 0
    RegSet 'HKLM:\Software\Policies\Microsoft\Edge\Recommended' 'StartupBoostEnabled' 0
    RegSet 'HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot' 'TurnOffWindowsCopilot' 1
    RegSet 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh' 'AllowNewsAndInterests' 0
    RegSet 'HKCU:\Software\Policies\Microsoft\Windows\Explorer' 'DisableSearchBoxSuggestions' 1
    RegSet 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR' 'AppCaptureEnabled' 0

    Step 'Приватность (как «отключить всё» при установке)'
    RegSet 'HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo' 'Enabled' 0
    RegSet 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy' 'TailoredExperiencesWithDiagnosticDataEnabled' 0
    RegSet 'HKCU:\Software\Microsoft\Speech_OneCore\Settings\OnlineSpeechPrivacy' 'HasAccepted' 0
    RegSet 'HKCU:\Software\Microsoft\InputPersonalization' 'RestrictImplicitInkCollection' 1
    RegSet 'HKCU:\Software\Microsoft\InputPersonalization' 'RestrictImplicitTextCollection' 1
    RegSet 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location' 'Value' 'Deny' 'String'

    Step 'Проводник и панель задач'
    RegSet 'HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32' '(default)' '' 'String'
    RegSet $adv 'HideFileExt' 0
    RegSet $adv 'LaunchTo' 1
    RegSet $adv 'ShowTaskViewButton' 0
    RegSet 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' 'SearchboxTaskbarMode' 0
    RegSet "$adv\TaskbarDeveloperSettings" 'TaskbarEndTask' 1
    RegSet 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Start' 'VisiblePlaces' ([byte[]]@()) 'Binary'
    foreach ($k in 'ClassicStartMenu', 'NewStartPanel') {
        foreach ($g in '{5399e694-6ce5-4d6c-8fce-1d8870fdcba0}','{b4bfcc3a-db2c-424c-b029-7fe99a87c641}','{a8cdff1c-4878-43be-b5fd-f8091c1c60d0}',
                       '{374de290-123f-4565-9164-39c4925e467b}','{e88865ea-0e1c-4e20-9aa6-edcd0212c87c}','{f874310e-b6b7-47dc-bc84-b9e6b38f5903}',
                       '{1cf1260c-4dd0-4ebb-811f-33c572699fde}','{f02c1a0d-be21-4350-88b0-7367fc96ef3c}','{3add1653-eb32-4cb0-bbd7-dfa0abb5acca}',
                       '{645ff040-5081-101b-9f08-00aa002f954e}','{20d04fe0-3aea-1069-a2d8-08002b30309d}','{59031a47-3f72-44a7-89c5-5595fe6b30ee}',
                       '{a0953c92-50dc-43bf-be83-3742fed03c9c}') {
            RegSet "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\$k" $g 1
        }
    }

    Step 'Мышь, залипание клавиш, тёмная тема'
    RegSet 'HKCU:\Control Panel\Mouse' 'MouseSpeed' '0' 'String'
    RegSet 'HKCU:\Control Panel\Mouse' 'MouseThreshold1' '0' 'String'
    RegSet 'HKCU:\Control Panel\Mouse' 'MouseThreshold2' '0' 'String'
    RegSet 'HKCU:\Control Panel\Accessibility\StickyKeys' 'Flags' '10' 'String'
    $pers = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
    RegSet $pers 'SystemUsesLightTheme' 0; RegSet $pers 'AppsUseLightTheme' 0
    RegSet $pers 'ColorPrevalence' 0; RegSet $pers 'EnableTransparency' 0
    RegSet 'HKCU:\Software\Microsoft\Windows\DWM' 'ColorPrevalence' 0

    Step 'Параметры быстродействия (оставлены 4 галочки)'
    if (-not ('Fln.Spi' -as [type])) { Add-Type -Namespace Fln -Name Spi -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool SystemParametersInfo(uint a, uint b, IntPtr c, uint d);
[DllImport("user32.dll")] public static extern bool SystemParametersInfo(uint a, uint b, int[] c, uint d);
'@ -ErrorAction Stop
    }
    $spiFailures = 0
    $upd = 3
    if (-not [Fln.Spi]::SystemParametersInfo(0x0004, 0, [int[]](0, 0, 0), $upd)) { $spiFailures++ }
    if (-not [Fln.Spi]::SystemParametersInfo(0x0025, 1, [IntPtr]::Zero, $upd)) { $spiFailures++ }
    if (-not [Fln.Spi]::SystemParametersInfo(0x004B, 1, [IntPtr]::Zero, $upd)) { $spiFailures++ }
    foreach ($a in 0x1003, 0x1005, 0x1007, 0x1015, 0x1017, 0x101B, 0x1025, 0x1043) {        # анимации и тени — выкл
        if (-not [Fln.Spi]::SystemParametersInfo($a, 0, [IntPtr]::Zero, $upd)) { $spiFailures++ }
    }
    if (-not [Fln.Spi]::SystemParametersInfo(0x0049, 8, [int[]](8, 0), $upd)) { $spiFailures++ }
    RegSet 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' 'VisualFXSetting' 3
    RegSet $adv 'TaskbarAnimations' 0; RegSet $adv 'ListviewShadow' 0; RegSet $adv 'ListviewAlphaSelect' 1; RegSet $adv 'IconsOnly' 0
    RegSet 'HKCU:\Software\Microsoft\Windows\DWM' 'EnableAeroPeek' 0
    RegSet 'HKCU:\Software\Microsoft\Windows\DWM' 'AlwaysHibernateThumbnails' 0

    if ($spiFailures) { Write-Warning "Windows отклонила часть настроек интерфейса ($spiFailures)." }
    else { Write-Host '   Профиль применён.' -ForegroundColor Green }
    Write-Host '   Для некоторых настроек потребуется выйти из сеанса Windows.' -ForegroundColor DarkGray
}

function Invoke-RemoveXbox {
    $cpu = (Get-CimInstance Win32_Processor -ErrorAction Stop | Select-Object -First 1).Name
    Write-Host "   Процессор: $cpu" -ForegroundColor DarkGray
    if ($cpu -match '(7900|7950|9900|9950)X3D') {
        Write-Warning 'Для этого Ryzen X3D исходная утилита рекомендует сохранить Xbox Game Bar.'
    }
    Write-Host '   Xbox и Game Bar будут удалены для всех пользователей.' -ForegroundColor Yellow
    if (-not (Confirm-Action '   Удалить Xbox и Game Bar?')) { return }
    $failures = Remove-AppPackages @('Microsoft.Xbox.TCUI','Microsoft.XboxApp','Microsoft.XboxGameOverlay',
        'Microsoft.XboxGamingOverlay','Microsoft.XboxIdentityProvider','Microsoft.XboxSpeechToTextOverlay','Microsoft.GamingApp')
    if ($failures) { Write-Warning "Операций с ошибками: $failures" }
    else { Write-Host '   Удаление завершено.' -ForegroundColor Green }
}

if ($env:FLN_TWEAKER_TEST) {
    $statusErrors = 0
    foreach ($t in $Tweaks) {
        try {
            $status = Get-TweakState $t
            if ($null -eq $status) { $status = 'Н/Д' }
            '{0,-35} {1}' -f $t.Name, $status
        }
        catch { '{0,-35} ? — {1}' -f $t.Name, $_.Exception.Message; $statusErrors++ }
    }
    if ($statusErrors) { exit 1 }
    return
}

while ($true) {
    Show-Menu
    $choice = Read-Choice '   Выбор'
    if ($choice -in 'Q', 'Й' -or [Console]::IsInputRedirected -and -not $choice) { break }
    try {
        if ($choice -in 'A', 'Ф') {
            foreach ($t in $Tweaks) { Invoke-Tweak $t -EnableOnly }
        } elseif ($choice -in 'F', 'А') {
            Invoke-AnswerFile
        } elseif ($choice -in 'D', 'В') {
            Invoke-RemoveWindowsApps
        } elseif ($choice -in 'X', 'Ч') {
            Invoke-RemoveXbox
        } elseif ($choice -match '^[0-9]+$') {
            $index = 0
            if (-not [int]::TryParse($choice, [ref]$index) -or $index -lt 1 -or $index -gt $Tweaks.Count) { continue }
            Invoke-Tweak $Tweaks[$index - 1]
        } else { continue }
    } catch {
        Write-Host ('   ' + $_.Exception.Message) -ForegroundColor Yellow
        Write-Host '   Часть изменений могла уже примениться.' -ForegroundColor Yellow
    }
    $null = Read-Host '   Enter — назад в меню'
}
