-- Auto-toggling ghost placement mode when entering/exiting map view
if not global then global = {} end

-- Stores whether planning mode is active per player
local planning_mode_enabled = {}

-- GLOBAL tables must be initialized inside script lifecycle events only!
script.on_init(function()
    global.original_research = {}
    global.entity_to_tech_map = {}
    global.last_render_mode = {}
    global.tech_map_built = false
    global.tech_map_build_tick = game.tick + 60 -- wait 30 ticks to build map
end)
----------------------------------------------------------------
-- Helper: Build a map of entity name -> unlocking tech name
----------------------------------------------------------------
local function build_entity_tech_map(force)
    local map = {}
    if not game.recipe_prototypes then
        log("⚠ Cannot build entity->tech map: recipe_prototypes not ready.")
        return map
    end

    for _, tech in pairs(force.technologies) do
        if tech.prototype.effects then
            for _, effect in pairs(tech.prototype.effects) do
                if effect.type == "unlock-recipe" then
                    local recipe = game.recipe_prototypes[effect.recipe]
                    if recipe then
                        for _, product in pairs(recipe.products) do
                            local entity = game.entity_prototypes[product.name]
                            if entity and entity.placeable_by then
                                map[product.name] = tech.name
                            end
                        end
                    end
                end
            end
        end
    end

    return map
end

----------------------------------------------------------------
-- Helper: Enable planning mode (pretend all techs are researched)
----------------------------------------------------------------
function enable_planning_mode(player)
    if planning_mode_enabled[player.index] then return end
    planning_mode_enabled[player.index] = true
    player.print("Planning Mode: Enabled (Map View)")

    -- save current research state before modifying it
    global.original_research[player.index] = {}

    local force = player.force

    -- save active research and queue
    global.original_research[player.index]._current = force.current_research and force.current_research.name or nil

    global.original_research[player.index]._queue = {}
    for i, tech in ipairs(force.research_queue) do
        global.original_research[player.index]._queue[i] = tech.name
    end
    for name, tech in pairs(player.force.technologies) do
        global.original_research[player.index][name] = tech.researched
        tech.researched = true
    end
end


-- Build a dependency graph of technologies
local function get_sorted_technologies(force)
    local graph = {}
    local visited = {}
    local sorted = {}

    for name, tech in pairs(force.technologies) do
        graph[name] = tech.prototype.prerequisites or {}
    end

    local function visit(name)
        if visited[name] then return end
        visited[name] = true
        for _, prereq in pairs(graph[name]) do
            visit(prereq.name)
        end
        table.insert(sorted, name)
    end

    for name in pairs(graph) do
        visit(name)
    end

    return sorted
end
----------------------------------------------------------------
-- Helper: Disable planning mode (restore original research state)
----------------------------------------------------------------
function disable_planning_mode(player)
    if not planning_mode_enabled[player.index] then return end
    planning_mode_enabled[player.index] = false
    player.print("Planning Mode: Disabled")

    local original = global.original_research[player.index] or {}
    local force = player.force
    local sorted_names = get_sorted_technologies(force)

    for _, name in ipairs(sorted_names) do
        local tech = force.technologies[name]
        if original[name] ~= nil then
            tech.researched = original[name]
        else
            tech.researched = false
        end
    end

    -- Clear the queue by disabling and re-enabling it
    while force.current_research do
        force.cancel_current_research()
    end

    -- Restore research queue in original order
    if original._queue then
        for _, tech_name in ipairs(original._queue) do
            local tech = force.technologies[tech_name]
            if tech and not tech.researched then
                force.add_research(tech)
            end
        end
    end
    -- Warn player if progress on current research was lost
        player.print("[color=orange]⚠ Research progress on \"" ..
                original._current .. "\" was lost due to Planning Mode. Restarting from 0%.[/color]")
end

----------------------------------------------------------------
-- Event: Player joins game → store research state + build tech map
----------------------------------------------------------------
script.on_event(defines.events.on_player_created, function(event)

    local player = game.get_player(event.player_index)
    local force = player.force

    global.original_research[player.index] = {}
    for name, tech in pairs(force.technologies) do
        global.original_research[player.index][name] = tech.researched
    end

    global.last_render_mode[player.index] = player.render_mode

    global.tech_map_built = false
end)

----------------------------------------------------------------
-- Event: Tick handler → poll for render_mode changes
----------------------------------------------------------------
script.on_event(defines.events.on_tick, function(event)

    if not global.tech_map_built then
        local player = game.connected_players[1]
        if player and player.valid and player.controller_type == defines.controllers.character then
            if recipes and next(game.recipe_prototypes) ~= nil then
                global.entity_to_tech_map = build_entity_te
                log("✔ Entity-to-tech map built successfully.")
            else
                log("⚠ Waiting: game.recipe_prototypes not populated yet")
            end
            global.achievement_warning_shown = global.achievement_warning_shown or {}
            if not global.achievement_warning_shown[player.index] then
                player.print("[color=orange]⚠ This mod disables achievements in this save.[/color]")
                global.achievement_warning_shown[player.index] = true
            end
        else
            log("⚠ Waiting: player not ready (still in intro or invalid)")
            end
    end

    if event.tick % 10 ~= 0 then return end  -- Check every 10 ticks

    for _, player in pairs(game.connected_players) do
        local current = player.render_mode
        local previous = global.last_render_mode[player.index]

        if current ~= previous then
            global.last_render_mode[player.index] = current

            local in_map_view = (current == defines.render_mode.chart or current == defines.render_mode.chart_zoomed_in)
            local was_in_map_view = (previous == defines.render_mode.chart or previous == defines.render_mode.chart_zoomed_in)

            if in_map_view and not was_in_map_view then
                enable_planning_mode(player)
            elseif was_in_map_view and not in_map_view then
                disable_planning_mode(player)
            end
        end
    end
end)

----------------------------------------------------------------
-- Event: Block building of unresearched entities
----------------------------------------------------------------
script.on_event({defines.events.on_built_entity, defines.events.on_robot_built_entity}, function(event)
    local entity = event.created_entity or event.entity
    if not entity.valid then return end

    local force = entity.force
    local tech_name = global.entity_to_tech_map[entity.name]

    if tech_name and not force.technologies[tech_name].researched then
        -- Replace with ghost and cancel build
        entity.surface.create_entity{
            name = "entity-ghost",
            inner_name = entity.name,
            position = entity.position,
            force = force,
        }
        entity.destroy()

        local player = game.get_player(event.player_index or 1)
        if player and player.valid then
            player.print("❌ \"" .. entity.name .. "\" requires tech: " .. tech_name)
        end
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