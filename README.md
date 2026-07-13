# callhistory-backup

Weekly snapshots of the macOS call history database — **phone and FaceTime
calls**, synced from the iPhone via iCloud — run by a `launchd` LaunchAgent.
Sibling of [screentime-backup](https://github.com/alexjmiller5/screentime-backup),
same mechanism.

Apple retains only a limited window of call history in
`~/Library/Application Support/CallHistoryDB/CallHistory.storedata`; these
snapshots are what preserve long-term history.

Each run lands a consistent SQLite snapshot (via `sqlite3 .backup`, WAL-safe) in
`~/Documents/call-history-backups/<YYYY-MM-DD>/callhistory.db.gz`, and logs a
self-check line with the call count and date range to
`~/Library/Logs/callhistory-backup.log`.

## Layout

```
callhistory-backup/
├── callhistory-backup.sh   # the backup logic (source of truth)
├── bundle/Info.plist       # template for the .app bundle
├── nix/darwin.nix          # nix-darwin module (the installer)
├── flake.nix               # exposes darwinModules.default
├── justfile                # run / status / logs
└── README.md
```

## Install (nix-darwin)

The repo is a flake exposing `darwinModules.default`. Consumed by
[nix-config](https://github.com/alexjmiller5/nix-config) as a flake input;
`darwin-rebuild switch` does the rest:

```nix
# flake input
callhistory-backup.url = "github:alexjmiller5/callhistory-backup";

# module config
services.callhistory-backup = {
  enable = true;
  user = "alexmiller";
  # weekday = 0; hour = 5; minute = 5;   # defaults: Sunday 05:05
};
```

Activation builds an `.app` whose main executable is the backup script,
installs it at `/Applications/CallHistoryBackup.app`, and signs it with a
stable self-signed cert it creates once (idempotently) in the System keychain.
TCC keys Full Disk Access on code identity, and the cert keeps that identity
stable — so the one manual grant below survives every rebuild.

## Manual step: grant Full Disk Access (once)

`CallHistory.storedata` is TCC-protected, and FDA cannot be granted
programmatically (Apple blocks it):

1. Open **System Settings → Privacy & Security → Full Disk Access**.
2. Click **+**, add `/Applications/CallHistoryBackup.app`, toggle it **on**.
3. Verify: `just run && just logs` — a healthy run logs a `backup OK` line with
   a call count and date range.

## Schedule

`StartCalendarInterval` — every **Sunday at 05:05** by default (offset from
screentime-backup's 05:00 on the same machine). Wall-clock anchored: a slot
missed while the machine is asleep/off fires once on the next wake instead of
drifting. Change via the module's `weekday`/`hour`/`minute` options.

## Reading a snapshot

```sh
gunzip -k -c ~/Documents/call-history-backups/<date>/callhistory.db.gz > /tmp/ch.db
sqlite3 /tmp/ch.db "SELECT datetime(ZDATE+978307200,'unixepoch','localtime') AS at,
                           ZADDRESS, ZDURATION, ZANSWERED, ZCALLTYPE
                    FROM ZCALLRECORD ORDER BY ZDATE DESC LIMIT 20;"
```

`ZDATE` is Mac Absolute Time (seconds since 2001-01-01 UTC) — add `978307200`
for Unix epoch. `ZCALLTYPE`: 1 = phone, 8 = FaceTime video, 16 = FaceTime audio.
