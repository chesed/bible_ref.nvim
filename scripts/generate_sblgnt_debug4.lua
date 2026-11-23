-- Debug script to check the parsing - simplified version with explicit loop
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

local function parse_file(filepath, output)
    local file = io.open(filepath, "r")
    if not file then
        print("Error: Could not open " .. filepath)
        return false
    end
    
    for line in file do
        -- Remove leading whitespace
        local trimmed = line:gsub("^%s+", "")
        
        if trimmed ~= "" then
            -- Print raw bytes to see exact format
            print(string.format("[Line] raw: %r", line))
            
            -- Check the actual content of the line
            local has_tab = (trimmed:match("\t") or false) and true
            
            if trimmed ~= "" then
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
                    
                    -- Add to output
                    if not output[key] then
                        output[key] = ""
                    end
                    table.insert(output[key], text)
                else
                    print("  MATCH FAILED")
                end
            end
        end
    end
    
    file:close()
    return true
end

-- Main execution with debug
local output = {}
local books_dir = "SBLGNT/data/sblgnt/text/"
local bible_books = {
    "1Cor.txt", "1John.txt" -- Just first two for testing
}

print("Found " .. #bible_books .. " book files to parse.")

for _, filename in ipairs(bible_books) do
    local filepath = books_dir .. filename
    print("\n=== Parsing: " .. filepath .. " ===")
    if not parse_file(filepath, output) then
        print("Failed to parse: " .. filepath)
    end
end

print("\nTotal verses parsed:", #output)