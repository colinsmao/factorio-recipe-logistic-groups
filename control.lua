
---@alias SlotFilter { slot: integer, filter: LogisticFilter }

---@class StableSection A table for a LuaLogisticSection that will not become invalid, which can be reloaded from
---@field group string
---@field active boolean
---@field multiplier number?
---@field slots SlotFilter[]?
local StableSection = {}

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
      if n > section.filters_count then break end
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
      section.set_slot(slot.slot, slot.filter)
    end
  else
    section.multiplier = stable_section.multiplier or 1
  end
  return section
end

script.on_event("debug-event", function(event)
  local player = game.get_player(event.player_index)
  if not player then return end
  local cursor_stack = player.cursor_stack
  if not cursor_stack or not cursor_stack.valid_for_read then return end
  if cursor_stack.name == "copper-plate" then
    local entities = player.surface.find_entities_filtered{type = "logistic-container", position=event.cursor_position}
    for _, entity in pairs(entities) do
      game.print(entity.name)
      local point = entity.get_logistic_point(defines.logistic_member_index.logistic_container)
      for _, section in pairs(point.sections) do
        game.print(section.group)
        game.print(serpent.block(save_section(section)))
      end
    end
  elseif cursor_stack.name == "iron-plate" then
    local entities = player.surface.find_entities_filtered{type = "logistic-container", position=event.cursor_position}
    for _, entity in pairs(entities) do
      local point = entity.get_logistic_point(defines.logistic_member_index.logistic_container)
      point.remove_section(1)
      for _, section in pairs(point.sections) do
        -- section.group = "test1"
        -- section.set_slot(4, {value="iron-plate", min=50})
        game.print(section.group.."."..section.index, {skip=defines.print_skip.never})
      end
    end
  end
end)

local is_alt_mode = false
script.on_event("alt-paste-mode", function(event)
  local player = game.get_player(event.player_index)
  if not player then return end
  if not player.entity_copy_source or player.entity_copy_source.type ~= "assembling-machine" then return end
  local entities = player.surface.find_entities_filtered{type = "logistic-container", position=event.cursor_position}
  for _, entity in pairs(entities) do
    is_alt_mode = true
    entity.copy_settings(player.entity_copy_source, player)  -- will fire on settings pasted events
  end
end)

local pre_paste
---@param event EventData.on_pre_entity_settings_pasted
local function on_pre_entity_settings_pasted(event)
  if event.destination.type ~= "logistic-container" then return end
  if event.source.type ~= "assembling-machine" then return end
  if is_alt_mode then
    pre_paste = {}
    for _, section in pairs(event.destination.get_logistic_point(defines.logistic_member_index.logistic_container).sections) do
      if section.valid and section.is_manual then
        table.insert(pre_paste, save_section(section))
      end
    end
    is_alt_mode = false  -- reset alt mode flag for the next event
    -- game.print(serpent.block(pre_paste), {skip=defines.print_skip.never})
  end
end
script.on_event(defines.events.on_pre_entity_settings_pasted, on_pre_entity_settings_pasted)

---@param recipe LuaRecipe
---@param quality string?
---@return string
local function get_group_name(recipe, quality)
  if quality and quality ~= "normal" then
    return "[recipe]"..recipe.name.."."..quality
  else
    return "[recipe]"..recipe.name
  end
end

---@param recipe LuaRecipe
---@param crafting_speed number
---@return number
local function get_multiplier(recipe, crafting_speed)
  return 30 * crafting_speed / recipe.energy
end

---@param point LuaLogisticPoint
---@param recipe LuaRecipe
---@param quality string?
---@return LuaLogisticSection?
local function add_section_from_recipe(point, recipe, quality, crafting_speed)
  local has_ingredient_item = false
  for _, ingredient in pairs(recipe.ingredients) do
    if ingredient.type == "item" then
      has_ingredient_item = true
    end
  end
  if not has_ingredient_item then return end

  local section = point.add_section(get_group_name(recipe, quality))
  if not section then
    game.print("Error creating logistic group")
    return
  end

  -- TODO check if the group already exists

  local i = 1
  for _, ingredient in pairs(recipe.ingredients) do
    if ingredient.type == "item" then
      local value
      if quality and quality ~= "normal" then
        value = {type="item", name=ingredient.name, quality=quality, comparator="="}
      else
        value = ingredient.name
      end
      section.set_slot(i, {value=value, min=ingredient.amount})
      i = i + 1
    end
  end
  section.multiplier = get_multiplier(recipe, crafting_speed)
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


---@param event EventData.on_entity_settings_pasted
local function on_entity_settings_pasted(event)
  -- if not pre_paste then return end
  if event.destination.type ~= "logistic-container" then return end
  if event.source.type ~= "assembling-machine" then return end
  local point = event.destination.get_logistic_point(defines.logistic_member_index.logistic_container)
  if not point then return end
  local recipe, quality = event.source.get_recipe()
  if not recipe then return end
  if quality then quality = quality.name end

  for i=point.sections_count,1,-1 do
    point.remove_section(i)
  end
  if pre_paste then
    local group_name = get_group_name(recipe, quality)
    local found_group = false
    for _, stable_section in pairs(pre_paste) do
      local section = add_section_from_stable(point, stable_section)
      if not section then return end
      if not found_group and section.active and section.group == group_name then
        -- if an active section already exists, increment its multiplier instead of creating a new group
        section.multiplier = section.multiplier + get_multiplier(recipe, event.source.crafting_speed)
        found_group = true
      end
    end
    if not found_group then
      add_section_from_recipe(point, recipe, quality, event.source.crafting_speed)
    end
    pre_paste = nil
  else
    add_section_from_recipe(point, recipe, quality, event.source.crafting_speed)
  end
  if point.sections_count == 0 then
    point.add_section("")  -- add an empty section if nothing was pasted (to match vanilla behaviour)
  end
end
script.on_event(defines.events.on_entity_settings_pasted, on_entity_settings_pasted)
