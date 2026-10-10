# Device onboarding

Devices are onboarded with a **Setup URI** — a single encrypted string holding
the server URL, credentials and passphrase. It beats typing an E2EE passphrase
into an iPhone, and it guarantees every device uses identical settings, which
is what prevents the "tweak mismatch" warnings.

## Generate a Setup URI

On the server (needs Deno 2):

```bash
cd /opt/obsidian-self-host
set -a; . ./.env; set +a

hostname="https://couch.$DOMAIN" \
database="<vault>" \
username="$COUCHDB_USER" \
password="$COUCHDB_PASSWORD" \
passphrase="$LIVESYNC_PASSPHRASE" \
uri_passphrase="<a short one-time code you'll type on the device>" \
  deno run --allow-env --allow-net \
  https://raw.githubusercontent.com/vrtmrz/obsidian-livesync/main/utils/couchdb/generate_setup_uri.ts
```

Three separate secrets are in play here; keep them distinct:

| Secret | Purpose |
|---|---|
| `passphrase` | the vault's E2EE key — same on every device, forever |
| `uri_passphrase` | protects this one URI in transit; throwaway |
| `id_recovery_code` | printed on first run; save it to regenerate URIs later |

The URI is ephemeral and expires. Generate it when you are at the device, not
in advance.

## First device

This device holds the vault's starting content (an empty vault, for a new one),
because its first sync is a full upload.

1. Obsidian → Settings → Community plugins → browse → **Self-hosted LiveSync**
   → install and enable.
2. In the plugin's setup wizard, choose to import a Setup URI and paste it.
3. Enter the `uri_passphrase`.
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

Then on the new device: install the plugin, import the URI, enter the
`uri_passphrase`, and let it sync down.

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
`add-vault.sh` once to create the database, onboard the first device, run
`add-vault.sh` again to connect the server, then onboard the remaining devices.
Finish one vault before starting the next.
