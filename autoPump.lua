-- Credits: Fox, samsonsin, San32
local component = require('component')
local thread = require('thread')
local event = require('event')
local term = require('term')
local me = component.me_controller
local pumps = {}

-- CTRL+C to stop the script at any time, or restart the computer.

-- ===================== CONFIG ======================
-- Only change the PRIORITY and TARGET values. Do not change the SETTING or RATE values.
-- Quantum = 270e9 || Digital Singularity = 4e18 || Artificial Universe = 9e18

local master = {
  -- Planet 2 -----------------------------------------------------------------------------
  ['Chlorobenzene'] =     {target=10e9,  priority=1,  setting={2,1},  rate=896000}, -- Gas 1
  -- Planet 3 -----------------------------------------------------------------------------
  ['Ender Goo'] =         {target=0,     priority=1,  setting={3,1},  rate=32000}, -- Gas 1
  ['Very Heavy Oil'] =    {target=0,     priority=1,  setting={3,2},  rate=1400000}, -- Gas 2
  ['Lava'] =              {target=30e9,  priority=1,  setting={3,3},  rate=1800000}, -- Gas 3
  ['Natural Gas'] =       {target=0,     priority=1,  setting={3,4},  rate=1400000}, -- Gas 4
  -- Planet 4 -----------------------------------------------------------------------------
  ['Sulfuric Acid'] =     {target=50e9,  priority=1,  setting={4,1},  rate=784000}, -- Gas 1
  ['Molten Iron'] =       {target=50e9,  priority=2,  setting={4,2},  rate=896000}, -- Gas 2
  ['Oil'] =               {target=50e9,  priority=1,  setting={4,3},  rate=1400000}, -- Gas 3
  ['Heavy Oil'] =         {target=50e9,     priority=1,  setting={4,4},  rate=1792000}, -- Gas 4
  ['Molten Lead'] =       {target=50e9,  priority=1,  setting={4,5},  rate=896000}, -- Gas 5
  ['Raw Oil'] =           {target=0,     priority=1,  setting={4,6},  rate=1400000}, -- Gas 6
  ['Light Oil'] =         {target=0,     priority=1,  setting={4,7},  rate=780000}, -- Gas 7
  ['Carbon Dioxide'] =    {target=10e9,   priority=1,  setting={4,8},  rate=1680000}, -- Gas 8
  -- Planet 5 -----------------------------------------------------------------------------
  ['Carbon Monoxide'] =   {target=10e9,  priority=1,  setting={5,1},  rate=4480000}, -- Gas 1
  ['Helium-3'] =          {target=200e9,  priority=1,  setting={5,2},  rate=2800000}, -- Gas 2
  ['Salt Water'] =        {target=100e9,  priority=1,  setting={5,3},  rate=2800000}, -- Gas 3
  ['Helium'] =            {target=200e9,  priority=3,  setting={5,4},  rate=1400000}, -- Gas 4
  ['Liquid Oxygen'] =     {target=0,     priority=1,  setting={5,5},  rate=896000}, -- Gas 5
  ['Neon'] =              {target=10e9,   priority=1,  setting={5,6},  rate=32000}, -- Gas 6
  ['Argon'] =             {target=10e9,   priority=1,  setting={5,7},  rate=32000}, -- Gas 7
  ['Krypton'] =           {target=10e9,   priority=1,  setting={5,8},  rate=8000}, -- Gas 8
  ['Methane'] =           {target=10e9,   priority=1,  setting={5,9},  rate=1792000}, -- Gas 9
  ['Hydrogen Sulfide'] =  {target=0,     priority=1,  setting={5,10},  rate=392000}, -- Gas 10
  ['Ethane'] =            {target=0,     priority=1,  setting={5,11},  rate=1194000}, -- Gas 11
  -- Planet 6 -----------------------------------------------------------------------------
  ['Deuterium'] =         {target=100e9,  priority=1,  setting={6,1},  rate=1568000}, -- Gas 1
  ['Tritium'] =           {target=100e9,  priority=1,  setting={6,2},  rate=240000}, -- Gas 2
  ['Ammonia'] =           {target=50e9,  priority=2,  setting={6,3},  rate=240000}, -- Gas 3
  ['Xenon'] =             {target=100e9,  priority=1,  setting={6,4},  rate=16000}, -- Gas 4
  ['Ethylene'] =          {target=50e9,  priority=1,  setting={6,5},  rate=1792000}, -- Gas 5
  -- Planet 7 -----------------------------------------------------------------------------
  ['Hydrofluoric Acid'] = {target=50e9,  priority=1,  setting={7,1},  rate=672000}, -- Gas 1
  ['Fluorine'] =          {target=200e9,  priority=3,  setting={7,2},  rate=1792000}, -- Gas 2
  ['Nitrogen'] =          {target=200e9,  priority=3,  setting={7,3},  rate=1792000}, -- Gas 3
  ['Oxygen'] =            {target=200e9,  priority=3,  setting={7,4},  rate=1729000}, -- Gas 4
  -- Planet 8 -----------------------------------------------------------------------------
  ['Hydrogen'] =          {target=200e9,  priority=3,  setting={8,1},  rate=1568000}, -- Gas 1
  ['Liquid Air'] =        {target=100e9,     priority=3,  setting={8,2},  rate=875000}, -- Gas 2
  ['Molten Copper'] =     {target=50e9,  priority=2,  setting={8,3},  rate=672000}, -- Gas 3
  ['Unknown Liquid'] =    {target=10e9,  priority=1,  setting={8,4},  rate=672000}, -- Gas 4
  ['Distilled Water'] =   {target=100e9,  priority=3,  setting={8,5},  rate=17920000}, -- Gas 5
  ['Radon'] =             {target=50e9,   priority=2,  setting={8,6},  rate=64000}, -- Gas 6
  ['Molten Tin'] =        {target=50e9,  priority=1,  setting={8,7},  rate=672000}} -- Gas 7

-- The % of the Target when Considered Complete (Default: 95%)
local threshold = 0.95
-- Median mode target offset (Target = Median + Offset)
local dynamicTargetOffset = 10e9
-- Digital Singularity storage size. Used to avoid overfilling in median mode.
local singularityCellSize = 4.61e18
local maxStorageAmount = singularityCellSize * 0.99
-- The Upper Limit on the Duration of an Iteration (Default: 30s)
local maxBatchSize = 30
-- The Text Color (Default: '\27[1;36m')
local color = '\27[1;36m'

-- (https://github.com/torch/sys/blob/master/colors.lua)
-- Cyan = '\27[1;36m' || Green = '\27[1;32m' || Red = '\27[0;31m' || Magenta = '\27[0;35m'

-- =================== END CONFIG ====================
local phase = 'target'
local medianTarget = 0

local function findPumps()
  for address in component.list('gt_machine') do
    local module = component.proxy(address)
    local name = module.getName()

    if name == "projectmodulepumpt1" then -- T1 Module
      table.insert(pumps, {module=module, threads=1, mult=4, priority=1, fluid=nil, amount=0})
    elseif name == "projectmodulepumpt2" then -- T2 Module
      table.insert(pumps, {module=module, threads=4, mult=16, priority=2, fluid=nil, amount=0})
    elseif name == "projectmodulepumpt3" then -- T3 Module
      table.insert(pumps, {module=module, threads=4, mult=256, priority=3, fluid=nil, amount=0})
    end
  end

  -- Sort Based on Priority
  table.sort(pumps, function(a, b) return a.priority > b.priority end)
end

local function refreshFluidAmounts()
  for _, fluid in pairs(master) do fluid.amount = 0 end

  for _, fluid in ipairs(me.getFluidsInNetwork()) do
    if master[fluid.label] ~= nil then master[fluid.label].amount = fluid.amount end
  end

  for _, pump in ipairs(pumps) do
    if pump.fluid ~= nil then master[pump.fluid].amount = master[pump.fluid].amount + pump.amount end
  end
end

local function getMedianTarget()
  local amounts = {}
  for _, fluid in pairs(master) do table.insert(amounts, fluid.amount) end
  table.sort(amounts)

  if #amounts == 0 then return maxStorageAmount, 0 end

  local medianAmount = amounts[math.ceil(#amounts / 2)]
  return math.min(medianAmount + dynamicTargetOffset, maxStorageAmount), medianAmount
end

local function updateFluids()
  local lowFluids = {}
  refreshFluidAmounts()

  if phase == 'target' then
    for _, fluid in pairs(master) do
      if fluid.target > 0 and fluid.amount < threshold * fluid.target then
        table.insert(lowFluids, fluid)
      end
    end

    if #lowFluids == 0 then
      phase = 'median'
      for _, pump in ipairs(pumps) do pump.fluid, pump.amount = nil, 0 end
      refreshFluidAmounts()
      medianTarget = getMedianTarget()
      print(string.format('autoPump: Target phase complete. Switching to median mode (new target: %.3e L)', medianTarget))
    end
  end

  if phase == 'median' then
    for _, fluid in pairs(master) do
      if fluid.target > 0 and fluid.amount < threshold * fluid.target then
        table.insert(lowFluids, fluid)
      end
    end

    if #lowFluids > 0 then
      phase = 'target'
      print(string.format('autoPump: %d target fluid(s) dropped below threshold. Returning to target mode.', #lowFluids))
      return lowFluids
    end

    medianTarget = getMedianTarget()
    for _, fluid in pairs(master) do
      if fluid.amount < medianTarget and fluid.amount < maxStorageAmount then
        table.insert(lowFluids, fluid)
      end
    end
  end

  return lowFluids
end

local function updatePumps(lowFluids)
  for _, pump in ipairs(pumps) do

    -- Ensure Pump is Disabled
    pump.module.setWorkAllowed(false)
    while pump.module.isMachineActive() do os.sleep(2) end
    pump.fluid, pump.amount = nil, 0

    if phase == 'target' then
      table.sort(lowFluids, function(a, b)
        local aScore = 1 - (a.amount / a.target) ^ a.priority
        local bScore = 1 - (b.amount / b.target) ^ b.priority
        return aScore > bScore
      end)
    else
      table.sort(lowFluids, function(a, b)
        if a.priority ~= b.priority then
          return a.priority > b.priority
        end
        return (a.amount / medianTarget) < (b.amount / medianTarget)
      end)
    end

    local fluid = lowFluids[1]
    if fluid ~= nil then

      -- Change Planet and Gas for all Threads
      for i=1, pump.threads do
        pump.module.setParameters(2*(i-1), 0, fluid.setting[1]) -- Planet
        pump.module.setParameters(2*(i-1), 1, fluid.setting[2]) -- Gas
      end

      local desiredTarget = phase == 'target' and fluid.target or medianTarget
      local remaining = math.max(0, desiredTarget - fluid.amount)
      if remaining <= 0 then
        table.remove(lowFluids, 1)
      else
        -- Change Batch Size based on Distance from Target
        local batchSize = math.min(maxBatchSize, math.ceil(remaining / (fluid.rate * pump.mult)))
        pump.module.setParameters(9, 1, batchSize) -- Batch Size
        print(string.format('autoPump: [%s] Running %s for %d Seconds', phase, fluid.label, batchSize))

        -- Preemptively Update Fluid Amount
        pump.fluid = fluid.label
        pump.amount = batchSize * fluid.rate * pump.mult
        fluid.amount = fluid.amount + pump.amount

        if phase == 'target' then
          if fluid.amount >= threshold * fluid.target then table.remove(lowFluids, 1) end
        else
          if fluid.amount >= medianTarget then table.remove(lowFluids, 1) end
        end

        -- Run Once
        pump.module.setWorkAllowed(true)
        os.sleep(0.1)
        pump.module.setWorkAllowed(false)
      end
    else
      return
    end
  end
end

local function parse(label)
  local fluid = master[label]
  local target = phase == 'median' and medianTarget or fluid.target
  if target <= 0 then
    return string.format('[----------] %-20s', fluid.label)
  else
    local percent = math.min(10, math.ceil(10 * (fluid.amount / target)))
    return string.format('[%s%s] %-20s', color .. string.rep('■', percent) .. '\27[0m', string.rep('□', 10-percent), fluid.label)
  end
end

local function printDashboard()
  term.clear()
  print('\n┌─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐')
  local status
  if phase == 'median' then
    status = string.format(' Mode: MEDIAN  | Shared Target: %.3e L', medianTarget)
  else
    status = ' Mode: TARGET  | Shared Target: N/A'
  end
  print('│' .. color .. ' Space Elevator Fluid Levels (% of Target)' .. '\27[0m' .. status .. string.rep(' ', math.max(0, 58 - #status)) .. '│')
  print('├─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤')
  print(string.format('│ %s %s %s %s │', parse('Hydrogen'),      parse('Argon'),            parse('Oil'),             parse('Hydrogen Sulfide')))
  print(string.format('│ %s %s %s %s │', parse('Helium'),        parse('Radon'),            parse('Raw Oil'),         parse('Sulfuric Acid')))
  print(string.format('│ %s %s %s %s │', parse('Nitrogen'),      parse('Neon'),             parse('Light Oil'),       parse('Hydrofluoric Acid')))
  print(string.format('│ %s %s %s %s │', parse('Oxygen'),        parse('Krypton'),          parse('Heavy Oil'),       string.rep(' ', 33)))
  print(string.format('│ %s %s %s %s │', parse('Fluorine'),      parse('Xenon'),            parse('Natural Gas'),     string.rep(' ', 33)))
  print(string.format('│ %s %s %s %s │', string.rep(' ', 33),    string.rep(' ', 33),       string.rep(' ', 33),      string.rep(' ', 33)))
  print(string.format('│ %s %s %s %s │', parse('Molten Iron'),   parse('Ammonia'),          parse('Distilled Water'), parse('Helium-3')))
  print(string.format('│ %s %s %s %s │', parse('Molten Copper'), parse('Ethylene'),         parse('Salt Water'),      parse('Deuterium')))
  print(string.format('│ %s %s %s %s │', parse('Molten Tin'),    parse('Ethane'),           parse('Chlorobenzene'),   parse('Tritium')))
  print(string.format('│ %s %s %s %s │', parse('Molten Lead'),   parse('Methane'),          parse('Unknown Liquid'),  string.rep(' ', 33)))
  print(string.format('│ %s %s %s %s │', string.rep(' ', 33),    string.rep(' ', 33),       string.rep(' ', 33),      string.rep(' ', 33)))
  print(string.format('│ %s %s %s %s │', parse('Liquid Air'),    parse('Carbon Monoxide'),  parse('Lava'),            string.rep(' ', 33)))
  print(string.format('│ %s %s %s %s │', parse('Liquid Oxygen'), parse('Carbon Dioxide'),   parse('Ender Goo'),       string.rep(' ', 33)))
  print('└─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘\n')
end

local keyHandler = thread.create(function()
  local keyboard = require('keyboard')
  while true do
    _, _, _, code, _ = term.pull('key_down')
    if code == keyboard.keys.p then printDashboard()
    elseif code == keyboard.keys.u then
      pumps = {}
      findPumps()
    end
  end
end)

-- ====================== MAIN =======================

local main = thread.create(function()
  local n = 0
  findPumps()
  for k, fluid in pairs(master) do fluid.label = k end

  -- THE LOOP
  while true do

    -- Update Fluid Amounts
    local lowFluids = updateFluids()
    if next(lowFluids) ~= nil then

      if n % 5 == 0 then printDashboard() end

      -- Update Pump Settings
      updatePumps(lowFluids)
      n = n+1

    else
      for _, pump in ipairs(pumps) do
        pump.fluid, pump.amount = nil, 0
      end

      printDashboard()
      if phase == 'median' then
        print('autoPump: Median target currently met. Sleeping...\n')
      else
        print('autoPump: Sleeping...\n')
      end
      os.sleep(180)
      n=0
    end
  end
end)

local cleanUp = thread.create(function()
    event.pull('interrupted')
    term.clear()
    print('Received Exit Command!')
    for _, pump in ipairs(pumps) do
      for _=1, pump.threads do pump.module.setWorkAllowed(false) end
    end
    main.kill()
    keyHandler.kill()
    os.exit(0)
end)

thread.waitForAny({main, keyHandler, cleanUp})
os.exit(0)
