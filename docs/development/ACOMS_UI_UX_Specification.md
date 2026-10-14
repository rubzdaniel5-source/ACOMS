# ACOMS UI/UX Specification

**Document ID:** ACOMS-DESIGN-001\
**Version:** 1.0\
**Status:** Approved design direction; implementation specification\
**Product:** Airline Catering Operations Management System (ACOMS)

## 1. Purpose

This specification defines the ACOMS visual design system, global theme
behaviour, navigation, dashboard layout, shared components, responsive
behaviour, accessibility requirements, and implementation acceptance
criteria. ACOMS must feel like a polished, trustworthy enterprise
operations platform without sacrificing operational clarity, data
density, speed, or data integrity.

This is a living specification. Approved design changes must be
reflected here and in the project decision log.

## 2. Approved decisions

1.  **Two complete themes:** Aero Blue Light Mode and Slate Modern Dark
    Mode.
2.  **Default for new users:** Aero Blue Light Mode.
3.  **Theme settings:** Settings → Appearance offers **Light**,
    **Dark**, and **System**.
4.  **Global scope:** The chosen theme applies throughout ACOMS,
    including all current and future modules, not only the dashboard.
5.  **Shared design system:** Both themes use the same component
    structure, interactions, layouts, and semantic status meanings,
    driven by central design tokens.
6.  **No legacy remnants:** Inspect and migrate existing
    pages/components so hardcoded old colours or styles do not
    unintentionally override the selected theme.
7.  **Dashboard layout:** Six control cards in a 3 × 2 desktop grid and
    a 2 × 3 grid on ordinary mobile/tablet widths. Fall back to one
    column only when two columns would be unusable.
8.  **Two-level navigation:** System identity bar at the top; primary
    navigation below it, centred on desktop, with a clearly distinct
    active tab.
9.  **Preserve functionality:** Visual work must not break business
    logic, permissions, data integrity, auditability, or operational
    workflows.

## 3. Design principles

-   Operational clarity first: show what needs attention, where, why,
    and what action is available.
-   Professional, not decorative: avoid excessive gradients, glowing
    borders, oversized graphics, and unnecessary animation.
-   Progressive disclosure: show useful summaries first and detailed
    records on demand.
-   Exception-oriented: prioritise critical shortages, pending
    transfers, overdue work, and unresolved discrepancies.
-   Responsive consistency: preserve information architecture and
    essential actions across screen sizes.
-   Accessible status communication: never rely on colour alone; pair
    colours with text and, where useful, icons.
-   Data integrity: figures must come from authoritative data and
    documented definitions.
-   Permission-aware actions: the UI reflects permissions, but
    server/backend enforcement remains mandatory.
-   Maintainability: use shared tokens and reusable components rather
    than duplicated page-specific styling.

## 4. Global theme system

### 4.1 User options and defaults

Settings → Appearance must provide: - **Light:** always use Aero Blue. -
**Dark:** always use Slate Modern. - **System:** follow the
device/browser colour-scheme preference and update when it changes where
supported.

Aero Blue Light Mode is the default for new users. A saved preference
takes precedence over the default. The selected preference must persist
across sessions. Prefer account-synchronised settings if available;
otherwise use a safe local preference and document the storage strategy
and precedence.

Theme switching must not change the current route, clear form values,
alter data, change permissions, or interrupt an in-progress operation.

### 4.2 Global scope

The selected theme must apply to every current and future ACOMS area,
including: - Application shell, system header, navigation, profile and
notifications. - Dashboard and all six control cards. - Equipment
catalogue, inventory, station views, transfers, approvals, dispatch,
receipt, and reconciliation. - Damage, loss, investigations,
discrepancies, reports, charts, filters, and exports/previews. - User
profile, settings, administration, roles, permissions, and
configuration. - Forms, inputs, selects, dropdowns, menus, tabs, badges,
tooltips, popovers, dialogs, drawers, confirmation prompts, tables,
pagination, loading states, empty states, errors, and success
feedback. - Future Meal Management, Flight Catering, integrations, and
AI features. - Third-party components and charts.

A dashboard-only theme switch is not acceptable.

### 4.3 Architecture

Implement one shared design system with central semantic tokens and two
theme maps. Integrate with the existing CSS/Tailwind setup rather than
introducing another styling framework without approval.

-   Define CSS custom properties for backgrounds, surfaces, text,
    borders, primary actions, focus, and semantic statuses.
-   Apply a root theme attribute/class such as `data-theme="light"` or
    `data-theme="dark"`.
-   Map Light to Aero Blue tokens and Dark to Slate Modern tokens.
-   Use tokens instead of scattering literal colours across components.
-   Reuse components for cards, buttons, inputs, badges, alerts, tables,
    dialogs, and navigation.
-   Avoid separate duplicated component trees for each theme.
-   Avoid arbitrary one-off colours unless documented.

New users default to Light. Explicit Light or Dark overrides the device
preference. System follows device preference. Avoid a visible flash of
the wrong theme on initial load where feasible. Store only the
preference in local storage if that is the chosen fallback; do not put
secrets or private account data there.

## 5. Visual identity and colour tokens

These values are starting points. Claude may tune them to meet contrast
requirements and improve cohesion, but must document material changes
and preserve the approved design direction and semantic meanings.

### 5.1 Aero Blue --- Light Mode

  Token                      Initial value   Purpose
  -------------------------- --------------- -----------------------------
  `--color-bg`               `#F3F7FC`       Page background
  `--color-surface`          `#FFFFFF`       Cards and panels
  `--color-surface-raised`   `#FFFFFF`       Dialogs and menus
  `--color-surface-subtle`   `#EAF1FA`       Secondary surfaces
  `--color-surface-hover`    `#F0F5FC`       Hover/selected surface
  `--color-border`           `#D7E1EE`       Standard border
  `--color-border-strong`    `#B9C9DD`       Strong separation
  `--color-text`             `#14263D`       Primary text
  `--color-text-muted`       `#52657D`       Secondary text
  `--color-text-subtle`      `#657991`       Supporting metadata
  `--color-primary`          `#2563EB`       Links and primary accent
  `--color-primary-strong`   `#1D4ED8`       Primary action/active state
  `--color-primary-soft`     `#DBEAFE`       Blue-tinted surface
  `--color-focus`            `#2563EB`       Focus ring
  `--color-success`          `#15803D`       Normal/success
  `--color-success-soft`     `#DCFCE7`       Success background
  `--color-info`             `#0369A1`       Informational state
  `--color-info-soft`        `#E0F2FE`       Informational background
  `--color-warning`          `#B45309`       Warning/attention
  `--color-warning-soft`     `#FEF3C7`       Warning background
  `--color-danger`           `#B91C1C`       Critical/serious exception
  `--color-danger-soft`      `#FEE2E2`       Critical background
  `--color-surplus`          `#6D28D9`       Surplus category
  `--color-surplus-soft`     `#EDE9FE`       Surplus background
  `--color-neutral`          `#64748B`       Neutral/closed
  `--color-neutral-soft`     `#E2E8F0`       Neutral background

### 5.2 Slate Modern --- Dark Mode

  Token                      Initial value   Purpose
  -------------------------- --------------- -----------------------------
  `--color-bg`               `#0F172A`       Page background
  `--color-surface`          `#172337`       Cards and panels
  `--color-surface-raised`   `#1E293B`       Dialogs and menus
  `--color-surface-subtle`   `#1B2A40`       Secondary surfaces
  `--color-surface-hover`    `#24354B`       Hover/selected surface
  `--color-border`           `#334155`       Standard border
  `--color-border-strong`    `#475569`       Strong separation
  `--color-text`             `#F1F5F9`       Primary text
  `--color-text-muted`       `#CBD5E1`       Secondary text
  `--color-text-subtle`      `#A3B3C7`       Supporting metadata
  `--color-primary`          `#60A5FA`       Links and primary accent
  `--color-primary-strong`   `#3B82F6`       Primary action/active state
  `--color-primary-soft`     `#1E3A5F`       Blue-tinted surface
  `--color-focus`            `#93C5FD`       Focus ring
  `--color-success`          `#4ADE80`       Normal/success
  `--color-success-soft`     `#123B2A`       Success background
  `--color-info`             `#7DD3FC`       Informational state
  `--color-info-soft`        `#12354A`       Informational background
  `--color-warning`          `#FBBF24`       Warning/attention
  `--color-warning-soft`     `#453313`       Warning background
  `--color-danger`           `#F87171`       Critical/serious exception
  `--color-danger-soft`      `#451D24`       Critical background
  `--color-surplus`          `#C4B5FD`       Surplus category
  `--color-surplus-soft`     `#352451`       Surplus background
  `--color-neutral`          `#CBD5E1`       Neutral/closed
  `--color-neutral-soft`     `#334155`       Neutral background

### 5.3 Semantic colour rules

Keep meanings consistent across themes: - Green: normal/healthy and
successful completion. - Blue/cyan: information, navigation, and general
actions. - Amber/orange: warning or non-critical attention. - Red:
critical shortage, confirmed loss, urgent exception, or serious
discrepancy. - Purple: surplus. - Grey: closed, inactive, historical, or
neutral.

Every status must include readable text. Validate contrast for small
text, muted labels, badges, tinted backgrounds, and focus rings in both
themes. An inventory condition (e.g. `SHORTAGE`) must remain distinct
from a workflow state (e.g. `AWAITING APPROVAL`).

## 6. Typography, spacing, and geometry

Use a consistent legible sans-serif stack and reuse the existing project
font where suitable. Do not add a font dependency without a reason.

Suggested hierarchy: - Page title: 24--30 px desktop; 21--25 px
mobile. - Section title: 16--19 px. - Card title: 12--14 px semibold. -
Main KPI value: 28--34 px desktop; 24--30 px compact layouts. - Body:
13--15 px. - Table text: 12--14 px. - Supporting metadata: 12--13 px
with adequate contrast.

Use a 4 px spacing scale: 4, 8, 12, 16, 20, 24, 32, 40 px. Starting
defaults: page padding 24 px desktop, 16 px tablet, 12--16 px mobile;
card padding 18--22 px desktop and 14--16 px compact; grid gap 16 px
desktop and 12 px mobile; section gap 24--32 px; form-field gap 12--16
px. Use consistent 8--12 px card radii, subtle borders, restrained
shadows, and visible keyboard focus.

## 7. Application shell and navigation

### 7.1 Two-level header

**Level 1 --- System identity bar** - ACOMS logo/wordmark and system
identity on the left. - User profile/account controls on the right. -
Notifications may be placed here when implemented. - Compact,
professional, and theme-aware.

**Level 2 --- Primary navigation** - Main tabs centred horizontally on
desktop. - Active tab clearly distinct with a blue accent, tinted
surface and/or underline. - Inactive tabs remain readable but quieter. -
Initial routes may include Dashboard, Transfers, Damage & Loss, and
Reports, matching implemented functionality. - Do not present dead or
placeholder routes as working features.

On mobile, navigation may scroll horizontally or use an accessible
compact menu. It must not overlap the system identity or user controls.
Keep labels readable.

Use semantic links for navigation and buttons for actions. Menus must be
keyboard-operable and dismissible. Until a final ACOMS logo is approved,
use a clean temporary typographic wordmark; do not invent a permanent
brand mark in code.

## 8. Equipment Control dashboard

The six main elements are **Dashboard Control Cards**: each is a summary
and navigation hub, not just a decorative KPI tile.

### 8.1 Six cards and sub-KPIs

**1. Equipment Overview** - Total Equipment - Available Equipment - In
Transit - Damaged - Missing

**2. Inventory Health** - Critical Shortages - Shortages - Normal
Stock - Surplus - Critical Surplus

**3. Equipment Movement & Exchange** - Pending Transfer Requests -
Awaiting Approval - Awaiting Dispatch - In Transit - Awaiting Receipt -
Awaiting Reconciliation - Disputed / Discrepant Transfers

**4. Loss & Damage Control** - Missing Equipment - Damaged Equipment -
Under Investigation - Confirmed Losses - Unresolved Discrepancies

**5. Reconciliation Control** - Awaiting Reconciliation - Reconciled
Transfers, distinguishing completed transfers from pending-close items -
Discrepancies - Unexplained Variances

**6. Station Inventory** - Stations Requiring Attention - Direct entry
to station/item inventory intelligence

### 8.2 Layout and order

-   Wide desktop: 3 columns × 2 rows.
-   Tablet: 2 columns × 3 rows.
-   Ordinary mobile: 2 columns × 3 rows.
-   Very narrow viewports or high zoom: one column if required for
    readability.
-   Preserve the same logical order on every device.
-   Do not default to one vertical column on ordinary mobile widths.
-   Do not force three columns on phones.

Below the six cards: 1. **Action Required** alert centre. 2. **Station
Inventory** working table or summary.

The Station Inventory card is a navigation entry point; the table is the
working surface. Avoid needless duplicate content.

### 8.3 Card anatomy and headline KPI

Each card has a consistent line icon, title, prominent headline KPI,
label, compact sub-KPI list, View Details affordance, and appropriate
hover/focus/pressed states.

Headline suggestions: - Equipment Overview: Total Equipment. - Inventory
Health: Critical Shortages if present; otherwise a useful overall health
summary. - Equipment Movement & Exchange: Transfers Requiring Action. -
Loss & Damage Control: Open Exceptions. - Reconciliation Control:
Awaiting Reconciliation. - Station Inventory: Stations Requiring
Attention.

Headline selection must be deterministic. When the preferred count is
zero, use an appropriate fallback instead of an unexplained blank.
Sub-KPI counts should open their corresponding filtered lists. Card
actions open authorised detail views. Counts and results must respect
the user's data-access scope.

## 9. Action Required

Action Required is a prominent alert centre below the six cards, not a
seventh main control card.

Each alert should show: - Severity/type. - Station. - Equipment or
transfer reference. - Current quantity and minimum/expected quantity
when relevant. - Brief explanation. - Relevant next action if the user
is authorised.

Example structure:

**CRITICAL SHORTAGE**\
`ACC · Aluminium Foil Casserole`\
`15 available · minimum 6,000`\
`View shortage` / `Request Transfer` (when permitted)

Sort by severity, then urgency/age using documented rules. Link alerts
to authoritative records, avoid duplicate alerts for one unresolved
condition, and provide View All when needed. If there are no alerts,
show an explicit calm empty state. Alert counts and lists must use
consistent definitions.

## 10. Station Inventory table

Required columns: 1. Station 2. Equipment 3. Current Stock 4. Minimum
Level 5. Variance 6. Status 7. Action

Required controls: - Station filter. - Equipment filter. - Status
filter. - Search by station, equipment code, or name. - Clear/reset
filters. - Meaningful sorting. - Pagination or controlled progressive
loading for larger result sets. - Export only when authorised and
implemented.

Provide a clear View Details action. Row click must not conflict with
controls or keyboard access. Show status text, not colour alone. Use
correct units and station/item thresholds. Do not assume all positive
variance means surplus.

For the initial table, define `Variance = Current Stock − Minimum Level`
unless the approved domain model specifies otherwise, and label the
comparison level clearly.

Inventory is transaction-driven. Conceptually:

`Opening Balance + Receipts + Transfers In − Transfers Out − Approved Damage − Confirmed Loss ± Approved Adjustments = Current Accountable Stock`

The domain model owns the actual rules. In-transit stock is represented
separately; the same units must not count as both available at origin
and received at destination. The UI must not implement a competing
inventory calculation.

## 11. Transfers, forms, and operational workflows

The transfer lifecycle is:

`Draft → Requested → Approved → Dispatched → In Transit → Received → Reconciliation → Closed`

Exceptions may include rejected, cancelled, partially received,
disputed, or discrepancy states as defined in the requirements.

Forms must: - Group related fields logically. - Mark required fields. -
Provide understandable inline validation. - Validate in both client and
server/backend. - Preserve entered values after recoverable errors. -
Prevent duplicate submissions while processing. - Provide clear
success/failure feedback. - Confirm consequential actions such as
dispatch, final reconciliation, and closure. - Enforce permissions
server-side. - Show source/destination, equipment, quantity/unit,
requestor, approval, dispatch, receipt, and reconciliation details as
relevant. - Record actual received quantities; do not silently copy
dispatched quantities. - Keep discrepancies visible until resolved
according to approved rules.

Authorised users may initiate transfer requests from Equipment Movement
& Exchange, a shortage record, or a Station Inventory row. Prefill
context where safe, but require confirmation of source, destination,
quantity, and required details. A shortage must never automatically
approve or dispatch a transfer.

## 12. Loss, damage, and reconciliation

Loss/damage views should clearly show missing equipment, damaged
equipment, investigations, confirmed losses, and unresolved
discrepancies. Include station, item, quantity, status, relevant dates,
last known location/movement reference where available, and authorised
actions. A missing report must not be treated as a confirmed loss.

Reconciliation views must distinguish: - Awaiting Reconciliation. -
Reconciled / Pending Close, where applicable. - Discrepancies. -
Unexplained Variances. - Closed Transfers.

A transfer can close only when approved reconciliation rules are
satisfied. Exceptions and adjustments must be documented, authorised,
and auditable.

## 13. Shared components and iconography

Create or standardise reusable theme-aware components for buttons,
inputs, selects, validation, cards, KPI summaries, badges, alerts,
tables, filters, pagination, tabs, navigation, menus, tooltips,
popovers, dialogs, drawers, loading states, and empty states.

Use one consistent line-icon family, preferably Lucide if already
installed or approved. Do not mix emoji, clip-art, and unrelated icon
styles in production. Icons support labels and do not replace essential
text. Icon-only controls need accessible names and suitable tooltips.

## 14. Interaction states and feedback

Interactive components must support appropriate default, hover, focus,
pressed/active, disabled, loading, success, and error states.
Distinguish destructive/high-impact actions from routine navigation.
Keep button dimensions stable during loading and prevent duplicate
submissions.

Use inline form errors for important validation. Toasts can supplement
but must not be the only communication for essential errors. All
interaction states must be themed.

## 15. Loading, empty, error, and stale-data states

Every data-driven screen must explicitly handle: - **Loading:** stable
skeleton/progress; do not show temporary zeros before data loads. -
**Empty:** explain no matching records; distinguish empty data from
missing permission or failed request. - **Error:** user-friendly message
and retry where appropriate; never expose stack traces, SQL errors,
secrets, or private backend details. - **Stale/unavailable data:** show
last-updated or stale/offline status where supported. Do not claim
"Live" or "Just now" unless substantiated.

These states must be tested in both themes.

## 16. Responsive behaviour

Test approximately 320, 360, 390, 768, 1024, and 1440 CSS pixel widths,
including portrait/landscape where practical.

-   No header/navigation overlap.
-   No unintended page-wide horizontal scrolling.
-   Dashboard grid follows the agreed 3-column desktop and 2-column
    ordinary mobile/tablet rules.
-   Forms become single-column on narrow screens.
-   Tables may scroll horizontally inside their own bounded container.
-   Dialogs/drawers fit the viewport and permit scrolling.
-   Essential actions remain readable and reachable.
-   Text zoom must not clip critical values or controls.

## 17. Accessibility

Target WCAG 2.2 AA as the design goal: - Semantic HTML and logical
heading hierarchy. - Keyboard access to all functionality. - Visible
focus indicators in both themes. - Adequate contrast for text, icons,
controls, badges, and focus rings. - Status never communicated by colour
alone. - Proper form labels and associated error messages. - Descriptive
accessible names for links and buttons. - Correct table header
semantics. - Screen-reader-readable KPI values and labels. - Touch
targets around 44 × 44 CSS pixels where practical. - Respect
reduced-motion preferences. - Support zoom/text resizing. - Announce
important asynchronous success/error messages accessibly.

## 18. Security and permission-aware presentation

The UI is not an authorisation boundary. Enforce sensitive reads and
mutations through server/backend logic and database policies. Show only
actions appropriate to the user's permissions, but validate permissions
server-side too. Respect organisation/station scope in KPIs, tables,
alerts, and search. Never expose Supabase service-role keys or secrets
in client code. Protect attachments and exports like the underlying
records. Preserve audit records for approvals, dispatch, receipt,
reconciliation, damage/loss changes, and inventory adjustments.

## 19. Technical implementation guidance

-   Inspect the repository, routes, components, dependencies,
    CSS/Tailwind setup, and existing theme logic before editing.
-   Preserve business logic, data queries, database schema, permissions,
    and workflows during visual refactoring.
-   Integrate tokens with the existing stack; do not introduce
    dependencies without checking what's installed and documenting the
    reason.
-   Keep inventory calculations and permission decisions out of
    presentational components.
-   Do not hardcode screenshot figures into production.
-   Clearly isolate demo/test data from production.
-   Prefer focused, reviewable refactors over wholesale rewrites.
-   Update this specification and the decision log if an approved
    decision changes.

## 20. Global theme migration and verification

Claude must inventory existing routes and shared components for
hardcoded backgrounds/text, inline colours, old navigation/card styles,
third-party controls, chart palettes, modals, disabled/focus/hover
states, and any component that only works in one theme.

Verify: 1. Aero Blue applies throughout every existing page and shared
component. 2. Slate Modern applies throughout every existing page and
shared component. 3. Settings → Appearance offers Light, Dark, and
System. 4. New users default to Light unless a valid preference already
exists. 5. Preferences persist according to the documented strategy. 6.
System mode follows device preference where supported. 7. Theme changes
do not alter route, records, form values, permissions, or business
logic. 8. No unintended legacy styling remains. 9. Text, statuses,
borders, focus rings, charts, and controls remain legible in both modes.
10. Avoidable flashes of the wrong theme and layout shifts are
prevented.

A dashboard-only theme implementation does not meet acceptance criteria.

## 21. Dashboard data integrity

Before accepting the dashboard, verify: - Total Equipment means quantity
of units, not number of catalogue types. - Available Equipment has a
documented definition and excludes unavailable units under approved
rules. - In-transit units are not counted as available at both
stations. - Damage, missing, loss investigations, and transfer
discrepancies are not unintentionally double-counted. - Transfer counts
match workflow state. - Stations Requiring Attention counts distinct
stations, not station-item rows. - Action Required links to
authoritative records. - KPI counts and detail lists use consistent
definitions and access scopes. - Zero does not conceal loading failures
or missing configuration. - Quantity counts and record counts are
clearly distinguished.

Critical shortage, shortage, normal stock, surplus, and critical surplus
must use approved domain thresholds. If thresholds are not defined in
the domain specification, identify the dependency rather than inventing
rules in UI code.

## 22. Definition of Done

### Theme system

-   [ ] Aero Blue Light Mode and Slate Modern Dark Mode are implemented.
-   [ ] Settings → Appearance offers Light, Dark, and System.
-   [ ] Light is the default for new users.
-   [ ] Preference persists according to the documented strategy.
-   [ ] Every existing route and shared component uses the selected
    theme.
-   [ ] Central tokens drive styling; no unintended legacy theme
    remains.
-   [ ] Both themes are verified across all existing routes.

### Navigation and dashboard

-   [ ] Two-level header is implemented.
-   [ ] Main tabs are centred on desktop and active tab is obvious.
-   [ ] Mobile navigation works without overlap.
-   [ ] Six cards appear in the approved order.
-   [ ] Desktop is 3 × 2; ordinary mobile/tablet is 2 × 3.
-   [ ] Each card has headline KPI, supporting sub-KPIs, icon, and
    details action.
-   [ ] Sub-KPIs open correct filtered views.
-   [ ] Action Required prioritises meaningful exceptions.
-   [ ] Station Inventory has the agreed columns and working filters.
-   [ ] Variance, units, and thresholds are explicit.

### Quality

-   [ ] Loading, empty, error, and stale-data states are implemented.
-   [ ] Accessibility is checked in both themes.
-   [ ] Business rules, permissions, workflows, and auditability remain
    intact.
-   [ ] Relevant tests, type checks, lint, and build pass, or failures
    are reported.
-   [ ] Desktop and mobile screenshots are reviewed in both modes.
-   [ ] Documentation and decision log are updated.

## 23. Implementation sequence

Use the ACOMS Progressive Systems Development approach: 1. Inspect
repository structure, routes, theme logic, dependencies, and hardcoded
styling. 2. Report the current state, risks, and proposed files before
broad edits. 3. Implement central theme tokens and Light/Dark/System
preference handling. 4. Update application shell and two-level
navigation. 5. Standardise shared components and interaction states. 6.
Refactor the six dashboard control cards. 7. Implement responsive 3 × 2
desktop and 2 × 3 ordinary mobile/tablet layout. 8. Refine Action
Required and Station Inventory. 9. Migrate all other existing
routes/components to the global theme system. 10. Test both themes, all
existing routes, loading/empty/error states, and responsive widths. 11.
Run tests, type checks, lint, and production build. 12. Report changed
files, test results, screenshots, known gaps, and decisions requiring
approval.

Do not perform an unreviewed all-at-once rewrite.

## 24. Instructions for Claude

Before implementation, read `CLAUDE.md`, `docs/ACOMS_MASTER_SPEC.md`,
relevant requirements/architecture documents, and this file.

Inspect the current code before editing. Report: 1. Current app
structure and routes. 2. Existing theme/styling approach. 3. Hardcoded
styles or legacy components preventing global theming. 4. Proposed files
and implementation stages. 5. Conflicts with domain rules or current
functionality.

Implement in small, reviewable stages. Preserve data access, business
rules, database schema, permissions, audit trails, and workflows. Do not
invent operational data, add unrelated features, or claim verification
without running checks. If this specification conflicts with domain
rules or creates a security/data-integrity risk, stop and report the
conflict.

------------------------------------------------------------------------

**End of specification.**
