# Device onboarding

Devices are onboarded with a **Setup URI**: a single encrypted string holding
the server URL, credentials and passphrase. It beats typing an E2EE passphrase
into an iPhone, and it guarantees every device uses identical settings, which
is what prevents the "tweak mismatch" warnings.

## Where Setup URIs come from

- **First device of a vault:** `add-vault.sh` prints one,
  with its one-time passphrase ([`vaults.md`](vaults.md)).
- **Every other device:** copy one from a device that already syncs the vault
  (see below). No server step.

A Setup URI and its passphrase are only for setting up a device, right away.
The generator says "store it safely", but there is nothing to keep: the URI
expires (at the next Thursday 00:00 UTC, so possibly within hours; the exact
time is printed), and a fresh one is always one command or one click away.

**Always set devices up from a Setup URI, never by hand.** Newer LiveSync
versions default a new vault to a random "ID key", which changes how document
IDs are computed. livesync-bridge cannot be given that key, so it would stop
matching the devices' documents. The URIs from `add-vault.sh` use legacy IDs
derived from `LIVESYNC_PASSPHRASE`; that is also why there is no ID recovery
code to save. If LiveSync ever asks about the ID key, choose **Keep current
configuration**.

To generate a first-device URI again without `add-vault.sh` (on the server):

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

This device holds the vault's starting content (an empty vault, for a new one),
because its first sync is a full upload.

1. Obsidian → Settings → Community plugins → browse → **Self-hosted LiveSync**
   → install and enable.
2. In the plugin's setup wizard, choose to import a Setup URI and paste the one
   from `add-vault.sh`.
3. Enter the passphrase printed with it.
4. Accept the suggested settings. When asked about the "Hidden File Sync"
   feature, **decline** — device config is deliberately not synced here
   (see the decision note in [`runbook.md`](runbook.md)).
5. Let the initial upload finish completely. The status bar stops showing
   pending counts; the log shows no further activity.

Confirm on the server:

```bash
curl -fsS -u "$COUCHDB_USER:$COUCHDB_PASSWORD" \
  "https://couch.$DOMAIN/<vault>" | jq '.doc_count'
```

## Every further device

Generate a **fresh** Setup URI from the already-working device, not from the
provisioning-time one:

Obsidian → Self-hosted LiveSync settings → **Setup URI** → copy / show QR.

Then on the new device: install the plugin, import the URI, enter its
passphrase, and let it sync down.

### iPhone and iPad

- A publicly valid TLS certificate is required. Caddy provides this; a
  self-signed certificate will not work.
- The QR code from the desktop plugin is the easiest transfer route.
- Obsidian on iOS suspends in the background. Open the app and leave it in the
  foreground for a moment after heavy edits elsewhere, or it will look like
  sync is lagging when it is simply asleep.
- On a large first sync, keep the device awake and on Wi-Fi.

### Other desktops

Same as the first device, except it should **not** do the initial upload — let it pull
an existing vault down. If both machines upload independently you get two
divergent document trees in one database.

## Where this fits

Onboarding happens inside adding a vault ([`vaults.md`](vaults.md)): run
`add-vault.sh`, onboard the first device while it waits, and it connects the
vault to the server once the upload has settled. Then onboard the remaining
devices. Finish one vault before starting the next.
