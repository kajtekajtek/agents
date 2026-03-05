---
name: clean-architecture
description: Analyze project architecture at macro level - package structure, module boundaries, dependency direction, and layering. Use when user asks "review architecture", "check structure", "package organization", when evaluating if a codebase follows clean architecture principles, or when creating a new project from scratch.
---

# Clean Architecture

Analyze project structure at the macro level - packages, modules, layers, and boundaries.

## When to Use

- User asks "review the architecture" / "check project structure"
- Evaluating package organization
- Checking dependency direction between layers
- Identifying architectural violations
- Assessing clean/hexagonal architecture compliance

## Quick Reference: Architecture Smells

- Package-by-layer bloat 
    - `service/` with 50+ classes 
    - Hard to find related code
- Domain → Infra dependency 
    - Entity imports `@Repository` 
    - Core logic tied to framework
- Circular dependencies 
    - A → B → C → A 
    - Untestable, fragile
- Master package 
    - `util/` or `common/` growing 
    - Dump for misplaced code
- Leaky abstractions 
    - Controller knows SQL 
    - Layer boundaries violated

## Dependency Direction Rules

### The Golden Rule

- Frameworks ← Outer (volatile)
- Adapters (Web, DB)
- Application Services
- Domain (Core Logic)
- Dependencies MUST point inward only.
- Inner layers MUST NOT know about outer layers.

## Architecture Review Checklist

### 1. Package Structure

- [ ] Clear organization strategy (by-layer, by-feature, or hexagonal)
- [ ] Consistent naming across modules
- [ ] No `util/` or `common/` packages growing unbounded
- [ ] Feature packages are cohesive (related code together)

### 2. Dependency Direction

- [ ] Domain has ZERO framework imports (Spring, JPA, Jackson)
- [ ] Adapters depend on domain, not vice versa
- [ ] No circular dependencies between packages
- [ ] Clear dependency hierarchy

### 3. Layer Boundaries

- [ ] Controllers don't contain business logic
- [ ] Services don't know about HTTP (no HttpServletRequest)
- [ ] Repositories don't leak into controllers
- [ ] DTOs at boundaries, domain objects inside

### 4. Module Boundaries

- [ ] Each module has clear public API
- [ ] Internal classes are package-private
- [ ] Cross-module communication through interfaces
- [ ] No "reaching across" modules for internals

### 5. Scalability Indicators

- [ ] Could extract a feature to separate service? (microservice-ready)
- [ ] Are boundaries enforced or just conventional?
- [ ] Does adding a feature require touching many packages?

## Recommendations Format

When reporting findings:

```markdown
## Architecture Review: [Project Name]

### Structure Assessment
- **Organization**: Package-by-layer / Package-by-feature / Hexagonal
- **Clarity**: Clear / Mixed / Unclear

### Findings

| Severity | Issue | Location | Recommendation |
|----------|-------|----------|----------------|
| High | Domain imports Spring | `domain/model/User.java` | Extract pure domain model |
| Medium | God package | `util/` (23 classes) | Distribute to feature modules |
| Low | Inconsistent naming | `service/` vs `services/` | Standardize to `service/` |

### Dependency Analysis
[Describe dependency flow, violations found]

### Recommendations
1. [Highest priority fix]
2. [Second priority]
3. [Nice to have]
```

### Token Optimization

For large codebases:
1. Start with `find` to understand structure
2. Check only domain package for framework imports
3. Sample 2-3 features for pattern analysis
4. Don't read every file - look for patterns

