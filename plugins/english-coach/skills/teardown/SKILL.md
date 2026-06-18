---
name: teardown
description: Undo english-coach statusline wiring (restore your original statusline). Disable the plugin to also stop the hook.
disable-model-invocation: true
---

# english-coach teardown — unwire the statusline

Restore the statusline to how it was before setup.

## Steps

1. Run the unwiring script:

   ```bash
   "${CLAUDE_PLUGIN_ROOT}/scripts/unwire-statusline.sh"
   ```

   It restores your original statusline (drift-aware — if you changed it manually since setup, it
   warns and leaves it alone) and removes the deployed wrapper. Your `config.local.sh`,
   `secrets.env`, `tips/`, and `state/` are left intact.

2. Tell the user:
   - **Open a NEW session** for the statusline change to apply.
   - To also stop the background hook, **disable the plugin** (`/plugin` → disable `english-coach`),
     which removes the `UserPromptSubmit` hook.
