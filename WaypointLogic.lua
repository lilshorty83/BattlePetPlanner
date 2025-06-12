-- BattlePetPlanner_WaypointLogic.lua
-- Contains the reusable handler for plotting waypoints and visual effects for capture step buttons

function BattlePetPlanner_HandleWaypointClick(step, btn, rightPane)
    -- Visual effect: yellow flash
    if btn and not btn.flash then
        btn.flash = btn:CreateTexture(nil, "BACKGROUND")
        btn.flash:SetAllPoints(btn)
        btn.flash:SetColorTexture(1, 1, 0, 0.5) -- yellow, semi-transparent
        btn.flash:Hide()
    end
    if btn and btn.flash then
        btn.flash:Show()
        btn.flash:SetAlpha(0.7)
        btn.flash.t = 0
        btn:SetScript("OnUpdate", function(self, elapsed)
            self.flash.t = self.flash.t + elapsed
            if self.flash.t >= 0.4 then
                self.flash:Hide()
                self:SetScript("OnUpdate", nil)
            else
                self.flash:SetAlpha(0.7 * (1 - self.flash.t/0.4))
            end
        end)
    end
    -- Waypoint logic
    local mapID, coord = step.mapID, step.coord
    local plotAll = rightPane and rightPane.plotAllWaypointsCheckbox and rightPane.plotAllWaypointsCheckbox:GetChecked()
    local coordsList = {}
    if type(coord) == "table" and type(coord[1]) == "table" then
        for _, c in ipairs(coord) do table.insert(coordsList, c) end
    elseif type(coord) == "table" then
        coordsList = {coord}
    end
    local numWaypoints = #coordsList
    local batchSize = 10
    local speciesID = step.speciesID or (step.text and step.text:match("Capture .- %((%d+)%)"))
    if plotAll or numWaypoints <= batchSize then
        -- Plot all waypoints
        for _, c in ipairs(coordsList) do
            if TomTom and TomTom.AddWaypoint then
                TomTom:AddWaypoint(mapID, c[1]/100, c[2]/100, { title = step.text })
            elseif C_Map and C_Map.SetUserWaypoint and UiMapPoint then
                local wp = UiMapPoint.CreateFromCoordinates(mapID, c[1]/100, c[2]/100)
                C_Map.SetUserWaypoint(wp)
                if C_SuperTrack then C_SuperTrack.SetSuperTrackedUserWaypoint(true) end
            end
        end
        -- Reset batch index for this pet
        if speciesID then BattlePetPlanner_WaypointBatchIndex[speciesID] = 1 end
    else
        -- Plot 10 random waypoints at a time, cycling through batches
        -- Ensure batch index and random order tables are initialized
        BattlePetPlanner_WaypointBatchIndex = BattlePetPlanner_WaypointBatchIndex or {}
        BattlePetPlanner_RandomWaypointOrder = BattlePetPlanner_RandomWaypointOrder or {}
        local idx = 1
        if speciesID then
            BattlePetPlanner_WaypointBatchIndex[speciesID] = (BattlePetPlanner_WaypointBatchIndex[speciesID] or 1)
            idx = BattlePetPlanner_WaypointBatchIndex[speciesID]
        end
        -- Shuffle the list for random selection if first batch
        if idx == 1 then
            -- Fisher-Yates shuffle
            BattlePetPlanner_RandomWaypointOrder[speciesID] = {}
            for i = 1, numWaypoints do BattlePetPlanner_RandomWaypointOrder[speciesID][i] = i end
            for i = numWaypoints, 2, -1 do
                local j = math.random(i)
                BattlePetPlanner_RandomWaypointOrder[speciesID][i], BattlePetPlanner_RandomWaypointOrder[speciesID][j] = BattlePetPlanner_RandomWaypointOrder[speciesID][j], BattlePetPlanner_RandomWaypointOrder[speciesID][i]
            end
        end
        local order = BattlePetPlanner_RandomWaypointOrder and BattlePetPlanner_RandomWaypointOrder[speciesID] or {}
        local startIdx = ((idx - 1) * batchSize) + 1
        local endIdx = math.min(startIdx + batchSize - 1, numWaypoints)
        -- Remove all previous waypoints for this batch (TomTom and Blizzard)
        if TomTom and TomTom.RemoveAllWaypoints then
            TomTom:RemoveAllWaypoints()
        end
        if C_Map and C_Map.ClearUserWaypoint then
            C_Map.ClearUserWaypoint()
        end
        -- Plot only the selected batch of waypoints
        for i = startIdx, endIdx do
            local orderIdx = order[i]
            if orderIdx and coordsList[orderIdx] then
                local c = coordsList[orderIdx]
                if TomTom and TomTom.AddWaypoint then
                    TomTom:AddWaypoint(mapID, c[1]/100, c[2]/100, { title = step.text })
                elseif C_Map and C_Map.SetUserWaypoint and UiMapPoint then
                    local wp = UiMapPoint.CreateFromCoordinates(mapID, c[1]/100, c[2]/100)
                    C_Map.SetUserWaypoint(wp)
                    if C_SuperTrack then C_SuperTrack.SetSuperTrackedUserWaypoint(true) end
                end
            end
        end
        -- Advance batch index for next click (wrap around)
        if speciesID then
            if endIdx >= numWaypoints then
                BattlePetPlanner_WaypointBatchIndex[speciesID] = 1
            else
                BattlePetPlanner_WaypointBatchIndex[speciesID] = idx + 1
            end
        end
    end
end

return BattlePetPlanner_HandleWaypointClick
