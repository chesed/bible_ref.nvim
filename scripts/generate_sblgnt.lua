-- Script to parse SBLGNT text files and generate bible_sblgnt.json
-- Source: https://github.com/Faithlife/SBLGNT/master

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
    
    for line in file:lines() do
        -- Remove leading whitespace
        local trimmed = line:gsub("^%s+", "")
        
        -- Skip empty lines and header lines (first line of each book)
        if trimmed ~= "" then
            -- Match the pattern: Book Chapter:Verse<TAB>TEXT
            -- Using Lua string patterns: [[:space:]] for whitespace, [0-9] for digits
            local match = trimmed:match("^(.+?)[[:space:]]+([0-9]):[[:space:]]*([0-9])\t(.*)$")
            if match then
                local book, chapter, verse, text = match[1], match[2], match[3], match[4]
                
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
                print("Warning: Unrecognized line format in " .. filepath .. ": " .. trimmed)
            end
        end
    end
    
    file:close()
    return true
end

-- Main execution
local output = {}
local books_dir = "SBLGNT/data/sblgnt/text/"

-- Known Bible book filenames in SBLGNT format (Greek texts, ordered)
local bible_books = {
    "1Cor.txt", "1John.txt", "1Pet.txt", "1Thess.txt", "1Tim.txt",
    "2Cor.txt", "2John.txt", "2Pet.txt", "2Thess.txt", "2Tim.txt",
    "3John.txt", "Acts.txt", "Col.txt", "Eph.txt", "Gal.txt",
    "Heb.txt", "Jas.txt", "John.txt", "Jude.txt", "Luke.txt",
    "Mark.txt", "Matt.txt", "Phil.txt", "Phlm.txt", "Rev.txt",
    "Rom.txt", "Titus.txt"
}

print("Found " .. #bible_books .. " book files to parse.")

for _, filename in ipairs(bible_books) do
    local filepath = books_dir .. filename
    print("Parsing: " .. filepath)
    if not parse_file(filepath, output) then
        print("Failed to parse: " .. filepath)
    end
end

-- Write the JSON file
local json_content = "{"
local first = true
local sorted_keys = {}
for key in ipairs(output) do
    table.insert(sorted_keys, key)
end

-- Sort keys alphabetically for consistent output
table.sort(sorted_keys)

for _, key in ipairs(sorted_keys) do
    if not first then
        json_content = json_content .. ",\n"
    end
    first = false
    
    -- Format: "Key": "value"
    local escaped_key = escape_json(key)
    local escaped_value = output[key]
    
    json_content = json_content .. string.format('  "%s": "%s",', escaped_key, escaped_value)
end

json_content = json_content .. "\n}"

-- Write to file
local output_path = "data/bible_sblgnt.json"
local file = io.open(output_path, "w")
if not file then
    print("Error: Could not open output file " .. output_path)
else
    file:write(json_content)
    file:close()
    print("Successfully wrote " .. output_path .. ")")
    print(string.format("Total verses: %d", #output))
end

print("Done!")