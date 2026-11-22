import json
import urllib.request

# Try the Bible API - https://www.biblicap.com/api/v1/api/
api_url = "https://www.biblicap.com/api/v1/api/"
print("Trying Bible API...")

req = urllib.request.Request(api_url, headers={"User-Agent": "Mozilla/5.0"})
try:
    with urllib.request.urlopen(req, timeout=30) as response:
        content = response.read().decode('utf-8')
        
        # Check if it's valid JSON
        try:
            data = json.loads(content)
            print("Got", len(data), "books")
            
            # Extract KJV text (array of objects format)
            kjv_entries = []
            for book in data:
                if "KJV" in book:
                    for v in book["KJV"]:
                        kjv_entries.append({
                            "book": book["id"],
                            "chapter": v["ch"],
                            "verse": v["v"],
                            "text": v["txt"].strip()
                        })
            
            # Create flat map: key = "{Book} {Chapter}:{Verse}", value = text
            flat_map = {}
            for entry in kjv_entries:
                # Normalize book name (e.g., "1 Corinthians" -> "1 Cor")
                book_name = normalize_book_name(entry["book"])
                key = str(book_name) + " " + str(entry["chapter"]) + ":" + str(entry["verse"])
                
                if not flat_map.get(key):
                    flat_map[key] = entry["text"]
            
            # Save both formats
            with open("kjv_flat.json", "w") as f:
                json.dump(flat_map, f, ensure_ascii=False)
            print("Saved KJV flat map:", len(flat_map), "verses to kjv_flat.json")
            
            with open("kjv_array.json", "w") as f:
                json.dump(kjv_entries, f, ensure_ascii=False)
            print("Saved KJV array format:", len(kjv_entries), "entries to kjv_array.json")
            
        except json.JSONDecodeError:
            print("Not valid JSON")
    except Exception as e:
        print("Error:", str(e))

def normalize_book_name(name):
    # Simple abbreviation map for KJV books
    abbreviations = {
        "Genesis": "Gen", "Exodus": "Exo", "Leviticus": "Lev", "Numbers": "Num",
        "Deuteronomy": "Deut", "Joshua": "Jsh", "Judges": "Jud", "Ruth": "Rth",
        "1 Samuel": "1 Sam", "2 Samuel": "2 Sam", "1 Kings": "1 Kgs", "2 Kings": "2 Kgs",
        "1 Chronicles": "1 Chr", "2 Chronicles": "2 Chr", "Ezra": "Ezr", "Nehemiah": "Neh",
        "Esther": "Est", "Job": "Jb", "Psalm": "Ps", "Proverbs": "Prov", "Ecclesiastes": "Eccl",
        "Daniel": "Dan", "Hosea": "Hos", "Joel": "Jol", "Amos": "Amo", "Obediah": "Obd",
        "Jonah": "Jon", "Micah": "Mic", "Nahum": "Num", "Habakkuk": "Hab", "Zephaniah": "Zeph",
        "Jeremiah": "Jer", "Lamentations": "Lam", "Ezekiel": "Ezo",
    }
    return abbreviations.get(name, name)
