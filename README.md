# linux-server-status
Quick output of server status. Similar to info upon login via ssh.

# Preview

## Basic usage
![Basic usage](demo-media/screenshots/basic_usage.png) ![Basic usage Zoomed](demo-media/screenshots/basic_usage_zoomed.png) 

## Update procedure
![Update usage](demo-media/screenshots/update_usage.png)

# Prerequisities
### Install Bash

```bash
sudo apt update
sudo apt install bash
```

### Set locale to english

Why? -> The tool reads cli-outputs to retrieve info -> must ensure that those outputs look the same

Verify your current locale setting is not english (e.g.: en_US.UTF-8)
```bash
locale
```

Change locale to english
```bash
sudo dpkg-reconfigure locales
```
In the dialog:
- Use spacebar to select en_US.UTF-8 (or another English locale like en_GB.UTF-8).
- Make sure to deselect de_DE.UTF-8 if you want to remove German completely.
- Press Enter to continue.
- Then choose en_US.UTF-8 (or your preferred English) as the default.

#### (Optional) Set locale permanently for all users
You can manually edit the file:

```bash
sudo vi /etc/default/locale
```
And set the contents like:


```ini
LANG="en_US.UTF-8"
LANGUAGE="en_US:en"
LC_ALL="en_US.UTF-8"
```

Save and reboot (or log out and back in):
```bash
sudo reboot
```

# 🧰 First Setup

Installiere `linux-server-status` unter `~/tools/linux-server-status`, erstelle einen globalen Befehl `server-info`, und mache ihn dauerhaft verfügbar:

### 🚀 Einfach den folgenden Block im Terminal ausführen:
```bash
ORIGINAL_DIR=$(pwd)
mkdir -p /tmp/server-info-setup && cd /tmp/server-info-setup
curl -sO https://raw.githubusercontent.com/Sokrates1989/linux-server-status/main/setup/linux-cli.sh
bash linux-cli.sh
cd "$ORIGINAL_DIR"
rm -rf /tmp/server-info-setup

# Apply PATH update in current shell (if not already applied)
export PATH="$HOME/.local/bin:$PATH"
hash -r
```

---

# 🚀 Usage

### ✨ Einfacher Aufruf überall im Terminal:
```bash
server-info
```

---

# 📄 JSON Output für Messaging / Automatisierung

### 🔧 Standard-Output-Datei
```bash
server-info --json
```

### 📝 Benutzerdefinierte Output-Datei
```bash
# Stelle sicher, dass der Zielordner existiert
mkdir -p /custom/path
touch /custom/path/file.json

# Mit Kurzoption:
server-info --json -o /custom/path/file.json

# Oder mit Langoption:
server-info --json --output-file /custom/path/file.json
```

---

# ⏰ Automatisierung per Cronjob

### Öffne Crontab im Editiermodus:
```bash
crontab -e
```

### Beispiel 1 – stündlich zur Minute 59:
```bash
59 * * * * /usr/local/bin/server-info --json --output-file /custom/path/file.json
```

### Beispiel 2 – produktiver Einsatz:
```bash
59 * * * * /usr/local/bin/server-info --json --output-file /serverInfo/system_info.json
```

---

# 🔄 Swarm Maintenance (Single-Node Safe Reboot)

For **single-node Docker Swarm** clusters, simply rebooting can leave services in an inconsistent state. The `--safe-reboot` workflow safely scales down services before reboot and restores them after.

## 🚀 Quick Safe Reboot

```bash
# Enter maintenance mode, scale down services, and reboot
server-info --safe-reboot

# After reboot, restore services
server-info --maintenance-exit
```

## 📋 Available Commands

| Command | Description |
|---------|-------------|
| `--safe-reboot` | Full safe reboot workflow (snapshot + scale down + reboot prompt) |
| `--maintenance-enter` | Enter maintenance mode only (snapshot + scale down) |
| `--maintenance-exit` | Exit maintenance mode (restore services from snapshot) |
| `--maintenance-status` | Show current maintenance status |
| `--maintenance-help` | Show detailed maintenance help |

## 🔧 How It Works

1. **Snapshot**: Creates a snapshot of all service replica counts
2. **Scale Down**: Stops services in safe order:
   - Applications first (APIs, frontends, bots)
   - Databases next (postgres, mysql, redis, neo4j)
   - Ingress last (traefik, nginx)
3. **Reboot**: System reboots safely with all services stopped
4. **Restore**: After reboot, services are restored to their exact previous state

## 📝 Example Workflow

```bash
# Check current status
server-info --maintenance-status

# Option A: Full automated workflow
server-info --safe-reboot
# (system reboots)
server-info --maintenance-exit

# Option B: Manual steps
server-info --maintenance-enter
reboot
# (after reboot)
server-info --maintenance-exit
```

## ⚙️ Options

| Option | Description |
|--------|-------------|
| `--force` | Overwrite existing snapshot (for `--maintenance-enter` and `--safe-reboot`) |
| `--dry-run` | Show what would be done without making changes (for `--maintenance-enter`) |
| `--keep-snapshot` | Don't archive snapshot after restore (for `--maintenance-exit`) |
| `-y, --yes` | Auto-confirm reboot without prompt (for `--safe-reboot`) |

## 📁 Snapshot Location

Snapshots are stored in `/var/lib/server-info/swarm-maintenance/` and archived after successful restore.

---

# 📚 All Available Options

```bash
server-info --help
```

| Option | Description |
|--------|-------------|
| `-s` | Display short system information (default) |
| `-f, --full, -l` | Display full system information |
| `-u` | Display available system updates |
| `--cpu` | Display CPU information |
| `-g, --gluster` | Display full GlusterFS info |
| `--json` | Save and display info in JSON format |
| `-o, --output-file` | Where to save the JSON output |
| `--maintenance-enter` | Enter swarm maintenance mode |
| `--maintenance-exit` | Exit swarm maintenance mode |
| `--safe-reboot` | Full safe reboot workflow |
| `--maintenance-status` | Show maintenance status |
| `--maintenance-help` | Show maintenance help |
| `--help` | Display help message |

