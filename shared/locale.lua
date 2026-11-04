-- MZ global locale switch, seguindo o mesmo convar usado por mz_target/mz_radialmenu.
-- pt-br e o padrao; en-us e o fallback.
MZFuelLocale = MZFuelLocale or {}

local Dictionaries = {}

local function normalizeLocale(value)
  value = tostring(value or ''):lower()
  if value == '' or value == 'pt' then
    return 'pt-br'
  end

  if value == 'en' then
    return 'en-us'
  end

  return value
end

local selectedLocale = normalizeLocale(GetConvar('ox:locale', 'pt-br'))

local function loadDictionary(code)
  code = normalizeLocale(code)
  if Dictionaries[code] ~= nil then
    return Dictionaries[code]
  end

  local raw = LoadResourceFile(GetCurrentResourceName(), ('locales/%s.json'):format(code))
  local dictionary = {}

  if raw and raw ~= '' then
    local ok, decoded = pcall(json.decode, raw)
    if ok and type(decoded) == 'table' then
      dictionary = decoded
    end
  end

  Dictionaries[code] = dictionary
  return dictionary
end

function MZFuelLocale.Get(key)
  key = tostring(key or '')
  if key == '' then
    return nil
  end

  local order = { selectedLocale, 'pt-br', 'en-us' }
  local seen = {}

  for _, code in ipairs(order) do
    if not seen[code] then
      seen[code] = true
      local value = loadDictionary(code)[key]
      if type(value) == 'string' and value ~= '' then
        return value
      end
    end
  end

  return nil
end

function MZFuelText(key, values)
  local phrase = MZFuelLocale.Get(key)
  if not phrase then
    return tostring(key or '')
  end

  for name, value in pairs(values or {}) do
    phrase = phrase:gsub('{' .. tostring(name) .. '}', tostring(value))
  end

  return phrase
end

function MZFuelLocale.GetCode()
  return selectedLocale
end
