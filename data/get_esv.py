import json
import requests

API_KEY = "cf194392a51f014f9f9ac8e8954f30204758fe1c"  # Token from api.esv.org
HEADERS = {"Authorization": f"Token {API_KEY}"}
API_URL = "https://api.esv.org/v3/passage/text/"

params = {
    "q": "John 1",
    "include-headings": False,
    "include-footnotes": False,
    "include-verse-numbers": True,
    "include-short-copyright": False,
}

response = requests.get(API_URL, headers=HEADERS, params=params)
data = response.json()
print(data.get("passages", [""])[0])
