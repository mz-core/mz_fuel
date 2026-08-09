local function expect(condition, message)
  if not condition then error(message, 2) end
end

local coreState = 'started'
local exportMode = 'success'
local captured

function GetResourceState(name)
  return name == 'mz_core' and coreState or 'missing'
end

Config = { Debug = false }
exports = {
  mz_core = {
    CreateDetailedLog = function(_, scope, action, payload)
      captured = { scope = scope, action = action, payload = payload }
      if exportMode == 'error' then error('export unavailable') end
      if exportMode == 'failed' then return false end
      return 42
    end
  }
}

dofile('server/logs.lua')

local ok, result = MZFuelLogs.Refuel(7, {
  plate = ' mz1234 ',
  liters = 12.5,
  price = 150,
  account = 'cash'
})
expect(ok == true and result == 42, 'canonical log write was not reported as successful')
expect(captured.scope == 'fuel' and captured.action == 'refuel', 'logging scope/action drifted')
expect(captured.payload.actor.id == 'source:7' and captured.payload.actor.source == 7,
  'logging actor was not mapped')
expect(captured.payload.target.type == 'vehicle' and captured.payload.target.id == 'MZ1234',
  'logging target was not mapped')
expect(captured.payload.after.liters == 12.5 and captured.payload.after.price == 150,
  'refuel result was not mapped to detailed log payload')

exportMode = 'failed'
ok, result = MZFuelLogs.Refuel(7, { plate = 'MZ1234' })
expect(ok == false and result == 'log_write_failed', 'false log write was treated as success')

exportMode = 'error'
ok, result = MZFuelLogs.Refuel(7, { plate = 'MZ1234' })
expect(ok == false and result == 'log_export_unavailable', 'export exception was not isolated')

coreState = 'stopped'
ok, result = MZFuelLogs.Refuel(7, {})
expect(ok == false and result == 'mz_core_unavailable', 'missing core did not fail closed')

local sourceFile = assert(io.open('server/logs.lua', 'rb')):read('*a')
expect(not sourceFile:find(':CreateLog(', 1, true), 'legacy nonexistent CreateLog contract remains')
expect(sourceFile:find(':CreateDetailedLog(', 1, true), 'canonical CreateDetailedLog contract missing')

print('[logging_contract_harness] PASS success=1 failures=3 contract=canonical')
