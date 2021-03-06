local util = require("utility_functions")

-- Initial definitions of shortcuts used by the TAScommands
local directions = {}
directions["STOP"] = {walking = false}
directions["N"] =  {walking = true, direction = defines.direction.north}
directions["E"] =  {walking = true, direction = defines.direction.east}
directions["S"] =  {walking = true, direction = defines.direction.south}
directions["W"] =  {walking = true, direction = defines.direction.west}
directions["NE"] = {walking = true, direction = defines.direction.northeast}
directions["NW"] = {walking = true, direction = defines.direction.northwest}
directions["SE"] = {walking = true, direction = defines.direction.southeast}
directions["SW"] = {walking = true, direction = defines.direction.southwest}

local TAScommands = {}

-- Definitions of the TAScommands

TAScommands["move"] = function (tokens, myplayer)
  util.debugprint("Moving: " .. tokens[2])
  global.walkstate = directions[tokens[2]]
  if tokens[2] == "STOP" then
    util.debugprint("Stopped at: (" .. myplayer.position.x .. "," .. myplayer.position.y .. ")")
  end
end

TAScommands["craft"] = function (tokens, myplayer)
  amt = myplayer.begin_crafting{recipe = tokens[2], count = tokens[3] or 1}
  if amt ~= (tokens[3] or 1) then
    util.errprint("Tried to craft with insufficient ingredients!")
    util.errprint("You were trying to make " .. (tokens[3] or 1) .. "x" ..tokens[2])
  else
    util.debugprint("Crafting: " .. tokens[2] .. " x" .. (tokens[3] or 1))
  end
end

TAScommands["stopcraft"] = function (tokens, myplayer)
  myplayer.cancel_crafting{index = tokens[2], count = tokens[3] or 1}
  util.debugprint("Craft abort: Index " .. tokens[2] .. " x" .. (tokens[3] or 1))
end

TAScommands["mine"] = function (tokens, myplayer)
  local position = tokens[2]
  if position then
    if position[1] ~= util.roundn(position[1]) or position[2] ~= util.roundn(position[2]) then
      hasdecimals = true
    else
      hasdecimals = false
    end
  end

  if not position or hasdecimals then global.minestate = position
  else global.minestate = {position[1] + 0.5, position[2] + 0.5} end

  if position then
    if hasdecimals then util.debugprint("Mining: Coordinates (" .. position[1] .. "," .. position[2] .. ")")
    else util.debugprint("Mining: Tile (" .. position[1] .. "," .. position[2] .. ")") end
  else util.debugprint("Mining: STOP") end
end

TAScommands["build"] = function (tokens, myplayer)
  local item = tokens[2]
  local position = tokens[3]
  local direction = tokens[4]
  util.debugprint("Building: " .. item .. " on tile (" .. position[1] .. "," .. position[2] .. ")")

  -- Check if we have the item
  if myplayer.get_item_count(item) == 0 then
    util.errprint("Build failed: No item available")
    return
  end

  -- Check if we can actually place the entity at this tile and are in range of it (Thank you for this amazing function Rseding)
  local canplace = myplayer.can_place_entity{name = item, position = position, direction = direction}
  
  -- Check if we can fast replace
  local can_replace = myplayer.surface.can_fast_replace{name = item, position = position, direction = direction, force = "player"}
  
  if (not canplace) and (not can_replace) then
    util.errprint("Build failed: Something that can't be fast replaced is in the way or you are trying to place beyond realistic reach.")
    return
  end

  -- If no errors, proceed to actually building things
  -- Place the item
  local created = myplayer.surface.create_entity{name = item, position = position, direction = direction, force="player", fast_replace = can_replace, player = myplayer}
  -- Remove the placed item from the player (since he has now spent it)
  if created and created.valid then
    myplayer.remove_item({name = item, count = 1})
    else
    util.errprint("Build failed: Reason unknown.")
  end
end

TAScommands["put"] = function (tokens, myplayer)
  local position = tokens[2]
  local item = tokens[3]
  local amount = tokens[4]
  local slot = tokens[5]

  myplayer.update_selected_entity(position)

  if not myplayer.selected then
    util.errprint("Put failed: No object at position {" .. position[1] .. "," .. position[2] .. "}.")
    return
  end

  if not myplayer.can_reach_entity(myplayer.selected) then
    util.errprint("Put failed: You are trying to reach too far.")
    return
  end

  local amountininventory = myplayer.get_item_count(item)
  local otherinv = myplayer.selected.get_inventory(slot)
  local toinsert = math.min(amountininventory, amount)

  if toinsert == 0 then
    util.errprint("Put failed: No items")
    return
  end
  if not otherinv then
    util.errprint("Put failed : Target doesn't have an inventory at {" .. position[1] .. "," .. position[2] .. "}.")
    return
  end

  local inserted = otherinv.insert{name=item, count=toinsert}

  --if we already failed for trying to insert no items, then if no items were inserted, it must be because it is full
  if inserted == 0 then
    util.errprint("Put failed: No space at {" .. position[1] .. "," .. position[2] .. "}.")
    return
  end

  myplayer.remove_item{name=item, count = inserted}

  if inserted < amount then
    util.errprint("Put sub-optimal: Only put " .. inserted .. "x " .. item  .. " instead of " .. amount .. "x " .. item .. " at {" .. position[1] .. "," .. position[2] .. "}.")
  end
  util.debugprint("Put " .. inserted .. "x " .. item .. " into " .. myplayer.selected.name  .. " at {" .. position[1] .. "," .. position[2] .. "}.")
end

TAScommands["speed"] = function (tokens, myplayer)
  if global.allowspeed then
    game.speed = tokens[2]
    util.debugprint("Speed: " .. tokens[2])
  else
    util.errprint("Speed failed: Changing the speed of the run is not allowed. ")
  end
end

TAScommands["take"] = function (tokens, myplayer)
  local position = tokens[2]
  local item = tokens[3]
  local amount = tokens[4]
  local slot = tokens[5]
  myplayer.update_selected_entity(position)

  if not myplayer.selected then
    util.errprint("Take failed: No object at position {" .. position[1] .. "," .. position[2] .. "}.")
    return
  end

  -- Check if we are in reach of this tile
  if not myplayer.can_reach_entity(myplayer.selected) then
    util.errprint("Take failed: You are trying to reach too far.")
    return
  end

  local otherinv = myplayer.selected.get_inventory(slot)

  if not otherinv then
     util.errprint("Take failed: Unable to access inventories")
    return
  end

  local totake = amount
  local amountintarget = otherinv.get_item_count(item)
  if totake == "all" then
    totake = amountintarget
  else
    totake = math.min(amountintarget, amount)
  end

  if amountintarget == 0 then
    util.errprint("Take failed: No items at {" .. position[1] .. "," .. position[2] .. "}.")
    return
  end

  local taken = myplayer.insert{name=item, count=totake}
  util.debugprint("Took " .. taken .. "x " .. item .. " from " .. myplayer.selected.name  .. " at {" .. position[1] .. "," .. position[2] .. "}.")

  if taken == 0 then
    util.errprint("Take failed: No space at {" .. position[1] .. "," .. position[2] .. "}.")
    return
  end

  otherinv.remove{name=item, count=taken}

  if amount ~= "all" and taken < amount then
    util.errprint("Take sub-optimal: Only took " .. taken .. " at {" .. position[1] .. "," .. position[2] .. "}.")
  end

end

TAScommands["tech"] = function (tokens, myplayer)
  myplayer.force.current_research = tokens[2]
  util.debugprint("Research: " .. tokens[2])
end

TAScommands["print"] = function (tokens, myplayer)
  myplayer.print(tokens[2])
end

TAScommands["recipe"] = function (tokens, myplayer)
  local position = tokens[2]
  local recipe = tokens[3]
  myplayer.update_selected_entity(position)
  if not myplayer.selected then
    util.errprint("Setting recipe: Entity at position {" .. position[1] .. "," .. position[2] .. "} could not be selected.")
    return
  end
  local items = myplayer.selected.set_recipe(recipe) --currently bugged, see https://forums.factorio.com/57452
  if items then
    for name, count in pairs(items) do
      myplayer.insert{name=name, count=count}
    end
  end
  util.debugprint("Setting recipe: " .. recipe .. " at position {" .. position[1] .. "," .. position[2] .. "}.")
end

--TODO: Change this to use LuaEntity::Rotate, this will however not allow setting it to a direction directly. Implement workaround?
TAScommands["rotate"] = function (tokens, myplayer)
  local position = tokens[2]
  local direction = tokens[3]

  myplayer.update_selected_entity(position)

  if not myplayer.selected then
    util.errprint ("Rotate failed, no object at position {" .. position[1] .. "," .. position[2] .. "}")
  end

  myplayer.selected.direction = directions[direction]["direction"]
  util.debugprint("Rotating " .. myplayer.selected.name  .. " so that it faces " .. direction .. ".")
end

return TAScommands
