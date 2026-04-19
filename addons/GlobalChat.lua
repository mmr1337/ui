--[[
    GlobalChat Addon for gamesense-style Library
    Firebase-based global chat window integrated into the UI library.
    
    Usage:
        local GlobalChat = loadstring(game:HttpGet(repo .. "addons/GlobalChat.lua"))()
        GlobalChat:SetLibrary(Library)
        -- In your settings tab:
        GlobalChat:ApplyToTab(tab)
]]

local Players      = game:GetService("Players")
local HttpService  = game:GetService("HttpService")
local RunService   = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local GlobalChat = {}
GlobalChat.__index = GlobalChat

-- ─── Configuration ────────────────────────────────────────────────────────────
GlobalChat.FirebaseUrl       = "https://apirobloxuser-default-rtdb.firebaseio.com"
GlobalChat.MessagesPath      = "/globalchat/messages"
GlobalChat.PMPath            = "/globalchat/pm"
GlobalChat.MaxMessages       = 50
GlobalChat.UpdateInterval    = 3
GlobalChat.BubbleDisplayTime = 10
-- ──────────────────────────────────────────────────────────────────────────────

-- State
GlobalChat.Library        = nil
GlobalChat.ScreenGui      = nil
GlobalChat.ChatWindow     = nil
GlobalChat.Enabled        = false
GlobalChat.ScrollFrame    = nil
GlobalChat.TextBox        = nil
GlobalChat.SendButton     = nil

-- Settings State (defaults: hidden)
GlobalChat.Settings = {
    ShowUsername   = false,
    ShowAvatar    = false,
    ShowPlaceIcon = false,
    AllowPM       = false,
    AllowConnect  = false,
}

-- Settings Panel State
GlobalChat.SettingsOpen    = false
GlobalChat.SettingsFrame   = nil
GlobalChat.SettingsOverlay = nil
GlobalChat.SettingsItems   = {}

local request = (syn and syn.request)
    or (http and http.request)
    or http_request
    or (Fluxus and Fluxus.request)
    or request

local thumbnailCache   = {}
local placeIconCache   = {}
local messageHistory   = {}
local displayedBubbles = {}
local lastFetchTime    = 0
local pollingStarted   = false

-- ─── Constants ────────────────────────────────────────────────────────────────
local HIDDEN_NAME        = "Secret User"
local HIDDEN_AVATAR      = "rbxassetid://5107154082"
local DEFAULT_AVATAR     = "rbxassetid://5107154082"

-- ─── Helpers ──────────────────────────────────────────────────────────────────

local function GetThumbnail(userId)
    if thumbnailCache[userId] then
        return thumbnailCache[userId]
    end
    local ok, result = pcall(function()
        return Players:GetUserThumbnailAsync(
            userId,
            Enum.ThumbnailType.HeadShot,
            Enum.ThumbnailSize.Size150x150
        )
    end)
    local url = ok and result or DEFAULT_AVATAR
    thumbnailCache[userId] = url
    return url
end

local function GetPlaceIcon(placeId)
    if placeIconCache[placeId] then
        return placeIconCache[placeId]
    end
    local ok, url = pcall(function()
        local resp = request({
            Url    = "https://thumbnails.roblox.com/v1/games/icons?universeIds="
                     .. tostring(game.GameId) .. "&size=150x150&format=Png&isCircular=false",
            Method = "GET",
        })
        if resp and resp.Success and resp.Body then
            local data = HttpService:JSONDecode(resp.Body)
            if data and data.data and data.data[1] then
                return data.data[1].imageUrl
            end
        end
        return nil
    end)
    local icon = (ok and url) or DEFAULT_AVATAR
    placeIconCache[placeId] = icon
    return icon
end

local function New(ClassName, Properties)
    local Inst = Instance.new(ClassName)
    for k, v in pairs(Properties) do
        if k ~= "Parent" then
            Inst[k] = v
        end
    end
    if Properties.Parent then
        Inst.Parent = Properties.Parent
    end
    return Inst
end

-- ─── Icon Helpers ─────────────────────────────────────────────────────────────

local ICON_SETTINGS = "rbxassetid://7733960981"
local ICON_BACK     = "rbxassetid://7733658504"
local ICON_CHECK    = "rbxassetid://7733715400"

local function GetIcon(name)
    local L = GlobalChat.Library
    if L and L.Icons and L.Icons[name] then
        return L.Icons[name]
    end
    local map = {
        ["settings"]    = ICON_SETTINGS,
        ["arrow-left"]  = ICON_BACK,
        ["check"]       = ICON_CHECK,
    }
    return map[name] or ""
end

-- ─── 3D Chat Bubble ───────────────────────────────────────────────────────────

local function Create3DBubble(player, message, timestamp)
    if not player or not player.Character then return end
    if not player.Character:FindFirstChild("Head") then return end

    local key = player.UserId .. "_" .. timestamp
    if displayedBubbles[key] then return end

    local now = os.time()
    local age = now - timestamp
    if age >= GlobalChat.BubbleDisplayTime then return end
    displayedBubbles[key] = true

    local head = player.Character.Head
    local old  = head:FindFirstChild("GlobalChatBubble")
    if old then old:Destroy() end

    local L = GlobalChat.Library

    local Board = New("BillboardGui", {
        Name        = "GlobalChatBubble",
        Size        = UDim2.fromOffset(240, 50),
        StudsOffset = Vector3.new(0, 3, 0),
        AlwaysOnTop = true,
        Parent      = head,
    })

    local Bg = New("Frame", {
        Size             = UDim2.fromScale(1, 1),
        BackgroundColor3 = Color3.fromRGB(12, 12, 12),
        BorderSizePixel  = 0,
        Parent           = Board,
    })

    New("Frame", {
        BackgroundColor3 = L and L.Scheme.AccentColor or Color3.fromRGB(100, 200, 100),
        Size             = UDim2.new(0, 2, 1, 0),
        BorderSizePixel  = 0,
        Parent           = Bg,
    })

    New("UIStroke", {
        Color           = Color3.fromRGB(45, 45, 45),
        Thickness       = 1,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
        Parent          = Bg,
    })

    New("TextLabel", {
        Size             = UDim2.new(1, -10, 1, -6),
        Position         = UDim2.fromOffset(8, 3),
        BackgroundTransparency = 1,
        Text             = message,
        TextColor3       = Color3.fromRGB(200, 200, 200),
        TextSize         = 13,
        Font             = Enum.Font.Code,
        TextWrapped      = true,
        TextXAlignment   = Enum.TextXAlignment.Left,
        Parent           = Bg,
    })

    local remain = GlobalChat.BubbleDisplayTime - age
    task.delay(remain, function()
        if Board and Board.Parent then
            Board:Destroy()
        end
        displayedBubbles[key] = nil
    end)
end

-- ─── Message Row ─────────────────────────────────────────────────────────────

function GlobalChat:AddMessage(data)
    local key = tostring(data.timestamp) .. tostring(data.userId)
    if messageHistory[key] then return end
    messageHistory[key] = true

    local SF = self.ScrollFrame
    local L  = self.Library
    if not (SF and L) then return end

    local showAvatar   = self.Settings.ShowAvatar
    local showUsername = self.Settings.ShowUsername
    local showPlace    = self.Settings.ShowPlaceIcon

    local leftOffset = showAvatar and 54 or 10
    local rowHeight  = showAvatar and 48 or 36

    local Row = New("Frame", {
        BackgroundColor3 = L.Scheme.MainColor,
        BorderSizePixel  = 0,
        Size             = UDim2.new(1, 0, 0, rowHeight),
        LayoutOrder      = data.timestamp,
        ClipsDescendants = true,
        Parent           = SF,
    })

    -- Accent left border
    New("Frame", {
        BackgroundColor3 = L.Scheme.AccentColor,
        Size             = UDim2.new(0, 2, 1, 0),
        BorderSizePixel  = 0,
        Parent           = Row,
    })

    -- Bottom divider
    New("Frame", {
        BackgroundColor3 = L.Scheme.OutlineColor,
        AnchorPoint      = Vector2.new(0, 1),
        Position         = UDim2.fromScale(0, 1),
        Size             = UDim2.new(1, 0, 0, 1),
        BorderSizePixel  = 0,
        Parent           = Row,
    })

    -- Avatar (conditional)
    if showAvatar then
        local avatarUrl = showUsername and GetThumbnail(data.userId) or HIDDEN_AVATAR
        
        local Av = New("ImageLabel", {
            BackgroundColor3 = L.Scheme.BackgroundColor,
            Position         = UDim2.fromOffset(8, 4),
            Size             = UDim2.fromOffset(40, 40),
            Image            = avatarUrl,
            BorderSizePixel  = 0,
            Parent           = Row,
        })

        New("UIStroke", {
            Color           = L.Scheme.OutlineColor,
            Thickness       = 1,
            ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
            Parent          = Av,
        })

        New("UICorner", {
            CornerRadius = UDim.new(0, 4),
            Parent       = Av,
        })
    end

    -- Place icon (small, next to name)
    local nameOffset = leftOffset
    if showPlace and data.gameId then
        local PlaceIcon = New("ImageLabel", {
            BackgroundTransparency = 1,
            Position = UDim2.fromOffset(leftOffset, showAvatar and 6 or 4),
            Size     = UDim2.fromOffset(14, 14),
            Image    = GetPlaceIcon(data.gameId),
            Parent   = Row,
        })
        New("UICorner", {
            CornerRadius = UDim.new(0, 2),
            Parent       = PlaceIcon,
        })
        nameOffset = nameOffset + 18
    end

    -- Name label
    local displayName
    if showUsername then
        displayName = data.displayName .. " (@" .. data.username .. ")"
    else
        displayName = HIDDEN_NAME
    end

    local nameY = showAvatar and 5 or 2
    local msgY  = showAvatar and 22 or 16

    New("TextLabel", {
        BackgroundTransparency = 1,
        Position         = UDim2.fromOffset(nameOffset, nameY),
        Size             = UDim2.new(1, -(nameOffset + 4), 0, 16),
        Text             = displayName,
        TextColor3       = L.Scheme.AccentColor,
        TextSize         = 12,
        Font             = Enum.Font.Code,
        TextXAlignment   = Enum.TextXAlignment.Left,
        TextTruncate     = Enum.TextTruncate.AtEnd,
        Parent           = Row,
    })

    -- Message text
    New("TextLabel", {
        BackgroundTransparency = 1,
        Position         = UDim2.fromOffset(leftOffset, msgY),
        Size             = UDim2.new(1, -(leftOffset + 4), 0, showAvatar and 22 or 16),
        Text             = data.message,
        TextColor3       = Color3.fromRGB(200, 200, 200),
        TextSize         = 13,
        Font             = Enum.Font.Code,
        TextXAlignment   = Enum.TextXAlignment.Left,
        TextWrapped      = true,
        ClipsDescendants = true,
        Parent           = Row,
    })

    -- Trim old rows
    local rows = {}
    for _, c in ipairs(SF:GetChildren()) do
        if c:IsA("Frame") then
            table.insert(rows, c)
        end
    end
    if #rows > GlobalChat.MaxMessages then
        table.sort(rows, function(a, b)
            return a.LayoutOrder < b.LayoutOrder
        end)
        rows[1]:Destroy()
    end
end

-- ─── Rebuild Messages ───────────────────────────────────────────────────────

function GlobalChat:ClearAndRefetch()
    if self.ScrollFrame then
        for _, c in ipairs(self.ScrollFrame:GetChildren()) do
            if c:IsA("Frame") then
                c:Destroy()
            end
        end
    end
    messageHistory = {}
    self:FetchAndUpdate()
end

-- ─── Firebase ────────────────────────────────────────────────────────────────

function GlobalChat:SendMessage(message)
    if not request then return end
    local LP = Players.LocalPlayer
    
    -- Always send real data to Firebase — display is controlled locally
    local data = {
        userId      = LP.UserId,
        username    = LP.Name,
        displayName = LP.DisplayName,
        message     = message,
        timestamp   = os.time(),
        gameId      = game.PlaceId,
        allowPM     = self.Settings.AllowPM,
        allowConnect = self.Settings.AllowConnect,
    }
    task.spawn(function()
        local ok = pcall(function()
            request({
                Url     = GlobalChat.FirebaseUrl .. GlobalChat.MessagesPath .. ".json",
                Method  = "POST",
                Headers = { ["Content-Type"] = "application/json" },
                Body    = HttpService:JSONEncode(data),
            })
        end)
        if ok then
            Create3DBubble(LP, message, data.timestamp)
        end
    end)
end

function GlobalChat:FetchAndUpdate()
    if not request then return end
    local ok, result = pcall(function()
        local resp = request({
            Url    = GlobalChat.FirebaseUrl .. GlobalChat.MessagesPath
                     .. ".json?orderBy=\"$key\"&limitToLast=" .. GlobalChat.MaxMessages
                     .. "&nocache=" .. math.random(1, 999999),
            Method = "GET",
        })
        if resp.Success and resp.Body and resp.Body ~= "null" then
            return HttpService:JSONDecode(resp.Body)
        end
    end)
    if not (ok and result) then return end

    local sorted = {}
    for _, msg in pairs(result) do
        table.insert(sorted, msg)
    end
    table.sort(sorted, function(a, b)
        return a.timestamp < b.timestamp
    end)

    local now = os.time()
    for _, msg in ipairs(sorted) do
        self:AddMessage(msg)
        if now - msg.timestamp < GlobalChat.BubbleDisplayTime then
            local pl = Players:GetPlayerByUserId(msg.userId)
            if pl and pl.Character then
                Create3DBubble(pl, msg.message, msg.timestamp)
            end
        end
    end
end

-- ─── Settings Panel ──────────────────────────────────────────────────────────

function GlobalChat:CreateSettingsToggle(parent, yPos, text, settingKey, callback)
    local L = self.Library

    local Container = New("CanvasGroup", {
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 0, 0, yPos),
        Size     = UDim2.new(1, 0, 0, 30),
        Parent   = parent,
        GroupTransparency = 1,
        Visible  = false,
    })

    -- Toggle background
    local ToggleBg = New("Frame", {
        BackgroundColor3 = self.Settings[settingKey]
            and L.Scheme.AccentColor
            or Color3.fromRGB(40, 40, 40),
        Position        = UDim2.new(1, -42, 0.5, -8),
        Size            = UDim2.fromOffset(36, 16),
        BorderSizePixel = 0,
        Parent          = Container,
    })

    New("UICorner", {
        CornerRadius = UDim.new(0, 8),
        Parent       = ToggleBg,
    })

    New("UIStroke", {
        Color           = L.Scheme.OutlineColor,
        Thickness       = 1,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
        Parent          = ToggleBg,
    })

    -- Toggle knob
    local Knob = New("Frame", {
        BackgroundColor3 = Color3.fromRGB(200, 200, 200),
        Position         = self.Settings[settingKey]
            and UDim2.new(1, -14, 0.5, -6)
            or UDim2.new(0, 2, 0.5, -6),
        Size             = UDim2.fromOffset(12, 12),
        BorderSizePixel  = 0,
        Parent           = ToggleBg,
    })

    New("UICorner", {
        CornerRadius = UDim.new(1, 0),
        Parent       = Knob,
    })

    -- Label
    New("TextLabel", {
        BackgroundTransparency = 1,
        Position         = UDim2.fromOffset(10, 0),
        Size             = UDim2.new(1, -56, 1, 0),
        Text             = text,
        TextColor3       = L.Scheme.FontColor,
        TextSize         = 12,
        Font             = Enum.Font.Code,
        TextXAlignment   = Enum.TextXAlignment.Left,
        Parent           = Container,
    })

    -- Divider
    New("Frame", {
        BackgroundColor3 = L.Scheme.OutlineColor,
        AnchorPoint      = Vector2.new(0, 1),
        Position         = UDim2.fromScale(0, 1),
        Size             = UDim2.new(1, 0, 0, 1),
        BorderSizePixel  = 0,
        Parent           = Container,
    })

    -- Click handler
    local btn = New("TextButton", {
        BackgroundTransparency = 1,
        Size     = UDim2.fromScale(1, 1),
        Text     = "",
        ZIndex   = 5,
        Parent   = Container,
    })

    btn.MouseButton1Click:Connect(function()
        self.Settings[settingKey] = not self.Settings[settingKey]
        local enabled = self.Settings[settingKey]

        TweenService:Create(Knob, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
            Position = enabled
                and UDim2.new(1, -14, 0.5, -6)
                or UDim2.new(0, 2, 0.5, -6),
        }):Play()

        TweenService:Create(ToggleBg, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
            BackgroundColor3 = enabled
                and L.Scheme.AccentColor
                or Color3.fromRGB(40, 40, 40),
        }):Play()

        if callback then callback(enabled) end
    end)

    table.insert(self.SettingsItems, Container)
    return Container
end

function GlobalChat:ToggleSettings()
    local L = self.Library
    if not L then return end

    if self.SettingsOpen then
        -- ─── Close Settings ───
        self.SettingsOpen = false

        -- Fade out items first
        for i, item in ipairs(self.SettingsItems) do
            task.delay((i - 1) * 0.03, function()
                if item and item.Parent then
                    TweenService:Create(item, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
                        GroupTransparency = 1,
                    }):Play()
                end
            end)
        end

        task.delay(#self.SettingsItems * 0.03 + 0.1, function()
            if self.SettingsOverlay and self.SettingsOverlay.Parent then
                local tween = TweenService:Create(self.SettingsOverlay, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
                    Position = UDim2.new(0, 0, 0, -self.ChatWindow.AbsoluteSize.Y),
                })
                tween:Play()
                tween.Completed:Wait()
                if self.SettingsOverlay and self.SettingsOverlay.Parent then
                    self.SettingsOverlay.Visible = false
                end
            end
        end)
    else
        -- ─── Open Settings ───
        self.SettingsOpen = true

        if not self.SettingsOverlay then
            self:BuildSettingsPanel()
        end

        local overlay = self.SettingsOverlay
        overlay.Visible = true
        overlay.Position = UDim2.new(0, 0, 0, -self.ChatWindow.AbsoluteSize.Y)

        -- Hide all items initially
        for _, item in ipairs(self.SettingsItems) do
            if item and item.Parent then
                item.Visible = false
                item.GroupTransparency = 1
            end
        end

        -- Slide in
        local slideTween = TweenService:Create(overlay, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
            Position = UDim2.new(0, 0, 0, 0),
        })
        slideTween:Play()
        slideTween.Completed:Wait()

        -- Reveal items one by one
        for i, item in ipairs(self.SettingsItems) do
            task.delay((i - 1) * 0.06, function()
                if item and item.Parent then
                    item.Visible = true
                    TweenService:Create(item, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
                        GroupTransparency = 0,
                    }):Play()
                end
            end)
        end
    end
end

function GlobalChat:BuildSettingsPanel()
    local L = self.Library
    self.SettingsItems = {}

    local overlay = New("Frame", {
        BackgroundColor3 = L.Scheme.BackgroundColor,
        BorderSizePixel  = 0,
        Position         = UDim2.new(0, 0, 0, 0),
        Size             = UDim2.fromScale(1, 1),
        ZIndex           = 10,
        ClipsDescendants = true,
        Visible          = false,
        Parent           = self.ChatWindow,
    })

    New("UIStroke", {
        Color           = L.Scheme.OutlineColor,
        Thickness       = 1,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
        Parent          = overlay,
    })

    -- Settings Title Bar
    local sTitleBar = New("Frame", {
        BackgroundColor3 = L.Scheme.MainColor,
        BorderSizePixel  = 0,
        Size             = UDim2.new(1, 0, 0, 28),
        ZIndex           = 11,
        Parent           = overlay,
    })

    New("Frame", {
        BackgroundColor3 = L.Scheme.OutlineColor,
        AnchorPoint      = Vector2.new(0, 1),
        Position         = UDim2.fromScale(0, 1),
        Size             = UDim2.new(1, 0, 0, 1),
        BorderSizePixel  = 0,
        ZIndex           = 11,
        Parent           = sTitleBar,
    })

    -- Accent top line
    New("Frame", {
        BackgroundColor3 = L.Scheme.AccentColor,
        Size             = UDim2.new(1, 0, 0, 2),
        BorderSizePixel  = 0,
        ZIndex           = 12,
        Parent           = overlay,
    })

    -- Back button
    local BackBtn = New("TextButton", {
        BackgroundTransparency = 1,
        Position  = UDim2.fromOffset(4, 2),
        Size      = UDim2.fromOffset(24, 24),
        Text      = "",
        ZIndex    = 12,
        Parent    = sTitleBar,
    })

    local backIcon = New("ImageLabel", {
        BackgroundTransparency = 1,
        Size     = UDim2.fromOffset(16, 16),
        Position = UDim2.fromOffset(4, 4),
        Image    = GetIcon("arrow-left"),
        ImageColor3 = L.Scheme.FontColor,
        ZIndex   = 12,
        Parent   = BackBtn,
    })

    BackBtn.MouseEnter:Connect(function()
        TweenService:Create(backIcon, TweenInfo.new(0.1), {
            ImageColor3 = L.Scheme.AccentColor,
        }):Play()
    end)
    BackBtn.MouseLeave:Connect(function()
        TweenService:Create(backIcon, TweenInfo.new(0.1), {
            ImageColor3 = L.Scheme.FontColor,
        }):Play()
    end)

    BackBtn.MouseButton1Click:Connect(function()
        self:ToggleSettings()
    end)

    -- Settings title
    New("TextLabel", {
        BackgroundTransparency = 1,
        Position         = UDim2.fromOffset(32, 0),
        Size             = UDim2.new(1, -36, 1, 0),
        Text             = "Chat Settings",
        TextColor3       = L.Scheme.FontColor,
        TextSize         = 13,
        Font             = Enum.Font.Code,
        TextXAlignment   = Enum.TextXAlignment.Left,
        ZIndex           = 11,
        Parent           = sTitleBar,
    })

    -- Settings content area
    local content = New("Frame", {
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(0, 30),
        Size     = UDim2.new(1, 0, 1, -30),
        ZIndex   = 10,
        Parent   = overlay,
    })

    -- ─── Toggle Items ───
    local yOffset = 8

    self:CreateSettingsToggle(content, yOffset, "Show Username & Avatar", "ShowUsername", function(val)
        if not val then
            self.Settings.ShowAvatar = false
        end
        self:ClearAndRefetch()
    end)
    yOffset = yOffset + 34

    self:CreateSettingsToggle(content, yOffset, "Show Avatar", "ShowAvatar", function(val)
        if val and not self.Settings.ShowUsername then
            self.Settings.ShowAvatar = false
            return
        end
        self:ClearAndRefetch()
    end)
    yOffset = yOffset + 34

    self:CreateSettingsToggle(content, yOffset, "Show Place Icon", "ShowPlaceIcon", function(val)
        self:ClearAndRefetch()
    end)
    yOffset = yOffset + 34

    self:CreateSettingsToggle(content, yOffset, "Allow PM Messages", "AllowPM", function(val)
    end)
    yOffset = yOffset + 34

    self:CreateSettingsToggle(content, yOffset, "Allow Connect to Server", "AllowConnect", function(val)
    end)

    self.SettingsOverlay = overlay

    -- Registry
    L:AddToRegistry(overlay, { BackgroundColor3 = "BackgroundColor" })
    L:AddToRegistry(sTitleBar, { BackgroundColor3 = "MainColor" })
end

-- ─── Chat Window ─────────────────────────────────────────────────────────────

function GlobalChat:CreateWindow()
    local L = self.Library
    if not L then return end

    if not self.ScreenGui then
        local SG = Instance.new("ScreenGui")
        SG.Name           = "GlobalChatGui"
        SG.ZIndexBehavior = Enum.ZIndexBehavior.Global
        SG.DisplayOrder   = 999
        SG.ResetOnSpawn   = false

        local protectgui = protectgui or (syn and syn.protect_gui) or function() end
        local gethui     = gethui or function() return game:GetService("CoreGui") end

        pcall(protectgui, SG)
        local ok = pcall(function() SG.Parent = gethui() end)
        if not ok then
            SG.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
        end

        self.ScreenGui = SG
    end

    local SG = self.ScreenGui

    local Scale = Instance.new("UIScale")
    Scale.Scale  = L.DPIScale
    Scale.Parent = SG
    table.insert(L.Scales, Scale)

    local ChatFrame = New("Frame", {
        BackgroundColor3 = L.Scheme.BackgroundColor,
        BorderSizePixel  = 0,
        Position         = UDim2.new(1, -375, 1, -310),
        Size             = UDim2.fromOffset(360, 300),
        ClipsDescendants = true,
        Parent           = SG,
    })

    if L.IsMobile then
        ChatFrame.Size     = UDim2.fromOffset(320, 260)
        ChatFrame.Position = UDim2.fromOffset(6, 6)
    end

    New("UIStroke", {
        Color           = L.Scheme.OutlineColor,
        Thickness       = 1,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
        Parent          = ChatFrame,
    })

    -- Accent top line
    New("Frame", {
        BackgroundColor3 = L.Scheme.AccentColor,
        Size             = UDim2.new(1, 0, 0, 2),
        BorderSizePixel  = 0,
        ZIndex           = 2,
        Parent           = ChatFrame,
    })

    -- Title bar
    local TitleBar = New("Frame", {
        BackgroundColor3 = L.Scheme.MainColor,
        BorderSizePixel  = 0,
        Size             = UDim2.new(1, 0, 0, 28),
        Parent           = ChatFrame,
    })

    New("Frame", {
        BackgroundColor3 = L.Scheme.OutlineColor,
        AnchorPoint      = Vector2.new(0, 1),
        Position         = UDim2.fromScale(0, 1),
        Size             = UDim2.new(1, 0, 0, 1),
        BorderSizePixel  = 0,
        Parent           = TitleBar,
    })

    -- Title label
    New("TextLabel", {
        BackgroundTransparency = 1,
        Size             = UDim2.new(1, -80, 1, 0),
        Position         = UDim2.fromOffset(8, 0),
        Text             = "Global Chat",
        TextColor3       = L.Scheme.FontColor,
        TextSize         = 13,
        Font             = Enum.Font.Code,
        TextXAlignment   = Enum.TextXAlignment.Left,
        Parent           = TitleBar,
    })

    -- ─── Settings Button (with icon) ───
    local SettingsBtn = New("TextButton", {
        BackgroundTransparency = 1,
        AnchorPoint = Vector2.new(1, 0.5),
        Position    = UDim2.new(1, -70, 0.5, 0),
        Size        = UDim2.fromOffset(24, 24),
        Text        = "",
        Parent      = TitleBar,
    })

    local settingsIcon = New("ImageLabel", {
        BackgroundTransparency = 1,
        Size        = UDim2.fromOffset(16, 16),
        Position    = UDim2.fromOffset(4, 4),
        Image       = GetIcon("settings"),
        ImageColor3 = L.Scheme.FontColor,
        Parent      = SettingsBtn,
    })

    SettingsBtn.MouseEnter:Connect(function()
        TweenService:Create(settingsIcon, TweenInfo.new(0.15), {
            ImageColor3 = L.Scheme.AccentColor,
        }):Play()
        TweenService:Create(settingsIcon, TweenInfo.new(0.3, Enum.EasingStyle.Quad), {
            Rotation = 45,
        }):Play()
    end)
    SettingsBtn.MouseLeave:Connect(function()
        TweenService:Create(settingsIcon, TweenInfo.new(0.15), {
            ImageColor3 = L.Scheme.FontColor,
        }):Play()
        TweenService:Create(settingsIcon, TweenInfo.new(0.3, Enum.EasingStyle.Quad), {
            Rotation = 0,
        }):Play()
    end)

    SettingsBtn.MouseButton1Click:Connect(function()
        self:ToggleSettings()
    end)

    -- Online count label
    local OnlineLabel = New("TextLabel", {
        BackgroundTransparency = 1,
        AnchorPoint      = Vector2.new(1, 0.5),
        Position         = UDim2.new(1, -8, 0.5, 0),
        Size             = UDim2.fromOffset(60, 20),
        Text             = "● online",
        TextColor3       = L.Scheme.AccentColor,
        TextSize         = 11,
        Font             = Enum.Font.Code,
        TextXAlignment   = Enum.TextXAlignment.Right,
        Parent           = TitleBar,
    })

    -- Draggable
    do
        local StartPos
        local FramePos
        local Dragging = false
        local Changed

        TitleBar.InputBegan:Connect(function(Input)
            if Input.UserInputType ~= Enum.UserInputType.MouseButton1
                and Input.UserInputType ~= Enum.UserInputType.Touch then
                return
            end
            StartPos = Input.Position
            FramePos = ChatFrame.Position
            Dragging = true

            Changed = Input.Changed:Connect(function()
                if Input.UserInputState == Enum.UserInputState.End then
                    Dragging = false
                    if Changed and Changed.Connected then
                        Changed:Disconnect()
                        Changed = nil
                    end
                end
            end)
        end)

        game:GetService("UserInputService").InputChanged:Connect(function(Input)
            if not Dragging then return end
            if Input.UserInputType == Enum.UserInputType.MouseMovement
                or Input.UserInputType == Enum.UserInputType.Touch
            then
                local Delta = Input.Position - StartPos
                ChatFrame.Position = UDim2.new(
                    FramePos.X.Scale,
                    FramePos.X.Offset + Delta.X,
                    FramePos.Y.Scale,
                    FramePos.Y.Offset + Delta.Y
                )
            end
        end)
    end

    -- Messages area
    local MsgArea = New("Frame", {
        BackgroundColor3 = L.Scheme.BackgroundColor,
        BorderSizePixel  = 0,
        Position         = UDim2.fromOffset(0, 29),
        Size             = UDim2.new(1, 0, 1, -75),
        ClipsDescendants = true,
        Parent           = ChatFrame,
    })

    New("UIStroke", {
        Color           = L.Scheme.OutlineColor,
        Thickness       = 1,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
        Parent          = MsgArea,
    })

    local SF = New("ScrollingFrame", {
        BackgroundTransparency = 1,
        BorderSizePixel        = 0,
        Size                   = UDim2.fromScale(1, 1),
        CanvasSize             = UDim2.fromScale(0, 0),
        AutomaticCanvasSize    = Enum.AutomaticSize.Y,
        ScrollBarThickness     = 3,
        ScrollBarImageColor3   = L.Scheme.AccentColor,
        ScrollingDirection     = Enum.ScrollingDirection.Y,
        Parent                 = MsgArea,
    })

    local Layout = New("UIListLayout", {
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding   = UDim.new(0, 0),
        Parent    = SF,
    })

    Layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        SF.CanvasPosition = Vector2.new(0, SF.AbsoluteCanvasSize.Y)
    end)

    -- Input area
    local InputArea = New("Frame", {
        BackgroundColor3 = L.Scheme.MainColor,
        BorderSizePixel  = 0,
        AnchorPoint      = Vector2.new(0, 1),
        Position         = UDim2.fromScale(0, 1),
        Size             = UDim2.new(1, 0, 0, 44),
        Parent           = ChatFrame,
    })

    New("Frame", {
        BackgroundColor3 = L.Scheme.OutlineColor,
        Size             = UDim2.new(1, 0, 0, 1),
        BorderSizePixel  = 0,
        Parent           = InputArea,
    })

    local TB = New("TextBox", {
        BackgroundColor3   = L.Scheme.BackgroundColor,
        BorderSizePixel    = 0,
        Position           = UDim2.fromOffset(6, 8),
        Size               = UDim2.new(1, -72, 0, 26),
        Font               = Enum.Font.Code,
        PlaceholderText    = "Type a message...",
        PlaceholderColor3  = Color3.fromRGB(80, 80, 80),
        Text               = "",
        TextColor3         = L.Scheme.FontColor,
        TextSize           = 13,
        TextXAlignment     = Enum.TextXAlignment.Left,
        ClearTextOnFocus   = false,
        Parent             = InputArea,
    })

    New("UIPadding", {
        PaddingLeft  = UDim.new(0, 6),
        PaddingRight = UDim.new(0, 6),
        Parent       = TB,
    })

    New("UIStroke", {
        Color           = L.Scheme.OutlineColor,
        Thickness       = 1,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
        Parent          = TB,
    })

    local SendBtn = New("TextButton", {
        BackgroundColor3 = L.Scheme.AccentColor,
        BorderSizePixel  = 0,
        AnchorPoint      = Vector2.new(1, 0),
        Position         = UDim2.new(1, -6, 0, 8),
        Size             = UDim2.fromOffset(58, 26),
        Font             = Enum.Font.Code,
        Text             = "Send",
        TextColor3       = Color3.fromRGB(10, 10, 10),
        TextSize         = 13,
        AutoButtonColor  = false,
        Parent           = InputArea,
    })

    New("UIStroke", {
        Color           = L.Scheme.OutlineColor,
        Thickness       = 1,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
        Parent          = SendBtn,
    })

    SendBtn.MouseEnter:Connect(function()
        TweenService:Create(SendBtn, TweenInfo.new(0.1), {
            BackgroundColor3 = Color3.fromRGB(
                math.clamp(L.Scheme.AccentColor.R * 255 + 20, 0, 255),
                math.clamp(L.Scheme.AccentColor.G * 255 + 20, 0, 255),
                math.clamp(L.Scheme.AccentColor.B * 255 + 20, 0, 255)
            ),
        }):Play()
    end)
    SendBtn.MouseLeave:Connect(function()
        TweenService:Create(SendBtn, TweenInfo.new(0.1), {
            BackgroundColor3 = L.Scheme.AccentColor,
        }):Play()
    end)

    local function DoSend()
        local msg = TB.Text:match("^%s*(.-)%s*$")
        if not msg or msg == "" then return end
        TB.Text = ""
        self:SendMessage(msg)
    end

    SendBtn.MouseButton1Click:Connect(DoSend)
    TB.FocusLost:Connect(function(Enter)
        if Enter then DoSend() end
    end)

    -- Save references
    self.ChatWindow  = ChatFrame
    self.ScrollFrame = SF
    self.TextBox     = TB
    self.SendButton  = SendBtn
    self.OnlineLabel = OnlineLabel

    -- Registry
    L:AddToRegistry(ChatFrame, { BackgroundColor3 = "BackgroundColor" })
    L:AddToRegistry(TitleBar, { BackgroundColor3 = "MainColor" })
    L:AddToRegistry(MsgArea, { BackgroundColor3 = "BackgroundColor" })
    L:AddToRegistry(InputArea, { BackgroundColor3 = "MainColor" })
    L:AddToRegistry(TB, {
        BackgroundColor3 = "BackgroundColor",
        TextColor3 = "FontColor",
    })
    L:AddToRegistry(SendBtn, { BackgroundColor3 = "AccentColor" })
    L:AddToRegistry(SF, { ScrollBarImageColor3 = "AccentColor" })
end

-- ─── Polling ─────────────────────────────────────────────────────────────────

function GlobalChat:StartPolling()
    if pollingStarted then return end
    pollingStarted = true

    task.spawn(function()
        while true do
            local now = tick()
            if now - lastFetchTime >= GlobalChat.UpdateInterval then
                self:FetchAndUpdate()
                lastFetchTime = now
            end
            task.wait(1)
        end
    end)

    local L = self.Library
    task.spawn(function()
        while true do
            RunService.Heartbeat:Wait()
            if self.Enabled and self.ChatWindow then
                local shouldShow = L and L.Toggled or false
                if self.ChatWindow.Visible ~= shouldShow then
                    self.ChatWindow.Visible = shouldShow
                end
            end
        end
    end)

    task.spawn(function()
        while true do
            task.wait(10)
            if self.OnlineLabel then
                local count = #Players:GetPlayers()
                if self.OnlineLabel and self.OnlineLabel.Parent then
                    self.OnlineLabel.Text = "● " .. count .. " online"
                end
            end
        end
    end)

    task.spawn(function()
        while true do
            task.wait(30)
            local now = os.time()
            for k in pairs(displayedBubbles) do
                local ts = tonumber(k:match("_(%d+)$"))
                if ts and (now - ts) > 15 then
                    displayedBubbles[k] = nil
                end
            end
        end
    end)

    Players.PlayerAdded:Connect(function(pl)
        pl.CharacterAdded:Connect(function()
            task.wait(1)
            if not request then return end
            local ok, result = pcall(function()
                local resp = request({
                    Url    = GlobalChat.FirebaseUrl .. GlobalChat.MessagesPath
                             .. ".json?orderBy=\"$key\"&limitToLast=5",
                    Method = "GET",
                })
                if resp.Success and resp.Body and resp.Body ~= "null" then
                    return HttpService:JSONDecode(resp.Body)
                end
            end)
            if not (ok and result) then return end

            local msgs = {}
            for _, m in pairs(result) do
                table.insert(msgs, m)
            end
            table.sort(msgs, function(a, b)
                return a.timestamp < b.timestamp
            end)

            local now = os.time()
            for i = #msgs, 1, -1 do
                local m = msgs[i]
                if m.userId == pl.UserId
                    and (now - m.timestamp) < GlobalChat.BubbleDisplayTime
                then
                    Create3DBubble(pl, m.message, m.timestamp)
                    break
                end
            end
        end)
    end)
end

-- ─── Public API ──────────────────────────────────────────────────────────────

function GlobalChat:SetLibrary(lib)
    self.Library = lib
end

function GlobalChat:SetFirebaseUrl(url)
    GlobalChat.FirebaseUrl = url
end

function GlobalChat:SetUpdateInterval(seconds)
    GlobalChat.UpdateInterval = seconds
end

function GlobalChat:SetMaxMessages(count)
    GlobalChat.MaxMessages = count
end

function GlobalChat:CreateGroupBox(groupbox)
    local L = self.Library

    groupbox:AddToggle("GlobalChatEnabled", {
        Text    = "Enable Global Chat",
        Default = false,
        Tooltip = "Open floating chat window",
        Callback = function(Value)
            self.Enabled = Value
            if Value then
                if not self.ChatWindow then
                    self:CreateWindow()
                    self:FetchAndUpdate()
                    lastFetchTime = tick()
                end
                self:StartPolling()
                if L and L.Toggled and self.ChatWindow then
                    self.ChatWindow.Visible = true
                end
            else
                if self.ChatWindow then
                    self.ChatWindow.Visible = false
                end
            end
        end,
    })
end

function GlobalChat:ApplyToTab(tab)
    assert(self.Library, "GlobalChat: Must call SetLibrary(lib) first!")
    local groupbox = tab:AddLeftGroupbox("Global Chat", "message-circle")
    self:CreateGroupBox(groupbox)
end

return GlobalChat
