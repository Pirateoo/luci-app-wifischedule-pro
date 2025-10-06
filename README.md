## luci-app-wifischedule-pro
Turns WiFi on and off according to a schedule on an openwrt router

## Components
* wifischedule: Shell script that creates cron jobs based on configuration provided in UCI and does all the other logic of enabling and disabling wifi with the use of `/sbin/wifi` and `/usr/bin/iwinfo`. Can be used standalone.
* luci-app-wifischedule: LUCI frontend for creating the UCI configuration and triggering the actions. Depends on wifischedule.


## Enhanced Features
This enhanced version includes additional features:

### CSV Scheduling Support
- Upload CSV files with specific date and action pairs to override regular schedules
- Format: `date,action` with supported date formats (YYYY-MM-DD, MM/DD/YYYY, DD/MM/YYYY)
- Actions: `enable`/`on`/`start` or `disable`/`off`/`stop`

### Multi-Region Holiday Calendar Support
- Predefined holiday calendars for China, United States, and European Union
- Support for custom holiday calendars
- Automatic detection of workdays vs holidays based on region

### Workday/Weekend/Holiday Scheduling
- Separate time schedules for workdays, weekends, and holidays
- Priority-based scheduling system (External API > CSV > Holiday > Weekend > Workday > Regular)

### External Holiday API Support
- Configure external API endpoint to check for holidays in specific regions
- Support for popular holiday APIs with configurable URL templates
- API key support for services requiring authentication
- Support for localized holiday names in multiple languages (including Chinese)
- Fallback to CSV/uploaded calendar if API is unavailable

### CSV Scheduling Support
- Upload CSV files with specific date and action pairs to override regular schedules
- Format: `date,action` with supported date formats (YYYY-MM-DD, MM/DD/YYYY, DD/MM/YYYY)
- Actions: `enable`/`on`/`start` or `disable`/`off`/`stop`

### API Endpoints
- JSON API for getting current status and schedule information
- Endpoints for external integration

### Timezone Support
- Timezone-aware scheduling respecting local time

## Use Cases
You can create user-defined events when to enable or disable WiFi. 
There are various use cases why you would like to do so:

1. Reduce power consumption and therefore reduce CO2 emissions.
2. Reduce emitted electromagnatic radiation.
3. Force business hours when WiFi is available.
4. Region-specific scheduling based on local holidays and work patterns.

Regarding 1: Please note, that you need to unload the wireless driver modules in order to get the most effect of saving power.
In my test scenario only disabling WiFi saves about ~0.4 Watt, unloading the modules removes another ~0.4 Watt.

Regarding 2: Think of a wireless accesspoint e.g. in your bedroom, kids room where you want to remove the ammount of radiation emitted.

Regarding 3: E.g. in a company, why would wireless need to be enabled weekends if no one is there working? 
Or think of an accesspoint in your kids room when you want the youngsters to sleep after 10 pm instead of facebooking...

## Configuration
You can create an arbitrary number of schedule events. Please note that there is on sanity check done wheather the start / stop times overlap or make sense.
If start and stop time are equal, this leads to disabling the WiFi at the given time.

Logging if enabled is done to the file `/var/log/wifi_schedule.log` and can be reviewed through the "View Logfile" tab.
The cron jobs created can be reviewed through the "View Cron Jobs" tab.

Please note that the "Unload Modules" function is currently considered as experimental. You can manually add / remove modules in the text field.
The button "Determine Modules Automatically" tries to make a best guess determining regarding the driver module and its dependencies.
When un-/loading the modules, there is a certain number of retries (`module_load`) performed.

The option "Force disabling wifi even if stations associated" does what it says - when activated it simply shuts down WiFi.
When unchecked, its checked every `recheck_interval` minutes if there are still stations associated. Once the stations disconnect, WiFi is disabled.

Please note, that the parameters `module_load` and `recheck_interval` are only accessible through uci.

## Enhanced UCI Configuration `wifi_schedule`
Enhanced UCI configuration file: `/etc/config/wifi_schedule`:

```
config global
        option logging '0'
        option enabled '0'
        option region 'china'  # Region for holiday calendar (china/us/eu/custom)
        option workday_starttime '06:00'  # Workday start time
        option workday_stoptime '22:00'   # Workday stop time
        option weekend_starttime '08:00'  # Weekend start time
        option weekend_stoptime '23:00'   # Weekend stop time
        option holiday_starttime '09:00'  # Holiday start time
        option holiday_stoptime '21:00'   # Holiday stop time
        option holiday_api_url ''         # URL for external holiday API, e.g., https://date.nager.at/api/v3/IsTodayPublicHoliday/{region}?date={date}
        option holiday_api_key ''         # API key if required
        option holiday_api_region 'US'    # Region code used by the holiday API (overrides 'region' for API calls)
        option holiday_api_country ''     # Country code parameter for APIs that use 'country' instead of 'region'
        option holiday_api_language 'en'  # Language code for localized holiday names (e.g., en, de, fr)
        option recheck_interval '10'
        option modules_retries '10'

config entry 'Businesshours'
        option enabled '0'
        option daysofweek 'Monday Tuesday Wednesday Thursday Friday'
        option starttime '06:00'
        option stoptime '22:00'
        option forcewifidown '0'

config entry 'Weekend'
        option enabled '0'
        option daysofweek 'Saturday Sunday'
        option starttime '00:00'
        option stoptime '00:00'
        option forcewifidown '1'
```

## API Endpoints
The enhanced application provides JSON API endpoints:

- `GET /admin/wifi_schedule/api?action=get_current_status` - Get current WiFi status
- `GET /admin/wifi_schedule/api?action=get_schedule_for_date&date=YYYY-MM-DD` - Get schedule for specific date
- `GET /admin/wifi_schedule/api?action=get_today_schedule` - Get schedule for today
- `GET /admin/wifi_schedule/api?action=get_available_regions` - Get available regions
- `GET /admin/wifi_schedule/api?action=is_holiday_external&date=YYYY-MM-DD&region=REGION` - Check if date is a holiday via external API
- `GET /admin/wifi_schedule/api?action=get_current_config` - Get current API configuration
- `POST /admin/wifi_schedule/api?action=update_api_config` - Update API configuration (requires token)

## External Holiday API Configuration
Configure external holiday API services using the following URL template formats:
- Nager.Date API: `https://date.nager.at/api/v3/PublicHoliday/{date}/{region}`
- Alternative: `https://date.nager.at/api/v3/IsTodayPublicHoliday/{region}?date={date}`
- Custom API: `https://your-api.com/holidays?date={date}&country={country}&lang={language}`
- Chinese holidays API: `https://some-chinese-holiday-api.com/holidays?date={date}&country=CN&lang=zh`
- Use `{date}`, `{region}`, `{country}`, and `{language}` as placeholders in your API URLs

The system can handle various JSON response formats:
- Standard format: `{ "date": "2025-01-01", "name": "New Year", "localName": "Neujahr" }`
- Chinese format: `{ "date": "2025-02-10", "name": "Spring Festival", "chineseName": "春节" }`
- Array format: `[ { "date": "2025-10-01", "name": "National Day", "chineseName": "国庆节" } ]`

## CSV Upload Format
Upload CSV files through the UI with the format:
```
date,action
2025-01-01,disable
2025-12-25,disable
2025-07-04,disable
```

## Priority Order
The scheduling system follows this priority order (highest to lowest):
1. External Holiday API results
2. CSV Upload Schedule 
3. Predefined Holiday Calendar
4. Weekend Schedule
5. Workday Schedule
6. Default Schedule

## Script: `wifi_schedule.sh`
This is the script that does the work. Make your changes to the UCI config file: `/etc/config/wifi_schedule`

Then call the script as follows in order to get the necessary cron jobs created:

`wifi_schedule.sh cron`

All commands:

```
wifi_schedule.sh cron|start|stop|forcestop|recheck|getmodules|savemodules|help

    cron: Create cronjob entries.
    start: Start wifi.
    stop: Stop wifi gracefully, i.e. check if there are stations associated and if so keep retrying.
    forcestop: Stop wifi immediately.
    recheck: Recheck if wifi can be disabled now.
    getmodules: Returns a list of modules used by the wireless driver(s)
    savemodules: Saves a list of automatic determined modules to UCI
    help: This description.
```
