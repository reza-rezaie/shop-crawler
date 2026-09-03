# web-frontend Specification

## Purpose

Defines how the browsable web UI is built and delivered: the framework it
is built with, the toolchain that builds it, and the contract that its
build output is static assets served by the existing backend process
rather than a separate web server. Also fixes the requirement that
re-platforming the UI must not change what a user sees or can do.

## Requirements

### Requirement: Web UI is delivered as static assets served by the backend
The built web UI SHALL consist of static files (HTML, CSS, JavaScript,
and other assets) with no server-side rendering performed at request
time. These files SHALL be served by the existing backend HTTP process
that also serves the `/api/*` routes. The system SHALL NOT require a
separate long-running web-server process to serve the UI.

#### Scenario: Single-process run serves both UI and API
- **WHEN** a developer builds the frontend and then starts the backend
  server
- **THEN** the backend process serves the UI at its root path and
  continues to serve the JSON API under `/api/*` from that same process,
  with no other server running

#### Scenario: Unknown client-side path falls back to the app shell
- **WHEN** an HTTP GET request targets a path that is neither an existing
  static file nor an `/api/*` route
- **THEN** the backend responds with the UI's entry HTML document, so
  client-side navigation still resolves, matching the fallback behaviour
  that existed before the migration

#### Scenario: Build output is missing
- **WHEN** the backend server starts and the frontend has not been built
- **THEN** the API still works and requests for the UI return a clear
  message explaining which command to run to build it

### Requirement: Frontend builds without a Node.js or npm installation
Building the web UI SHALL require only the project's pixi-provisioned
toolchain, including a pixi-provisioned Bun. It SHALL NOT require a
separately installed Node.js runtime or npm client.

#### Scenario: Clean checkout builds with pixi only
- **WHEN** a developer who has pixi but no separately installed Node.js
  or npm runs the project's frontend install and build tasks
- **THEN** the install and build complete successfully and produce the
  static output directory the backend serves

#### Scenario: CI builds the frontend without a Node provisioning step
- **WHEN** the automated CI workflow runs its checks
- **THEN** it installs dependencies and builds the frontend using the
  pixi environment only, with no step that installs or configures
  Node.js

### Requirement: Web UI is built with Next.js configured for static export
The web UI SHALL be a Next.js application using the App Router, and its
production build SHALL be a static export: a directory of static files
that can be served without a running Next.js server.

#### Scenario: Production build emits a static export
- **WHEN** the frontend production build runs
- **THEN** it writes a directory of static files, including an entry
  HTML document at its root, and requires no Next.js runtime to serve
  them

#### Scenario: Dev server proxies API calls to the backend
- **WHEN** the frontend development server is running and the UI issues a
  request to an `/api/*` path
- **THEN** that request is forwarded to the Mojo/Python backend, so the
  dev server can be used without CORS configuration, matching the
  proxy behaviour that existed before the migration

### Requirement: Existing UI behaviour is preserved across the migration
Re-platforming the UI SHALL NOT change any user-visible behaviour. Every
view, control, filter, crawl and discovery action, progress display, and
API interaction that functioned before the migration SHALL function
identically after it. No user-facing feature is added or removed by this
change.

#### Scenario: Browse, filter, and paginate products
- **WHEN** a user opens the UI, switches to the products view, and
  applies name search, category, source-host, and price filters together
  with pagination
- **THEN** the filtered, paginated results and the result-count and
  empty-state messaging behave exactly as they did before the migration

#### Scenario: Run a crawl
- **WHEN** a user submits a crawl URL with a page limit and the
  descriptions option
- **THEN** the progress bar polling, the success/warning/error status
  message, the notes list, and the automatic narrowing of the browse
  view to the crawled host all behave exactly as before

#### Scenario: Discover and view a site's category tree
- **WHEN** a user runs category discovery for a URL and then views a
  host's category tree
- **THEN** the discovery progress, status messaging, and the recursively
  rendered category tree with per-node product signals behave exactly as
  before
