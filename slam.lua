local sides = require('sides')
local component = require('component')
local computer = require('computer')
local term = require('term')
local t = component.proxy(component.list('transposer')())

local antimatterSide = sides.west
local target = 43646

local matterExponent = 1.03
local euPerBurn = 1e12 * (target ^ matterExponent)
local burnDurations = {}
local lastBurnDuration = nil
local lastBurnStartTime = nil
local lastTimeBetweenBurns = nil
local burnCount = 0

local function formatSeconds(seconds)
  if seconds == nil then
    return "n/a"
  end

  return string.format("%.2fs", seconds)
end

local function formatScientific(value)
  if value == nil then
    return "n/a"
  end

  return string.format("%.3e", value)
end

local function addBurnDuration(duration)
  table.insert(burnDurations, duration)
  if #burnDurations > 10 then
    table.remove(burnDurations, 1)
  end
end

local function rollingAverageDuration()
  if #burnDurations == 0 then
    return nil
  end

  local total = 0
  for i = 1, #burnDurations do
    total = total + burnDurations[i]
  end

  return total / #burnDurations
end

local function logStatus(antimatterLevel, didBurn)
  local averageBurnDuration = rollingAverageDuration()
  local euPerTick = nil
  if averageBurnDuration ~= nil and averageBurnDuration > 0 then
    euPerTick = euPerBurn / averageBurnDuration / 20
  end

  term.clear()
  term.setCursor(1, 1)

  print("SLAM status")
  print("-----------")
  print(string.format("Antimatter: %d / %d", antimatterLevel, target))
  print(string.format("Burn happened this cycle: %s", didBurn and "yes" or "no"))
  print(string.format("Total burns: %d", burnCount))
  print(string.format("Last burn duration: %s", formatSeconds(lastBurnDuration)))
  print(string.format("Time between last burns: %s", formatSeconds(lastTimeBetweenBurns)))
  print(string.format("Rolling average (last %d burns): %s", #burnDurations, formatSeconds(averageBurnDuration)))
  print(string.format("EU/Burn: %s", formatScientific(euPerBurn)))
  print(string.format("EU/t (rolling avg): %s", formatScientific(euPerTick)))
end

while true do
  -- Extract Fluid
  local level1 = t.getTankLevel(sides.west)
  local level2 = t.getTankLevel(sides.east)
  local antimatterLevel = t.getTankLevel(antimatterSide)
  local didBurn = false
    
  if (level1 >= target) and (level2 >= target) then
    local burnStartTime = computer.uptime()
    if lastBurnStartTime ~= nil then
      lastTimeBetweenBurns = burnStartTime - lastBurnStartTime
    end

    t.transferFluid(sides.west, sides.down, target)
    t.transferFluid(sides.east, sides.down, target)

    local burnEndTime = computer.uptime()
    lastBurnDuration = burnEndTime - burnStartTime
    lastBurnStartTime = burnStartTime
    burnCount = burnCount + 1
    didBurn = true

    addBurnDuration(lastBurnDuration)
  end

  logStatus(antimatterLevel, didBurn)

  -- Sleep 5 Seconds
  os.sleep(5)
end
