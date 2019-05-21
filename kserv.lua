-- kserv.lua
-- Experimental kitserver with GDB

local m = {}

m.version = "1.9h"

local kroot = ".\\content\\kit-server\\"
local kmap
local compmap

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
local away_loaded_for = {}
local away_gk_loaded_for = {}
local was_p_home
local was_p_away

local config_editor_on

-- edit mode
local _team_id
local _kit_id
local _is_gk
local curr_col

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
    if not t then
        return tostring(t)
    end
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

local function pad_to_numchars(s, n)
    s = tostring(s)
    if n > #s then
        return s .. string.rep(" ", n-#s)
    end
    return s
end

-- kit config editor part ...
local function tableLength(T)
    local count = 0
    for _ in pairs(T) do
        count = count + 1
    end
    return count
end

local function tableInvert(T) -- swaps keys with values
   local s={}
   for k,v in pairs(T) do
     s[v]=k
   end
   return s
end

local function rot_left(k, v, cv)
    for i, val in pairs(table_copy(v)) do
        if v[1] ~= cv then
            -- keep rotating to the left, until current value is reached
            table.insert( v, tableLength(v), table.remove( v, 1 ) )
        else
            break
        end
    end
    -- then rotate once more, to reach next value
    table.insert( v, tableLength(v), table.remove( v, 1 ) )
    return v[1], k[v[1]]
end

local function rot_right(k, v, cv)
    for i, val in pairs(table_copy(v)) do
        if v[1] ~= cv then
            -- keep rotating to the right, until current value is reached
            table.insert( v, 1, table.remove( v, tableLength(v) ) )
        else
            break
        end
    end
    -- then rotate once more, to reach previous value
    table.insert( v, 1, table.remove( v, tableLength(v) ) )
    return v[1], k[v[1]]
end

local configEd_settings = {}
local PREV_PROP_KEY = 0x21
local NEXT_PROP_KEY = 0x22
local PREV_VALUE_KEY = 0xbd
local NEXT_VALUE_KEY = 0xbb
local SWITCH_MENU_PAGE = 0x33
local overlay_curr = 1
local overlay_page = 1
local overlay_states = {
    { ui = "Short sleeves model: %d", prop = "ShortSleevesModel", page = 1, col = 1, row = 1, decr = -1, incr = 1, min = 1, max = 1  },
    { ui = "Shirt model: %s", prop = "ShirtModel", page = 1, col = 1, row = 2,
        vals = {"144", "151=Semi-long", "160", "176=Legacy"}, keys = {["144"] = 144, ["151=Semi-long"] = 151, ["160"] = 160, ["176=Legacy"] = 176},
        nextf = rot_left,
        prevf = rot_right,
    },
    { ui = "Collar: %d", prop = "Collar", page = 1, col = 1, row = 3, decr = -1, incr = 1, min = 1, max = 127  },
    { ui = "Tight kit: %s", prop = "TightKit", page = 1, col = 1, row = 4,
        vals = {"Off", "On"}, keys = {["Off"] = 0, ["On"] = 1},
        nextf = rot_left,
        prevf = rot_right,
    },
    { ui = "Shirt pattern: %d", prop = "ShirtPattern", page = 1, col = 1, row = 5, decr = -1, incr = 1, min = 0, max = 6  },
    { ui = "Winter collar: %d", prop = "WinterCollar", page = 1, col = 1, row = 6, decr = -1, incr = 1, min = 1, max = 127  },
    { ui = "Long sleeves: %s", prop = "LongSleevesType", page = 1, col = 1, row = 7,
        vals = {"Normal&U-Shirt", "Only Undershirt"}, keys = {["Normal&U-Shirt"] = 62, ["Only Undershirt"] = 187},
        nextf = rot_left,
        prevf = rot_right,
    },

    { ui = "Chest number size: %d", prop = "ChestNumberSize", page = 1, col = 2, row = 1, decr = -1, incr = 1, min = 0, max = 28 },
    { ui = "Chest number x: %d", prop = "ChestNumberX", page = 1, col = 2, row = 2, decr = -1, incr = 1, min = 0, max = 29  },
    { ui = "Chest number y: %d", prop = "ChestNumberY", page = 1, col = 2, row = 3, decr = -1, incr = 1, min = 0, max = 6  },

    { ui = "Shorts model: %d", prop = "ShortsModel", page = 1, col = 2, row = 4, decr = -1, incr = 1, min = 0, max = 17  },
    { ui = "Shorts number size: %d", prop = "ShortsNumberSize", page = 1, col = 2, row = 5, decr = -1, incr = 1, min = 0, max = 28  },
    { ui = "Shorts number x: %d", prop = "ShortsNumberX", page = 1, col = 2, row = 6, decr = -1, incr = 1, min = 0, max = 14  },
    { ui = "Shorts number y: %d", prop = "ShortsNumberY", page = 1, col = 2, row = 7, decr = -1, incr = 1, min = 0, max = 15  },
    { ui = "Shorts number side: %s", prop = "ShortsNumberSide", page = 1, col = 2, row = 8,
        vals = {"Left", "Right"}, keys = {["Left"] = 0, ["Right"] = 1},
        nextf = rot_left,
        prevf = rot_right,
    },

    { ui = "Name: %s", prop = "Name", page = 1, col = 3, row = 1,
        vals = {"On", "Off"}, keys = {["On"] = 0, ["Off"] = 1},
        nextf = rot_left,
        prevf = rot_right,
    },
    { ui = "Name shape: %s", prop = "NameShape", page = 1, col = 3, row = 2,
        vals = {"Straight", "Light curve", "Medium curve", "Extreme curve"}, keys = {["Straight"] = 0, ["Light curve"] = 1, ["Medium curve"] = 2, ["Extreme curve"] = 3},
        nextf = rot_left,
        prevf = rot_right,
    },
    { ui = "Name y: %d", prop = "NameY", page = 1, col = 3, row = 3, decr = -1, incr = 1, min = 0, max = 16  },
    { ui = "Name size: %d", prop = "NameSize", page = 1, col = 3, row = 4, decr = -1, incr = 1, min = 0, max = 20  },
    { ui = "Back number size: %d", prop = "BackNumberSize", page = 1, col = 3, row = 5, decr = -1, incr = 1, min = 0, max = 28 },
    { ui = "Back number y: %d", prop = "BackNumberY", page = 1, col = 3, row = 6, decr = -1, incr = 1, min = 0, max = 29  },
    { ui = "Back number spacing: %d", prop = "BackNumberSpacing", page = 1, col = 3, row = 7, decr = -1, incr = 1, min = 0, max = 3  },

    { ui = "Badge (Right,Short,X): %d", prop = "RightShortX", page = 1, col = 4, row = 1, decr = -1, incr = 1, min = 0, max = 31  },
    { ui = "Badge (Right,Short,Y): %d", prop = "RightShortY", page = 1, col = 4, row = 2, decr = -1, incr = 1, min = 0, max = 31  },
    { ui = "Badge (Right,Long,X): %d", prop = "RightLongX", page = 1, col = 4, row = 3, decr = -1, incr = 1, min = 0, max = 31  },
    { ui = "Badge (Right,Long,Y): %d", prop = "RightLongY", page = 1, col = 4, row = 4, decr = -1, incr = 1, min = 0, max = 31  },
    { ui = "Badge (Left,Short,X): %d", prop = "LeftShortX", page = 1, col = 4, row = 5, decr = -1, incr = 1, min = 0, max = 31  },
    { ui = "Badge (Left,Short,Y): %d", prop = "LeftShortY", page = 1, col = 4, row = 6, decr = -1, incr = 1, min = 0, max = 31  },
    { ui = "Badge (Left,Long,X): %d", prop = "LeftLongX", page = 1, col = 4, row = 7, decr = -1, incr = 1, min = 0, max = 31  },
    { ui = "Badge (Left,Long,Y): %d", prop = "LeftLongY", page = 1, col = 4, row = 8, decr = -1, incr = 1, min = 0, max = 31  },

    { ui = "ShirtColor1 (R): %s", prop = "ShirtColor1", subprop = "R", subprop_type = "COLOR", page = 2, col = 1, row = 1, decr = -1, incr = 1, min = 0, max = 255  },
    { ui = "ShirtColor1 (G): %s", prop = "ShirtColor1", subprop = "G", subprop_type = "COLOR", page = 2, col = 1, row = 2, decr = -1, incr = 1, min = 0, max = 255  },
    { ui = "ShirtColor1 (B): %s", prop = "ShirtColor1", subprop = "B", subprop_type = "COLOR", page = 2, col = 1, row = 3, decr = -1, incr = 1, min = 0, max = 255  },
    { ui = "ShirtColor2 (R): %s", prop = "ShirtColor2", subprop = "R", subprop_type = "COLOR", page = 2, col = 1, row = 4, decr = -1, incr = 1, min = 0, max = 255  },
    { ui = "ShirtColor2 (G): %s", prop = "ShirtColor2", subprop = "G", subprop_type = "COLOR", page = 2, col = 1, row = 5, decr = -1, incr = 1, min = 0, max = 255  },
    { ui = "ShirtColor2 (B): %s", prop = "ShirtColor2", subprop = "B", subprop_type = "COLOR", page = 2, col = 1, row = 6, decr = -1, incr = 1, min = 0, max = 255  },

    { ui = "UndershirtColor (R): %s", prop = "UndershirtColor", subprop = "R", subprop_type = "COLOR", page = 2, col = 2, row = 1, decr = -1, incr = 1, min = 0, max = 255  },
    { ui = "UndershirtColor (G): %s", prop = "UndershirtColor", subprop = "G", subprop_type = "COLOR", page = 2, col = 2, row = 2, decr = -1, incr = 1, min = 0, max = 255  },
    { ui = "UndershirtColor (B): %s", prop = "UndershirtColor", subprop = "B", subprop_type = "COLOR", page = 2, col = 2, row = 3, decr = -1, incr = 1, min = 0, max = 255  },

    { ui = "ShortsColor (R): %s", prop = "ShortsColor", subprop = "R", subprop_type = "COLOR", page = 2, col = 3, row = 1, decr = -1, incr = 1, min = 0, max = 255  },
    { ui = "ShortsColor (G): %s", prop = "ShortsColor", subprop = "G", subprop_type = "COLOR", page = 2, col = 3, row = 2, decr = -1, incr = 1, min = 0, max = 255  },
    { ui = "ShortsColor (B): %s", prop = "ShortsColor", subprop = "B", subprop_type = "COLOR", page = 2, col = 3, row = 3, decr = -1, incr = 1, min = 0, max = 255  },
    { ui = "SocksColor (R): %s", prop = "SocksColor", subprop = "R", subprop_type = "COLOR", page = 2, col = 3, row = 4, decr = -1, incr = 1, min = 0, max = 255  },
    { ui = "SocksColor (G): %s", prop = "SocksColor", subprop = "G", subprop_type = "COLOR", page = 2, col = 3, row = 5, decr = -1, incr = 1, min = 0, max = 255  },
    { ui = "SocksColor (B): %s", prop = "SocksColor", subprop = "B", subprop_type = "COLOR", page = 2, col = 3, row = 6, decr = -1, incr = 1, min = 0, max = 255  },

    { ui = "UniColor Color1 (R): %s", prop = "UniColor_Color1", subprop = "R", subprop_type = "COLOR", page = 2, col = 4, row = 1, decr = -1, incr = 1, min = 0, max = 255  },
    { ui = "UniColor Color1 (G): %s", prop = "UniColor_Color1", subprop = "G", subprop_type = "COLOR", page = 2, col = 4, row = 2, decr = -1, incr = 1, min = 0, max = 255  },
    { ui = "UniColor Color1 (B): %s", prop = "UniColor_Color1", subprop = "B", subprop_type = "COLOR", page = 2, col = 4, row = 3, decr = -1, incr = 1, min = 0, max = 255  },
    { ui = "UniColor Color2 (R): %s", prop = "UniColor_Color2", subprop = "R", subprop_type = "COLOR", page = 2, col = 4, row = 4, decr = -1, incr = 1, min = 0, max = 255  },
    { ui = "UniColor Color2 (G): %s", prop = "UniColor_Color2", subprop = "G", subprop_type = "COLOR", page = 2, col = 4, row = 5, decr = -1, incr = 1, min = 0, max = 255  },
    { ui = "UniColor Color2 (B): %s", prop = "UniColor_Color2", subprop = "B", subprop_type = "COLOR", page = 2, col = 4, row = 6, decr = -1, incr = 1, min = 0, max = 255  },

}
local ui_lines = {}

local grid_menu = {}
local grid_menu_rows, grid_menu_cols, grid_menu_pages
local menu_item_width = 29
local function get_ui_line_by_page_row_and_col(page, row, col)
    for i,v in ipairs(overlay_states) do
        if v.page == page and v.row == row and v.col == col then
            return v
        end
    end
end

local function get_grid_menu_params()
    local r, c, p = 1, 1, 1
    for i, v in pairs(overlay_states) do
        if v.col > c then
            c = v.col
        end
        if v.row > r then
            r = v.row
        end
        if v.page > p then
            p = v.page
        end
    end
    return r, c, p -- max values
end

local function fill_matrix(m, f)
    for i = 1, grid_menu_pages do
        m[i] = {}
        for j = 1, grid_menu_rows do
            m[i][j] = {}
            for k = 1, grid_menu_cols do
                m[i][j][k] = f
            end
        end
    end
end

local function RGB_parts(color_str)
    -- color_str should be formatted as "#RRGGBB"
    local parts = {}
    if color_str and color_str:sub(1, 1) == "#" and #color_str == 7 then
        parts["R"] = tonumber( "0x" .. color_str:sub(2, 3) )
        parts["G"] = tonumber( "0x" .. color_str:sub(4, 5) )
        parts["B"] = tonumber( "0x" .. color_str:sub(6, 7) )
    end
    return parts
end

local function get_subprop_colors(color_val, state)
    if state then
        if state.subprop_type and state.subprop_type == "COLOR" then
            local color_parts = RGB_parts(color_val)
            if tableLength(color_parts) > 0 then
                return color_parts
            end
        end
    end
end

local function update_subprop_colors(color_val, sub_color_val, state)
    local final_color = color_val -- string #RRGGBB
    if state then
        if state.subprop_type and state.subprop_type == "COLOR" then
            local hex_subcolor = string.format("%02X",sub_color_val)
            -- log("hex subcolor:: " .. state.subprop .. ": " .. hex_subcolor)
            if state.subprop == "R" then
                final_color = "#" .. hex_subcolor .. final_color:sub(4,7)
                -- log("final color (change red: ): " .. final_color)
            elseif state.subprop == "G" then
                final_color = "#" .. final_color:sub(2,3) .. hex_subcolor .. final_color:sub(6,7)
                -- log("final color (change green: ): " .. final_color)
            elseif state.subprop == "B" then
                final_color = "#" .. final_color:sub(2,5) .. hex_subcolor
                -- log("final color (change blue: ): " .. final_color)
            end
        end
    end
    return final_color
end

local function first_overlay_state_on_page(page)
    for i, val in pairs(overlay_states) do
        if val.page == page and val.row == 1 and val.col == 1 then
            return i
        end
    end
end

local function update_menu_selection()
    -- highlight the currently selected property and expand them all to equal width (menu_item_width)
    local curr_sel_prop = overlay_states[overlay_curr]
    for i, page in pairs(grid_menu) do
        for j, row in pairs(page) do
            for k, val in pairs(row) do
                -- ugly attempt to compare equality of e.g. "Chest number size: %d" and "Chest number size: 26" until the ocurrence of ":"
                if val:find(":") and curr_sel_prop.ui:find(":") and val:sub(1,val:find(":")-1) == curr_sel_prop.ui:sub(1,curr_sel_prop.ui:find(":")-1) then
                    grid_menu[i][j][k] = string.format("--> %s <--", pad_to_numchars(val, menu_item_width))
                else
                    grid_menu[i][j][k] = string.format("    %s    ", pad_to_numchars(val, menu_item_width))
                end
            end
        end
    end
end

local function build_grid_menu(team_id, kit_path, cfg)
    grid_menu = {}
    fill_matrix(grid_menu, pad_to_numchars(" ", menu_item_width))
    for i, v in pairs(overlay_states) do -- loop through flat properties list ...
        local row, col = v.row, v.col
        for grid_page = 1, grid_menu_pages do
            for grid_row = 1, grid_menu_rows do
                for grid_column = 1, grid_menu_cols do
                    local ui_line = get_ui_line_by_page_row_and_col(grid_page, grid_row, grid_column)
                    if ui_line then
                        local curr_cfg = cfg and cfg or configEd_settings[team_id][kit_path]
                        -- local prop_configEd_val = configEd_settings[team_id][kit_path][ui_line.prop]
                        local prop_configEd_val = curr_cfg[ui_line.prop]
                        if ui_line.keys then
                            local inv_keys = tableInvert(ui_line.keys)
                            prop_configEd_val = inv_keys[prop_configEd_val]
                        end
                        if ui_line.subprop and ui_line.subprop_type == "COLOR" then
                            local color_parts = RGB_parts(prop_configEd_val)
                            local subcolor_val = color_parts[ui_line.subprop]
                            prop_configEd_val = subcolor_val
                        end
                        grid_menu[grid_page][grid_row][grid_column] = string.format(ui_line.ui, prop_configEd_val)
                    end
                end
            end
        end
    end
    update_menu_selection()
    -- for i, v in pairs(grid_menu) do
    --  log("build_grid_menu:: gm_line: " .. t2s(v))
    -- end
end

local function KitConfigEditor_get_settings(team_id, kit_path, kit_info)
    -- log(string.format("Into KitConfigEditor_get_settings (%s, %s, %s) ... ", team_id, kit_path, kit_info))
    if kit_path then
        configEd_settings[team_id] = configEd_settings[team_id] or {}
        configEd_settings[team_id][kit_path] = {}
        for name, value in pairs(kit_info) do
            if name and name ~= "CompKit" and value and not configEd_settings[team_id][kit_path][name] then -- do not repeatedly overwrite color properties that will use subprops
                value = tonumber(value) or value:gsub("%s+", "") -- strip trailing whitespaces, if it is a string ...
                configEd_settings[team_id][kit_path][name] = value
            end
        end
        -- log(string.format("... loaded kit config editor state: %s", t2s(configEd_settings[team_id][kit_path])))
    end
end

-- end kit config editor part ...

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

local function get_away_kit_path_for(kit_id, is_gk)
    if not kit_id then
        return
    end
    local ord = is_gk and away_gk_loaded_for[kit_id] or away_loaded_for[kit_id]
    local kits = is_gk and away_gk_kits or away_kits
    local kit_path = kits and kits[ord] and kits[ord][1]
    kit_path = kit_path or (is_gk and standard_gk_kits[kit_id+1] or standard_kits[kit_id+1])
    return kit_path
end

local function is_edit_mode(ctx)
    -- sorta works now, but probably needs to be more robust
    local home_team_id = ctx.kits.get_current_team(0)
    local away_team_id = ctx.kits.get_current_team(1)
    return home_team_id ~= 0x1ffff and away_team_id == 0x1ffff
end

-- end kit config editor part ...

local function load_map(filename)
    local map = {}
    for line in io.lines(filename) do
        -- strip comment
        line = string.gsub(line, "#.*", "")
        local tid, path = string.match(line, "%s*(%d+)%s*,%s*[\"]?([^\"]*)")
        tid = tonumber(tid)
        if tid and path then
            map[tid] = path
            log(string.format("tid: %d ==> content path: %s", tid, path))
        end
    end
    return map
end

local function load_compmap(filename)
    local map = {}
    for line in io.lines(filename) do
        -- strip comment
        line = string.gsub(line, "#.*", "")
        -- allow only ONE word - alphanumerics, underscore and hyphen -- is there better pattern to do that?
        local tid, path = string.match(line, "%s*(%d+)%s*,%s*([%w_-]*)%s*")
        tid = tonumber(tid)
        if tid and path then
            map[tid] = path
            log(string.format("comp id: %d ==> content prefix: %s", tid, path))
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
        key, value = string.match(line, "%s*([%w_]+)%s*=%s*[\"]?([^\"]*)")
        -- strip trailing space from value
        value = value and string.gsub(value, "%s*$", "") or nil
        -- convert to number of we can
        value = tonumber(value) or value
        if key and value then
            cfg[key] = value
        end
        -- store original structure
        cfg_org[#cfg_org + 1] = { line, comment, key, value }
    end
    return cfg, cfg_org
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
            if comment ~= "" then
                s = pad_to_numchars(s, 50)
            end
            f:write(string.format("%s%s\n", s, comment))
            cfg_dup[key] = nil
        end
    end
    -- write remaining (new) key/value pairs, if any left
    -- but, do not save the CompKit flag ...
    if cfg_dup['CompKit'] then
        cfg_dup['CompKit'] = nil
        -- log("CompKit flag removed while saving config ...")
    end
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

local function get_all_order_files_for_team(path, is_gk)
    local all_order_files = is_gk == true and {"\\gk_order.txt"} or {"\\order.txt"}  -- generic one is always assumed to be there ...
    local inverted_compmap = tableInvert(compmap) -- eliminates duplicated prefix values as a side-effect (e.g. "ucl" remains only once), id's are actualy not needed here
    -- log("compmap: " .. t2s(compmap))
    -- log("inverted compmap: " .. t2s(tableInvert(compmap)))
    for comp_prefix, comp_id in pairs(inverted_compmap) do
        local order_file = string.format("\\%s_order.txt", string.format("%s%s", comp_prefix, is_gk == true and "_gk" or "") )
        local f = io.open(kroot .. path .. order_file)
        if f then
            f:close()
            table.insert(all_order_files, #all_order_files+1, order_file) -- append at the end of the table
        end
    end
    return all_order_files
end

local function load_collections(path, orderfile, collection_name)
    local filename = kroot .. path .. "\\" .. orderfile
    local f = io.open(filename)
    if f then
        f:close()
        local t = {}
        local collection = "default"
        for line in io.lines(filename) do
            -- strip BOF
            line = string.gsub(line, "^\xef\xbb\xbf", "")
            -- strip comments
            line = string.gsub(line, ";.*", "")
            line = string.gsub(line, "#.*", "")
            -- get string value
            line = string.match(line, "%s*([^%s]+)%s*")
            if line then
                local new_collection = string.match(line, "%[([^%]]+)%]")
                if new_collection then
                    collection = new_collection
                else
                    -- only load sections that were asked for
                    if collection_name == nil or collection_name == collection then
                        local filename = kroot .. path .. "\\" .. line .. "\\config.txt"
                        local cfg, cfg_org = load_config(filename)
                        if cfg then
                            -- part oh the badge handling routine:
                            -- let's tag this config as competition-specific if it is not part of default collection
                            if collection ~= "default" then
                                cfg.CompKit = true
                                -- log("kit " .. t2s(cfg) .. " tagged as CompKit.")
                            end
                            t[#t + 1] = { line, cfg, cfg_org }
                        else
                            log("WARNING: unable to load kit config from: " .. filename)
                        end
                    end
                end
            end
        end
        return #t>0 and t or nil
    end
end

local function load_configs_for_team(ctx, team_id)
    -- check if team is licensed
    local has_kit = ctx.kits.get(team_id, 0)
    if not has_kit then
        log(string.format("we have kitserver kits for: %s, but the team is unlicensed. Disabling kits.", team_id))
        return nil, nil
    end

    -- ctx added for comp_id retrieval
    local path = kmap[team_id]

    local comp_id = ctx.tournament_id and ctx.tournament_id or nil
    local comp_prefix = compmap[comp_id]

    if not path then
        -- no kits for this team
        log(string.format("no kitserver kits for: %s", team_id))
        return nil, nil
    end
    log(string.format("looking for configs for: %s", path))

    if is_edit_mode(ctx) or (comp_id and comp_id == 65535)  then
        -- in edit mode we have to be able to cycle through ALL kits - the ones from generic order.txt and from all the possible competition-specific .txt's
        -- (e.g. for Liverpool - they could easily have at least two competition-specific kits - for UCL and FA cup)

        -- the same principle might apply to exhibition mode too? what harm could we create if we "merge" all order files togehter and enable ...
        -- ... using all the possible kits in exhibition mode? Regular ones and comp-specific? To give that "full manual" selection choice?
        -- Some badge handling would be required (dummy badges that replace official ones), but that's also on TO-DO list

        -- players
        local pt = load_collections(path, "order.ini")
        log(string.format("%s mode:: all player kits: ", is_edit_mode(ctx) and "edit" or "exhibition") .. t2s(pt))

        -- goalkeepers
        local gt = load_collections(path, "gk_order.ini")
        log(string.format("%s mode:: all gk kits: ", is_edit_mode(ctx) and "edit" or "exhibition") .. t2s(gt))

        return pt, gt
    else -- pre-match menus in non-exhibition modes? hopefully, this is reliable enough
        -- only two possible order files - either generic one or the competition specific one (determined by comp_id)

        -- players
        local pt = load_collections(path, "order.ini", comp_prefix or "default")
        if not pt then
            pt  = load_collections(path, "order.ini", "default")
        end
        log("not edit/exhibition mode:: all player kits: " .. t2s(pt))

        -- goalkeepers
        local gt = load_collections(path, "gk_order.ini", comp_prefix or "default")
        if not gt then
            gt = load_collections(path, "gk_order.ini", "default")
        end
        log("not edit/exhibition mode:: all gk kits: " .. t2s(gt))

        return pt, gt
    end
end

local function get_curr_kit(ctx, team_id, home_or_away)
    local kit_id = ctx.kits.get_current_kit_id(home_or_away)
    if home_or_away == 0 then
        local idx = home_loaded_for[kit_id]
        if idx and home_kits then
            return home_kits[idx]
        end
    else
        local idx = away_loaded_for[kit_id]
        if idx and away_kits then
            return away_kits[idx]
        end
    end
end

local function get_curr_gk_kit(ctx, team_id, home_or_away)
    if home_or_away == 0 then
        local idx = home_gk_loaded_for[0]
        if idx and home_gk_kits then
            return home_gk_kits[idx]
        end
    else
        local idx = away_gk_loaded_for[0]
        if idx and away_gk_kits then
            return away_gk_kits[idx]
        end
    end
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
    home_kits, home_gk_kits = load_configs_for_team(ctx, ctx.home_team)
    home_next_kit = home_kits and #home_kits>0 and 0 or nil
    home_next_gk_kit = home_gk_kits and #home_gk_kits>0 and 0 or nil
    log(string.format("prepped home kits for: %s", ctx.home_team))
end

local function prep_away_team(ctx)
    -- see what kits are available
    away_kits, away_gk_kits = load_configs_for_team(ctx, ctx.away_team)
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
                    kfile_remap[string.format("Asset\\model\\character\\uniform\\texture\\#windx11\\%s.ftex", fkey)] = pathname
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
    -- trick: for CompKits move the badge out of the way
    if cfg.CompKit then
        cfg.LeftShortY = 31
        cfg.LeftLongY = 31
        cfg.RightShortY = 31
        cfg.RightLongY = 31
    end
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
    -- trick: for CompKits move the badge out of the way
    if cfg.CompKit then
        cfg.LeftShortY = 31
        cfg.LeftLongY = 31
        cfg.RightShortY = 31
        cfg.RightLongY = 31
    end
end

local function reset_match(ctx)
    home_loaded_for = {}
    home_gk_loaded_for = {}
    away_loaded_for = {}
    away_gk_loaded_for = {}

    was_p_home = nil
    was_p_away = nil
    is_gk_mode = false -- always start in Players mode

    prep_home_team(ctx)
    prep_away_team(ctx)
end

local function init_home_team_kits(ctx, team_id, skip_shirt_colors, init_config_editor)
    if home_kits and #home_kits>0 then
        for i,ki in ipairs(home_kits) do
            local org_cfg = ctx.kits.get(team_id, i-1)
            log(string.format("i=%d, org_cfg=%s", i, org_cfg))
            if org_cfg then -- check if we can go this far in list of kits
                local cfg = table_copy(ki[2])
                update_kit_config(team_id, i, ki[1], cfg)
                local radar_flag = (not skip_shirt_colors) and 0 or nil
                ctx.kits.set(team_id, i-1, cfg, radar_flag)
                home_loaded_for[i-1] = i
                if init_config_editor then
                    --
                    KitConfigEditor_get_settings(team_id, ki[1], cfg)
                    --
                end
            end
        end
        home_next_kit = 1
    end
    if home_gk_kits and #home_gk_kits>0 then
        local ki = home_gk_kits[1]
        local cfg = table_copy(ki[2])
        update_gk_kit_config(team_id, 1, ki[1], cfg)
        ctx.kits.set_gk(team_id, cfg)
        home_gk_loaded_for[0] = 1
        if init_config_editor then
            --
            KitConfigEditor_get_settings(team_id, ki[1], cfg)
            --
        end
        home_next_gk_kit = 1
    end
end

local function init_away_team_kits(ctx, team_id)
    if away_kits and #away_kits>0 then
        for i,ki in ipairs(away_kits) do
            local org_cfg = ctx.kits.get(team_id, i-1)
            log(string.format("i=%d, org_cfg=%s", i, org_cfg))
            if org_cfg then -- check if we can go this far in list of kits
                local cfg = table_copy(ki[2])
                update_kit_config(team_id, i, ki[1], cfg)
                ctx.kits.set(team_id, i-1, cfg, 1)
                away_loaded_for[i-1] = i
            end
        end
        away_next_kit = 1
    end
    if away_gk_kits and #away_gk_kits>0 then
        local ki = away_gk_kits[1]
        local cfg = table_copy(ki[2])
        update_gk_kit_config(team_id, 1, ki[1], cfg)
        ctx.kits.set_gk(team_id, cfg)
        away_gk_loaded_for[0] = 1
        away_next_gk_kit = 1
    end
end

function m.set_teams(ctx, home, away)
    reset_match(ctx)
    init_home_team_kits(ctx, home)
    init_away_team_kits(ctx, away)
end

function m.set_home_team_for_kits(ctx, team_id, edit_mode)
    log(string.format("set_home_team_for_kits CALLED with %s,%s", team_id, edit_mode))
    if edit_mode == 1 then
        -- keep track
        ctx.home_team = team_id
        _team_id = team_id

        -- clear state
        reset_match(ctx)
        config_editor_on = false

        -- apply GDB kits for the team
        local skip_shirt_colors = true
        local init_config_editor = true
        init_home_team_kits(ctx, team_id, skip_shirt_colors, init_config_editor)
    end
end

function m.set_kits(ctx, home_info, away_info)
    log(string.format("set_kits: home_info (team=%d): %s", ctx.home_team, t2s(home_info)))
    log(string.format("set_kits: away_info (team=%d): %s", ctx.away_team, t2s(away_info)))
    --dump_kit_config(string.format("%s%d-%s-config.txt", ctx.sider_dir, ctx.home_team, home_info.kit_id), home_info)
    --dump_kit_config(string.format("%s%d-%s-config.txt", ctx.sider_dir, ctx.away_team, away_info.kit_id), away_info)

    if home_kits and #home_kits > 0 then
        home_next_kit = ctx.kits.get_current_kit_id(0) + 1
    end
    if away_kits and #away_kits > 0 then
        away_next_kit = ctx.kits.get_current_kit_id(1) + 1
    end
end

function m.make_key(ctx, filename)
    --log("wants: " .. filename)
    local key = kfile_remap[filename]
    if key then
        --log(string.format("mapped: {%s} ==> {%s}", filename, key))
        return key
    end
end

function m.get_filepath(ctx, filename, key)
    if key then
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
        compmap = load_compmap(kroot .. "\\map_comp.txt")
        log("Reloaded competition map from: " .. kroot .. "\\map_comp.txt")

    elseif vkey == 0x32 then
        if is_edit_mode(ctx) then
            config_editor_on = not config_editor_on
            if config_editor_on then
                -- curr_col = 1 -- for compact edit menu ...
                local team_id = ctx.kits.get_current_team(0)
                if team_id and team_id ~= 0x1ffff then
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
                        build_grid_menu(team_id, curr[1])
                        -- end kit config editor part ...
                    end
                end
            end
        end

    elseif not is_edit_mode(ctx) and vkey == 0x39 then -- player/goalkeeper mode toggle
        if is_gk_mode then
            -- try to switch to players mode
            -- home: update cfg
            local switched_home
            local home_kit_id = ctx.kits.get_current_kit_id(0)
            if home_kits and #home_kits > 0 then
                local idx = home_loaded_for[home_kit_id]
                local curr = idx and home_kits[idx] or nil
                log(string.format("PL home: %s", curr))
                if curr and curr[2] then
                    local cfg = table_copy(curr[2])
                    update_kit_config(ctx.home_team, idx, curr[1], cfg)
                    -- trigger refresh
                    ctx.kits.set(ctx.home_team, home_kit_id, cfg, 0)
                    ctx.kits.refresh(0)
                    is_gk_mode = false
                    switched_home = true
                end
            end
            if not switched_home and was_p_home then
                -- fallback when we didn't have a player GDB kit
                ctx.kits.set(ctx.home_team, home_kit_id, was_p_home, 0)
                ctx.kits.refresh(0)
                is_gk_mode = false
            end
            -- away: update cfg
            local switched_away
            local away_kit_id = ctx.kits.get_current_kit_id(1)
            if away_kits and #away_kits > 0 then
                local idx = away_loaded_for[away_kit_id]
                local curr = idx and away_kits[idx] or nil
                log(string.format("PL away: %s", curr))
                if curr and curr[2] then
                    local cfg = table_copy(curr[2])
                    update_kit_config(ctx.away_team, idx, curr[1], cfg)
                    -- trigger refresh
                    ctx.kits.set(ctx.away_team, away_kit_id, cfg, 1)
                    ctx.kits.refresh(1)
                    is_gk_mode = false
                    switched_away = true
                end
            end
            if not switched_away and was_p_away then
                -- fallback when we didn't have a player GDB kit
                ctx.kits.set(ctx.away_team, away_kit_id, was_p_away, 1)
                ctx.kits.refresh(1)
                is_gk_mode = false
            end
        else
            -- try to switch to goalkeepers mode
            -- home: update cfg
            if home_gk_kits and #home_gk_kits > 0 then
                local curr = home_gk_kits[home_next_gk_kit]
                log(string.format("GK home: %s", curr))
                if curr and curr[2] then
                    -- we have a home GK kit
                    local cfg = table_copy(curr[2])
                    update_gk_kit_config(ctx.home_team, home_next_gk_kit, curr[1], cfg)
                    -- update kit
                    ctx.kits.set_gk(ctx.home_team, cfg)
                    -- trigger refresh
                    local home_kit_id = ctx.kits.get_current_kit_id(0)
                    was_p_home = ctx.kits.get(ctx.home_team, home_kit_id)
                    ctx.kits.set(ctx.home_team, home_kit_id, cfg)
                    ctx.kits.refresh(0)
                    is_gk_mode = true
                end
            end
            -- away: update cfg
            if away_gk_kits and #away_gk_kits > 0 then
                local curr = away_gk_kits[away_next_gk_kit]
                log(string.format("GK away: %s", curr))
                if curr and curr[2] then
                    -- we have an away GK kit
                    local cfg = table_copy(curr[2])
                    update_gk_kit_config(ctx.away_team, away_next_gk_kit, curr[1], cfg)
                    -- update kit
                    ctx.kits.set_gk(ctx.away_team, cfg)
                    -- trigger refresh
                    local away_kit_id = ctx.kits.get_current_kit_id(1)
                    was_p_away = ctx.kits.get(ctx.away_team, away_kit_id)
                    ctx.kits.set(ctx.away_team, away_kit_id, cfg)
                    ctx.kits.refresh(1)
                    is_gk_mode = true
                end
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
                local radar_flag = (not is_edit_mode(ctx)) and 0 or nil
                ctx.kits.set(ctx.home_team, kit_id, cfg, radar_flag)
                ctx.kits.refresh(0)
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
                away_loaded_for[kit_id] = away_next_kit
                ctx.kits.set(ctx.away_team, kit_id, cfg, 1)
                ctx.kits.refresh(1)
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
                away_gk_loaded_for[0] = away_next_gk_kit
                ctx.kits.set(ctx.away_team, kit_id, cfg)
                ctx.kits.refresh(1)
            end
        end
    elseif config_editor_on and vkey == NEXT_PROP_KEY then
        if overlay_curr < #overlay_states and overlay_states[overlay_curr].page == overlay_states[overlay_curr+1].page then
            overlay_curr = overlay_curr + 1

            -- could this be somehow shortened? easier way to get team_id and curr for the final build_grid_menu(team_id, curr[1]) call?
            local team_id = ctx.kits.get_current_team(0)
            if team_id and team_id ~= 0x1ffff then
                local kit_id, is_gk = ctx.kits.get_current_kit_id(0)
                local kit_ord = get_home_kit_ord_for(kit_id, is_gk)
                local kits = is_gk and home_gk_kits or home_kits
                if kit_ord then
                    local curr = kits[kit_ord]
                    build_grid_menu(team_id, curr[1])
                end
            end
        end
    elseif config_editor_on and vkey == PREV_PROP_KEY then
        if overlay_curr > 1 and overlay_states[overlay_curr].page == overlay_states[overlay_curr-1].page then
            overlay_curr = overlay_curr - 1

            -- could this be somehow shortened? easier way to get team_id and curr for the final build_grid_menu(team_id, curr[1]) call?
            local team_id = ctx.kits.get_current_team(0)
            if team_id and team_id ~= 0x1ffff then
                local kit_id, is_gk = ctx.kits.get_current_kit_id(0)
                local kit_ord = get_home_kit_ord_for(kit_id, is_gk)
                local kits = is_gk and home_gk_kits or home_kits
                if kit_ord then
                    local curr = kits[kit_ord]
                    build_grid_menu(team_id, curr[1])
                end
            end
        end

    elseif config_editor_on and vkey == NEXT_VALUE_KEY then
        local s = overlay_states[overlay_curr]
        local kit_id, is_gk = ctx.kits.get_current_kit_id(0)
        local kit_ord = get_home_kit_ord_for(kit_id, is_gk)
        local kits = is_gk and home_gk_kits or home_kits
        local update = is_gk and update_gk_kit_config or update_kit_config
        if kit_ord then
            local curr = kits[kit_ord]
            -- log(string.format("curr: %s, %s", curr[1], t2s(curr[2])))
            local team_id = ctx.kits.get_current_team(0)
            if s.incr ~= nil and team_id then
                if s.subprop and s.subprop_type == "COLOR" then
                    local curr_color = configEd_settings[team_id][curr[1]][s.prop]
                    -- extract current sub-color from color string
                    local subprop_colors = get_subprop_colors(curr_color, s)
                    local curr_sub_color = subprop_colors[s.subprop] -- s.subprop used as key is either "R" or "G" or "B"
                    -- increase current sub-color
                    curr_sub_color = math.min(curr_sub_color + s.incr, s.max)
                    -- combine increased sub-color with other two color parts
                    local new_color = update_subprop_colors(curr_color, curr_sub_color, s)
                    configEd_settings[team_id][curr[1]][s.prop] = new_color
                else
                    configEd_settings[team_id][curr[1]][s.prop] = math.min(configEd_settings[team_id][curr[1]][s.prop] + s.incr, s.max)
                end
                local cfg = table_copy(configEd_settings[team_id][curr[1]])
                --update(team_id, kit_ord, curr[1], cfg)
                apply_changes(team_id, kits[kit_ord], cfg, false)
                build_grid_menu(team_id, curr[1])
            elseif s.nextf ~= nil and team_id then
                local curr_disp_val = tableInvert(s.keys)[configEd_settings[team_id][curr[1]][s.prop]]
                -- log("curr_disp_val: " .. curr_disp_val)
                local disp_val, conf_val = s.nextf(s.keys, s.vals, curr_disp_val)
                -- log("disp_val (next): " .. disp_val .. " conf_val (next): " .. conf_val)
                configEd_settings[team_id][curr[1]][s.prop] = conf_val
                local cfg = table_copy(configEd_settings[team_id][curr[1]])
                --update(team_id, kit_ord, curr[1], cfg)
                apply_changes(team_id, kits[kit_ord], cfg, false)
                build_grid_menu(team_id, curr[1])
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
            -- log(string.format("curr: %s, %s", curr[1], t2s(curr[2])))
            local team_id = ctx.kits.get_current_team(0)
            if s.decr ~= nil and team_id then
                -- configEd_settings[team_id][curr[1]][s.prop] = math.max(s.min, configEd_settings[team_id][curr[1]][s.prop] + s.decr)
                if s.subprop and s.subprop_type == "COLOR" then
                    local curr_color = configEd_settings[team_id][curr[1]][s.prop]
                    -- extract current sub-color from color string
                    local subprop_colors = get_subprop_colors(curr_color, s)
                    local curr_sub_color = subprop_colors[s.subprop] -- s.subprop used as key is either "R" or "G" or "B"
                    -- decrease current sub-color
                    curr_sub_color = math.max(s.min, curr_sub_color + s.decr)
                    -- combine decreased sub-color with other two color parts
                    local new_color = update_subprop_colors(curr_color, curr_sub_color, s)
                    configEd_settings[team_id][curr[1]][s.prop] = new_color
                else
                    configEd_settings[team_id][curr[1]][s.prop] = math.max(s.min, configEd_settings[team_id][curr[1]][s.prop] + s.decr)
                end
                local cfg = table_copy(configEd_settings[team_id][curr[1]])
                --update(team_id, kit_ord, curr[1], cfg)
                apply_changes(team_id, kits[kit_ord], cfg, false)
                build_grid_menu(team_id, curr[1])
            elseif s.prevf ~= nil and team_id then
                local curr_disp_val = tableInvert(s.keys)[configEd_settings[team_id][curr[1]][s.prop]]
                -- log("curr_disp_val: " .. curr_disp_val)
                local disp_val, conf_val = s.prevf(s.keys, s.vals, curr_disp_val)
                -- log("disp_val (prev): " .. disp_val .. " conf_val (prev): " .. conf_val)
                configEd_settings[team_id][curr[1]][s.prop] = conf_val
                local cfg = table_copy(configEd_settings[team_id][curr[1]])
                --update(team_id, kit_ord, curr[1], cfg)
                apply_changes(team_id, kits[kit_ord], cfg, false)
                build_grid_menu(team_id, curr[1])
            end
        end
    elseif config_editor_on and vkey == SWITCH_MENU_PAGE then
        overlay_page = (overlay_page % grid_menu_pages) + 1

        overlay_curr = first_overlay_state_on_page(overlay_page)
        if not overlay_curr then
            overlay_curr = 1
        end
    end
end

function m.finalize_kits(ctx)
    log("finalizing kits ...")
    is_gk_mode = false
    -- goalkeepers
    if home_gk_kits and #home_gk_kits > 0 then
        local curr = home_gk_kits[home_next_gk_kit]
        if curr then
            local cfg = table_copy(curr[2])
            update_gk_kit_config(ctx.home_team, home_next_gk_kit, curr[1], cfg)
            ctx.kits.set_gk(ctx.home_team, cfg)
        end
    end
    if away_gk_kits and #away_gk_kits > 0 then
        local curr = away_gk_kits[away_next_gk_kit]
        if curr then
            local cfg = table_copy(curr[2])
            update_gk_kit_config(ctx.away_team, away_next_gk_kit, curr[1], cfg)
            ctx.kits.set_gk(ctx.away_team, cfg)
        end
    end
    -- players
    local set_home
    local kit_id = ctx.kits.get_current_kit_id(0)
    if home_kits and #home_kits > 0 then
        local idx = home_loaded_for[kit_id]
        local curr = idx and home_kits[idx] or nil
        if curr then
            local cfg = table_copy(curr[2])
            update_kit_config(ctx.home_team, idx, curr[1], cfg)
            ctx.kits.set(ctx.home_team, kit_id, cfg, 0)
            set_home = true
        end
    end
    if not set_home and was_p_home then
        -- fallback
        ctx.kits.set(ctx.home_team, kit_id, was_p_home, 0)
    end
    local set_away
    local kit_id = ctx.kits.get_current_kit_id(1)
    if away_kits and #away_kits > 0 then
        local idx = away_loaded_for[kit_id]
        local curr = idx and away_kits[idx] or nil
        if curr then
            local cfg = table_copy(curr[2])
            update_kit_config(ctx.away_team, idx, curr[1], cfg)
            ctx.kits.set(ctx.away_team, kit_id, cfg, 1)
            set_away = true
        end
    end
    if not set_away and was_p_away then
        -- fallback
        ctx.kits.set(ctx.away_team, kit_id, was_p_away, 1)
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
        return "" -- we're here on screen before the "Strip" menu
    end

    local kit_ord = get_home_kit_ord_for(kit_id, is_gk)
    if not kit_ord then
        -- we don't have a GDB kit to edit
        return "\n\n\n\tCannot find config file for this kit (1)."
    end

    local team_id = ctx.kits.get_current_team(0)
    local kits = is_gk and home_gk_kits or home_kits
    if not kits then
        return "\n\n\n\tCannot find config file for this kit (2)."
        --return ""
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

        -- ADDED TO RESPOND TO UP/DOWN movements in Strip menu - to update overlay
        local cfg = table_copy(curr[2])
        -- KitConfigEditor_get_settings(team_id, curr[1], cfg) -- get current kit data for configEd overlay - may be called way too often, but for the moment, I don't know how to reliably call this only once, when user goes one choice up/down in Strip menu
        -- previous line MOVED TO new "set_home_team_for_kits" event - seems like a perfect place to make ONLY ONE update of displayed menu values, exactly when user goes up/down in "Strip" menu :)
        build_grid_menu(team_id, curr[1], cfg) -- optional 3rd parameter used here
        -- .. HOPEFULLY, it won't cause troubles elsewhere

        ui_lines = {}
        for i, row in pairs(grid_menu[overlay_page]) do
            table.insert(ui_lines, tableLength(ui_lines)+1, "\n" .. table.concat(row))
            -- log("row: " .. table.concat(row))
        end

        return string.format([[

     Kit Config live editor - Menu page %d of %d
     Keys: [PgUp][PgDn] - choose setting, [-][+] - modify value
     %s]], overlay_page, grid_menu_pages, table.concat(ui_lines))

    else
        -- log("In get_overlay_states: configEd_settings is nul or empty!! ")
    end
    return ""
end
-- end kit config editor part ...

function m.overlay_on(ctx)
    if is_edit_mode(ctx) then
        _kit_id, _is_gk = ctx.kits.get_current_kit_id(0)
        return string.format("team:%s, kit:%s | [2] - Editor (%s), [3] - Next menu page, [6] - switch kit, [0] - reload map"
                -- kit config editor part ...
                .. "\n" ..
                get_configEd_overlay_states(ctx),
                -- end kit config editor part ...
                _team_id, get_home_kit_path_for(_kit_id, _is_gk),
                config_editor_on and "ON" or "OFF")
    elseif ctx.home_team and ctx.away_team and ctx.home_team ~=  0x1ffff and ctx.away_team ~= 0x1ffff then
        local hkid = ctx.kits.get_current_kit_id(0)
        local akid = ctx.kits.get_current_kit_id(1)
        local hk = get_home_kit_path_for(hkid, is_gk_mode)
        local ak = get_away_kit_path_for(akid, is_gk_mode)
        return string.format("%s | %s:%s vs %s:%s | [6][7] - switch kits, [9] - PL/GK, [0] - reload map",
            modes[is_gk_mode and 2 or 1], ctx.home_team, hk, ctx.away_team, ak)
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
    compmap = load_compmap(kroot .. "\\map_comp.txt")
    ctx.register("overlay_on", m.overlay_on)
    ctx.register("key_down", m.key_down)
    ctx.register("key_up", m.key_up)
    ctx.register("set_teams", m.set_teams)
    ctx.register("set_kits", m.set_kits)
    ctx.register("set_home_team_for_kits", m.set_home_team_for_kits)
    ctx.register("after_set_conditions", m.finalize_kits)
    ctx.register("livecpk_make_key", m.make_key)
    ctx.register("livecpk_get_filepath", m.get_filepath)

    grid_menu_rows, grid_menu_cols, grid_menu_pages = get_grid_menu_params()
end

return m
