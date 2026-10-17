--!strict
-- Eingabeprüfung für alles, was vom Client kommt. Grundsatz: nichts glauben, alles prüfen.
-- Jede Funktion gibt den bereinigten Wert oder nil zurück.

local Guard = {}

function Guard.finite(value: any): number?
	if typeof(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
		return nil
	end
	return value
end

function Guard.number(value: any, min: number, max: number): number?
	local n = Guard.finite(value)
	if n == nil or n < min or n > max then
		return nil
	end
	return n
end

function Guard.integer(value: any, min: number, max: number): number?
	local n = Guard.number(value, min, max)
	if n == nil or n % 1 ~= 0 then
		return nil
	end
	return n
end

-- auf ein Raster runden (Slider-Werte) und Floating-Point-Reste abschneiden
function Guard.snap(value: number, step: number): number
	return math.round(math.round(value / step) * step * 100) / 100
end

-- kurze technische IDs (Config-IDs, GUIDs)
function Guard.id(value: any): string?
	if typeof(value) ~= "string" or #value == 0 or #value > 64 then
		return nil
	end
	if string.find(value, "[^%w_%-]") then
		return nil
	end
	return value
end

local function isInvisible(code: number): boolean
	return (code >= 0x200B and code <= 0x200F) -- Zero-Width, LRM/RLM
		or (code >= 0x202A and code <= 0x202E) -- Bidi-Overrides
		or (code >= 0x2066 and code <= 0x2069) -- Bidi-Isolates
		or code == 0xFEFF
end

-- Freitext (Firmen-/Modellnamen): gültiges UTF-8, keine Steuer-/Unsichtbar-Zeichen, Länge in Zeichen.
-- Ersetzt NICHT den Roblox-Textfilter – der kommt danach (Lib/TextFilter).
function Guard.text(value: any, minLength: number, maxLength: number): string?
	if typeof(value) ~= "string" or #value > maxLength * 4 then
		return nil
	end
	if utf8.len(value) == nil then
		return nil
	end
	local cleaned = (string.gsub(value, "%s+", " "))
	cleaned = string.match(cleaned, "^%s*(.-)%s*$") or ""
	if string.find(cleaned, "%c") then
		return nil
	end
	for _, code in utf8.codes(cleaned) do
		if isInvisible(code) then
			return nil
		end
	end
	local length = utf8.len(cleaned) or 0
	if length < minLength or length > maxLength then
		return nil
	end
	return cleaned
end

return Guard
