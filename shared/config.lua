Config = Config or {}

Config.Debug = false
Config.DebugCommands = false
Config.DebugAce = 'mz_fuel.debug'
Config.UpdateIntervalMs = 1000
Config.SaveIntervalMs = 15000
Config.MinFuel = 0.0
Config.MaxFuel = 100.0
Config.DefaultFuel = 100.0
Config.UseStateBag = true
Config.UseNativeFuelLevel = true
Config.DisableOnBicycles = true
Config.DisableOnElectric = false
Config.ConsumptionMultiplier = 1.0
Config.SaveOnExitVehicle = true
Config.SaveWhenDriver = true

Config.DisableNativeFuelConsumption = true
Config.MinimumSaveDelta = 0.2
Config.StopEngineWhenEmpty = true

Config.Stations = {
  enabled = true,
  blips = {
    enabled = true,
    sprite = 361,
    color = 0,
    scale = 0.7,
    shortRange = true,
    name = 'Posto de combustivel'
  },
  marker = {
    type = 1,
    radius = 4.0,
    drawDistance = 18.0,
    color = { r = 57, g = 229, b = 140, a = 110 }
  },
  locations = {
    vec3(49.4187, 2778.793, 58.043),
    vec3(263.894, 2606.463, 44.983),
    vec3(1039.958, 2671.134, 39.550),
    vec3(1207.260, 2660.175, 37.899),
    vec3(2539.685, 2594.192, 37.944),
    vec3(2679.858, 3263.946, 55.240),
    vec3(2005.055, 3773.887, 32.403),
    vec3(1687.156, 4929.392, 42.078),
    vec3(1701.314, 6416.028, 32.763),
    vec3(179.857, 6602.839, 31.868),
    vec3(-94.4619, 6419.594, 31.489),
    vec3(-2554.996, 2334.40, 33.078),
    vec3(-1800.375, 803.661, 138.651),
    vec3(-1437.622, -276.747, 46.207),
    vec3(-2096.243, -320.286, 13.168),
    vec3(-724.619, -935.1631, 19.213),
    vec3(-526.019, -1211.003, 18.184),
    vec3(-70.2148, -1761.792, 29.534),
    vec3(265.648, -1261.309, 29.292),
    vec3(819.653, -1028.846, 26.403),
    vec3(1208.951, -1402.567, 35.224),
    vec3(1181.381, -330.847, 69.316),
    vec3(620.843, 269.100, 103.089),
    vec3(2581.321, 362.039, 108.468),
    vec3(176.631, -1562.025, 29.263),
    vec3(-319.292, -1471.715, 30.549),
    vec3(1784.324, 3330.55, 41.253)
  }
}

Config.Refuel = {
  pricePerLiter = 5,
  paymentAccount = 'cash',
  tickMs = 1000,
  litersPerTick = 1.0,
  maxDistance = 6.0,
  paidCreditTtlMs = 120000,
  requireDriver = true,
  allowInsideVehicle = true,
  saveOnComplete = true,
  useMenu = false,
  menuMode = 'simple',
  maxLitersPerRequest = 100.0,
  allowFillTank = true,
  allowMoneyAmount = true,
  allowLiterAmount = true
}

Config.JerryCan = {
  enabled = false,
  item = 'WEAPON_PETROLCAN',
  inventoryItem = 'jerrycan',
  litersPerUse = 10.0,
  useTimeMs = 6000,
  maxDistance = 3.0,
  consumeItem = false,
  requireOutsideVehicle = true,
  authorizedCreditTtlMs = 120000,
  allowWithoutInventory = false
}

Config.Notify = {
  enabled = true,
  resource = 'mz_notify',
  fallback = true,
  messages = {
    refuelStarted = 'Abastecimento iniciado.',
    refuelFinished = 'Veiculo abastecido.',
    refuelCanceled = 'Abastecimento cancelado.',
    noMoney = 'Dinheiro insuficiente.',
    vehicleFull = 'O veiculo ja esta cheio.',
    invalidVehicle = 'Veiculo invalido.',
    driverRequired = 'Entre no banco do motorista para abastecer.',
    tooFar = 'Voce esta longe demais do posto.',
    paymentUnavailable = 'Pagamento indisponivel.',
    rateLimited = 'Aguarde um instante para tentar novamente.',
    jerrycanStarted = 'Usando galao de combustivel.',
    jerrycanFinished = 'Combustivel adicionado.',
    jerrycanCanceled = 'Uso do galao cancelado.',
    noJerrycan = 'Voce nao possui um galao.'
  }
}

Config.Payment = {
  enabled = true,
  allowFallbackWithoutMzCore = false,
  accountAliases = {
    cash = 'wallet',
    wallet = 'wallet',
    bank = 'bank',
    dirty = 'dirty'
  }
}

Config.Interaction = {
  mode = 'auto', -- 'auto', 'target', 'interact', 'marker', 'none'
  prefer = 'target',
  fallbackMarker = true
}

Config.ConsumptionByClass = {
  [0] = 0.55,
  [1] = 0.55,
  [2] = 0.65,
  [3] = 0.60,
  [4] = 0.85,
  [5] = 0.75,
  [6] = 0.80,
  [7] = 1.00,
  [8] = 0.45,
  [9] = 0.90,
  [10] = 1.10,
  [11] = 1.05,
  [12] = 1.00,
  [13] = 0.0,
  [14] = 0.25,
  [15] = 1.30,
  [16] = 1.50,
  [17] = 0.75,
  [18] = 0.85,
  [19] = 1.20,
  [20] = 1.15,
  [21] = 1.40,
  [22] = 0.65
}

Config.ConsumptionByCategory = {
  compact = 0.55,
  sedan = 0.55,
  suv = 0.65,
  coupe = 0.65,
  muscle = 0.85,
  sport = 0.85,
  super = 1.0,
  motorcycle = 0.45,
  offroad = 0.90,
  industrial = 1.10,
  utility = 1.05,
  van = 1.0,
  cycle = 0.0,
  boat = 0.25,
  helicopter = 1.30,
  plane = 1.50,
  service = 0.75,
  emergency = 0.85,
  military = 1.20,
  commercial = 1.15,
  train = 1.40,
  openwheel = 0.65
}

Config.ElectricModels = {
  airtug = true,
  caddy = true,
  caddy2 = true,
  caddy3 = true,
  cyclone = true,
  dilettante = true,
  imorgon = true,
  khamelion = true,
  neon = true,
  omnisegt = true,
  raiden = true,
  surge = true,
  tezeract = true,
  virtue = true,
  voltic = true,
  voltic2 = true
}
