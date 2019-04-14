-- kserv.lua
-- Experimental kitserver with GDB

local m = {}

m.version = "1.4"

local kroot = ".\\content\\kit-server\\"
local kmap

local home_kits
local away_kits
local home_gk_kits
local away_gk_kits

local home_next_kit
local away_next_kit
local home_next_gk_kit
local away_next_gk_kit

local is_gk_mode = false
local modes = { "PLAYERS", "GOALKEEPERS" }

local home_loaded_for = {}
local home_gk_loaded_for = {}
local config_editor_on

-- edit mode
local _team_id
local _kit_id
local _is_gk

-- final selections
local p_home
local p_away
local g_home
local g_away

local patterns = {
    ["\\(k%d+p%d+)%.ftex$"] = "KitFile",
    ["\\(k%d+p%d+_srm)%.ftex$"] = "KitFile_srm",
    ["\\(k%d+p%d+_c)%.ftex$"] = "ChestNumbersFile",
    ["\\(k%d+p%d+_l)%.ftex$"] = "LegNumbersFile",
    ["\\(k%d+p%d+_b)%.ftex$"] = "BackNumbersFile",
    ["\\(k%d+p%d+_n)%.ftex$"] = "NameFontFile",
    ["\\(k%d+g%d+)%.ftex$"] = "KitFile",
    ["\\(k%d+g%d+_srm)%.ftex$"] = "KitFile_srm",
    ["\\(k%d+g%d+_c)%.ftex$"] = "ChestNumbersFile",
    ["\\(k%d+g%d+_l)%.ftex$"] = "LegNumbersFile",
    ["\\(k%d+g%d+_b)%.ftex$"] = "BackNumbersFile",
    ["\\(k%d+g%d+_n)%.ftex$"] = "NameFontFile",
}
local ks_player_formats = {
    KitFile = "k%dp%d",
    KitFile_srm = "k%dp%d_srm",
    ChestNumbersFile = "k%dp%d_c",
    LegNumbersFile = "k%dp%d_l",
    BackNumbersFile = "k%dp%d_b",
    NameFontFile = "k%dp%d_n",
}
local ks_gk_formats = {
    KitFile = "k%dg%d",
    KitFile_srm = "k%dg%d_srm",
    ChestNumbersFile = "k%dg%d_c",
    LegNumbersFile = "k%dg%d_l",
    BackNumbersFile = "k%dg%d_b",
    NameFontFile = "k%dg%d_n",
}
local filename_keys = {
    "KitFile", "KitFile_srm", "ChestNumbersFile",
    "LegNumbersFile", "BackNumbersFile", "NameFontFile",
}

local kfile_remap = {}

local function file_exists(filename)
    local f = io.open(filename)
    if f then
        f:close()
        return true
    end
end

local function t2s(t)
    local parts = {}
    for k,v in pairs(t) do
        parts[#parts + 1] = string.format("%s=%s", k, v)
    end
    table.sort(parts) -- sort alphabetically
    return string.format("{%s}", table.concat(parts,", "))
end

local function table_copy(t)
    local new_t = {}
    for k,v in pairs(t) do
        new_t[k] = v
    end
    return new_t
end

-- kit config editor part ...
local configEd_settings = {}
local PREV_PROP_KEY = 0x21
local NEXT_PROP_KEY = 0x22
local PREV_VALUE_KEY = 0xbd
local NEXT_VALUE_KEY = 0xbb
local overlay_curr = 1
local overlay_states = {
    { ui = "Chest number size: %d", prop = "ChestNumberSize", decr = -1, incr = 1, min = 0, max = 31 },
    { ui = "Chest number x: %d", prop = "ChestNumberX", decr = -1, incr = 1, min = 0, max = 31  },
    { ui = "Chest number y: %d", prop = "ChestNumberY", decr = -1, incr = 1, min = 0, max = 7  },
    { ui = "Back number size: %d", prop = "BackNumberSize", decr = -1, incr = 1, min = 0, max = 15 },
    { ui = "Back number y: %d", prop = "BackNumberY", decr = -1, incr = 1, min = 0, max = 31  },
}
local ui_lines = {}

local function tableLength(T)
    local count = 0
    for _ in pairs(T) do
        count = count + 1
    end
    return count
end

local standard_kits = { "p1", "p2", "p3", "p4", "p5", "p6", "p7", "p8", "p9" }
local standard_gk_kits = { "g1" }

local function get_home_kit_ord_for(kit_id, is_gk)
    if not kit_id then
        return
    end
    local ord = is_gk and home_gk_loaded_for[kit_id] or home_loaded_for[kit_id]
    local kits = is_gk and home_gk_kits or home_kits
    return ord or (kits and kits[kit_id+1] and kit_id+1)
end

local function get_home_kit_path_for(kit_id, is_gk)
    if not kit_id then
        return
    end
    local ord = is_gk and home_gk_loaded_for[kit_id] or home_loaded_for[kit_id]
    local kits = is_gk and home_gk_kits or home_kits
    local kit_path = kits and kits[ord] and kits[ord][1]
    kit_path = kit_path or (is_gk and standard_gk_kits[kit_id+1] or standard_kits[kit_id+1])
    return kit_path
end

local function is_edit_mode(ctx)
    -- sorta works now, but probably needs to be more robust
    local home_team_id = ctx.kits.get_current_team(0)
    local away_team_id = ctx.kits.get_current_team(1)
    return home_team_id ~= 65535 and away_team_id == 65535
end

-- end kit config editor part ...

local function load_map(filename)
    local map = {}
    for line in io.lines(filename) do
        -- strip comment
        line = string.gsub(line, "#.*", "")
        tid, path = string.match(line, "%s*(%d+)%s*,%s*[\"]?([^\"]*)")
        tid = tonumber(tid)
        if tid and path then
            map[tid] = path
            log(string.format("tid: %d ==> content path: %s", tid, path))
        end
    end
    return map
end

local function load_config(filename)
    local cfg = {}
    local cfg_org = {}
    local key, value
    local f = io.open(filename)
    if not f then
        -- don't let io.lines raise an error, if config is missing
        -- instead, just ignore that kit
        return
    end
    for line in io.lines(filename) do
        -- strip BOF
        line = string.gsub(line, "^\xef\xbb\xbf", "")
        -- get comment
        local comment = string.match(line, ";.*")
        -- strip comment
        line = string.gsub(line, ";.*", "")
        key, value = string.match(line, "%s*(%w+)%s*=%s*[\"]?([^\"]*)")
        value = tonumber(value) or value
        if key and value then
            cfg[key] = value
        end
        -- store original structure
        cfg_org[#cfg_org + 1] = { line, comment, key, value }
    end
    return cfg, cfg_org
end

local function pad_to_numchars(s, n)
    if n > #s then
        return s .. string.rep(" ", n-#s)
    end
    return s
end

local function save_config(filename, cfg, cfg_org)
    local f = io.open(filename,"wt")
    if not f then
        log(string.format("warning: unable to save kit config to: %s", filename))
        return
    end
    local cfg_dup = table_copy(cfg)
    for i,li in ipairs(cfg_org) do
        local line, comment, key, value = li[1],li[2],li[3],li[4]
        comment = comment or ""
        if key==nil or value==nil then
            -- write original line
            f:write(string.format("%s%s\n", line, comment))
        else
            -- write updated value or original
            local s = string.format("%s=%s", key, cfg_dup[key] or value)
            s = pad_to_numchars(s, 50)
            f:write(string.format("%s%s\n", s, comment))
            cfg_dup[key] = nil
        end
    end
    -- write remaining (new) key/value pairs, if any left
    if tableLength(cfg_dup)>0 then
        f:write("\n")
        f:write("; values added by kserv.lua\n")
        local keys = {}
        for k,v in pairs(cfg_dup) do
            keys[#keys + 1] = k
        end
        table.sort(keys)
        for i,k in ipairs(keys) do
            f:write(string.format("%s=%s\n", k, cfg_dup[k]))
        end
    end
    f:close()
    log(string.format("kit config saved to: %s", filename))
end

local function apply_changes(team_id, ki, cfg, save_to_disk)
    local excludes = {
        KitFile=1, KitFile_srm=1, ChestNumbersFile=1,
        BackNumbersFile=1, LegNumbersFile=1, NameFontFile=1,
    }
    for k,v in pairs(cfg) do
        if not excludes[k] then
            ki[2][k] = v
        end
    end
    if not save_to_disk then
        return
    end
    -- save
    local team_path = kmap[team_id]
    if not team_path then
        log("warning: no entry for team %d in map.txt. Skipping save")
        return
    end
    local filename = string.format("%s%s\\%s\\config.txt", kroot, team_path, ki[1])
    save_config(filename, ki[2], ki[3])
end

local function load_configs_for_team(team_id)
    local path = kmap[team_id]
    if not path then
        -- no kits for this team
        log(string.format("no kitserver kits for: %s", team_id))
        return nil, nil
    end
    log(string.format("looking for configs for: %s", path))
    -- players
    local pt = {}
    local f = io.open(kroot .. path .. "\\order.txt")
    if f then
        f:close()
        for line in io.lines(kroot .. path .. "\\order.txt") do
            line = string.gsub(line, "^\xef\xbb\xbf", "")
            line = string.gsub(string.gsub(line,"%s*$", ""), "^%s*", "")
            local filename = kroot .. path .. "\\" .. line .. "\\config.txt"
            local cfg, cfg_org = load_config(filename)
            if cfg then
                pt[#pt + 1] = { line, cfg, cfg_org }
            else
                log("WARNING: unable to load kit config from: " .. filename)
            end
        end
    end
    -- goalkeepers
    local gt = {}
    local f = io.open(kroot .. path .. "\\gk_order.txt")
    if f then
        f:close()
        for line in io.lines(kroot .. path .. "\\gk_order.txt") do
            line = string.gsub(line, "^\xef\xbb\xbf", "")
            line = string.gsub(string.gsub(line,"%s*$", ""), "^%s*", "")
            local filename = kroot .. path .. "\\" .. line .. "\\config.txt"
            local cfg, cfg_org = load_config(filename)
            if cfg then
                gt[#gt + 1] = { line, cfg, cfg_org }
            else
                log("WARNING: unable to load GK kit config from: " .. filename)
            end
        end
    end
    return pt, gt
end

local function get_curr_kit(ctx, team_id, home_or_away)
    local kit_id = ctx.kits.get_current_kit_id(home_or_away)
    local kit_path = standard_kits[kit_id] or standard_kits[1]
    return { kit_path, ctx.kits.get(team_id, kit_id) }
end

local function get_curr_gk_kit(ctx, team_id)
    local kit_path = standard_gk_kits[1]
    return { kit_path, ctx.kits.get_gk(team_id) }
end

local function dump_kit_config(filename, t)
    -- utility method, for easy dumping of configs to disk
    -- (for debugging purposes)
    local f = assert(io.open(filename,"wt"))
    f:write("; Kit config dumped by kserv.lua\n\n")
    local keys = {}
    for k,v in pairs(t) do
        keys[#keys + 1] = k
    end
    table.sort(keys)
    for i,k in ipairs(keys) do
        f:write(string.format("%s=%s\n", k, t[k]))
    end
    f:close()
end

local function prep_home_team(ctx)
    -- see what kits are available
    home_kits, home_gk_kits = load_configs_for_team(ctx.home_team)
    home_next_kit = home_kits and #home_kits>0 and 0 or nil
    home_next_gk_kit = home_gk_kits and #home_gk_kits>0 and 0 or nil
    log(string.format("prepped home kits for: %s", ctx.home_team))
end

local function prep_away_team(ctx)
    -- see what kits are available
    away_kits, away_gk_kits = load_configs_for_team(ctx.away_team)
    away_next_kit = away_kits and #away_kits>0 and 0 or nil
    away_next_gk_kit = away_gk_kits and #away_gk_kits>0 and 0 or nil
    log(string.format("prepped away kits for: %s", ctx.away_team))
end

local function config_update_filenames(team_id, ord, kit_path, kit_cfg, formats)
    local path = kmap[team_id]
    if not path then
        return
    end
    for _,k in ipairs(filename_keys) do
        local attr = kit_cfg[k]
        if attr and attr ~= "" then
            local pathname = string.format("%s\\%s\\%s.ftex", path, kit_path, attr)
            log("checking: " .. kroot .. pathname)
            if file_exists(kroot .. pathname) then
                --[[
                rewrite filename in uniparam config to a "fake" file
                that uniquely maps to a specific kit for this team.
                Later, when the game requests this texture, we use
                "livecpk_make_key" and "livecpk_get_filepath" to feed
                the actual ftex from GDB
                --]]
                local fmt = formats[k]
                if fmt then
                    local fkey = string.format(fmt, team_id, ord)
                    kfile_remap[fkey] = pathname
                    kit_cfg[k] = fkey
                end
            end
        end
    end
end

local function update_kit_config(team_id, kit_ord, kit_path, cfg)
    -- insert _srm property, if not there
    -- (Standard configs do not have it, because the game
    -- just adds an "_srm" suffix to KitFile. But because
    -- we are remapping names, we need to account for that)
    if cfg.KitFile and not cfg.KitFile_srm then
        cfg.KitFile_srm = cfg.KitFile .. "_srm"
    end
    -- trick: mangle the filenames so that we can livecpk them later
    -- (only do that for files that actually exist in kitserver content)
    kit_ord = kit_ord or (kit_path == "p2" and 2 or 1)
    config_update_filenames(team_id, kit_ord, kit_path, cfg, ks_player_formats)
end

local function update_gk_kit_config(team_id, kit_ord, kit_path, cfg)
    -- insert _srm property, if not there
    -- (Standard configs do not have it, because the game
    -- just adds an "_srm" suffix to KitFile. But because
    -- we are remapping names, we need to account for that)
    if cfg.KitFile and not cfg.KitFile_srm then
        cfg.KitFile_srm = cfg.KitFile .. "_srm"
    end
    -- trick: mangle the filenames so that we can livecpk them later
    -- (only do that for files that actually exist in kitserver content)
    kit_ord = kit_ord or 1
    config_update_filenames(team_id, kit_ord, kit_path, cfg, ks_gk_formats)
end

-- kit config editor part ...
local function KitConfigEditor_get_settings(team_id, kit_path, kit_info)
    log(string.format("Into KitConfigEditor_get_settings (%s, %s, %s) ... ", team_id, kit_path, kit_info))
    if kit_path then
        configEd_settings[team_id] = configEd_settings[team_id] or {}
		configEd_settings[team_id][kit_path] = {}
		for name, value in pairs(kit_info) do
			if name and value then
				value = tonumber(value) or value
				configEd_settings[team_id][kit_path][name] = value
			end
		end
		log(string.format("... loaded kit config editor state: %s", t2s(configEd_settings[team_id][kit_path])))
	end
end
-- end kit config editor part ...

local function reset_match(ctx)
    home_loaded_for = {}
    home_gk_loaded_for = {}
    p_home, p_away = nil, nil
    g_home, g_away = nil, nil
    is_gk_mode = false -- always start in Players mode

    prep_home_team(ctx)
    prep_away_team(ctx)
end

function m.set_teams(ctx, home, away)
    reset_match(ctx)
end

function m.set_kits(ctx, home_info, away_info)
    log(string.format("set_kits: home_info (team=%d): %s", ctx.home_team, t2s(home_info)))
    log(string.format("set_kits: away_info (team=%d): %s", ctx.away_team, t2s(away_info)))
    --dump_kit_config(string.format("%s%d-%s-config.txt", ctx.sider_dir, ctx.home_team, home_info.kit_id), home_info)
    --dump_kit_config(string.format("%s%d-%s-config.txt", ctx.sider_dir, ctx.away_team, away_info.kit_id), away_info)

    reset_match(ctx)

    -- load corresponding kits, if available in GDB
    local hi
    if home_kits and #home_kits > 0 then
        local kit_id = ctx.kits.get_current_kit_id(0)
        local ki = home_kits[kit_id+1]
        hi = ki and ki[2] or nil
        if hi then
            local kit_path = ki[1]
            log("loading home kit: "  .. kit_path)
            home_next_kit = kit_id+1
            update_kit_config(ctx.home_team, home_next_kit, kit_path, hi)
            log(string.format("home cfg returned (%s): %s", kit_path, t2s(hi)))
        end
        p_home = get_curr_kit(ctx, ctx.home_team, 0)
    end
    local ai
    if away_kits and #away_kits > 0 then
        local kit_id = ctx.kits.get_current_kit_id(1)
        local ki = away_kits[kit_id+1]
        ai = ki and ki[2] or nil
        if ai then
            local kit_path = ki[1]
            log("loading away kit: "  .. kit_path)
            away_next_kit = kit_id+1
            update_kit_config(ctx.away_team, away_next_kit, kit_path, ai)
            log(string.format("away cfg returned (%s): %s", kit_path, t2s(ai)))
        end
        p_away = get_curr_kit(ctx, ctx.away_team, 1)
    end

    -- set gk kits, if we have them
    if home_gk_kits and #home_gk_kits>0 then
        local kit_id = ctx.kits.get_current_kit_id(0)
        local ki = home_gk_kits[kit_id+1]
        local cfg = ki and ki[2] or nil
        if cfg then
            local kit_path = ki[1]
            log("loading home GK kit: "  .. kit_path)
            home_next_gk_kit = kit_id+1
            update_gk_kit_config(ctx.home_team, home_next_gk_kit, kit_path, cfg)
            ctx.kits.set_gk(ctx.home_team, cfg)
        end
        g_home = get_curr_gk_kit(ctx, ctx.home_team)
    end
    if away_gk_kits and #away_gk_kits>0 then
        local kit_id = ctx.kits.get_current_kit_id(1)
        local ki = away_gk_kits[kit_id+1]
        local cfg = ki and ki[2] or nil
        if cfg then
            local kit_path = ki[1]
            log("loading away GK kit: "  .. kit_path)
            away_next_gk_kit = kit_id+1
            update_gk_kit_config(ctx.away_team, away_next_gk_kit, kit_path, cfg)
            ctx.kits.set_gk(ctx.away_team, cfg)
        end
        g_away = get_curr_gk_kit(ctx, ctx.away_team)
    end
    --dump_kit_config(string.format("%s%d-%s-gk-config.txt", ctx.sider_dir, ctx.home_team, 0), g_home[2])
    --dump_kit_config(string.format("%s%d-%s-gk-config.txt", ctx.sider_dir, ctx.away_team, 0), g_away[2])
    return hi, ai
end

function m.make_key(ctx, filename)
    --log("wants: " .. filename)
    for patt,attr in pairs(patterns) do
        local fkey = string.match(filename, patt)
        if fkey then
            local key = kfile_remap[fkey]
            if key then
                log(string.format("fkey: {%s}, key: {%s}", fkey, key))
            end
            return key
        end
    end
    -- no key for this file
    return ""
end

function m.get_filepath(ctx, filename, key)
    if key and key ~= "" then
        return kroot .. key
    end
end

function m.key_up(ctx, vkey)
    if config_editor_on and (vkey == PREV_VALUE_KEY or vkey == NEXT_VALUE_KEY) then
        local s = overlay_states[overlay_curr]
        local kit_id, is_gk = ctx.kits.get_current_kit_id(0)
        local kit_ord = get_home_kit_ord_for(kit_id, is_gk)
        if kit_ord then
            local kits = is_gk and home_gk_kits or home_kits
            local update = is_gk and update_gk_kit_config or update_kit_config
            local curr = kits[kit_ord]
            local team_id = ctx.kits.get_current_team(0)
            if team_id then
                local cfg = table_copy(configEd_settings[team_id][curr[1]])
                update(team_id, kit_ord, curr[1], cfg)
                apply_changes(team_id, kits[kit_ord], cfg, true)
                -- trigger refresh
                if is_edit_mode(ctx) and is_gk then
                    ctx.kits.set_gk(team_id, cfg)
                else
                    ctx.kits.set(team_id, kit_id, cfg)
                end
                ctx.kits.refresh(0)
            end
        end
    end
end

function m.key_down(ctx, vkey)
    if vkey == 0x30 then
        kmap = load_map(kroot .. "\\map.txt")
        log("Reloaded map from: " .. kroot .. "\\map.txt")

    elseif vkey == 0x32 then
        if is_edit_mode(ctx) then
            config_editor_on = not config_editor_on
            if config_editor_on then
                local team_id = ctx.kits.get_current_team(0)
                if team_id and team_id ~= 65535 then
                    ctx.home_team = team_id
                    prep_home_team(ctx)

                    local kit_id, is_gk = ctx.kits.get_current_kit_id(0)
                    log(string.format("kit_id=%d, is_gk=%s", kit_id, is_gk))
                    local kit_ord = get_home_kit_ord_for(kit_id, is_gk)
                    local kits = is_gk and home_gk_kits or home_kits
                    local update = is_gk and update_gk_kit_config or update_kit_config
                    if kit_ord then
                        local curr = kits[kit_ord]
                        local cfg = table_copy(curr[2])
                        update(ctx.home_team, kit_ord, curr[1], cfg)
                        -- kit config editor part ...
                        KitConfigEditor_get_settings(team_id, curr[1], cfg) -- get current kit data for configEd overlay
                        -- end kit config editor part ...
                    end
                end
            end
        end

    elseif not is_edit_mode(ctx) and vkey == 0x39 then -- player/goalkeeper mode toggle
        if is_gk_mode then
            -- try to switch to players mode
            g_home = home_kits and home_gk_kits[home_next_gk_kit]
            g_away = away_kits and away_gk_kits[away_next_gk_kit]

            -- home: update cfg
            local curr = p_home
            if curr and curr[2] then
                local cfg = table_copy(curr[2])
                update_kit_config(ctx.home_team, home_next_kit, curr[1], cfg)
                -- trigger refresh
                local home_kit_id = ctx.kits.get_current_kit_id(0)
                ctx.kits.set(ctx.home_team, home_kit_id, cfg, 0)
                ctx.kits.refresh(0)
                is_gk_mode = false
            end
            -- away: update cfg
            local curr = p_away
            if curr and curr[2] then
                local cfg = table_copy(curr[2])
                update_kit_config(ctx.away_team, away_next_kit, curr[1], cfg)
                -- trigger refresh
                local away_kit_id = ctx.kits.get_current_kit_id(1)
                ctx.kits.set(ctx.away_team, away_kit_id, cfg, 1)
                ctx.kits.refresh(1)
                is_gk_mode = false
            end
        else
            -- try to switch to goalkeepers mode
            p_home = home_kits and home_kits[home_next_kit]
            p_away = away_kits and away_kits[away_next_kit]

            -- home: update cfg
            local curr = g_home
            if curr and curr[2] then
                -- we have a home GK kit
                local cfg = table_copy(curr[2])
                update_gk_kit_config(ctx.home_team, home_next_gk_kit, curr[1], cfg)
                -- update kit
                ctx.kits.set_gk(ctx.home_team, cfg)
                -- trigger refresh
                local home_kit_id = ctx.kits.get_current_kit_id(0)
                ctx.kits.set(ctx.home_team, home_kit_id, cfg)
                ctx.kits.refresh(0)
                is_gk_mode = true
            end
            -- away: update cfg
            local curr = g_away
            if curr and curr[2] then
                -- we have an away GK kit
                local cfg = table_copy(curr[2])
                update_gk_kit_config(ctx.away_team, away_next_gk_kit, curr[1], cfg)
                -- update kit
                ctx.kits.set_gk(ctx.away_team, cfg)
                -- trigger refresh
                local away_kit_id = ctx.kits.get_current_kit_id(1)
                ctx.kits.set(ctx.away_team, away_kit_id, cfg)
                ctx.kits.refresh(1)
                is_gk_mode = true
            end
        end

    elseif vkey == 0x36 then -- next home kit
        if not home_kits or not home_gk_kits then
            prep_home_team(ctx)
        end
        if not is_gk_mode and not(is_edit_mode(ctx) and _is_gk) then
            -- players
            if home_kits and #home_kits > 0 then
                -- advance the iter
                home_next_kit = (home_next_kit % #home_kits) + 1
                log("home_next_kit: " .. home_next_kit)
                -- update cfg
                local curr = home_kits[home_next_kit]
                local cfg = table_copy(curr[2])
                update_kit_config(ctx.home_team, home_next_kit, curr[1], cfg)
                -- trigger refresh
                local kit_id = ctx.kits.get_current_kit_id(0)
                home_loaded_for[kit_id] = home_next_kit
                ctx.kits.set(ctx.home_team, kit_id, cfg, 0)
                ctx.kits.refresh(0)
                p_home = curr
            end
        else
            -- goalkeepers
            if home_gk_kits and #home_gk_kits > 0 then
                -- advance the iter
                home_next_gk_kit = (home_next_gk_kit % #home_gk_kits) + 1
                log("home_next_gk_kit: " .. home_next_gk_kit)
                -- update cfg
                local curr = home_gk_kits[home_next_gk_kit]
                local cfg = table_copy(curr[2])
                update_gk_kit_config(ctx.home_team, home_next_gk_kit, curr[1], cfg)
                -- trigger refresh
                local kit_id, is_gk = ctx.kits.get_current_kit_id(0)
                log(string.format("is_edit_mode=%s, is_gk=%s", is_edit_mode(ctx), is_gk))
                home_gk_loaded_for[0] = home_next_gk_kit
                if is_edit_mode(ctx) and is_gk then
                    -- in edit mode, we need to modify the actual GK block
                    log(string.format("calling set_gk(%s, %s)", ctx.home_team, t2s(cfg)))
                    ctx.kits.set_gk(ctx.home_team, cfg)
                else
                    ctx.kits.set(ctx.home_team, kit_id, cfg)
                end
                ctx.kits.refresh(0)
                g_home = curr
            end
        end
    elseif not is_edit_mode(ctx) and vkey == 0x37 then -- next away kit
        if not away_kits or not away_gk_kits then
            prep_away_team(ctx)
        end
        if not is_gk_mode then
            -- players
            if away_kits and #away_kits > 0 then
                -- advance the iter
                away_next_kit = (away_next_kit % #away_kits) + 1
                log("away_next_kit: " .. away_next_kit)
                -- update cfg
                local curr = away_kits[away_next_kit]
                local cfg = table_copy(curr[2])
                update_kit_config(ctx.away_team, away_next_kit, curr[1], cfg)
                -- trigger refresh
                local kit_id = ctx.kits.get_current_kit_id(1)
                ctx.kits.set(ctx.away_team, kit_id, cfg, 1)
                ctx.kits.refresh(1)
                p_away = curr
            end
        else
            -- goalkeepers
            if away_gk_kits and #away_gk_kits > 0 then
                -- advance the iter
                away_next_gk_kit = (away_next_gk_kit % #away_gk_kits) + 1
                log("away_next_gk_kit: " .. away_next_gk_kit)
                -- update cfg
                local curr = away_gk_kits[away_next_gk_kit]
                local cfg = table_copy(curr[2])
                update_gk_kit_config(ctx.away_team, away_next_gk_kit, curr[1], cfg)
                -- trigger refresh
                local kit_id = ctx.kits.get_current_kit_id(1)
                ctx.kits.set(ctx.away_team, kit_id, cfg)
                ctx.kits.refresh(1)
                g_away = curr
            end
        end

	-- kit config editor part ...
    elseif config_editor_on and vkey == NEXT_PROP_KEY then
        if overlay_curr < #overlay_states then
            overlay_curr = overlay_curr + 1
        end
    elseif config_editor_on and vkey == PREV_PROP_KEY then
        if overlay_curr > 1 then
            overlay_curr = overlay_curr - 1
        end

    elseif config_editor_on and vkey == NEXT_VALUE_KEY then
        local s = overlay_states[overlay_curr]
        local kit_id, is_gk = ctx.kits.get_current_kit_id(0)
        local kit_ord = get_home_kit_ord_for(kit_id, is_gk)
        local kits = is_gk and home_gk_kits or home_kits
        local update = is_gk and update_gk_kit_config or update_kit_config
        if kit_ord then
            local curr = kits[kit_ord]
            log(string.format("curr: %s, %s", curr[1], t2s(curr[2])))
            local team_id = ctx.kits.get_current_team(0)
            if s.incr ~= nil and team_id then
                configEd_settings[team_id][curr[1]][s.prop] = math.min(configEd_settings[team_id][curr[1]][s.prop] + s.incr, s.max)
                local cfg = table_copy(configEd_settings[team_id][curr[1]])
                update(team_id, kit_ord, curr[1], cfg)
                apply_changes(team_id, kits[kit_ord], cfg, true)
            elseif s.nextf ~= nil and team_id then
                configEd_settings[team_id][curr[1]][s.prop] = s.nextf(configEd_settings[team_id][curr[1]][s.prop])
                local cfg = table_copy(configEd_settings[team_id][curr[1]])
                update(team_id, kit_ord, curr[1], cfg)
                apply_changes(team_id, kits[kit_ord], cfg, true)
            end
        end

    elseif config_editor_on and vkey == PREV_VALUE_KEY then
        local s = overlay_states[overlay_curr]
        local kit_id, is_gk = ctx.kits.get_current_kit_id(0)
        local kit_ord = get_home_kit_ord_for(kit_id, is_gk)
        local kits = is_gk and home_gk_kits or home_kits
        local update = is_gk and update_gk_kit_config or update_kit_config
        if kit_ord then
            local curr = kits[kit_ord]
            log(string.format("curr: %s, %s", curr[1], t2s(curr[2])))
            local team_id = ctx.kits.get_current_team(0)
            if s.decr ~= nil and team_id then
                configEd_settings[team_id][curr[1]][s.prop] = math.max(s.min, configEd_settings[team_id][curr[1]][s.prop] + s.decr)
                local cfg = table_copy(configEd_settings[team_id][curr[1]])
                update(team_id, kit_ord, curr[1], cfg)
                apply_changes(team_id, kits[kit_ord], cfg, true)
            elseif s.prevf ~= nil and team_id then
                configEd_settings[team_id][curr[1]][s.prop] = s.prevf(configEd_settings[team_id][curr[1]][s.prop])
                local cfg = table_copy(configEd_settings[team_id][curr[1]])
                update(team_id, kit_ord, curr[1], cfg)
                apply_changes(team_id, kits[kit_ord], cfg, true)
            end
        end
    end
end

function m.finalize_kits(ctx)
    log("finalizing kits ...")
    is_gk_mode = false
    if home_kits and #home_kits > 0 then
        local curr = g_home
        if curr then
            local cfg = table_copy(curr[2])
            update_gk_kit_config(ctx.home_team, home_next_gk_kit, curr[1], cfg)
            ctx.kits.set_gk(ctx.home_team, cfg)
        end
        local curr = p_home
        if curr then
            local kit_id = ctx.kits.get_current_kit_id(0)
            local cfg = table_copy(curr[2])
            update_kit_config(ctx.home_team, home_next_kit, curr[1], cfg)
            ctx.kits.set(ctx.home_team, kit_id, cfg, 0)
        end
    end
    if away_kits and #away_kits > 0 then
        local curr = g_away
        if curr then
            local cfg = table_copy(curr[2])
            update_gk_kit_config(ctx.away_team, away_next_gk_kit, curr[1], cfg)
            ctx.kits.set_gk(ctx.away_team, cfg)
        end
        local curr = p_away
        if curr then
            local kit_id = ctx.kits.get_current_kit_id(1)
            local cfg = table_copy(curr[2])
            update_kit_config(ctx.away_team, away_next_kit, curr[1], cfg)
            ctx.kits.set(ctx.away_team, kit_id, cfg, 1)
        end
    end
end

-- kit config editor part ...
local function get_configEd_overlay_states(ctx)
    if not config_editor_on then
        return ""
    end
    if not is_edit_mode(ctx) then
        -- does not look to be Edit mode
        return ""
    end
    local kit_id, is_gk = ctx.kits.get_current_kit_id(0)
    if not kit_id then
        return ""
    end

    local kit_ord = get_home_kit_ord_for(kit_id, is_gk)
    if not kit_ord then
        -- we don't have a GDB kit to edit
        return ""
    end

    local team_id = ctx.kits.get_current_team(0)
    local kits = is_gk and home_gk_kits or home_kits
    if not kits then
        return ""
    end

    local update = is_gk and update_gk_kit_config or update_kit_config
	local curr = kits[kit_ord]
    if curr and configEd_settings and configEd_settings[team_id] and configEd_settings[team_id][curr[1]]==nil then
        local cfg = table_copy(curr[2])
        update(team_id, kit_ord, curr[1], cfg)
        -- kit config editor part ...
        KitConfigEditor_get_settings(team_id, curr[1], cfg) -- get current kit data for configEd overlay
        -- end kit config editor part ...
    end
    if curr and curr[1] and configEd_settings and configEd_settings[team_id] and tableLength(configEd_settings[team_id]) > 0
            and tableLength(configEd_settings[team_id][curr[1]]) > 0 then
        -- construct ui text
        for i,v in ipairs(overlay_states) do
            local s = overlay_states[i]
            local setting = string.format(s.ui, configEd_settings[team_id][curr[1]][s.prop])
            if i == overlay_curr then
                ui_lines[i] = string.format("\n---> %s <---", setting)
            else
                ui_lines[i] = string.format("\n     %s", setting)
            end
        end
        return string.format([[

     Kit Config live editor (for now, home team only, chest numbers)
     Keys: [PgUp][PgDn] - choose setting, [-][+] - modify value
     %s]], table.concat(ui_lines))

    else
        -- log("In get_overlay_states: configEd_settings is nul or empty!! ")
    end
    return ""
end
-- end kit config editor part ...

function m.overlay_on(ctx)
    if is_edit_mode(ctx) then
        _team_id = ctx.kits.get_current_team(0)
        _kit_id, _is_gk = ctx.kits.get_current_kit_id(0)
        if ctx.home_team ~= _team_id then
            -- team changed: reset
            ctx.home_team = _team_id
            prep_home_team(ctx)
        end
        return string.format("team:%d, kit:%s | [2] - Editor (%s), [6] - switch kit, [0] - reload map"
                -- kit config editor part ...
                .. "\n" ..
                get_configEd_overlay_states(ctx),
                -- end kit config editor part ...
                _team_id, get_home_kit_path_for(_kit_id, _is_gk),
                config_editor_on and "ON" or "OFF")
    else
        return string.format("%s | [6][7] - switch kits, [9] - PL/GK, [0] - reload map",
            modes[is_gk_mode and 2 or 1])
    end
end

function m.init(ctx)
    if kroot:sub(1,1) == "." then
        kroot = ctx.sider_dir .. kroot
    end
    kmap = load_map(kroot .. "\\map.txt")
    ctx.register("overlay_on", m.overlay_on)
    ctx.register("key_down", m.key_down)
    ctx.register("key_up", m.key_up)
    ctx.register("set_teams", m.set_teams)
    ctx.register("set_kits", m.set_kits)
    ctx.register("after_set_conditions", m.finalize_kits)
    ctx.register("livecpk_make_key", m.make_key)
    ctx.register("livecpk_get_filepath", m.get_filepath)
end

return m
