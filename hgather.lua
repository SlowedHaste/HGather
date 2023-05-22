--[[
* Goal of this addon is to build on hgather, adding configurable elements
* and eventually extending support to other HELM activities
*
* Used atom0s equipmon as a base for the config elements of this addon
* https://ashitaxi.com/';
--]]

addon.name      = 'hgather';
addon.author    = 'Hastega';
addon.version   = '1.4';
addon.desc      = 'General purpose gathering tracker.';
addon.link      = 'https://github.com/SlowedHaste/HGather';
addon.commands  = {'/hgather'};

require('common');
local chat      = require('chat');
local d3d       = require('d3d8');
local ffi       = require('ffi');
local fonts     = require('fonts');
local imgui     = require('imgui');
local prims     = require('primitives');
local scaling   = require('scaling');
local settings  = require('settings');
local data      = require('constants');

local C = ffi.C;
local d3d8dev = d3d.get_device();

-- Default Settings
local default_settings = T{
    visible = T{ true, },
    moon_display = T{ true, },
    display_timeout = T{ 600 },
    opacity = T{ 1.0, },
    padding = T{ 1.0, },
    scale = T{ 1.0, },
    item_index = ItemIndex,
    font_scale = T{ 1.0 },
    x = T{ 100, },
    y = T{ 100, },

    -- Choco Digging Display Settings
    digging = T{ 
        gysahl_cost = T{ 62 },
        gysahl_subtract = T{ false, },
        skillup_display = T{ true, },
    },
    reset_on_load = T{ false },
    first_attempt = 0,
    rewards = T{ },
    -- Save dig items/tries across sessions for fatigue tracking
    dig_items = 0,
    dig_tries = 0,
};

-- HGather Variables
local hgather = T{
    settings = settings.load(default_settings),

    -- HGather movement variables..
    move = T{
        dragging = false,
        drag_x = 0,
        drag_y = 0,
        shift_down = false,
    },

    -- Editor variables..
    editor = T{
        is_open = T{ false, },
    },

    is_attempt = false,
    last_attempt = ashita.time.clock()['ms'],
    -- digging_rewards = { },
    pricing = T{ },
    gil_per_hour = 0,

    digging = T{
        dig_timing = { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
        dig_index = 1,
        dig_per_minute = 0,
        dig_skillup = 0.0,
    },
};

--[[
* Renders the HGather settings editor.
--]]
local function render_editor()
    if (not hgather.editor.is_open[1]) then
        return;
    end

    imgui.SetNextWindowSize({ 500, 600, });
    imgui.SetNextWindowSizeConstraints({ 500, 600, }, { FLT_MAX, FLT_MAX, });
    if (imgui.Begin('HGather##Config', hgather.editor.is_open)) then

        -- imgui.SameLine();
        if (imgui.Button('Save Settings')) then
            settings.save();
            print(chat.header(addon.name):append(chat.message('Settings saved.')));
        end
        imgui.SameLine();
        if (imgui.Button('Reload Settings')) then
            settings.reload();
            print(chat.header(addon.name):append(chat.message('Settings reloaded.')));
        end
        imgui.SameLine();
        if (imgui.Button('Reset Settings')) then
            settings.reset();
            print(chat.header(addon.name):append(chat.message('Settings reset to defaults.')));
        end
        if (imgui.Button('Update Pricing')) then
            update_pricing();
            print(chat.header(addon.name):append(chat.message('Pricing updated.')));
        end
        imgui.SameLine();
        if (imgui.Button('Clear Session')) then
            clear_rewards();
            print(chat.header(addon.name):append(chat.message('Cleared hgather rewards.')));
        end

        imgui.Separator();

        if (imgui.BeginTabBar('##hgather_tabbar', ImGuiTabBarFlags_NoCloseWithMiddleMouseButton)) then
            if (imgui.BeginTabItem('General', nil)) then
                render_general_config(settings);
                imgui.EndTabItem();
            end
            if (imgui.BeginTabItem('Items', nil)) then
                render_items_config(settings);
                imgui.EndTabItem();
            end
            imgui.EndTabBar();
        end

    end
    imgui.End();
end

function render_general_config(settings)
    imgui.Text('General Settings');
    imgui.BeginChild('settings_general', { 0, 250, }, true);
        if( imgui.Checkbox('Visible', hgather.settings.visible) ) then
            -- if the checkbox is interacted with, reset the last_attempt
            -- to force the window back open
            hgather.last_attempt = ashita.time.clock()['ms'];
        end
        imgui.ShowHelp('Toggles if HGather is visible or not.');
        imgui.SliderFloat('Opacity', hgather.settings.opacity, 0.125, 1.0, '%.3f');
        imgui.ShowHelp('The opacity of the HGather window.');
        imgui.SliderFloat('Font Scale', hgather.settings.font_scale, 0.1, 2.0, '%.3f');
        imgui.ShowHelp('The scaling of the font size.');
        imgui.InputInt('Display Timeout', hgather.settings.display_timeout);
        imgui.ShowHelp('How long should the display window stay open after the last dig.');

        local pos = { hgather.settings.x[1], hgather.settings.y[1] };
        if (imgui.InputInt2('Position', pos)) then
            hgather.settings.x[1] = pos[1];
            hgather.settings.y[1] = pos[2];
        end
        imgui.ShowHelp('The position of HGather on screen.');

        imgui.Checkbox('Moon Display', hgather.settings.moon_display);
        imgui.ShowHelp('Toggles if moon phase / percent is shown.');
        imgui.Checkbox('Reset Rewards On Load', hgather.settings.reset_on_load);
        imgui.ShowHelp('Toggles whether we reset rewards each time the addon is loaded.');
    imgui.EndChild();
    imgui.Text('Chocobo Digging Display Settings');
    imgui.BeginChild('dig_general', { 0, 110, }, true);
        imgui.Checkbox('Digging Skillups', hgather.settings.digging.skillup_display);
        imgui.ShowHelp('Toggles if digging skillups are shown.');
        imgui.Checkbox('Subtract Greens', hgather.settings.digging.gysahl_subtract);
        imgui.ShowHelp('Toggles if gysahl greens are automatically subtracted from gil earned.');
    imgui.EndChild();
end

function render_items_config(settings)
    imgui.Text('Item Settings');
    imgui.BeginChild('settings_general', { 0, 470, }, true);

        imgui.InputInt('Gysahl Cost', hgather.settings.digging.gysahl_cost);
        imgui.ShowHelp('Cost of a single gysahl green.');

        imgui.Separator();

        local temp_strings = T{ };
        temp_strings[1] = table.concat(hgather.settings.item_index, '\n');
        if(imgui.InputTextMultiline('\nItem Prices', temp_strings, 8192, {0, 420})) then
            hgather.settings.item_index = split(temp_strings[1], '\n');
            table.sort(hgather.settings.item_index);
        end
        imgui.ShowHelp('Individual items, lowercase, separated by : with price on right side.');
    imgui.EndChild();
end

function split(inputstr, sep)
    if sep == nil then
        sep = '%s';
    end
    local t = {};
    for str in string.gmatch(inputstr, '([^'..sep..']+)') do
        table.insert(t, str);
    end
    return t;
end

function update_pricing() 
    for k, v in pairs(hgather.settings.item_index) do
        for k2, v2 in pairs(split(v, ':')) do
            if (k2 == 1) then
                itemname = v2;
            end
            if (k2 == 2) then
                itemvalue = v2;
            end
        end

        hgather.pricing[itemname] = itemvalue;
    end
end

----------------------------------------------------------------------------------------------------
-- Format numbers with commas
-- https://stackoverflow.com/questions/10989788/format-integer-in-lua
----------------------------------------------------------------------------------------------------
function format_int(number)
    if (string.len(number) < 4) then
        return number
    end
    if (number ~= nil and number ~= '' and type(number) == 'number') then
        local i, j, minus, int, fraction = tostring(number):find('([-]?)(%d+)([.]?%d*)');

        -- we sometimes get a nil int from the above tostring, just return number in those cases
        if (int == nil) then
            return number
        end

        -- reverse the int-string and append a comma to all blocks of 3 digits
        int = int:reverse():gsub("(%d%d%d)", "%1,");
  
        -- reverse the int-string back remove an optional comma and put the 
        -- optional minus and fractional part back
        return minus .. int:reverse():gsub("^,", "") .. fraction;
    else
        return 'NaN';
    end
end

----------------------------------------------------------------------------------------------------
-- Format the output used in display window and report
----------------------------------------------------------------------------------------------------
function format_output()
    local elapsed_time = ashita.time.clock()['s'] - math.floor(hgather.settings.first_attempt / 1000.0);

    local total_worth = 0;
    local accuracy = 0;
    local moon_table = GetMoon();
    local moon_phase = moon_table.MoonPhase;
    local moon_percent = moon_table.MoonPhasePercent;

    local output_text = '';

    if (hgather.settings.dig_tries ~= 0) then
        accuracy = (hgather.settings.dig_items / hgather.settings.dig_tries) * 100;
    end
        
    output_text = '~~~~~~ HGather Session ~~~~~~';
    output_text = output_text .. '\nAttempted Digs: ' .. hgather.settings.dig_tries .. ' (' .. string.format('%.2f', hgather.digging.dig_per_minute) .. ' dpm)';
    output_text = output_text .. '\nGreens Cost: ' .. format_int(hgather.settings.dig_tries * hgather.settings.digging.gysahl_cost[1]);
    output_text = output_text .. '\nItems Dug: ' .. hgather.settings.dig_items;
    output_text = output_text .. '\nDig Accuracy: ' .. string.format('%.2f', accuracy) .. '%%';
    if (hgather.settings.moon_display[1]) then
        output_text = output_text .. '\nMoon: ' + moon_phase + ' ('+ moon_percent + '%%)';
    end
    if (hgather.settings.digging.skillup_display[1]) then
        --Only show skillup line if one was seen during session
        if (hgather.digging.dig_skillup ~= 0.0) then
            output_text = output_text .. '\nSkillups: ' + hgather.digging.dig_skillup;
        end
    end

    -- imgui.Separator();
    output_text = output_text .. '\n~~~~~~~~~~~~~~~~~~~~~~~~~~~~';

    for k,v in pairs(hgather.settings.rewards) do
        itemTotal = 0;
        if (hgather.pricing[k] ~= nil) then
            total_worth = total_worth + hgather.pricing[k] * v;
            itemTotal = v * hgather.pricing[k];
        end
              
        output_text = output_text .. '\n' .. k .. ': ' .. 'x' .. format_int(v) .. ' (' .. format_int(itemTotal) .. 'g)';
    end

    -- imgui.Separator();
    output_text = output_text .. '\n~~~~~~~~~~~~~~~~~~~~~~~~~~~~';


    if (hgather.settings.digging.gysahl_subtract[1]) then
        total_worth = total_worth - (hgather.settings.dig_tries * hgather.settings.gysahl_cost[1]);
        -- only update gil_per_hour every 3 seconds
        if ((ashita.time.clock()['s'] % 3) == 0) then
            hgather.gil_per_hour = math.floor((total_worth / elapsed_time) * 3600); 
        end
        output_text = output_text .. '\nGil Made (minus greens): ' .. format_int(total_worth) .. 'g' .. ' (' .. format_int(hgather.gil_per_hour) .. ' gph)';
    else
        -- only update gil_per_hour every 3 seconds
        if ((ashita.time.clock()['s'] % 3) == 0) then
            hgather.gil_per_hour = math.floor((total_worth / elapsed_time) * 3600); 
        end
        output_text = output_text .. '\nGil Made: ' .. format_int(total_worth) .. 'g' .. ' (' .. format_int(hgather.gil_per_hour) .. ' gph)';
    end
    return output_text;
end

function clear_rewards()
    hgather.is_attempt = 0;
    hgather.last_attempt = ashita.time.clock()['ms'];
    hgather.settings.first_attempt = 0;
    hgather.settings.rewards = { };
    hgather.settings.dig_items = 0;
    hgather.settings.dig_tries = 0;
    hgather.digging.dig_skillup = 0.0;
end

----------------------------------------------------------------------------------------------------
-- Helper functions borrowed from luashitacast
----------------------------------------------------------------------------------------------------
function GetTimestamp()
    local pVanaTime = ashita.memory.find('FFXiMain.dll', 0, 'B0015EC390518B4C24088D4424005068', 0, 0);
    local pointer = ashita.memory.read_uint32(pVanaTime + 0x34);
    local rawTime = ashita.memory.read_uint32(pointer + 0x0C) + 92514960;
    local timestamp = {};
    timestamp.day = math.floor(rawTime / 3456);
    timestamp.hour = math.floor(rawTime / 144) % 24;
    timestamp.minute = math.floor((rawTime % 144) / 2.4);
    return timestamp;
end

function GetWeather()
    local pWeather = ashita.memory.find('FFXiMain.dll', 0, '66A1????????663D????72', 0, 0);
    local pointer = ashita.memory.read_uint32(pWeather + 0x02);
    return ashita.memory.read_uint8(pointer + 0);
end

function GetMoon()
    local timestamp = GetTimestamp();
    local moon_index = ((timestamp.day + 26) % 84) + 1;
    local moon_table = {};
    moon_table.MoonPhase = MoonPhase[moon_index];
    moon_table.MoonPhasePercent = MoonPhasePercent[moon_index];
    return moon_table;
end

--[[
* Prints the addon help information.
*
* @param {boolean} isError - Flag if this function was invoked due to an error.
--]]
local function print_help(isError)
    -- Print the help header..
    if (isError) then
        print(chat.header(addon.name):append(chat.error('Invalid command syntax for command: ')):append(chat.success('/' .. addon.name)));
    else
        print(chat.header(addon.name):append(chat.message('Available commands:')));
    end

    local cmds = T{
        { '/hgather', 'Toggles the HGather editor.' },
        { '/hgather edit', 'Toggles the HGather editor.' },
        { '/hgather save', 'Saves the current settings to disk.' },
        { '/hgather reload', 'Reloads the current settings from disk.' },
        { '/hgather report', 'Reports the current session to chat window.' },
        { '/hgather clear', 'Clears the HGather session stats.' },
        { '/hgather show', 'Shows the HGather information.' },
        { '/hgather hide', 'Hides the HGather information.' },
    };

    -- Print the command list..
    cmds:ieach(function (v)
        print(chat.header(addon.name):append(chat.error('Usage: ')):append(chat.message(v[1]):append(' - ')):append(chat.color1(6, v[2])));
    end);
end

--[[
* Registers a callback for the settings to monitor for character switches.
--]]
settings.register('settings', 'settings_update', function (s)
    if (s ~= nil) then
        hgather.settings = s;
    end

    -- Save the current settings..
    settings.save();
    update_pricing();
end);

--[[
* event: load
* desc : Event called when the addon is being loaded.
--]]
ashita.events.register('load', 'load_cb', function ()
    update_pricing();
    if ( hgather.settings.reset_on_load[1] ) then
        print('Reset rewards on reload.');
        clear_rewards();
    end
end);

--[[
* event: unload
* desc : Event called when the addon is being unloaded.
--]]
ashita.events.register('unload', 'unload_cb', function ()
    -- Save the current settings..
    settings.save();
end);

--[[
* event: command
* desc : Event called when the addon is processing a command.
--]]
ashita.events.register('command', 'command_cb', function (e)
    -- Parse the command arguments..
    local args = e.command:args();
    if (#args == 0 or not args[1]:any('/hgather')) then
        return;
    end

    -- Block all related commands..
    e.blocked = true;

    -- Handle: /hgather - Toggles the hgather editor.
    -- Handle: /hgather edit - Toggles the hgather editor.
    if (#args == 1 or (#args >= 2 and args[2]:any('edit'))) then
        hgather.editor.is_open[1] = not hgather.editor.is_open[1];
        return;
    end

    -- Handle: /hgather save - Saves the current settings.
    if (#args >= 2 and args[2]:any('save')) then
        update_pricing();
        settings.save();
        print(chat.header(addon.name):append(chat.message('Settings saved.')));
        return;
    end

    -- Handle: /hgather reload - Reloads the current settings from disk.
    if (#args >= 2 and args[2]:any('reload')) then
        settings.reload();
        print(chat.header(addon.name):append(chat.message('Settings reloaded.')));
        return;
    end

    -- Handle: /hgather report - Reports the current session to the chat window.
    if (#args >= 2 and args[2]:any('report')) then
        output_text = format_output();
        print(output_text);
        return;
    end

    -- Handle: /hgather clear - Clears the current rewards.
    if (#args >= 2 and args[2]:any('clear')) then
        clear_rewards();
        print(chat.header(addon.name):append(chat.message('Cleared hgather rewards.')));
        return;
    end

    -- Handle: /hgather show - Shows the hgather object.
    if (#args >= 2 and args[2]:any('show')) then
        -- reset last dig on show command to reset timeout counter
        hgather.last_attempt = ashita.time.clock()['ms'];
        hgather.settings.visible[1] = true;
        return;
    end

    -- Handle: /hgather hide - Hides the hgather object.
    if (#args >= 2 and args[2]:any('hide')) then
        hgather.settings.visible[1] = false;
        return;
    end

    -- Unhandled: Print help information..
    print_help(true);
end);

--[[
* event: packet_in
* desc : Event called when the addon is processing incoming packets.
ashita.events.register('packet_in', 'packet_in_cb', function (e)
end);
--]]

--[[
* event: packet_out
* desc : Event called when the addon is processing outgoing packets.
--]]
ashita.events.register('packet_out', 'packet_out_cb', function (e)
    if e.id == 0x01A then -- digging
        if struct.unpack("H", e.data_modified, 0x0A) == 0x1104 then -- digging
            hgather.is_attempt = true;
            dig_diff = (ashita.time.clock()['ms'] - hgather.last_attempt);
            hgather.last_attempt = ashita.time.clock()['ms'];
            if (hgather.settings.first_attempt == 0) then
                hgather.settings.first_attempt = ashita.time.clock()['ms'];
            end
            if (dig_diff > 1000) then
                -- print('digdiff: ' + dig_diff)
                hgather.digging.dig_timing[hgather.digging.dig_index] = dig_diff;
                timing_total = 0;
                for i=1, #hgather.digging.dig_timing do
                    timing_total = timing_total + hgather.digging.dig_timing[i];
                end
        
                hgather.digging.dig_per_minute = 60 / ((timing_total / 1000.0) / #hgather.digging.dig_timing);
    
                if ( hgather.digging.dig_index >= #hgather.digging.dig_timing ) then
                    hgather.digging.dig_index = 1;
                else
                    hgather.digging.dig_index = hgather.digging.dig_index + 1;
                end
            end
        end
    end
end);

----------------------------------------------------------------------------------------------------
-- Parse Digging Items + Main Logic
----------------------------------------------------------------------------------------------------
ashita.events.register('text_in', 'text_in_cb', function (e)
    local last_attempt_secs = (ashita.time.clock()['ms'] - hgather.last_attempt) / 1000.0;
    message = e.message;
    message = string.lower(message);
    message = string.strip_colors(message);

    success = string.match(message, "obtained: (.*).") or success_break;
    unable = string.contains(message, "you dig and you dig");
    skill_up = string.match(message, "skill increases by (.*) raising");
	
    -- only set is_attempt if we dug within last 60 seconds
    if ((success or unable) and last_attempt_secs < 60) then
        hgather.is_attempt = true;
        if (hgather.settings.visible[1] == false) then
            hgather.settings.visible[1] = true
        end
    else
        hgather.is_attempt = false;
    end
   
    --skillup count
    if (skill_up) then
        hgather.digging.dig_skillup = hgather.digging.dig_skillup + skill_up;
    end

    if hgather.is_attempt then 
        success_break = false;
        success = string.match(message, "obtained: (.*).") or success_break;
        unable = string.contains(message, "you dig and you dig");
        broken = false;
        lost = false;

        --count attempt
        if (unable) then 
            hgather.settings.dig_tries = hgather.settings.dig_tries + 1;
        end
        
        if success then
            hgather.settings.dig_items = hgather.settings.dig_items + 1;
            hgather.settings.dig_tries = hgather.settings.dig_tries + 1;

            if (success ~= nil) then
                if (hgather.settings.rewards[success] == nil) then
                    hgather.settings.rewards[success] = 1;
                elseif (hgather.settings.rewards[success] ~= nil) then
                    hgather.settings.rewards[success] = hgather.settings.rewards[success] + 1;
                end
                -- sorting this table does nothing because we access it via pairs();
                -- table.sort(hgather.digging_rewards);
            end
        end
    end
end);

--[[
* event: d3d_beginscene
* desc : Event called when the Direct3D device is beginning a scene.
--]]
ashita.events.register('d3d_beginscene', 'beginscene_cb', function (isRenderingBackBuffer)
end);

--[[
* event: d3d_present
* desc : Event called when the Direct3D device is presenting a scene.
--]]
ashita.events.register('d3d_present', 'present_cb', function ()
    local last_attempt_secs = (ashita.time.clock()['ms'] - hgather.last_attempt) / 1000.0;
    render_editor();

    if (last_attempt_secs > hgather.settings.display_timeout[1]) then
        hgather.settings.visible[1] = false;
    end

    -- Hide the hgather object if not visible..
    if (not hgather.settings.visible[1]) then
        return;
    end

    -- Hide the hgather object if Ashita is currently hiding font objects..
    if (not AshitaCore:GetFontManager():GetVisible()) then
        return;
    end

    imgui.SetNextWindowBgAlpha(hgather.settings.opacity[1]);
    imgui.SetNextWindowSize({ -1, -1, }, ImGuiCond_Always);
    if (imgui.Begin('HGather##Display', hgather.settings.visible[1], bit.bor(ImGuiWindowFlags_NoDecoration, ImGuiWindowFlags_AlwaysAutoResize, ImGuiWindowFlags_NoFocusOnAppearing, ImGuiWindowFlags_NoNav))) then
        imgui.SetWindowFontScale(hgather.settings.font_scale[1]);
        output_text = format_output();
        imgui.Text(output_text);
    end
    imgui.End();

end);

--[[
* event: key
* desc : Event called when the addon is processing keyboard input. (WNDPROC)
--]]
ashita.events.register('key', 'key_callback', function (e)
    -- Key: VK_SHIFT
    if (e.wparam == 0x10) then
        hgather.move.shift_down = not (bit.band(e.lparam, bit.lshift(0x8000, 0x10)) == bit.lshift(0x8000, 0x10));
        return;
    end
end);

--[[
* event: mouse
* desc : Event called when the addon is processing mouse input. (WNDPROC)
--]]
ashita.events.register('mouse', 'mouse_cb', function (e)
    -- Tests if the given coords are within the equipmon area.
    local function hit_test(x, y)
        local e_x = hgather.settings.x[1];
        local e_y = hgather.settings.y[1];
        local e_w = ((32 * hgather.settings.scale[1]) * 4) + hgather.settings.padding[1] * 3;
        local e_h = ((32 * hgather.settings.scale[1]) * 4) + hgather.settings.padding[1] * 3;

        return ((e_x <= x) and (e_x + e_w) >= x) and ((e_y <= y) and (e_y + e_h) >= y);
    end

    -- Returns if the equipmon object is being dragged.
    local function is_dragging() return hgather.move.dragging; end

    -- Handle the various mouse messages..
    switch(e.message, {
        -- Event: Mouse Move
        [512] = (function ()
            hgather.settings.x[1] = e.x - hgather.move.drag_x;
            hgather.settings.y[1] = e.y - hgather.move.drag_y;

            e.blocked = true;
        end):cond(is_dragging),

        -- Event: Mouse Left Button Down
        [513] = (function ()
            if (hgather.move.shift_down) then
                hgather.move.dragging = true;
                hgather.move.drag_x = e.x - hgather.settings.x[1];
                hgather.move.drag_y = e.y - hgather.settings.y[1];

                e.blocked = true;
            end
        end):cond(hit_test:bindn(e.x, e.y)),

        -- Event: Mouse Left Button Up
        [514] = (function ()
            if (hgather.move.dragging) then
                hgather.move.dragging = false;

                e.blocked = true;
            end
        end):cond(is_dragging),

        -- Event: Mouse Wheel Scroll
        [522] = (function ()
            if (e.delta < 0) then
                hgather.settings.opacity[1] = hgather.settings.opacity[1] - 0.125;
            else
                hgather.settings.opacity[1] = hgather.settings.opacity[1] + 0.125;
            end
            hgather.settings.opacity[1] = hgather.settings.opacity[1]:clamp(0.125, 1);

            e.blocked = true;
        end):cond(hit_test:bindn(e.x, e.y)),
    });
end);