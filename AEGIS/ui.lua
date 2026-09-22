--- AEGIS UI
local Gfx = require("lib/gfx")
local Utils = require("lib/utils")
local UI = {}

--------------------------------
----         Enums          ----
--------------------------------

--- Type of visual message. 
UI.MessageType = {
    Unknown = {},
    Warning = {}
}

--- Possible state of the reactor.
UI.State = {
    Active = {}, -- Activated
    Idle = {},   -- Stopped by external intervention   
    HI = {}      -- (Human Investigate) Automatically stopped after an emergency and requires manual activation
}

--------------------------------
---- Local script variables ----
--------------------------------

local currentMessage = {}
local messageLayout
local needClearing = true
local alerts
local state

local icons = {}
local version = ""

local reactorSize = {
    width = 1,
    length = 1
}

local reactor

local reactorSurface
local informationSurface
local statusSurface
local lastFrameBlink = false
local alertActivated = false

local uiTerminal
local consoleTerminal
local consoleLayout
local startButton
local stopButton
local quitButton

local Log

--------------------------------
---- Local script functions ----
--------------------------------

--- Draws the reactor diagram.
--- @param reactor table The reactor peripheral.
local function drawReactorDiagram(reactor)
    reactorSurface:clear()
    local line = {}
    local waterTexel = Gfx.Texel(colors.gray, colors.black, "\x7F")
    local coolantPercentage = reactor.getCoolantFilledPercentage();
    if (coolantPercentage > 0) and (coolantPercentage < 0.5) then
        waterTexel = Gfx.Texel(colors.black, colors.blue, "\x7F")
    elseif coolantPercentage > 0.5 then
        waterTexel = Gfx.Texel(colors.cyan, colors.blue, "\x7F")
    end
    local rodTexel
    if reactor.getStatus() then
        rodTexel = Gfx.Texel(colors.green, colors.gray, "\x07")
    else
        rodTexel = Gfx.Texel(colors.lightGray, colors.gray, "\x07")
    end
    local columnSize = math.floor((reactorSurface.width - 2) / reactorSize.width)
    for i=0, reactorSize.length - 1 do
        line = {}
        for j=0, reactorSize.width - 1 do
            local columnTexel
            if (i + j) % 2 == 0 then
                columnTexel = rodTexel
            else
                columnTexel = waterTexel
            end
            for _ = 1, columnSize do
                table.insert(line, columnTexel)
            end
        end
        for _ = 1, columnSize do
            reactorSurface:addLine(line)
        end
    end
    reactorSurface:draw()
end

--- Draws the status indicator below the reactor diagram.
local function drawStatus()
    local blinking = false
    local message = ""
    local color = colors.black
    if state == UI.State.Idle then
        blinking = false
        message = " IDLE "
        color = colors.yellow
    elseif state == UI.State.Active then
        blinking = true
        message = "ACTIVE"
        color = colors.green
    elseif state == UI.State.HI then
        blinking = true
        message = "  HI  "
        color = colors.red
    end
    local blinkingFrame = blinking and not lastFrameBlink
    statusSurface:clear()
    local paddingSize = (statusSurface.width - message:len()) / 2
    local textColor = color
    local backgroundColor = colors.black
    if blinkingFrame then
        textColor, backgroundColor = colors.white, textColor
    end
    local padding = Gfx.TextToTexels(uiTerminal.terminal, string.rep(" ", paddingSize))
    local upperBorder = Gfx.TextToTexels(uiTerminal.terminal, string.rep("\x8F", message:len()), colors.black, backgroundColor)
    local content = Gfx.TextToTexels(uiTerminal.terminal, message, textColor, backgroundColor)
    statusSurface:addLine(Utils.concatTables(padding, upperBorder))
    statusSurface:addLine(Utils.concatTables(padding, content))
    statusSurface:draw()
    lastFrameBlink = blinkingFrame
end

--- Adds a data line in the information frame.
--- @param title string The title of the line.
--- @param value string The value of the line.
--- @param details string Any other details in addition of the value.
--- @param isAlert boolean true if the value is currently responsible for an alert, false otherwise.
local function addInformationLine(title, value, details, isAlert)
    local titleColor = colors.yellow
    local valueBackground = colors.black
    if isAlert then
        titleColor = colors.red
        valueBackground = colors.red
        alertActivated = true
    end
    local titleTexels = Gfx.TextToTexels(uiTerminal.terminal, title, titleColor, colors.black)
    local valueTexels = Gfx.TextToTexels(uiTerminal.terminal, value, colors.white, valueBackground)
    local lineTexels = Utils.concatTables(titleTexels, valueTexels)
    if details ~= nil then
        local detailsTexels = Gfx.TextToTexels(uiTerminal.terminal, details, colors.lightGray, colors.black)
        lineTexels = Utils.concatTables(lineTexels, detailsTexels)
    end
    informationSurface:addLine(lineTexels)
end

--- Creates a visual progress bar.
--- @param percentage number Percentage filled of the progress bar.
--- @param color color The color of the filled section.
--- @param width number The total width of the progress bar.
--- @return table progressBar A table of Texels representing a progress bar.
local function progressBar(percentage, color, width)
    local filled = math.floor((width * percentage) + 0.5)
    local filledTexels = Gfx.TextToTexels(uiTerminal, string.rep(" ", filled), color, color)
    local emptyTexels = Gfx.TextToTexels(uiTerminal, string.rep(" ", width - filled), colors.lightGray, colors.lightGray)
    return Utils.concatTables(filledTexels, emptyTexels)
end

--- Adds a fluid data line with a progress bar in the information frame.
--- @param title string The title of the line.
--- @param percentage number Percentage filled of the progress bar.
--- @param amount number Total fluid amount in L. Will be divided by 1000 and shown as cubic meters.
--- @param name string Name of the fluid.
--- @param color color Color of the progress bar.
--- @param isAlert boolean true if the value is currently responsible for an alert, false otherwise.
local function addInformationProgressBar(title, percentage, amount, name, color, isAlert)
    local stringPercentage = string.format("%.1f", percentage * 100)
    local stringAmount = string.format("%.1f", amount / 1000)
    addInformationLine(title, " " .. stringPercentage .. "% ", "(" .. stringAmount .. "m\xB3 " .. name .. ")       ", isAlert)
    local progressBar = progressBar(percentage, color, informationSurface.width - 4)
    informationSurface:addLine(Utils.concatTables(Gfx.TextToTexels(uiTerminal, " ", colors.black, colors.black), progressBar))
    informationSurface:blankLine()
end

--- Draws the reactor information frame.
--- @param reactor table The reactor peripheral. 
local function drawInformation(reactor)
    alertActivated = false
    local temperature = reactor.getTemperature()
    local tempK = string.format("%.1f", temperature)
    local tempC = string.format("%.1f", temperature - 273.15)
    informationSurface:clear()
    informationSurface:blankLine()
    addInformationLine(" Temperature:", " " .. tempK .. "K", " (" .. tempC .. "\xB0C)      ", temperature > alerts.temperature)
    addInformationLine(" Burn rate: ", reactor.getActualBurnRate() .. " L/t", " (max " .. reactor.getMaxBurnRate() .. " L/t)      ", false)
    addInformationLine(" Heating rate: ", reactor.getHeatingRate() .. " L/t", " (eff=" .. reactor.getBoilEfficiency() .. ")      ", false)
    addInformationLine(" Damage:", " " .. reactor.getDamagePercent() .. "% ", "      ", reactor.getDamagePercent() > alerts.damage)
    informationSurface:blankLine()

    local coolant = reactor.getCoolant()
    local coolantName = Utils.convertIdToReadable(coolant.name)
    addInformationProgressBar(" Coolant:", reactor.getCoolantFilledPercentage(), coolant.amount, coolantName, colors.blue, reactor.getCoolantFilledPercentage() < alerts.coolant)
    local fuel = reactor.getFuel()
    local fuelName = Utils.convertIdToReadable(fuel.name)
    addInformationProgressBar(" Fuel:", reactor.getFuelFilledPercentage(), fuel.amount, fuelName, colors.green, reactor.getFuelFilledPercentage() < alerts.fuel)
    local heatedCoolant = reactor.getHeatedCoolant()
    local heatedCoolantName = Utils.convertIdToReadable(heatedCoolant.name)
    addInformationProgressBar(" Heated coolant:", reactor.getHeatedCoolantFilledPercentage(), heatedCoolant.amount, heatedCoolantName, colors.orange, reactor.getHeatedCoolantFilledPercentage() > alerts.heatedCoolant)
    local waste = reactor.getWaste()
    local wasteName = Utils.convertIdToReadable(waste.name)
    addInformationProgressBar(" Waste:", reactor.getWasteFilledPercentage(), waste.amount, wasteName, colors.red, reactor.getWasteFilledPercentage() > alerts.waste)
    if alertActivated then
        informationSurface:setBorder(colors.red)
    else
        informationSurface:setBorder(colors.gray)
    end
    informationSurface:draw()
end

--- Creates a surface reprentating a button.
--- @param text string The text in the middle of the button.
--- @param color color The accent color of the button.
--- @return table button The surface representing the button.
local function createButton(text, color)
    local button = consoleTerminal:newSurface(0, 0, text:len() + 4, 5)
    button:blankLine()
    button:textLine(" " .. text .. " ", color)
    button:blankLine()
    button:setBorder(color)
    return button
end

--------------------------------
----     Public methods     ----
--------------------------------

--- Sets the known state of the reactor.
--- @param newState UI.State The new state of the reactor.
function UI:setState(newState)
    state = newState
end

--- Draws a full screen message with an icon.
--- @param type UI.MessageType Type of message.
--- @param message string The text of the message.
--- @param color color Color of the text.
function UI.drawMessage(type, message, color)
    uiTerminal:clear()
    needClearing = true
    if (type == currentMessage.type) and (currentMessage.text == message) and (currentMessage.color == color) then
        messageLayout:draw()
        return
    end
    currentMessage = {
        type = type,
        text = message,
        color = color
    }
    messageLayout:removeAll()
    local textSurface = uiTerminal:newSurface(0, 0, message:len(), 2)
    textSurface:blankLine()
    textSurface:textLine(message, color, colors.black)
    if type == UI.MessageType.Unknown then
        messageLayout:add(icons.unknown)
    elseif type == UI.MessageType.Warning then
        messageLayout:add(icons.warning)
    end
    messageLayout:add(textSurface)
    messageLayout:draw()
end

--- Draws the console UI.
function UI.drawConsole()
    consoleTerminal:header("", "AEGIS", version)
    if reactor == nil then
        startButton:setBorder(colors.gray)
        stopButton:setBorder(colors.gray)
    else
        local status = reactor.getStatus()
        if status then
            startButton:setBorder(colors.gray)
            stopButton:setBorder(colors.red)
        else
            startButton:setBorder(colors.green)
            stopButton:setBorder(colors.gray)
        end
    end
    consoleLayout:draw()
end

--- Plays the startup animation on the UI monitor.
function UI.splash()
    uiTerminal:clear()
    local path = shell.dir() .. "/assets/splash/"
    local frames = fs.list(path)
    local splashText = "Automated Energy Generation Inspection System"
    local textSurface = uiTerminal:newSurface(0, 0, splashText:len(), 2)
    local animationFrame = uiTerminal:newSurface(0, 0, 0, 0)
    messageLayout:removeAll()
    messageLayout:add(animationFrame, textSurface)
    textSurface:blankLine()
    for _, frame in ipairs(frames) do
        animationFrame:loadNFP(path .. frame)
        messageLayout:refresh()
        messageLayout:draw()
        sleep(0.1)
    end
    sleep(0.5)
    textSurface:textLine(splashText, colors.white, colors.black)
    messageLayout:refresh()
    messageLayout:draw()
    sleep(5)
    messageLayout:removeAll()
end

--- Initializes the UI.
--- @param _uiMonitor table The UI monitor peripheral.
--- @param config table The table representation of the AEGIS configuration file.
--- @param log Log The logger.
function UI.init(_uiMonitor, config, log)
    Log = log
    version = config.version
    alerts = config.alerts
    uiTerminal = Gfx.Terminal.new(_uiMonitor)
    consoleTerminal = Gfx.Terminal.new(term)
    consoleTerminal:clear()
    local consoleTermWidth, consoleTermHeight = consoleTerminal:getSize()
    consoleLayout = consoleTerminal:newLayout(Gfx.LayoutTypes.Vertical, 1, 2, consoleTermWidth, consoleTermHeight - 1)
    startButton = createButton("Start", colors.green)
    stopButton = createButton("Stop ", colors.red)
    quitButton = createButton("Exit", colors.white)
    local firstRow = consoleTerminal:newLayout(Gfx.LayoutTypes.Horizontal, 0, 0, consoleTermWidth, 5)
    local vSpacer = consoleTerminal:newSurface(0, 0, 1, 5)
    local hSpacer = consoleTerminal:newSurface(0, 0, 5, 1)
    firstRow:add(startButton, hSpacer, stopButton)
    consoleLayout:add(firstRow, vSpacer, quitButton)

    if config.uiMonitor.scale ~= nil then
        _uiMonitor.setTextScale(config.uiMonitor.scale)
    end
    _uiMonitor.setTextColor(colors.white)
    _uiMonitor.setBackgroundColor(colors.black)
    _uiMonitor.clear()
    icons.unknown = uiTerminal:newSurface()
    icons.warning = uiTerminal:newSurface()

    reactorSurface = uiTerminal:newSurface(1, 2)
    reactorSurface:setBorder(colors.black)
    icons.unknown:loadNFP(shell.dir() .. "/assets/unknown.nfp")
    icons.warning:loadNFP(shell.dir() .. "/assets/warning.nfp")
    local uiTermWidth, uiTermHeight = _uiMonitor.getSize()
    messageLayout = uiTerminal:newLayout(Gfx.LayoutTypes.Vertical, 1, 2, uiTermWidth, uiTermHeight)
    informationSurface = uiTerminal:newSurface(0, 3, 0, uiTermHeight - 3)
    informationSurface:setBorder(colors.gray)
    statusSurface = uiTerminal:newSurface(1, 0, 0, 3)
end

--- Sets up the reactor component of the UI.
--- This is separated from UI.init() as the reactor might no be found on the network.
--- @param _reactor table The reactor peripheral.
function UI.setup(_reactor)
    reactor = _reactor
    if reactor ~= nil and reactor.isFormed() then
        local reactorWidth = reactor.getWidth() - 2
        local reactorLength = reactor.getLength() - 2
        reactorSize.length = math.max(reactorLength, reactorWidth)
        reactorSize.width = math.min(reactorLength, reactorWidth)
    end
    reactorSurface.width = (reactorSize.width + 1)*2
    reactorSurface.height = (reactorSize.length + 1)*2
    informationSurface.x = reactorSurface.x + reactorSurface.width + 1
    local termWidth, _ = uiTerminal:getSize()
    informationSurface.width = termWidth - (reactorSurface.x + reactorSurface.width) - 1
    statusSurface.y = reactorSurface.y + reactorSurface.height
    statusSurface.width = reactorSurface.width
end

--- Draws the UI on the main UI monitor.
function UI.drawUI()
    if reactor == nil then
        UI.drawMessage(UI.MessageType.Unknown, "Reactor not found", colors.red)
    elseif reactor.isFormed() == false then
        UI.drawMessage(UI.MessageType.Warning, "Reactor not formed", colors.orange)
    elseif reactor.isFormed() == nil then
        UI.drawMessage(UI.MessageType.Warning, "Reactor unreachable", colors.red)
    else
        if needClearing then
            uiTerminal:clear()
            uiTerminal:header("", "AEGIS", version)
            needClearing = false
        end
        if state ~= UI.State.HI then
            if reactor.getStatus() then
                state = UI.State.Active
            else
                state = UI.State.Idle
            end
        end
        drawReactorDiagram(reactor)
        drawStatus()
        drawInformation(reactor)
    end
end

--- Console click events listener.
function UI.handleConsoleInput()
    while true do
        local _, button, x, y = os.pullEvent("mouse_click")
        if button ~= 1 then
            goto continue
        end
        if startButton:contains(x, y) then
            local activation, _ = pcall(reactor.activate)
            if activation then
                state = UI.State.Active
                Log:info("Manual activation")
            else
                Log:error("Manual activation failed")
            end
        elseif stopButton:contains(x, y) then
            local shutdown, _ = pcall(reactor.scram)
            if shutdown then
                Log:info("Manual shutdown")
            else
                Log:error("Manual shutdown failed")
            end
        elseif quitButton:contains(x, y) then
            Log:info("Shutting down reactor before exiting AEGIS")
            pcall(reactor.scram)
            break
        end
        UI.drawConsole()
        ::continue::
    end
end

return UI