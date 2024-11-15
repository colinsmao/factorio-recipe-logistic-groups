<h2>Recipe Logistic Groups</h2>

Automatically create logistic groups for recipe ingredients when pasting into a requester chest. Supports quality. The multiplier can be adjusted freely afterwards.

Optional "additive" pasting mode, which adds the recipe's ingredients to the existing logistic requests, instead of replacing them. Pasting multiple times will increase the request multiplier.

Adds an alternate paste keybind to allow for two types of pasting behaviour.

Fully configurable, including:
- Configurable multiplier options, based on crafting time, or by product count.
- Configurable paste options for both the primary and alternate keybinds, including replace, additive, and vanilla (no logistic group).

If using eg "Shift + Alt + Left-Click" for alternate pasting, it is recommended to add "Shift + Alt + Right-click" as an alias for copy, so you do not need to release Alt to copy.

<br/>

---
<br/><br/>
<h3>Notes</h3>

If a recipe has multiple products and a main_product is not defined, the N items/stacks multiplier option will default to N recipes. Fluids are treated as a stack size of 500.

<br/>

Currently, the Factorio modding api lacks support for logistic group management. Including:
- Missing a way to get all existing logistic groups. Or a specific group by name. So if recipes change in some update, there is not a way to go through and migrate all existing recipe groups to the new recipe.
  - Base factorio recipes are probably relatively stable, but mod recipes can change a lot.
  - If you add or remove a mod which adds/changes recipes, recipe groups may be stuck on their old version or orphaned.
- There is no way to delete a recipe group via script, so if you want to remove unused recipe logistic groups you have to delete them manually.
- There is no event after changing the name of a logistic group, so the auto-created group names can be changed by the player. The mod will no longer recognize said name, causing it to create new recipe groups.
- Logistic groups do not have internal vs localized names. I am using the rich text recipe icons, which should be consistent across locales, and unique. This means the mod currently does not support text/named recipe groups.

