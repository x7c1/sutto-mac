# Architecture

## Overview

Sutto for macOS separates concerns into layers with dependencies pointing inward toward the domain. This is closer to Clean Architecture or Onion Architecture than traditional layered architecture, as outer layers (UI, infra) can access inner layers (operations, domain) directly. The layering mirrors the [GNOME version of Sutto](https://github.com/x7c1/sutto), so the two codebases stay structurally recognizable to each other.

Each layer is a SwiftPM target, and the dependency rules are declared in `Package.swift`; an import that violates the layering fails to compile.

## Layers

```
┌───────────────────────────────────────────────────┐
│                    SuttoApp                       │
│  Composition root: wiring, dependency injection,  │
│  app lifecycle                                    │
└───────────────────────────────────────────────────┘
        │                            │
        ▼                            ▼
┌─────────────────┐      ┌─────────────────────────┐
│     SuttoUI     │      │        SuttoInfra       │
│  Status item,   │      │  Adapters over Apple    │
│  windows, menus │      │  frameworks (AX APIs)   │
└────────┬────────┘      └────────────┬────────────┘
         │                            │
         └──────────┬─────────────────┘
                    ▼
┌───────────────────────────────────────────────────┐
│                 SuttoOperations                   │
│  Use cases, defines protocols for infra           │
└───────────────────────────────────────────────────┘
                    │
                    ▼
┌───────────────────────────────────────────────────┐
│                   SuttoDomain                     │
│  Pure domain models, no external dependencies     │
└───────────────────────────────────────────────────┘
```

SuttoUI and SuttoInfra can also access SuttoDomain directly (not shown for simplicity).

## Layer Responsibilities

### SuttoDomain

Pure domain models and business rules. Depends on nothing beyond Foundation; must not import AppKit, ApplicationServices, or any other macOS framework.

- Entities and value objects (e.g. `AccessibilityAuthorization`)
- Domain logic that doesn't require external resources (e.g. `PermissionOnboardingPolicy`)

### SuttoOperations

Coordinates the domain to execute use cases. Defines the protocols that SuttoInfra implements.

- Use-case types that the UI calls (e.g. `AccessibilityPermissionUseCase`)
- Protocols abstracting OS capabilities (e.g. `PermissionChecking`)

### SuttoInfra

Handles all interactions with Apple frameworks. Implements protocols defined by SuttoOperations.

- Accessibility (AX) API bridging (e.g. `AccessibilityPermissionChecker`)
- Any future file I/O, persistence, or system information providers

### SuttoUI

Everything on screen. Calls the operations layer; never touches SuttoInfra.

- The menu bar status item and its menu (`StatusItemController`)
- Windows and onboarding flows (`PermissionOnboarding`)

### SuttoApp

The executable target and composition root. Wiring only — no business logic.

- Instantiates the infra adapters and injects them into operations
- Hands the wired use cases to the UI
- Owns the app lifecycle (`main.swift`, `AppDelegate`)

## Dependency Rules

```
SuttoApp → SuttoUI → SuttoOperations → SuttoDomain
                            ↑
                       SuttoInfra (implements SuttoOperations protocols)
```

- **SuttoDomain**: depends on nothing
- **SuttoOperations**: depends on SuttoDomain, defines protocols
- **SuttoInfra**: depends on SuttoDomain and SuttoOperations (for the protocol definitions)
- **SuttoUI**: depends on SuttoOperations (and SuttoDomain for value types)
- **SuttoApp**: depends on everything (wiring only)

These rules are encoded as target dependencies in `Package.swift`, so the compiler enforces them.

## Testing

- `Tests/SuttoDomainTests` covers the pure domain logic.
- `Tests/SuttoOperationsTests` covers use cases, substituting the SuttoOperations protocols with in-test stubs — no AX APIs or AppKit involved.
- `Tests/SuttoInfraTests` covers the Foundation-only infra adapters (file persistence, UserDefaults) against temp directories and isolated defaults suites; the AX-backed adapters are exercised by the e2e suite instead.
- `Tests/SuttoE2ETests` drives the real app bundle from the outside (injected shortcut → panel → actual window movement). It depends on SuttoDomain only — shared constants and frame math — and observes the app through the Accessibility API like an external tool, never through SuttoInfra/SuttoUI internals.
- Anything requiring the Accessibility (TCC) permission is local-only (`make e2e`, excluded from `make test`); see [testing.md](testing.md) for the testing strategy.
