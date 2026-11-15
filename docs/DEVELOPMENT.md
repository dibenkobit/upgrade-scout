# Development

The tests run outside the game and need Lua 5.1:

```
lua5.1 tests/run.lua
```

[luacheck](https://github.com/lunarmodules/luacheck) checks the code for misspelled names and
unused variables:

```
luacheck UpgradeScout tests
```

GitHub Actions runs both on every push.

Each script in `scripts/` says at the top what it does and how to run it.

To release, push a tag with the version from `UpgradeScout.toc`, for example `1.2.0`. GitHub Actions
runs the tests and uploads the zip to CurseForge, Wago Addons and GitHub.
