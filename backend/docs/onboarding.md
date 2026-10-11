# Device onboarding

You connect each device with a **Setup URI**. A Setup URI is one encrypted
string. It holds the server URL, the login and the passphrase. It is easier
than typing an E2EE passphrase on an iPhone. It also gives all devices the
same settings. Equal settings prevent the "tweak mismatch" warnings.

## Where Setup URIs come from

| Device | Source of the Setup URI |
|---|---|
| **First device of a vault** | `add-vault.sh` prints one, with its one-time passphrase ([`vaults.md`](vaults.md)). |
| **All other devices** | Copy one from a device that syncs the vault (see below). There is no step on the server. |

A Setup URI and its passphrase are only to set up one device, immediately.
The generator says "store it safely", but you do not need to keep it:

- The URI expires at the next Thursday 00:00 UTC. That can be in a few hours.
  The generator prints the exact time.
- You can get a new one with one command or one click at any time.

**Always set up a device from a Setup URI. Do not set it up by hand.** The
reasons:

- Newer LiveSync versions give a new vault a random "ID key". This key
  changes how LiveSync calculates document IDs.
- livesync-bridge cannot get that key. Thus the bridge and the devices
  calculate different IDs for the same document.
- The URIs from `add-vault.sh` use legacy IDs. LiveSync calculates them from
  `LIVESYNC_PASSPHRASE`, which the bridge has.
- For the same reason, there is no ID recovery code to keep.

If LiveSync asks about the ID key, select **Keep current configuration**.

To make a first-device URI again without `add-vault.sh`, run this on the
server:

```bash
cd /opt/obsidian-self-host/backend
set -a; . ./.env; set +a

hostname="https://couch.$DOMAIN" \
database="<vault>" \
username="$COUCHDB_USER" \
password="$COUCHDB_PASSWORD" \
passphrase="$LIVESYNC_PASSPHRASE" \
id_mode=legacy \
  deno run --minimum-dependency-age=0 --allow-env \
  https://raw.githubusercontent.com/vrtmrz/obsidian-livesync/14141446a14deab3353a8864dee41e44c372d006/utils/flyio/generate_setupuri.ts
```

## First device

This device holds the start content of the vault. For a new vault, that is an
empty vault. Its first sync is a full upload.

1. **Do this:** in Obsidian, go to Settings → Community plugins → Browse.
   Install and enable **Self-hosted LiveSync**.
2. **Do this:** open the command palette with Cmd+P (macOS) or Ctrl+P
   (Windows, Linux).
3. **Do this:** run "Self-hosted LiveSync: Use the copied setup URI".
   - Older versions call it "Open setup URI".
   - You can also use the setup wizard tab in the plugin settings.
4. **Do this:** paste the whole `obsidian://setuplivesync?settings=…` URI from
   `add-vault.sh`.
   **If it fails:** copy the URI again. It must be complete, on one line.
5. **Do this:** type the passphrase that `add-vault.sh` printed with the URI.
6. **Do this:** when LiveSync asks how to use the device, select the first
   device option ("set up as new").
7. **Do this:** when LiveSync asks about Hidden File Sync, select **No**.
   This setup does not sync device configuration on purpose. Read the
   decision in [`runbook.md`](runbook.md).
8. **Do this:** if LiveSync shows "ID key" or "configuration mismatch", select
   **Keep current configuration**.
9. **Do this:** accept the other suggested settings.
10. **Do this:** let the first upload finish completely.
    **Result:** the status bar shows no pending counts, and the log shows no
    more activity.

Check the result on the server:

```bash
curl -fsS -u "$COUCHDB_USER:$COUCHDB_PASSWORD" \
  "https://couch.$DOMAIN/<vault>" | jq '.doc_count'
```

`add-vault.sh` also watches the database. It connects the vault when the
upload is quiet for 30 seconds.

## All other devices

Make a **new** Setup URI on a device that works. Do not use the URI from the
provision:

1. On the device that works, go to Self-hosted LiveSync settings →
   **Setup URI**.
2. Copy the URI, or show the QR code.
3. On the new device, install the plugin.
4. Import the URI with the same command as for the first device.
5. Type the passphrase of the new URI.
6. Let the device download the vault.

### iPhone and iPad

- The server must have a TLS certificate that is valid in public. Caddy gives
  one. A self-signed certificate does not work.
- The QR code from the desktop plugin is the easiest way to move the URI.
- Obsidian on iOS stops when it is in the background. After many edits on
  other devices, open the app and keep it in the foreground for some seconds.
  If not, sync looks slow, but the app only sleeps.
- For a large first sync, keep the device awake and on Wi-Fi.

### Other desktops

Do the same steps as for the first device, but do **not** do the first
upload. Let the desktop pull the existing vault down. If two computers upload
at the same time, one database gets two different document trees.

## Where this fits

You connect the devices as part of the procedure to add a vault ([`vaults.md`](vaults.md)):

1. Run `add-vault.sh`.
2. While it waits, connect the first device.
3. When the upload is quiet, the script connects the vault to the server.
4. Connect the other devices.

Finish one vault before you start the next.
