TV-KIT - clean up an Android TV / Google TV and give it the tv-home launcher
==========================================================================

Nothing is ever uninstalled. Apps are only turned off ("disabled"), every
change is written down first, and RESTORE.bat puts the TV back the way it was.

BEFORE YOU START, on the TV (2 minutes, with the remote):
  1. Settings > System > About > select "Android TV OS build" 7 times
     until it says "You are now a developer".
  2. Settings > System > Developer options:
       TV on Wi-Fi:     turn on "Wireless debugging" (allow it on this network)
       TV on Ethernet:  turn on "USB debugging"
  3. Keep the TV on, on the same network as this PC.

THEN: double-click TV-KIT.bat. It
  - finds the TV on your network and connects (if the TV shows a pairing
    code, choose "Pair device with pairing code" on the TV and type the
    code here; when the TV asks "Allow debugging?", tick "Always allow"
    and choose Allow)
  - backs everything up (backups\)
  - shows you exactly what it will turn off, and waits for Enter
  - turns off ads, tracking, junk, casting, Ambient mode and unused apps
    that came with the TV; Google Assistant and voice stay on
  - installs the tv-home launcher with a dock of your most-used apps and
    the nature-photo screensaver, and makes it the home screen (Google TV's
    home screen goes straight back on if the Home button doesn't open it)
  - takes screenshots from the TV after each step (shots\)
  - makes SEND-TO-CLAUDE.zip: attach it in the chat so Claude can check

To change what gets turned off, edit the "David's answers" lines at the
top of tools\tvkit.ps1 (set one to $true to keep that feature on).

RESTORE.bat
  Puts the TV back the way it was in the first backup: every app turned
  back on, changed settings put back, Google TV's home screen back as the
  home screen, and the launcher turned off.
    RESTORE.bat -RemoveLauncher            also deletes the launcher
    RESTORE.bat -Backup "backups\<folder>" restores a later backup

FOLDERS (made by the scripts)
  backups\   one folder per backup
  shots\     screenshots taken straight from the TV
  logs\      every command each run used
  state\     which TV, which backup is the original, what was changed

adb: if it isn't on this PC, TV-Kit offers to download Google's official
platform-tools into this folder (it asks first; nothing is installed).

The launcher is tv-home by mihirgupta0900 (MIT, github.com/mihirgupta0900/
tv-home), built from your fork. Its wallpapers are Wikimedia Commons photos
under their own licences (launcher/WALLPAPER-CREDITS.md). TV-Kit is MIT too.
