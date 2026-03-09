# macstate

Capture a complete, diffable snapshot of your macOS system state — preferences, installed software, filesystem structure, dotfile contents, and system configuration.

## Install

```bash
git clone https://github.com/youlun/macstate.git
cd macstate
```

No dependencies beyond macOS and Python 3 (bundled with Xcode Command Line Tools).

## Usage

```bash
# Capture system state
./macstate.sh

# Full capture (includes sudo-gated collectors)
sudo ./macstate.sh

# Run specific collectors only
./macstate.sh --only homebrew,shell-env

# Skip slow collectors
./macstate.sh --skip fonts,packages

# Preference-only capture (skip filesystem index)
./macstate.sh --no-filesystem

# Compare two snapshots
./macstate.sh --diff ~/MacSnapshots/2024-01-15_100000 ~/MacSnapshots/2024-01-16_100000

# View snapshot in browser
./macstate.sh --view ~/MacSnapshots/2024-01-15_100000

# View diff in browser
./macstate.sh --view ~/MacSnapshots/2024-01-15_100000 ~/MacSnapshots/2024-01-16_100000

# Export as JSON
./macstate.sh --export-json ~/MacSnapshots/2024-01-15_100000

# Interactive SQL query
./macstate.sh --query ~/MacSnapshots/2024-01-15_100000
```

## What it captures

| Collector | Description |
|-----------|-------------|
| system-info | macOS version, hardware profile |
| filesystem | Full filesystem index (SQLite) |
| defaults-global | NSGlobalDomain preferences |
| defaults-domains | Per-domain defaults |
| defaults-apps | Key application preferences |
| system-plists | System preference plists |
| systemsetup | System setup (requires sudo) |
| network | Network configuration |
| power | Power management settings |
| security | Firewall, SIP, Gatekeeper, FileVault |
| login-items | LaunchAgents, LaunchDaemons |
| sharing | Sharing services, Bluetooth, Time Machine |
| input | Keyboard, trackpad, accessibility |
| appearance | Dock, wallpaper, window management |
| apps | Installed applications |
| homebrew | Brew packages, casks, taps |
| shell-env | Shell, PATH, env vars (secrets redacted) |
| dotfile-contents | Key dotfile contents |
| packages | npm, pip, gem, mise packages |
| fonts | Installed fonts |

## Output

Snapshots are saved to `~/MacSnapshots/<timestamp>/` with `chmod 700`. Each snapshot contains text files from collectors and a SQLite database with the filesystem index.

## License

MIT
