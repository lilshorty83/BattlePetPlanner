-- Addon DB/init and utility functions

-- Utility: Flatten nested route steps for display
function FlattenRouteSteps(route)
    local flat = {}
    for _, step in ipairs(route.steps) do
        -- Add the navigation step
        table.insert(flat, { text = step.text, mapID = step.mapID })
        -- Add each pet as a capture step
        if step.pets then
            for _, pet in ipairs(step.pets) do
                if type(pet) == "table" then
                    table.insert(flat, {
                        text = "Capture " .. pet.name,
                        mapID = step.mapID,
                        speciesID = pet.speciesID
                    })
                elseif type(pet) == "string" then
                    local speciesID = nil
                    if PET_SPECIES_MAP then
                        speciesID = PET_SPECIES_MAP[pet]
                    end
                    table.insert(flat, {
                        text = "Capture " .. pet,
                        mapID = step.mapID,
                        speciesID = speciesID
                    })
                end
            end
        end
    end
    return flat
end

-- Move selectedLeg to top level and make it persistent
BattlePetPlannerDB = BattlePetPlannerDB or {}
local selectedLeg = nil

local function BattlePetPlanner_ScanMissingPets()
    
    -- Clear all Pet Journal filters to ensure we see all pets
    if C_PetJournal.ClearSearchFilter then C_PetJournal.ClearSearchFilter() end
    if C_PetJournal.SetFilterChecked then
        if LE_PET_JOURNAL_FILTER_COLLECTED then C_PetJournal.SetFilterChecked(LE_PET_JOURNAL_FILTER_COLLECTED, true) end
        if LE_PET_JOURNAL_FILTER_NOT_COLLECTED then C_PetJournal.SetFilterChecked(LE_PET_JOURNAL_FILTER_NOT_COLLECTED, true) end
        if LE_PET_JOURNAL_FILTER_PETTYPE then C_PetJournal.SetFilterChecked(LE_PET_JOURNAL_FILTER_PETTYPE, true) end
        if LE_PET_JOURNAL_FILTER_SOURCE then C_PetJournal.SetFilterChecked(LE_PET_JOURNAL_FILTER_SOURCE, true) end
    end
    -- Ensure Pet Journal is sorted in 'Pet Journal Order' (not by name or level)
    if C_PetJournal.SetPetSortParameter then
        if LE_PET_JOURNAL_SORT_PET_JOURNAL_ORDER then
            C_PetJournal.SetPetSortParameter(LE_PET_JOURNAL_SORT_PET_JOURNAL_ORDER)
        else
            -- Fallback to name sort if journal order is not available (older clients)
            if LE_PET_JOURNAL_SORT_NAME then
                C_PetJournal.SetPetSortParameter(LE_PET_JOURNAL_SORT_NAME)
                print("BattlePetPlanner WARNING: Pet Journal order sort is not available; falling back to alphabetical order.")
            end
        end
    end
    -- DO NOT sort or filter allPets after this point. The order must match the Pet Journal exactly.
    -- If the last pet in the Pet Journal is not the last in the planner, please report your WoW version and locale.
    local total = C_PetJournal.GetNumPets(false)
    local allPets = {}
    local missing = {}
    for i = 1, total do
        local petID, speciesID, isOwned, customName, level, favorite, isRevoked, speciesName, icon, petType, companionID, tooltipSource, tooltipDescription, isWild, canBattle, tradable, unique, obtainable = C_PetJournal.GetPetInfoByIndex(i)
        local numCollected, limit = C_PetJournal.GetNumCollectedInfo(speciesID)
        table.insert(allPets, {
            speciesID = speciesID,
            name = speciesName,
            favorite = favorite,
            icon = icon,
            petType = petType,
            isOwned = isOwned,
            numCollected = numCollected,
            isWild = isWild,
            obtainable = obtainable,
            tooltipSource = tooltipSource,
            customName = customName,
            level = level,
            isRevoked = isRevoked,
            companionID = companionID,
            tooltipDescription = tooltipDescription,
            canBattle = canBattle,
            tradable = tradable,
            unique = unique
        })
        if (numCollected or 0) < 1 and obtainable then
            table.insert(missing, allPets[#allPets])
        end
    end
    BattlePetPlannerDB.allPets = allPets
    BattlePetPlannerDB.missingPets = missing
end

-- =====================
-- =====================
-- UI construction
-- =====================

-- =====================
-- Globals and Forward Declarations
-- =====================
local rightPane
local tabButtons = {}
local progress
local gui
local TABS_PER_PAGE = 4
local tabPageStart = 1
local leftArrow, rightArrow
local selectedLeg = nil

local UpdateTabVisibility
local ScrollToTabIndex
local ShowRouteLeg

-- =====================
-- MAIN FRAME (Parent for all UI panes)
-- =====================
local gui = CreateFrame("Frame", "BattlePetPlannerFrame", UIParent, "PortraitFrameTemplate")
gui:Hide() -- Ensure the frame is hidden on creation
gui:SetSize(770, 606)
gui:SetPoint("CENTER")
gui:SetFrameStrata("HIGH")
gui:SetMovable(true)
gui:EnableMouse(true)
gui:RegisterForDrag("LeftButton")
gui:SetScript("OnDragStart", function(self) self:StartMoving() end)
gui:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)

-- =====================
-- LEFT PANE: Pet List (Uncollected Wild Pets)
-- =====================
local leftPane = CreateFrame("Frame", nil, gui, "InsetFrameTemplate")
leftPane:SetPoint("TOPLEFT", gui, "TOPLEFT", 10, -100)
leftPane:SetPoint("BOTTOMLEFT", gui, "BOTTOMLEFT", 10, 10)
leftPane:SetWidth(230)

-- =====================
-- RIGHT PANE: Route Steps / Planner
-- =====================
rightPane = CreateFrame("Frame", nil, gui, "InsetFrameTemplate")
rightPane:SetPoint("TOPLEFT", leftPane, "TOPRIGHT", 10, 0)
rightPane:SetPoint("BOTTOMRIGHT", gui, "BOTTOMRIGHT", -10, 10)
-- Optionally, you can force a minimum width for the right pane if needed:
--rightPane:SetWidth(650)

-- Add a customizable background texture to the right pane
local bg = rightPane:CreateTexture(nil, "BACKGROUND")
bg:SetTexture("interface/collections/collectionsbackgroundtile")
bg:SetAllPoints(rightPane)
rightPane.bg = bg

gui.leftPane = leftPane
gui.rightPane = rightPane
gui.petListContent = petListContent

local function ShowLandingPage()
    if not rightPane then
        return
    end

    -- First, deselect ALL tabs and reset their state completely
    if tabButtons then
        for _, btn in ipairs(tabButtons) do
            if btn.UnlockHighlight then btn:UnlockHighlight() end
            if btn.SetChecked then btn:SetChecked(false) end
            if PanelTemplates_DeselectTab then PanelTemplates_DeselectTab(btn) end
            if btn.SetButtonState then btn:SetButtonState("NORMAL", false) end
            btn.selected = nil
            btn.checked = nil
        end
    end

    -- Reset selected leg
    selectedLeg = nil

    -- Reset parent frame selectedTab property if present
    if BattlePetPlannerFrame then
        PanelTemplates_SetTab(BattlePetPlannerFrame, nil)
    end

    -- Hide all tab-specific widgets
    if rightPane.showCollectedCheckbox then rightPane.showCollectedCheckbox:Hide() end
    if rightPane.plotAllWaypointsCheckbox then rightPane.plotAllWaypointsCheckbox:Hide() end
    if rightPane.scrollFrame then rightPane.scrollFrame:Hide() end
    if rightPane.steps then
        for _, s in ipairs(rightPane.steps) do s:Hide() end
        rightPane.steps = nil
    end
    if rightPane.routeNote then rightPane.routeNote:Hide() end
    if rightPane.showCollectedCheckbox then rightPane.showCollectedCheckbox:Hide() end
    if rightPane.scrollFrame then rightPane.scrollFrame:Hide() end
    -- Hide any congratulatory message from previous route view
    if rightPane.stepsContainer and rightPane.stepsContainer.allCollectedMessage then
        rightPane.stepsContainer.allCollectedMessage:Hide()
    end
    -- Remove any previous landing widgets
    if rightPane.landingWidgets then
        for _, w in ipairs(rightPane.landingWidgets) do w:Hide() end
    end
    rightPane.landingWidgets = {}

    -- Welcome message
    local welcome = rightPane:CreateFontString(nil, "OVERLAY", "GameFontHighlightHuge")
    welcome:SetPoint("TOP", rightPane, "TOP", 0, -40)
    welcome:SetText("Welcome to Battle Pet Planner!")
    welcome:Show()
    -- Frame level only applies to frames, not FontStrings
    local highestLevel = rightPane:GetFrameLevel() + 10
    table.insert(rightPane.landingWidgets, welcome)

    -- Usage instructions
    local instructions = rightPane:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    instructions:SetPoint("TOP", welcome, "BOTTOM", 0, -20)
    instructions:SetJustifyH("LEFT")
    instructions:SetText("How to use:\n- Select a zone tab to view wild pets.\n- Use the checkbox to show all or only missing pets.\n- Click a pet name to set a waypoint.")
    instructions:Show()
    table.insert(rightPane.landingWidgets, instructions)

    -- Progress summary
    if not Route then
        return
    end
    local total, collected = 0, 0
    local seen = {}
    for _, route in ipairs(Route) do
        for _, step in ipairs(route.steps) do
            if step.speciesID and not seen[step.speciesID] then
                seen[step.speciesID] = true
                total = total + 1
                if C_PetJournal and C_PetJournal.GetNumCollectedInfo then
                    local n = C_PetJournal.GetNumCollectedInfo(step.speciesID)
                    if n and n > 0 then collected = collected + 1 end -- Any quality counts as collected
                end
            end
        end
    end
    local progress = rightPane:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    progress:SetPoint("TOP", instructions, "BOTTOM", 0, -30)
    progress:SetText(string.format("Progress: %d / %d wild pets collected", collected, total))
    progress:Show()
    table.insert(rightPane.landingWidgets, progress)

    -- =======================
    -- 3D Pet Model Randomizer
    -- =======================

    -- Add randomized 3D battle pet model below Progress text
    -- Destroy previous model if it exists
    if rightPane.petModel then
        rightPane.petModel:Hide()
        rightPane.petModel:SetParent(nil)
        rightPane.petModel = nil
    end
    -- Randomize among collected pets only
    local numCollectedPets = C_PetJournal.GetNumPets and C_PetJournal.GetNumPets(false) or 0
    local collectedSpeciesIDs = {}
    for i = 1, numCollectedPets do
        local petID, speciesID, _, _, _, _, _, _, _, _, _, _, _, _, _, isOwned = C_PetJournal.GetPetInfoByIndex(i)
        if isOwned and speciesID then
            table.insert(collectedSpeciesIDs, speciesID)
        end
    end
    local petModelDisplayID = nil
    local numCollected = #collectedSpeciesIDs
    if numCollected > 0 then
        -- Shuffle RNG based on time to ensure different pet each time
        local t = math.floor(GetTime() * 1000)
        for i = 1, (t % 10) + 1 do
            math.random()
        end
        local idx = math.random(1, numCollected)
        local speciesID = collectedSpeciesIDs[idx]
        if speciesID and C_PetJournal.GetDisplayIDByIndex then
            petModelDisplayID = C_PetJournal.GetDisplayIDByIndex(speciesID, 1)
        end
    end
    -- Fallback to Murky if randomization fails
    if not petModelDisplayID then
        petModelDisplayID = select(12, C_PetJournal.GetPetInfoBySpeciesID(107))
    end
    if petModelDisplayID then
        local petModel = CreateFrame("PlayerModel", nil, rightPane)
        rightPane.petModel = petModel
        petModel:SetSize(250, 250)
        petModel:SetPoint("TOP", progress, "BOTTOM", 0, -20)
        petModel:ClearModel()
        petModel:SetDisplayInfo(petModelDisplayID)
        petModel:SetRotation(0)
        petModel:SetPortraitZoom(0.65)
        petModel:SetCamDistanceScale(2)
        petModel:SetPosition(0, 0, 0.0) -- Centered for best fit
        petModel:SetFrameLevel(highestLevel)
        petModel:Show()

        -- Interactivity: Rotate with drag, zoom with wheel, click to animate
        local isDragging = false
        local lastX = 0
        local baseRotation = 0
        local zoom = 0.4
        petModel:SetPortraitZoom(zoom)

        petModel:SetScript("OnMouseDown", function(self, button)
            if button == "LeftButton" then
                isDragging = true
                lastX = GetCursorPosition()
            end
        end)
        petModel:SetScript("OnMouseUp", function(self, button)
            if button == "LeftButton" then
                isDragging = false
            end
        end)
        petModel:SetScript("OnUpdate", function(self)
            if isDragging then
                local x = GetCursorPosition()
                local delta = (x - lastX) * 0.01
                baseRotation = baseRotation + delta
                self:SetRotation(baseRotation)
                lastX = x
            end
        end)
        petModel:EnableMouse(true)
        petModel:SetScript("OnMouseWheel", function(self, delta)
            zoom = math.max(0.4, math.min(0.65, zoom + delta * 0.05))
            self:SetPortraitZoom(zoom)
        end)
        petModel:EnableMouseWheel(true)
        petModel.isAnimating = false
        petModel.animationTicker = nil
        petModel:SetScript("OnMouseUp", function(self, button)
            if button == "LeftButton" then
                isDragging = false
                if not self.isAnimating then
                    -- Start repeating animation
                    self.isAnimating = true
                    local anims = {
                        0,	   -- Stand (Idle)
                        69,    -- EmoteDance (Dance)
                    }
                    local anim = anims[math.random(#anims)]
                    self.animationTicker = C_Timer.NewTicker(1.2, function()
                        if self and self.SetAnimation then
                            self:SetAnimation(anim)
                        end
                    end)
                    -- Start immediately
                    self:SetAnimation(anim)
                else
                    -- Stop animation and return to idle
                    self.isAnimating = false
                    if self.animationTicker then
                        self.animationTicker:Cancel()
                        self.animationTicker = nil
                    end
                    self:SetAnimation(0)
                end
            end
        end)
        table.insert(rightPane.landingWidgets, petModel)
    end
end

-- =====================
-- Main frame (parent for all UI panes)
-- =====================

-- Define constants before they are used
local TABS_PER_PAGE = 4
local tabPageStart = 1

-- Define UpdateTabVisibility first
local function UpdateTabVisibility()
    -- Hide all tabs first
    for i, tab in ipairs(tabButtons) do
        tab:Hide()
    end
    -- Calculate centering
    local numTabs = math.min(TABS_PER_PAGE, #Route - tabPageStart + 1)
    local tabWidth = 110
    local tabSpacing = 1
    local totalTabWidth = numTabs * tabWidth + (numTabs-1) * tabSpacing
    local paneWidth = rightPane:GetWidth() or 400
    local startX = math.floor((paneWidth - totalTabWidth) / 2)
    -- Show only the current page of tabs, centered
    local visible = 0
    for i = tabPageStart, math.min(tabPageStart + TABS_PER_PAGE - 1, #Route) do
        visible = visible + 1
        local tab = tabButtons[i]
        if tab then
            tab:SetWidth(tabWidth)
            if visible == 1 then
                tab:ClearAllPoints()
                tab:SetPoint("TOPLEFT", rightPane, "TOPLEFT", startX, 0)
            else
                tab:ClearAllPoints()
                tab:SetPoint("LEFT", tabButtons[i-1], "RIGHT", tabSpacing, 0)
            end
            tab:Show()
        end
    end
    -- Enable/disable arrows
    if leftArrow then leftArrow:SetEnabled(tabPageStart > 1) end
    if rightArrow then rightArrow:SetEnabled(tabPageStart + TABS_PER_PAGE <= #Route) end
end

-- Define ScrollToTabIndex before gui creation
local function ScrollToTabIndex(index)
    if not index then return end
    local targetPage = math.ceil(index / TABS_PER_PAGE)
    tabPageStart = ((targetPage - 1) * TABS_PER_PAGE) + 1
    UpdateTabVisibility()
end

-- Define ShowRouteLeg before OnShow handler
local ShowRouteLeg

-- Ensure landing page randomizer runs every time the planner is opened
gui:SetScript("OnShow", function()
    BattlePetPlanner_ScanMissingPets()
    BattlePetPlanner_UpdatePetListGUI()
    if BattlePetPlannerDB.lastSelectedLeg and Route[BattlePetPlannerDB.lastSelectedLeg] then
        ScrollToTabIndex(BattlePetPlannerDB.lastSelectedLeg)
        C_Timer.After(0, function()
            ShowRouteLeg(BattlePetPlannerDB.lastSelectedLeg)
        end)
    else
        ShowLandingPage()
    end
end)
gui:SetScript("OnHide", function()
    -- No longer clear tab selection state on hide
    -- This allows the selected tab to persist when reopening
end)


-- Set the frame title using the method that works for PortraitFrameTemplate in this version
-- (gui:GetTitleText() returns the correct FontString; TitleText and titleText are nil)
if gui.GetTitleText then
    local t = gui:GetTitleText()
    if t then t:SetText("Battle Pet Planner") end
end


-- Add a Blizzard-style portrait region (visible in FrameStack)
local portrait = gui:CreateTexture("BattlePetPlannerFramePortrait", "ARTWORK")
portrait:SetSize(60, 60)
portrait:SetPoint("TOPLEFT", gui, "TOPLEFT", -4, 6)
portrait:SetTexture("Interface\\Icons\\PetJournalPortrait")
portrait:SetTexCoord(0, 1, 0, 1)
-- Add Blizzard's circular mask
local mask = gui:CreateMaskTexture(nil, "ARTWORK")
mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
mask:SetSize(60, 60)
mask:SetPoint("CENTER", portrait, "CENTER")
portrait:AddMaskTexture(mask)
gui.Portrait = portrait


-- =====================
-- LEFT PANE: Pet List (Uncollected Wild Pets)
-- =====================

-- Search Bar: Blizzard style search box above leftPane
local searchBox = CreateFrame("EditBox", "BattlePetPlannerSearchBox", leftPane, "SearchBoxTemplate")
searchBox:SetHeight(20)
searchBox:ClearAllPoints()
searchBox:SetPoint("BOTTOMLEFT", leftPane, "TOPLEFT", 3, 2)
searchBox:SetPoint("BOTTOMRIGHT", leftPane, "TOPRIGHT", 0, 2)
searchBox:SetAutoFocus(false)
searchBox:SetFrameStrata("HIGH")
searchBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
searchBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

-- Set Blizzard-style instruction text for placeholder
searchBox.instructionText = "Search Pets"
if searchBox.Instructions then
    searchBox.Instructions:SetText(searchBox.instructionText)
end

local function BattlePetPlanner_SearchBox_UpdateInstructions(self)
    if self.Instructions then
        if self:GetText() == "" and not self:HasFocus() then
            self.Instructions:Show()
        else
            self.Instructions:Hide()
        end
    end
end

searchBox:SetScript("OnEditFocusGained", function(self)
    SearchBoxTemplate_OnEditFocusGained(self)
    BattlePetPlanner_SearchBox_UpdateInstructions(self)
end)

searchBox:SetScript("OnTextChanged", function(self)
    SearchBoxTemplate_OnTextChanged(self)
    BattlePetPlanner_UpdatePetListGUI()
    BattlePetPlanner_SearchBox_UpdateInstructions(self)
end)

-- Add a customizable background texture to the left pane (same as right pane)
local leftBg = leftPane:CreateTexture(nil, "BACKGROUND")
leftBg:SetTexture("interface/collections/collectionsbackgroundtile")
leftBg:SetAllPoints(leftPane)
leftPane.bg = leftBg

-- Constants for pet list
local PET_ROW_HEIGHT = 46  -- Height of each pet row in pixels
local SCROLLBAR_WIDTH = 10  -- Width of the scrollbar
local SCROLLBAR_PADDING = 6  -- Padding around the scrollbar
local PET_LIST_PADDING = 3  -- Padding around the pet list

-- Create main container for the pet list (this is the visible area)
local petListContainer = CreateFrame("Frame", nil, leftPane, "BackdropTemplate")
petListContainer:SetPoint("TOPLEFT", leftPane, "TOPLEFT", PET_LIST_PADDING, -PET_LIST_PADDING)
petListContainer:SetPoint("BOTTOMRIGHT", leftPane, "BOTTOMRIGHT", -PET_LIST_PADDING, PET_LIST_PADDING)
petListContainer:SetClipsChildren(true)

-- Create scroll child that will contain the content
local scrollChild = CreateFrame("Frame", nil, petListContainer, "BackdropTemplate")
scrollChild:SetPoint("TOPLEFT")
scrollChild:SetPoint("RIGHT")
scrollChild:SetHeight(1)  -- Will be updated based on content
scrollChild:SetClipsChildren(true)

-- Create content frame that will hold the pet list buttons
local initialMissing = (BattlePetPlannerDB and type(BattlePetPlannerDB.missingPets) == "table" and BattlePetPlannerDB.missingPets) or {}
local petListContent = CreateFrame("Frame", nil, scrollChild, "BackdropTemplate")
petListContent:SetPoint("TOPLEFT")
petListContent:SetPoint("RIGHT")
petListContent:SetHeight(math.max(200, #initialMissing * PET_ROW_HEIGHT))

-- Store references for later use
leftPane.petListContainer = petListContainer
leftPane.scrollChild = scrollChild
leftPane.petListContent = petListContent

-- Function to update content position and handle bounds
local function UpdatePetListPosition(scrollValue)
    -- Calculate max possible scroll value (number of rows that can be scrolled)
    local contentHeight = petListContent:GetHeight() or 1
    local containerHeight = petListContainer:GetHeight() or 1
    local maxScroll = math.max(0, (contentHeight - containerHeight) / PET_ROW_HEIGHT)
    
    -- Clamp the scroll value to valid range
    scrollValue = math.max(0, math.min(scrollValue, maxScroll))
    
    -- Calculate pixel offset (negative because we're moving the content up)
    local offset = -scrollValue * PET_ROW_HEIGHT
    
    -- Update content position
    petListContent:ClearAllPoints()
    petListContent:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, offset)
    petListContent:SetPoint("RIGHT", scrollChild, "RIGHT")
    
    -- Return the actual scroll value used (after clamping)
    return scrollValue
end

-- Store the function for later use
leftPane.UpdatePetListPosition = UpdatePetListPosition

-- =====================
-- LEFT PANE: Minimal Scrollbar
-- =====================
local function SetupLeftPaneScrollbar()
    local BPP_MinimalScrollbar = _G.BPP_MinimalScrollbar
    if not BPP_MinimalScrollbar or not BPP_MinimalScrollbar.Attach then
        print("BattlePetPlanner: BPP_MinimalScrollbar not found, scrollbar will not work")
        return
    end
    
    -- Create the scrollbar with options
    local opts = {
        width = SCROLLBAR_WIDTH,
        skinnyWidth = 6,
        arrowButtonHeight = 16,
        padding = SCROLLBAR_PADDING,
        buttonHeight = PET_ROW_HEIGHT,
        -- Custom offsets for left pane scrollbar
        upButtonOffsetX = -1,  -- Move 2px left from default -3 (to -1)
        downButtonOffsetX = -1, -- Move 2px left from default -3 (to -1)
    }
    
    -- Attach the scrollbar to the container
    local scrollbar = BPP_MinimalScrollbar.Attach(
        petListContainer,
        petListContainer,
        petListContent,
        opts
    )
    
    -- Store reference to the scrollbar
    leftPane.scrollbar = scrollbar
    
    -- Helper to update scrollbar range and thumb
    local function RefreshPetListScrollbar()
        -- Get the current pet list
        local allPets = BattlePetPlannerDB and BattlePetPlannerDB.allPets or {}
        if type(allPets) ~= "table" then allPets = {} end
        
        -- Filter pets based on search text if needed
        local displayPets = {}
        local searchText = leftPane.searchBox and leftPane.searchBox:GetText():lower() or ""
        
        for _, pet in ipairs(allPets) do
            if searchText == "" or (pet.name and pet.name:lower():find(searchText, 1, true)) then
                table.insert(displayPets, pet)
            end
        end
        
        local numPets = #displayPets
        local containerHeight = petListContainer:GetHeight() or 1
        local contentHeight = numPets * PET_ROW_HEIGHT
        
        -- Update content height
        petListContent:SetHeight(contentHeight)
        scrollChild:SetHeight(math.max(containerHeight, contentHeight))
        
        -- Calculate maximum scroll value
        local maxScroll = math.max(0, contentHeight - containerHeight)
        
        -- Update scrollbar range
        scrollbar:SetMinMaxValues(0, maxScroll)
        
        -- Update scrollbar visibility and thumb size
        if maxScroll > 0 then
            scrollbar:Show()
            
            -- Update thumb size based on visible content ratio
            local thumb = scrollbar.thumb
            if thumb then
                local thumbHeight = math.max(20, (containerHeight / contentHeight) * containerHeight)
                thumb:SetHeight(thumbHeight)
                
                -- Force update of thumb position
                local currentValue = scrollbar:GetValue()
                if currentValue > maxScroll then
                    scrollbar:SetValue(maxScroll)
                end
            end
        else
            scrollbar:SetValue(0)
            scrollbar:Hide()
        end
    end
    
    -- Set up scrollbar value changed handler with bounds checking
    local lastValue = 0
    scrollbar:SetScript("OnValueChanged", function(self, value, isUserInput)
        -- Only update if value actually changed
        if math.abs(value - lastValue) < 0.1 then return end
        lastValue = value
        
        -- Update the content position
        local actualValue = UpdatePetListPosition(value)
        
        -- Ensure scrollbar reflects any clamping that occurred
        if math.abs(actualValue - value) > 0.1 then
            scrollbar:SetValue(actualValue)
        end
    end)
    
    -- Enable mouse wheel scrolling on the container
    petListContainer:EnableMouseWheel(true)
    petListContainer:SetScript("OnMouseWheel", function(self, delta)
        local min, max = scrollbar:GetMinMaxValues()
        local current = scrollbar:GetValue()
        
        -- Calculate new value with smoother scrolling (2 rows per tick)
        -- Negative delta means scrolling down (content moves up)
        local scrollStep = 2  -- Rows per scroll tick
        local newVal = current - (delta * scrollStep)
        
        -- Clamp the value with bounds checking
        newVal = math.max(min, math.min(newVal, max))
        
        -- Only update if value changed significantly
        if math.abs(newVal - current) > 0.1 then
            scrollbar:SetValue(newVal)
        end
        
        -- Mark as handled to prevent event bubbling
        return true
    end)
    
    -- Debounce function to prevent rapid updates
    local debounceTimer
    local function DebouncedRefresh()
        if debounceTimer then return end
        debounceTimer = C_Timer.NewTimer(0.05, function()
            RefreshPetListScrollbar()
            debounceTimer = nil
        end)
    end
    
    -- Hook up events for scrollbar updates with debounce
    petListContent:SetScript("OnSizeChanged", DebouncedRefresh)
    petListContainer:SetScript("OnSizeChanged", DebouncedRefresh)
    
    -- Update scrollbar when pet list changes
    hooksecurefunc("BattlePetPlanner_UpdatePetListGUI", DebouncedRefresh)
    
    -- Initial update after a short delay to ensure frames are properly sized
    C_Timer.After(0.1, function()
        -- Force update container size and refresh
        petListContainer:GetHeight()
        RefreshPetListScrollbar()
    end)
    
    -- Initial position update
    UpdatePetListPosition(0)
end

-- Initialize the scrollbar
C_Timer.After(0, SetupLeftPaneScrollbar)

-- =====================
-- RIGHT PANE: Route Steps / Planner
-- =====================
rightPane = CreateFrame("Frame", nil, gui, "InsetFrameTemplate")
rightPane:SetPoint("TOPLEFT", leftPane, "TOPRIGHT", 10, 0)
rightPane:SetPoint("BOTTOMRIGHT", gui, "BOTTOMRIGHT", -10, 10)
-- Optionally, you can force a minimum width for the right pane if needed:
--rightPane:SetWidth(650)

-- Add a customizable background texture to the right pane
local bg = rightPane:CreateTexture(nil, "BACKGROUND")
bg:SetTexture("interface/collections/collectionsbackgroundtile")
bg:SetAllPoints(rightPane)
rightPane.bg = bg

gui.leftPane = leftPane
gui.rightPane = rightPane
gui.petListContent = petListContent

-- Home Button at the top-right of the main window
local homeBtn = CreateFrame("Button", nil, gui, "UIPanelButtonTemplate")
homeBtn:SetSize(56, 32)
homeBtn:SetPoint("TOPRIGHT", gui, "TOPRIGHT", -24, -48)
homeBtn:SetNormalAtlas("UI-Frame-Button-Up")
homeBtn:SetPushedAtlas("UI-Frame-Button-Down")
homeBtn:SetHighlightAtlas("UI-Frame-Button-Highlight")

local homeLabel = homeBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
homeLabel:SetText("Home")
homeLabel:SetPoint("CENTER", homeBtn, "CENTER", 0, 0)
homeLabel:SetTextColor(1, 0.82, 0)


-- =====================
-- ROUTE DATA AND PLANNER LOGIC
-- =====================
-- Route Planner: Use global route tables loaded by the TOC (now in Routes/ subfolder)
Route = {
    BPP_Route_Kalimdor,
    BPP_Route_EasternKingdoms,
    BPP_Route_Outland,
    BPP_Route_Northrend,
    BPP_Route_Draenor,
    BPP_Route_Pandaria,
    BPP_Route_BrokenIsles,
    BPP_Route_Argus,
    BPP_Route_Shadowlands,
    BPP_Route_DragonIsles,
    BPP_Route_Zandalar,
    BPP_Route_KulTiras,
    BPP_Route_Nazjatar,
    BPP_Route_Maelstrom,
    BPP_Route_ZerethMortis,
    BPP_Route_KhazAlgar,
    BPP_Route_SirenIsle,
    -- Add more routes here as you add more continents
}

-- Create tab buttons
for i, leg in ipairs(Route) do
    local tab
    local tabTemplate = "TabSystemButtonArtTemplate"
    if tabTemplate and type(tabTemplate) == "string" then
        tab = CreateFrame("Button", nil, rightPane, tabTemplate)
    else
        tab = CreateFrame("Button", nil, rightPane, "UIPanelButtonTemplate")
    end
    tab:SetID(i)
    tab:SetSize(110, 32)
    tab:SetText(leg.name)
    tab:SetScript("OnClick", function(self)
        local id = self:GetID()
        -- Ensure the clicked tab is visible (move pagination if needed)
        local page = math.floor((id - 1) / TABS_PER_PAGE)
        tabPageStart = page * TABS_PER_PAGE + 1
        UpdateTabVisibility()
        ShowRouteLeg(id)
    end)
    -- Do not select any tab by default
    PanelTemplates_DeselectTab(tab)
    tabButtons[i] = tab
end

-- Ensure tabs are positioned and shown
UpdateTabVisibility()

-- Route Planner UI

local highlightedLabel = nil

-- Define the function implementation
ShowRouteLeg = function(idx)
    if not rightPane or not Route[idx] then return end
    
    -- Update persistent selected leg
    selectedLeg = idx
    BattlePetPlannerDB.lastSelectedLeg = idx
    
    -- Force hide landing page first
    if rightPane.landingWidgets then
        for _, w in ipairs(rightPane.landingWidgets) do w:Hide() end
        rightPane.landingWidgets = {}
    end
    
    -- Update tab visuals before doing anything else
    for i, btn in ipairs(tabButtons) do
        if i == idx then
            btn:LockHighlight()
            PanelTemplates_SelectTab(btn)
        else
            btn:UnlockHighlight()
            PanelTemplates_DeselectTab(btn)
        end
    end



    -- Create route elements if needed
    if not rightPane.routeNote then
        rightPane.routeNote = rightPane:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        rightPane.routeNote:SetWidth(400)
        rightPane.routeNote:SetJustifyH("CENTER")
        rightPane.routeNote:SetText("|cff00ff00Tip:|r Click a pet name below to plot a waypoint on your map!")
        rightPane.routeNote:SetPoint("TOP", rightPane, "TOP", 0, -50)
    end
    
    -- Show all route elements
    rightPane.routeNote:Show()
    if rightPane.scrollFrame then rightPane.scrollFrame:Show() end
    if rightPane.showCollectedCheckbox then rightPane.showCollectedCheckbox:Show() end
    if rightPane.plotAllWaypointsCheckbox then rightPane.plotAllWaypointsCheckbox:Show() end

    -- Hide old route content
    if rightPane.steps then
        for _, s in ipairs(rightPane.steps) do s:Hide() end
        rightPane.steps = nil
    end

    -- Filter steps for seasonality and remove navigation steps with no pets
    local function isStepInSeason(step)
        if step.seasonStart and step.seasonEnd then
            local now = date("!*t")
            local startMonth, startDay = step.seasonStart.month, step.seasonStart.day
            local endMonth, endDay = step.seasonEnd.month, step.seasonEnd.day
            local afterStart = (now.month > startMonth) or (now.month == startMonth and now.day >= startDay)
            local beforeEnd = (now.month < endMonth) or (now.month == endMonth and now.day <= endDay)
            return afterStart and beforeEnd
        end
        return true
    end
    -- First, filter steps by seasonality
    local filteredSteps = {}
    for _, step in ipairs(Route[idx].steps) do
        if isStepInSeason(step) then table.insert(filteredSteps, step) end
    end
    -- Then, filter out navigation steps with no pets
    -- Separate navigation and capture steps
    local navSteps, captureSteps = {}, {}
    for i, step in ipairs(filteredSteps) do
        if string.sub(step.text, 1, 6) == "Go to " and step.mapID then
            -- Look ahead for any visible capture step with same mapID
            local hasPet = false
            for j = i + 1, #filteredSteps do
                local nextStep = filteredSteps[j]
                if nextStep.mapID == step.mapID and string.sub(nextStep.text, 1, 8) == "Capture " then
                    hasPet = true
                    break
                end
            end
            if hasPet then table.insert(navSteps, step) end
        elseif string.sub(step.text, 1, 8) == "Capture " and step.mapID and step.coord then
            -- Only use TSP for valid capture steps
            table.insert(captureSteps, step)
        end
    end
    -- Determine player position for TSP
    local startIdx = 1
    local tspPoints = {}
    local playerMap, playerX, playerY
    if C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition then
        playerMap = C_Map.GetBestMapForUnit("player")
        if playerMap then
            local pos = C_Map.GetPlayerMapPosition(playerMap, "player")
            if pos then
                playerX, playerY = pos:GetXY()
            end
        end
    end
    for i, step in ipairs(captureSteps) do
        tspPoints[i] = {
            mapID = step.mapID,
            x = step.coord[1],
            y = step.coord[2],
            name = step.text,
        }
    end
    -- If player is on a relevant map, insert as start point
    if playerMap and playerX and playerY then
        local found = nil
        for i, pt in ipairs(tspPoints) do
            if pt.mapID == playerMap then found = i break end
        end
        if found then
            tspPoints[found].x = playerX * 100
            tspPoints[found].y = playerY * 100
            startIdx = found
        end
    end
    -- Run TSP if enough points
    local tspOrder
    if TSP_Solve and #tspPoints > 1 then
        local result = TSP_Solve(tspPoints, startIdx)
        tspOrder = result and result.order
    end
    -- Build final steps list: navigation steps appear immediately before first capture in each zone
    local steps = {}
    local zoneFirstCapture = {}
    local zoneNavStep = {}
    for _, nav in ipairs(navSteps) do
        zoneNavStep[nav.mapID] = nav
    end
    local usedZones = {}
    if tspOrder then
        for i = 2, #tspOrder do -- skip index 1 (start)
            local capStep = captureSteps[tspOrder[i]]
            local mapID = capStep.mapID
            if not usedZones[mapID] and zoneNavStep[mapID] then
                table.insert(steps, zoneNavStep[mapID])
                usedZones[mapID] = true
            end
            table.insert(steps, capStep)
        end
    else
        for _, capStep in ipairs(captureSteps) do
            local mapID = capStep.mapID
            if not usedZones[mapID] and zoneNavStep[mapID] then
                table.insert(steps, zoneNavStep[mapID])
                usedZones[mapID] = true
            end
            table.insert(steps, capStep)
        end
    end
    local num = 1 

    -- Attach a scrollable container to the right pane if not present
    if not rightPane.stepsContainer then
        -- Container for steps and scrollbar, below tabs/checkboxes
        local container = CreateFrame("Frame", nil, rightPane)
        container:SetPoint("TOPLEFT", rightPane, "TOPLEFT", 6, -120)
        container:SetPoint("BOTTOMRIGHT", rightPane, "BOTTOMRIGHT", -5, 8)
        container:SetClipsChildren(true) -- Ensures content is clipped to this area
        rightPane.stepsContainer = container

        -- ScrollChild: The visible mask area
        local scrollChild = CreateFrame("Frame", nil, container)
        scrollChild:SetPoint("TOPLEFT", rightPane, "TOPLEFT", 0, 0)
        scrollChild:SetPoint("BOTTOMRIGHT", rightPane, "BOTTOMRIGHT", 0, 0)
        scrollChild:SetPoint("TOPLEFT")
        scrollChild:SetPoint("BOTTOMRIGHT")
        scrollChild:SetClipsChildren(true)
        rightPane.scrollChild = scrollChild


        -- Content: The actual scrollable content (step labels)
        local content = CreateFrame("Frame", nil, scrollChild)
        content:SetPoint("TOPLEFT")
        content:SetWidth(scrollChild:GetWidth()) -- Will be updated dynamically
        rightPane.stepContent = content
    end
    local content = rightPane.stepContent
    if not content.lines then content.lines = {} end


    -- Minimal Scrollbar integration (attach only once)
    if not rightPane.minimalScrollBar and rightPane.stepsContainer and rightPane.scrollChild and rightPane.stepContent then
        local BPP_MinimalScrollbar = _G.BPP_MinimalScrollbar
        if BPP_MinimalScrollbar and BPP_MinimalScrollbar.Attach then
            local opts = {
                width = 8,
                skinnyWidth = 4,
                arrowButtonHeight = 16,
                padding = 4,
                totalNumItems = #steps,
                buttonHeight = 22,
            }
            local minimalScrollBar = BPP_MinimalScrollbar.Attach(
                rightPane.stepsContainer,
                rightPane.scrollChild,
                rightPane.stepContent,
                opts
            )
            rightPane.minimalScrollBar = minimalScrollBar
            minimalScrollBar:Show()

            -- Helper to update range and thumb
            local function RefreshStepsScrollbar()
                local numSteps = #steps
                local visibleRows = math.floor((rightPane.scrollChild:GetHeight() or 1) / 22)
                local maxScroll = math.max(0, numSteps - visibleRows)
                minimalScrollBar:SetMinMaxValues(0, maxScroll)
                if minimalScrollBar:GetValue() > maxScroll then
                    minimalScrollBar:SetValue(maxScroll)
                end
            end

            rightPane.scrollChild:HookScript("OnShow", RefreshStepsScrollbar)
            rightPane.scrollChild:HookScript("OnSizeChanged", RefreshStepsScrollbar)
            rightPane.stepContent:HookScript("OnSizeChanged", RefreshStepsScrollbar)

            -- Move content on scroll
            minimalScrollBar:SetScript("OnValueChanged", function(self, value)
                rightPane.stepContent:ClearAllPoints()
                rightPane.stepContent:SetPoint("TOPLEFT", rightPane.scrollChild, "TOPLEFT", 0, value * 22)
            end)
            rightPane.stepsContainer:EnableMouseWheel(true)
            rightPane.stepsContainer:SetScript("OnMouseWheel", function(self, delta)
    local min, max = minimalScrollBar:GetMinMaxValues()
    local newVal = minimalScrollBar:GetValue() - delta
    if newVal < min then newVal = min end
    if newVal > max then newVal = max end
    minimalScrollBar:SetValue(newVal)
end)
            -- Initial update
            RefreshStepsScrollbar()
            minimalScrollBar:SetValue(0)
        end
    end

    -- Hide scrollbar on landing page (if stepsContainer is hidden)
    if rightPane.minimalScrollBar and (not rightPane.stepsContainer:IsShown()) then
        rightPane.minimalScrollBar:Hide()
    end

    -- Hide old lines
    for _, line in ipairs(content.lines) do line:Hide() end
    -- Two-pass grouping: build a map of navigation steps to captures, then filter
    local canFilter = C_PetJournal and C_PetJournal.GetNumCollectedInfo
    local zones = {}
    local zoneOrder = {}
    local lastZone = nil

    -- First check if we have collection data access
    if not canFilter then 
        return
    end

    -- First group all steps by zone
    for _, step in ipairs(steps) do
        if string.sub(step.text, 1, 6) == "Go to " and step.mapID then
            if not zones[step.mapID] then
                zones[step.mapID] = { nav = step, captures = {} }
                table.insert(zoneOrder, step.mapID)
            end
            lastZone = step.mapID
        elseif string.sub(step.text, 1, 8) == "Capture " and step.mapID and lastZone then
            -- Only add capture steps that have a valid speciesID
            if step.speciesID then
                table.insert(zones[lastZone].captures, step)
            end
        end
    end

    -- Check collection status for all pets first
    local anyUncollectedPets = false
    for _, mapID in ipairs(zoneOrder) do
        local zone = zones[mapID]
        zone.hasUncollected = false
        
        for _, capture in ipairs(zone.captures) do
            local numCollected = C_PetJournal.GetNumCollectedInfo(capture.speciesID) or 0
            if numCollected == 0 then
                zone.hasUncollected = true
                anyUncollectedPets = true
                break -- Found an uncollected pet in this zone, can stop checking
            end
        end
    end

    -- Always update the showCollectedCheckbox for the current tab before any early return
    if not rightPane.showCollectedCheckbox then
        local cb = CreateFrame("CheckButton", nil, rightPane, "UICheckButtonTemplate")
        cb:ClearAllPoints()
        cb:SetPoint("TOPLEFT", rightPane, "TOPLEFT", 8, -80)
        cb.text = cb:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        cb.text:SetPoint("LEFT", cb, "RIGHT", 4, 0)
        cb.text:SetText("Show collected pets in routes")
        if not BattlePetPlannerDB.showCollectedRoutes then
            BattlePetPlannerDB.showCollectedRoutes = {}
        end
        cb:SetChecked(BattlePetPlannerDB.showCollectedRoutes[idx] or false)
        cb.currentTab = idx
        cb:SetScript("OnClick", function(self)
            BattlePetPlannerDB.showCollectedRoutes[self.currentTab] = self:GetChecked()
            selectedLeg = self.currentTab
            ShowRouteLeg(self.currentTab)
        end)
        rightPane.showCollectedCheckbox = cb
    else
        rightPane.showCollectedCheckbox.currentTab = idx
        rightPane.showCollectedCheckbox:SetChecked(BattlePetPlannerDB.showCollectedRoutes[idx] or false)
        rightPane.showCollectedCheckbox:Show()
    end

    -- Always update the plotAllWaypointsCheckbox for the current tab before any early return
    if not rightPane.plotAllWaypointsCheckbox then
        local cb2 = CreateFrame("CheckButton", nil, rightPane, "UICheckButtonTemplate")
        cb2:ClearAllPoints()
        cb2:SetPoint("LEFT", rightPane.showCollectedCheckbox, "RIGHT", 160, 0)
        cb2.text = cb2:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        cb2.text:SetPoint("LEFT", cb2, "RIGHT", 4, 0)
        cb2.text:SetText("Plot all waypoints for this pet")
        if not BattlePetPlannerDB.plotAllWaypoints then
            BattlePetPlannerDB.plotAllWaypoints = {}
        end
        cb2:SetChecked(BattlePetPlannerDB.plotAllWaypoints[idx] or false)
        cb2.currentTab = idx
        cb2:SetScript("OnClick", function(self)
            BattlePetPlannerDB.plotAllWaypoints[self.currentTab] = self:GetChecked()
            selectedLeg = self.currentTab
            ShowRouteLeg(self.currentTab)
        end)
        rightPane.plotAllWaypointsCheckbox = cb2
    else
        rightPane.plotAllWaypointsCheckbox.currentTab = idx
        rightPane.plotAllWaypointsCheckbox:SetChecked(BattlePetPlannerDB.plotAllWaypoints[idx] or false)
        rightPane.plotAllWaypointsCheckbox:Show()
    end

    -- Ensure showCollectedRoutes is always a table
    if type(BattlePetPlannerDB.showCollectedRoutes) ~= "table" then
        BattlePetPlannerDB.showCollectedRoutes = {}
    end
    -- Early exit if everything is collected and we're not showing collected pets
    local showCollected = BattlePetPlannerDB.showCollectedRoutes[idx] or false
    if not anyUncollectedPets and not showCollected then
        if rightPane.routeNote then rightPane.routeNote:Show() end
        if rightPane.scrollFrame then rightPane.scrollFrame:Show() end
    
        -- Show the congratulatory message centered in the visible scroll area
        local parentFrame = rightPane.stepsContainer
        if parentFrame then
            if not parentFrame.allCollectedMessage then
                local msg = parentFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightHuge")
                msg:SetPoint("CENTER", parentFrame, "CENTER", 0, 30)
                msg:SetWidth(340)
                msg:SetJustifyH("CENTER")
                msg:SetTextColor(1, 0.85, 0.2, 1)
                msg:SetText("|TInterface\\AddOns\\BattlePetPlanner\\Icons\\trophy.tga:14:14:0:0|t Congratulations!|nYou've collected all the battle pets in this region! |TInterface\\AddOns\\BattlePetPlanner\\Icons\\trophy.tga:14:14:0:0|t")
                parentFrame.allCollectedMessage = msg
            end
            parentFrame.allCollectedMessage:Show()
        end
        if rightPane.minimalScrollBar then
            rightPane.minimalScrollBar:Hide()
        end
        return
    else
        if rightPane.stepsContainer and rightPane.stepsContainer.allCollectedMessage then
            rightPane.stepsContainer.allCollectedMessage:Hide()
        end
        if rightPane.minimalScrollBar then
            rightPane.minimalScrollBar:Show()
        end
    end

    -- Build final display steps list
    local steps = {}
    for _, mapID in ipairs(zoneOrder) do
        local zone = zones[mapID]
        local hasStepsToShow = false
        local zoneSteps = {}

        -- Check if we should include this zone's steps
        for _, capture in ipairs(zone.captures) do
            local numCollected = C_PetJournal.GetNumCollectedInfo(capture.speciesID) or 0
            local petName = "?"
            if C_PetJournal.GetPetInfoBySpeciesID then
                local name = select(1, C_PetJournal.GetPetInfoBySpeciesID(capture.speciesID))
                if type(name) == "string" then
                    petName = name
                end
            end

            if numCollected == 0 or showCollected then
                hasStepsToShow = true
                table.insert(zoneSteps, capture)
            end
        end

        -- Only add navigation and captures if we have steps to show
        if hasStepsToShow then
            table.insert(steps, zone.nav)
            for _, step in ipairs(zoneSteps) do
                table.insert(steps, step)
            end
        end
    end

    -- Debug print: Show final steps before rendering

    for i, step in ipairs(steps) do

    end

    -- Fallback: If no steps were found using zone grouping, try displaying flat steps directly
    if #steps == 0 and Route[idx] and Route[idx].steps then
        for _, step in ipairs(Route[idx].steps) do
            -- Only add steps that are not navigation, or are 'Capture' steps, and match the filter
            if step.speciesID then
                local numCollected = C_PetJournal.GetNumCollectedInfo(step.speciesID) or 0
                if numCollected == 0 or showCollected then
                    table.insert(steps, step)
                end
            elseif string.sub(step.text or '', 1, 6) == "Go to " then
                -- Always add navigation steps if followed by a capture step (optional: could refine)
                table.insert(steps, step)
            end
        end
    end


        -- Rebuild lines for steps
        for i, step in ipairs(steps) do
        local label = content.lines[i] or content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        content.lines[i] = label
        label:SetJustifyH("LEFT")
        label:SetWidth(370)
        if string.sub(step.text, 1, 6) == "Go to " then
            label:SetFontObject(GameFontNormal)
            label:SetTextColor(1, 0.82, 0, 1)
            label:SetText(string.format("%d. %s", num, step.text))
            num = num + 1
        else
            label:SetFontObject(GameFontHighlightSmall)
            label:SetTextColor(1, 1, 1, 1)
            label:SetText("    • " .. step.text)
        end
        -- Position each label relative to the block (content frame)
        local baseYOffset = -2  -- Tiny vertical gap at the top
        local yOffset = baseYOffset - ((i-1)*22 - 1)
        label:SetPoint("TOPLEFT", content, "TOPLEFT", 15, yOffset)  -- Increased horizontal gap (15px left)
        label:Show()
    end
    content:SetHeight(#steps * 22)
    -- No scrollFrame: handled by minimal scrollbar logic
    if rightPane.minimalScrollBar then
        local numSteps = #steps
        local visibleRows = math.floor((rightPane.scrollChild:GetHeight() or 1) / 22)
        local maxScroll = math.max(0, numSteps - visibleRows)
        rightPane.minimalScrollBar:SetMinMaxValues(0, maxScroll)
        if rightPane.minimalScrollBar:GetValue() > maxScroll then
            rightPane.minimalScrollBar:SetValue(maxScroll)
        end
        rightPane.minimalScrollBar:Show()
    end

    local tabKey = selectedLeg or 1
    if not BattlePetPlannerDB.showCollectedRoutes then
        BattlePetPlannerDB.showCollectedRoutes = {}
    end

    if not rightPane.showCollectedCheckbox then
        local cb = CreateFrame("CheckButton", nil, rightPane, "UICheckButtonTemplate")
        cb:ClearAllPoints()
        cb:SetPoint("TOPLEFT", rightPane, "TOPLEFT", 8, -80)
        cb.text = cb:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        cb.text:SetPoint("LEFT", cb, "RIGHT", 4, 0)
        cb.text:SetText("Show collected pets in routes")
        
        -- Initialize saved variable if needed
        if not BattlePetPlannerDB.showCollectedRoutes then
            BattlePetPlannerDB.showCollectedRoutes = {}
        end
        
        -- Set initial state from saved variable using current tab index
        cb:SetChecked(BattlePetPlannerDB.showCollectedRoutes[idx] or false)
        
        -- Store current tab index in the checkbox for reference
        cb.currentTab = idx
        
        cb:SetScript("OnClick", function(self)
            -- Save state for current tab only
            BattlePetPlannerDB.showCollectedRoutes[self.currentTab] = self:GetChecked()
            -- Ensure selectedLeg is set before refreshing display
            selectedLeg = self.currentTab
            ShowRouteLeg(self.currentTab)
        end)
        
        rightPane.showCollectedCheckbox = cb
    else
        -- Update existing checkbox state and tab reference
        rightPane.showCollectedCheckbox.currentTab = idx
        rightPane.showCollectedCheckbox:SetChecked(BattlePetPlannerDB.showCollectedRoutes[idx] or false)
    end
end

local function UpdateTabVisibility()
    -- Hide all tabs first
    for i, tab in ipairs(tabButtons) do
        tab:Hide()
    end
    -- Calculate centering
    local numTabs = math.min(TABS_PER_PAGE, #Route - tabPageStart + 1)
    local tabWidth = 110
    local tabSpacing = 1
    local totalTabWidth = numTabs * tabWidth + (numTabs-1) * tabSpacing
    local paneWidth = rightPane:GetWidth() or 400
    local startX = math.floor((paneWidth - totalTabWidth) / 2)
    -- Show only the current page of tabs, centered
    local visible = 0
    for i = tabPageStart, math.min(tabPageStart + TABS_PER_PAGE - 1, #Route) do
        visible = visible + 1
        local tab = tabButtons[i]
        if tab then
            tab:SetWidth(tabWidth)
            if visible == 1 then
                tab:ClearAllPoints()
                tab:SetPoint("TOPLEFT", rightPane, "TOPLEFT", startX, 0)
            else
                tab:ClearAllPoints()
                tab:SetPoint("LEFT", tabButtons[i-1], "RIGHT", tabSpacing, 0)
            end
            tab:Show()
        end
    end
    -- Enable/disable arrows
    if leftArrow then leftArrow:SetEnabled(tabPageStart > 1) end
    if rightArrow then rightArrow:SetEnabled(tabPageStart + TABS_PER_PAGE <= #Route) end
end

local function ScrollTabs(direction)
    local numTabs = #Route
    local maxPage = math.ceil(numTabs / TABS_PER_PAGE)
    local currentPage = math.ceil(tabPageStart / TABS_PER_PAGE)
    if direction == "left" then
        currentPage = math.max(1, currentPage - 1)
    elseif direction == "right" then
        currentPage = math.min(maxPage, currentPage + 1)
    end
    tabPageStart = (currentPage - 1) * TABS_PER_PAGE + 1
    UpdateTabVisibility()
end

-- Create tab buttons
-- (tabButtons population moved above)

-- Create left/right arrow buttons
leftArrow = CreateFrame("Button", nil, rightPane, "UIPanelButtonTemplate")
leftArrow:SetSize(32, 32)
leftArrow:SetText("<")
leftArrow:SetPoint("TOPLEFT", rightPane, "TOPLEFT", 3, 0)
leftArrow:SetScript("OnClick", function() ScrollTabs("left") end)

rightArrow = CreateFrame("Button", nil, rightPane, "UIPanelButtonTemplate")
rightArrow:SetSize(32, 32)
rightArrow:SetText(">")
rightArrow:SetPoint("TOPRIGHT", rightPane, "TOPRIGHT", -3, 0)
rightArrow:SetScript("OnClick", function() ScrollTabs("right") end)

UpdateTabVisibility()

-- ShowLandingPage() call removed; landing page will be shown via gui:SetScript("OnShow") and Home button only.

-- Clear all tab highlights on landing page
for i, btn in ipairs(tabButtons) do
    btn:UnlockHighlight()
end
-- Also clear any highlight after tab creation just in case
hooksecurefunc("PanelTemplates_DeselectTab", function(tab)
    if tab and tab.UnlockHighlight then tab:UnlockHighlight() end
end)

-- Do NOT select any tab by default; landing page is shown until a tab is clicked

-- Hide landing page when a tab is selected
local oldShowRouteLeg = ShowRouteLeg
ShowRouteLeg = function(idx)
    -- Hide landing page widgets if present
    if rightPane.landingWidgets then
        for _, w in ipairs(rightPane.landingWidgets) do w:Hide() end
    end
    -- Highlight only the selected tab
    for i, btn in ipairs(tabButtons) do
        if i == idx then
            btn:LockHighlight()
        else
            btn:UnlockHighlight()
        end
    end
    oldShowRouteLeg(idx)
end

-- Event handler(s)
local function OnAddonLoaded(self, event, ...)
    local addonName = ...
    if event == "ADDON_LOADED" and addonName == "BattlePetPlanner" then
        BattlePetPlannerDB = BattlePetPlannerDB or {}
        BattlePetPlannerDB.minimap = BattlePetPlannerDB.minimap or {}
        print("BattlePetPlanner is loaded.")
        BattlePetPlanner_ScanMissingPets()
        BattlePetPlanner_UpdatePetListGUI()
        -- Hook search box update
        if BattlePetPlannerSearchBox then
            BattlePetPlannerSearchBox:SetScript("OnTextChanged", function(self)
                BattlePetPlanner_UpdatePetListGUI()
            end)
        end
    elseif event == "PET_JOURNAL_LIST_UPDATE" then
        BattlePetPlanner_ScanMissingPets()
        BattlePetPlanner_UpdatePetListGUI()
        -- Always update the right pane route view when collection changes
        if BattlePetPlannerFrame and BattlePetPlannerFrame:IsShown() and ShowRouteLeg and selectedLeg then
            ShowRouteLeg(selectedLeg)
        end
    end
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("PET_JOURNAL_LIST_UPDATE") -- Ensure we rescan when the pet journal updates

f:SetScript("OnEvent", function(self, event, ...)
    if event == "PET_JOURNAL_LIST_UPDATE" then
        BattlePetPlanner_ScanMissingPets()
        BattlePetPlanner_UpdatePetListGUI()
        -- Always update the right pane route view when collection changes
        if BattlePetPlannerFrame and BattlePetPlannerFrame:IsShown() and ShowRouteLeg and selectedLeg then
            ShowRouteLeg(selectedLeg)
        end
    end
end)

f:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        OnAddonLoaded(self, event, ...)
    elseif event == "PLAYER_LOGIN" then
        -- Register minimap button on PLAYER_LOGIN, after all frames are loaded
        local ldb = LibStub and LibStub("LibDataBroker-1.1", true)
        local dbicon = LibStub and LibStub("LibDBIcon-1.0", true)
        if ldb and dbicon then
            local icon = ldb:NewDataObject("BattlePetPlanner", {
                type = "launcher",
                text = "BattlePetPlanner",
                icon = "Interface\\Icons\\Tracking_WildPet",
                OnClick = function(self, button)
                    if gui:IsShown() then gui:Hide() else BattlePetPlanner_UpdatePetListGUI(); gui:Show() end
                end,
                OnTooltipShow = function(tt)
                    tt:AddLine("BattlePetPlanner")
                end,
            })
            dbicon:Register("BattlePetPlanner", icon, BattlePetPlannerDB.minimap)
        end
    end
end)


-- Minimap button logic will be registered on PLAYER_LOGIN

-- =====================
-- LEFT PANE: Pet List GUI Update Function
-- =====================
function BattlePetPlanner_UpdatePetListGUI()
    local allPets = BattlePetPlannerDB and BattlePetPlannerDB.allPets or {}
    if type(allPets) ~= "table" then allPets = {} end
    local content = petListContent
    if not content then
        return
    end
    -- Filter by search text
    local searchText = (BattlePetPlannerSearchBox and BattlePetPlannerSearchBox:GetText()) or ""
    local displayPets = {}
    if type(allPets) == "table" then
        if searchText ~= "" then
            local filtered = {}
            local lower = string.lower(searchText)
            for _, pet in ipairs(allPets) do
                if string.find(string.lower(pet.name or ""), lower, 1, true) then
                    table.insert(filtered, pet)
                end
            end
            displayPets = filtered
        else
            displayPets = allPets
        end
    end
    if type(displayPets) ~= "table" then
        displayPets = {}
    end
    -- DO NOT sort the pet list here; preserve Pet Journal order
    local ROW_HEIGHT = 46
    content.buttonPool = content.buttonPool or {}
    -- Create pool if not enough
    local numDisplayPets = tonumber(#displayPets) or 0
    if numDisplayPets > 0 then
        for i = #content.buttonPool + 1, numDisplayPets do
            local btn = CreateFrame("Button", nil, content)
            btn:SetSize(209, ROW_HEIGHT)
            btn:SetNormalAtlas("PetList-ButtonBackground")
            btn:SetHighlightAtlas("PetList-ButtonHighlight")
            btn:SetPushedAtlas("PetList-ButtonSelect")
            -- Selection overlay
            btn.selectOverlay = btn:CreateTexture(nil, "OVERLAY")
            btn.selectOverlay:SetAllPoints()
            btn.selectOverlay:SetAtlas("PetList-ButtonHighlight")
            btn.selectOverlay:Hide()
            -- Icon
            btn.icon = btn:CreateTexture(nil, "ARTWORK")
            btn.icon:SetSize(22, 22)
            btn.icon:SetPoint("LEFT", btn, "LEFT", 2, 0)
            -- Name
            btn.name = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            btn.name:SetPoint("LEFT", btn.icon, "RIGHT", 6, 0)
            btn.name:SetWidth(130)
            btn.name:SetJustifyH("LEFT")
            btn.name:SetWordWrap(true)
            -- Pet type icon
            btn.petTypeIcon = btn:CreateTexture(nil, "ARTWORK")
            btn.petTypeIcon:SetSize(22, 22)
            btn.petTypeIcon:SetPoint("RIGHT", btn, "RIGHT", -2, 0)
            content.buttonPool[i] = btn
        end
    end
    -- Hide any extra buttons
    for i = #displayPets + 1, #content.buttonPool do
        content.buttonPool[i]:Hide()
    end
    -- Lay out and set up all buttons
    for i, pet in ipairs(displayPets) do
        local btn = content.buttonPool[i]
        btn:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -((i-1)*ROW_HEIGHT))
        -- Set up icon, name, type, selection, scripts, etc. here (reuse your existing logic)

        -- Grey out uncollected pets using pet.isOwned
        if pet.isOwned == false or pet.isOwned == nil then
            if btn.icon.SetDesaturated then btn.icon:SetDesaturated(true) end
            if btn.name.SetTextColor then btn.name:SetTextColor(0.5, 0.5, 0.5) end
        else
            if btn.icon.SetDesaturated then btn.icon:SetDesaturated(false) end
            if btn.name.SetTextColor then btn.name:SetTextColor(1, 0.82, 0) end -- WoW default yellow
        end
        btn:Show()
    end

    content:SetHeight(#displayPets * ROW_HEIGHT)
    -- No scrollOffset or virtualization needed
    -- Display only visible rows
    local selectedPetIndex = content.selectedPetIndex or nil
    local petTypeTextures = {
        [1] = "Interface/PetBattles/PetIcon-Humanoid",
        [2] = "Interface/PetBattles/PetIcon-Dragon",
        [3] = "Interface/PetBattles/PetIcon-Flying",
        [4] = "Interface/PetBattles/PetIcon-Undead",
        [5] = "Interface/PetBattles/PetIcon-Critter",
        [6] = "Interface/PetBattles/PetIcon-Magical",
        [7] = "Interface/PetBattles/PetIcon-Elemental",
        [8] = "Interface/PetBattles/PetIcon-Beast",
        [9] = "Interface/PetBattles/PetIcon-Water",
        [10] = "Interface/PetBattles/PetIcon-Mechanical",
    }
    -- Dynamically determine visibleRows based on content frame height
    local visibleRows = math.max(1, math.floor((content:GetHeight() or (#displayPets * ROW_HEIGHT)) / ROW_HEIGHT))
    visibleRows = math.min(visibleRows, #displayPets)
    for row = 1, visibleRows do
        local i = row + (scrollOffset or 0)
        local btn = content.buttonPool[row]
        if i <= #displayPets then
            local pet = displayPets[i]
            btn:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -((row-1)*ROW_HEIGHT))
            btn.icon:SetTexture(pet.icon)
            btn.name:SetText(pet.name)
            local texturePath = petTypeTextures[pet.petType]
            if texturePath then
                btn.petTypeIcon:SetTexture(texturePath)
                btn.petTypeIcon:SetSize(22, 22)
                btn.petTypeIcon:SetTexCoord(0.4609, 0.8516, 0.4844, 0.6797)
                btn.petTypeIcon:Show()
            else
                btn.petTypeIcon:Hide()
            end
            if selectedPetIndex == i then
                btn.selectOverlay:Show()
            else
                btn.selectOverlay:Hide()
            end
            -- Button scripting and highlight logic (must be inside the loop)
            btn:SetScript("OnClick", function()
                content.selectedPetIndex = i
                BattlePetPlanner_UpdatePetListGUI()
            end)
            if not btn.bg then
                btn.bg = btn:CreateTexture(nil, "BACKGROUND")
                btn.bg:SetAllPoints()
                btn.bg:SetAtlas("PetList-ButtonBackground")
            end
            btn:SetScript("OnEnter", function(self)
                btn.bg:SetAtlas("PetList-ButtonHighlight")
            end)
            btn:SetScript("OnLeave", function(self)
                if content.selectedPetIndex == i then
                    btn.bg:SetAtlas("PetList-ButtonSelect")
                else
                    btn.bg:SetAtlas("PetList-ButtonBackground")
                end
            end)
            btn:Enable()
            btn:Show()
        else
            btn:Hide()
        end
    end
    -- Hook scroll to update visible rows (only if scrollFrame supports OnVerticalScroll)
    if not content._scrollHooked then
        local parent = content:GetParent()
        local scrollFrame = nil
        if parent and type(parent.GetParent) == "function" then
            local maybeScroll = parent:GetParent()
            if maybeScroll and type(maybeScroll.HookScript) == "function" then
                -- Only hook if OnVerticalScroll is a valid handler for this frame
                local frameType = nil
                if type(maybeScroll.GetObjectType) == "function" then
                    frameType = maybeScroll:GetObjectType()
                end
                if frameType == "ScrollFrame" then
                    maybeScroll:HookScript("OnVerticalScroll", function()
                        BattlePetPlanner_UpdatePetListGUI()
                    end)
                    content._scrollHooked = true
                end
            end
        end
    end
end

-- Add this to the home button's OnClick handler
homeBtn:SetScript("OnClick", function()
    -- Hide any route content
    if rightPane.steps then
        for _, s in ipairs(rightPane.steps) do s:Hide() end
        rightPane.steps = nil
    end
    if rightPane.routeNote then rightPane.routeNote:Hide() end
    if rightPane.showCollectedCheckbox then rightPane.showCollectedCheckbox:Hide() end
    if rightPane.plotAllWaypointsCheckbox then rightPane.plotAllWaypointsCheckbox:Hide() end
    if rightPane.scrollFrame then rightPane.scrollFrame:Hide() end

    -- Deselect ALL tabs
    if tabButtons then
        for _, btn in ipairs(tabButtons) do
            if btn.UnlockHighlight then btn:UnlockHighlight() end
            if btn.SetChecked then btn:SetChecked(false) end
            if PanelTemplates_DeselectTab then PanelTemplates_DeselectTab(btn) end
            if btn.SetButtonState then btn:SetButtonState("NORMAL", false) end
            btn.selected = nil
            btn.checked = nil
        end
    end

    -- Reset selected leg and clear from saved variables
    selectedLeg = nil
    BattlePetPlannerDB.lastSelectedLeg = nil

    -- Show landing page
    ShowLandingPage()
end)
