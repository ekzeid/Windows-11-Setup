# Setting Up Windows 11 Without the Bloat

My guide to a clean Windows 11 installation and setup. The repository contains answer files, scripts, and additional materials that I use myself.

## Installation and Setup

**0)** Take an empty USB flash drive and copy the repository files onto it. For convenience, it's better to use **two USB drives**: one for installing Windows and the other for the remaining files and drivers.

**1)** Create a Windows 11 installation USB using the [official Microsoft website](https://www.microsoft.com/software-download/windows11). I recommend a USB drive with at least **16 GB** of storage. Using the Media Creation Tool is easier than downloading an ISO separately and writing it with Rufus, although that works too. **Warning:** creating installation media may erase the data on the selected USB drive.

**2)** Copy **one** appropriate `autounattend.xml` answer file from the Russian or English version folder to the installation USB. Place it in the **root of the USB drive**. It automates part of the Windows installation and changes some default settings. Keep in mind that the file also affects security settings.

**3)** Download the drivers for your device onto the second USB drive with the repository files, especially network drivers (Wi-Fi or Ethernet). It's best to get them from your laptop or motherboard manufacturer's website.

**4)** Shut down the computer, leave the installation USB plugged in, and open the **Boot Menu** during startup. Usually, you press `F12`, `Esc`, `F9`, or another key depending on your device. Select the installation USB and go through Windows Setup. If the language selection screen doesn't appear, it *may* mean the answer file was applied, but this alone doesn't guarantee that all its settings took effect.

**5)** After installing Windows, install the drivers from the second USB drive. If necessary, you can get the remaining drivers through Windows Update or the manufacturer's website.

**6)** Open the `Тулзы` folder on the USB drive with the repository files. It contains two BAT files:

- `explorer.bat` — File Explorer customization: lets you remove unnecessary interface elements. Choose the option you need by its number; descriptions are included in the script.
- `win-tweaker.bat` — additional Windows settings. Its options are explained inside the script as well. **I don't recommend enabling everything at once:** some modes disable Windows security features, including UAC and SmartScreen. Choose only the changes you actually need.

**7)** Configure everything else: region, time, language, wallpapers, display, and other personal settings.

**8)** After installing the apps you need, clean up startup apps: `Ctrl + Shift + Esc` → **Startup apps**. Disable anything that doesn't need to launch with Windows.

## What I Recommend Installing

### Important Windows Utilities

**1) [Mem Reduct](https://memreduct.org/)** — a utility for clearing certain areas of RAM and the system cache. It doesn't remove Windows processes or guarantee a faster PC. It can be useful when you're short on RAM.

**2) [All-Tweaker](https://github.com/scode18/All-Tweaker)** — a collection of tools for customizing Windows, removing unnecessary apps, and changing system settings, including telemetry-related ones. Use it selectively: some changes can affect how the system works.

**3) [Microsoft PowerToys](https://learn.microsoft.com/en-us/windows/powertoys/)** — a set of Microsoft utilities for convenient Windows customization and additional features. You can install it through the Microsoft Store.

### Apps I Personally Use

**1) [Google App for Windows](https://search.google/google-app/desktop/)** — Google Search from your screen using keyboard shortcuts.

**2) [Handy](https://handy.computer/)** — a free voice typing tool: dictate text, and it converts your speech into text.

**3) [Zen Browser](https://zen-browser.app/)** — the best browser. Its mod manager is [Sine](https://github.com/CosmoCreeper/Sine). The best mod is **Nebula**: it adds clean animations where they're needed, along with blur effects.

**4) [Windhawk](https://windhawk.net/)** — an app for installing Windows mods. I recommend these mods:

- **Taskbar Dock Animation** — taskbar animations.
- **Windows 11 Start Menu Styler** — changes the look of the Start menu.
- **Dynamic Island for Windows** — a Dynamic Island on your desktop.
- **OverhauledWin Alt+Tab** — changes the appearance of the window switcher.

**5) [VLC](https://www.videolan.org/index.ru.html)** — the best video player.

**6) [AIMP](https://aimp.ru/?do=download&os=windows)** — the best audio player.

**7) [Millennium (SteamBrew)](https://steambrew.app/)** — a utility for installing Steam mods and themes. I recommend these themes: `F4XgbtTW4x5CJmi5DUK3` and `uV8M1eg45Hh662blPuyD`.

**8) [SteamBooster](https://steambalance.cc/)** — a utility for topping up your Steam wallet through SteamBalance directly from the client. There are claims online that it may contain malware, but part of its source code is published on [GitHub](https://github.com/STEAMBALANCE). I use it myself and haven't noticed any problems. However, having code on GitHub doesn't automatically guarantee that the installer is safe.

For quickly installing common programs (browsers, messengers, media players, etc.), you can use [Ninite](https://ninite.com/): select your apps and download a single installer. Not every app is available.

**Important:** I recommend temporarily disabling Windows antivirus protection when installing certain utilities, such as All-Tweaker or Sine, because Windows Defender may flag programs that change system settings. But first, check the source and the reason for the warning: antivirus detections aren't always false positives. Turn protection back on immediately after installation.

That's it: you've installed Windows 11, removed some unnecessary apps, and customized the system to your liking. This can make it more convenient to use, especially on a weaker PC, but **a speed boost isn't guaranteed**: results depend on your hardware and the settings you choose.
