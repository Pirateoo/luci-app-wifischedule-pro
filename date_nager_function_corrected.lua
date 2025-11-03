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
    
    -- Extract year from date_str for date.nager.at API (format: YYYY-MM-DD)
    local year, month, day = date_str:match("(%d+)-(%d+)-(%d+)")
    if not year then
        return nil  -- Invalid date format
    end
    
    -- Check if this is a date.nager.at API URL and handle it specifically
    if api_url:match("date%.nager%.at") then
        -- Format date.nager.at API URL - this API returns holidays for the whole year
        -- For the date.nager.at API, use the PublicHolidays endpoint which returns an array of holidays for the year
        local country_code = api_country or api_region or "US"  -- Use api_country first, then api_region, then default to US
        local nager_url = "https://date.nager.at/api/v3/PublicHolidays/" .. year .. "/" .. country_code
        
        -- Prepare cURL command for making the HTTP request
        local cmd = "curl -s -m 10 \"" .. nager_url .. "\""
        
        local result = sys.exec(cmd)
        
        if result and result ~= "" then
            -- Try to parse as JSON
            if jsonc then
                local parsed = jsonc.parse(result)
                if parsed and type(parsed) == "table" then
                    -- The date.nager.at API returns an array of holiday objects
                    -- Each object has: date, localName, name, countryCode, fixed, global, counties, launchYear, types
                    for _, holiday in ipairs(parsed) do
                        if holiday.date == date_str then
                            -- This date is a holiday
                            return true, holiday.localName or holiday.name or "Public Holiday"
                        end
                    end
                    -- Date not found in holidays, so it's not a holiday
                    return false, "Not a public holiday"
                end
            end
        end
        
        -- If date.nager.at API fails, return nil to use fallback
        return nil
    end
    
    -- Format the API URL with various parameters for non-date.nager.at APIs
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
                                return true, holiday.name or holiday.localName or holiday.englishName or holiday.chineseName or holiday.local_name or parsed.description or "Holiday"
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