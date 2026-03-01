# Meaning To - Project Documentation

## Overview
Meaning To is a Flutter application designed to help users manage tasks and categories, with special features for handling links and media content. The app uses Supabase for backend services and provides a modern, intuitive user interface.

## Core Modules

### Models

#### Category (`lib/models/category.dart`)
Represents a category or collection of tasks.

**Properties:**
- `id` (int): Unique identifier
- `headline` (String): Category name
- `invitation` (String?): Optional invitation text
- `ownerId` (String): User ID of the category owner
- `createdAt` (DateTime): Creation timestamp
- `updatedAt` (DateTime?): Last update timestamp
- `originalId` (int?): Reference to original category if copied
- `triggersAt` (DateTime?): Scheduled trigger time
- `template` (String?): Template identifier

**Methods:**
- `fromJson(Map<String, dynamic>)`: Factory constructor from JSON
- `toJson()`: Convert to JSON map
- `operator ==`: Equality comparison
- `hashCode`: Hash code generation

#### Task (`lib/models/task.dart`)
Represents a task within a category.

**Properties:**
- `id` (int): Unique identifier
- `categoryId` (int): Parent category ID
- `headline` (String): Task title
- `notes` (String?): Optional task notes
- `ownerId` (String): User ID of the task owner
- `createdAt` (DateTime): Creation timestamp
- `suggestibleAt` (DateTime?): When task becomes available
- `triggersAt` (DateTime?): Scheduled trigger time
- `deferral` (int?): Deferral duration in minutes
- `links` (List<String>?): Associated URLs
- `processedLinks` (List<ProcessedLink>?): Processed link data
- `finished` (bool): Completion status

**Key Methods:**
- `loadTaskSet(Category, String)`: Load tasks for a category
- `loadRandomTask(Category, String)`: Get a random task
- `rejectCurrentTask()`: Reject the current task
- `finishCurrentTask()`: Mark current task as complete
- `getSuggestibleTimeDisplay()`: Get formatted deferral time
- `ensureLinksProcessed()`: Process task links for display

#### DomainIcon (`lib/models/icon.dart`)
Handles domain icons and favicons.

**Properties:**
- `domain` (String): Website domain
- `iconUrl` (String): Icon URL
- `iconData` (Uint8List?): Binary icon data

**Key Methods:**
- `fetchIconData()`: Download and process icon
- `getIconForDomain(String)`: Get icon for a domain
- `validateIconUrl(String)`: Validate icon URL
- `clearCache()`: Clear icon cache
- `getCacheStats()`: Get cache statistics

### Utilities

#### LinkExtractor (`lib/utils/link_extractor.dart`)
Extracts and processes links from text.

**Key Methods:**
- `extractLinkFromString(String)`: Extract link from text
- `parseLinksFromJson(List<dynamic>)`: Parse links from JSON

#### LinkProcessor (`lib/utils/link_processor.dart`)
Processes and displays links.

**Key Methods:**
- `processLinkForDisplay(String)`: Process single link
- `processLinksForDisplay(List<String>)`: Process multiple links
- `determineLinkType(String)`: Determine link type
- `fetchWebpageTitle(String)`: Get webpage title
- `buildLinksList(List<ProcessedLink>)`: Build link display widget

### Screens

#### HomeScreen (`lib/home_screen.dart`)
Main application screen.

**Features:**
- Category management
- Task display and interaction
- Random task selection
- Task completion/rejection

#### EditCategoryScreen (`lib/edit_category_screen.dart`)
Category editing interface.

**Features:**
- Category creation/editing
- Task management
- Link import from clipboard
- Task list display

#### ImportJustWatchScreen (`lib/import_justwatch_screen.dart`)
Specialized screen for importing JustWatch content.

**Features:**
- JSON file import
- Content parsing
- Task creation from media items

### App Structure

#### MeaningToApp (`lib/app.dart`)
Main application widget.

**Routes:**
- `/`: HomeScreen
- `/auth`: AuthScreen
- `/edit-category`: EditCategoryScreen
- `/edit-task`: TaskEditScreen
- `/import-justwatch`: ImportJustWatchScreen

## Data Flow

1. **Authentication**
   - User authentication via Supabase
   - Session management
   - User-specific data access

2. **Category Management**
   - Create/edit categories
   - Category templates
   - Category sharing

3. **Task Management**
   - Task creation and editing
   - Link processing
   - Task deferral system
   - Random task selection

4. **Link Processing**
   - URL extraction
   - Link validation
   - Title fetching
   - Icon management
   - Special handling for JustWatch

## Technical Details

### Dependencies
- Flutter: UI framework
- Supabase: Backend services
- html: HTML parsing
- http: Network requests
- url_launcher: URL handling
- file_selector: File operations

### State Management
- Uses Flutter's built-in StatefulWidget
- ValueNotifier for task reloading
- Supabase real-time updates

### Data Storage
- Supabase database
- Local caching for icons
- JSON for data import/export

### Security
- Supabase authentication
- User-specific data access
- Secure API key management

## Best Practices

1. **Error Handling**
   - Comprehensive error catching
   - User-friendly error messages
   - Detailed logging

2. **Performance**
   - Icon caching
   - Efficient link processing
   - Optimized database queries

3. **Code Organization**
   - Clear module separation
   - Consistent naming conventions
   - Comprehensive documentation

4. **User Experience**
   - Intuitive navigation
   - Responsive design
   - Clear feedback mechanisms

## Implementation Plan: Deferrable Page Access Library

### Goal
Extract link/site access into a reusable library that can:
- Fetch and enrich URLs across contexts (app runtime + Supabase)
- Defer and retry enrichment when immediate fetch quality is low
- Return normalized, scored, provenance-rich results
- Leave app-specific interpretation (task fields, UI policy) to the host app

### Scope
The library will own:
- URL normalization/canonicalization
- Site rule matching and fetch strategy orchestration
- Metadata extraction (title/synopsis + optional generic fields)
- Quality scoring and source provenance
- Deferred fetch lifecycle (pending, retrying, complete, failed)

The app will own:
- Mapping enrichment output to task/headline/notes/synopsis
- Suggested category business policy and user-facing UX
- Final merge rules when updating existing tasks

### Proposed Package Structure
- `lib/link_enrichment_core/`
- `lib/link_enrichment_core/models/` (request/result/status/provenance)
- `lib/link_enrichment_core/rules/` (site rules, matcher, validators)
- `lib/link_enrichment_core/fetch/` (direct/proxy/api drivers, orchestrator)
- `lib/link_enrichment_core/extract/` (selector/metadata extraction)
- `lib/link_enrichment_core/score/` (quality scoring)
- `lib/link_enrichment_core/deferred/` (retry policy + scheduling contracts)

### Data Contracts
Primary input:
- `EnrichmentRequest`
  - `url`
  - `context` (`web`, `native`, `edge`, `test`)
  - `deadlineMs`
  - `allowDeferred`
  - `hints` (optional app metadata)

Primary output:
- `EnrichmentResult`
  - `normalizedUrl`
  - `title`
  - `synopsis`
  - `categoryHints` (generic tags/IDs)
  - `qualityScore` (0-100)
  - `source` (method + context + site rule id)
  - `status` (`success`, `partial`, `deferred`, `failed`)
  - `errors` (typed reason codes)

### Site Rule Model (Table-Driven)
Move site behavior into one table/schema (Dart map now, file-backed next):
- `siteId`, `domainPatterns`, `pathPatterns`
- ordered fetch methods per context
- title/synopsis extraction selectors
- normalization rules
- fallback/title-cleanup rules
- category hint rules
- quality boosts/penalties per strategy

### Storage Plan
Owner-scoped app data (existing RLS):
- Task/link-level chosen enrichment fields
- Per-item provenance summary
- Deferred status for that specific item

Internal service-owned telemetry (new internal schema, no direct client writes):
- Aggregated fetch success/latency by `{site, context, method}`
- Rule health metrics for adaptive ordering
- Anomaly flags (poisoning protection)

### Rollout Phases

#### Phase 1: Foundations
- Introduce core request/result models and typed error codes
- Add unified URL normalize/extract/match utility
- Wrap current `SiteTable` into rule-provider interface
- Add quality scoring baseline

#### Phase 2: Orchestrator
- Implement fetch orchestrator with:
  - ordered attempts per context
  - global deadline budget
  - first-success return with best-quality replacement option
- Add provenance capture for every attempt

#### Phase 3: Deferred Enrichment
- Add pending enrichment state and retry scheduler interface
- Trigger deferred retries from:
  - local app context when suitable
  - Supabase Edge function for server-side retries
- Add idempotent merge/update path for better-later results

#### Phase 4: App Integration
- Replace direct calls in:
  - `LinkProcessor`
  - `LinkToTaskConverter`
  - `SynopsisFetcher`
  - `IntentHandler` category suggestion path
- Keep app-specific mapping in adapter layer

#### Phase 5: Adaptive Optimization
- Record aggregated success/latency stats
- Dynamically reorder methods by site/context health
- Add hedged fetch option for slow first attempts

### Testing Strategy
- Keep example-driven regression tables (existing link-to-task fixtures)
- Add rule-conformance tests for each site-rule row:
  - URL match behavior
  - canonicalization idempotence
  - extraction strategy validity
  - fallback behavior
- Add orchestrator tests for deadline, retries, and merge determinism

### Migration Strategy
- Ship behind feature flag: `useLinkEnrichmentCore`
- Dual-run in shadow mode on selected links (compare old vs new outputs)
- Promote by route:
  1. task creation
  2. link edit verification
  3. background/deferred enrichment
- Remove legacy per-site conditionals after parity targets are met

### Exit Criteria
- New site onboarding requires only table/rule changes in >90% of cases
- Median task-from-link latency reduced for problematic sites
- Deferred enrichment success rate improves metadata completeness
- No direct client-writable global telemetry paths
