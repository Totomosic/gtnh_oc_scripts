local component = require("component")
local computer = require("computer")
local sides = require("sides")
local term = require("term")

local function getTransposers()
    local hatch_transposers = {}
    local all_components = component.list()
    local out_transposer = nil
    for addr, comp in pairs(all_components) do
        if comp == "transposer" then
            --print(os.time())
            local proxy = component.proxy(addr)
            local enderSide = -1
            local antiSide = -1
            local pipeSide = -1
            local interfaceSide = -1
            for side = 0, 5 do
                local capacity = proxy.getTankCapacity(side)
                if capacity == 256000 then
                    enderSide = side
                elseif capacity == 16384000 then
                    antiSide = side
                elseif capacity == 16000 then
                    interfaceSide = side
                elseif capacity > 0 then
                    pipeSide = side
                end
            end
            if interfaceSide >= 0 and enderSide >= 0 and antiSide < 0 and pipeSide < 0 and out_transposer == nil then
                out_transposer = {proxy, enderSide, interfaceSide}
            else
                if enderSide < 0 or antiSide < 0 or pipeSide < 0 then
                    print("Error: transposer with address " .. addr .. " is not set up correctly.")
                end
                table.insert(hatch_transposers, {proxy, enderSide, antiSide, pipeSide})
            end
            --print(os.time())
        end
    end
    return hatch_transposers, out_transposer
end

local function sensorInfo(gt_machine)
    local sensorData = gt_machine.getSensorInformation()
    local contained = sensorData[4]
    local change = sensorData[7]
    -- Invariant: we assume contained AM is never negative
    local containedNum = string.gmatch(contained:gsub(",", ""), "§9[%d]+§r")():gsub("§9", ""):gsub("§r", "")
    local changeNum = string.gmatch(change:gsub(",", ""), "§b[-]?[%d]+§r")():gsub("§b", ""):gsub("§r", "")
    return tonumber(containedNum), tonumber(changeNum)
end

local function mainLoop(targetAM, offset)
    local transposers, output = getTransposers()
    if offset == 0 and output == nil then
        print("Error: Missing an output transposer on computer 0")
    end
    local currAM = {}
    local ssass = component.gt_machine
    local lastTotal = -1
    local lastChange = -1
    local cycleCount = 0
    local changeHistory = {}
    local changeSum = 0
    local safetyBuffer = targetAM * 0.0003
    local tankTarget = safetyBuffer * 16
    local logPhase = (offset % 4) * 5 -- offsets 0..3 log on cycles 0,5,10,15 in each 20-cycle block
    while true do
        -- Current relative tick: 0
        local currTotal = 0
        local currChange = 0
        while true do
            currTotal, currChange = sensorInfo(ssass)
            if (currTotal ~= 0 and currTotal ~= lastTotal) or (currChange ~= 0 and currChange ~= lastChange) then
                break
            end
        end
        local tr = transposers[1]
        -- Current relative tick: 1
        local enderLevel = tr[1].getTankLevel(tr[2])
        --print("Curr total", currTotal, os.time())
        -- Current relative tick: 2
        for idx, tr in pairs(transposers) do
            currAM[idx] = tr[1].getTankLevel(tr[3])
            --print("Index", idx, " has ", currAM[idx])
        end
        -- Current relative tick: 6
        local realTarget = math.min(currTotal // 16, targetAM)
        local extraAM = 0
        if realTarget < targetAM then
            extraAM = currTotal - (realTarget * 16)
        end
        local eachTarget = {}
        for idx = 1, 4 do
            local thisTarget = realTarget
            if enderLevel >= tankTarget and (thisTarget + safetyBuffer > targetAM) then
                thisTarget = targetAM
            elseif (offset * 4) + idx <= extraAM then
                thisTarget = thisTarget + 1
            end
            eachTarget[idx] = thisTarget
        end
        local eachDiff = {}
        for idx = 1, 4 do
            local diff = currAM[idx] - eachTarget[idx]
            eachDiff[idx] = diff
        end
        --for idx = 1, 4 do
        --    print("Index ", idx, " has current ", currAM[idx], ", target ", eachTarget[idx], ", and diff ", eachDiff[idx])
        --end
        --print("Target", realTarget, "Extra", extraAM)
        --print(eachTarget, eachDiff)
        local totalOut = 0
        for idx, tr in pairs(transposers) do
            if eachDiff[idx] > 0 then
                --print("Transferring on idx ", idx, " in quantity ", eachDiff[idx])
                success, amount = tr[1].transferFluid(tr[3], tr[2], eachDiff[idx])
                --print("Transfer success was ", success, " with amount ", amount)
            else
                tr[1].transferFluid(tr[3], tr[2], 0)
            end
        end
        -- Current relative tick: 10
        local totalIn = 0
        for idx, tr in pairs(transposers) do
            if eachDiff[idx] < 0 then
                --print("Transferring on idx ", idx, " in quantity ", -1 * eachDiff[idx])
                success, amount = tr[1].transferFluid(tr[2], tr[4], -1 * eachDiff[idx])
                --print("Transfer success was ", success, " with amount ", amount)
            else
                tr[1].transferFluid(tr[2], tr[4], 0)
            end
        end
        -- Current relative tick: 14
        --local tr = transposers[1]
        --tr[1].getTankLevel(tr[3])
        --tr[1].getTankLevel(tr[3])
        --for idx, tr in pairs(transposers) do
        --    print("Post-cycle AM in idx ", idx, " is ", tr[1].getTankLevel(tr[3]))
        --end

        if offset == 0 then
            local leftoverAM = output[1].getTankLevel(output[2])
            if leftoverAM > tankTarget then
                output[1].transferFluid(output[2], output[3], leftoverAM - tankTarget)
            end
        end
        -- Current relative tick: 16 (if offset = 0)
        cycleCount = cycleCount + 1
        table.insert(changeHistory, currChange)
        changeSum = changeSum + currChange
        if #changeHistory > 100 then
            changeSum = changeSum - table.remove(changeHistory, 1)
        end
        if (cycleCount % 20) == logPhase then
            local rollingAvg = 0
            if #changeHistory > 0 then
                rollingAvg = changeSum / #changeHistory
            end
            term.clear()
            term.setCursor(1, 1)
            print(string.format("AM Script Offset %d", offset))
            print(string.format("Cycle: %d", cycleCount))
            print(string.format("Last AM change: %d L/cycle", currChange))
            print(string.format("Rolling avg AM change (last %d cycles): %.2f L/cycle", #changeHistory, rollingAvg))
        end
        lastTotal = currTotal
        lastChange = currChange
        --print("Cycle done at", os.time())
    end
end



args = { ... }
targetAM = tonumber(args[1])
offset = tonumber(args[2])
mainLoop(targetAM, offset)
