# CIWS Demo Button Notes

## Confirmed Loading Rule

The scene button script must start with:

```lua
#version 2
```

Important:

- `#` must be the first character on the line.
- Do not write `# version 2`.
- Do not add a space between `#` and `version`.

If the first line is written incorrectly, the scene script may fail to load and
the button will stay in its default red state, making it look like the script
never ran.

## Confirmed Working Baseline

Current confirmed working baseline:

- `main.xml` loads `MOD/demo/ciws_demo.lua`
- `demo/ciws_demo.lua` begins with `#version 2`
- The script uses `server.init()` and `server.tick()`
- The script only controls the button and light first

## Recommended Workflow

When adding functionality back:

1. Keep the verified button/light version working.
2. Add one small piece of logic at a time.
3. Reload the map after each change.
4. If loading breaks again, compare against the verified baseline first.

## Current Verified Baseline File

- `demo/ciws_demo.lua`
