# AppaRent Contribution Guide

AppaRent is a neighborhood marketplace prototype built with Elm and elm-pages. Prefer Elm for application behavior and presentation. Node.js is required by elm-pages' framework runtime and command-line tooling, but do not move application logic into JavaScript.

## Architecture

- Use elm-pages routes, `BackendTask`, and forms according to the existing framework patterns. Do not introduce a second router or a separate HTTP backend without updating this guide and the backlog.
- Keep domain rules and validation in pure Elm modules so they can be tested independently of page rendering.
- Prefer custom types for finite choices and validated values. Use smart constructors for values with invariants, and model mutually exclusive UI modes with custom types rather than parallel booleans and `Maybe` fields.
- Use records for cohesive data that can validly exist together; do not force records onto finite alternatives or mutually exclusive states.
- Keep file persistence behind the smallest possible elm-pages `BackendTask.Custom` adapter. Validate, encode, decode, expire, and otherwise interpret listing content in Elm; Node code should perform only the filesystem boundary operations.
- Treat all user-submitted values as untrusted. Validate values at the server boundary as well as in the UI.
- The prototype is not an authenticated or multi-user production service. Do not treat a client-provided profile identifier as authorization or enter real personal information.
- Be explicit about persistence and deployment assumptions. Do not imply that in-memory or browser-local data is shared or durable.

## Development

- Prefer small, typed Elm modules and explicit custom types over stringly typed state.
- Add or update tests for domain behavior and user-visible workflows.
- Format Elm files with `elm-format`; keep JavaScript and JSON consistent with the existing project tooling.
- Run the focused tests and build after each coherent change. Before completing work, run the project-wide test, format, and build commands documented in `README.md`.
- Update `BACKLOG.md` when completing or reprioritizing work, and update `README.md` when setup or capabilities change.
- Inspect the staged diff before committing. Commit only project files related to the task.
- Do not commit `node_modules`, `elm-stuff`, generated build output, IDE metadata, credentials, or real personal data.

## Scope and safety

The current marketplace stores server-created listings as individual text files in `data/listings/`. A deployment must provide persistent writable local storage for this to be durable; serverless ephemeral filesystems are not suitable. Listings expire after seven days and are permanently deleted on a subsequent listings API request. Sample listings are generated with the build and are separate from the server file store. Authentication, ownership, payments, moderation, dispute handling, durable notifications, backups, and production data retention require deliberate design before public deployment.
