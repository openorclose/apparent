# AppaRent

AppaRent is a neighborhood marketplace prototype built with Elm and elm-pages. Browse useful things neighbors are sharing, filter by category and neighborhood, inspect a listing, or add an item to the shelf.

## Run locally

Requires Node.js 20 or newer and npm. elm-pages uses Node.js for its development/build runtime; marketplace behavior and domain logic are written in Elm.

```bash
npm install
npm run dev
```

Open the local URL printed by elm-pages.

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
- `app/Shared.elm` provides the shared Elm page shell. Styling is in `style.css`.
- `tests/MarketplaceTests.elm` covers pure domain behavior.

The marketplace has a server-rendered `/api/listings` endpoint. New listings are validated in Elm and persisted as individual JSON-formatted `.txt` files under `data/listings/` (override with `APPARENT_LISTINGS_DIR`). Contact details are free-form and shown publicly on each listing. Listings expire exactly seven days after creation; expired files are permanently deleted the next time the API is queried, and the open page hides expired entries as its clock advances.

The file store is intended for local development or a single server with a persistent writable disk. It is not a shared or durable store on ephemeral/serverless filesystems, and it has no account or ownership system. Authentication, booking workflows, payments, moderation, backups, and production privacy/security policies remain future work. Do not enter real personal information or deploy as a public marketplace. Replace the reserved `.example` canonical URL in `app/Site.elm` before any deployment.
