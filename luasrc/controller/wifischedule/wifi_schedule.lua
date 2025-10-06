-- Copyright (c) 2016, prpl Foundation
--
-- Permission to use, copy, modify, and/or distribute this software for any purpose with or without
-- fee is hereby granted, provided that the above copyright notice and this permission notice appear
-- in all copies.
--
-- THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES WITH REGARD TO THIS SOFTWARE
-- INCLUDING ALL IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE
-- FOR ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM
-- LOSS OF USE, DATA OR PROFITS, WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION,
-- ARISING OUT OF OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
--
-- Author: Nils Koenig <openwrt@newk.it>
-- Enhanced by: Assistant for multi-region and CSV support

module("luci.controller.wifischedule.wifi_schedule", package.seeall)  

function index()
     entry({"admin", "wifi_schedule"}, firstchild(), "Wifi Schedule", 60).dependent=false  
     entry({"admin", "wifi_schedule", "tab_from_cbi"}, cbi("wifischedule/wifi_schedule"), "Schedule", 1)
     entry({"admin", "wifi_schedule", "wifi_schedule"}, call("wifi_schedule_log"), "View Logfile", 2) 
     entry({"admin", "wifi_schedule", "cronjob"}, call("view_crontab"), "View Cron Jobs", 3) 
     
     -- API endpoints
     entry({"admin", "wifi_schedule", "api"}, call("api_handler"), nil, 4)
     entry({"admin", "wifi_schedule", "upload_csv"}, call("upload_csv"), nil, 5)
end

function api_handler()
    local api = require "luci.util.wifischedule.api"
    local uci = require "luci.model.uci".cursor()
    
    local action = luci.http.formvalue("action")
    
    luci.http.prepare_content("application/json")
    
    if action == "get_current_status" then
        luci.http.write_json(api.get_current_status())
    elseif action == "get_schedule_for_date" then
        local date = luci.http.formvalue("date") or os.date("%Y-%m-%d")
        luci.http.write_json(api.get_schedule_for_date(date))
    elseif action == "get_today_schedule" then
        luci.http.write_json(api.get_today_schedule())
    elseif action == "get_available_regions" then
        luci.http.write_json(api.get_available_regions())
    elseif action == "is_holiday_external" then
        local date = luci.http.formvalue("date") or os.date("%Y-%m-%d")
        local region = luci.http.formvalue("region")
        luci.http.write_json(api.is_holiday_external(date, region))
    elseif action == "get_current_config" then
        luci.http.write_json(api.get_current_config())
    elseif action == "update_api_config" then
        -- Verify token for security
        local token = luci.http.formvalue("token")
        if not token or token ~= luci.dispatcher.context.xsrf_token then
            luci.http.status(403, "Forbidden")
            luci.http.write_json({error = "Invalid token"})
            return
        end
        
        -- Update API configuration
        local holiday_api_url = luci.http.formvalue("holiday_api_url")
        local holiday_api_key = luci.http.formvalue("holiday_api_key")
        local holiday_api_region = luci.http.formvalue("holiday_api_region")
        local holiday_api_country = luci.http.formvalue("holiday_api_country")
        local holiday_api_language = luci.http.formvalue("holiday_api_language")
        
        -- Validate inputs
        if holiday_api_url ~= "" and not holiday_api_url:match("^https?://") then
            luci.http.write_json({error = "API URL must start with http:// or https://"})
            return
        end
        
        -- Update UCI values
        uci:set("wifi_schedule", "global", "holiday_api_url", holiday_api_url or "")
        if holiday_api_key and holiday_api_key ~= "" then
            uci:set("wifi_schedule", "global", "holiday_api_key", holiday_api_key)
        else
            uci:delete("wifi_schedule", "global", "holiday_api_key")
        end
        uci:set("wifi_schedule", "global", "holiday_api_region", holiday_api_region or "")
        if holiday_api_country and holiday_api_country ~= "" then
            uci:set("wifi_schedule", "global", "holiday_api_country", holiday_api_country)
        else
            uci:delete("wifi_schedule", "global", "holiday_api_country")
        end
        if holiday_api_language and holiday_api_language ~= "" then
            uci:set("wifi_schedule", "global", "holiday_api_language", holiday_api_language)
        else
            uci:delete("wifi_schedule", "global", "holiday_api_language")
        end
        
        -- Save changes
        uci:commit("wifi_schedule")
        
        luci.http.write_json({success = true, message = "API configuration updated successfully"})
    else
        luci.http.write_json({error = "Invalid action"})
    end
end

function upload_csv()
    local calendar = require "luci.util.wifischedule.calendar"
    
    -- Check if this is a POST request with file upload
    if luci.http.getenv("REQUEST_METHOD") == "POST" then
        -- Get uploaded file content
        local fp
        local filename
        luci.http.setfilehandler(
            function(meta, chunk, eof)
                if not fp and meta and meta.name == "csv_file" then
                    filename = meta.file
                    fp = io.open("/tmp/wifi_schedule_upload.csv", "w")
                end
                if fp and chunk then
                    fp:write(chunk)
                end
                if fp and eof then
                    fp:close()
                end
            end
        )
        
        -- Process the uploaded file
        local file = io.open("/tmp/wifi_schedule_upload.csv", "r")
        if file then
            local uploaded_content = file:read("*all")
            file:close()
            
            -- Parse and store the CSV schedule
            local schedule = calendar.parse_csv_schedule(uploaded_content)
            
            if calendar.store_csv_schedule(schedule) then
                -- Render success page with redirect
                luci.template.render("wifischedule.csv_upload", {message = "CSV file uploaded and processed successfully", message_type = "success"})
            else
                -- Render error page
                luci.template.render("wifischedule.csv_upload", {message = "Error saving CSV schedule", message_type = "error"})
            end
        else
            -- Render error page
            luci.template.render("wifischedule.csv_upload", {message = "Error reading uploaded file", message_type = "error"})
        end
        
        -- Clean up temporary file
        os.remove("/tmp/wifi_schedule_upload.csv")
    else
        -- Show upload form
        luci.template.render("wifischedule.csv_upload")
    end
end

function wifi_schedule_log()
        local logfile = luci.sys.exec("cat /tmp/log/wifi_schedule.log")
        luci.template.render("wifischedule/file_viewer", {title="Wifi Schedule Logfile", content=logfile})
end

function view_crontab()
        local crontab = luci.sys.exec("cat /etc/crontabs/root")
        luci.template.render("wifischedule/file_viewer", {title="Cron Jobs", content=crontab})
end
