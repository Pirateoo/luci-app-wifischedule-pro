#!/usr/bin/lua

-- Test script to verify date.nager.at API integration
print("Testing date.nager.at API integration...")

-- Mock the UCI cursor to simulate configuration
local mock_uci = {
    data = {
        wifi_schedule = {
            global = {
                holiday_api_url = "https://date.nager.at/api/v3/PublicHolidays/2025/US",
                holiday_api_region = "US",
                holiday_api_country = "US"
            }
        }
    },
    get = function(self, section, option, key)
        if self.data[section] and self.data[section][option] then
            return self.data[section][option][key]
        end
        return nil
    end,
    set = function(self, section, option, key, value)
        if not self.data[section] then
            self.data[section] = {}
        end
        if not self.data[section][option] then
            self.data[section][option] = {}
        end
        self.data[section][option][key] = value
    end
}

-- Mock the sys.exec function
local mock_sys = {
    exec = function(cmd)
        print("Executing command: " .. cmd)
        -- Mock response for US holidays in 2025
        if cmd:match("date%.nager%.at") then
            return [[
[
    {
        "date": "2025-01-01",
        "localName": "New Year's Day",
        "name": "New Year's Day",
        "countryCode": "US",
        "fixed": true,
        "global": true,
        "counties": null,
        "launchYear": null,
        "types": [
            "Public"
        ]
    },
    {
        "date": "2025-07-04",
        "localName": "Independence Day",
        "name": "Independence Day",
        "countryCode": "US",
        "fixed": true,
        "global": true,
        "counties": null,
        "launchYear": null,
        "types": [
            "Public"
        ]
    },
    {
        "date": "2025-12-25",
        "localName": "Christmas Day",
        "name": "Christmas Day",
        "countryCode": "US",
        "fixed": true,
        "global": true,
        "counties": null,
        "launchYear": null,
        "types": [
            "Public"
        ]
    }
]
]]
        end
        return ""
    end
}

-- Mock the luci.jsonc module
local mock_jsonc = {
    parse = function(str)
        -- Simple JSON parsing for our test
        if str:match("New Year's Day") then
            return {
                {
                    date = "2025-01-01",
                    localName = "New Year's Day",
                    name = "New Year's Day",
                    countryCode = "US",
                    fixed = true,
                    global = true,
                    counties = nil,
                    launchYear = nil,
                    types = {"Public"}
                },
                {
                    date = "2025-07-04",
                    localName = "Independence Day",
                    name = "Independence Day", 
                    countryCode = "US",
                    fixed = true,
                    global = true,
                    counties = nil,
                    launchYear = nil,
                    types = {"Public"}
                },
                {
                    date = "2025-12-25",
                    localName = "Christmas Day",
                    name = "Christmas Day",
                    countryCode = "US",
                    fixed = true,
                    global = true,
                    counties = nil,
                    launchYear = nil,
                    types = {"Public"}
                }
            }
        end
        return nil
    end
}

-- Load the calendar module and override dependencies with mocks
local calendar_path = "./luasrc/util/wifischedule/calendar.lua"
local calendar_code = io.open(calendar_path, "r"):read("*all")

-- Temporarily redefine the required modules
local original_require = require
local function mock_require(module_name)
    if module_name == "luci.model.uci" then
        return {cursor = function() return mock_uci end}
    elseif module_name == "luci.sys" then
        return mock_sys
    elseif module_name == "luci.jsonc" then
        return mock_jsonc
    else
        return original_require(module_name)
    end
end

-- Replace require calls temporarily
_G.require = mock_require

-- Execute the calendar module code
local env = {
    require = mock_require,
    uci = mock_uci,
    sys = mock_sys,
    jsonc = mock_jsonc,
    os = os,
    string = string,
    table = table,
    print = print,
    tonumber = tonumber,
    type = type,
    ipairs = ipairs,
    pairs = pairs,
    module = function(name) _G[name] = {} return _G[name] end,
    package = { seeall = function() return {} end }
}

setmetatable(env, {__index = _G})

local func, err = load(calendar_code, "calendar.lua", "t", env)
if func then
    func()
    print("Calendar module loaded successfully")
    
    -- Test the date.nager.at API functionality
    local test_date = "2025-01-01"
    local is_holiday, holiday_name = env.is_holiday_via_api(test_date)
    
    print("\nTest Results:")
    print("Date: " .. test_date)
    print("Is holiday: " .. tostring(is_holiday))
    print("Holiday name: " .. (holiday_name or "N/A"))
    
    if is_holiday == true and holiday_name == "New Year's Day" then
        print("\n✓ SUCCESS: date.nager.at API integration works correctly!")
    else
        print("\n✗ FAILURE: date.nager.at API integration failed!")
    end
    
    -- Test a non-holiday date
    local test_date2 = "2025-06-15"
    local is_holiday2, holiday_name2 = env.is_holiday_via_api(test_date2)
    
    print("\nTest Results for non-holiday:")
    print("Date: " .. test_date2)
    print("Is holiday: " .. tostring(is_holiday2))
    print("Holiday name: " .. (holiday_name2 or "N/A"))
    
    if is_holiday2 == false then
        print("✓ SUCCESS: Correctly identified non-holiday date!")
    else
        print("✗ FAILURE: Did not correctly identify non-holiday date!")
    end
else
    print("Error loading calendar module: " .. err)
end

-- Restore original require
_G.require = original_require