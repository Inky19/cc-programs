--- Simple graphics library
local Stack = require("lib/stack")
local Gfx = {}
Gfx.NULL = {}

--------------------------------
----       Terminal         ----
--------------------------------

-- A terminal is an abstraction of either the computer terminal or a network monitor.
Gfx.Terminal = {}
Gfx.Terminal.__index = Gfx.Terminal

--- Constructor.
--- @param terminal table The terminal to wrap.
--- @return table terminal The newly created terminal.
function Gfx.Terminal.new(terminal)
    return setmetatable({
        terminal = terminal,
        termSettingsHistory = Stack.new()
    }, Gfx.Terminal)
end

--- Saves the terminal settings in the history stack.
function Gfx.Terminal:saveTermSettings()
    local settings = {}
    settings.textColor = self.terminal.getTextColor()
    settings.backgroundColor = self.terminal.getBackgroundColor()
    settings.cursorPos = {self.terminal.getCursorPos()}
    self.termSettingsHistory:push(settings)
end

--- Restores the last saved settings from the history stack.
function Gfx.Terminal:restoreTermSettings()
    local settings = self.termSettingsHistory:pop()
    self.terminal.setTextColor(settings.textColor)
    self.terminal.setBackgroundColor(settings.backgroundColor)
    self.terminal.setCursorPos(table.unpack(settings.cursorPos))
end

---Draws a header at the top of the terminal.
---@param left string Text to be displayed in the top left corner.
---@param center string Text to be displayed in the middle.
---@param right string Text to be displayed in the top right corner.
function Gfx.Terminal:header(left, center, right)
    self:saveTermSettings()
    self.terminal.setCursorPos(1, 1)
    self.terminal.setBackgroundColor(colors.white)
    self.terminal.setTextColor(colors.black)
    local width, _ = self.terminal.getSize()
    local padding = (width - center:len()) / 2
    self.terminal.write(left)
    for _ = 1, (padding - left:len()) do
        self.terminal.write(" ")
    end
    self.terminal.write(center)
    for _ = 1, (padding - right:len()) do
        self.terminal.write(" ")
    end
    self.terminal.write(right)
    self:restoreTermSettings()
end

-- Boilerplate to forward methods common to 'term' and 'monitor'.
function Gfx.Terminal:write(text) return self.terminal.write(text) end
function Gfx.Terminal:scroll(y) return self.terminal.scroll(y) end
function Gfx.Terminal:getCursorPos() return self.terminal.getCursorPos() end
function Gfx.Terminal:setCursorPos(x, y) return self.terminal.setCursorPos(x, y) end
function Gfx.Terminal:getCursorBlink() return self.terminal.getCursorBlink() end
function Gfx.Terminal:setCursorBlink(blink) return self.terminal.setCursorBlink(blink) end
function Gfx.Terminal:getSize() return self.terminal.getSize() end
function Gfx.Terminal:clear() return self.terminal.clear() end
function Gfx.Terminal:getTextColor() return self.terminal.getTextColor() end
function Gfx.Terminal:setTextColor(color) return self.terminal.setTextColor(color) end
function Gfx.Terminal:getBackgroundColor() return self.terminal.getBackgroundColor() end
function Gfx.Terminal:setBackgroundColor(color) return self.terminal.setBackgroundColor(color) end
function Gfx.Terminal:isColor() return self.terminal.isColor() end
function Gfx.Terminal:blit(text, textColor, backgroundColor) return self.terminal.blit(text, textColor, backgroundColor) end
function Gfx.Terminal:setPaletteColor(...) return self.terminal.setPaletteColor(...) end
function Gfx.Terminal:getPaletteColor() return self.terminal.getPaletteColor() end

--------------------------------
----        Surface         ----
--------------------------------

-- A surface is a rectangular area on a screen with content and an optional border.
Gfx.Surface = {}
Gfx.Surface.__index = Gfx.Surface
local DEFAULT_BORDER_COLOR = colors.white

--- Constructor.
--- @param x number The X coordinate of the top left corner of the surface.
--- @param y number The Y coordinate of the top left corner of the surface.
--- @param width number The width of the surface (including if the border if present).
--- @param height number The height of the surface (including if the border if present).
--- @return table surface The newly created surface.
function Gfx.Terminal:newSurface(x, y, width, height)
    return setmetatable({
        terminal = self,
        x = x,
        y = y,
        width = width,
        height = height,
        data = {},
        borderColor = DEFAULT_BORDER_COLOR,
        hasBorder = false
    }, Gfx.Surface)
end

--- Clears the content data of the surface.
function Gfx.Surface:clear()
    self.data = {}
end

--- Adds a blank line to the content.
function Gfx.Surface:blankLine()
    local line = {}
    local blankTexel = Gfx.Texel(self.terminal:getTextColor(), self.terminal:getBackgroundColor(), " ")
    for _ = 1, self.width do
        table.insert(line, blankTexel)
    end
    self:addLine(line)
end

--- Adds a simple text line to the content.
--- @param text string The text to add.
--- @param textColor color The text color.
--- @param backgroundColor color The background color of the text.
function Gfx.Surface:textLine(text, textColor, backgroundColor)
    self:addLine(Gfx.TextToTexels(self.terminal, text, textColor, backgroundColor))
end

--- Adds a line to the content.
--- @param line table A table of texels.
function Gfx.Surface:addLine(line)
    table.insert(self.data, line)
end

--- Enables the border.
--- @param color color The border color.
function Gfx.Surface:setBorder(color)
    self.borderColor = color
    self.hasBorder = true
end

--- Disables the border.
function Gfx.Surface:unsetBorder()
    self.hasBorder = false
    self.borderColor = DEFAULT_BORDER_COLOR
end

--- Directly sets the content of the surface.
--- @param data table A table of texel table.
function Gfx.Surface:setData(data)
    self.data = data
end

--- Checks if a point is inside the surface.
--- @param x number The point X coordinate.
--- @param y number The point Y coordinate.
--- @return boolean isInside true if the point is overlapping with the surface, false otherwise.
function Gfx.Surface:contains(x, y)
    return (x >= self.x) and (x < self.x + self.width)
    and (y >= self.y) and (y < self.y + self.height)
end

--- Loads a NFP file as the content of the surface.
--- @param filename string Path to the NFP file to load.
function Gfx.Surface:loadNFP(filename)
    local data = Gfx.LoadNFP(filename)
    if data == nil then
        return
    end
    self:setData(data)
    self.height = #data
    local imageWidth = 0
    for _, line in ipairs(data) do
        imageWidth = math.max(imageWidth, #line)
    end
    self.width = imageWidth
    if self.hasBorder then
        self.width = self.width + 2
        self.height = self.height + 2
    end
end

--- Draws the surface on its screen.
function Gfx.Surface:draw()
    self.terminal:saveTermSettings()
    self.terminal:setCursorPos(self.x, self.y)
    local _, termHeight = self.terminal:getSize()
    local function drawEmptyLine()
        for _=1, self.width do
            self.terminal:write(" ")
        end
    end

    if self.hasBorder then
        self.terminal:setBackgroundColor(self.borderColor)
        drawEmptyLine()
    end

    local contentHeight = self.height
    local contentWidth = self.width
    local contentY = self.y
    if self.hasBorder then
        contentHeight = math.max(0, contentHeight - 2)
        contentWidth = math.max(0, contentWidth - 2)
        contentY = contentY + 1
    end

    for i=1, contentHeight do -- Lines
        local absoluteY = contentY + i - 1
        if (absoluteY > termHeight) or (not self.hasBorder and i > #self.data) then
            break
        end
        self.terminal:setCursorPos(self.x, absoluteY)
        if self.hasBorder then
            self.terminal:setBackgroundColor(self.borderColor)
            self.terminal:write(" ")
        end
        local line = self.data[i]
        if line == nil then
            goto skipLine
        end
        for j=1, contentWidth do -- Columns
            if j > contentWidth then
                break
            end
            local texel = line[j]
            if ((texel == Gfx.NULL) or (texel == nil)) then
                local cursorX, cursorY = self.terminal:getCursorPos()
                self.terminal:setCursorPos(cursorX + 1, cursorY)
                goto continue
            end
            self.terminal:setTextColor(texel.textColor)
            self.terminal:setBackgroundColor(texel.backgroundColor)
            if texel.char:len() == 0 then
                self.terminal:write(" ")
            else
                self.terminal:write(string.sub(texel.char, 1, 1))
            end
            ::continue::
        end
        ::skipLine::
        if self.hasBorder then
            self.terminal:setCursorPos(self.x + self.width - 1, absoluteY)
            self.terminal:setBackgroundColor(self.borderColor)
            self.terminal:write(" ")
        end
    end

    if self.hasBorder then
        self.terminal:setCursorPos(self.x, self.y + self.height - 1)
        self.terminal:setBackgroundColor(self.borderColor)
        drawEmptyLine()
    end
    self.terminal:restoreTermSettings()
end

--------------------------------
----        Layout          ----
--------------------------------

Gfx.LayoutTypes = {
    Horizontal = {},
    Vertical = {}
}

Gfx.HorizontalAlignment = {
    Left = {},
    Center = {},
    Right = {}
}

Gfx.VerticalAlignement = {
    Top = {},
    Middle = {},
    Bottom = {}
}

--- A layout is a rectangular area on a screen that contains and arranges multiple surfaces or sub-layouts.
--- It can be considered like a viewport of the screen.
Gfx.Layout = {}
Gfx.Layout.__index = Gfx.Layout

--- Constructor.
--- @param type Gfx.LayoutTypes The type of the layout.
--- @param x number The X coordinate of the top left corner of the layout.
--- @param y number The Y coordinate of the top left corner of the layout.
--- @param width number The width of the layout.
--- @param height number The height of the layout.
--- @return table layout The newly created layout.
function Gfx.Terminal:newLayout(type, x, y, width, height)
    return setmetatable({
        surfaces = {},
        type = type,
        x = x,
        y = y,
        width = width,
        height = height,
        verticalAlignement = Gfx.VerticalAlignement.Middle,
        horizontalAlignment = Gfx.HorizontalAlignment.Center
    }, Gfx.Layout)
end

--- Refreshes the pre-computed position of the children inside a horizontal layout.
--- @param layout Gfx.Layout The layout to render.
local function renderHorizontalLayout(layout)
    local contentWidth = 0
    for _, surface in ipairs(layout.surfaces) do
        contentWidth = contentWidth + surface.width
    end
    local offsetX = 0
    if layout.horizontalAlignment == Gfx.HorizontalAlignment.Left then
        offsetX = layout.x
    elseif layout.horizontalAlignment == Gfx.HorizontalAlignment.Center then
        offsetX = layout.x + math.floor((layout.width - contentWidth) / 2)
    elseif layout.horizontalAlignment == Gfx.HorizontalAlignment.Right then
        offsetX = layout.x + layout.width - contentWidth
    end
    local setY
    if layout.verticalAlignement == Gfx.VerticalAlignement.Top then
        setY = function (surface)
            surface.y = layout.y
        end
    elseif layout.verticalAlignement == Gfx.VerticalAlignement.Middle then
        local centerY = layout.y + math.floor(layout.height / 2)
        setY = function (surface)
            surface.y = centerY - math.floor(surface.height / 2)
        end
    elseif layout.verticalAlignement == Gfx.VerticalAlignement.Bottom then
        setY = function (surface)
            surface.y = layout.y + layout.height - surface.height
        end
    end
    for _, surface in ipairs(layout.surfaces) do
        surface.x = offsetX
        offsetX = offsetX + surface.width
        setY(surface)
    end
end

--- Refreshes the pre-computed position of the children inside a verical layout.
--- @param layout Gfx.Layout The layout to render.
local function renderVerticalLayout(layout)
    local contentHeight = 0
    for _, surface in ipairs(layout.surfaces) do
        contentHeight = contentHeight + surface.height
    end
    local offsetY = 0
    if layout.verticalAlignement == Gfx.VerticalAlignement.Top then
        offsetY = layout.y
    elseif layout.verticalAlignement == Gfx.VerticalAlignement.Middle then
        offsetY = layout.y + math.floor((layout.height - contentHeight) / 2)
    elseif layout.verticalAlignement == Gfx.VerticalAlignement.Bottom then
        offsetY = layout.y + layout.height - contentHeight
    end
    local setX
    if layout.horizontalAlignment == Gfx.HorizontalAlignment.Left then
        setX = function (surface)
            surface.x = layout.x
        end
    elseif layout.horizontalAlignment == Gfx.HorizontalAlignment.Center then
        local centerX = layout.x + math.floor(layout.width / 2)
        setX = function (surface)
            surface.x = centerX - math.floor(surface.width / 2)
        end
    elseif layout.horizontalAlignment == Gfx.HorizontalAlignment.Right then
        setX = function (surface)
            surface.x = layout.x + layout.width - surface.width
        end
    end
    for _, surface in ipairs(layout.surfaces) do
        surface.y = offsetY
        offsetY = offsetY + surface.height
        setX(surface)
    end
end

--- Refreshes a layout and its children.
function Gfx.Layout:refresh()
    if self.type == Gfx.LayoutTypes.Horizontal then
        renderHorizontalLayout(self)
    elseif self.type == Gfx.LayoutTypes.Vertical then
        renderVerticalLayout(self)
    else
        print("[ERROR] Invalid layout")
    end
    for _, surface in ipairs(self.surfaces) do
        if surface.refresh ~= nil then
            surface:refresh()
        end
    end
end

--- Adds components to the layout.
--- @param ... Gfx.Surface|Gfx.Layout The components to add.
function Gfx.Layout:add(...)
    local surfaces = table.pack(...)
    for _, surface in ipairs(surfaces) do
        table.insert(self.surfaces, surface)
    end
    self:refresh()
end

--- Sets the components of the layout.
--- @param ... Gfx.Surface|Gfx.Layout The components.
function Gfx.Layout:setItems(...)
    self:removeAll()
    self:add(...)
end

--- Removes all the components from the layout.
function Gfx.Layout:removeAll()
    self.surfaces = {}
end

--- Draws the layout (i.e. draws all of its children recursively).
function Gfx.Layout:draw()
    for _, surface in ipairs(self.surfaces) do
        surface:draw()
    end
end

--- Sets the alignements of the layout.
--- @param horizontalAlignment Gfx.HorizontalAlignment Horizontal alignement.
--- @param verticalAlignement Gfx.VerticalAlignement Vertical alignement.
function Gfx.Layout:setAlignment(horizontalAlignment, verticalAlignement)
    self.horizontalAlignment = horizontalAlignment
    self.verticalAlignement = verticalAlignement
    self:refresh()
end

--- Sets the vertical alignement of the layout.
--- @param verticalAlignement Gfx.VerticalAlignement Vertical alignement.
function Gfx.Layout:setVerticalAlignment(verticalAlignement)
    self:setAlignment(self.horizontalAlignment, verticalAlignement)
end

--- Sets the horizontal alignement of the layout.
--- @param horizontalAlignment Gfx.HorizontalAlignment Horizontal alignement.
function Gfx.Layout:setHorizontalAlignment(horizontalAlignment)
    self:setAlignment(horizontalAlignment, self.verticalAlignement)
end

--------------------------------
----         Texel          ----
--------------------------------

--- Constructor.
--- @param textColor color Text element color.
--- @param backgroundColor color The background color.
--- @param char string The character to display inside the texel.
--- @return table texel The newly created texel.
function Gfx.Texel(textColor, backgroundColor, char)
    local texel = {}
    texel.textColor = textColor
    texel.backgroundColor = backgroundColor
    texel.char = string.sub(char, 1, 1)
    return texel
end

--- Helper function to convert a string into a table of texels.
--- @param terminal table The terminal where the texels will be displayed.
--- @param text string The text to convert.
--- @param textColor color The text color to use.
--- @param backgroundColor color The background color to use.
--- @return table texels A table of texels.
function Gfx.TextToTexels(terminal, text, textColor, backgroundColor)
    textColor = textColor or terminal:getTextColor()
    backgroundColor = backgroundColor or terminal:getBackgroundColor()
    local texels = {}
    for i = 1, text:len() do
        table.insert(texels, Gfx.Texel(textColor, backgroundColor, string.sub(text, i, i)))
    end
    return texels
end

--------------------------------
----         Utils          ----
--------------------------------

--- Loads a NFP file and converts it to a table of texels.
--- @param filename string The path of the NFP file.
--- @return table|nil texels A table of texel tables if the conversion was successful or nil in case of an error.
function Gfx.LoadNFP(filename)
    local imageFile = io.open(filename, "r")
    local texelData = {}
    if imageFile == nil then
        print("[Error] Invalid image file")
        return nil
    end
    for imageLine in imageFile:lines() do
        local texelLine = {}
        for i=1, #imageLine do
            local color = colors.fromBlit(string.sub(imageLine, i, i))
            if color == nil then
                table.insert(texelLine, Gfx.NULL)
            else
                table.insert(texelLine, Gfx.Texel(colors.black, color, " "))
            end
        end
        table.insert(texelData, texelLine)
    end
    return texelData
end

return Gfx