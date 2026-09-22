--- Utils functions for AEGIS
local Utils = {}

--- Merges two tables.
--- @param t1 table The first table.
--- @param t2 table The second table.
--- @return table table A flat table starting with the first table and ending with the second table.
function Utils.concatTables(t1, t2)
    local merge = {}
    for i = 1, #t1 do merge[i] = t1[i] end
    for i = 1, #t2 do merge[#merge + 1] = t2[i] end
    return merge
end

--- Dumps all methos of a ComputerCraft peripheral in a text file.
--- @param peripheralName string Name of the peripheral.
--- @param outputFileName string Path of the output file.
function Utils.dumpPeripheralMethods(peripheralName, outputFileName)
    local methods = peripheral.getMethods(peripheralName)
    local file = io.open(outputFileName, "w")
    for i=1, #methods do
        file:write(methods[i] .. "\n")
    end
    file:close()
end

--- Converts a minecraft ID to a readable string.
--- This will not find the "real" name of the ID, but only tries to infer it from the ID string by removing the prefix and replacing underscores by spaces.
--- @param id string The item ID.
--- @return string name A readable name if the ID was parsed correctly or else the same ID value.
function Utils.convertIdToReadable(id)
    local name = id:match(":(.+)$")
    if name then
        name = name:gsub("_", " ")
        return name
    end
    return id
end

return Utils