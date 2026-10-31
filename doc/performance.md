# Startup and performance acceptance

This development preview measures default Neovim startup and repeated module setup on both supported platforms.

## Baseline

Run `nvim --headless -u NONE -l tests/startup_performance_spec.lua` from the repository root.

The Lua fixture launches five clean Neovim processes and five processes that evaluate the public `init.lua`. It prints minimum, median and maximum wall-clock startup durations. It also runs 50 unchanged `orbit.setup()` calls and prints their median, 95th percentile and maximum duration.

The CI limit is intentionally generous. It only detects a stuck process, accidental network activity during default startup, or pathological reconfiguration. Do not interpret it as a stable latency service-level objective. Compare the same host, Neovim version and runner image when evaluating improvements.

## Required ownership checks

- Initial setup must not import Lazy, the icon plugin or the Git signs plugin when demand-loading is disabled.
- Repeated setup must not stack core diagnostic or startup autocommands.
- All executable benchmarks and fixture checks run in Neovim Lua, without Python.
- Real external plugin imports belong in the separate live-upstream workflow.

## Remaining release gates

Before declaring production startup parity, benchmark interactive UI startup, plugin first-demand activation, real theme initialization, a large workspace, and Windows process creation. Record platform-specific results and assess regressions against the legacy configuration. This fixture measures a controlled headless baseline, not the user's full interactive environment.
