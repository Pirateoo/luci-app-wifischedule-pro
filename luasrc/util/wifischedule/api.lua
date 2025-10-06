-- API module for wifi schedule app
-- Provides endpoints for retrieving current status and scheduling info

module("luci.util.wifischedule.api", package.seeall)

local uci = require "luci.model.uci".cursor()
local calendar = require "luci.util.wifischedule.calendar"

-- Get current status
function get_current_status()
    local date = os.date("%Y-%m-%d")
    local time = os.date("%H:%M")
    
    local schedule = calendar.get_schedule_for_date(date)
    
    -- Determine if WiFi should be on or off based on current time vs schedule
    local current_status = "unknown"
    local is_enabled = uci:get("wifi_schedule", "global", "enabled")
    
    if is_enabled ~= "1" then
        current_status = "disabled"
    else
        if schedule.source == "csv" then
            -- For CSV schedules, status is determined by the CSV entry
            current_status = schedule.action
        else
            -- For regular schedules, check if current time falls within the schedule window
            local start_time = schedule.starttime or "06:00"
            local stop_time = schedule.stoptime or "22:00"
            
            if time_in_range(time, start_time, stop_time) then
                current_status = "enabled"
            else
                current_status = "disabled"
            end
        end
    end
    
    return {
        date = date,
        time = time,
        status = current_status,
        schedule_source = schedule.source,
        schedule = schedule
    }
end

-- Check if current time falls within the start-stop range
function time_in_range(current_time, start_time, stop_time)
    -- Parse time strings (HH:MM format)
    local curr_h, curr_m = current_time:match("(%d%d):(%d%d)")
    local start_h, start_m = start_time:match("(%d%d):(%d%d)")
    local stop_h, stop_m = stop_time:match("(%d%d):(%d%d)")
    
    curr_h, curr_m = tonumber(curr_h), tonumber(curr_m)
    start_h, start_m = tonumber(start_h), tonumber(start_m)
    stop_h, stop_m = tonumber(stop_h), tonumber(stop_m)
    
    -- Convert to total minutes since midnight for comparison
    local curr_total = curr_h * 60 + curr_m
    local start_total = start_h * 60 + start_m
    local stop_total = stop_h * 60 + stop_m
    
    -- Handle case where stop time is next day (e.g. 23:00 to 06:00)
    if stop_total < start_total then
        -- Overnight schedule
        return curr_total >= start_total or curr_total <= stop_total
    else
        -- Normal schedule (same day)
        return curr_total >= start_total and curr_total <= stop_total
    end
end

-- Get schedule for specific date
function get_schedule_for_date(date_str)
    -- Validate date format
    local year, month, day = date_str:match("(%d%d%d%d)%-(%d%d)%-(%d%d)")
    if not year then
        return {error = "Invalid date format. Use YYYY-MM-DD."}
    end
    
    local schedule = calendar.get_schedule_for_date(date_str)
    local date_type = calendar.get_schedule_type(date_str)
    
    return {
        date = date_str,
        date_type = date_type,  -- workday, weekend, holiday, or determined by API
        schedule = schedule,
        schedule_source = schedule.source
    }
end

-- Get all available regions for calendar settings
function get_available_regions()
    return {
        china = "China",
        us = "United States", 
        eu = "European Union",
        custom = "Custom"
    }
end

-- Get current configuration
function get_current_config()
    return {
        holiday_api_url = uci:get("wifi_schedule", "global", "holiday_api_url"),
        holiday_api_region = uci:get("wifi_schedule", "global", "holiday_api_region"),
        holiday_api_country = uci:get("wifi_schedule", "global", "holiday_api_country"),
        holiday_api_language = uci:get("wifi_schedule", "global", "holiday_api_language"),
        region = uci:get("wifi_schedule", "global", "region") or "custom"
    }
end

-- Check if a specific date is a holiday in a specific region via external API
function is_holiday_external(date_str, region)
    -- Use the calendar module's function which handles API calls
    local calendar = require "luci.util.wifischedule.calendar"
    
    -- Temporarily set the region for this check
    local original_region = uci:get("wifi_schedule", "global", "region")
    uci:set("wifi_schedule", "global", "holiday_api_region", region or original_region)
    
    local is_holiday, holiday_name = calendar.is_holiday_via_api(date_str)
    
    -- Restore original region if needed
    if original_region then
        uci:set("wifi_schedule", "global", "region", original_region)
    end
    
    if is_holiday ~= nil then
        return {
            is_holiday = is_holiday,
            name = holiday_name,
            date = date_str,
            region = region
        }
    else
        -- Return nil if API is not configured or failed
        return {
            is_holiday = nil,
            error = "Holiday API not configured or failed",
            date = date_str,
            region = region
        }
    end
end

-- Get today's schedule
function get_today_schedule()
    local today = os.date("%Y-%m-%d")
    return get_schedule_for_date(today)
end