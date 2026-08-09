MZFuelLogs = MZFuelLogs or {}

function MZFuelLogs.Refuel(source, payload)
  payload = type(payload) == 'table' and payload or {}

  if GetResourceState('mz_core') ~= 'started' then
    return false, 'mz_core_unavailable'
  end

  local sourceId = tonumber(source) or 0
  local plate = tostring(payload.plate or 'unknown'):upper():gsub('^%s+', ''):gsub('%s+$', ''):sub(1, 16)
  if plate == '' then plate = 'unknown' end

  local callOk, logId = pcall(function()
    return exports['mz_core']:CreateDetailedLog('fuel', 'refuel', {
      actor = {
        type = sourceId > 0 and 'player' or 'system',
        id = sourceId > 0 and ('source:%s'):format(sourceId) or 'system',
        source = sourceId > 0 and sourceId or nil
      },
      target = { type = 'vehicle', id = plate },
      context = { source = sourceId, plate = plate },
      after = {
        liters = tonumber(payload.liters) or 0.0,
        price = tonumber(payload.price) or 0.0,
        account = tostring(payload.account or 'unknown'):sub(1, 32)
      },
      meta = { event = 'refuel', resource = 'mz_fuel' }
    })
  end)

  if callOk and logId ~= nil and logId ~= false then
    return true, logId
  end

  if Config.Debug == true then
    print(('[mz_fuel] log adapter unavailable for refuel plate=%s'):format(tostring(payload.plate or '')))
  end

  return false, callOk and 'log_write_failed' or 'log_export_unavailable'
end
