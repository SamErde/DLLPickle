# Issue 242 Background Event Handler Design

## Goal

Prevent `Import-DPLibrary` from installing PowerShell script blocks as CLR event delegates that may execute on threads without a PowerShell runspace.

## Supported Baseline

- PowerShell 7.4 or later.
- The `net8.0` dependency bundle.
- Windows, Linux, and macOS.
- No Windows PowerShell 5.1 or .NET Framework compatibility work.

## Root Cause

`Import-DPLibrary` casts a script block to `System.ResolveEventHandler`, and `Invoke-DPConflictCheck` casts another script block to `System.AssemblyLoadEventHandler`. CLR publishers can invoke both delegates on arbitrary threads. PowerShell attempts to obtain a runspace before entering either script block body, so the functions' internal `try` blocks cannot catch the resulting `PSInvalidOperationException`.

## Design

Start with deletion, because both callbacks may be legacy or advisory under the current baseline:

1. Remove the one-shot `AssemblyLoad` watcher. Keep immediate conflict detection and the public `Test-DPLibraryConflict` command. The automatic future warning is advisory and does not justify a cross-thread event bridge.
2. Remove the temporary `AssemblyResolve` handler and retain dependency-graph ordering, same-directory .NET loading, and retry behavior.
3. Prove the deletion with deterministic synthetic dependency and child-process regression tests.
4. Add a compiled resolver only if the synthetic dependency test demonstrates that supported-runtime loading fails without the handler.

The fallback resolver, if required, must be a precompiled `net8.0` type. It must use an immutable map of canonical paths under the module's `bin/net8.0` directory, match assembly name/version/culture/public-key-token exactly, return `null` for every unrelated request, and unregister through `IDisposable`. Runtime `Add-Type` and captured PowerShell runspaces are prohibited.

## Behavior Changes

- `Import-DPLibrary` still warns immediately when a known conflicting module pair is already loaded.
- DLLPickle no longer attempts to warn later from an `AssemblyLoad` event. Users retain the reliable on-demand `Test-DPLibraryConflict` command.
- Dependency loading must continue to produce the existing result objects and statuses.

## Security and Reliability Constraints

- No PowerShell script block may be registered directly as an `AssemblyLoad` or `AssemblyResolve` CLR delegate.
- Regression tests that exercise process-fatal behavior must run in an isolated child `pwsh` process with a bounded timeout.
- Synthetic tests must not download modules, access the network, or depend on installed Az/Exchange modules.
- Tests must use synchronization primitives or synchronous child-process completion, not timing-only sleeps.
- If a resolver is required, it must not probe the current directory, `PATH`, `PSModulePath`, or caller-provided locations.

## Verification

- A source guard rejects direct `AssemblyLoadEventHandler` and `ResolveEventHandler` script-block casts.
- A synthetic two-assembly dependency test proves dependency loading on the supported runtime.
- A child-process test imports and exercises the module without `PSInvalidOperationException` or abnormal termination.
- Analyzer, unit tests, issue reproduction integration tests, and the complete repository build pass.
