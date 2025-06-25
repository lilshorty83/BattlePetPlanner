-- BPP_MinimalScrollbar.lua
-- Reusable minimal-style scrollbar for WoW addons
local BPP_MinimalScrollbar = {}

function BPP_MinimalScrollbar.Attach(parent, scrollFrame, contentFrame, opts)
    opts = opts or {}
    local width = opts.width or 10
    local arrowButtonHeight = opts.arrowButtonHeight or 10
    local padding = opts.padding or 6
    local totalNumItems = opts.totalNumItems
    local buttonHeight = opts.buttonHeight

    -- Up Button
    local upButton = CreateFrame("Button", nil, parent)
    upButton:SetSize(17, 11)
    upButton:SetNormalAtlas("minimal-scrollbar-small-arrow-top")
    upButton:SetPushedAtlas("minimal-scrollbar-small-arrow-top-down")
    upButton:SetHighlightAtlas("minimal-scrollbar-small-arrow-top-over")
    
    -- Apply custom up button position or use default
    if opts.upButtonPoint then
        upButton:SetPoint(unpack(opts.upButtonPoint))
    else
        upButton:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -3, -4)
    end

    -- Down Button
    local downButton = CreateFrame("Button", nil, parent)
    downButton:SetSize(17, 11)
    downButton:SetNormalAtlas("minimal-scrollbar-small-arrow-bottom")
    downButton:SetPushedAtlas("minimal-scrollbar-small-arrow-bottom-down")
    downButton:SetHighlightAtlas("minimal-scrollbar-small-arrow-bottom-over")
    
    -- Apply custom down button position or use default
    if opts.downButtonPoint then
        downButton:SetPoint(unpack(opts.downButtonPoint))
    else
        downButton:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -3, 4)
    end

    -- ScrollBar
    local minimalScrollBar = CreateFrame("Slider", nil, parent)
    minimalScrollBar:SetOrientation("VERTICAL")
    minimalScrollBar:SetWidth(width)
    minimalScrollBar:SetMinMaxValues(0, 1)
    minimalScrollBar:SetValueStep(1)
    minimalScrollBar:SetObeyStepOnDrag(true)
    
    -- Apply custom scrollbar positioning or use default
    if opts.scrollBarPoints then
        for _, point in ipairs(opts.scrollBarPoints) do
            if #point == 1 then
                minimalScrollBar:SetPoint(point[1])
            else
                local relativeTo = point[2] == "upButton" and upButton or (point[2] == "downButton" and downButton or nil)
                minimalScrollBar:SetPoint(point[1], relativeTo or point[2], point[3] or "CENTER", point[4] or 0, point[5] or 0)
            end
        end
    else
        -- Default positioning if no custom points provided
        minimalScrollBar:SetPoint("TOP", upButton, "BOTTOM", 0, -padding)
        minimalScrollBar:SetPoint("BOTTOM", downButton, "TOP", 0, padding)
        minimalScrollBar:SetPoint("CENTER", upButton, "CENTER", 0, 0)
    end

    -- Track
    local trackTop = minimalScrollBar:CreateTexture(nil, "BACKGROUND")
    trackTop:SetAtlas("minimal-scrollbar-track-top")
    trackTop:SetPoint("TOPLEFT", minimalScrollBar, "TOPLEFT", 1, 0)
    trackTop:SetPoint("TOPRIGHT", minimalScrollBar, "TOPRIGHT", -1, 0)
    trackTop:SetHeight(8)

    local trackMiddle = minimalScrollBar:CreateTexture(nil, "BACKGROUND")
    trackMiddle:SetAtlas("!minimal-scrollbar-track-middle")
    trackMiddle:SetPoint("TOPLEFT", trackTop, "BOTTOMLEFT", 0, 0)
    trackMiddle:SetPoint("TOPRIGHT", trackTop, "BOTTOMRIGHT", 0, 0)
    trackMiddle:SetPoint("BOTTOMLEFT", minimalScrollBar, "BOTTOMLEFT", 1, 8)
    trackMiddle:SetPoint("BOTTOMRIGHT", minimalScrollBar, "BOTTOMRIGHT", -1, 8)
    trackMiddle:SetVertTile(true)

    local trackBottom = minimalScrollBar:CreateTexture(nil, "BACKGROUND")
    trackBottom:SetAtlas("minimal-scrollbar-track-bottom")
    trackBottom:SetPoint("BOTTOMLEFT", minimalScrollBar, "BOTTOMLEFT", 1, 0)
    trackBottom:SetPoint("BOTTOMRIGHT", minimalScrollBar, "BOTTOMRIGHT", -1, 0)
    trackBottom:SetHeight(8)

    -- Thumb
    local thumbTop = minimalScrollBar:CreateTexture(nil, "ARTWORK")
    thumbTop:SetAtlas("minimal-scrollbar-small-thumb-top")
    thumbTop:SetWidth(8)
    thumbTop:SetHeight(8)

    local thumbTexture = minimalScrollBar:CreateTexture(nil, "ARTWORK")
    thumbTexture:SetAtlas("minimal-scrollbar-small-thumb-middle")
    thumbTexture:SetWidth(8)
    thumbTexture:SetHeight(16)

    local thumbBottom = minimalScrollBar:CreateTexture(nil, "ARTWORK")
    thumbBottom:SetAtlas("minimal-scrollbar-small-thumb-bottom")
    thumbBottom:SetWidth(8)
    thumbBottom:SetHeight(8)

    minimalScrollBar:SetThumbTexture(thumbTexture)

    -- Thumb sizing logic
    local lastThumbHeight = 0
    local function UpdateMinimalThumbSize()
        local frameHeight = scrollFrame:GetHeight() or 1
        if frameHeight <= 1 then return end  -- Skip if frame height is invalid
        
        local minThumb = 16
        local contentHeight
        
        if totalNumItems and buttonHeight then
            contentHeight = totalNumItems * buttonHeight
        else
            contentHeight = contentFrame:GetHeight() or 1
        end
        
        -- Only update if content height is valid
        if contentHeight <= 0 then return end
        
        local proportion = math.min(1, frameHeight / contentHeight)
        local thumbHeight = math.max(minThumb, math.floor(proportion * frameHeight))
        
        -- Only update if thumb size actually changed
        if thumbHeight == lastThumbHeight then return end
        lastThumbHeight = thumbHeight
        
        -- Set thumb size and position
        thumbTexture:SetHeight(math.max(thumbHeight - 8, 8))
        
        -- Only update points if they've changed
        if not thumbTop:GetPoint(1) then
            thumbTop:SetPoint("BOTTOM", thumbTexture, "TOP", 0, 0)
            thumbBottom:SetPoint("TOP", thumbTexture, "BOTTOM", 0, 0)
        end
        
        -- Only update visibility if needed
        local shouldShow = contentHeight > frameHeight
        if shouldShow ~= minimalScrollBar:IsShown() then
            minimalScrollBar:SetShown(shouldShow)
            if upButton then upButton:SetShown(shouldShow) end
            if downButton then downButton:SetShown(shouldShow) end
        end
    end
    scrollFrame:HookScript("OnShow", UpdateMinimalThumbSize)
    scrollFrame:HookScript("OnSizeChanged", UpdateMinimalThumbSize)
    contentFrame:HookScript("OnSizeChanged", UpdateMinimalThumbSize)

    -- Store arrow references on the scrollbar for reliable visibility control
    minimalScrollBar.upButton = upButton
    minimalScrollBar.downButton = downButton

    -- Arrow button scrolling logic (1 row per click)
    local function clampScrollBarValue(val)
        local min, max = minimalScrollBar:GetMinMaxValues()
        if val < min then return min end
        if val > max then return max end
        return val
    end
    upButton:SetScript("OnClick", function()
        local val = clampScrollBarValue(minimalScrollBar:GetValue() - 1)
        minimalScrollBar:SetValue(val)
    end)
    downButton:SetScript("OnClick", function()
        local val = clampScrollBarValue(minimalScrollBar:GetValue() + 1)
        minimalScrollBar:SetValue(val)
    end)

    -- Mouse wheel support (1 row per notch)
    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local val = clampScrollBarValue(minimalScrollBar:GetValue() - delta * 1)  -- Changed - to + to fix scroll direction
        minimalScrollBar:SetValue(val)
    end)

    -- Store last value to prevent unnecessary updates
    local lastValue = 0
    
    -- Update list on scrollbar value change
    minimalScrollBar:SetScript("OnValueChanged", function(self, value, isUserInput)
        -- Only update if value actually changed and we're not in the middle of a drag
        if math.abs((value or 0) - (lastValue or 0)) < 0.1 then return end
        lastValue = value or 0
        
        -- Only update content if this is a user interaction or the first update
        if isUserInput or lastValue == 0 then
            if type(scrollFrame.UpdateList) == "function" then
                scrollFrame:UpdateList()
            elseif _G.UpdateList then
                -- fallback: global UpdateList
                _G.UpdateList(scrollFrame, contentFrame, scrollFrame.buttons or {}, minimalScrollBar)
            end
        end
    end)

    -- Override Hide/Show to always affect arrows as well
    if not minimalScrollBar._origHide then
        minimalScrollBar._origHide = minimalScrollBar.Hide
        minimalScrollBar.Hide = function(self)

            self:_origHide()
            if self.upButton then self.upButton:Hide() end
            if self.downButton then self.downButton:Hide() end
        end
    end
    if not minimalScrollBar._origShow then
        minimalScrollBar._origShow = minimalScrollBar.Show
        minimalScrollBar.Show = function(self)

            self:_origShow()
            if self.upButton then self.upButton:Show() end
            if self.downButton then self.downButton:Show() end
        end
    end

    return minimalScrollBar, upButton, downButton
end

_G.BPP_MinimalScrollbar = BPP_MinimalScrollbar
