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

This first prototype uses in-memory sample listings. Listings created in the UI exist only for the current page session; reloads and other visitors do not share them. Neighbor messaging is not implemented. Authentication, durable storage, booking workflows, payments, moderation, and production privacy/security policies are future work. Do not enter real personal information or deploy as a public marketplace. Replace the reserved `.example` canonical URL in `app/Site.elm` before any deployment.
