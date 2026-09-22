--- Simple stack data structure
local Stack = {}

--- Creates a new stack.
--- @return table stack An empty stack.
function Stack.new()
    local stack = {}

    --- Pushes a new element on top of the stack.
    --- @param element any The element to add.
    function stack:push(element)
        table.insert(self, element)
    end

    --- Pops the element on top of the stack
    --- @return any element The element on top of the stack or nil if the stack is empty.
    function stack:pop()
        if #self < 1 then
            return nil
        end
        local element = table.remove(self)
        return element
    end
    
    return stack
end

return Stack