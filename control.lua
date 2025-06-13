
---@alias SlotFilter { slot: integer, filter: LogisticFilter }

---@class StableSection A table for a LuaLogisticSection that will not become invalid, which can be reloaded from
---@field group string
---@field active boolean
---@field multiplier number?
---@field slots SlotFilter[]?
local StableSection = {}

---@param section LuaLogisticSection
---@param index integer
---@param filter LogisticFilter
local function set_slot_safe(section, index, filter)
  -- safe setting of slots that doesnt cause infinite on_entity_logistic_slot_changed recursion
  storage.prevent_recursion = true
  section.set_slot(index, filter)
  storage.prevent_recursion = false
end

--- Returns a mapping of slot_id: LogisticFilter for a given logistic section
---@param section LuaLogisticSection
---@return SlotFilter[]
local function get_slot_filters(section)
  local n = 0
  local ret = {}
  for i=1,10000 do
    local filter = section.get_slot(i)
    if filter.value then
      table.insert(ret, {slot=i, filter=filter})
      n = n + 1
      if n >= section.filters_count then break end
    end
  end
  return ret
end

--- Saves a logistic section as a table that it can be reloaded from, which will not become invalid after the paste
---@param section LuaLogisticSection
---@return StableSection
local function save_section(section)
  ---@type StableSection
  local ret = {
    group = section.group,
    active = section.active,
  }
  if section.group == "" then
    ret.slots = get_slot_filters(section)
  else
    ret.multiplier = section.multiplier
  end
  return ret
end

--- Load a logistic session from a saved StableSection
---@param section LuaLogisticSection
---@param stable_section StableSection
---@return LuaLogisticSection
local function load_section(section, stable_section)
  section.group = stable_section.group
  section.active = stable_section.active
  if stable_section.group == "" then
    if not stable_section.slots then return section end
    for _, slot in pairs(stable_section.slots) do
      set_slot_safe(section, slot.slot, slot.filter)
    end
  else
    section.multiplier = stable_section.multiplier or 1
  end
  return section
end

-- script.on_event("debug-event", function(event)
--   local player = game.get_player(event.player_index)
--   if not player then return end
--   local cursor_stack = player.cursor_stack
--   if not cursor_stack or not cursor_stack.valid_for_read then return end
--   if cursor_stack.name == "copper-plate" then
--     local entities = player.surface.find_entities_filtered{type = "logistic-container", position=event.cursor_position}
--     for _, entity in pairs(entities) do
--       game.print(entity.name)
--       local point = entity.get_logistic_point(defines.logistic_member_index.logistic_container)
--       for _, section in pairs(point.sections) do
--         game.print(section.group)
--         game.print(serpent.block(save_section(section)))
--       end
--     end
--   elseif cursor_stack.name == "iron-plate" then
--     local entities = player.surface.find_entities_filtered{type = "logistic-container", position=event.cursor_position}
--     for _, entity in pairs(entities) do
--       local point = entity.get_logistic_point(defines.logistic_member_index.logistic_container)
--       -- point.remove_section(1)
--       for _, section in pairs(point.sections) do
--         -- section.group = "test1"
--         -- set_slot_safe(section, 4, {value="iron-plate", min=50})
--         for _, filter in pairs(section.filters) do
--           game.print(serpent.block(filter), {skip=defines.print_skip.never})
--         end
--       end
--     end
--   end
-- end)


---@param recipe LuaRecipe
---@param quality string
---@return string
local function get_group_name(recipe, quality)
  return "[recipe="..recipe.name..",quality="..quality.."]"
end

---@param product Product?
---@return number
local function get_product_count(product)
  if not product then return 1 end
  local amount = product.amount
  if not amount then
    amount = (product.amount_max + product.amount_min) / 2
  end
  return amount * product.probability
end

---@param recipe LuaRecipe
---@param crafting_speed number
---@param player_index integer
---@return number
local function get_multiplier(recipe, crafting_speed, player_index)
  local player_settings = settings.get_player_settings(player_index)
  local multiplier_mode = player_settings["multiplier-mode"].value
  -- , "constant-items", "constant-stacks", "duration-base", "duration-speed"
  local multiplier = 1
  if multiplier_mode == "duration-speed" then
    multiplier = player_settings["multiplier-duration"].value * crafting_speed / recipe.energy
  elseif multiplier_mode == "duration-base" then
    multiplier = player_settings["multiplier-duration"].value / recipe.energy
  elseif multiplier_mode == "constant-recipes" then
    multiplier = player_settings["multiplier-constant"].value
  elseif multiplier_mode == "constant-items" or multiplier_mode == "constant-stacks" then
    local product = recipe.prototype.main_product
    if not product and #recipe.products == 1 then
      product = recipe.products[1]
    end
    local stack_size = 1
    if multiplier_mode == "constant-stacks" and product then
      if product.type == "item" then
        local proto = prototypes.item[product.name]
        if proto then
          stack_size = proto.stack_size
        end
      elseif product.type == "fluid" then
        stack_size = 500
      end
    end
    multiplier = player_settings["multiplier-constant"].value * stack_size / get_product_count(product)
  end
  if player_settings["multiplier-max"].value > 0 then
    return math.min(multiplier, player_settings["multiplier-max"].value)
  end
  return multiplier
end

---@param recipe LuaRecipe|LuaRecipePrototype
---@return boolean
local function has_item_ingredients(recipe)
  for _, ingredient in pairs(recipe.ingredients) do
    if ingredient.type == "item" then
      return true
    end
  end
  return false
end

---@param ingredient Ingredient
---@param quality string
---@return LogisticFilter
local function build_filter(ingredient, quality)
  return {value={type="item", name=ingredient.name, quality=quality, comparator="="}, min=ingredient.amount}
end

---@param point LuaLogisticPoint
---@param recipe LuaRecipe
---@param quality string
---@return LuaLogisticSection?
local function add_section_from_recipe(point, recipe, quality)
  if not has_item_ingredients(recipe) then return end  -- skip create section if there are no item ingredients

  local section = point.add_section(get_group_name(recipe, quality))
  if not section then
    game.print("Error creating logistic group")
    return
  end

  if section.filters_count > 0 then return section end  -- the group already exists

  local i = 1
  for _, ingredient in pairs(recipe.ingredients) do
    if ingredient.type == "item" then
      set_slot_safe(section, i, build_filter(ingredient, quality))
      i = i + 1
    end
  end
  return section
end

---@param point LuaLogisticPoint
---@param stable_section StableSection
---@return LuaLogisticSection?
local function add_section_from_stable(point, stable_section)
  local section = point.add_section(stable_section.group)
  if not section then
    game.print("Error creating logistic group")
    return
  end
  load_section(section, stable_section)
  return section
end


local function get_paste_mode(player_index)
  if storage.is_alt_mode[player_index] then
    return settings.get_player_settings(player_index)["alternate-mode"].value
  else
    return settings.get_player_settings(player_index)["primary-mode"].value
  end
end


---Returns a true if the given entity matches entity_type or is a ghost containing entity_type
---@param entity LuaEntity
---@param entity_type string
---@return boolean
local function check_entity_type_ghost(entity, entity_type)
  return (entity.type == entity_type) or (entity.type == "entity-ghost" and entity.ghost_type == entity_type)
end


script.on_event("alt-paste-event", function(event)
  if settings.get_player_settings(event.player_index)["alternate-mode"].value == "disabled" then return end

  local player = game.get_player(event.player_index)
  if not player then return end

  if not player.entity_copy_source or not check_entity_type_ghost(player.entity_copy_source, "assembling-machine") then return end

  local entities = player.surface.find_entities_filtered{type = "logistic-container", position=event.cursor_position}
  for _, entity in pairs(entities) do
    storage.is_alt_mode[event.player_index] = true
    entity.copy_settings(player.entity_copy_source, player)  -- will fire on_settings_pasted events
  end

  local entities_ghost = player.surface.find_entities_filtered{type = "entity-ghost", ghost_type = "logistic-container", position=event.cursor_position}
  for _, entity in pairs(entities_ghost) do
    storage.is_alt_mode[event.player_index] = true
    entity.copy_settings(player.entity_copy_source, player)  -- will fire on_settings_pasted events
  end
end)


script.on_event(defines.events.on_pre_entity_settings_pasted, function(event)
  if (not check_entity_type_ghost(event.destination, "logistic-container")) or (not check_entity_type_ghost(event.source, "assembling-machine")) then return end
  if get_paste_mode(event.player_index) == "additive" then
    -- save the pre-paste state of the logistic container, to restore after the paste
    local tbl = {}
    for _, section in pairs(event.destination.get_logistic_point(defines.logistic_member_index.logistic_container).sections) do
      if section.valid and section.is_manual then
        table.insert(tbl, save_section(section))
      end
    end
    storage.pre_paste[event.player_index] = tbl
    -- storage.is_alt_mode[event.player_index] = false  -- reset alt mode flag for the next event
  end
end)


script.on_event(defines.events.on_entity_settings_pasted, function(event)
  local paste_mode = get_paste_mode(event.player_index)
  storage.is_alt_mode[event.player_index] = false  -- reset alt mode flag for the next event
  if paste_mode == "vanilla" then return end

  if (not check_entity_type_ghost(event.destination, "logistic-container")) or (not check_entity_type_ghost(event.source, "assembling-machine")) then return end
  local point = event.destination.get_logistic_point(defines.logistic_member_index.logistic_container)
  if not point then return end
  local recipe, quality = event.source.get_recipe()
  if not recipe then return end
  if quality then
    quality = quality.name
  else
    quality = "normal"
  end

  for i=point.sections_count,1,-1 do  -- since it was just pasted, I think there should only ever be one manual section
    point.remove_section(i)
  end
  if paste_mode == "additive" and storage.pre_paste[event.player_index] then
    local group_name = get_group_name(recipe, quality)
    local found_group = false
    for _, stable_section in pairs(storage.pre_paste[event.player_index]) do
      local section = add_section_from_stable(point, stable_section)
      if not found_group and section and section.active and section.group == group_name then
        -- if an active section already exists, increment its multiplier instead of creating a new group
        section.multiplier = section.multiplier + get_multiplier(recipe, event.source.crafting_speed, event.player_index)
        found_group = true
      end
    end
    if not found_group then
      local section = add_section_from_recipe(point, recipe, quality)
      if section then
        section.multiplier = get_multiplier(recipe, event.source.crafting_speed, event.player_index)
      end
    end
    storage.pre_paste[event.player_index] = nil
  else  -- paste_mode == "replace"
    local section = add_section_from_recipe(point, recipe, quality)
    if section then
      section.multiplier = get_multiplier(recipe, event.source.crafting_speed, event.player_index)
    end
  end
  if point.sections_count == 0 then
    point.add_section("")  -- add an empty section if nothing was pasted (to match vanilla behaviour)
  end
end)

---@param recipe LuaRecipe|LuaRecipePrototype
---@param n integer
---@return Ingredient?
local function get_nth_item(recipe, n)
  local i = 1
  for _, ingredient in pairs(recipe.ingredients) do
    if ingredient.type == "item" then
      if i == n then return ingredient end
      i = i + 1
    end
  end
  return nil
end

---@param section LuaLogisticSection
---@param item string
---@param quality string
---@return integer?
local function get_filter_index(section, item, quality)
  -- game.print(item.."."..quality)
  local n = 0
  for i=1,4 do
    local filter = section.get_slot(i)
    -- game.print(i..serpent.block(filter))
    if filter.value then
      if filter.value.name == item and filter.value.quality == quality and filter.value.comparator == "=" then
        return i
      end
      n = n + 1
      if n >= section.filters_count then break end
    end
  end
end

script.on_event(defines.events.on_entity_logistic_slot_changed, function(event)
  -- Enforce structure of [recipe=x,quality=y] logistic groups
  if storage.prevent_recursion then return end
  if event.section.group:sub(1, 8) ~= "[recipe=" then return end
  if event.section.group:sub(-1) ~= "]" then return end
  local group = event.section.group:sub(9, -2)  -- trim off [recipe= ]
  local j, k = group:find(",quality=")
  if not j or not k then return end
  local recipe = prototypes.recipe[group:sub(1, j-1)]
  if not recipe then return end
  local quality = prototypes.quality[group:sub(k+1)]
  if not quality then return end
  local item = get_nth_item(recipe, event.slot_index)
  if not item then  -- slot index > num items
    event.section.clear_slot(event.slot_index)
  else
    -- find and clear filter for item if it already exists (ie was moved)
    local i = get_filter_index(event.section, item.name, quality.name)
    if i and i ~= event.slot_index then
      event.section.clear_slot(i)
    end
    -- then write it back to the original index location
    set_slot_safe(event.section, event.slot_index, build_filter(item, quality.name))
  end
  if event.player_index then
    local player = game.get_player(event.player_index)
    if player then
      player.create_local_flying_text{text={"recipe-logistic-groups.logistic-slot-changed-flying-text"}, create_at_cursor=true}
      player.play_sound{path="utility/cannot_build"}
    end
  end
end)


script.on_init(function()
  storage.is_alt_mode = {}  -- player_index: mode of latest paste event
  storage.pre_paste = {}  -- player_index: StableSection to restore
end)

-- script.on_load(function()
-- end)

-- script.on_event(defines.events.on_runtime_mod_setting_changed, function(event)
--   storage.is_alt_mode = storage.is_alt_mode or {}  -- TESTING
--   storage.pre_paste = storage.pre_paste or {}
-- end)


