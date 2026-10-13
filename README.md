# AppaRent

AppaRent is a static Elm marketplace frontend. It runs in the visitor's browser and calls Oracle Autonomous Database's Oracle REST Data Services (ORDS) endpoints directly. There is no elm-pages server, app server, Node runtime service, or database credential in the frontend. GitHub Pages can host the compiled static files; Oracle hosts the REST API and listing data.

## Develop and build

Requires Node.js/npm for the Elm compiler and formatter, plus Python 3 for the optional local static-file server.

```bash
npm ci
npm run build
npm run dev
```

`npm run build` compiles `app/Main.elm` to `public/elm.js`. `npm run dev` builds the app and serves `public/` at `http://localhost:8000`. Set up the Oracle database and edit `public/ords-config.json` before expecting remote listings to load.

Run the checks:

```bash
npm test
npm run format:check
npm run build
```

## Create the Oracle REST API

1. Create an Always Free Autonomous Transaction Processing database in Oracle Cloud. In its database actions/SQL worksheet, connect as `ADMIN` and create a dedicated schema owner:

   ```sql
   CREATE USER APPARENT_OWNER IDENTIFIED BY "<strong unique password>";
   GRANT CREATE SESSION, CREATE TABLE, CREATE TRIGGER, CREATE JOB TO APPARENT_OWNER;
   ALTER USER APPARENT_OWNER QUOTA 50M ON DATA;
   ```

2. Connect the SQL worksheet as `APPARENT_OWNER` and run [`sql/oracle-ords.sql`](sql/oracle-ords.sql). It creates a constrained listing table, server-generated IDs and seven-day expiries, an expiry index and cleanup job, and an ORDS module with only a public `GET /listings/` and validated `POST /listings/`. The ORDS GET response is its standard collection-feed JSON (`items` array); Elm decodes those rows. The script is a one-time installation, not an idempotent migration.
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
5. Test the GET endpoint in a browser or with `curl`; verify its response contains an `items` array with listing fields such as `listing_id`, `price_cents`, and `expires_at_ms`. Then build the frontend and test creating a demo listing.

The database API intentionally permits unauthenticated listing reads and submissions so a purely static browser client can use it without a secret. Oracle validates field lengths, finite categories/neighborhoods, and prices in the ORDS POST handler and table constraints. However, anyone can call a public endpoint outside a browser: CORS does not prevent bots or direct API clients from creating records. This is a prototype, not a production public write API; add authentication and abuse/rate controls before inviting unrestricted use.

## Publish on GitHub Pages

The included [GitHub Actions workflow](.github/workflows/pages.yml) builds the Elm app and publishes the `public/` directory. Before publishing, commit the correct public ORDS `apiBaseUrl` in `public/ords-config.json`, enable GitHub Pages with **GitHub Actions** as the source, and add the final `https://<account>.github.io` site origin to the ORDS module's allowed origins.

No OCI Compute VM or long-running Node server is needed. The browser connects to the Autonomous Database REST endpoint over HTTPS. Static hosting and database REST availability are independent services, so the page itself can load while listing requests fail if ORDS, CORS, or the database is unavailable.

## Architecture and limits

- `app/Main.elm` is a `Browser.element` Elm application. It owns the UI state and communicates with ORDS using `elm/http`.
- `src/Marketplace.elm` contains pure domain types, smart constructors, validation, expiry, and JSON decoding. Contact details are public plain text.
- `sql/oracle-ords.sql` defines the database table, constraints, expiry cleanup, and GET/POST ORDS module.
- `public/ords-config.json` contains only the ORDS collection URL; the compiled app is `public/elm.js`.
- GitHub Pages serves static files only. Database credentials and authorization cannot be kept secret in client-side Elm.

Listings expire exactly seven days after Oracle inserts them. The GET endpoint excludes expired rows, and an hourly database job permanently deletes them. Sample listings are separate frontend demo data. The prototype has no accounts, ownership, listing management, bookings, messaging, or moderation. Publicly shared contact information and unauthenticated write access make it unsuitable for real personal information or unrestricted production use.
