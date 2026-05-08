MZFuelNotify = MZFuelNotify or {}

local ActiveProgress = {}
local ProgressThreadRunning = false

local function notifyConfig()
  return type(Config.Notify) == 'table' and Config.Notify or {}
end

local function getMessage(key, fallback)
  local messages = type(notifyConfig().messages) == 'table' and notifyConfig().messages or {}
  return tostring(messages[key] or fallback or key or '')
end

local function drawText(text, x, y, scale, center)
  SetTextFont(4)
  SetTextScale(scale, scale)
  SetTextColour(255, 255, 255, 230)
  SetTextOutline()
  SetTextCentre(center == true)
  BeginTextCommandDisplayText('STRING')
  AddTextComponentSubstringPlayerName(tostring(text or ''))
  EndTextCommandDisplayText(x, y)
end

local function drawProgress(label, percent)
  percent = math.max(0.0, math.min(1.0, tonumber(percent) or 0.0))

  local x = 0.5
  local y = 0.88
  local width = 0.24
  local height = 0.018
  DrawRect(x, y, width + 0.006, height + 0.008, 0, 0, 0, 150)
  DrawRect(x, y, width, height, 20, 20, 20, 210)
  DrawRect(x - (width / 2.0) + ((width * percent) / 2.0), y, width * percent, height, 57, 229, 140, 220)
  drawText(label, x, y - 0.036, 0.32, true)
end

local function ensureProgressThread()
  if ProgressThreadRunning == true then
    return
  end

  ProgressThreadRunning = true
  CreateThread(function()
    while true do
      local now = GetGameTimer()
      local hasProgress = false

      for id, progress in pairs(ActiveProgress) do
        local expiresAt = tonumber(progress.expiresAt) or 0
        if expiresAt <= now then
          ActiveProgress[id] = nil
        else
          hasProgress = true
          local duration = math.max(1, tonumber(progress.durationMs) or 1)
          local elapsed = now - (tonumber(progress.startedAt) or now)
          drawProgress(progress.label, elapsed / duration)
        end
      end

      if hasProgress ~= true then
        ProgressThreadRunning = false
        return
      end

      Wait(0)
    end
  end)
end

function MZFuelNotify.Message(key, fallback)
  return getMessage(key, fallback)
end

function MZFuelNotify.Notify(message, notifyType)
  local cfg = notifyConfig()
  if cfg.enabled == false then
    return
  end

  message = tostring(message or '')
  if message == '' then
    return
  end

  local resource = tostring(cfg.resource or 'mz_notify')
  if resource ~= '' and GetResourceState(resource) == 'started' then
    local ok = pcall(function()
      exports[resource]:Notify({
        title = 'Combustivel',
        message = message,
        type = notifyType or 'inform'
      })
    end)

    if ok then
      return
    end
  end

  if cfg.fallback ~= true then
    return
  end

  BeginTextCommandThefeedPost('STRING')
  AddTextComponentSubstringPlayerName(message)
  EndTextCommandThefeedPostTicker(false, false)
end

function MZFuelNotify.NotifyKey(key, notifyType, fallback)
  MZFuelNotify.Notify(getMessage(key, fallback), notifyType)
end

function MZFuelNotify.StartProgress(id, label, durationMs)
  if notifyConfig().enabled == false then
    return
  end

  id = tostring(id or '')
  if id == '' then
    return
  end

  durationMs = math.max(250, tonumber(durationMs) or 1000)
  ActiveProgress[id] = {
    label = tostring(label or ''),
    startedAt = GetGameTimer(),
    durationMs = durationMs,
    expiresAt = GetGameTimer() + durationMs
  }

  ensureProgressThread()
end

function MZFuelNotify.StopProgress(id)
  id = tostring(id or '')
  if id == '' then
    return
  end

  ActiveProgress[id] = nil
end
