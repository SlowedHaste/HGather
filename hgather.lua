addon.name = 'hgather';
addon.description = 'Simple dig tracker.';
addon.author = 'Hastega';
addon.version = '1.1.1';
addon.commands = {'/hgather'};

----------------------------------------------------------------------------------------------------
-- Variables
----------------------------------------------------------------------------------------------------
local common = require('common');
local imgui = require('imgui');
local settings = require('settings');
local ffi = require('ffi');
local d3d = require 'd3d8';
local d3d8dev = d3d.get_device();
local data = require('constants');

local ashitaResourceManager = AshitaCore:GetResourceManager();
local ashitaChatManager     = AshitaCore:GetChatManager();
local ashitaDataManager     = AshitaCore:GetMemoryManager();
local ashitaParty           = ashitaDataManager:GetParty();
local ashitaPlayer          = ashitaDataManager:GetPlayer();
local ashitaInventory       = ashitaDataManager:GetInventory();
local ashitaTarget          = ashitaDataManager:GetTarget();
local ashitaEntity          = ashitaDataManager:GetEntity();

hgather = T{
    open = false,
    isAttempt = false,
    numDigs = 0,
    numItems = 0,
    skillUp = 0.0,
    firstDig = 0,
    lastDig = ashita.time.clock()['ms'],
    diggingRewards = { },
    pricing = { },
    digTiming = { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
    digPerMinute = 0,
    digIndex = 1
};

----------------------------------------------------------------------------------------------------
-- Helper Functions
----------------------------------------------------------------------------------------------------
function file_exists(file)
    local f = io.open(file, "rb");
    if f then f:close() end
    return f ~= nil;
end
  
function lines_from(file)
    if not file_exists(file) then return {} end
    local lines = {};
    for line in io.lines(file) do 
      lines[#lines + 1] = line;
    end
    return lines;
end

function mysplit (inputstr, sep)
    if sep == nil then
        sep = "%s";
    end
    local t={};
    for str in string.gmatch(inputstr, "([^"..sep.."]+)") do
        table.insert(t, str);
    end
    return t;
end

function updatePricing() 
    -- Grab Pricing
    local path = ('%saddons\\hgather\\%s.txt'):fmt(AshitaCore:GetInstallPath(), 'itempricing');
    local file = path;
    local lines = lines_from(file);

    -- print all line numbers and their contents
    for k,v in pairs(lines) do
        for k2, v2 in pairs(mysplit(v, ':')) do
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

function reportSession()
    totalWorth = 0;
    accuracy = 0;

    if (hgather.numDigs ~= 0) then
        accuracy = (hgather.numItems / hgather.numDigs) * 100;
    end

    print('~~ Digging Session ~~');
    print("Attempted Digs: " + hgather.numDigs);
    print('Items Dug: ' + hgather.numItems);
    print('Dig Accuracy: ' + string.format('%.2f', accuracy) + '%%');
    --Only show skillup line if one was seen during session
    if (hgather.skillUp ~= 0.0) then
        print('Skillups: ' + hgather.skillUp);
    end
    print('----------');

    for k,v in pairs(hgather.diggingRewards) do
        itemTotal = 0;
        if (hgather.pricing[k] ~= nil) then
            totalWorth = totalWorth + hgather.pricing[k] * v;
            itemTotal = v * hgather.pricing[k];
        end

        print(k + ": " + "x" + v + " (" + itemTotal + "g)");
    end

    print('----------');
    print("Gil Made: " + totalWorth + 'g');
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
    local moonIndex = ((timestamp.day + 26) % 84) + 1;
    local moonTable = {};
    moonTable.MoonPhase = MoonPhase[moonIndex];
    moonTable.MoonPhasePercent = MoonPhasePercent[moonIndex];
    return moonTable;
end

----------------------------------------------------------------------------------------------------
-- Load Event
----------------------------------------------------------------------------------------------------
ashita.events.register('load', 'load_cb', function()
    updatePricing();
end)

----------------------------------------------------------------------------------------------------
-- Commands
----------------------------------------------------------------------------------------------------
ashita.events.register('text_out', 'text_out_callback1', function (e)
    if (not e.injected) then
        if (string.match(e.message, '/hgather reset')) then
            hgather.diggingRewards = { };
            hgather.isAttempt = 0;
            hgather.numItems = 0;
            hgather.skillUp = 0.0;
            print('HGather: Digging session has been reset');
        end
    end

    if (not e.injected) then
        if (string.match(e.message, '/hgather open')) then
            hgather.open = true;
            hgather.lastDig = ashita.time.clock()['ms'];
        end
    end

    if (not e.injected) then
        if (string.match(e.message, '/hgather close')) then
            hgather.open = false;
        end
    end

    if (not e.injected) then
        if (string.match(e.message, '/hgather update')) then
            updatePricing();
            print('HGather: Pricing has been Updated.');
        end
    end

    if (not e.injected) then
        if (string.match(e.message, '/hgather report')) then
            print('HGather: Reporting current session');
            reportSession();
        end
    end

    if (not e.injected) then
        if (string.match(e.message, '/hgather help')) then
            print('HGather: Commands are Open, Close, Reset, Update, Report, Help');
        end
    end
end);

----------------------------------------------------------------------------------------------------
-- Parse Digging Items + Main Logic
----------------------------------------------------------------------------------------------------
ashita.events.register('text_in', 'text_in_cb', function (e)
    local lastDigSecs = (ashita.time.clock()['ms'] - hgather.lastDig) / 1000.0;
    message = e.message;
    message = string.lower(message);
    message = string.strip_colors(message);

    success = string.match(message, "obtained: (.*).") or successBreak;
    unable = string.contains(message, "you dig and you dig");
    skillUp = string.match(message, "skill increases by (.*) raising");
	
    -- only set isAttempt if we dug within last 60 seconds
    if ((success or unable) and lastDigSecs < 60) then
        hgather.isAttempt = true;
    else
        hgather.isAttempt = false;
    end
   
    if hgather.isAttempt then 
        --skillup count
        if (skillUp) then
            hgather.skillUp = hgather.skillUp + skillUp;
        end

        successBreak = false;
        success = string.match(message, "obtained: (.*).") or successBreak;
        unable = string.contains(message, "you dig and you dig");
        broken = false;
        lost = false;

        --keep window open
        if (unable or success) then
            hgather.open = true;
        end

        --count attempt
        if (unable) then 
            hgather.numDigs = hgather.numDigs + 1;
        end
        
        if success then
            --local of = string.match(success, "of (.*)");
            --if of then success = of; txt = of end;
            hgather.numItems = hgather.numItems + 1;
            hgather.numDigs = hgather.numDigs + 1;

            if (success ~= nil) then
                if (hgather.diggingRewards[success] == nil) then
                    hgather.diggingRewards[success] = 1;
                elseif (hgather.diggingRewards[success] ~= nil) then
                    hgather.diggingRewards[success] = hgather.diggingRewards[success] + 1;
                end
            end
        end
    end
end)

----------------------------------------------------------------------------------------------------
-- Digging Event
----------------------------------------------------------------------------------------------------
ashita.events.register('packet_out', 'packet_out_callback1', function (e)
    if e.id == 0x01A then -- digging
        if struct.unpack("H", e.data_modified, 0x0A) == 0x1104 then -- digging
            hgather.isAttempt = true;
            digDiff = (ashita.time.clock()['ms'] - hgather.lastDig);
            hgather.lastDig = ashita.time.clock()['ms'];
            if (hgather.firstDig == 0) then
                hgather.firstDig = ashita.time.clock()['ms'];
            end
            if (digDiff > 1000) then
                -- print('digdiff: ' + digDiff)
                hgather.digTiming[hgather.digIndex] = digDiff;
                timingTotal = 0;
                for i=1, #hgather.digTiming do
                    timingTotal = timingTotal + hgather.digTiming[i];
                end
        
                hgather.digPerMinute = 60 / ((timingTotal / 1000.0) / #hgather.digTiming);
    
                if ( hgather.digIndex >= #hgather.digTiming ) then
                    hgather.digIndex = 1;
                else
                    hgather.digIndex = hgather.digIndex + 1;
                end
            end
        end
    end
end)

----------------------------------------------------------------------------------------------------
-- GUI
----------------------------------------------------------------------------------------------------
ashita.events.register('d3d_present', 'present_cb', function () 
    local digDiff = ashita.time.clock()['ms'] - hgather.lastDig;
    local elapsedTime = ashita.time.clock()['ms'] - hgather.firstDig;
    if (hgather.open == false) then
        return;
    end

    imgui.SetNextWindowBgAlpha(0.8);
    imgui.SetNextWindowSize({ 250, -1, }, ImGuiCond_Always);

    if (imgui.Begin('HasteGather', hgather.open, bit.bor(ImGuiWindowFlags_NoDecoration, ImGuiWindowFlags_AlwaysAutoResize, ImGuiWindowFlags_NoSavedSettings, ImGuiWindowFlags_NoFocusOnAppearing, ImGuiWindowFlags_NoNav))) then
        local totalWorth = 0;
        local accuracy = 0;
        local moonTable = GetMoon();
        local moonPhase = moonTable.MoonPhase;
        local moonPercent = moonTable.MoonPhasePercent;

        if (hgather.numDigs ~= 0) then
            accuracy = (hgather.numItems / hgather.numDigs) * 100;
        end
        
        imgui.Text('~~ Digging Session ~~');
        imgui.Text('Attempted Digs: ' + hgather.numDigs + ' (' + string.format('%.2f', hgather.digPerMinute) + ' dpm)');
        imgui.Text('Greens Cost: ' + hgather.numDigs * 62);
        imgui.Text('Items Dug: ' + hgather.numItems);
        imgui.Text('Dig Accuracy: ' + string.format('%.2f', accuracy) + '%%');
        imgui.Text('Moon: ' + moonPhase + ' ('+ moonPercent + '%%)');
        --Only show skillup line if one was seen during session
        if (hgather.skillUp ~= 0.0) then
            imgui.Text('Skillups: ' + hgather.skillUp);
        end
        imgui.Separator();

        for k,v in pairs(hgather.diggingRewards) do
            itemTotal = 0;
            if (hgather.pricing[k] ~= nil) then
                totalWorth = totalWorth + hgather.pricing[k] * v;
                itemTotal = v * hgather.pricing[k];
            end
                
            imgui.Text(k + ": " + "x" + v + " (" + itemTotal + "g)");
        end

        imgui.Separator();
        gilHour = math.floor((totalWorth / (elapsedTime / 1000.0)) * 3600); 
        imgui.Text("Gil Made: " + totalWorth + "g" + " (" + gilHour + " gph)");

        --List things gotten for digging session
    end

    --end session
    if ((digDiff / 1000.0) > 300) then
        imgui.End();
        hgather.open = false;
    end
end)
