--- Logging system
local Logger = {}

--------------------------------
----         Enums          ----
--------------------------------

Logger.Level = {
    Debug = {},
    Info = {},
    Warning = {},
    Error = {}
}

--------------------------------
---- Local script variables ----
--------------------------------

local lastFileCreated = 0
local logFile = nil

--------------------------------
---- Local script functions ----
--------------------------------

--- Checks the age of the current log file and creates a new one if necessary.
--- Deletes old log files if the number of files is above the maximum allowed.
local function updateFile()
    local currentTime = os.epoch("utc") / 1000
    local files = fs.list(Logger.logDirectory)
    if #files > Logger.maxFiles then
        local excess = #files - Logger.maxFiles
        for i = 1, excess do
            fs.delete(Logger.logDirectory .. files[i])
            Logger:info("Deleted old log file: " .. files[i])
        end
    end
    if ((currentTime - lastFileCreated) > Logger.rotationPeriodSeconds) then
        if logFile ~= nil then
            logFile.close()
        end
        logFile = fs.open(Logger.logDirectory .. os.date("%Y-%m-%d_%H%M%S") ..".log", "w")
        lastFileCreated = currentTime
    end
end

--- Prints a message on the log terminal.
--- @param message string The message to log.
--- @param color color The text color.
local function printOnTerminal(message, color)
    Logger.terminal.setTextColor(color)
    local _, cursorY = Logger.terminal.getCursorPos()
    local _, termHeight = Logger.terminal.getSize()
    if cursorY > termHeight then
        Logger.terminal.scroll(1)
        Logger.terminal.setCursorPos(1, termHeight)
    end
    Logger.terminal.write(message)
    Logger.terminal.setCursorPos(1, cursorY + 1)
end

--- Adds a new log in the log file and the log terminal.
--- @param newLog string The message to log.
--- @param color color The text color for the terminal.
local function log(newLog, color)
    updateFile()
    local logLine = os.date("%Y-%m-%d %T") .. " " .. newLog .. "\n"
    logFile.write(logLine)
    if Logger.terminal ~= nil then
        printOnTerminal(newLog .. "\n", color)
    end
end

--------------------------------
----     Public methods     ----
--------------------------------

--- Initializes the logger.
--- @param logDirectory string Path to the log directory.
--- @param rotationPeriodSeconds number Maximum duration of a log file (in seconds).
--- @param maxFiles number Maximum number of old log files.
function Logger:init(logDirectory, rotationPeriodSeconds, maxFiles)
    logDirectory = logDirectory .. "/"
    if not fs.exists(logDirectory) then
        fs.makeDir(logDirectory)
    end
    self.logDirectory = logDirectory
    self.rotationPeriodSeconds = rotationPeriodSeconds
    self.maxFiles = maxFiles
    updateFile()
end

--- Sets the rotation period of log files.
--- @param rotationPeriodSeconds number The maximum duration of a log file (in seconds).
function Logger:setRotationPeriodSeconds(rotationPeriodSeconds)
    self.rotationPeriodSeconds = rotationPeriodSeconds
end

--- Sets the number of kept log files.
--- @param maxFiles number Maximum number of old log files.
function Logger:setMaxFiles(maxFiles)
    self.maxFiles = maxFiles
end

--- Sets the terminal to use to display logs.
--- @param terminal table The terminal to use.
function Logger:setTerminal(terminal)
    self.terminal = terminal
    terminal.clear()
    terminal.setCursorPos(1, 1)
end

--- Logs a new error message.
--- @param message string The error to log.
function Logger:error(message)
    log("[ERROR] " .. message, colors.red)
end

--- Logs a new warning message.
--- @param message string The warning to log.
function Logger:warning(message)
    log("[WARNING] " .. message, colors.orange)
end

--- Logs a new information message.
--- @param message string The information to log.
function Logger:info(message)
    log("[INFO] " .. message, colors.blue)
end

--- Logs a new debug message.
--- @param message string The debug message to log.
function Logger:debug(message)
    log("[DEBUG] " .. message, colors.gray)
end

return Logger