Currently, the Factorio modding api lacks comprehensive support for logistic group management. Including:
- Missing a way to get all existing logistic groups. Or a specific group by name. So if recipes change in some update, there is not a way to go through and migrate all existing recipe groups to the new recipe.
  - Base factorio recipes are probably relatively stable, but mod recipes can change a lot.
  - If you add or remove a mod, recipe groups may be stuck on their old version or orphaned.
- There is no way to delete a recipe group via script, so if you want to remove unused recipe logistic groups you have to delete them manually.

<br/><br/>

Note, if a recipe has multiple products and a main_product is not defined, the N items/stacks multiplier option will default to N recipes. Fluids are treated as a stack size of 500.

