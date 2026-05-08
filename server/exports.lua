exports('SaveFuelByPlate', function(plate, fuel)
  return MZFuelPersistence.SaveFuelByPlate(plate, fuel)
end)

exports('GetCachedFuelByPlate', function(plate)
  return MZFuelPersistence.GetCachedFuelByPlate(plate)
end)
