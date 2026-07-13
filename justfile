# callhistory-backup — manage the call history backup LaunchAgent.
# Install is declarative (nix-darwin module, see README); these recipes
# operate the installed agent on whatever machine it runs on.

set shell := ["zsh", "-cu"]

label := "com.alexmiller.callhistory-backup"
log   := "~/Library/Logs/callhistory-backup.log"

# List available recipes.
default:
    @just --list

# Trigger a backup now, through launchd (so it runs with the app's FDA identity).
run:
    launchctl kickstart -k "gui/$(id -u)/{{label}}"
    @echo "Backup kicked off. Watch it with: just logs"

# Show the agent's load state, schedule, and the last run from the log.
status:
    #!/usr/bin/env zsh
    set -euo pipefail
    launchctl print "gui/$(id -u)/{{label}}" 2>/dev/null \
        | grep -iE "state =|runs =|last exit|program =" || echo "agent not loaded"
    echo "--- last log lines ---"
    tail -n 15 {{log}} 2>/dev/null || echo "(no log yet)"

# Follow the backup log.
logs:
    tail -n 40 -f {{log}}
