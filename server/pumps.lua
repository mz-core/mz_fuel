MZFuelPumpsServer = MZFuelPumpsServer or {}

local PumpLocks = {}
local ClaimThrottle = {}

local function refuelConfig()
  return type(Config.Refuel) == 'table' and Config.Refuel or {}
end

local function debugPrint(tag, fields)
  if Config.Debug ~= true then
    return
  end

  local parts = {}
  for key, value in pairs(fields or {}) do
    parts[#parts + 1] = ('%s=%s'):format(tostring(key), tostring(value))
  end

  print(('[mz_fuel][%s] %s'):format(tostring(tag), table.concat(parts, ' ')))
end

local function isValidSource(source)
  source = tonumber(source) or 0
  return source > 0 and GetPlayerName(source) ~= nil
end

local function normalizeCoords(coords)
  if type(coords) ~= 'table' then
    return nil
  end

  local x = tonumber(coords.x or coords[1])
  local y = tonumber(coords.y or coords[2])
  local z = tonumber(coords.z or coords[3])
  if not x or not y or not z then
    return nil
  end

  return vector3(x, y, z)
end

local function stationForId(stationId)
  stationId = tonumber(stationId) or 0
  local locations = Config.Stations and Config.Stations.locations or {}
  if stationId <= 0 or stationId > #locations then
    return nil, nil
  end

  return stationId, locations[stationId]
end

function MZFuelPumpsServer.ValidatePump(source, pump, stationId, station)
  source = tonumber(source) or 0
  if not isValidSource(source) then
    return false, 'invalid_source'
  end

  local pumpCoords = normalizeCoords(pump)
  if not pumpCoords then
    return false, 'pump_invalid'
  end

  local resolvedId, configuredStation = stationForId(stationId)
  local hasStation = resolvedId ~= nil and configuredStation ~= nil

  if hasStation then
    local pumpRadius = tonumber(refuelConfig().pumpStationRadius) or 40.0
    if #(pumpCoords - configuredStation) > pumpRadius then
      return false, 'pump_not_near_station'
    end
  elseif stationId ~= nil and tonumber(stationId) ~= nil and tonumber(stationId) > 0 then
    return false, 'station_invalid'
  end

  local ped = GetPlayerPed(source)
  if not ped or ped == 0 then
    return false, 'player_invalid'
  end

  local maxDistance = math.max(
    tonumber(refuelConfig().pumpTargetDistance) or 2.6,
    tonumber(refuelConfig().maxPumpDistance) or 10.0
  )

  if #(GetEntityCoords(ped) - pumpCoords) > maxDistance then
    return false, 'pump_distance_invalid'
  end

  if hasStation and station then
    local stationCoords = normalizeCoords(station)
    if not stationCoords or #(stationCoords - configuredStation) > 2.5 then
      return false, 'station_mismatch'
    end
  elseif station and not hasStation then
    -- Se o client enviar uma estacao mas ela nao existir na configuracao,
    -- a coordenada da bomba continua sendo a fonte de verdade para a sessao.
    local stationCoords = normalizeCoords(station)
    if not stationCoords then
      return false, 'station_invalid'
    end
  end

  return true
end

local function cleanupLocks()
  local now = GetGameTimer()
  for key, lock in pairs(PumpLocks) do
    if type(lock) ~= 'table' or (tonumber(lock.expiresAt) or 0) <= now then
      PumpLocks[key] = nil
    end
  end
end

local function makeToken(source, key)
  return ('%s:%s:%s:%s'):format(tostring(source), tostring(key), GetGameTimer(), math.random(100000, 999999))
end

function MZFuelPumpsServer.Claim(source, pumpKey, stationId, pumpCoords, stationCoords)
  source = tonumber(source) or 0
  pumpKey = tostring(pumpKey or '')
  if not isValidSource(source) or pumpKey == '' or #pumpKey > 128 then
    return false, 'invalid_claim', nil
  end

  local ok, reason = MZFuelPumpsServer.ValidatePump(source, pumpCoords, stationId, stationCoords)
  if not ok then
    return false, reason, nil
  end

  local now = GetGameTimer()
  local lastClaim = tonumber(ClaimThrottle[source]) or 0
  if lastClaim > 0 and now - lastClaim < 1000 then
    return false, 'rate_limited', nil
  end
  ClaimThrottle[source] = now

  cleanupLocks()

  local existing = PumpLocks[pumpKey]
  if existing and existing.source ~= source and (tonumber(existing.expiresAt) or 0) > GetGameTimer() then
    return false, 'pump_busy', nil
  end

  local token = makeToken(source, pumpKey)
  local ttl = math.max(30000, tonumber(refuelConfig().pumpLockTtlMs) or 300000)

  PumpLocks[pumpKey] = {
    source = source,
    token = token,
    expiresAt = GetGameTimer() + ttl,
    stationId = tonumber(stationId) or 0
  }

  debugPrint('pump_claim', {
    source = source,
    pump = pumpKey,
    station = stationId
  })

  return true, nil, token
end

function MZFuelPumpsServer.Release(source, pumpKey, token)
  source = tonumber(source) or 0
  pumpKey = tostring(pumpKey or '')
  token = tostring(token or '')
  local lock = PumpLocks[pumpKey]

  if type(lock) ~= 'table' or lock.source ~= source then
    return false
  end

  if token ~= '' and lock.token ~= token then
    return false
  end

  PumpLocks[pumpKey] = nil
  debugPrint('pump_release', { source = source, pump = pumpKey })
  return true
end

function MZFuelPumpsServer.ReleaseSource(source)
  source = tonumber(source) or 0
  local removed = 0

  for key, lock in pairs(PumpLocks) do
    if type(lock) ~= 'table' or lock.source == source then
      PumpLocks[key] = nil
      removed = removed + 1
    end
  end

  return removed
end

function MZFuelPumpsServer.IsLockedBy(source, pumpKey)
  source = tonumber(source) or 0
  pumpKey = tostring(pumpKey or '')
  local lock = PumpLocks[pumpKey]
  return type(lock) == 'table'
    and lock.source == source
    and (tonumber(lock.expiresAt) or 0) > GetGameTimer()
end

RegisterNetEvent('mz_fuel:server:claimPump', function(payload)
  local src = source
  payload = type(payload) == 'table' and payload or {}

  local requestId = tostring(payload.request_id or payload.requestId or '')
  local ok, reason, token = MZFuelPumpsServer.Claim(
    src,
    payload.pump_key or payload.pumpKey,
    payload.station_id or payload.stationId,
    payload.pump or payload.coords,
    payload.station
  )

  TriggerClientEvent('mz_fuel:client:pumpClaimResult', src, {
    request_id = requestId,
    ok = ok == true,
    error = reason,
    token = token
  })
end)

RegisterNetEvent('mz_fuel:server:releasePump', function(payload)
  local src = source
  payload = type(payload) == 'table' and payload or {}
  MZFuelPumpsServer.Release(src, payload.pump_key or payload.pumpKey, payload.token)
end)

AddEventHandler('playerDropped', function()
  MZFuelPumpsServer.ReleaseSource(source)
  ClaimThrottle[tonumber(source) or 0] = nil
end)

CreateThread(function()
  while true do
    Wait(60000)
    cleanupLocks()
  end
end)

exports('IsPumpLockedBy', function(source, pumpKey)
  return MZFuelPumpsServer.IsLockedBy(source, pumpKey)
end)
