local sides = require('sides')
local component = require('component')
local t = component.proxy(component.list('transposer')())
local target = 43646

while true do
  -- Extract Fluid
  local level1 = t.getTankLevel(sides.west)
  local level2 = t.getTankLevel(sides.east)
    
  if (level1 >= target) and (level2 >= target) then
    t.transferFluid(sides.west, sides.down, target)
    t.transferFluid(sides.east, sides.down, target)
  end

  -- Sleep 5 Seconds
  os.sleep(5)
end
