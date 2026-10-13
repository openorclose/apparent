# AppaRent

AppaRent is a static Elm marketplace frontend. It runs in the visitor's browser and calls Oracle Autonomous Database's Oracle REST Data Services (ORDS) endpoints directly. There is no application server, Node.js, npm, or database credential in the frontend. GitHub Pages hosts the static files; Oracle hosts the REST API and listing data.

## Run and develop

The deployed app needs only a modern browser. To preview it locally, use Python 3's built-in static file server:

```bash
python3 -m http.server 8000 --directory public
```

Open `http://localhost:8000`. Configure Oracle and set the public ORDS collection URL in `public/ords-config.json` before expecting shared listings to load.

Elm source changes can be compiled with the standalone Elm 0.19.1 compiler, without npm or Node.js:

```bash
elm make app/Main.elm --output=public/elm.js --optimize
```

`public/elm.js` is generated and ignored; do not commit it. GitHub Pages CI downloads the standalone Elm 0.19.1 Linux compiler, builds the bundle, then uploads the complete `public/` directory as the deployment artifact. No npm or Node.js setup is required. `public/app.js` is the only hand-written JavaScript file; it loads public configuration, makes browser-native `fetch` calls to ORDS, and sends results through Elm ports. The adapter does not connect to the Oracle database protocol directly: ORDS is the HTTPS REST boundary and no database credentials belong in a static client.

## Create the Oracle REST API

1. Create an Always Free Autonomous Transaction Processing database in Oracle Cloud. In its database actions/SQL worksheet, connect as `ADMIN` and create a dedicated schema owner:

   ```sql
   CREATE USER APPARENT_OWNER IDENTIFIED BY "<strong unique password>";
   GRANT CREATE SESSION, CREATE TABLE, CREATE TRIGGER, CREATE PROCEDURE, CREATE JOB TO APPARENT_OWNER;
   ALTER USER APPARENT_OWNER QUOTA 50M ON DATA;
   ```

2. Connect the SQL worksheet as `APPARENT_OWNER` and run [`sql/oracle-ords.sql`](sql/oracle-ords.sql). It creates a constrained listing table, server-generated IDs and seven-day expiries, an expiry index and cleanup job, a database-enforced create limit, and an ORDS module with only a public `GET /listings/` and validated `POST /listings/`. The ORDS GET response is its standard collection-feed JSON (`items` array); Elm decodes those rows. This is a one-time installation, not an idempotent migration. If the existing schema and ORDS module are already installed, first grant the owner `CREATE PROCEDURE` as `ADMIN` (`GRANT CREATE PROCEDURE TO APPARENT_OWNER;`), then run [`sql/oracle-rate-limit.sql`](sql/oracle-rate-limit.sql) once instead; do not rerun the full installation script.
3. Allow cross-origin browser calls for the exact frontend origins. In the SQL worksheet as `APPARENT_OWNER`, run this after replacing the example origins with your actual GitHub Pages origin and local development origin:

   ```sql
   BEGIN
     ORDS.SET_MODULE_ORIGINS_ALLOWED(
       p_module_name => 'apparent.listings.v1',
       p_origins_allowed => 'https://YOUR-ACCOUNT.github.io,http://localhost:8000'
     );
     COMMIT;
   END;
   /
   ```

   For a project site such as `https://YOUR-ACCOUNT.github.io/apparent/`, the origin is `https://YOUR-ACCOUNT.github.io` (no project path). Do not use `*`. CORS only controls browser access; it is not authentication or an anti-abuse measure.
4. Find the database's HTTPS ORDS base URL in the OCI console. The endpoint for the SQL module above is:

   ```text
   https://<your-autonomous-database-host>/ords/apparent_owner/v1/listings/
   ```

   Edit `apiBaseUrl` in [`public/ords-config.json`](public/ords-config.json) to that full URL, including the trailing slash. This value is public configuration, not a credential. Never place database usernames, passwords, wallet contents, or API secrets in this file or any Elm/browser code.
5. Test the GET endpoint in a browser or with `curl`; verify its response contains an `items` array with listing fields such as `listing_id`, `price_cents`, and `expires_at_ms`. Then preview the static app and test creating a demo listing.

The database API intentionally permits unauthenticated listing reads and submissions so a purely static browser client can use it without a secret. Oracle validates field lengths, finite categories/neighborhoods, and prices in the ORDS POST handler and table constraints. The POST handler also atomically allows at most five creation attempts per source address per one-hour window, hashes the address before storing the bucket, and returns HTTP 429 after the limit. Missing source-address information fails closed; the hourly cleanup job removes expired rate-limit buckets. Clients sharing one public IP (for example, a household or carrier NAT) share that quota. Verify that ORDS `REMOTE_ADDR` is the actual caller address in your deployment; if it identifies a shared proxy instead, this database limit will also be shared. Do not replace it with an arbitrary `X-Forwarded-For` header, which callers can spoof unless a trusted proxy sanitizes it. The limit covers listing creation, not public GET traffic, and is a baseline abuse control rather than a substitute for an upstream WAF/API gateway and monitoring. No account or authentication is introduced.

## Publish on GitHub Pages

The included [GitHub Actions workflow](.github/workflows/pages.yml) compiles the Elm app using the standalone compiler and publishes the resulting `public/` directory without Node.js or npm. Before publishing, commit the correct public ORDS `apiBaseUrl` in `public/ords-config.json`, enable GitHub Pages with **GitHub Actions** as the source, and add the final `https://<account>.github.io` site origin to the ORDS module's allowed origins.

No OCI Compute VM or long-running Node server is needed. The browser connects to the Autonomous Database REST endpoint over HTTPS. Static hosting and database REST availability are independent services, so the page itself can load while listing requests fail if ORDS, CORS, or the database is unavailable.

## Architecture and limits

- `app/Main.elm` is a `Browser.element` Elm application. It owns the UI state and uses ports to request ORDS operations.
- `public/app.js` is the only hand-written JavaScript file. It uses the browser's native `fetch` API for public ORDS GET/POST requests and passes results to Elm over ports.
- `src/Marketplace.elm` contains pure domain types, smart constructors, validation, expiry, and JSON decoding. Contact details are public plain text.
- `sql/oracle-ords.sql` defines the database tables, constraints, expiry and rate-limit cleanup, per-source creation quota, and GET/POST ORDS module.
- `public/ords-config.json` contains only the ORDS collection URL; CI generates the ignored `public/elm.js` bundle during the Pages build.
- GitHub Pages serves static files only. Database credentials and authorization cannot be kept secret in client-side Elm or JavaScript.

Listings expire exactly seven days after Oracle inserts them. The GET endpoint excludes expired rows, and an hourly database job permanently deletes them. Sample listings are separate frontend demo data. The prototype has no accounts, ownership, listing management, bookings, messaging, or moderation. Publicly shared contact information and unauthenticated write access make it unsuitable for real personal information or unrestricted production use.
