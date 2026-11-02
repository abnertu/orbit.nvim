# Run Orbit checks on Linux and Windows. Each recipe runs one Neovim command.
set windows-shell := ["pwsh", "-NoLogo", "-NoProfile", "-Command"]

# List the recipes.
default:
    @just --list

# Run the offline test suites.
test pattern="":
    nvim --headless -u NONE -l scripts/test.lua test {{pattern}}

# Run the live suites against real plugins and tools.
live pattern="":
    nvim --headless -u NONE -l scripts/test.lua live {{pattern}}

# Check the generated schema and settings validation.
schema:
    nvim --headless -u NONE -l scripts/test.lua schema
