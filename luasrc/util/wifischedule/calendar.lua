-- Calendar utility for wifi schedule app
-- Handles workdays, weekends, and holidays for different regions with timezone support
-- Supports external API requests for holiday checking and CSV uploads

module("luci.util.wifischedule.calendar", package.seeall)

local uci = require "luci.model.uci".cursor()
local http = require "luci.http"
local sys = require "luci.sys"
local jsonc = require "luci.jsonc"

-- Default holiday calendars for different regions
local calendars = {
    china = {
        name = "China",
        workdays = {}, -- Custom workdays that are normally holidays (like before/after holidays)
        holidays = {
            -- Fixed date holidays
            ["01-01"] = "New Year's Day",
            ["05-01"] = "Labor Day",
            ["10-01"] = "National Day",
            ["10-02"] = "National Day",
            ["10-03"] = "National Day",
            
            -- Chinese lunar calendar holidays need to be manually configured
            -- Example: ["02-14"] = "Spring Festival" -- This is just an example
        }
    },
    us = {
        name = "United States",
        workdays = {},
        holidays = {
            ["01-01"] = "New Year's Day",
            ["07-04"] = "Independence Day", 
            ["12-25"] = "Christmas Day",
            -- Thanksgiving is on the fourth Thursday of November
        }
    },
    eu = {
        name = "European Union",
        workdays = {},
        holidays = {
            ["01-01"] = "New Year's Day",
            ["05-01"] = "Labour Day",
            ["12-25"] = "Christmas Day",
            ["12-26"] = "Boxing Day",
        }
    },
    custom = {
        name = "Custom",
        workdays = {},
        holidays = {}
    }
}

-- Get the current region from UCI config
local function get_current_region()
    local region = uci:get("wifi_schedule", "global", "region")
    return region or "custom"
end

-- Get timezone offset from system
local function get_timezone_offset()
    -- Try to get the timezone from system
    local tz = os.getenv("TZ") or "UTC"
    local offset = 0
    -- This is a simplified approach - in practice, you might need more complex timezone handling
    return tz, offset
end

-- Check if a specific date is a workday (handles timezone conversion)
function is_workday(date_str)
    -- Format: YYYY-MM-DD
    local year, month, day = date_str:match("(%d+)-(%d+)-(%d+)")
    if not year then
        return false
    end
    
    -- First, try external API for holiday information (highest priority)
    local is_holiday, holiday_name = is_holiday_via_api(date_str)
    if is_holiday ~= nil then
        -- API returned a result, return the opposite (if it's a holiday, it's not a workday)
        return not is_holiday
    end
    
    -- Get timezone information
    local tz_name, tz_offset = get_timezone_offset()
    
    -- Convert to day of week (0=Sunday, 1=Monday, ..., 6=Saturday)
    local timestamp = os.time({year=tonumber(year), month=tonumber(month), day=tonumber(day)})
    local day_of_week = tonumber(os.date("%w", timestamp)) -- 0=Sunday, 1=Monday, ..., 6=Saturday
    
    -- Check if it's weekend (Saturday or Sunday in this default implementation)
    if day_of_week == 0 or day_of_week == 6 then
        -- Check if it's a special workday
        local date_part = string.format("%02d-%02d", tonumber(month), tonumber(day))
        local region = get_current_region()
        local calendar = calendars[region] or calendars["custom"]
        
        if calendar and calendar.workdays and calendar.workdays[date_part] then
            return true -- This weekend day is a special workday
        else
            return false -- It's a normal weekend
        end
    end
    
    -- It's a weekday, check if it's a holiday
    local date_part = string.format("%02d-%02d", tonumber(month), tonumber(day))
    local region = get_current_region()
    local calendar = calendars[region] or calendars["custom"]
    
    if calendar and calendar.holidays and calendar.holidays[date_part] then
        return false -- It's a holiday
    end
    
    return true -- Normal workday
end

-- Get the schedule type for a date: "workday", "weekend", or "holiday"
function get_schedule_type(date_str)
    -- First, try external API for holiday information (highest priority)
    local is_holiday, holiday_name = is_holiday_via_api(date_str)
    if is_holiday ~= nil then
        if is_holiday then
            return "holiday"
        else
            -- If API says it's not a holiday, check if it's weekend or workday
            local year, month, day = date_str:match("(%d+)-(%d+)-(%d+)")
            local date_part = string.format("%02d-%02d", tonumber(month), tonumber(day))
            local timestamp = os.time({year=tonumber(year), month=tonumber(month), day=tonumber(day)})
            local day_of_week = tonumber(os.date("%w", timestamp)) -- 0=Sunday, 1=Monday, ..., 6=Saturday
            
            if day_of_week == 0 or day_of_week == 6 then
                -- Weekend day that isn't a holiday
                local region = get_current_region()
                local calendar = calendars[region] or calendars["custom"]
                if calendar and calendar.workdays and calendar.workdays[date_part] then
                    return "workday"  -- Special workday
                else
                    return "weekend"  -- Regular weekend
                end
            else
                return "workday"  -- Regular workday that isn't a holiday
            end
        end
    end
    
    -- Fallback to existing logic if API is not configured or failed
    if is_workday(date_str) then
        -- Further check if it's a holiday
        local year, month, day = date_str:match("(%d+)-(%d+)-(%d+)")
        local date_part = string.format("%02d-%02d", tonumber(month), tonumber(day))
        local region = get_current_region()
        local calendar = calendars[region] or calendars["custom"]
        
        if calendar and calendar.holidays and calendar.holidays[date_part] then
            return "holiday"
        else
            return "workday"
        end
    else
        -- Check if it's a weekend or special workday
        local date_part = string.format("%02d-%02d", tonumber(month), tonumber(day))
        local region = get_current_region()
        local calendar = calendars[region] or calendars["custom"]
        
        if calendar and calendar.workdays and calendar.workdays[date_part] then
            return "workday"  -- Special workday
        else
            return "weekend"  -- Regular weekend
        end
    end
end

-- Load custom holidays from UCI config
function load_custom_holidays()
    local custom_holidays = uci:get("wifi_schedule", "calendar", "holidays")
    if custom_holidays then
        -- Parse custom holidays from UCI config
        -- Format: "MM-DD:Description,MM-DD:Description"
        for date_desc in custom_holidays:gmatch("[^,]+") do
            local date_part, desc = date_desc:match("(%d%d-%d%d):(.+)")
            if date_part and desc then
                calendars["custom"].holidays[date_part] = desc
            end
        end
    end
    
    local custom_workdays = uci:get("wifi_schedule", "calendar", "workdays")
    if custom_workdays then
        -- Parse custom workdays
        for date_desc in custom_workdays:gmatch("[^,]+") do
            local date_part, desc = date_desc:match("(%d%d-%d%d):(.+)")
            if date_part and desc then
                calendars["custom"].workdays[date_part] = desc
            end
        end
    end
end

-- Check if a specific date is a holiday using external API
function is_holiday_via_api(date_str)
    -- Get API configuration from UCI
    local api_url = uci:get("wifi_schedule", "global", "holiday_api_url")
    local api_region = uci:get("wifi_schedule", "global", "holiday_api_region") or get_current_region()
    local api_key = uci:get("wifi_schedule", "global", "holiday_api_key")
    local api_country = uci:get("wifi_schedule", "global", "holiday_api_country")  -- Additional country parameter
    local api_language = uci:get("wifi_schedule", "global", "holiday_api_language")  -- Additional language parameter
    
    if not api_url or api_url == "" then
        -- No API configured, return nil to indicate fallback should be used
        return nil
    end
    
    -- Format the API URL with various parameters
    local formatted_url = api_url
        :gsub("{{date}}", date_str)
        :gsub("{date}", date_str)
        :gsub("{{region}}", api_region or "")
        :gsub("{region}", api_region or "")
        :gsub("{{country}}", api_country or "")
        :gsub("{country}", api_country or "")
        :gsub("{{language}}", api_language or "")
        :gsub("{language}", api_language or "")
    
    -- Prepare cURL command for making the HTTP request
    local cmd = "curl -s -m 10 "
    if api_key and api_key ~= "" then
        cmd = cmd .. "-H \"X-API-Key: " .. api_key .. "\" "
        cmd = cmd .. "-H \"Authorization: Bearer " .. api_key .. "\" "
        cmd = cmd .. "-H \"Authorization: Token " .. api_key .. "\" "
    end
    cmd = cmd .. "\"" .. formatted_url .. "\""
    
    local result = sys.exec(cmd)
    
    if result and result ~= "" then
        -- Try to parse as JSON first
        if jsonc then
            local parsed = jsonc.parse(result)
            if parsed then
                -- Check common response formats for holiday APIs
                if type(parsed) == "table" then
                    -- Holiday API response formats:
                    -- 1. { date: "2023-01-01", holiday: true, name: "New Year" }
                    -- 2. { is_holiday: true, name: "New Year" }
                    -- 3. { date: "2023-01-01", holidays: [{name: "New Year", date: "2023-01-01"}] }
                    -- 4. [ { name: "New Year", date: "2023-01-01", type: "Public" } ] (an array of holidays)
                    
                    if parsed.holiday == true or parsed.is_holiday == true then
                        return true, parsed.name or parsed.localName or parsed.englishName or parsed.chineseName or parsed.local_name or parsed.description or "Holiday"
                    elseif parsed.holidays and type(parsed.holidays) == "table" and #parsed.holidays > 0 then
                        -- Check if any of the returned holidays matches our date
                        for _, holiday in ipairs(parsed.holidays) do
                            if holiday.date == date_str then
                                return true, holiday.name or holiday.localName or holiday.englishName or holiday.chineseName or holiday.local_name or holiday.description or "Holiday"
                            end
                        end
                    elseif type(parsed) == "table" and #parsed > 0 then
                        -- Handle array response format
                        for _, holiday in ipairs(parsed) do
                            if holiday.date == date_str then
                                return true, holiday.name or holiday.localName or holiday.englishName or holiday.chineseName or holiday.local_name or holiday.description or "Holiday"
                            end
                        end
                    end
                elseif type(parsed) == "boolean" then
                    -- Some APIs just return true/false
                    return parsed == true, "Holiday"
                elseif type(parsed) == "number" then
                    -- Some APIs return 1/0 for true/false
                    return parsed == 1, "Holiday"
                elseif type(parsed) == "string" then
                    -- Some APIs return "true"/"false" as strings
                    local lower_parsed = parsed:lower()
                    if lower_parsed == "true" or lower_parsed == "yes" or lower_parsed == "holiday" then
                        return true, "Holiday"
                    elseif lower_parsed == "false" or lower_parsed == "no" then
                        return false, "Not a holiday"
                    end
                end
            end
        else
            -- If JSON parsing fails, look for simple text responses
            local lower_result = result:lower()
            if lower_result:match("true") or lower_result:match("holiday") or lower_result:match("yes") then
                return true, "Holiday"
            elseif lower_result:match("false") or lower_result:match("no") then
                return false, "Not a holiday"
            end
        end
    end
    
    -- API request failed or didn't return expected result
    return nil
end

-- Parse CSV content and store in a temporary format
function parse_csv_schedule(csv_content)
    local schedule = {}
    local lines = {}
    
    -- Split CSV into lines
    for line in csv_content:gmatch("[^\r\n]+") do
        line = line:match("^%s*(.-)%s*$") -- trim whitespace
        if line ~= "" then
            table.insert(lines, line)
        end
    end
    
    -- Skip header if it exists (contains "date" and "action")
    local has_header = false
    if #lines > 0 then
        local first_line = lines[1]:lower()
        if first_line:match("date") and first_line:match("action") then
            has_header = true
        end
    end
    
    local start_idx = has_header and 2 or 1
    for i = start_idx, #lines do
        local line = lines[i]
        -- Parse date,action format (supporting comma-separated values)
        local date_part, action_part = line:match("^([^,]+),([^,]+)")
        if not date_part then
            -- Try other common separators
            date_part, action_part = line:match("^([^|]+)|([^|]+)")
        end
        if not date_part then
            date_part, action_part = line:match("^([^;]+);([^;]+)")
        end
        
        if date_part and action_part then
            date_part = date_part:match("^%s*(.-)%s*$") -- trim
            action_part = action_part:match("^%s*(.-)%s*$") -- trim
            
            -- Validate date format (YYYY-MM-DD or MM/DD/YYYY or DD/MM/YYYY)
            local year, month, day
            if date_part:match("%d%d%d%d%-%d%d%-%d%d") then -- YYYY-MM-DD
                year, month, day = date_part:match("(%d%d%d%d)%-(%d%d)%-(%d%d)")
            elseif date_part:match("%d%d?/%d%d?/%d%d%d%d") then -- MM/DD/YYYY
                month, day, year = date_part:match("(%d%d?)/(%d%d?)/(%d%d%d%d)")
            elseif date_part:match("%d%d?%-%d%d?%-%d%d%d%d") then -- MM-DD-YYYY
                month, day, year = date_part:match("(%d%d?)-(%d%d?)-(%d%d%d%d)")
            else
                -- Try DD/MM/YYYY or DD-MM-YYYY
                day, month, year = date_part:match("(%d%d?)[/%-](%d%d?)[/%-](%d%d%d%d)")
            end
            
            if year and month and day then
                -- Normalize date to YYYY-MM-DD format
                local normalized_date = string.format("%04d-%02d-%02d", tonumber(year), tonumber(month), tonumber(day))
                
                -- Validate action (should be "on", "off", "enable", "disable", or "start", "stop")
                local action_normalized = action_part:lower()
                if action_normalized == "on" or action_normalized == "enable" or action_normalized == "start" then
                    schedule[normalized_date] = "enable"
                elseif action_normalized == "off" or action_normalized == "disable" or action_normalized == "stop" then
                    schedule[normalized_date] = "disable"
                end
            end
        end
    end
    
    return schedule
end

-- Store CSV schedule to file
function store_csv_schedule(schedule_table)
    local csv_file = io.open("/etc/wifi_schedule.csv", "w")
    if csv_file then
        csv_file:write("date,action\n")
        for date_str, action in pairs(schedule_table) do
            csv_file:write(string.format("%s,%s\n", date_str, action))
        end
        csv_file:close()
        return true
    end
    return false
end

-- Load CSV schedule from file
function load_csv_schedule()
    local schedule = {}
    local csv_file = io.open("/etc/wifi_schedule.csv", "r")
    if csv_file then
        local content = csv_file:read("*all")
        csv_file:close()
        
        schedule = parse_csv_schedule(content)
    end
    return schedule
end

-- Get schedule for a specific date considering priority: External API response (via schedule_type) > CSV > other schedules
function get_schedule_for_date(date_str)
    -- First check CSV schedule (high priority, but lower than API if API determines special schedule)
    local csv_schedule = load_csv_schedule()
    if csv_schedule[date_str] then
        return {action = csv_schedule[date_str], source = "csv"}
    end
    
    -- Then check based on schedule type (workday/weekend/holiday), which now includes API results
    local schedule_type = get_schedule_type(date_str)
    
    -- Get configuration from UCI for the specific schedule type
    local uci_section = "global"
    local start_time, stop_time
    
    if schedule_type == "workday" then
        start_time = uci:get("wifi_schedule", uci_section, "workday_starttime")
        stop_time = uci:get("wifi_schedule", uci_section, "workday_stoptime")
    elseif schedule_type == "weekend" then
        start_time = uci:get("wifi_schedule", uci_section, "weekend_starttime") 
        stop_time = uci:get("wifi_schedule", uci_section, "weekend_stoptime")
    elseif schedule_type == "holiday" then
        start_time = uci:get("wifi_schedule", uci_section, "holiday_starttime")
        stop_time = uci:get("wifi_schedule", uci_section, "holiday_stoptime")
    end
    
    -- Fallback to regular schedule if specific schedule type is not configured
    if not start_time or not stop_time then
        start_time = uci:get("wifi_schedule", uci_section, "starttime") or "06:00"
        stop_time = uci:get("wifi_schedule", uci_section, "stoptime") or "22:00"
    end
    
    return {
        action = nil, -- Will be determined based on current time vs start/stop
        source = schedule_type,
        starttime = start_time,
        stoptime = stop_time
    }
end

-- Get current date in the proper format considering timezone
function get_current_date()
    -- Get current date in YYYY-MM-DD format
    return os.date("%Y-%m-%d")
end

-- Get current time in HH:MM format considering timezone
function get_current_time()
    -- Get current time in HH:MM format
    return os.date("%H:%M")
end

-- Initialize by loading any custom calendars
load_custom_holidays()