local mod_gui = require("mod-gui")
-- Auto-toggling ghost placement mode when entering/exiting map view
if not global then global = {} end

-- Stores whether planning mode is active per player
local planning_mode_enabled = {}

-- GLOBAL tables must be initialized inside script lifecycle events only!
--script.on_init(function()
--    global.entity_to_tech_map = {}
--end)

local function simulate_planner_radars(player)
    local surface = player.surface
    local original_force = game.forces[global.original_force_name[player.index]]
    local planner_force = game.forces["planner-force"]

    global.simulated_planner_radars = global.simulated_planner_radars or {}

    -- Remove old simulated radars first
    for _, radar in pairs(global.simulated_planner_radars) do
        if radar.valid then radar.destroy() end
    end
    global.simulated_planner_radars = {}

    -- Create new simulated radars
    for _, radar in pairs(surface.find_entities_filtered{force = original_force, name = "radar"}) do
        local new_radar = surface.create_entity{
            name = "radar",
            position = radar.position,
            force = planner_force,
            destructible = false,
            operable = false
        }
        new_radar.active = true
        table.insert(global.simulated_planner_radars, new_radar)
    end
end

----------------------------------------------------------------
-- Helper: Enable planning mode (pretend all techs are researched)
----------------------------------------------------------------
function enable_planning_mode(player)
    if planning_mode_enabled[player.index] then return end
    planning_mode_enabled[player.index] = true
    player.print("Planning Mode: Enabled")

    -- check if crafting menu is open
    if player.opened_gui_type == 3 then
        player.opened = nil
    end

    local original_force = player.force
    global.original_force_name = global.original_force_name or {}
    global.original_force_name[player.index] = original_force.name

    -- create or reuse a dummy force
    local dummy_force = game.forces["planner-force"]
    if not dummy_force then
        dummy_force = game.create_force("planner-force")
    end
    -- Only configure dummy force once
    if not global.planner_force_initialized then
        -- Prevent combat or other issues
        for _, force in pairs(game.forces) do
            if force.name ~= "enemy" then
                dummy_force.set_friend(force.name, true)
                dummy_force.set_cease_fire(force.name, true)
                force.set_friend("planner-force", true)
                force.set_cease_fire("planner-force", true)
                end
            end
        global.planner_force_initialized = true
    end

    original_force.set_friend("planner-force", true)
    dummy_force.set_friend(original_force.name, true)
    original_force.set_cease_fire("planner-force", true)
    dummy_force.set_cease_fire(original_force.name, true)

    -- set all tech as researched on dummy force
    for _, tech in pairs(dummy_force.technologies) do
        tech.researched = true
    end

    player.force = dummy_force

    -- copy charted areas from original force to planner-force
    local surface = player.surface
    for chunk in surface.get_chunks() do
        local pos = {x = chunk.x * 32, y = chunk.y * 32}
        if original_force.is_chunk_charted(surface, chunk) then
            dummy_force.chart(surface, {left_top = pos, right_bottom = {x = pos.x + 32, y = pos.y + 32}})
        end
    end

    simulate_planner_radars(player)

    local button_flow = mod_gui.get_button_flow(player)

    local frame = button_flow.add{
        type = "frame",
        name = "planning_mode_frame",
        direction = "horizontal",
        style = "inside_shallow_frame"
    }
    frame.add{
        type = "label",
        name = "planning_mode_label",
        caption = "[Planning Mode Enabled]",
        style = "planning_mode_label_style"
    }
end



----------------------------------------------------------------
-- Helper: Disable planning mode (restore original research state)
----------------------------------------------------------------
function disable_planning_mode(player)
    if not planning_mode_enabled[player.index] then return end
    planning_mode_enabled[player.index] = false
    player.print("Planning Mode: Disabled")

    -- restore original force
    local original_force_name = global.original_force_name and global.original_force_name[player.index]
    local original_force = original_force_name and game.forces[original_force_name]
    if original_force then
        player.force = original_force
    else
        player.print("[color=red]⚠ Could not restore original force after Planning Mode.[/color]")
    end

    if global.simulated_planner_radars then
        for _, radar in pairs(global.simulated_planner_radars) do
            if radar.valid then radar.destroy() end
        end
        global.simulated_planner_radars = nil
    end

    local button_flow = mod_gui.get_button_flow(player)

    if button_flow.planning_mode_frame then
        button_flow.planning_mode_frame.destroy()
    end
end

script.on_event("planning-mode-toggle", function(event)
    local player = game.get_player(event.player_index)
    if not player then return end

    if planning_mode_enabled[player.index] then
        disable_planning_mode(player)
    else
        enable_planning_mode(player)
    end
end)
----------------------------------------------------------------
-- Event: Block opening the tech tree while planning mode is enabled
----------------------------------------------------------------
script.on_event("planning-mode-block-research-key", function(event)
    local player = game.get_player(event.player_index)
    if not player then return end

    if planning_mode_enabled[player.index] then
        player.print("[color=orange]⚠ You can't open the research screen in Planning Mode.[/color]")
    else
        player.open_technology_gui() -- manually open it if planning mode is off
    end
end)

local function is_player_in_map_view(player)
    return player and player.valid and
            player.controller_type == defines.controllers.remote
end
script.on_event(defines.events.on_gui_opened, function(event)
    local player = game.get_player(event.player_index)
    if not player then return end

    -- You can inspect event.gui_type, event.element, event.entity, etc.
    -- Leave logic here blank for now
    if planning_mode_enabled[player.index] and not is_player_in_map_view(player) then
        player.print("[color=orange]⚠ Crafting is disabled in Planning Mode.[/color]")
        player.opened = nil
    end
end)