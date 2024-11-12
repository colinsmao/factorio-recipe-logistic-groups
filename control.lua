
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
      for _, section in pairs(point.sections) do
        section.group = "test1"
        -- section.set_slot(4, {value="iron-plate", min=50})
      end
    end
  end
end)

local pre_paste
---@param event EventData.on_pre_entity_settings_pasted
local function on_pre_entity_settings_pasted(event)
  if event.destination.type ~= "logistic-container" then return end
  pre_paste = event.destination.get_logistic_point(defines.logistic_member_index.logistic_container).sections
  -- if not pre_paste then return end
  -- for _, section in pairs(pre_paste) do
  --   game.print(section.valid, {skip=defines.print_skip.never})
  -- end
end
-- script.on_event(defines.events.on_pre_entity_settings_pasted, on_pre_entity_settings_pasted)

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

---@param section LuaLogisticSection
---@param recipe LuaRecipe
---@param quality string?
local function set_section_from_recipe(section, recipe, quality)
  local i = 1
  for _, ingredient in pairs(recipe.ingredients) do
    if ingredient.type == "item" then
      if quality and quality ~= "normal" then
        value = {type="item", name=ingredient.name, quality=quality, comparator="="}
      else
        value = ingredient.name
      end
      section.set_slot(i, {value=value, min=ingredient.amount})
      i = i + 1
    end
  end
end

---@param recipe LuaRecipe
---@param crafting_speed number
---@return number
local function get_multiplier(recipe, crafting_speed)
  return 30 * crafting_speed / recipe.energy
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

  for i=1,point.sections_count do
    point.remove_section(i)
  end
  local section = point.add_section(get_group_name(recipe, quality))
  if not section then
    game.print("Error creating logistic group")
    return
  end
  set_section_from_recipe(section, recipe, quality)
  section.multiplier = get_multiplier(recipe, event.source.crafting_speed)
  -- for _, section in pairs(pre_paste) do
  --   game.print(serpent.block(section), {skip=defines.print_skip.never})
  --   if section.valid then
  --     if section.group ~= "" then
  --       point.add_section(section.group)
  --     else
  --       local new_section = point.add_section()
  --       new_section.filters = section.filters
  --     end
  --   end
  -- end
end
script.on_event(defines.events.on_entity_settings_pasted, on_entity_settings_pasted)
