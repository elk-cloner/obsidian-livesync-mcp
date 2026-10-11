# Setup

The quick start (`../../docs/quickstart.md`) and `sudo ./scripts/bootstrap.sh`
do these steps for you. This page explains each step, for a manual setup or
to repair one step.

This setup makes a backend with **no vaults**. At the end, Claude can
connect and the timers run, but there is nothing to sync. Then add the vaults
one at a time with [`vaults.md`](vaults.md). New vaults and existing vaults
use the same steps.

Do the steps in this order. Mobile devices cannot sync before TLS works.

## What `bootstrap.sh` does

`bootstrap.sh` does sections 2 to 9 of this page. Each step checks first and
skips the work that it did before. It does not change a value that `.env` has
already. The placeholders of `.env.example`, for example `example.com`, count
as not set. If a step fails, repair the cause and run the script again. It
continues from that step.

| Section | Bootstrap step | What the script does | What you do |
|---|---|---|---|
| 1. DNS | 3. DNS | Checks that the two names point at the public IPv4 address of the server. | Make the A records. |
| 2. Host prerequisites | 1. Tools | Checks the tools and shows the install command of each missing tool. | Install the tools. Clone the repository. |
| 3. Secrets | 2. `.env` | Makes `.env` (mode 600). Asks for the missing values. Makes the random secrets and the passphrase. | Store the passphrase. |
| 4. Directories | 4. Folders | Makes the folders with the correct owners. | Nothing. |
| 5. CouchDB behind TLS | 5. CouchDB and Caddy | Starts the two containers and waits for `/_up` over TLS. | Nothing. |
| 6. Bridge config | 6. Bridge config | Writes `bridge/config.json` if it is missing. | Nothing. |
| 7. Google OAuth and the MCP server | 2. `.env` and 7. MCP server | Asks for the client ID and secret. Starts the MCP server and checks its OAuth discovery. | Make the Google client. Add the connector in claude.ai. |
| 8. Google Drive backup | 9. rclone remote | Checks that the remote exists, and shows the commands if not. | Run `sudo rclone config`. |
| 9. Timers | 8. Timers | Runs `install-timers.sh` if the units are old or not enabled. | Nothing. |
| 10. GitHub push (optional) | (none) | Nothing. | All of it. |
| 11. Verify | 10. Health check | Runs `doctor.sh`. | Add the first vault. |

To see what the script will do, and change nothing, run
`sudo ./scripts/bootstrap.sh --dry-run`. The script writes the secrets only to
`.env`. It shows the passphrase one time.

### Short form of the manual setup

These are the commands of sections 2 to 9, with no explanation. Sections 1
to 11 explain each command.

```bash
git clone <this repo> /opt/obsidian-self-host && cd /opt/obsidian-self-host/backend
cp .env.example .env && chmod 600 .env && "$EDITOR" .env   # fill in; leave VAULTS empty
set -a; . ./.env; set +a

sudo install -d -o 5984 -g 5984 couchdb/local.d
sudo install -d -m 755 -o 1993 -g 1993 "$VAULT_ROOT"   # uid both containers run as
sudo install -d -m 700 "$GIT_ROOT"

docker compose up -d couchdb caddy mcp
sudo ./scripts/gen-bridge-config.sh   # empty config; the bridge starts with the first vault
sudo rclone config                    # Google Drive remote for the nightly backup

sudo ./scripts/install-timers.sh      # renders the units for this checkout, enables the timers
```

Add the connector at `https://mcp.<domain>/mcp` in claude.ai. Then add the
vaults ([`vaults.md`](vaults.md)):

```bash
sudo ./scripts/add-vault.sh <name>    # creates the database, prints a Setup URI,
                                      # waits while the first device uploads
                                      # (docs/onboarding.md), then connects it
sudo ./scripts/seed-vault.sh <name>   # new vault: puts the schema in (../vault/)
```

`add-vault.sh` now offers to seed the schema at the end of its run. Thus you
need `seed-vault.sh` only if you said no, or used `--no-seed`.

## 1. DNS

*Bootstrap step 3 checks this. You make the records.*

Make two A records that point at the VPS:

| Name | Service |
|---|---|
| `couch.<domain>` | CouchDB |
| `mcp.<domain>` | the MCP server |

CouchDB must be at the **root** of its own subdomain. Under a path, LiveSync
fails with "404 Database not found". To repair that, you must also proxy
`/_session` and rewrite the path. That is too much work for no gain.

## 2. Host prerequisites

*Bootstrap step 1 checks the tools. It does not install them.*

```bash
# Docker, Deno 2 (for the upstream provisioner), rclone, git
curl -fsSL https://get.docker.com | sh
curl -fsSL https://deno.land/install.sh | sh
apt-get install -y rclone git
# Only if you will push history to GitHub (section 10): the GitHub CLI.
# https://github.com/cli/cli/blob/trunk/docs/install_linux.md

git clone <this repo> /opt/obsidian-self-host
cd /opt/obsidian-self-host/backend
```

`bootstrap.sh` also checks for `jq`, `openssl`, `curl`, `python3` and the
Python `cryptography` package. To install all packages in one command, run
`apt-get install -y rclone git jq openssl curl python3 python3-cryptography`.

> **Warning:** Install Deno for root, not for your normal user. The scripts
> run with `sudo`, where `HOME` is `/root`. `_common.sh` adds only
> `$HOME/.deno/bin` to `PATH`. Run the Deno installer inside `sudo -i`.

```bash
sudo -i
curl -fsSL https://deno.land/install.sh | sh
exit
```

You can clone into any path that has no spaces. Run all commands on this page
from `backend/`. The root of the repository also holds `vault/` and
`skills/`. `vault/` is the schema that `seed-vault.sh` copies into vaults.
`skills/` holds the Claude skills.

## 3. Secrets

*Bootstrap step 2 does this. It asks for the domain, the emails, the Google
client and the rclone remote. It makes the random secrets.*

```bash
cp .env.example .env
chmod 600 .env

# Generate the ones that must be random:
openssl rand -base64 32                       # COUCHDB_PASSWORD
openssl rand -base64 48                       # JWT_SIGNING_KEY
python3 -c 'from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())'
                                              # OAUTH_STORAGE_ENCRYPTION_KEY
```

Set `LIVESYNC_PASSPHRASE` to a strong passphrase of your own. **Store it in a
password manager now.** It is the E2EE key. All devices and the bridge need
it. Without it, nothing can recover the vaults.

`bootstrap.sh` can make the passphrase for you, or you can type your own. A
passphrase that you type must have at least 12 characters and no single
quote. The script shows the passphrase one time. It writes the passphrase to
`.env` only after you type `saved`.

Leave `VAULTS` empty. `add-vault.sh` and `remove-vault.sh` manage it.

The host paths (`VAULT_ROOT`, `GIT_ROOT`, `REMOVED_ROOT`) have the defaults
`/srv/...`. To put them in a different place, change them in `.env`. Compose
and all scripts read them from `.env`. The commands below load `.env`, so they
use your values.

The scripts write a value into `.env` with `set_env_value` in
`scripts/_common.sh`. It changes only that one line and keeps the mode of the
file. It refuses a value with a single quote or a newline.

## 4. Directories

*Bootstrap step 4 does this.*

```bash
# CouchDB chowns its config directory to uid/gid 5984 on first start.
sudo chown -R 5984:5984 couchdb/local.d

set -a; . ./.env; set +a

# The mirror. Both the bridge and the MCP server run as uid 1993, so it
# must be owned by that uid -- root-owned and mode 755 would leave both
# containers able to read but not write. 1993 is fixed: the bridge's base
# image ships that user.
sudo install -d -m 755 -o 1993 -g 1993 "${VAULT_ROOT:-/srv/vaults}"

# History repos, driven by root via systemd, deliberately outside the mirror.
sudo install -d -m 700 "${GIT_ROOT:-/srv/git}"
```

The rules behind these commands:

- CouchDB writes its `docker.ini` into `couchdb/local.d`, so uid 5984 must
  own the folder.
- The bridge and the MCP server both run as uid 1993, so uid 1993 must own
  the mirror. If root owns it with mode 755, the containers can read but
  cannot write.
- The uid 1993 is not a setting. The base image of the bridge has that user.
- The history repositories are outside the mirror on purpose. Root runs them
  through systemd.

## 5. CouchDB behind TLS

*Bootstrap step 5 does this. It waits up to two minutes for `/_up`.*

```bash
docker compose up -d couchdb caddy
docker compose logs -f caddy          # watch the certificate get issued
set -a; . ./.env; set +a              # load DOMAIN and the CouchDB login
curl -fsS -u "$COUCHDB_USER:$COUCHDB_PASSWORD" https://couch.$DOMAIN/_up
# {"status":"ok", ...}  (a 401 means it was asked without the login)
```

The correct result is `{"status":"ok", ...}`. A 401 means that the request
had no login.

If `/_up` does not answer:

1. Look at the certificate issue: `docker compose logs caddy`.
2. Make sure that `couch.<domain>` points at the server.
3. Make sure that ports 80 and 443 are open.
4. Look at CouchDB: `docker compose logs couchdb`.

CouchDB loads its LiveSync settings from `couchdb/local.d/10-livesync.ini`
when it starts. `add-vault.sh` makes the database of each vault later. It
also runs the upstream provisioner for that database.

## 6. Bridge config

*Bootstrap step 6 does this.*

```bash
sudo ./scripts/gen-bridge-config.sh    # writes bridge/config.json with no vaults
```

Do not start the bridge yet. `add-vault.sh` starts it when it connects the
first vault.

Make the file now all the same. If `bridge/config.json` is missing when a
command starts the bridge, Docker makes a *directory* with that name. Docker
shows no message. The bridge then fails with a parse error that does not
tell you the cause. If an empty directory is there, `bootstrap.sh` removes it
and writes the file.

> **Warning:** Do not run `docker compose down --volumes`. It deletes the
> `localStorage` of the bridge, and the bridge must then scan everything again.

## 7. Google OAuth and the MCP server

*Bootstrap step 2 asks for the client ID and secret. Bootstrap step 7 starts
the MCP server and checks its OAuth discovery. You make the Google client
and add the connector.*

Open [Google Cloud Console](https://console.cloud.google.com/auth/overview).
Go to **Google Auth Platform** (the old name is "OAuth consent screen"):

1. Go to **Overview → Get started.** Type an app name, and your email as the
   support email.
2. Select **Audience: External**. "Internal" exists only for Google Workspace
   organizations.
3. Type your email as the contact. Accept the policy. Click **Create**.
4. Go to **Audience → Test users → Add users.** Add your own address, the
   same one as `ALLOWED_EMAIL`. No other person needs access.
5. Go to **Audience → Publish app** (recommended). The reason follows this list.
6. Go to **Clients → Create client** → Web application.
7. Set the Authorized redirect URI to `https://mcp.<domain>/auth/callback`.
   It must be exact: this is the default `redirect_path` of FastMCP.
8. Copy the secret immediately. The Console can show it in full only one time.
9. Put the client ID and the secret in `.env`.

You can keep Branding, Data Access and Verification Center as they are. The
server asks only for `openid` and `userinfo.email`. These basic scopes need
no review.

Publish the app as the default. If the publishing status stays on
**Testing**, Google ends each sign-in after 7 days. The connector then asks
you to connect again each week. With only basic scopes, a published app gets
no review. `ALLOWED_EMAIL` continues to refuse all other accounts. If you
keep **Testing**, your address must stay a test user.

Do **not** register the callback of Claude
(`https://claude.ai/api/mcp/auth_callback`) with Google. The OAuth proxy of
FastMCP ends that part of the flow itself.

Start the MCP server and check the three requests that Claude makes first.
`bootstrap.sh` uses `docker compose up -d --build mcp`, so it also builds new
code.

```bash
docker compose up -d mcp

# Claude's first request looks like this:
curl -i https://mcp.$DOMAIN/mcp
# expect: 401 with
#   www-authenticate: Bearer ... resource_metadata="https://mcp.<domain>/.well-known/oauth-protected-resource/mcp"

curl -s https://mcp.$DOMAIN/.well-known/oauth-protected-resource/mcp | jq .
# "resource" must equal https://mcp.<domain>/mcp exactly

curl -s https://mcp.$DOMAIN/.well-known/oauth-authorization-server | jq \
  '{code_challenge_methods_supported, registration_endpoint,
    client_id_metadata_document_supported, token_endpoint_auth_methods_supported}'
# S256, a registration endpoint, and both CIMD markers
```

| Request | Correct result |
|---|---|
| `/mcp` | 401, with a `www-authenticate` header that names `resource_metadata` |
| `/.well-known/oauth-protected-resource/mcp` | `"resource"` is exactly `https://mcp.<domain>/mcp` |
| `/.well-known/oauth-authorization-server` | S256, a registration endpoint, and the two CIMD markers |

Then add the connector in claude.ai:

1. Go to **Customize → Connectors → + → Add custom connector**.
2. Type the URL `https://mcp.<domain>/mcp`.
3. Sign in with Google when claude.ai asks.

## 8. Google Drive backup

*Bootstrap step 9 checks that the remote exists. You make the remote.*

Google Drive is the default copy outside the server. Make the rclone remote
that `RCLONE_REMOTE` names:

```bash
sudo rclone config     # choose "drive"; use the headless flow and paste the
                       # token from a browser on your computer
sudo rclone lsd gdrive:
```

Use `sudo`. The backup timer runs as root and uses the rclone configuration of
root. All other parts work without the remote. `doctor.sh` shows a warning
until the remote exists.

## 9. Timers

*Bootstrap step 8 does this.*

```bash
./scripts/install-timers.sh --dry-run   # optional: see the units it will write
sudo ./scripts/install-timers.sh
```

The units in `systemd/` are templates. The script puts the path of this
checkout into them, installs them, verifies them and enables the three timers.
Run it again after you move the checkout or pull changes to the units.

With no vaults, each run writes "No vaults configured" to the log and
succeeds. The timers find the vaults that you add later.

`vault-git.timer` keeps local history for each vault in `$GIT_ROOT/<vault>.git`.
It needs no setup, and it gives a 15-minute undo for bad edits.

## 10. Optional: push history to GitHub

*Bootstrap does not do this.*

This push is off by default. The Drive backup is the copy outside the server.
To also push the history of each vault to its own private GitHub repository:

1. Install the GitHub CLI (section 2).
2. Log in **as root**, because the timer runs as root:
   ```bash
   sudo gh auth login
   ```
3. Set `GIT_PUSH=github` in `.env`.
4. To put the repositories under an organization, set `GIT_REMOTE_OWNER`.
   By default, they go to the account that `gh` uses.
5. For each existing vault, run `sudo ./scripts/add-vault.sh <name>` one more
   time.

Your GitHub account, the token and its permissions are yours to manage. The
scripts only use the login. The token must have permission to make
repositories and to push to them.

In step 5, `add-vault.sh` makes the private repository, or uses an existing
one. Then it pushes the history. A new vault gets its repository when you add
it.

If the login expires, each push writes a warning to the log. Local history
continues.

## 11. Verify, then add your first vault

*Bootstrap step 10 runs `doctor.sh`.*

1. Run `sudo ./scripts/doctor.sh`.
2. Do the verification checklist in [`runbook.md`](runbook.md).
3. Add the vaults with [`vaults.md`](vaults.md).
4. For a new vault, accept the schema offer at the end of `add-vault.sh`.
   Or, after the vault is connected, run `sudo ./scripts/seed-vault.sh <name>`.
5. Install the skills that work with the vault: read
   [`skills/README.md`](../../skills/README.md).
