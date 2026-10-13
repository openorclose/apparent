# AppaRent Backlog

Priorities: **P0** runnable foundation, **P1** core marketplace, **P2** trust and engagement, **P3** production expansion.

## Foundation

- [x] **P0** Create a standalone Elm browser app with documented setup, development, build, test, and formatting commands.
- [x] **P0** Establish reusable page layout, navigation, and responsive marketplace styling.
- [x] **P0** Add representative marketplace data and focused Elm domain tests.
- [x] **P0** Document the ORDS API, data lifecycle, deployment limits, and prototype-only workflows.

## Marketplace

- [x] **P1** Browse listings with search, category, neighborhood, price sorting, and pagination.
- [ ] **P1** Create and edit a neighbor profile and durable listings owned by authenticated neighbors.
- [ ] **P1** Let listing owners manage availability and remove listings safely.
- [x] **P1** Add in-page listing details and a direct-to-ORDS create listing flow.
- [x] **P1** Let a sharer provide free-form public contact information and have neighbors contact them directly outside the app.
- [x] **P1** Persist listings through Oracle REST Data Services and permanently remove them after seven days.
- [ ] **P1** Add dated borrowing requests with overlap checks, owner decisions, and renter cancellation.

## Trust and engagement

- [ ] **P2** Add a return flow and post-completion participant reviews.
- [ ] **P2** Add reporting/moderation, community guidance, and privacy controls.
- [ ] **P2** Add reliable notifications and delivery/read status.
- [ ] **P2** Evaluate image upload, listing condition, and pickup/return details.

## Production readiness

- [ ] **P3** Design durable authentication and authorization before enabling multi-user actions.
- [x] **P3** Choose durable shared storage and static GitHub Pages hosting with direct ORDS requests.
- [ ] **P3** Define payment, cancellation, refund, and dispute responsibilities before adding transactions.
- [ ] **P3** Review accessibility, localization, privacy, backups, observability, and data retention.

## Engineering

- [x] **P1** Add GitHub Pages CI for Elm formatting, pure domain tests, and static builds.
- [ ] **P2** Add route-level interaction tests for marketplace filters and listing creation.
- [ ] **P2** Add ORDS authentication and abuse controls before enabling public multi-user write access.
