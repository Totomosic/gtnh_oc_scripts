local sides = require('sides')
local component = require('component')
local computer = require('computer')
local term = require('term')
local t = component.proxy(component.list('transposer')())

local ssassEuT = 3.28e13
local antimatterSide = sides.west
local target = 580688

local matterExponent = 1.03
local euPerBurn = 1e12 * (target ^ matterExponent)
local burnIntervals = {}
local antimatterGainRates = {}
local lastBurnStartTime = nil
local lastTimeBetweenBurns = nil
local burnCount = 0
local lastAntimatterLevel = nil
local lastAntimatterSampleTime = nil

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

  local absValue = math.abs(value)
  local shortSuffixes = {
    [0] = "",
    "K",
    "M",
    "G",
    "T",
    "P",
    "E",
  }

  local suffixIndex = 0
  local scaled = absValue
  while scaled >= 1000 and suffixIndex < #shortSuffixes do
    scaled = scaled / 1000
    suffixIndex = suffixIndex + 1
  end

  if value < 0 then
    scaled = -scaled
  end

  local shortValue
  if suffixIndex == 0 then
    shortValue = string.format("%.0f", scaled)
  elseif math.abs(scaled) >= 100 then
    shortValue = string.format("%.0f%s", scaled, shortSuffixes[suffixIndex])
  elseif math.abs(scaled) >= 10 then
    shortValue = string.format("%.1f%s", scaled, shortSuffixes[suffixIndex])
  else
    shortValue = string.format("%.2f%s", scaled, shortSuffixes[suffixIndex])
  end

  return string.format("%.3e (%s)", value, shortValue)
end

local function formatInteger(value)
  if value == nil then
    return "n/a"
  end

  return string.format("%d", math.floor(value + 0.5))
end

local function addBurnInterval(interval)
  table.insert(burnIntervals, interval)
  if #burnIntervals > 10 then
    table.remove(burnIntervals, 1)
  end
end

local function rollingAverageInterval()
  if #burnIntervals == 0 then
    return nil
  end

  local total = 0
  for i = 1, #burnIntervals do
    total = total + burnIntervals[i]
  end

  return total / #burnIntervals
end

local function addAntimatterGainRate(gainRate)
  table.insert(antimatterGainRates, gainRate)
  if #antimatterGainRates > 10 then
    table.remove(antimatterGainRates, 1)
  end
end

local function rollingAverageAntimatterGainRate()
  if #antimatterGainRates == 0 then
    return nil
  end

  local total = 0
  for i = 1, #antimatterGainRates do
    total = total + antimatterGainRates[i]
  end

  return total / #antimatterGainRates
end

local function logStatus(antimatterLevel, didBurn)
  local averageBurnInterval = rollingAverageInterval()
  local averageAntimatterGainRate = rollingAverageAntimatterGainRate()
  local euPerTick = nil
  if averageBurnInterval ~= nil and averageBurnInterval > 0 then
    euPerTick = euPerBurn / averageBurnInterval / 20
  end

  term.clear()
  term.setCursor(1, 1)

  print("SLAM status")
  print("-----------")
  print(string.format("Antimatter: %d / %d", antimatterLevel, target))
  print(string.format("Antimatter gain/s (rolling avg): %s", formatInteger(averageAntimatterGainRate)))
  print(string.format("Burn happened this cycle: %s", didBurn and "yes" or "no"))
  print(string.format("Total burns: %d", burnCount))
  print(string.format("Time between last burns: %s", formatSeconds(lastTimeBetweenBurns)))
  print(string.format("Rolling avg time between burns (last %d): %s", #burnIntervals, formatSeconds(averageBurnInterval)))
  print(string.format("EU/Burn: %s", formatScientific(euPerBurn)))
  print(string.format("EU/t: %s", formatScientific(euPerTick)))
  if euPerTick ~= nil then
    print(string.format("EU/t Net: %s", formatScientific(euPerTick - ssassEuT)))
  end
end

while true do
  -- Extract Fluid
  local level1 = t.getTankLevel(sides.west)
  local level2 = t.getTankLevel(sides.east)
  local didBurn = false
    
  if (level1 >= target) and (level2 >= target) then
    local burnStartTime = computer.uptime()
    if lastBurnStartTime ~= nil then
      lastTimeBetweenBurns = burnStartTime - lastBurnStartTime
      addBurnInterval(lastTimeBetweenBurns)
    end

    t.transferFluid(sides.west, sides.down, target)
    t.transferFluid(sides.east, sides.down, target)

    lastBurnStartTime = burnStartTime
    burnCount = burnCount + 1
    didBurn = true

  end

  local antimatterLevel = t.getTankLevel(antimatterSide)
  local sampleTime = computer.uptime()
  if lastAntimatterLevel ~= nil and lastAntimatterSampleTime ~= nil then
    local elapsed = sampleTime - lastAntimatterSampleTime
    if elapsed > 0 then
      local gained = antimatterLevel - lastAntimatterLevel
      if gained < 0 then
        gained = gained + target
      end
      local gainRate = gained / elapsed
      addAntimatterGainRate(gainRate)
    end
  end
  lastAntimatterLevel = antimatterLevel
  lastAntimatterSampleTime = sampleTime

  logStatus(antimatterLevel, didBurn)

  -- Sleep 5 Seconds
  os.sleep(5)
end
