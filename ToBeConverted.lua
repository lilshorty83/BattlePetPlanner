    -- Attach a scrollable container to the left pane if not present
    if not leftPane.petListContainer then
        -- Container for pet list and scrollbar, below search box
        local container = CreateFrame("Frame", nil, leftPane)
        container:SetPoint("TOPLEFT", leftPane, "TOPLEFT", 6, -40)  -- Adjusted y-offset for search box
        container:SetPoint("BOTTOMRIGHT", leftPane, "BOTTOMRIGHT", -5, 8)
        container:SetClipsChildren(true) -- Ensures content is clipped to this area
        leftPane.petListContainer = container

        -- ScrollChild: The visible mask area
        local scrollChild = CreateFrame("Frame", nil, container)
        scrollChild:SetPoint("TOPLEFT", leftPane, "TOPLEFT", 0, 0)
        scrollChild:SetPoint("BOTTOMRIGHT", leftPane, "BOTTOMRIGHT", 0, 0)
        scrollChild:SetPoint("TOPLEFT")
        scrollChild:SetPoint("BOTTOMRIGHT")
        scrollChild:SetClipsChildren(true)
        leftPane.scrollChild = scrollChild

        -- Content: The actual scrollable content (pet list items)
        local content = CreateFrame("Frame", nil, scrollChild)
        content:SetPoint("TOPLEFT")
        content:SetWidth(scrollChild:GetWidth()) -- Will be updated dynamically
        leftPane.petListContent = content
    end
    local content = leftPane.petListContent
    if not content.buttons then content.buttons = {} end

    -- Minimal Scrollbar integration (attach only once)
    if not leftPane.minimalScrollBar and leftPane.petListContainer and leftPane.scrollChild and leftPane.petListContent then
        local BPP_MinimalScrollbar = _G.BPP_MinimalScrollbar
        if BPP_MinimalScrollbar and BPP_MinimalScrollbar.Attach then
            local opts = {
                width = 8,
                arrowButtonHeight = 16,
                padding = 4,
                totalNumItems = #pets,
                buttonHeight = 46,
            }
            local minimalScrollBar = BPP_MinimalScrollbar.Attach(
                leftPane.petListContainer,
                leftPane.scrollChild,
                leftPane.petListContent,
                opts
            )
            leftPane.minimalScrollBar = minimalScrollBar
            minimalScrollBar:Show()

            -- Helper to update range and thumb
            local function RefreshPetListScrollbar()
                local numPets = #pets
                local visibleRows = math.floor((leftPane.scrollChild:GetHeight() or 1) / 22)
                local maxScroll = math.max(0, numPets - visibleRows)
                minimalScrollBar:SetMinMaxValues(0, maxScroll)
                if minimalScrollBar:GetValue() > maxScroll then
                    minimalScrollBar:SetValue(maxScroll)
                end
            end

            leftPane.scrollChild:HookScript("OnShow", RefreshPetListScrollbar)
            leftPane.scrollChild:HookScript("OnSizeChanged", RefreshPetListScrollbar)
            leftPane.petListContent:HookScript("OnSizeChanged", RefreshPetListScrollbar)

            -- Move content on scroll
            minimalScrollBar:SetScript("OnValueChanged", function(self, value)
                leftPane.petListContent:ClearAllPoints()
                leftPane.petListContent:SetPoint("TOPLEFT", leftPane.scrollChild, "TOPLEFT", 0, value * 22)
            end)
            leftPane.petListContainer:EnableMouseWheel(true)
            leftPane.petListContainer:SetScript("OnMouseWheel", function(self, delta)
    local min, max = minimalScrollBar:GetMinMaxValues()
    local newVal = minimalScrollBar:GetValue() - delta
    if newVal < min then newVal = min end
    if newVal > max then newVal = max end
    minimalScrollBar:SetValue(newVal)
end)
            -- Initial update
            RefreshPetListScrollbar()
            minimalScrollBar:SetValue(0)
        end
    end
