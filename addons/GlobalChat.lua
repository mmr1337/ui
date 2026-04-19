--[[
    GlobalChat Addon for gamesense-style Library
    Stable simple version with chat settings.

    Added:
        - Settings button in chat window
        - Hide Username toggle
        - Hide Avatar toggle

    Notes:
        - No PM/inbox system
        - No CanvasGroup usage
        - No invalid ZIndex/UICorner assignments
]]

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local GlobalChat = {}
GlobalChat.__index = GlobalChat

GlobalChat.FirebaseUrl = "https://apirobloxuser-default-rtdb.firebaseio.com"
GlobalChat.MessagesPath = "/globalchat/messages"
GlobalChat.MaxMessages = 50
GlobalChat.UpdateInterval = 3
GlobalChat.BubbleDisplayTime = 10

GlobalChat.Library = nil
GlobalChat.ScreenGui = nil
GlobalChat.ChatWindow = nil
GlobalChat.Enabled = false
GlobalChat.ScrollFrame = nil
GlobalChat.TextBox = nil
GlobalChat.SendButton = nil
GlobalChat.OnlineLabel = nil

GlobalChat.Settings = {
    HideUsername = true,
    HideAvatar = true,
}

GlobalChat.SettingsOpen = false
GlobalChat.SettingsOverlay = nil
GlobalChat.SettingsRows = {}

local request = (syn and syn.request)
    or (http and http.request)
    or http_request
    or (Fluxus and Fluxus.request)
    or request

local thumbnailCache = {}
local messageHistory = {}
local displayedBubbles = {}
local lastFetchTime = 0
local pollingStarted = false

local HIDDEN_NAME = "Secret User"
local HIDDEN_AVATAR = "rbxassetid://5107154082"
local DEFAULT_AVATAR = "rbxassetid://5107154082"

local ICON_SETTINGS = "rbxassetid://7733960981"
local ICON_BACK = "rbxassetid://7733658504"

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

local function New(className, properties)
    local inst = Instance.new(className)
    for k, v in pairs(properties or {}) do
        if k ~= "Parent" then
            pcall(function()
                inst[k] = v
            end)
        end
    end
    if properties and properties.Parent then
        inst.Parent = properties.Parent
    end
    return inst
end

local function Create3DBubble(player, message, timestamp)
    if not player or not player.Character then return end
    local head = player.Character:FindFirstChild("Head")
    if not head then return end

    local key = tostring(player.UserId) .. "_" .. tostring(timestamp)
    if displayedBubbles[key] then return end

    local age = os.time() - timestamp
    if age >= GlobalChat.BubbleDisplayTime then return end
    displayedBubbles[key] = true

    local old = head:FindFirstChild("GlobalChatBubble")
    if old then old:Destroy() end

    local accent = Color3.fromRGB(100, 200, 100)
    if GlobalChat.Library and GlobalChat.Library.Scheme then
        accent = GlobalChat.Library.Scheme.AccentColor
    end

    local board = New("BillboardGui", {
        Name = "GlobalChatBubble",
        Size = UDim2.fromOffset(240, 50),
        StudsOffset = Vector3.new(0, 3, 0),
        AlwaysOnTop = true,
        Parent = head,
    })

    local bg = New("Frame", {
        Size = UDim2.fromScale(1, 1),
        BackgroundColor3 = Color3.fromRGB(12, 12, 12),
        BorderSizePixel = 0,
        Parent = board,
    })

    New("Frame", {
        BackgroundColor3 = accent,
        Size = UDim2.new(0, 2, 1, 0),
        BorderSizePixel = 0,
        Parent = bg,
    })

    New("UIStroke", {
        Color = Color3.fromRGB(45, 45, 45),
        Thickness = 1,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
        Parent = bg,
    })

    New("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(8, 3),
        Size = UDim2.new(1, -10, 1, -6),
        Text = tostring(message),
        TextColor3 = Color3.fromRGB(200, 200, 200),
        TextSize = 13,
        Font = Enum.Font.Code,
        TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = bg,
    })

    task.delay(GlobalChat.BubbleDisplayTime - age, function()
        if board and board.Parent then
            board:Destroy()
        end
        displayedBubbles[key] = nil
    end)
end

function GlobalChat:AddMessage(data)
    local key = tostring(data.timestamp) .. tostring(data.userId)
    if messageHistory[key] then return end
    messageHistory[key] = true

    local sf = self.ScrollFrame
    local L = self.Library
    if not (sf and L) then return end

    local showUsername = not self.Settings.HideUsername
    local showAvatar = not self.Settings.HideAvatar

    local leftOffset = showAvatar and 54 or 10
    local rowHeight = showAvatar and 48 or 34
    local nameText = showUsername and ((data.displayName or "Unknown") .. " (@" .. (data.username or "unknown") .. ")") or HIDDEN_NAME
    local avatarImage = showAvatar and (showUsername and GetThumbnail(data.userId) or HIDDEN_AVATAR) or nil

    local row = New("Frame", {
        BackgroundColor3 = L.Scheme.MainColor,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, rowHeight),
        LayoutOrder = tonumber(data.timestamp) or 0,
        ClipsDescendants = true,
        Parent = sf,
    })

    New("Frame", {
        BackgroundColor3 = L.Scheme.AccentColor,
        Size = UDim2.new(0, 2, 1, 0),
        BorderSizePixel = 0,
        Parent = row,
    })

    New("Frame", {
        BackgroundColor3 = L.Scheme.OutlineColor,
        AnchorPoint = Vector2.new(0, 1),
        Position = UDim2.fromScale(0, 1),
        Size = UDim2.new(1, 0, 0, 1),
        BorderSizePixel = 0,
        Parent = row,
    })

    if showAvatar and avatarImage then
        local av = New("ImageLabel", {
            BackgroundColor3 = L.Scheme.BackgroundColor,
            Position = UDim2.fromOffset(8, 4),
            Size = UDim2.fromOffset(40, 40),
            Image = avatarImage,
            BorderSizePixel = 0,
            Parent = row,
        })

        New("UIStroke", {
            Color = L.Scheme.OutlineColor,
            Thickness = 1,
            ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
            Parent = av,
        })
    end

    local nameY = showAvatar and 5 or 2
    local msgY = showAvatar and 22 or 16
    local msgHeight = showAvatar and 22 or 14

    New("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(leftOffset, nameY),
        Size = UDim2.new(1, -(leftOffset + 6), 0, 16),
        Text = nameText,
        TextColor3 = L.Scheme.AccentColor,
        TextSize = 12,
        Font = Enum.Font.Code,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
        Parent = row,
    })

    New("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(leftOffset, msgY),
        Size = UDim2.new(1, -(leftOffset + 6), 0, msgHeight),
        Text = tostring(data.message or ""),
        TextColor3 = Color3.fromRGB(200, 200, 200),
        TextSize = 13,
        Font = Enum.Font.Code,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextWrapped = true,
        ClipsDescendants = true,
        Parent = row,
    })

    local rows = {}
    for _, c in ipairs(sf:GetChildren()) do
        if c:IsA("Frame") then
            table.insert(rows, c)
        end
    end

    if #rows > GlobalChat.MaxMessages then
        table.sort(rows, function(a, b)
            return (a.LayoutOrder or 0) < (b.LayoutOrder or 0)
        end)
        if rows[1] then
            rows[1]:Destroy()
        end
    end
end

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

function GlobalChat:SendMessage(message)
    if not request then return end
    local lp = Players.LocalPlayer
    local data = {
        userId = lp.UserId,
        username = lp.Name,
        displayName = lp.DisplayName,
        message = message,
        timestamp = os.time(),
        gameId = game.PlaceId,
    }

    task.spawn(function()
        local ok = pcall(function()
            request({
                Url = GlobalChat.FirebaseUrl .. GlobalChat.MessagesPath .. ".json",
                Method = "POST",
                Headers = { ["Content-Type"] = "application/json" },
                Body = HttpService:JSONEncode(data),
            })
        end)

        if ok then
            Create3DBubble(lp, message, data.timestamp)
        end
    end)
end

function GlobalChat:FetchAndUpdate()
    if not request then return end

    local ok, result = pcall(function()
        local resp = request({
            Url = GlobalChat.FirebaseUrl .. GlobalChat.MessagesPath
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
        return (a.timestamp or 0) < (b.timestamp or 0)
    end)

    local now = os.time()
    for _, msg in ipairs(sorted) do
        self:AddMessage(msg)
        if msg.timestamp and (now - msg.timestamp < GlobalChat.BubbleDisplayTime) then
            local pl = Players:GetPlayerByUserId(msg.userId)
            if pl and pl.Character then
                Create3DBubble(pl, msg.message, msg.timestamp)
            end
        end
    end
end

function GlobalChat:CreateSettingsRow(parent, yPos, text, settingKey)
    local L = self.Library

    local row = New("Frame", {
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 0, 0, yPos),
        Size = UDim2.new(1, 0, 0, 28),
        Parent = parent,
    })

    New("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(8, 0),
        Size = UDim2.new(1, -40, 1, 0),
        Text = text,
        TextColor3 = L.Scheme.FontColor,
        TextSize = 12,
        Font = Enum.Font.Code,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = row,
    })

    local checkBox = New("Frame", {
        BackgroundColor3 = L.Scheme.MainColor,
        BorderSizePixel = 0,
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -8, 0.5, 0),
        Size = UDim2.fromOffset(12, 12),
        Parent = row,
    })

    New("UIStroke", {
        Color = L.Scheme.OutlineColor,
        Thickness = 1,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
        Parent = checkBox,
    })

    local fill = New("Frame", {
        BackgroundColor3 = L.Scheme.AccentColor,
        BorderSizePixel = 0,
        Size = UDim2.new(1, -2, 1, -2),
        Position = UDim2.fromOffset(1, 1),
        Visible = self.Settings[settingKey] == true,
        Parent = checkBox,
    })

    local divider = New("Frame", {
        BackgroundColor3 = L.Scheme.OutlineColor,
        AnchorPoint = Vector2.new(0, 1),
        Position = UDim2.fromScale(0, 1),
        Size = UDim2.new(1, 0, 0, 1),
        BorderSizePixel = 0,
        Parent = row,
    })

    local button = New("TextButton", {
        BackgroundTransparency = 1,
        Size = UDim2.fromScale(1, 1),
        Text = "",
        Parent = row,
    })

    button.MouseButton1Click:Connect(function()
        self.Settings[settingKey] = not self.Settings[settingKey]
        fill.Visible = self.Settings[settingKey] == true
        self:ClearAndRefetch()
    end)

    table.insert(self.SettingsRows, {
        Row = row,
        Fill = fill,
        Divider = divider,
    })

    return row
end

function GlobalChat:BuildSettingsPanel()
    if self.SettingsOverlay or not self.ChatWindow then return end
    local L = self.Library

    local overlay = New("Frame", {
        BackgroundColor3 = L.Scheme.BackgroundColor,
        BorderSizePixel = 0,
        Position = UDim2.new(0, 0, 0, -self.ChatWindow.AbsoluteSize.Y),
        Size = UDim2.fromScale(1, 1),
        Visible = false,
        ClipsDescendants = true,
        Parent = self.ChatWindow,
    })

    New("UIStroke", {
        Color = L.Scheme.OutlineColor,
        Thickness = 1,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
        Parent = overlay,
    })

    New("Frame", {
        BackgroundColor3 = L.Scheme.AccentColor,
        Size = UDim2.new(1, 0, 0, 2),
        BorderSizePixel = 0,
        Parent = overlay,
    })

    local titleBar = New("Frame", {
        BackgroundColor3 = L.Scheme.MainColor,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, 28),
        Parent = overlay,
    })

    New("Frame", {
        BackgroundColor3 = L.Scheme.OutlineColor,
        AnchorPoint = Vector2.new(0, 1),
        Position = UDim2.fromScale(0, 1),
        Size = UDim2.new(1, 0, 0, 1),
        BorderSizePixel = 0,
        Parent = titleBar,
    })

    local backBtn = New("TextButton", {
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(4, 2),
        Size = UDim2.fromOffset(24, 24),
        Text = "",
        Parent = titleBar,
    })

    local backIcon = New("ImageLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(4, 4),
        Size = UDim2.fromOffset(16, 16),
        Image = ICON_BACK,
        ImageColor3 = L.Scheme.FontColor,
        Parent = backBtn,
    })

    backBtn.MouseEnter:Connect(function()
        TweenService:Create(backIcon, TweenInfo.new(0.1), {
            ImageColor3 = L.Scheme.AccentColor,
        }):Play()
    end)

    backBtn.MouseLeave:Connect(function()
        TweenService:Create(backIcon, TweenInfo.new(0.1), {
            ImageColor3 = L.Scheme.FontColor,
        }):Play()
    end)

    backBtn.MouseButton1Click:Connect(function()
        self:ToggleSettings()
    end)

    New("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(32, 0),
        Size = UDim2.new(1, -36, 1, 0),
        Text = "Chat Settings",
        TextColor3 = L.Scheme.FontColor,
        TextSize = 13,
        Font = Enum.Font.Code,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = titleBar,
    })

    local content = New("Frame", {
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(0, 30),
        Size = UDim2.new(1, 0, 1, -30),
        Parent = overlay,
    })

    self.SettingsRows = {}
    self:CreateSettingsRow(content, 6, "Hide Username", "HideUsername")
    self:CreateSettingsRow(content, 34, "Hide Avatar", "HideAvatar")

    self.SettingsOverlay = overlay

    L:AddToRegistry(overlay, { BackgroundColor3 = "BackgroundColor" })
    L:AddToRegistry(titleBar, { BackgroundColor3 = "MainColor" })
end

function GlobalChat:ToggleSettings()
    if not self.ChatWindow then return end
    if not self.SettingsOverlay then
        self:BuildSettingsPanel()
    end
    if not self.SettingsOverlay then return end

    if self.SettingsOpen then
        self.SettingsOpen = false
        local tween = TweenService:Create(self.SettingsOverlay, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
            Position = UDim2.new(0, 0, 0, -self.ChatWindow.AbsoluteSize.Y),
        })
        tween:Play()
        task.delay(0.2, function()
            if self.SettingsOverlay then
                self.SettingsOverlay.Visible = false
            end
        end)
    else
        self.SettingsOpen = true
        self.SettingsOverlay.Visible = true
        self.SettingsOverlay.Position = UDim2.new(0, 0, 0, -self.ChatWindow.AbsoluteSize.Y)
        TweenService:Create(self.SettingsOverlay, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
            Position = UDim2.new(0, 0, 0, 0),
        }):Play()
    end
end

function GlobalChat:CreateWindow()
    local L = self.Library
    if not L then return end

    if not self.ScreenGui then
        local SG = Instance.new("ScreenGui")
        SG.Name = "GlobalChatGui"
        SG.ZIndexBehavior = Enum.ZIndexBehavior.Global
        SG.DisplayOrder = 999
        SG.ResetOnSpawn = false

        local protectgui = protectgui or (syn and syn.protect_gui) or function() end
        local gethui = gethui or function() return game:GetService("CoreGui") end

        pcall(protectgui, SG)
        local ok = pcall(function()
            SG.Parent = gethui()
        end)
        if not ok then
            SG.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
        end

        self.ScreenGui = SG
    end

    local SG = self.ScreenGui

    local scale = Instance.new("UIScale")
    scale.Scale = L.DPIScale
    scale.Parent = SG
    table.insert(L.Scales, scale)

    local chatFrame = New("Frame", {
        BackgroundColor3 = L.Scheme.BackgroundColor,
        BorderSizePixel = 0,
        Position = UDim2.new(1, -375, 1, -310),
        Size = UDim2.fromOffset(360, 300),
        ClipsDescendants = true,
        Parent = SG,
    })

    if L.IsMobile then
        chatFrame.Size = UDim2.fromOffset(320, 260)
        chatFrame.Position = UDim2.fromOffset(6, 6)
    end

    New("UIStroke", {
        Color = L.Scheme.OutlineColor,
        Thickness = 1,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
        Parent = chatFrame,
    })

    New("Frame", {
        BackgroundColor3 = L.Scheme.AccentColor,
        Size = UDim2.new(1, 0, 0, 2),
        BorderSizePixel = 0,
        Parent = chatFrame,
    })

    local titleBar = New("Frame", {
        BackgroundColor3 = L.Scheme.MainColor,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, 28),
        Parent = chatFrame,
    })

    New("Frame", {
        BackgroundColor3 = L.Scheme.OutlineColor,
        AnchorPoint = Vector2.new(0, 1),
        Position = UDim2.fromScale(0, 1),
        Size = UDim2.new(1, 0, 0, 1),
        BorderSizePixel = 0,
        Parent = titleBar,
    })

    New("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(8, 0),
        Size = UDim2.new(1, -120, 1, 0),
        Text = "Global Chat",
        TextColor3 = L.Scheme.FontColor,
        TextSize = 13,
        Font = Enum.Font.Code,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = titleBar,
    })

    local settingsBtn = New("TextButton", {
        BackgroundTransparency = 1,
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -6, 0.5, 0),
        Size = UDim2.fromOffset(24, 24),
        Text = "",
        Parent = titleBar,
    })

    local settingsIcon = New("ImageLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(4, 4),
        Size = UDim2.fromOffset(16, 16),
        Image = ICON_SETTINGS,
        ImageColor3 = L.Scheme.FontColor,
        Parent = settingsBtn,
    })

    settingsBtn.MouseEnter:Connect(function()
        TweenService:Create(settingsIcon, TweenInfo.new(0.15), {
            ImageColor3 = L.Scheme.AccentColor,
            Rotation = 45,
        }):Play()
    end)

    settingsBtn.MouseLeave:Connect(function()
        TweenService:Create(settingsIcon, TweenInfo.new(0.15), {
            ImageColor3 = L.Scheme.FontColor,
            Rotation = 0,
        }):Play()
    end)

    settingsBtn.MouseButton1Click:Connect(function()
        self:ToggleSettings()
    end)

    local onlineLabel = New("TextLabel", {
        BackgroundTransparency = 1,
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -36, 0.5, 0),
        Size = UDim2.fromOffset(70, 20),
        Text = "● online",
        TextColor3 = L.Scheme.AccentColor,
        TextSize = 11,
        Font = Enum.Font.Code,
        TextXAlignment = Enum.TextXAlignment.Right,
        Parent = titleBar,
    })

    do
        local startPos
        local framePos
        local dragging = false
        local changed

        titleBar.InputBegan:Connect(function(input)
            if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
                return
            end
            startPos = input.Position
            framePos = chatFrame.Position
            dragging = true

            changed = input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                    if changed and changed.Connected then
                        changed:Disconnect()
                        changed = nil
                    end
                end
            end)
        end)

        UserInputService.InputChanged:Connect(function(input)
            if not dragging then return end
            if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
                local delta = input.Position - startPos
                chatFrame.Position = UDim2.new(
                    framePos.X.Scale,
                    framePos.X.Offset + delta.X,
                    framePos.Y.Scale,
                    framePos.Y.Offset + delta.Y
                )
            end
        end)
    end

    local msgArea = New("Frame", {
        BackgroundColor3 = L.Scheme.BackgroundColor,
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(0, 29),
        Size = UDim2.new(1, 0, 1, -75),
        Parent = chatFrame,
    })

    New("UIStroke", {
        Color = L.Scheme.OutlineColor,
        Thickness = 1,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
        Parent = msgArea,
    })

    local sf = New("ScrollingFrame", {
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Size = UDim2.fromScale(1, 1),
        CanvasSize = UDim2.fromScale(0, 0),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        ScrollBarThickness = 3,
        ScrollBarImageColor3 = L.Scheme.AccentColor,
        ScrollingDirection = Enum.ScrollingDirection.Y,
        Parent = msgArea,
    })

    local layout = New("UIListLayout", {
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 0),
        Parent = sf,
    })

    layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        sf.CanvasPosition = Vector2.new(0, math.max(0, sf.AbsoluteCanvasSize.Y))
    end)

    local inputArea = New("Frame", {
        BackgroundColor3 = L.Scheme.MainColor,
        BorderSizePixel = 0,
        AnchorPoint = Vector2.new(0, 1),
        Position = UDim2.fromScale(0, 1),
        Size = UDim2.new(1, 0, 0, 44),
        Parent = chatFrame,
    })

    New("Frame", {
        BackgroundColor3 = L.Scheme.OutlineColor,
        Size = UDim2.new(1, 0, 0, 1),
        BorderSizePixel = 0,
        Parent = inputArea,
    })

    local tb = New("TextBox", {
        BackgroundColor3 = L.Scheme.BackgroundColor,
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(6, 8),
        Size = UDim2.new(1, -72, 0, 26),
        Font = Enum.Font.Code,
        PlaceholderText = "Type a message...",
        PlaceholderColor3 = Color3.fromRGB(80, 80, 80),
        Text = "",
        TextColor3 = L.Scheme.FontColor,
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
        ClearTextOnFocus = false,
        Parent = inputArea,
    })

    New("UIPadding", {
        PaddingLeft = UDim.new(0, 6),
        PaddingRight = UDim.new(0, 6),
        Parent = tb,
    })

    New("UIStroke", {
        Color = L.Scheme.OutlineColor,
        Thickness = 1,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
        Parent = tb,
    })

    local sendBtn = New("TextButton", {
        BackgroundColor3 = L.Scheme.AccentColor,
        BorderSizePixel = 0,
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -6, 0, 8),
        Size = UDim2.fromOffset(58, 26),
        Font = Enum.Font.Code,
        Text = "Send",
        TextColor3 = Color3.fromRGB(10, 10, 10),
        TextSize = 13,
        AutoButtonColor = false,
        Parent = inputArea,
    })

    New("UIStroke", {
        Color = L.Scheme.OutlineColor,
        Thickness = 1,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
        Parent = sendBtn,
    })

    sendBtn.MouseEnter:Connect(function()
        TweenService:Create(sendBtn, TweenInfo.new(0.1), {
            BackgroundColor3 = Color3.fromRGB(
                math.clamp(L.Scheme.AccentColor.R * 255 + 20, 0, 255),
                math.clamp(L.Scheme.AccentColor.G * 255 + 20, 0, 255),
                math.clamp(L.Scheme.AccentColor.B * 255 + 20, 0, 255)
            ),
        }):Play()
    end)

    sendBtn.MouseLeave:Connect(function()
        TweenService:Create(sendBtn, TweenInfo.new(0.1), {
            BackgroundColor3 = L.Scheme.AccentColor,
        }):Play()
    end)

    local function DoSend()
        local msg = tb.Text:match("^%s*(.-)%s*$")
        if not msg or msg == "" then return end
        tb.Text = ""
        self:SendMessage(msg)
    end

    sendBtn.MouseButton1Click:Connect(DoSend)
    tb.FocusLost:Connect(function(enter)
        if enter then
            DoSend()
        end
    end)

    self.ChatWindow = chatFrame
    self.ScrollFrame = sf
    self.TextBox = tb
    self.SendButton = sendBtn
    self.OnlineLabel = onlineLabel

    L:AddToRegistry(chatFrame, { BackgroundColor3 = "BackgroundColor" })
    L:AddToRegistry(titleBar, { BackgroundColor3 = "MainColor" })
    L:AddToRegistry(msgArea, { BackgroundColor3 = "BackgroundColor" })
    L:AddToRegistry(inputArea, { BackgroundColor3 = "MainColor" })
    L:AddToRegistry(tb, {
        BackgroundColor3 = "BackgroundColor",
        TextColor3 = "FontColor",
    })
    L:AddToRegistry(sendBtn, { BackgroundColor3 = "AccentColor" })
    L:AddToRegistry(sf, { ScrollBarImageColor3 = "AccentColor" })
end

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
            if self.OnlineLabel and self.OnlineLabel.Parent then
                self.OnlineLabel.Text = "● " .. tostring(#Players:GetPlayers()) .. " online"
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
                    Url = GlobalChat.FirebaseUrl .. GlobalChat.MessagesPath .. ".json?orderBy=\"$key\"&limitToLast=5",
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
                return (a.timestamp or 0) < (b.timestamp or 0)
            end)

            local now = os.time()
            for i = #msgs, 1, -1 do
                local m = msgs[i]
                if m.userId == pl.UserId and m.timestamp and (now - m.timestamp) < GlobalChat.BubbleDisplayTime then
                    Create3DBubble(pl, m.message, m.timestamp)
                    break
                end
            end
        end)
    end)
end

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
        Text = "Enable Global Chat",
        Default = false,
        Tooltip = "Open floating chat window",
        Callback = function(value)
            self.Enabled = value
            if value then
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
