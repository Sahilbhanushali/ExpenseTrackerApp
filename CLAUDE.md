# Flutter Expense Tracker — Development Rules

## 1. Project Goal

Build a premium, modern, highly interactive expense tracker in Flutter.

Priorities, in order:

1. Correctness
2. Performance
3. Excellent UX
4. Clean architecture
5. Maintainability
6. Minimal code/token usage

The app should feel fast, polished, responsive, and native on Android and iOS.

---

# 2. Flutter Rules

* Use the latest stable Flutter/Dart APIs already supported by the project.
* Follow official Flutter/Dart conventions.
* Prefer simple Flutter primitives over unnecessary third-party packages.
* Do not add a dependency unless it provides clear value.
* Keep widgets small and focused.
* Prefer `const` constructors/widgets whenever possible.
* Avoid unnecessary widget rebuilds.
* Never put expensive computation inside `build()`.
* Never perform database/network/file operations inside `build()`.
* Dispose controllers, animations, streams, and listeners correctly.
* Use lazy builders for large lists:

  * `ListView.builder`
  * `GridView.builder`
  * `SliverList`
  * `SliverGrid`
* Avoid `ListView(children: [...])` for potentially large dynamic lists.
* Avoid deeply nested widget trees when a simpler structure is possible.
* Use `RepaintBoundary` only when profiling shows it is useful.
* Do not optimize blindly. Prefer measurable performance improvements.

---

# 3. UI/UX Rules

The UI must feel:

* Premium
* Clean
* Modern
* Fast
* Minimal
* Consistent
* Responsive
* Accessible

Avoid:

* Excessive gradients
* Excessive shadows
* Giant cards everywhere
* Unnecessary animations
* Random spacing
* Inconsistent corner radii
* Inconsistent typography
* Overloaded screens
* Decorative UI that doesn't improve usability

Use a consistent design system for:

* Colors
* Typography
* Spacing
* Border radius
* Elevation
* Icons
* Buttons
* Inputs
* Cards

Prefer reusable design tokens instead of hardcoded values throughout the application.

Example:

```dart
AppSpacing.md
AppRadius.md
AppColors.primary
AppTextStyles.title
```

Do not scatter magic numbers throughout UI code.

---

# 4. Responsive Design

The application must work correctly across:

* Small phones
* Large phones
* Tablets
* Landscape
* Different text scaling settings

Never assume a fixed screen size.

Prefer:

```dart
MediaQuery
LayoutBuilder
Flexible
Expanded
ConstrainedBox
SliverLayoutBuilder
```

Avoid hardcoded widths/heights unless they represent a deliberate design constraint.

Test layouts at multiple screen sizes.

---

# 5. Expense Tracker UX

The main dashboard should make these immediately understandable:

* Total balance
* Income
* Expenses
* Current period spending
* Spending categories
* Recent transactions

Adding an expense should require as few steps as reasonably possible.

The primary action should always be obvious.

Important interactions should provide immediate visual feedback.

Use subtle animations for:

* Adding/removing transactions
* Changing totals
* Opening sheets
* Navigation
* Filtering
* Category selection

Animations must be short and purposeful.

Do not animate everything.

---

# 6. Animation Rules

Prefer Flutter's built-in animation APIs.

Use:

* `AnimatedContainer`
* `AnimatedSwitcher`
* `AnimatedOpacity`
* `TweenAnimationBuilder`
* `AnimationController` when custom control is required

Avoid expensive or continuous animations.

Do not use animation packages unless necessary.

Animations should generally feel quick and natural.

Avoid animation durations that make the app feel slow.

---

# 7. Architecture

Organize code by feature rather than creating one huge global folder.

Preferred structure:

```text
lib/
├── core/
│   ├── constants/
│   ├── theme/
│   ├── utils/
│   └── widgets/
│
├── data/
│   ├── models/
│   ├── repositories/
│   └── datasources/
│
├── features/
│   ├── dashboard/
│   ├── expenses/
│   ├── income/
│   ├── categories/
│   ├── analytics/
│   └── settings/
│
└── main.dart
```

Keep business logic out of widgets.

Widgets should primarily handle:

* Rendering
* User interaction
* UI state

Business logic belongs in appropriate controllers/services/repositories.

---

# 8. State Management

Use the project's existing state-management solution consistently.

Do not introduce another state-management library without a strong reason.

Avoid global mutable state.

Keep state as local as possible.

Prefer:

* Local state for UI-only state
* Feature-level state for feature logic
* Repository/service layers for persistent data

Do not rebuild the entire application when only a small widget needs updating.

---

# 9. Data Layer

Keep persistence separate from UI.

Do not access SQLite/Isar/Hive/API/database code directly from widgets.

Preferred flow:

```text
UI
 ↓
Controller / State
 ↓
Repository
 ↓
Data Source
 ↓
Database / API
```

Models should be simple and predictable.

Do not duplicate model conversion logic.

Handle loading, empty, error, and success states explicitly.

---

# 10. Performance

Performance is a first-class requirement.

Always consider:

* Widget rebuild frequency
* List size
* Database queries
* Image size
* Memory usage
* Animation cost
* Startup time

For large transaction lists:

* Use lazy lists
* Paginate when appropriate
* Avoid loading unnecessary records
* Avoid repeatedly sorting/filtering the same data
* Cache expensive derived values when appropriate

Do not execute expensive operations repeatedly during rebuilds.

Prefer precomputed/derived state where appropriate.

Avoid unnecessary JSON parsing, database queries, and object allocations.

---

# 11. Database Rules

Database operations must be asynchronous where appropriate.

Never block the UI thread with expensive database work.

Prefer indexed queries for frequently filtered/sorted fields.

For transactions, consider indexes for:

* date
* category
* type
* amount

Do not retrieve all records when only a subset is required.

Use pagination for potentially large datasets.

---

# 12. Error Handling

Never silently ignore errors.

User-facing errors should be:

* Clear
* Short
* Actionable

Avoid showing raw exceptions to users.

Log useful technical information during development.

Do not expose sensitive data in logs.

---

# 13. Accessibility

Support:

* Semantic labels
* Sufficient contrast
* Large text settings
* Touch targets of appropriate size
* Screen readers

Do not communicate important information through color alone.

Icons that perform actions should have semantic labels/tooltips where appropriate.

---

# 14. Code Quality

Prefer readable code over clever code.

Avoid:

* Giant classes
* Giant widgets
* Giant methods
* Duplicate logic
* Unnecessary abstractions
* Premature optimization
* Dead code
* Commenting obvious code

Extract reusable widgets when there is actual reuse or meaningful complexity.

Do not create abstractions just to make the folder structure look sophisticated.

---

# 15. Dart Style

Follow Dart formatting conventions.

Use:

```bash
dart format .
```

Before considering a task complete, run:

```bash
flutter analyze
```

Run relevant tests:

```bash
flutter test
```

Fix analyzer errors and warnings introduced by your changes.

Do not suppress analyzer warnings unless there is a documented reason.

---

# 16. Dependency Rules

Before adding a package:

1. Check whether Flutter/Dart already provides the functionality.
2. Check whether the existing project already has a package that solves it.
3. Add a dependency only when it materially improves the project.

Avoid dependency bloat.

Do not add multiple packages that solve the same problem.

---

# 17. Token Efficiency — IMPORTANT

Optimize Claude's token usage.

Before modifying code:

1. Inspect only the relevant files.
2. Do not read the entire repository unnecessarily.
3. Do not repeatedly inspect files already understood.
4. Search for symbols/usages instead of opening unrelated files.
5. Make focused changes.
6. Avoid rewriting entire files when a small patch is sufficient.

When solving a task:

```text
Understand → Locate → Patch → Analyze/Test → Finish
```

Do not repeatedly explain the same reasoning.

Do not generate long explanations unless explicitly requested.

Prefer concise responses.

When modifying code, summarize only:

* What changed
* Important decisions
* Validation performed
* Any remaining issue

---

# 18. Claude Coding Behavior

Before coding:

* Understand the existing architecture.
* Reuse existing components.
* Reuse existing utilities.
* Reuse existing theme/design tokens.
* Do not create duplicate implementations.

When a suitable existing component exists, modify/reuse it instead of creating another one.

Do not change unrelated files.

Do not refactor unrelated code during a feature task.

Do not introduce architecture changes without necessity.

If requirements are ambiguous, choose the simplest implementation consistent with the existing architecture.

---

# 19. UI Implementation Rules

For new screens:

1. Check existing theme.
2. Check existing reusable components.
3. Check existing spacing/typography tokens.
4. Implement responsive layout.
5. Add loading/empty/error states.
6. Add appropriate interaction feedback.
7. Test small and large screens.
8. Run analyzer.

Never create arbitrary colors, font sizes, padding, or radii when design tokens already exist.

---

# 20. Financial Data Rules

Expense amounts must use appropriate numeric handling.

Avoid floating-point arithmetic for financial calculations where precision matters.

Use integer minor units where practical.

Example:

```text
₹100.50 → 10050 paise
```

Store currency information explicitly when needed.

Do not assume every transaction uses the same currency if multi-currency support is introduced.

---

# 21. Security & Privacy

Treat financial information as sensitive.

Never:

* Log transaction details unnecessarily
* Hardcode API keys
* Commit secrets
* Store sensitive credentials in source code
* Expose database credentials
* Put secrets in UI code

Use secure storage mechanisms when sensitive local credentials/tokens are required.

---

# 22. Testing

Prioritize tests for:

1. Expense calculations
2. Balance calculations
3. Filtering
4. Sorting
5. Date handling
6. Recurring expenses
7. Repository/data operations
8. Important user flows

Do not write meaningless tests simply to increase coverage.

---

# 23. Git Rules

Keep changes focused.

Use small logical commits when committing.

Do not modify generated files unnecessarily.

Never commit:

```text
.env
API keys
passwords
private credentials
local secrets
```

---

# 24. Definition of Done

A task is complete only when:

* Feature works correctly
* UI is responsive
* Existing components are reused where appropriate
* No unnecessary dependencies were added
* No obvious performance issues were introduced
* `flutter analyze` passes
* Relevant tests pass
* No unrelated files were changed

Keep the final response concise.

Report:

```text
Implemented:
- ...

Validated:
- flutter analyze
- flutter test

Notes:
- ...
```
