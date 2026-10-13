# AppaRent Contribution Guide

AppaRent is a static Elm marketplace frontend hosted on GitHub Pages and connected directly from browsers to Oracle Autonomous Database through Oracle REST Data Services (ORDS). There is no application server, Node.js, or npm dependency.

## Architecture

- Keep UI and domain behavior in the Elm `Browser.element` app at `app/Main.elm` and pure modules under `src/`.
- Keep browser database transport in the single `public/app.js` file. It may only load the public ORDS URL and issue the GET/POST requests requested by Elm ports; do not add database credentials or domain/UI logic there.
- Keep listing invariants, validation, JSON codecs, and expiry in pure Elm modules under `src/`.
- Keep the REST contract and database-side validation/expiry in `sql/oracle-ords.sql`. The ORDS module exposes only the collection GET and create POST handlers.
- Never put database credentials, access tokens, wallet data, or other secrets in browser code, static configuration, or Git. Static clients cannot keep secrets.
- Treat all browser submissions as untrusted. Validate in Elm for UX and enforce the same constraints in ORDS and Oracle.
- CORS is not authentication. Public write endpoints can be called outside browsers and need deliberate abuse controls before production use.
- Explicitly document that GitHub Pages serves static files only and that requests depend on a separate reachable ORDS endpoint.

## Development

- Prefer custom types, smart constructors, and small Elm modules over stringly typed state.
- Add/update Elm tests for domain behavior and the ORDS JSON contract.
- Format Elm files with `elm-format`; keep JSON, SQL, YAML, and Markdown consistent with existing styles.
- Compile with the standalone Elm compiler (`elm make app/Main.elm --output=public/elm.js --optimize`) and update the checked-in `public/elm.js` whenever Elm sources change.
- Verify the static app and JavaScript adapter with a local static file server; GitHub Pages deploys the checked-in `public/` files without a Node/npm build.
- Update `BACKLOG.md` and `README.md` when capabilities, deployment, or database setup change.
- Inspect the staged diff before committing. Commit only project files related to the task.
- Do not commit `elm-stuff`, `dist`, credentials, or real personal data.

## Scope and safety

Listings are public, unauthenticated submissions with free-form public contact details. Oracle creates listing IDs and seven-day expiries; the public GET endpoint omits expired rows, and a scheduled database job permanently deletes them hourly. This prototype has no accounts, ownership, moderation, or abuse controls and is not suitable for unrestricted production traffic or real personal information.
