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
$Host.UI.RawUI.WindowTitle = 'fln explorer tweaker'
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

$Explorer = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer'
$Blocked  = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Shell Extensions\Blocked'
$Classes  = 'HKLM:\SOFTWARE\Classes'
$GitVerbs = 'Directory\shell\git_gui','Directory\shell\git_shell','Directory\Background\shell\git_gui','Directory\Background\shell\git_shell',
            'LibraryFolder\background\shell\git_gui','LibraryFolder\background\shell\git_shell'

function New-BlockTweak($name, $hint, $clsids) {
    @{
        Name = $name
        Hint = $hint
        Ids = $clsids
        Test = {
            param($tweak)
            foreach ($id in $tweak.Ids) { if ($null -eq (RegGet $Blocked $id)) { return $false } }
            return $true
        }
        On = { param($tweak) foreach ($id in $tweak.Ids) { RegSet $Blocked $id '' 'String' } }
        Off = { param($tweak) foreach ($id in $tweak.Ids) { RegDel $Blocked $id } }
    }
}

function New-SidebarTweak($name, $hint, $clsid) {
    @{
        Name = $name
        Hint = $hint
        Key = "HKCU:\Software\Classes\CLSID\$clsid"
        Test = { param($tweak) (RegGet $tweak.Key 'System.IsPinnedToNameSpaceTree') -eq 0 }
        On = { param($tweak) RegSet $tweak.Key 'System.IsPinnedToNameSpaceTree' 0 }
        Off = { param($tweak) RegSet $tweak.Key 'System.IsPinnedToNameSpaceTree' 1 }
    }
}

function Get-PinnedItem($path) {
    if (-not $path -or -not (Test-Path -LiteralPath $path -PathType Container -ErrorAction Stop)) {
        throw 'Системная папка недоступна.'
    }
    $homeFolder = (New-Object -ComObject Shell.Application).Namespace('shell:::{679f85cb-0220-4080-b29b-5540cc05aab6}')
    if ($null -eq $homeFolder) { throw 'Не удалось открыть быстрый доступ Проводника.' }
    $homeFolder.Items() | Where-Object { $_.Path -eq $path -and $_.ExtendedProperty('System.Home.IsPinned') } |
        Select-Object -First 1
}

function Set-PinnedItem($path, [bool]$pin) {
    if ($pin) {
        $folder = (New-Object -ComObject Shell.Application).Namespace($path)
        if ($null -eq $folder) { throw 'Не удалось открыть системную папку.' }
        $folder.Self.InvokeVerb('pintohome')
    } else {
        $item = Get-PinnedItem $path
        if ($item) { $item.InvokeVerb('unpinfromhome') }
    }
    for ($attempt = 0; $attempt -lt 10; $attempt++) {
        if ([bool](Get-PinnedItem $path) -eq $pin) { return }
        Start-Sleep -Milliseconds 200
    }
    throw 'Проводник не подтвердил изменение закрепления.'
}

function New-UnpinTweak($name, $folder) {
    @{
        Name = $name
        Hint = 'убирает папку из закреплённых в левой панели'
        Path = [Environment]::GetFolderPath($folder)
        Test = { param($tweak) -not (Get-PinnedItem $tweak.Path) }
        On = { param($tweak) Set-PinnedItem $tweak.Path $false }
        Off = { param($tweak) Set-PinnedItem $tweak.Path $true }
    }
}

$Tweaks = @(
    @{
        Name = 'Context Menu: Git'
        Hint = 'убирает Open Git GUI here и Open Git Bash here'
        Test = {
            $paths = @($GitVerbs | ForEach-Object { "$Classes\$_" } | Where-Object { Test-Path -LiteralPath $_ -ErrorAction Stop })
            if (-not $paths.Count) { return $null }
            foreach ($path in $paths) { if ($null -eq (RegGet $path 'LegacyDisable')) { return $false } }
            return $true
        }
        On   = { foreach ($v in $GitVerbs) { if (Test-Path -LiteralPath "$Classes\$v") { RegSet "$Classes\$v" 'LegacyDisable' '' 'String' } } }
        Off  = { foreach ($v in $GitVerbs) { RegDel "$Classes\$v" 'LegacyDisable' } }
    },
    (New-BlockTweak 'Context Menu: AMD' 'убирает AMD Radeon Software, AMD Link и Adrenalin' @('{5E2121EE-0300-11D4-8D3B-444553540000}')),
    (New-BlockTweak 'Context Menu: NVIDIA' 'убирает NVIDIA Control Panel (сама панель открывается из Пуска)' @('{3D1975AF-48C6-4f8e-A182-BE0E08FA86A9}')),
    (New-BlockTweak 'Context Menu: Open in Terminal' 'меню становится короче, терминал открывается и через Win+X' @('{9F156763-7844-4DC4-B2B1-901F640F5155}','{02DB545A-3E20-46DE-83A5-1329B1E88B6B}')),
    @{
        Name = 'Quick Access History: Disabled'
        Hint = 'проводник не подкидывает часто используемые папки и недавние файлы'
        Test = { ((RegGet $Explorer 'ShowFrequent') -eq 0) -and ((RegGet $Explorer 'ShowRecent') -eq 0) -and
            ((RegGet $Explorer 'ShowCloudFilesInQuickAccess') -eq 0) }
        On   = {
            RegSet $Explorer 'ShowFrequent' 0; RegSet $Explorer 'ShowRecent' 0; RegSet $Explorer 'ShowCloudFilesInQuickAccess' 0
        }
        Off  = {
            RegSet $Explorer 'ShowFrequent' 1; RegSet $Explorer 'ShowRecent' 1; RegSet $Explorer 'ShowCloudFilesInQuickAccess' 1
        }
    },
    (New-SidebarTweak 'Sidebar: Home' 'убирает «Главную» из левой панели' '{f874310e-b6b7-47dc-bc84-b9e6b38f5903}'),
    (New-SidebarTweak 'Sidebar: Gallery' 'убирает «Галерею» из левой панели' '{e88865ea-0e1c-4e20-9aa6-edcd0212c87c}'),
    (New-SidebarTweak 'Sidebar: Network' 'убирает «Сеть» из левой панели' '{F02C1A0D-BE21-4350-88B0-7367FC96EF3C}'),
    (New-UnpinTweak 'Unpin: Documents' 'MyDocuments'),
    (New-UnpinTweak 'Unpin: Pictures' 'MyPictures'),
    (New-UnpinTweak 'Unpin: Music' 'MyMusic'),
    (New-UnpinTweak 'Unpin: Videos' 'MyVideos')
)

function Show-Menu {
    Clear-Host
    Write-Host ''
    Write-Host '   ███████ ██      ███    ██   ' -ForegroundColor White -NoNewline; Write-Host 'explorer tweaker' -ForegroundColor DarkGray
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
    Write-Host '   [A] ' -ForegroundColor White -NoNewline; Write-Host 'Включить все твики' -ForegroundColor Cyan
    Write-Host '   [Q] ' -ForegroundColor White -NoNewline; Write-Host 'Выход' -ForegroundColor DarkGray
    Write-Host ''
    Write-Host '   Для некоторых настроек может потребоваться выход из сеанса Windows.' -ForegroundColor DarkGray
    Write-Host ''
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
