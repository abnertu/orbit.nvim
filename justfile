# Run Orbit development tools and checks on Linux and Windows.
set windows-shell := ["pwsh", "-NoLogo", "-NoProfile", "-Command"]

# List the recipes.
default:
    @just --list

# Format Lua files with the project StyLua configuration.
format:
    stylua --verify . .luacheckrc

# Lint Lua files with the project Luacheck configuration.
lint:
    luacheck . .luacheckrc

# Run the offline test suites.
test pattern="":
    nvim --headless -u NONE -l scripts/test.lua test {{pattern}}

# Run the live suites against real plugins and tools.
live pattern="":
    nvim --headless -u NONE -l scripts/test.lua live {{pattern}}

# Check the generated schema and settings validation.
schema:
    nvim --headless -u NONE -l scripts/test.lua schema
