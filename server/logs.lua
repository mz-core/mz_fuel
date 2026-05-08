MZFuelLogs = MZFuelLogs or {}

function MZFuelLogs.Refuel(source, payload)
  payload = type(payload) == 'table' and payload or {}

  if GetResourceState('mz_core') ~= 'started' then
    return false, 'mz_core_unavailable'
  end

  local ok = pcall(function()
    return exports['mz_core']:CreateLog('fuel', 'refuel', source, payload.plate or 'unknown', payload)
  end)

  if ok then
    return true
  end

  if Config.Debug == true then
    print(('[mz_fuel] log adapter unavailable for refuel plate=%s'):format(tostring(payload.plate or '')))
  end

  return false, 'log_export_unavailable'
end
