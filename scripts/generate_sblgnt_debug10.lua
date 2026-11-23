-- Debug script to check the parsing - completely simplified version
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

-- Read entire file as a string using io.lines() properly
local function read_file(filepath)
    local lines = {}
    for line in io.lines(filepath) do
        table.insert(lines, line)
    end
    return table.concat(lines, "\n")
end

-- Main execution with debug
print("Testing file reading...")

for _, filename in ipairs({ "SBLGNT/data/sblgnt/text/1Cor.txt" }) do
    local filepath = filename
    print("\n=== Testing: " .. filepath .. " ===")
    
    -- Try to read the file
    local content = read_file(filepath)
    if not content then
        print("Failed to read file")
    else
        print(string.format("File size: %d chars", #content))
        print(string.format("First 200 chars: %s", string.sub(content, 1, 200)))
        
        -- Split into lines manually
        for line in gmatch(content, "[^\\n]*") do
            local trimmed = line:gsub("^%s+", "")
            if trimmed ~= "" then
                print(string.format("Line: %s", line))
                
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