-- Automated Energy Generation Inspection System
-- By Inky19
-- Repository:
-- Under GPLv3 license (see LICENSE)
local VERSION = "1.0.0"

term.clear()
local UI = require("ui")
local Log = require("lib/logger")

--------------------------------
---- Local script variables ----
--------------------------------

-- The state of each log event during the last cycle.
-- This is used to detect rising edge to only log the information once.
local logEventState = {
    alerts = {
        temperature = false,
        damage = false,
        coolant = false,
        heatedCoolant = false,
        waste = false,
        fuel = false
    },
    limits = {
        temperature = false,
        damage = false,
        coolant = false,
        heatedCoolant = false,
        waste = false,
        fuel = false
    }
}
-- The state of the reactor during the last cycle.
local reactorActivated = nil;

-- Directory of the AEGIS installation.
local dirPath = shell.getRunningProgram():match("(.*)/[^/]*$")

-- Configuration
local config = {}

-- Peripherals
local logMonitor
local uiMonitor
local alarmRelay
local reactor

--------------------------------
---- Local script functions ----
--------------------------------

--- Loads and parses the JSON configuration file.
--- @return table|nil config A table representation of the config file or `nil` in case of error.
local function loadConfig ()
    local configFile = io.open(shell.dir() .. "/config.json", "r")
    if configFile == nil then
        Log:error("Failed to load config file.")
        return nil
    end
    local config, err = textutils.unserialiseJSON(configFile:read("a"))
    if config == nil then
        Log:error("Failed to parse config file:\n" .. err)
    end
    configFile:close()
    Log:debug("Parsed config file successfully")
    return config
end

--- Tries to load the reactor and sets up the UI if successful.
--- This is used to workaround the reactor's chunk being loaded after the computer and thus the reactor being not found.
local function getReactor()
    reactor = peripheral.wrap(config.reactor)
    UI.drawUI()
    if (reactor ~= nil) and (reactor.getStatus ~= nil) then
        UI.setup(reactor)
        reactorActivated = reactor.getStatus()
    end
    UI.drawConsole()
end

--- Checks a condition and logs a message.
--- The log will only be generated if the condition didn't already occured during the last cycle. 
--- @param condition boolean The condition to check.
--- @param level string Log event level ("alerts" or "limits")
--- @param logLevel Log.Level The level of log to use.
--- @param messageEventStart string The message to log when at a rising edge of the event (first cycle when the condition is true).
--- @param messageEventDone string The message to log when at a falling edge of the event (first cycle when the condition is back to false).
--- @param component string The name of the log component in the log event state.
--- @return boolean condition Returns the same value as the input condition.
local function checkLogEvent(condition, level, logLevel, messageEventStart, messageEventDone, component)
    if condition and not logEventState[level][component] then
        logEventState[level][component] = true
        if logLevel == Log.Level.Debug then
            Log:debug(messageEventStart)
        elseif logLevel == Log.Level.Info then
            Log:info(messageEventStart)
        elseif logLevel == Log.Level.Warning then
            Log:warning(messageEventStart)
        elseif logLevel == Log.Level.Error then
            Log:error(messageEventStart)
        end
    elseif (not condition) and logEventState[level][component] then
        logEventState[level][component] = false
        Log:info(messageEventDone)
    end
    return condition
end

--- Checks an alerts condition.
--- @param condition boolean The condition to check.
--- @param messageStart string The message to log when at a rising edge of the event (first cycle when the condition is true).
--- @param messageDone string The message to log when at a falling edge of the event (first cycle when the condition is back to false).
--- @param component string The name of the log component in the log event state.
--- @return boolean condition Returns the same value as the input condition.
local function checkAlert(condition, messageStart, messageDone, component)
    return checkLogEvent(condition, "alerts", Log.Level.Warning, messageStart, messageDone, component)
end
--- Checks a limit condition.
--- @param condition boolean The condition to check.
--- @param messageStart string The message to log when at a rising edge of the event (first cycle when the condition is true).
--- @param messageDone string The message to log when at a falling edge of the event (first cycle when the condition is back to false).
--- @param component string The name of the log component in the log event state.
--- @return boolean condition Returns the same value as the input condition.
local function checkLimit(condition, messageStart, messageDone, component)
    return checkLogEvent(condition, "limits", Log.Level.Error, messageStart, messageDone, component)
end

--- Checks if the reactor is operating inside safety margins.
--- Triggers alerts and shutdown if necessary.
local function checkReactor()
    local temperature = reactor.getTemperature()
    local damage = reactor.getDamagePercent()
    local coolantPercentage = reactor.getCoolantFilledPercentage()
    local heatedCoolantPercentage = reactor.getHeatedCoolantFilledPercentage()
    local wastePercentage = reactor.getWasteFilledPercentage()
    local fuelPercentage = reactor.getFuelFilledPercentage()

    local temperatureAlert = checkAlert(temperature > config.alerts.temperature, "Excessive reactor core temperature", "Reactor core temperature back to expected range", "temperature")
    local damageAlert = checkAlert(damage > config.alerts.damage, "Excessive reactor core damage", "Reactor core repaired", "damage")
    local coolantAlert = checkAlert(coolantPercentage < config.alerts.coolant, "Low coolant level in reactor", "Reactor coolant back to safety level","coolantPercentage")
    local heatedCoolantAlert = checkAlert(heatedCoolantPercentage > config.alerts.heatedCoolant, "Excessive heated coolant in reactor core", "Heated coolant excess drained from reactor core", "heatedCoolant")
    local wasteAlert = checkAlert(wastePercentage > config.alerts.waste, "Excessive nuclear waste level in reactor core", "Nuclear waste excess drained from reactor core", "waste")
    local fuelAlert = checkAlert(fuelPercentage < config.alerts.fuel, "Low fuel level in ractor", "Reactor fuel back to safety level","fuel")
    if temperatureAlert or damageAlert or coolantAlert or heatedCoolantAlert or wasteAlert or fuelAlert then
        alarmRelay.setOutput(config.alarmRelay.side, true)
    else
        alarmRelay.setOutput(config.alarmRelay.side, false)
    end

    local temperatureLimit = checkLimit(temperature > config.limits.temperature, "Critical reactor core temperature", "Reactor core temperature back to non critical range", "temperature")
    local damageLimit = checkLimit(damage > config.limits.damage, "Critical reactor core damage", "Reactor core damage back to non critical", "damage")
    local coolantLimit = checkLimit(coolantPercentage < config.limits.coolant, "Critical coolant level in reactor", "Reactor coolant back to non critical level","coolantPercentage")
    local heatedCoolantLimit = checkLimit(heatedCoolantPercentage > config.limits.heatedCoolant, "Critical heated coolant in reactor core", "Heated coolant excess back to non critical", "heatedCoolant")
    local wasteLimit = checkLimit(wastePercentage > config.limits.waste, "Critical nuclear waste level in reactor core", "Nuclear waste excess back to non critical", "waste")
    local fuelLimit = checkLimit(fuelPercentage < config.limits.fuel, "Critical fuel level in ractor", "Reactor fuel back to non critical level","fuel")

    local reactorStatus = reactor.getStatus()
    if temperatureLimit or damageLimit or coolantLimit or heatedCoolantLimit or wasteLimit or fuelLimit then
        UI:setState(UI.State.HI)
        if reactorStatus then
            Log:warning("Automatic reactor shutdown")
            reactor.scram()
        end
    end
    if reactorStatus ~= reactorActivated then
        UI.drawConsole()
        if reactorStatus then
            Log:info("External activation of reactor.")
        else
            Log:info("External shutdown of reactor.")
        end
        reactorActivated = reactorStatus
    end
end

--------------------------------
---- Initialization script  ----
--------------------------------

shell.setDir(dirPath)

-- Logs
Log:init(dirPath .. "/logs", 86400, 10)
config = loadConfig()
if config == nil then
    print("Error: Failed to load config.json. Aborting AEGIS startup.")
    return
end
Log:setMaxFiles(config.logs.maxFiles)
Log:setRotationPeriodSeconds(config.logs.fileDurationSeconds)

-- Monitors
config.version = VERSION
logMonitor = peripheral.wrap(config.logMonitor.name);
logMonitor.setTextScale(config.logMonitor.scale)
Log:setTerminal(logMonitor)
uiMonitor = peripheral.wrap(config.uiMonitor.name)

-- Startup animation
UI.init(uiMonitor, config, Log)
UI.splash()

-- Redstone alarm
getReactor()
alarmRelay = peripheral.wrap(config.alarmRelay.name)
alarmRelay.setOutput(config.alarmRelay.side, false)

Log:info("AEGIS startup complete.")

--------------------------------
----       Main loop        ----
--------------------------------

local function mainLoop()
    while true do
        local returnCheck, errCheck = pcall(checkReactor)
        if (not returnCheck) then
            Log:warning("Skipped cycle due to check routine failure.")
            Log:debug(errCheck)
        end
        local returnUi, errUi = pcall(UI.drawUI)
        if (not returnUi) then
            Log:warning("UI failed to refresh due to routine failure.")
            Log:debug(errUi)
        end
        if (not returnCheck) or (not returnUi) then
            getReactor()
        end
        sleep(1)
    end
end

--------------------------------
----      Exit script       ----
--------------------------------

parallel.waitForAny(mainLoop, UI.handleConsoleInput)
Log:info("Exiting AEGIS")
uiMonitor.clear()
logMonitor.clear()
term.clear()
alarmRelay.setOutput(config.alarmRelay.side, false)
return