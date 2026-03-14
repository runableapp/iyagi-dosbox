
# Goal and initial design

There is a DOS terminal communication program from 90s, it was for dial up. it's a freeware, but not open source. I want to wrap it with dosbox or something simialr for Ubuntu and Windows, and make it work as SSH instead of dial up. is this feasible, how?


Yes, this is absolutely feasible. The process involves creating a "bridge" where your old DOS program thinks it is talking to a dial-up modem, but the data is actually being routed over an encrypted SSH connection.Since you are dealing with a closed-source freeware program, you cannot rewrite its networking code. Instead, you will use DOSBox and a Modem Emulator to trick it.

1. The Strategy: The "Virtual Modem" BridgeStandard DOS terminal programs (like Telix, Procomm Plus, or Telemate) communicate via a serial COM port using AT commands (e.g., `ATDT 555-1212`).

To make this work with SSH, we create a chain:

  1. DOS Program sends data to a virtual COM port inside DOSBox.
  2. DOSBox is configured to treat that COM port as a "TCP/IP Modem."
  3. A Bridge Service (like tcpser or a local SSH tunnel) converts that TCP data into an SSH session.

2. Setting Up DOSBox (Ubuntu & Windows)

First, you need to tell DOSBox to emulate a modem on a serial port. Edit your `dosbox.conf` file (usually found in `~/.dosbox/` on Ubuntu or `%LOCALAPPDATA%\DOSBox\` on Windows).

Find the `[serial]` section and modify it:
```Ini, TOML
[serial]
serial1=modem listenport:2323
```

- This tells DOSBox that COM1 is a modem.
- It will "listen" for incoming connections on port 2323, but more importantly, it allows the DOS program to "dial" IP addresses.

3. Handling the SSH PartDOS terminal programs generally don't understand the SSH protocol (encryption/handshakes); they only understand raw text (Telnet-style). You have two main ways to bridge this to an SSH server:

Option A: The SSH Tunnel (Easiest)

You can use a standard SSH tunnel to create a "local pipe." In your Ubuntu or Windows terminal, run:
```Bash
ssh -L 2323:remote-ssh-server.com:22 user@remote-ssh-server.com
```

Now, any data sent to your local port `2323` is securely tunneled to the remote server.

Option B: Using tcpser (More Authentic)

If you want the full "vintage" experience where you "dial" the server from within the DOS program, use *tcpser*. It acts as a bridge that translates Hayes AT commands into TCP connections.

  1. Install tcpser:
    - Ubuntu: `sudo apt install tcpser`
    - Windows: Download the `tcpser.exe` binary.
  2. Run tcpser:
    ```Bash
    tcpser -v 2323 -p 22
    ```

  3. In your DOS program:
  Instead of dialing a phone number, you would type:
  `ATDT remote-ssh-server.com`

4. Addressing the SSH Protocol Mismatch

Warning: Most 90s DOS programs expect a raw stream of text. If you connect directly to an SSH port, the DOS program will just see a bunch of "gibberish" (the SSH handshake).

The Solution:

- The "Proxy" approach: Use a modern terminal (like PuTTY or the Linux `ssh` command) to handle the SSH encryption, and then use a tool like socat or netcat to pipe that session into the DOSBox virtual serial port.
- Telnet-to-SSH Gateway: If you control the server, you can run a "Telnet-to-SSH" gateway. However, for most users, Option A (SSH Tunneling) combined with a local Telnet-to-Serial bridge is the most stable path.

5. Summary Checklist

| Component    | Configuration                                                      |
|--------------|--------------------------------------------------------------------|
| DOSBox       | serial1=modem                                                      |
| DOS Program  | Set to COM1, Baud Rate 57600 (or max)                              |
| Connection   | Dial the IP address of your local tunnel (e.g., ATDT 127.0.0.1)    |
| Encryption   | Handled by the background SSH tunnel on your host OS               |

---

# Plan

To make this a single-click experience, you essentially need to create a portable bundle that includes the DOSBox executable, your DOS program, a pre-configured configuration file, and a "bridge" script.

Since you want to cover Windows, Linux, and macOS, here is the most efficient way to package them:

## 1. The Portable Directory Structure

Before you package it, you need a "Template Folder" that works across all systems. Organize it like this:

- `/App` (The DOS terminal program files)
- `/Data` (Your custom dosbox.conf)
- `/Runtime` (The DOSBox binaries for that specific OS)
- `Launch-Script` (The .bat, .sh, or .command file that starts it all)

### The Magic dosbox.conf

In your `[autoexec]` section at the bottom of the config file, you should automate the connection so the user doesn't have to type anything:

```ini
[serial]
serial1=modem listenport:2323

[autoexec]
mount c ./App
c:
TERMINAL.EXE  # Replace with your program's name
exit
```

## 2. Packaging for Each OS

### Windows (Portable EXE)

- Use 7-Zip SFX or NSIS (Nullsoft Scriptable Install System).
- Compress your folder.
- Use an SFX (Self-Extracting) creator to point the "Execute after extraction" command to a batch file.
- The batch file should run: `runtime/dosbox.exe -conf data/dosbox.conf`.

### Linux (AppImage)

This is the cleanest way to distribute on Linux.

- Use AppImageAssistant.
- Your AppRun script (the entry point) should look like this:

```bash
#!/bin/bash
HERE="$(dirname "$(readlink -f "${0}")")"
$HERE/usr/bin/dosbox -conf $HERE/data/dosbox.conf
```

This bundles the DOSBox dependencies so it runs on Ubuntu, Fedora, or Arch without the user installing anything.

### macOS (DMG / .app Bundle)

- macOS sees a folder ending in `.app` as a single file.
- Create a folder named `MyTerminal.app`.
- Inside, create `Contents/MacOS/` and `Contents/Resources/`.
- Put a shell script in `MacOS/` that launches the bundled DOSBox.
- Use Disk Utility to "Create Image from Folder" to generate the `.DMG`.

## 3. The SSH "Middleware" Problem

As mentioned before, DOS programs don't speak SSH. If you want a truly single-file experience, your launch script needs to start the SSH tunnel before it starts DOSBox.

The Logic flow of your Launch Script:

1. Check if an SSH tunnel is active.
2. Start the tunnel in the background (using a tool like `plink.exe` for Windows or `ssh` for Unix).
3. Launch DOSBox.
4. Kill the tunnel when DOSBox closes.

## 4. Feasibility Check: The "Legal" Bit

Since the program is Freeware but not Open Source:

- **Redistribution:** Check the original documentation (usually a `.TXT` or `.DOC` file). Most 90s freeware allowed redistribution if the files weren't modified.
- **Bundling:** You are not modifying the program; you are wrapping it in an emulator. This is generally legally safe for personal or community use.


# Wrapper scripts straregy


To package this cross-platform, you will use a wrapper script strategy. Each OS package will contain the same "Payload" (your DOS program and a customized dosbox.conf) but a different "Launch Script" and "Binary" (the DOSBox executable for that OS).

## 1. The Common Configuration (dosbox.conf)

This file tells DOSBox to act like a modem. Save it as dosbox.conf in your project root.

Ini, TOML
```ini
[serial]
# This tricks the DOS program into thinking a modem is on COM1
# It listens on local port 2323 for the SSH tunnel
serial1=modem listenport:2323

[autoexec]
mount c ./app
c:
# Replace 'TERMINAL.EXE' with your program's filename
TERMINAL.EXE
exit
```

## 2. Windows: Portable Batch Wrapper

For Windows, you'll bundle plink.exe (the command-line version of PuTTY) to handle the SSH tunnel.

Project Structure:

- launch.bat
- dosbox/ (DOSBox files)
- app/ (Your DOS program)
- bin/plink.exe
- dosbox.conf

launch.bat script:

Code snippet
```bat
@echo off
:: 1. Start SSH Tunnel in background (-N means no command, -L is the tunnel)
:: Replace 'user@yourserver.com' with your actual server details
start /b bin\plink.exe -N -L 2323:localhost:22 user@yourserver.com

:: 2. Wait 2 seconds for tunnel to stabilize
timeout /t 2 >nul

:: 3. Run DOSBox with custom config
dosbox\dosbox.exe -conf dosbox.conf -noconsole

:: 4. Cleanup: Kill the tunnel when DOSBox closes
taskkill /f /im plink.exe >nul
```

To Package: Zip the folder. For a "single file" feel, use IExpress (built into Windows) or 7-Zip SFX to create an auto-extracting EXE that runs launch.bat.

## 3. Linux: AppImage / Shell Script

On Linux, we use the native ssh client and create a portable directory.

launch.sh script:

Bash
```bash
#!/bin/bash
# 1. Open SSH Tunnel (forks to background)
ssh -f -N -L 2323:localhost:22 user@yourserver.com

# 2. Launch DOSBox
./runtime/dosbox -conf dosbox.conf

# 3. Cleanup: Find the SSH process we started and kill it
pkill -f "ssh -f -N -L 2323"
```

To Package: Use AppImageKit. You place your folder inside an AppDir structure, point the AppRun file to your launch.sh, and run appimagetool. This gives you one .AppImage file that works on Ubuntu, Fedora, etc.

## 4. macOS: .app Bundle

macOS apps are just folders that look like files.

Project Structure:

- MyTerminal.app/Contents/MacOS/launcher (The script)
- MyTerminal.app/Contents/Resources/ (DOSBox, App, Config)

launcher script:

Bash
```bash
#!/bin/bash
DIR="$(dirname "$0")"
# Start Tunnel
ssh -f -N -L 2323:localhost:22 user@yourserver.com
# Start Bundled DOSBox
"$DIR/../Resources/dosbox" -conf "$DIR/../Resources/dosbox.conf"
# Cleanup
pkill -f "ssh -f -N -L 2323"
```

To Package:

1. Create the folder structure.
2. Use a simple Info.plist file (standard XML) to tell macOS the "Executable" is your launcher script.
3. Right-click the folder and "Create Archive," then rename to .dmg if you want a professional installer.

## Important: Automating the SSH Login

Since this is for a "one-click" user experience, you have two choices for the SSH password:

- SSH Keys (Best): Ask the user to run a "Setup" once to generate a key and send it to the server.
- Hardcoded / Prompt: If you use plink (Windows) or sshpass (Linux), you can pass a password via script, but this is very insecure and not recommended.

# Gitea workflow

Since Gitea Actions is compatible with GitHub Actions syntax, you can use a YAML workflow to automate the entire "factory" process.

The workflow will:

- Download the DOSBox binaries for each OS.
- Inject your scripts and the DOS communication program.
- Bundle them into the final formats (ZIP for Windows, AppImage for Linux, DMG for macOS).
- Upload them as a single Release.

## 1. The Gitea Workflow (.gitea/workflows/build.yaml)

This example shows how to build the Windows version. You can add "jobs" for Linux and macOS following a similar pattern.

YAML
```yaml
name: Build DOS Terminal Bundles
on: [push]

jobs:
  build-windows:
    runs-on: ubuntu-latest  # We can cross-compile/bundle Windows on Linux
    steps:
      - name: Checkout Code
        uses: actions/checkout@v3

      - name: Create Build Directory
        run: mkdir -p build/windows/bin build/windows/app

      - name: Download DOSBox (Windows)
        run: |
          wget https://github.com/dosbox-staging/dosbox-staging/releases/download/v0.80.1/dosbox-staging-windows-x86_64-v0.80.1.zip
          unzip dosbox-staging-windows-x86_64-v0.80.1.zip -d build/windows/dosbox

      - name: Download Plink (SSH Client)
        run: wget https://the.earth.li/~sgtatham/putty/latest/w64/plink.exe -O build/windows/bin/plink.exe

      - name: Copy App and Scripts
        run: |
          cp -r ./my_dos_program/* build/windows/app/
          cp launch.bat build/windows/
          cp dosbox.conf build/windows/

      - name: Create Portable ZIP
        run: |
          cd build/windows
          zip -r ../../DOS_Terminal_Windows.zip .

      - name: Upload Artifact
        uses: actions/upload-artifact@v3
        with:
          name: windows-bundle
          path: DOS_Terminal_Windows.zip
```

## 2. Handling the Other Platforms

For Linux (AppImage): You would add a step to download appimagetool and run it against a folder containing the Linux DOSBox binary and your launch.sh.

For macOS: This is slightly harder on Gitea unless your runner is a Mac. If you use a Linux runner, you can still create the .app folder structure and zip it, but creating a .dmg usually requires a Mac or a specific tool like genisoimage.

## 3. The "Legal & Storage" Setup

To make this work, your Gitea repository should look like this:

Plaintext
```text
/
├── .gitea/workflows/build.yaml
├── my_dos_program/       <-- Put the DOS Freeware files here
├── launch.bat            <-- The Windows script
├── launch.sh             <-- The Linux/macOS script
└── dosbox.conf           <-- The common config
```

## 4. Why this is powerful

By using Gitea Actions:

- Version Control: If you update your dosbox.conf to improve modem speeds, the build happens automatically.
- Consistency: Every user gets the exact same "Plink" and "DOSBox" version, reducing "it doesn't work on my machine" complaints.
- Security: You can use Gitea Secrets to inject server IP addresses or specific SSH configurations into the scripts during the build process so they aren't plain-text in your repo.

## 5. Potential Roadblock: SSH Keys

The hardest part to automate is the SSH Key. Since you are packaging this for others, you can't include your private key.

Pro Tip: In your launch scripts, add a check: "If ~/.ssh/id_rsa doesn't exist, run an ssh-keygen setup wizard first."

Would you like me to help you refine the "Linux AppImage" section of the YAML, or should we look at how to make the Windows installer an EXE instead of a ZIP?

# Summary

Project Specification: SSH-Wrapped DOS Terminal Portable Bundle

## 1. Project Overview

Goal: Package a 16-bit DOS terminal program (Freeware) into a modern, single-file portable execution environment for Windows, Linux, and macOS.

Core Tech: DOSBox (Emulator), plink (Windows SSH), ssh (Unix-like SSH), and a "Virtual Modem" bridge.

Networking: The DOS program communicates via COM1 (Hayes AT Commands). DOSBox translates this to a TCP/IP "Modem" listening on localhost:2323. An SSH tunnel bridges localhost:2323 to a remote SSH server.

## 2. Directory Structure (Source Repo)

Plaintext
```text
/
├── app/                  # Place the DOS terminal program files here
├── bin/                  # Static binaries (e.g., plink.exe for Windows)
├── scripts/
│   ├── launch.bat        # Windows Launcher
│   ├── launch.sh         # Linux Launcher
│   └── mac_launcher.sh   # macOS Internal Launcher
├── dosbox.conf           # Shared DOSBox configuration
└── .gitea/workflows/
    └── build.yaml        # Gitea Actions Automation
```

## 3. Configuration Files

Shared dosbox.conf
Ini, TOML
```ini
[sdl]
autolock=true

[serial]
# Map COM1 to a virtual modem listening on local port 2323
serial1=modem listenport:2323

[cpu]
cycles=fixed 10000

[autoexec]
mount c ./app
c:
# AUTO-RUN: Replace TERMINAL.EXE with the actual executable name
TERMINAL.EXE
exit
```

## 4. Platform Launcher Scripts

Windows (scripts/launch.bat)
Code snippet
```bat
@echo off
setlocal
:: Start SSH Tunnel in background using Plink
:: Note: User must have accepted the server key once or use -batch
start /b bin\plink.exe -N -L 2323:localhost:22 user@yourserver.com

:: Brief delay to allow tunnel to open
timeout /t 2 >nul

:: Launch DOSBox using the local config
bin\dosbox.exe -conf dosbox.conf -noconsole

:: Cleanup tunnel on exit
taskkill /f /im plink.exe >nul
endlocal
```

Linux (scripts/launch.sh)
Bash
```bash
#!/bin/bash
# Start SSH Tunnel (forked to background)
ssh -f -N -L 2323:localhost:22 user@yourserver.com

# Launch DOSBox (Assuming relative path to binary in bundle)
./bin/dosbox -conf ./dosbox.conf

# Kill the specific tunnel process on exit
pkill -f "ssh -f -N -L 2323"
```

## 5. Gitea Workflow (.gitea/workflows/build.yaml)

YAML
```yaml
name: Cross-Platform DOS Bundle Build
on: [push]

jobs:
  build-windows:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v3

      - name: Prepare Workspace
        run: mkdir -p dist/windows/bin dist/windows/app

      - name: Fetch DOSBox Staging (Windows)
        run: |
          wget https://github.com/dosbox-staging/dosbox-staging/releases/download/v0.80.1/dosbox-staging-windows-x86_64-v0.80.1.zip
          unzip dosbox-staging-windows-x86_64-v0.80.1.zip -d dist/windows/bin

      - name: Fetch Plink
        run: wget https://the.earth.li/~sgtatham/putty/latest/w64/plink.exe -O dist/windows/bin/plink.exe

      - name: Assemble
        run: |
          cp -r app/* dist/windows/app/
          cp scripts/launch.bat dist/windows/
          cp dosbox.conf dist/windows/

      - name: Package ZIP
        run: cd dist/windows && zip -r ../../DOS_Terminal_Win.zip .

      - name: Upload
        uses: actions/upload-artifact@v3
        with:
          name: windows-portable
          path: DOS_Terminal_Win.zip

  build-linux:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v3

      - name: Prepare Workspace
        run: mkdir -p dist/linux/bin dist/linux/app

      - name: Fetch DOSBox (Linux Binary)
        run: |
          # Example using a static or appimage-extracted binary
          sudo apt-get update && sudo apt-get install -y dosbox
          cp /usr/bin/dosbox dist/linux/bin/

      - name: Assemble & AppImage
        run: |
          cp -r app/* dist/linux/app/
          cp scripts/launch.sh dist/linux/AppRun
          chmod +x dist/linux/AppRun
          # (Further AppImageTool commands would go here)
```

## 6. Implementation Notes for the Agent

- SSH Authentication: Remind the user they must handle SSH keys (IdentityFile) or the scripts will hang waiting for a password that is hidden in the background.
- Binary Compatibility: On Linux, ensure the DOSBox binary is either statically linked or bundled with necessary .so libraries for a true "run-anywhere" AppImage.
- Pathing: Always use relative paths (./) in dosbox.conf and scripts to ensure portability.

To make this a "one-click" experience across Windows, Linux, and macOS, we need a Wrapper Strategy. Each package will contain the same "Payload" (your DOS program and dosbox.conf) but will use a different "Launcher" and "Binary" (the DOSBox executable for that specific OS).

## 1. The Common Configuration (dosbox.conf)

This file tells DOSBox to act like a modem. Save this as dosbox.conf in your project root.

Ini, TOML
```ini
[serial]
# This tricks the DOS program into thinking a modem is on COM1.
# It listens on local port 2323 for the SSH tunnel.
serial1=modem listenport:2323

[autoexec]
mount c ./app
c:
# Replace 'TERMINAL.EXE' with your actual program's filename
TERMINAL.EXE
exit
```

## 2. Windows: Portable Batch Wrapper

For Windows, we will bundle plink.exe (the command-line version of PuTTY) to handle the SSH tunnel since it's lightweight and portable.

Project Structure:

- launch.bat
- dosbox/ (DOSBox files)
- app/ (Your DOS program)
- bin/plink.exe
- dosbox.conf

launch.bat script:
Code snippet
```bat
@echo off
:: 1. Start SSH Tunnel in background (-N = no command, -L = tunnel)
:: Replace 'user@yourserver.com' with your actual server details
start /b bin\plink.exe -N -L 2323:localhost:22 user@yourserver.com

:: 2. Wait 2 seconds for tunnel to stabilize
timeout /t 2 >nul

:: 3. Run DOSBox with custom config
dosbox\dosbox.exe -conf dosbox.conf -noconsole

:: 4. Cleanup: Kill the tunnel when DOSBox closes
taskkill /f /im plink.exe >nul
```

## 3. Linux: AppImage / Shell Script

On Linux, we use the native ssh client. The goal is to create a portable directory that can be turned into an AppImage.

launch.sh script:
Bash
```bash
#!/bin/bash
# 1. Open SSH Tunnel (forks to background)
ssh -f -N -L 2323:localhost:22 user@yourserver.com

# 2. Launch DOSBox
./runtime/dosbox -conf dosbox.conf

# 3. Cleanup: Find the SSH process we started and kill it
pkill -f "ssh -f -N -L 2323"
```

## 4. macOS: .app Bundle

macOS apps are just folders with a specific structure that the OS treats as a single file.

Project Structure:

- MyTerminal.app/Contents/MacOS/launcher (The script below)
- MyTerminal.app/Contents/Resources/ (Contains DOSBox, App files, and Config)

launcher script:
Bash
```bash
#!/bin/bash
DIR="$(dirname "$0")"
# Start Tunnel
ssh -f -N -L 2323:localhost:22 user@yourserver.com
# Start Bundled DOSBox
"$DIR/../Resources/dosbox" -conf "$DIR/../Resources/dosbox.conf"
# Cleanup
pkill -f "ssh -f -N -L 2323"
```

## 5. Important: Authenticating the SSH Login

Because you want this to be "one-click," the SSH connection needs to happen without a password prompt. You have two main choices:

- SSH Keys (Recommended): The user generates an SSH key once and adds it to the server. Your script can then point to that key.
- Hardcoding (Not Recommended): Using sshpass (Linux) or -pw (Plink) to include the password in the script. Warning: This exposes your password to anyone who can see the script files.

Summary of Packaging Tools

Platform
Target Format
Recommended Tool
Windows.exe (Self-extracting)
7-Zip SFX or IExpress
Linux.AppImage
AppImageTool
macOS.dmg
Create .app folder then use Disk Utility

This expanded specification now includes a "First-Run" logic for all three operating systems. This script checks for an existing SSH key; if one isn't found, it generates one and provides instructions to the user. This ensures the "one-click" goal is met by removing the password prompt hurdle.

Copy and paste the block below for your AI agent.

Complete Specification: SSH-Wrapped DOS Terminal with Auto-Provisioning

## 1. Project Overview

Target: A 16-bit DOS terminal freeware.

Infrastructure: DOSBox (Emulator) + SSH Tunnel (Plink/OpenSSH).

Key Feature: Auto-detection of SSH keys. If missing, the app generates them and helps the user "provision" the remote server.

## 2. Directory Structure

Plaintext
```text
/
├── app/                  # DOS Program Files
├── bin/                  # DOSBox binaries & plink.exe
├── keys/                 # Store generated SSH keys here
├── scripts/
│   ├── setup_ssh.sh      # Unix Key Gen
│   ├── setup_ssh.bat     # Windows Key Gen
│   ├── launch.bat        # Windows Main
│   └── launch.sh         # Linux/macOS Main
├── dosbox.conf           # Serial-to-IP Config
└── .gitea/workflows/     # CI/CD Automation
```

## 3. SSH Setup Scripts (The "First-Run" Logic)

Windows Setup (scripts/setup_ssh.bat)
Code snippet
```bat
@echo off
if exist "keys\id_rsa.ppk" goto :eof
echo --- FIRST RUN: Generating SSH Keys ---
bin\puttygen.exe -t rsa -b 2048 -o "keys\id_rsa.ppk" --comment "DOS-Terminal-Key"
echo.
echo Please copy the text below and add it to your server's ~/.ssh/authorized_keys:
bin\puttygen.exe -L "keys\id_rsa.ppk"
pause
```

Unix Setup (scripts/setup_ssh.sh)
Bash
```bash
#!/bin/bash
if [ ! -f "keys/id_rsa" ]; then
    echo "--- FIRST RUN: Generating SSH Keys ---"
    ssh-keygen -t rsa -b 2048 -f "keys/id_rsa" -N ""
    echo ""
    echo "Please run this command to copy your key to the server:"
    echo "ssh-copy-id -i keys/id_rsa.pub user@yourserver.com"
    read -p "Press enter after the key is uploaded..."
fi
```

## 4. Main Launchers (With Key Integration)

Windows Launcher (scripts/launch.bat)
Code snippet
```bat
@echo off
call scripts\setup_ssh.bat
:: -i uses the generated private key for passwordless login
start /b bin\plink.exe -N -L 2323:localhost:22 -i "keys\id_rsa.ppk" user@yourserver.com
timeout /t 2 >nul
bin\dosbox.exe -conf dosbox.conf -noconsole
taskkill /f /im plink.exe >nul
```

Linux/macOS Launcher (scripts/launch.sh)
Bash
```bash
#!/bin/bash
chmod +x scripts/setup_ssh.sh
./scripts/setup_ssh.sh
# -i points to the local identity file
ssh -f -N -L 2323:localhost:22 -i keys/id_rsa user@yourserver.com
./bin/dosbox -conf ./dosbox.conf
pkill -f "ssh -f -N -L 2323"
```

## 5. DOSBox Configuration (dosbox.conf)

Ini, TOML
```ini
[serial]
serial1=modem listenport:2323

[autoexec]
mount c ./app
c:
TERMINAL.EXE
exit
```

## 6. Gitea Automation (.gitea/workflows/build.yaml)

YAML
```yaml
name: Build Cross-Platform Bundles
on: [push]

jobs:
  bundle-windows:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Download Binaries
        run: |
          # Download DOSBox, Plink, and PuttyGen
          mkdir -p dist/win/bin
          wget https://the.earth.li/~sgtatham/putty/latest/w64/plink.exe -O dist/win/bin/plink.exe
          wget https://the.earth.li/~sgtatham/putty/latest/w64/puttygen.exe -O dist/win/bin/puttygen.exe
          # Add DOSBox Staging
          wget https://github.com/dosbox-staging/dosbox-staging/releases/download/v0.80.1/dosbox-staging-windows-x86_64-v0.80.1.zip
          unzip dosbox-staging-windows-x86_64-v0.80.1.zip -d dist/win/bin
      - name: Finalize
        run: |
          cp -r app/ dist/win/app/
          cp scripts/launch.bat dist/win/
          cp scripts/setup_ssh.bat dist/win/scripts/
          cp dosbox.conf dist/win/
          cd dist/win && zip -r ../../DOS_Terminal_Windows.zip .
      - name: Release
        uses: actions/upload-artifact@v3
        with:
          name: Windows-Portable
          path: DOS_Terminal_Windows.zip
```

