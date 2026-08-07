local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
local Nodes = require(ReplicatedStorage:WaitForChild("Nodes"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Information = require(Shared:WaitForChild("Information"))

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

local requestFunc = http_request or request or (syn and syn.request) or httprequest or (function(options)
    return game:GetService("HttpService"):RequestAsync({
        Url = options.Url,
        Method = options.Method or "POST",
        Headers = options.Headers or {["Content-Type"] = "application/json"},
        Body = options.Body
    })
end)

if PlayerGui:FindFirstChild("AutoSummonGUI") then
    PlayerGui.AutoSummonGUI:Destroy()
end

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "AutoSummonGUI"
ScreenGui.ResetOnSpawn = false
ScreenGui.DisplayOrder = 9999
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

local themes = {
    ["Cyber Dark"] = {
        MainBg = Color3.fromRGB(18, 20, 26),
        TopBarBg = Color3.fromRGB(26, 29, 38),
        Accent = Color3.fromRGB(65, 105, 225),
        CardBg = Color3.fromRGB(24, 27, 36),
        Stroke = Color3.fromRGB(65, 105, 225),
        Text = Color3.fromRGB(255, 255, 255)
    },
    ["Neon Violet"] = {
        MainBg = Color3.fromRGB(22, 16, 32),
        TopBarBg = Color3.fromRGB(34, 24, 48),
        Accent = Color3.fromRGB(155, 89, 182),
        CardBg = Color3.fromRGB(30, 22, 42),
        Stroke = Color3.fromRGB(155, 89, 182),
        Text = Color3.fromRGB(245, 230, 255)
    },
    ["Gold Luxury"] = {
        MainBg = Color3.fromRGB(24, 22, 18),
        TopBarBg = Color3.fromRGB(38, 34, 26),
        Accent = Color3.fromRGB(241, 196, 15),
        CardBg = Color3.fromRGB(32, 28, 22),
        Stroke = Color3.fromRGB(241, 196, 15),
        Text = Color3.fromRGB(255, 248, 220)
    },
    ["Emerald Cyber"] = {
        MainBg = Color3.fromRGB(14, 24, 20),
        TopBarBg = Color3.fromRGB(20, 36, 30),
        Accent = Color3.fromRGB(46, 204, 113),
        CardBg = Color3.fromRGB(18, 30, 25),
        Stroke = Color3.fromRGB(46, 204, 113),
        Text = Color3.fromRGB(230, 255, 240)
    }
}

local currentThemeName = "Cyber Dark"
local currentTheme = themes[currentThemeName]

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
local webhookUrlInput = ""

local dropCounts = {
    Mythic = 0,
    ShinyMythic = 0,
    Secret = 0,
    ShinySecret = 0
}

pcall(function()
    Nodes.CHANGE_SETTING:FireServer("FastSummon", true)
end)

local addDropToLogUI
local sendDiscordWebhook

local function inspectRewardsAndLog(rewards)
    if type(rewards) ~= "table" then return end

    local itemList = rewards
    if rewards.Rewards and type(rewards.Rewards) == "table" then
        itemList = rewards.Rewards
    end

    for _, item in pairs(itemList) do
        if type(item) == "table" then
            local uName = item.Unit or item.Name or item.Asset or item.Id
            if uName then
                local uInfo = Information.Units and Information.Units[uName]
                local rarity = item.Rarity or (uInfo and uInfo.Rarity)
                local isShiny = item.Shiny or item.IsShiny or false

                if rarity == "Mythic" or rarity == "Secret" then
                    if rarity == "Mythic" then
                        if isShiny then
                            dropCounts.ShinyMythic = dropCounts.ShinyMythic + 1
                        else
                            dropCounts.Mythic = dropCounts.Mythic + 1
                        end
                    elseif rarity == "Secret" then
                        if isShiny then
                            dropCounts.ShinySecret = dropCounts.ShinySecret + 1
                        else
                            dropCounts.Secret = dropCounts.Secret + 1
                        end
                    end

                    if addDropToLogUI then
                        addDropToLogUI(uName, rarity, isShiny)
                    end
                    if sendDiscordWebhook then
                        sendDiscordWebhook(webhookUrlInput, uName, rarity, isShiny, selectedBanner)
                    end
                end
            end
        end
    end
end

-- Zero-Flicker Event Hooking with Drop Inspection
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
            nodeSignal.Signal.Fire = function(self, rewards, ...)
                if rewards then
                    task_spawn(function()
                        inspectRewardsAndLog(rewards)
                    end)
                end
                if skipAnimation or isAutoSummoning then
                    return nil
                end
                return realFire(self, rewards, ...)
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
local defaultMainSize = UDim2.new(0, 350, 0, 625)
local defaultMainPos = UDim2.new(0, 25, 0.5, -312)

local MainFrame = Instance.new("CanvasGroup")
MainFrame.Name = "MainFrame"
MainFrame.Size = defaultMainSize
MainFrame.Position = defaultMainPos
MainFrame.BackgroundColor3 = currentTheme.MainBg
MainFrame.BorderSizePixel = 0
MainFrame.ClipsDescendants = false
MainFrame.GroupTransparency = 0
MainFrame.Parent = ScreenGui

local UICorner = Instance.new("UICorner")
UICorner.CornerRadius = UDim.new(0, 12)
UICorner.Parent = MainFrame

local UIStroke = Instance.new("UIStroke")
UIStroke.Color = currentTheme.Stroke
UIStroke.Thickness = 1.5
UIStroke.Transparency = 0
UIStroke.Parent = MainFrame

-- Floating Toggle Button (OpenBtn)
local OpenBtn = Instance.new("TextButton")
OpenBtn.Name = "OpenToggleButton"
OpenBtn.Size = UDim2.new(0, 50, 0, 50)
OpenBtn.Position = defaultMainPos
OpenBtn.BackgroundColor3 = currentTheme.TopBarBg
OpenBtn.Text = "✨"
OpenBtn.TextSize = 24
OpenBtn.Visible = false
OpenBtn.Parent = ScreenGui

local OpenCorner = Instance.new("UICorner")
OpenCorner.CornerRadius = UDim.new(1, 0)
OpenCorner.Parent = OpenBtn

local OpenStroke = Instance.new("UIStroke")
OpenStroke.Color = currentTheme.Stroke
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
TopBar.BackgroundColor3 = currentTheme.TopBarBg
TopBar.BorderSizePixel = 0
TopBar.Parent = MainFrame

local TopBarCorner = Instance.new("UICorner")
TopBarCorner.CornerRadius = UDim.new(0, 12)
TopBarCorner.Parent = TopBar

local TitleLabel = Instance.new("TextLabel")
TitleLabel.Size = UDim2.new(1, -50, 1, 0)
TitleLabel.Position = UDim2.new(0, 15, 0, 0)
TitleLabel.BackgroundTransparency = 1
TitleLabel.Text = "✨ Auto Summoner Pro"
TitleLabel.TextColor3 = currentTheme.Text
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

-- Theme Switcher Row
local ThemeDropdown = Instance.new("TextButton")
ThemeDropdown.Size = UDim2.new(1, 0, 0, 26)
ThemeDropdown.Position = UDim2.new(0, 0, 0, 0)
ThemeDropdown.BackgroundColor3 = currentTheme.CardBg
ThemeDropdown.Text = "🎨 Theme: " .. currentThemeName .. " ▼"
ThemeDropdown.TextColor3 = currentTheme.Text
ThemeDropdown.Font = Enum.Font.GothamMedium
ThemeDropdown.TextSize = 11
ThemeDropdown.Parent = ContentFrame

local ThemeCorner = Instance.new("UICorner")
ThemeCorner.CornerRadius = UDim.new(0, 5)
ThemeCorner.Parent = ThemeDropdown

local ThemeStroke = Instance.new("UIStroke")
ThemeStroke.Color = currentTheme.Stroke
ThemeStroke.Thickness = 1
ThemeStroke.Parent = ThemeDropdown

local ThemeListFrame = Instance.new("Frame")
ThemeListFrame.Size = UDim2.new(1, 0, 0, 110)
ThemeListFrame.Position = UDim2.new(0, 0, 0, 28)
ThemeListFrame.BackgroundColor3 = currentTheme.CardBg
ThemeListFrame.BorderSizePixel = 0
ThemeListFrame.Visible = false
ThemeListFrame.ZIndex = 60
ThemeListFrame.Parent = ContentFrame

local ThemeListCorner = Instance.new("UICorner")
ThemeListCorner.CornerRadius = UDim.new(0, 6)
ThemeListCorner.Parent = ThemeListFrame

local ThemeListStroke = Instance.new("UIStroke")
ThemeListStroke.Color = currentTheme.Stroke
ThemeListStroke.Thickness = 1
ThemeListStroke.Parent = ThemeListFrame

local ThemeListLayout = Instance.new("UIListLayout")
ThemeListLayout.SortOrder = Enum.SortOrder.LayoutOrder
ThemeListLayout.Padding = UDim.new(0, 2)
ThemeListLayout.Parent = ThemeListFrame

local applyTheme

local function renderThemeButtons()
    for _, child in pairs(ThemeListFrame:GetChildren()) do
        if child:IsA("TextButton") then child:Destroy() end
    end
    for tName, _ in pairs(themes) do
        local tBtn = Instance.new("TextButton")
        tBtn.Size = UDim2.new(1, -6, 0, 24)
        tBtn.BackgroundColor3 = (tName == currentThemeName) and currentTheme.Accent or Color3.fromRGB(34, 38, 50)
        tBtn.Text = tName
        tBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
        tBtn.Font = Enum.Font.GothamMedium
        tBtn.TextSize = 11
        tBtn.ZIndex = 61
        tBtn.Parent = ThemeListFrame
        
        local bCorner = Instance.new("UICorner")
        bCorner.CornerRadius = UDim.new(0, 4)
        bCorner.Parent = tBtn
        
        tBtn.MouseButton1Click:Connect(function()
            currentThemeName = tName
            currentTheme = themes[tName]
            ThemeDropdown.Text = "🎨 Theme: " .. currentThemeName .. " ▼"
            ThemeListFrame.Visible = false
            renderThemeButtons()
            if applyTheme then applyTheme() end
        end)
    end
end
renderThemeButtons()

ThemeDropdown.MouseButton1Click:Connect(function()
    renderThemeButtons()
    ThemeListFrame.Visible = not ThemeListFrame.Visible
end)

-- Banner Dropdown
local BannerTitle = Instance.new("TextLabel")
BannerTitle.Size = UDim2.new(1, 0, 0, 16)
BannerTitle.Position = UDim2.new(0, 0, 0, 32)
BannerTitle.BackgroundTransparency = 1
BannerTitle.Text = "SELECT BANNER (AUTO-DETECTED):"
BannerTitle.TextColor3 = Color3.fromRGB(140, 145, 160)
BannerTitle.Font = Enum.Font.GothamBold
BannerTitle.TextSize = 10
BannerTitle.TextXAlignment = Enum.TextXAlignment.Left
BannerTitle.Parent = ContentFrame

local BannerDropdown = Instance.new("TextButton")
BannerDropdown.Size = UDim2.new(1, 0, 0, 32)
BannerDropdown.Position = UDim2.new(0, 0, 0, 50)
BannerDropdown.BackgroundColor3 = currentTheme.CardBg
BannerDropdown.Text = "Banner: " .. selectedBanner .. " ▼"
BannerDropdown.TextColor3 = currentTheme.Text
BannerDropdown.Font = Enum.Font.GothamMedium
BannerDropdown.TextSize = 12
BannerDropdown.Parent = ContentFrame

local DropCorner = Instance.new("UICorner")
DropCorner.CornerRadius = UDim.new(0, 6)
DropCorner.Parent = BannerDropdown

local DropStroke = Instance.new("UIStroke")
DropStroke.Color = currentTheme.Stroke
DropStroke.Thickness = 1
DropStroke.Parent = BannerDropdown

local BannerListFrame = Instance.new("ScrollingFrame")
BannerListFrame.Size = UDim2.new(1, 0, 0, 110)
BannerListFrame.Position = UDim2.new(0, 0, 0, 84)
BannerListFrame.BackgroundColor3 = currentTheme.CardBg
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
ListStroke.Color = currentTheme.Stroke
ListStroke.Thickness = 1
ListStroke.Parent = BannerListFrame

local UIListLayout = Instance.new("UIListLayout")
UIListLayout.SortOrder = Enum.SortOrder.LayoutOrder
UIListLayout.Padding = UDim.new(0, 3)
UIListLayout.Parent = BannerListFrame

local AmountFrame = Instance.new("Frame")
AmountFrame.Size = UDim2.new(1, 0, 0, 32)
AmountFrame.Position = UDim2.new(0, 0, 0, 86)
AmountFrame.BackgroundColor3 = currentTheme.TopBarBg
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
BtnX10.BackgroundColor3 = currentTheme.Accent
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
AnimToggleBtn.Size = UDim2.new(1, 0, 0, 30)
AnimToggleBtn.Position = UDim2.new(0, 0, 0, 122)
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
ToggleBtn.Size = UDim2.new(1, 0, 0, 42)
ToggleBtn.Position = UDim2.new(0, 0, 0, 156)
ToggleBtn.BackgroundColor3 = Color3.fromRGB(46, 204, 113)
ToggleBtn.Text = "▶ START AUTO SUMMON"
ToggleBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
ToggleBtn.Font = Enum.Font.GothamBold
ToggleBtn.TextSize = 13
ToggleBtn.Parent = ContentFrame

local ToggleCorner = Instance.new("UICorner")
ToggleCorner.CornerRadius = UDim.new(0, 8)
ToggleCorner.Parent = ToggleBtn

-- Pity Container Frame
local StatsFrame = Instance.new("Frame")
StatsFrame.Size = UDim2.new(1, 0, 0, 88)
StatsFrame.Position = UDim2.new(0, 0, 0, 204)
StatsFrame.BackgroundColor3 = currentTheme.CardBg
StatsFrame.BorderSizePixel = 0
StatsFrame.Parent = ContentFrame

local StatsCorner = Instance.new("UICorner")
StatsCorner.CornerRadius = UDim.new(0, 8)
StatsCorner.Parent = StatsFrame

local StatsStroke = Instance.new("UIStroke")
StatsStroke.Color = currentTheme.Stroke
StatsStroke.Thickness = 1
StatsStroke.Parent = StatsFrame

local CanOpenLabel = Instance.new("TextLabel")
CanOpenLabel.Size = UDim2.new(1, -20, 0, 20)
CanOpenLabel.Position = UDim2.new(0, 10, 0, 8)
CanOpenLabel.BackgroundTransparency = 1
CanOpenLabel.Text = "🎫 Can Open: 0 pulls"
CanOpenLabel.TextColor3 = Color3.fromRGB(46, 204, 113)
CanOpenLabel.Font = Enum.Font.GothamBold
CanOpenLabel.TextSize = 11
CanOpenLabel.TextXAlignment = Enum.TextXAlignment.Left
CanOpenLabel.Parent = StatsFrame

local SecretPityLabel = Instance.new("TextLabel")
SecretPityLabel.Size = UDim2.new(1, -20, 0, 20)
SecretPityLabel.Position = UDim2.new(0, 10, 0, 32)
SecretPityLabel.BackgroundTransparency = 1
SecretPityLabel.Text = "🔮 Until Secret Pity: N/A"
SecretPityLabel.TextColor3 = Color3.fromRGB(155, 89, 182)
SecretPityLabel.Font = Enum.Font.GothamMedium
SecretPityLabel.TextSize = 11
SecretPityLabel.TextXAlignment = Enum.TextXAlignment.Left
SecretPityLabel.Parent = StatsFrame

local MythicPityLabel = Instance.new("TextLabel")
MythicPityLabel.Size = UDim2.new(1, -20, 0, 20)
MythicPityLabel.Position = UDim2.new(0, 10, 0, 56)
MythicPityLabel.BackgroundTransparency = 1
MythicPityLabel.Text = "🌟 Until Mythic Pity: 0 pulls"
MythicPityLabel.TextColor3 = Color3.fromRGB(241, 196, 15)
MythicPityLabel.Font = Enum.Font.GothamMedium
MythicPityLabel.TextSize = 11
MythicPityLabel.TextXAlignment = Enum.TextXAlignment.Left
MythicPityLabel.Parent = StatsFrame

-- Instant Teleports Bar
local TeleportTitle = Instance.new("TextLabel")
TeleportTitle.Size = UDim2.new(1, 0, 0, 14)
TeleportTitle.Position = UDim2.new(0, 0, 0, 298)
TeleportTitle.BackgroundTransparency = 1
TeleportTitle.Text = "📌 INSTANT TELEPORTS:"
TeleportTitle.TextColor3 = Color3.fromRGB(140, 145, 160)
TeleportTitle.Font = Enum.Font.GothamBold
TeleportTitle.TextSize = 10
TeleportTitle.TextXAlignment = Enum.TextXAlignment.Left
TeleportTitle.Parent = ContentFrame

local TeleportRow = Instance.new("Frame")
TeleportRow.Size = UDim2.new(1, 0, 0, 30)
TeleportRow.Position = UDim2.new(0, 0, 0, 314)
TeleportRow.BackgroundTransparency = 1
TeleportRow.Parent = ContentFrame

local function createTpBtn(text, posScale, areaName)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(0.24, -2, 1, 0)
    btn.Position = UDim2.new(posScale, 0, 0, 0)
    btn.BackgroundColor3 = currentTheme.CardBg
    btn.Text = text
    btn.TextColor3 = currentTheme.Text
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 10
    btn.Parent = TeleportRow

    local bCorner = Instance.new("UICorner")
    bCorner.CornerRadius = UDim.new(0, 6)
    bCorner.Parent = btn

    local bStroke = Instance.new("UIStroke")
    bStroke.Color = currentTheme.Stroke
    bStroke.Thickness = 1
    bStroke.Parent = btn

    btn.MouseButton1Click:Connect(function()
        pcall(function()
            Nodes.TELEPORT_TO_AREA:FireServer(areaName)
        end)
    end)
    return btn
end

local TpSummon = createTpBtn("🔮 Summon", 0, "Summon")
local TpAFK = createTpBtn("💤 AFK", 0.25, "AFKChamber")
local TpSpawn = createTpBtn("🏠 Spawn", 0.50, "Spawn")
local TpCraft = createTpBtn("🛠️ Craft", 0.75, "Crafting")

-- Webhook Input & Test Frame
local WebhookFrame = Instance.new("Frame")
WebhookFrame.Size = UDim2.new(1, 0, 0, 30)
WebhookFrame.Position = UDim2.new(0, 0, 0, 350)
WebhookFrame.BackgroundColor3 = currentTheme.CardBg
WebhookFrame.BorderSizePixel = 0
WebhookFrame.Parent = ContentFrame

local WebhookCorner = Instance.new("UICorner")
WebhookCorner.CornerRadius = UDim.new(0, 6)
WebhookCorner.Parent = WebhookFrame

local WebhookBox = Instance.new("TextBox")
WebhookBox.Size = UDim2.new(1, -70, 1, 0)
WebhookBox.Position = UDim2.new(0, 10, 0, 0)
WebhookBox.BackgroundTransparency = 1
WebhookBox.PlaceholderText = "Paste Discord Webhook URL..."
WebhookBox.PlaceholderColor3 = Color3.fromRGB(120, 125, 140)
WebhookBox.Text = ""
WebhookBox.TextColor3 = currentTheme.Text
WebhookBox.Font = Enum.Font.Gotham
WebhookBox.TextSize = 10
WebhookBox.ClearTextOnFocus = false
WebhookBox.TextXAlignment = Enum.TextXAlignment.Left
WebhookBox.Parent = WebhookFrame

WebhookBox.FocusLost:Connect(function()
    webhookUrlInput = WebhookBox.Text
end)

local TestWebhookBtn = Instance.new("TextButton")
TestWebhookBtn.Size = UDim2.new(0, 55, 1, -6)
TestWebhookBtn.Position = UDim2.new(1, -60, 0, 3)
TestWebhookBtn.BackgroundColor3 = currentTheme.Accent
TestWebhookBtn.Text = "TEST"
TestWebhookBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
TestWebhookBtn.Font = Enum.Font.GothamBold
TestWebhookBtn.TextSize = 10
TestWebhookBtn.Parent = WebhookFrame

local TestCorner = Instance.new("UICorner")
TestCorner.CornerRadius = UDim.new(0, 4)
TestCorner.Parent = TestWebhookBtn

-- High Tier Drops Log Container
local LogTitle = Instance.new("TextLabel")
LogTitle.Size = UDim2.new(1, 0, 0, 14)
LogTitle.Position = UDim2.new(0, 0, 0, 386)
LogTitle.BackgroundTransparency = 1
LogTitle.Text = "🏆 HIGH-TIER DROPS LOG (0 M | 0 ✨M | 0 S | 0 ✨S):"
LogTitle.TextColor3 = Color3.fromRGB(140, 145, 160)
LogTitle.Font = Enum.Font.GothamBold
LogTitle.TextSize = 10
LogTitle.TextXAlignment = Enum.TextXAlignment.Left
LogTitle.Parent = ContentFrame

local DropLogFrame = Instance.new("ScrollingFrame")
DropLogFrame.Size = UDim2.new(1, 0, 0, 75)
DropLogFrame.Position = UDim2.new(0, 0, 0, 402)
DropLogFrame.BackgroundColor3 = currentTheme.CardBg
DropLogFrame.BorderSizePixel = 0
DropLogFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
DropLogFrame.ScrollBarThickness = 4
DropLogFrame.Parent = ContentFrame

local LogCorner = Instance.new("UICorner")
LogCorner.CornerRadius = UDim.new(0, 6)
LogCorner.Parent = DropLogFrame

local LogLayout = Instance.new("UIListLayout")
LogLayout.SortOrder = Enum.SortOrder.LayoutOrder
LogLayout.Padding = UDim.new(0, 2)
LogLayout.Parent = DropLogFrame

local totalLogEntries = 0

addDropToLogUI = function(unitName, rarity, isShiny)
    totalLogEntries = totalLogEntries + 1
    LogTitle.Text = string_format("🏆 HIGH-TIER DROPS LOG (%d M | %d ✨M | %d S | %d ✨S):", dropCounts.Mythic, dropCounts.ShinyMythic, dropCounts.Secret, dropCounts.ShinySecret)
    
    local entryLabel = Instance.new("TextLabel")
    entryLabel.Size = UDim2.new(1, -10, 0, 20)
    entryLabel.BackgroundTransparency = 1
    entryLabel.Font = Enum.Font.GothamBold
    entryLabel.TextSize = 11
    entryLabel.TextXAlignment = Enum.TextXAlignment.Left
    
    local timeStr = os.date("%X")
    local shinyPrefix = isShiny and "✨ " or ""
    local rarityTag = isShiny and ("Shiny " .. rarity) or rarity
    entryLabel.Text = string_format(" [%s] %s[%s] %s", timeStr, shinyPrefix, rarityTag, tostring(unitName))

    if rarity == "Secret" then
        entryLabel.TextColor3 = isShiny and Color3.fromRGB(255, 0, 255) or Color3.fromRGB(180, 100, 255)
    else
        entryLabel.TextColor3 = isShiny and Color3.fromRGB(0, 240, 255) or Color3.fromRGB(241, 196, 15)
    end
    
    entryLabel.Parent = DropLogFrame
    DropLogFrame.CanvasSize = UDim2.new(0, 0, 0, totalLogEntries * 22)
    DropLogFrame.CanvasPosition = Vector2.new(0, totalLogEntries * 22)
end

sendDiscordWebhook = function(webhookUrl, unitName, rarity, isShiny, bannerName)
    if not webhookUrl or webhookUrl == "" or not webhookUrl:find("http") then
        return
    end

    local titleEmoji = isShiny and "✨🌟" or (rarity == "Secret" and "🔮" or "🌟")
    local fullCategory = (isShiny and "Shiny " or "") .. rarity
    
    local embedColor = 15844367
    if rarity == "Secret" then
        embedColor = isShiny and 16711935 or 10181046
    elseif isShiny then
        embedColor = 65535
    end

    local payload = {
        username = "Auto Summoner Bot",
        embeds = {
            {
                title = titleEmoji .. " NEW HIGH-TIER DROP!",
                color = embedColor,
                fields = {
                    { name = "Unit", value = "**" .. tostring(unitName) .. "**", inline = true },
                    { name = "Rarity", value = "**" .. fullCategory .. "**", inline = true },
                    { name = "Banner", value = tostring(bannerName), inline = true },
                    { name = "Player", value = LocalPlayer.Name, inline = true },
                    { name = "Total Pulls", value = tostring(currentSessionPulls), inline = true }
                },
                footer = {
                    text = "Auto Summoner Pro • " .. os.date("%X")
                }
            }
        }
    }

    pcall(function()
        requestFunc({
            Url = webhookUrl,
            Method = "POST",
            Headers = {["Content-Type"] = "application/json"},
            Body = game:GetService("HttpService"):JSONEncode(payload)
        })
    end)
end

TestWebhookBtn.MouseButton1Click:Connect(function()
    webhookUrlInput = WebhookBox.Text
    if webhookUrlInput == "" or not webhookUrlInput:find("http") then
        TestWebhookBtn.Text = "INVALID"
        TestWebhookBtn.BackgroundColor3 = Color3.fromRGB(231, 76, 60)
        task_wait(1.5)
        TestWebhookBtn.Text = "TEST"
        TestWebhookBtn.BackgroundColor3 = currentTheme.Accent
        return
    end

    sendDiscordWebhook(webhookUrlInput, "Flame Emperor", "Mythic", true, selectedBanner)
    TestWebhookBtn.Text = "SENT!"
    TestWebhookBtn.BackgroundColor3 = Color3.fromRGB(46, 204, 113)
    task_wait(1.5)
    TestWebhookBtn.Text = "TEST"
    TestWebhookBtn.BackgroundColor3 = currentTheme.Accent
end)

-- Dota 2 Launcher Button
local DotaBtn = Instance.new("TextButton")
DotaBtn.Size = UDim2.new(1, 0, 0, 32)
DotaBtn.Position = UDim2.new(0, 0, 0, 482)
DotaBtn.BackgroundColor3 = Color3.fromRGB(180, 40, 40)
DotaBtn.Text = "🎮 QUIT ROBLOX & LAUNCH DOTA 2"
DotaBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
DotaBtn.Font = Enum.Font.GothamBold
DotaBtn.TextSize = 11
DotaBtn.Parent = ContentFrame

local DotaCorner = Instance.new("UICorner")
DotaCorner.CornerRadius = UDim.new(0, 6)
DotaCorner.Parent = DotaBtn

DotaBtn.MouseButton1Click:Connect(function()
    pcall(function()
        if setclipboard then
            setclipboard("steam://run/570")
        end
    end)
    task_spawn(function()
        task_wait(0.2)
        game:Shutdown()
    end)
end)

applyTheme = function()
    MainFrame.BackgroundColor3 = currentTheme.MainBg
    TopBar.BackgroundColor3 = currentTheme.TopBarBg
    TitleLabel.TextColor3 = currentTheme.Text
    UIStroke.Color = currentTheme.Stroke
    OpenBtn.BackgroundColor3 = currentTheme.TopBarBg
    OpenStroke.Color = currentTheme.Stroke
    
    ThemeDropdown.BackgroundColor3 = currentTheme.CardBg
    ThemeDropdown.TextColor3 = currentTheme.Text
    ThemeStroke.Color = currentTheme.Stroke
    ThemeListFrame.BackgroundColor3 = currentTheme.CardBg
    ThemeListStroke.Color = currentTheme.Stroke

    BannerDropdown.BackgroundColor3 = currentTheme.CardBg
    BannerDropdown.TextColor3 = currentTheme.Text
    DropStroke.Color = currentTheme.Stroke
    BannerListFrame.BackgroundColor3 = currentTheme.CardBg
    ListStroke.Color = currentTheme.Stroke

    AmountFrame.BackgroundColor3 = currentTheme.TopBarBg
    if summonAmount == 10 then BtnX10.BackgroundColor3 = currentTheme.Accent end
    if summonAmount == 1 then BtnX1.BackgroundColor3 = currentTheme.Accent end
    if summonAmount == 50 then BtnX50.BackgroundColor3 = currentTheme.Accent end

    StatsFrame.BackgroundColor3 = currentTheme.CardBg
    StatsStroke.Color = currentTheme.Stroke

    WebhookFrame.BackgroundColor3 = currentTheme.CardBg
    WebhookBox.TextColor3 = currentTheme.Text
    TestWebhookBtn.BackgroundColor3 = currentTheme.Accent

    DropLogFrame.BackgroundColor3 = currentTheme.CardBg

    for _, btn in ipairs({TpSummon, TpAFK, TpSpawn, TpCraft}) do
        btn.BackgroundColor3 = currentTheme.CardBg
        btn.TextColor3 = currentTheme.Text
        if btn:FindFirstChildOfClass("UIStroke") then
            btn:FindFirstChildOfClass("UIStroke").Color = currentTheme.Stroke
        end
    end
end

local StatusLabel = Instance.new("TextLabel")
StatusLabel.Size = UDim2.new(1, 0, 0, 16)
StatusLabel.Position = UDim2.new(0, 0, 0, 520)
StatusLabel.BackgroundTransparency = 1
StatusLabel.Text = "Status: Idle | Total: 0"
StatusLabel.TextColor3 = Color3.fromRGB(150, 155, 170)
StatusLabel.Font = Enum.Font.GothamMedium
StatusLabel.TextSize = 10
StatusLabel.Parent = ContentFrame

local CurrencyLabel = Instance.new("TextLabel")
CurrencyLabel.Size = UDim2.new(1, 0, 0, 16)
CurrencyLabel.Position = UDim2.new(0, 0, 0, 536)
CurrencyLabel.BackgroundTransparency = 1
CurrencyLabel.Text = "Balance: 0 Gem | Required: 500 Gem"
CurrencyLabel.TextColor3 = Color3.fromRGB(200, 205, 220)
CurrencyLabel.Font = Enum.Font.GothamMedium
CurrencyLabel.TextSize = 10
CurrencyLabel.Parent = ContentFrame

local function updateCurrencyState()
    local isEnough, totalCost, currentBalance, currencyName, costPerPull, maxAffordablePulls = checkCurrencyRequirement()
    CurrencyLabel.Text = string_format("Balance: %s %s | Cost (x%d): %s %s", tostring(currentBalance), currencyName, summonAmount, tostring(totalCost), currencyName)
    CanOpenLabel.Text = string_format("🎫 Can Open: %s pulls (%s)", tostring(maxAffordablePulls), currencyName)

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
        bBtn.BackgroundColor3 = (bName == selectedBanner) and currentTheme.Accent or Color3.fromRGB(34, 38, 50)
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
    BtnX1.BackgroundColor3 = (summonAmount == 1) and currentTheme.Accent or Color3.fromRGB(40, 44, 58)
    BtnX1.TextColor3 = (summonAmount == 1) and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(180, 180, 200)
    BtnX1.Font = (summonAmount == 1) and Enum.Font.GothamBold or Enum.Font.GothamMedium

    BtnX10.BackgroundColor3 = (summonAmount == 10) and currentTheme.Accent or Color3.fromRGB(40, 44, 58)
    BtnX10.TextColor3 = (summonAmount == 10) and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(180, 180, 200)
    BtnX10.Font = (summonAmount == 10) and Enum.Font.GothamBold or Enum.Font.GothamMedium

    BtnX50.BackgroundColor3 = (summonAmount == 50) and currentTheme.Accent or Color3.fromRGB(40, 44, 58)
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
