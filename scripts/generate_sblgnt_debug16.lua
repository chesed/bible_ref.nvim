-- Debug script to check the parsing - simplified version with explicit line inspection and more detailed pattern testing
local function escape_json(s)
    local result = ""
    for i, char in ipairs(string.bytes(s)) do
        if char == 10 then
            result = result .. "\\n"
        elseif char == 9 then
            result = result .. "\\t"
        elseif char == 34 then
            result = result .. "\\" .. "\""
        elseif char == 127 or char < 32 then
            result = result .. string.format("\\%02x", char)
        else
            result = result .. char
        end
    end
    return result
end

-- Read entire file as a table of lines
local function read_lines(filepath)
    local lines = {}
    for line in io.lines(filepath) do
        table.insert(lines, line)
    end
    return lines
end

-- Main execution with debug
print("Testing file reading...")

for _, filename in ipairs({ "SBLGNT/data/sblgnt/text/1Cor.txt" }) do
    local filepath = filename
    print("\n=== Testing: " .. filepath .. " ===")
    
    -- Try to read the lines
    local lines = read_lines(filepath)
    if not lines then
        print("Failed to read file")
    else
        print(string.format("Number of lines: %d", #lines))
        
        -- Process first 10 lines for debugging
        for i, line in ipairs(lines) do
            if i > 10 then break end
            
            local trimmed = line:gsub("^%s+", "")
            if trimmed ~= "" then
                print(string.format("Line %d: '%s'", i, trimmed))
                
                -- Try to match with explicit pattern - using literal whitespace matching
                local match = trimmed:match("^([A-Za-z0-9]+) [0-9]: ([0-9])\\t(.*)$")
                if match then
                    local book, chapter, verse, text = match[1], match[2], match[3], match[4]
                    print(string.format("  MATCH found: book='%s', chapter=%s, verse=%s", book, chapter, verse))
                    
                    -- Clean the text (remove trailing spaces)
                    text = text:gsub("%s+$", "")
                    
                    -- Escape special characters for JSON
                    text = escape_json(text)
                    
                    -- Build the key: "Book Chapter:Verse"
                    local key = book .. " " .. chapter .. ":" .. verse
                    
                    print(string.format("  Key: '%s'", key))
                else
                    print("  MATCH FAILED")
                end
            end
        end
    end
end

print("\nDone!")