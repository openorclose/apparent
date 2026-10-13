# AppaRent

AppaRent is a neighborhood marketplace prototype built with Elm and elm-pages. Browse useful things neighbors are sharing, filter by category and neighborhood, inspect a listing, or add an item to the shelf.

## Run locally

Requires Node.js 20.19 or newer and npm. elm-pages uses Node.js for its development/build runtime and its Oracle adapter; marketplace behavior and domain logic are written in Elm.

```bash
npm install
cp .env.example .env
# Set the Oracle connection values in .env and export them into the shell.
npm run dev
```

Open the local URL printed by elm-pages. `npm run dev` uses the project's local `.env` only if you export it yourself (for example, `set -a; . ./.env; set +a` in Bash). See **Oracle Database setup** below for connection requirements.

## Oracle Database setup

The app stores server-created listings in Oracle Autonomous Database. It uses `node-oracledb` Thin mode, so no Oracle client libraries are required. Create an Always Free Autonomous Database in Oracle Cloud, enable a TLS connection, and copy a TLS connection string for a low-priority service (for example, `..._low`). Set these server-only environment variables:

```text
ORACLE_USER=APPARENT_APP
ORACLE_PASSWORD=<strong database-user password>
ORACLE_CONNECT_STRING=<TLS connection string from OCI>
```

Do not put these values in Elm, browser code, GitHub source, or a `VITE_` variable. Keep `.env` out of Git; it is ignored. Use the database's TLS connection string, not a wallet or mTLS connect string. See [node-oracledb's Autonomous Database guide](https://node-oracledb.readthedocs.io/en/latest/user_guide/connection_handling.html#connecting-to-autonomous-database) for supported TLS connection formats.

1. In the OCI Console, create an **Always Free Autonomous Transaction Processing** database (availability depends on your home region). Choose a database admin password and retain it securely.
2. In **Database connection**, select a **TLS** connection and copy its connect string. For an app running on OCI Compute, keep the database on a reachable endpoint; prefer a private endpoint in the same VCN where available. For a public endpoint, restrict the database network access control list to the app server's egress IP rather than opening it to the internet.
3. Open the database SQL Worksheet as `ADMIN` and create separate schema-owner and runtime users. Replace both passwords with unique strong secrets; do not commit them:

   ```sql
   CREATE USER APPARENT_OWNER IDENTIFIED BY "<schema-owner password>";
   GRANT CREATE SESSION, CREATE TABLE TO APPARENT_OWNER;
   ALTER USER APPARENT_OWNER QUOTA 50M ON DATA;

   CREATE USER APPARENT_APP IDENTIFIED BY "<runtime password>";
   GRANT CREATE SESSION TO APPARENT_APP;
   ```

4. Connect to the database as `APPARENT_OWNER` and run [`sql/oracle-schema.sql`](sql/oracle-schema.sql). The script creates the listing table, JSON constraint, expiry index, and grants the runtime user only `SELECT`, `INSERT`, and `DELETE` on that table. The application does not create or migrate tables at runtime.
5. Set `ORACLE_USER=APPARENT_APP`, its password, and `ORACLE_CONNECT_STRING` in the server environment, then start the app. The app lazily opens a small connection pool, uses bind variables for SQL, and fails explicitly when configuration or database access is unavailable.

## Deploy from GitHub to Oracle Cloud

GitHub is the source repository, not the runtime host. **GitHub Pages cannot host this app's elm-pages server routes or connect securely to Oracle Database.** Run the server on an OCI Compute VM and connect it to Autonomous Database. Keep the VM and database in the same VCN and use a private database endpoint when the chosen OCI configuration supports it.

1. Push this repository to GitHub. Provision an OCI Compute VM with Node.js 20.19+ and `git`, and configure VCN/security-list rules plus a TLS reverse proxy (such as Nginx or an OCI Load Balancer); do not expose the Node port directly to the public internet.
2. Clone the repository onto the VM, install the locked dependencies, and build the elm-pages server bundle:

   ```bash
   git clone <your-github-repository-url> /opt/apparent
   cd /opt/apparent
   npm ci
   npm run build
   ```

3. Create a root-owned environment file such as `/etc/apparent.env` containing `ORACLE_USER`, `ORACLE_PASSWORD`, `ORACLE_CONNECT_STRING`, and `PORT=3000`. Restrict it with `sudo chmod 600 /etc/apparent.env`; use OCI Vault or another secret manager where available.
4. Start the built Node server with `npm run serve` (or run `node server.mjs`) and configure the reverse proxy to send requests to `127.0.0.1:3000`. For a persistent deployment, install a systemd unit using `WorkingDirectory=/opt/apparent`, `ExecStart=/usr/bin/node /opt/apparent/server.mjs`, `EnvironmentFile=/etc/apparent.env`, and `Restart=on-failure`. Keep the OCI VM patched, back up the database, and redeploy by pulling the intended Git commit, running `npm ci && npm run build`, then restarting the service.

`npm run dev` is for local development. Production uses the Node server entry point and generated elm-pages server bundle. The checked-in Netlify adapter remains available for a GitHub-connected Netlify deployment, but that is a separate hosting choice and must also be configured with the Oracle credentials and network access to the database; serverless egress addresses may complicate database IP allowlists, so the OCI VM deployment is preferred.

## Checks

Elm files are formatted with `elm-format`.

```bash
npm test
npm run format:check
npm run build
```

## Architecture and current limits

- `app/Route/Index.elm` is the stateful elm-pages marketplace route. It implements search, category and neighborhood filters, price sorting, pagination, listing details, and a create-listing dialog.
- `src/Marketplace.elm` owns the pure marketplace domain types, validation, filtering, sorting, and pagination. Finite categories and neighborhoods are custom types; prices and listing titles are opaque validated types.
- `app/Shared.elm` provides the shared Elm page shell. The production-served stylesheet is `public/style.css`.
- `custom-backend-task.js` is the Oracle Database boundary; `server.mjs` serves the generated elm-pages app on OCI Compute.
- `tests/MarketplaceTests.elm` covers pure domain behavior.

The marketplace has a server-rendered `/api/listings` endpoint. New listings are validated in Elm and stored in Oracle Database. Contact details are free-form and shown publicly on each listing. Listings expire exactly seven days after creation; expired rows are permanently deleted the next time the API is queried, and the open page hides expired entries as its clock advances.

The database is shared and durable, but this prototype still has no account or ownership system: contact details are public, and submissions are not authenticated. Authentication, booking workflows, payments, moderation, backups, and production privacy/security policies remain future work. Do not enter real personal information or deploy as a public marketplace. Replace the reserved `.example` canonical URL in `app/Site.elm` before any deployment.
