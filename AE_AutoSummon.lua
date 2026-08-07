local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
local Nodes = require(ReplicatedStorage:WaitForChild("Nodes"))

local math_floor = math.floor
local math_max = math.max
local string_format = string.format
local task_wait = task.wait
local task_spawn = task.spawn
local pcall = pcall
local type = type
local typeof = typeof
local table_find = table.find
local table_insert = table.insert

if PlayerGui:FindFirstChild("AutoSummonGUI") then
    PlayerGui.AutoSummonGUI:Destroy()
end

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "AutoSummonGUI"
ScreenGui.ResetOnSpawn = false
ScreenGui.DisplayOrder = 9999
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

local activeBanners = {}
local activeBannersFull = {}

local function updateBannerList()
    local success, banners = pcall(function()
        return Nodes.GET_ACTIVE_BANNERS:InvokeSelf()
    end)
    if success and type(banners) == "table" then
        activeBannersFull = banners
        for bannerId, _ in pairs(banners) do
            if not table_find(activeBanners, bannerId) then
                table_insert(activeBanners, bannerId)
            end
        end
    end
end

updateBannerList()

local selectedBanner = table_find(activeBanners, "Standard") and "Standard" or (activeBanners[1] or "Standard")
local summonAmount = 10
local isAutoSummoning = false
local skipAnimation = true
local currentSessionPulls = 0
local initialBannerSummonCount = 0

pcall(function()
    Nodes.CHANGE_SETTING:FireServer("FastSummon", true)
end)

-- Zero-Flicker Event Hooking
local hookedSignals = {}
local function setupNoFlickerHooks()
    local targetSignals = {
        Nodes.PROMPT_OBTAINED_REWARD_SLOTS,
        Nodes.PROMPT_OBTAINED_REWARDS,
        Nodes.PROMPT_OBTAINMENT_OVERLAY
    }
    for _, nodeSignal in ipairs(targetSignals) do
        if nodeSignal and nodeSignal.Signal and not hookedSignals[nodeSignal.Signal] then
            local realFire = nodeSignal.Signal.Fire
            hookedSignals[nodeSignal.Signal] = true
            nodeSignal.Signal.Fire = function(self, ...)
                if skipAnimation or isAutoSummoning then
                    return nil
                end
                return realFire(self, ...)
            end
        end
    end
end
setupNoFlickerHooks()

local cachedReplica = nil
local function getReplica()
    if not cachedReplica then
        pcall(function()
            cachedReplica = Nodes.GET_PLAYER_REPLICA:InvokeSelf()
        end)
    end
    return cachedReplica
end

local function getBannerTotalSummonCount(bannerId)
    local replica = getReplica()
    if replica and replica.Data and replica.Data.BannerData and replica.Data.BannerData[bannerId] then
        return replica.Data.BannerData[bannerId].SummonCount or 0
    end
    return 0
end

local function resetSessionCounter()
    initialBannerSummonCount = getBannerTotalSummonCount(selectedBanner)
    currentSessionPulls = 0
end
resetSessionCounter()

local function getCurrencyAmount(currencyName)
    local success, val = pcall(function()
        return Nodes.GET_DATA_VALUE:InvokeSelf({"ItemData", currencyName, "Amount"})
    end)
    if success and type(val) == "number" then
        return val
    end
    local replica = getReplica()
    if replica and replica.Data and replica.Data.ItemData then
        local item = replica.Data.ItemData[currencyName]
        if type(item) == "table" then
            return item.Amount or 0
        elseif type(item) == "number" then
            return item
        end
    end
    return 0
end

local function getPityData(bannerId)
    local replica = getReplica()
    local bannerData = activeBannersFull[bannerId] and activeBannersFull[bannerId].Data
    local bannerInfo = bannerData and bannerData.BannerInfo
    local maxPity = bannerInfo and bannerInfo.Pity or {}

    local currentPity = {}
    if replica and replica.Data and replica.Data.BannerData and replica.Data.BannerData[bannerId] then
        currentPity = replica.Data.BannerData[bannerId].Pity or {}
    end

    return maxPity, currentPity
end

local function checkCurrencyRequirement()
    local bannerData = activeBannersFull[selectedBanner] and activeBannersFull[selectedBanner].Data
    local bannerInfo = bannerData and bannerData.BannerInfo

    local costPerPull = bannerInfo and bannerInfo.Cost or 50
    local currencyName = bannerInfo and bannerInfo.Currency or "Gem"
    local totalCost = costPerPull * summonAmount
    local currentBalance = getCurrencyAmount(currencyName)

    local isEnough = (currentBalance >= totalCost)
    local maxAffordablePulls = (costPerPull > 0) and math_floor(currentBalance / costPerPull) or 0

    return isEnough, totalCost, currentBalance, currencyName, costPerPull, maxAffordablePulls
end

-- Ultra-Smooth CanvasGroup
local defaultMainSize = UDim2.new(0, 330, 0, 395)
local defaultMainPos = UDim2.new(0, 25, 0.5, -197)

local MainFrame = Instance.new("CanvasGroup")
MainFrame.Name = "MainFrame"
MainFrame.Size = defaultMainSize
MainFrame.Position = defaultMainPos
MainFrame.BackgroundColor3 = Color3.fromRGB(18, 20, 26)
MainFrame.BorderSizePixel = 0
MainFrame.ClipsDescendants = false
MainFrame.GroupTransparency = 0
MainFrame.Parent = ScreenGui

local UICorner = Instance.new("UICorner")
UICorner.CornerRadius = UDim.new(0, 12)
UICorner.Parent = MainFrame

local UIStroke = Instance.new("UIStroke")
UIStroke.Color = Color3.fromRGB(65, 105, 225)
UIStroke.Thickness = 1.5
UIStroke.Transparency = 0
UIStroke.Parent = MainFrame

-- Floating Toggle Button (OpenBtn)
local OpenBtn = Instance.new("TextButton")
OpenBtn.Name = "OpenToggleButton"
OpenBtn.Size = UDim2.new(0, 50, 0, 50)
OpenBtn.Position = defaultMainPos
OpenBtn.BackgroundColor3 = Color3.fromRGB(26, 29, 38)
OpenBtn.Text = "✨"
OpenBtn.TextSize = 24
OpenBtn.Visible = false
OpenBtn.Parent = ScreenGui

local OpenCorner = Instance.new("UICorner")
OpenCorner.CornerRadius = UDim.new(1, 0)
OpenCorner.Parent = OpenBtn

local OpenStroke = Instance.new("UIStroke")
OpenStroke.Color = Color3.fromRGB(65, 105, 225)
OpenStroke.Thickness = 2
OpenStroke.Parent = OpenBtn

local function enableSmoothDrag(frame, dragHandle)
    local dragging = false
    local dragInput = nil
    local dragStart = nil
    local startPos = nil

    dragHandle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = frame.Position
            
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                end
            end)
        end
    end)

    dragHandle.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
            dragInput = input
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if input == dragInput and dragging then
            local delta = input.Position - dragStart
            local targetPos = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
            TweenService:Create(frame, TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Position = targetPos}):Play()
        end
    end)
end

local isAnimating = false

local function setGuiVisibleSmooth(visible)
    if isAnimating then return end
    isAnimating = true

    if visible then
        MainFrame.Position = OpenBtn.Position
        MainFrame.Size = UDim2.new(0, 50, 0, 50)
        UICorner.CornerRadius = UDim.new(1, 0)
        UIStroke.Transparency = 1
        MainFrame.GroupTransparency = 1
        MainFrame.Visible = true

        TweenService:Create(OpenBtn, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
            Size = UDim2.new(0, 0, 0, 0)
        }):Play()

        task_wait(0.04)
        OpenBtn.Visible = false

        TweenService:Create(UICorner, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
            CornerRadius = UDim.new(0, 12)
        }):Play()

        TweenService:Create(UIStroke, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
            Transparency = 0
        }):Play()

        local tExpand = TweenService:Create(MainFrame, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
            Size = defaultMainSize,
            GroupTransparency = 0
        })
        tExpand:Play()
        tExpand.Completed:Wait()
    else
        OpenBtn.Position = MainFrame.Position
        OpenBtn.Size = UDim2.new(0, 0, 0, 0)
        OpenBtn.Visible = true

        TweenService:Create(UICorner, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
            CornerRadius = UDim.new(1, 0)
        }):Play()

        TweenService:Create(UIStroke, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
            Transparency = 1
        }):Play()

        local tShrink = TweenService:Create(MainFrame, TweenInfo.new(0.26, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
            Size = UDim2.new(0, 50, 0, 50),
            GroupTransparency = 1
        })
        tShrink:Play()

        local tPop = TweenService:Create(OpenBtn, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
            Size = UDim2.new(0, 50, 0, 50)
        })
        tPop:Play()

        tShrink.Completed:Wait()
        MainFrame.Visible = false
    end

    isAnimating = false
end

OpenBtn.MouseButton1Click:Connect(function()
    setGuiVisibleSmooth(true)
end)

-- TopBar
local TopBar = Instance.new("Frame")
TopBar.Size = UDim2.new(1, 0, 0, 42)
TopBar.BackgroundColor3 = Color3.fromRGB(26, 29, 38)
TopBar.BorderSizePixel = 0
TopBar.Parent = MainFrame

local TopBarCorner = Instance.new("UICorner")
TopBarCorner.CornerRadius = UDim.new(0, 12)
TopBarCorner.Parent = TopBar

local TitleLabel = Instance.new("TextLabel")
TitleLabel.Size = UDim2.new(1, -50, 1, 0)
TitleLabel.Position = UDim2.new(0, 15, 0, 0)
TitleLabel.BackgroundTransparency = 1
TitleLabel.Text = "✨ Auto Summoner"
TitleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
TitleLabel.TextSize = 14
TitleLabel.Font = Enum.Font.GothamBold
TitleLabel.TextXAlignment = Enum.TextXAlignment.Left
TitleLabel.Parent = TopBar

local CloseBtn = Instance.new("TextButton")
CloseBtn.Size = UDim2.new(0, 36, 0, 36)
CloseBtn.Position = UDim2.new(1, -38, 0, 3)
CloseBtn.BackgroundTransparency = 1
CloseBtn.Text = "─"
CloseBtn.TextColor3 = Color3.fromRGB(180, 180, 190)
CloseBtn.TextSize = 18
CloseBtn.Font = Enum.Font.GothamBold
CloseBtn.Parent = TopBar

CloseBtn.MouseButton1Click:Connect(function()
    setGuiVisibleSmooth(false)
end)

UserInputService.InputBegan:Connect(function(input, gpe)
    if not gpe and (input.KeyCode == Enum.KeyCode.Insert or input.KeyCode == Enum.KeyCode.RightShift) then
        setGuiVisibleSmooth(not MainFrame.Visible)
    end
end)

enableSmoothDrag(MainFrame, TopBar)
enableSmoothDrag(OpenBtn, OpenBtn)

local ContentFrame = Instance.new("Frame")
ContentFrame.Size = UDim2.new(1, -30, 1, -52)
ContentFrame.Position = UDim2.new(0, 15, 0, 48)
ContentFrame.BackgroundTransparency = 1
ContentFrame.Parent = MainFrame

local BannerTitle = Instance.new("TextLabel")
BannerTitle.Size = UDim2.new(1, 0, 0, 16)
BannerTitle.Position = UDim2.new(0, 0, 0, 0)
BannerTitle.BackgroundTransparency = 1
BannerTitle.Text = "SELECT BANNER (AUTO-DETECTED):"
BannerTitle.TextColor3 = Color3.fromRGB(140, 145, 160)
BannerTitle.Font = Enum.Font.GothamBold
BannerTitle.TextSize = 10
BannerTitle.TextXAlignment = Enum.TextXAlignment.Left
BannerTitle.Parent = ContentFrame

local BannerDropdown = Instance.new("TextButton")
BannerDropdown.Size = UDim2.new(1, 0, 0, 34)
BannerDropdown.Position = UDim2.new(0, 0, 0, 18)
BannerDropdown.BackgroundColor3 = Color3.fromRGB(28, 32, 44)
BannerDropdown.Text = "Banner: " .. selectedBanner .. " ▼"
BannerDropdown.TextColor3 = Color3.fromRGB(230, 230, 245)
BannerDropdown.Font = Enum.Font.GothamMedium
BannerDropdown.TextSize = 12
BannerDropdown.Parent = ContentFrame

local DropCorner = Instance.new("UICorner")
DropCorner.CornerRadius = UDim.new(0, 6)
DropCorner.Parent = BannerDropdown

local DropStroke = Instance.new("UIStroke")
DropStroke.Color = Color3.fromRGB(50, 55, 70)
DropStroke.Thickness = 1
DropStroke.Parent = BannerDropdown

local BannerListFrame = Instance.new("ScrollingFrame")
BannerListFrame.Size = UDim2.new(1, 0, 0, 110)
BannerListFrame.Position = UDim2.new(0, 0, 0, 54)
BannerListFrame.BackgroundColor3 = Color3.fromRGB(24, 27, 36)
BannerListFrame.BorderSizePixel = 0
BannerListFrame.Visible = false
BannerListFrame.ZIndex = 50
BannerListFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
BannerListFrame.ScrollBarThickness = 4
BannerListFrame.Parent = ContentFrame

local ListCorner = Instance.new("UICorner")
ListCorner.CornerRadius = UDim.new(0, 6)
ListCorner.Parent = BannerListFrame

local ListStroke = Instance.new("UIStroke")
ListStroke.Color = Color3.fromRGB(65, 105, 225)
ListStroke.Thickness = 1
ListStroke.Parent = BannerListFrame

local UIListLayout = Instance.new("UIListLayout")
UIListLayout.SortOrder = Enum.SortOrder.LayoutOrder
UIListLayout.Padding = UDim.new(0, 3)
UIListLayout.Parent = BannerListFrame

local AmountFrame = Instance.new("Frame")
AmountFrame.Size = UDim2.new(1, 0, 0, 34)
AmountFrame.Position = UDim2.new(0, 0, 0, 56)
AmountFrame.BackgroundColor3 = Color3.fromRGB(26, 29, 38)
AmountFrame.BorderSizePixel = 0
AmountFrame.Parent = ContentFrame

local AmtCorner = Instance.new("UICorner")
AmtCorner.CornerRadius = UDim.new(0, 8)
AmtCorner.Parent = AmountFrame

local BtnX1 = Instance.new("TextButton")
BtnX1.Size = UDim2.new(0.333, -3, 1, -6)
BtnX1.Position = UDim2.new(0, 3, 0, 3)
BtnX1.BackgroundColor3 = Color3.fromRGB(40, 44, 58)
BtnX1.Text = "x1"
BtnX1.TextColor3 = Color3.fromRGB(180, 180, 200)
BtnX1.Font = Enum.Font.GothamMedium
BtnX1.TextSize = 13
BtnX1.Parent = AmountFrame
local X1Corner = Instance.new("UICorner")
X1Corner.CornerRadius = UDim.new(0, 6)
X1Corner.Parent = BtnX1

local BtnX10 = Instance.new("TextButton")
BtnX10.Size = UDim2.new(0.333, -3, 1, -6)
BtnX10.Position = UDim2.new(0.333, 1, 0, 3)
BtnX10.BackgroundColor3 = Color3.fromRGB(65, 105, 225)
BtnX10.Text = "x10"
BtnX10.TextColor3 = Color3.fromRGB(255, 255, 255)
BtnX10.Font = Enum.Font.GothamBold
BtnX10.TextSize = 13
BtnX10.Parent = AmountFrame
local X10Corner = Instance.new("UICorner")
X10Corner.CornerRadius = UDim.new(0, 6)
X10Corner.Parent = BtnX10

local BtnX50 = Instance.new("TextButton")
BtnX50.Size = UDim2.new(0.333, -3, 1, -6)
BtnX50.Position = UDim2.new(0.666, 0, 0, 3)
BtnX50.BackgroundColor3 = Color3.fromRGB(40, 44, 58)
BtnX50.Text = "x50"
BtnX50.TextColor3 = Color3.fromRGB(180, 180, 200)
BtnX50.Font = Enum.Font.GothamMedium
BtnX50.TextSize = 13
BtnX50.Parent = AmountFrame
local X50Corner = Instance.new("UICorner")
X50Corner.CornerRadius = UDim.new(0, 6)
X50Corner.Parent = BtnX50

local AnimToggleBtn = Instance.new("TextButton")
AnimToggleBtn.Size = UDim2.new(1, 0, 0, 32)
AnimToggleBtn.Position = UDim2.new(0, 0, 0, 96)
AnimToggleBtn.BackgroundColor3 = Color3.fromRGB(46, 204, 113)
AnimToggleBtn.Text = "⚡ Fast / Skip Animation: ON"
AnimToggleBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
AnimToggleBtn.Font = Enum.Font.GothamBold
AnimToggleBtn.TextSize = 11
AnimToggleBtn.Parent = ContentFrame

local AnimToggleCorner = Instance.new("UICorner")
AnimToggleCorner.CornerRadius = UDim.new(0, 6)
AnimToggleCorner.Parent = AnimToggleBtn

local ToggleBtn = Instance.new("TextButton")
ToggleBtn.Size = UDim2.new(1, 0, 0, 44)
ToggleBtn.Position = UDim2.new(0, 0, 0, 134)
ToggleBtn.BackgroundColor3 = Color3.fromRGB(46, 204, 113)
ToggleBtn.Text = "▶ START AUTO SUMMON"
ToggleBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
ToggleBtn.Font = Enum.Font.GothamBold
ToggleBtn.TextSize = 13
ToggleBtn.Parent = ContentFrame

local ToggleCorner = Instance.new("UICorner")
ToggleCorner.CornerRadius = UDim.new(0, 8)
ToggleCorner.Parent = ToggleBtn

-- Optimised Clean Pity Container Frame
local StatsFrame = Instance.new("Frame")
StatsFrame.Size = UDim2.new(1, 0, 0, 92)
StatsFrame.Position = UDim2.new(0, 0, 0, 186)
StatsFrame.BackgroundColor3 = Color3.fromRGB(24, 27, 36)
StatsFrame.BorderSizePixel = 0
StatsFrame.Parent = ContentFrame

local StatsCorner = Instance.new("UICorner")
StatsCorner.CornerRadius = UDim.new(0, 8)
StatsCorner.Parent = StatsFrame

local StatsStroke = Instance.new("UIStroke")
StatsStroke.Color = Color3.fromRGB(45, 50, 65)
StatsStroke.Thickness = 1
StatsStroke.Parent = StatsFrame

local CanOpenLabel = Instance.new("TextLabel")
CanOpenLabel.Size = UDim2.new(1, -20, 0, 22)
CanOpenLabel.Position = UDim2.new(0, 10, 0, 8)
CanOpenLabel.BackgroundTransparency = 1
CanOpenLabel.Text = "🎫 Can Open: 0 pulls"
CanOpenLabel.TextColor3 = Color3.fromRGB(46, 204, 113)
CanOpenLabel.Font = Enum.Font.GothamBold
CanOpenLabel.TextSize = 11
CanOpenLabel.TextXAlignment = Enum.TextXAlignment.Left
CanOpenLabel.Parent = StatsFrame

local SecretPityLabel = Instance.new("TextLabel")
SecretPityLabel.Size = UDim2.new(1, -20, 0, 22)
SecretPityLabel.Position = UDim2.new(0, 10, 0, 34)
SecretPityLabel.BackgroundTransparency = 1
SecretPityLabel.Text = "🔮 Until Secret Pity: N/A"
SecretPityLabel.TextColor3 = Color3.fromRGB(155, 89, 182)
SecretPityLabel.Font = Enum.Font.GothamMedium
SecretPityLabel.TextSize = 11
SecretPityLabel.TextXAlignment = Enum.TextXAlignment.Left
SecretPityLabel.Parent = StatsFrame

local MythicPityLabel = Instance.new("TextLabel")
MythicPityLabel.Size = UDim2.new(1, -20, 0, 22)
MythicPityLabel.Position = UDim2.new(0, 10, 0, 60)
MythicPityLabel.BackgroundTransparency = 1
MythicPityLabel.Text = "🌟 Until Mythic Pity: 0 pulls"
MythicPityLabel.TextColor3 = Color3.fromRGB(241, 196, 15)
MythicPityLabel.Font = Enum.Font.GothamMedium
MythicPityLabel.TextSize = 11
MythicPityLabel.TextXAlignment = Enum.TextXAlignment.Left
MythicPityLabel.Parent = StatsFrame

local StatusLabel = Instance.new("TextLabel")
StatusLabel.Size = UDim2.new(1, 0, 0, 20)
StatusLabel.Position = UDim2.new(0, 0, 0, 284)
StatusLabel.BackgroundTransparency = 1
StatusLabel.Text = "Status: Idle | Total: 0"
StatusLabel.TextColor3 = Color3.fromRGB(150, 155, 170)
StatusLabel.Font = Enum.Font.GothamMedium
StatusLabel.TextSize = 11
StatusLabel.Parent = ContentFrame

local CurrencyLabel = Instance.new("TextLabel")
CurrencyLabel.Size = UDim2.new(1, 0, 0, 20)
CurrencyLabel.Position = UDim2.new(0, 0, 0, 304)
CurrencyLabel.BackgroundTransparency = 1
CurrencyLabel.Text = "Balance: 0 Gem | Required: 500 Gem"
CurrencyLabel.TextColor3 = Color3.fromRGB(200, 205, 220)
CurrencyLabel.Font = Enum.Font.GothamMedium
CurrencyLabel.TextSize = 11
CurrencyLabel.Parent = ContentFrame

local function updateCurrencyState()
    local isEnough, totalCost, currentBalance, currencyName, costPerPull, maxAffordablePulls = checkCurrencyRequirement()
    CurrencyLabel.Text = string_format("Balance: %s %s | Cost (x%d): %s %s", tostring(currentBalance), currencyName, summonAmount, tostring(totalCost), currencyName)
    CanOpenLabel.Text = string_format("🎫 Can Open: %s pulls (%s)", tostring(maxAffordablePulls), currencyName)

    -- Accurate Real-Time Server Pull Counter
    local nowSummonCount = getBannerTotalSummonCount(selectedBanner)
    if initialBannerSummonCount == 0 then
        initialBannerSummonCount = nowSummonCount
    end
    currentSessionPulls = math_max(0, nowSummonCount - initialBannerSummonCount)

    local maxPity, currentPity = getPityData(selectedBanner)

    -- Secret Pity
    if maxPity.Secret then
        local curSecret = currentPity.Secret or 0
        local secretLeft = math_max(0, maxPity.Secret - curSecret)
        SecretPityLabel.Text = string_format("🔮 Until Secret Pity: %d pulls (%d/%d)", secretLeft, curSecret, maxPity.Secret)
    else
        SecretPityLabel.Text = "🔮 Until Secret Pity: N/A (No Secret Pity)"
    end

    -- Mythic Pity
    if maxPity.Mythic then
        local curMythic = currentPity.Mythic or 0
        local mythicLeft = math_max(0, maxPity.Mythic - curMythic)
        MythicPityLabel.Text = string_format("🌟 Until Mythic Pity: %d pulls (%d/%d)", mythicLeft, curMythic, maxPity.Mythic)
    else
        MythicPityLabel.Text = "🌟 Until Mythic Pity: N/A"
    end

    if not isEnough then
        if isAutoSummoning then
            isAutoSummoning = false
            StatusLabel.Text = string_format("⚠️ STOPPED: Out of %s (%s/%s) | Total: %d", currencyName, tostring(currentBalance), tostring(totalCost), currentSessionPulls)
            StatusLabel.TextColor3 = Color3.fromRGB(231, 76, 60)
        end
        ToggleBtn.BackgroundColor3 = Color3.fromRGB(80, 85, 95)
        ToggleBtn.Text = "⛔ NOT ENOUGH CURRENCY"
        ToggleBtn.AutoButtonColor = false
    else
        ToggleBtn.AutoButtonColor = true
        if not isAutoSummoning then
            ToggleBtn.BackgroundColor3 = Color3.fromRGB(46, 204, 113)
            ToggleBtn.Text = "▶ START AUTO SUMMON"
            StatusLabel.Text = string_format("Status: Idle | Total: %d", currentSessionPulls)
            StatusLabel.TextColor3 = Color3.fromRGB(150, 155, 170)
        else
            ToggleBtn.BackgroundColor3 = Color3.fromRGB(231, 76, 60)
            ToggleBtn.Text = "⏸ STOP AUTO SUMMON"
            StatusLabel.Text = string_format("Status: Silent Pulling (%s)... | Total: %d", selectedBanner, currentSessionPulls)
            StatusLabel.TextColor3 = Color3.fromRGB(46, 204, 113)
        end
    end
    return isEnough
end

local function renderBannerButtons()
    for _, child in pairs(BannerListFrame:GetChildren()) do
        if child:IsA("TextButton") then
            child:Destroy()
        end
    end
    updateBannerList()
    local totalHeight = 0
    for _, bName in ipairs(activeBanners) do
        local bBtn = Instance.new("TextButton")
        bBtn.Size = UDim2.new(1, -6, 0, 30)
        bBtn.BackgroundColor3 = (bName == selectedBanner) and Color3.fromRGB(65, 105, 225) or Color3.fromRGB(34, 38, 50)
        bBtn.Text = bName
        bBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
        bBtn.Font = Enum.Font.GothamMedium
        bBtn.TextSize = 12
        bBtn.ZIndex = 51
        bBtn.Parent = BannerListFrame
        
        local bCorner = Instance.new("UICorner")
        bCorner.CornerRadius = UDim.new(0, 4)
        bCorner.Parent = bBtn
        
        bBtn.MouseButton1Click:Connect(function()
            selectedBanner = bName
            BannerDropdown.Text = "Banner: " .. selectedBanner .. " ▼"
            BannerListFrame.Visible = false
            resetSessionCounter()
            renderBannerButtons()
            updateCurrencyState()
        end)
        totalHeight = totalHeight + 33
    end
    BannerListFrame.CanvasSize = UDim2.new(0, 0, 0, totalHeight)
end

renderBannerButtons()

BannerDropdown.MouseButton1Click:Connect(function()
    renderBannerButtons()
    BannerListFrame.Visible = not BannerListFrame.Visible
end)

local function updateAmountUI()
    BtnX1.BackgroundColor3 = (summonAmount == 1) and Color3.fromRGB(65, 105, 225) or Color3.fromRGB(40, 44, 58)
    BtnX1.TextColor3 = (summonAmount == 1) and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(180, 180, 200)
    BtnX1.Font = (summonAmount == 1) and Enum.Font.GothamBold or Enum.Font.GothamMedium

    BtnX10.BackgroundColor3 = (summonAmount == 10) and Color3.fromRGB(65, 105, 225) or Color3.fromRGB(40, 44, 58)
    BtnX10.TextColor3 = (summonAmount == 10) and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(180, 180, 200)
    BtnX10.Font = (summonAmount == 10) and Enum.Font.GothamBold or Enum.Font.GothamMedium

    BtnX50.BackgroundColor3 = (summonAmount == 50) and Color3.fromRGB(65, 105, 225) or Color3.fromRGB(40, 44, 58)
    BtnX50.TextColor3 = (summonAmount == 50) and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(180, 180, 200)
    BtnX50.Font = (summonAmount == 50) and Enum.Font.GothamBold or Enum.Font.GothamMedium

    updateCurrencyState()
end

BtnX1.MouseButton1Click:Connect(function() summonAmount = 1 updateAmountUI() end)
BtnX10.MouseButton1Click:Connect(function() summonAmount = 10 updateAmountUI() end)
BtnX50.MouseButton1Click:Connect(function() summonAmount = 50 updateAmountUI() end)

AnimToggleBtn.MouseButton1Click:Connect(function()
    skipAnimation = not skipAnimation
    if skipAnimation then
        AnimToggleBtn.BackgroundColor3 = Color3.fromRGB(46, 204, 113)
        AnimToggleBtn.Text = "⚡ Fast / Skip Animation: ON"
        pcall(function() Nodes.CHANGE_SETTING:FireServer("FastSummon", true) end)
    else
        AnimToggleBtn.BackgroundColor3 = Color3.fromRGB(80, 85, 95)
        AnimToggleBtn.Text = "🐢 Fast / Skip Animation: OFF"
        pcall(function() Nodes.CHANGE_SETTING:FireServer("FastSummon", false) end)
    end
end)

ToggleBtn.MouseButton1Click:Connect(function()
    local isEnough = updateCurrencyState()
    if not isEnough then
        return
    end

    isAutoSummoning = not isAutoSummoning
    if isAutoSummoning then
        if skipAnimation then
            pcall(function() Nodes.CHANGE_SETTING:FireServer("FastSummon", true) end)
        end
        ToggleBtn.BackgroundColor3 = Color3.fromRGB(231, 76, 60)
        ToggleBtn.Text = "⏸ STOP AUTO SUMMON"
        
        task_spawn(function()
            while isAutoSummoning do
                local hasMoney = checkCurrencyRequirement()
                if not hasMoney then
                    isAutoSummoning = false
                    updateCurrencyState()
                    break
                end

                Nodes.BANNER_SUMMON:FireServer(selectedBanner, summonAmount)
                updateCurrencyState()
                task_wait(skipAnimation and 0.12 or 0.5)
            end
        end)
    else
        ToggleBtn.BackgroundColor3 = Color3.fromRGB(46, 204, 113)
        ToggleBtn.Text = "▶ START AUTO SUMMON"
        updateCurrencyState()
    end
end)

pcall(function()
    Nodes.CLIENT_BANNER_REPLICA_LOADED:Connect(function()
        updateBannerList()
        updateCurrencyState()
    end)
end)

task_spawn(function()
    while ScreenGui.Parent do
        if isAutoSummoning then
            updateCurrencyState()
        end
        task_wait(0.5)
    end
end)

ScreenGui.Parent = PlayerGui
