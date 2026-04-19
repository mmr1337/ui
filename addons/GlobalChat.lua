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

local request = (syn and syn.request)
    or (http and http.request)
    or http_request
    or (Fluxus and Fluxus.request)
    or request

local thumbnailCache   = {}
local messageHistory   = {}
local displayedBubbles = {}
local lastFetchTime    = 0
local pollingStarted   = false

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
    local url = ok and result or "rbxassetid://5107154082"
    thumbnailCache[userId] = url
    return url
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

    --// gamesense style bubble: тёмный фон, accent border
    local Bg = New("Frame", {
        Size             = UDim2.fromScale(1, 1),
        BackgroundColor3 = Color3.fromRGB(12, 12, 12),
        BorderSizePixel  = 0,
        Parent           = Board,
    })

    --// Accent left line
    New("Frame", {
        BackgroundColor3 = L and L.Scheme.AccentColor or Color3.fromRGB(100, 200, 100),
        Size             = UDim2.new(0, 2, 1, 0),
        BorderSizePixel  = 0,
        Parent           = Bg,
    })

    --// Outline
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

    --// gamesense style row
    local Row = New("Frame", {
        BackgroundColor3 = L.Scheme.MainColor,
        BorderSizePixel  = 0,
        Size             = UDim2.new(1, 0, 0, 48),
        LayoutOrder      = data.timestamp,
        Parent           = SF,
    })

    --// Accent left border
    New("Frame", {
        BackgroundColor3 = L.Scheme.AccentColor,
        Size             = UDim2.new(0, 2, 1, 0),
        BorderSizePixel  = 0,
        Parent           = Row,
    })

    --// Bottom divider line
    New("Frame", {
        BackgroundColor3 = L.Scheme.OutlineColor,
        AnchorPoint      = Vector2.new(0, 1),
        Position         = UDim2.fromScale(0, 1),
        Size             = UDim2.new(1, 0, 0, 1),
        BorderSizePixel  = 0,
        Parent           = Row,
    })

    --// Avatar
    local Av = New("ImageLabel", {
        BackgroundColor3 = L.Scheme.BackgroundColor,
        Position         = UDim2.fromOffset(8, 4),
        Size             = UDim2.fromOffset(40, 40),
        Image            = GetThumbnail(data.userId),
        BorderSizePixel  = 0,
        Parent           = Row,
    })

    New("UIStroke", {
        Color           = L.Scheme.OutlineColor,
        Thickness       = 1,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
        Parent          = Av,
    })

    --// Name label — accent color
    New("TextLabel", {
        BackgroundTransparency = 1,
        Position         = UDim2.fromOffset(54, 5),
        Size             = UDim2.new(1, -58, 0, 16),
        Text             = data.displayName .. " (@" .. data.username .. ")",
        TextColor3       = L.Scheme.AccentColor,
        TextSize         = 12,
        Font             = Enum.Font.Code,
        TextXAlignment   = Enum.TextXAlignment.Left,
        TextTruncate     = Enum.TextTruncate.AtEnd,
        Parent           = Row,
    })

    --// Message text
    New("TextLabel", {
        BackgroundTransparency = 1,
        Position         = UDim2.fromOffset(54, 22),
        Size             = UDim2.new(1, -58, 0, 22),
        Text             = data.message,
        TextColor3       = Color3.fromRGB(200, 200, 200),
        TextSize         = 13,
        Font             = Enum.Font.Code,
        TextXAlignment   = Enum.TextXAlignment.Left,
        TextWrapped      = true,
        ClipsDescendants = true,
        Parent           = Row,
    })

    --// Trim old rows
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

-- ─── Firebase ────────────────────────────────────────────────────────────────

function GlobalChat:SendMessage(message)
    if not request then return end
    local LP = Players.LocalPlayer
    local data = {
        userId      = LP.UserId,
        username    = LP.Name,
        displayName = LP.DisplayName,
        message     = message,
        timestamp   = os.time(),
        gameId      = game.PlaceId,
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

-- ─── Chat Window ─────────────────────────────────────────────────────────────

function GlobalChat:CreateWindow()
    local L = self.Library
    if not L then return end

    --// Создаём отдельный ScreenGui
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

    --// UIScale — берём из либы
    local Scale = Instance.new("UIScale")
    Scale.Scale  = L.DPIScale
    Scale.Parent = SG
    table.insert(L.Scales, Scale)

    --// Основной фрейм окна чата — gamesense стиль
    local ChatFrame = New("Frame", {
        BackgroundColor3 = L.Scheme.BackgroundColor,
        BorderSizePixel  = 0,
        Position         = UDim2.new(1, -375, 1, -310),
        Size             = UDim2.fromOffset(360, 300),
        Parent           = SG,
    })

    if L.IsMobile then
        ChatFrame.Size     = UDim2.fromOffset(320, 260)
        ChatFrame.Position = UDim2.fromOffset(6, 6)
    end

    --// Outline
    New("UIStroke", {
        Color           = L.Scheme.OutlineColor,
        Thickness       = 1,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
        Parent          = ChatFrame,
    })

    --// Accent top line
    New("Frame", {
        BackgroundColor3 = L.Scheme.AccentColor,
        Size             = UDim2.new(1, 0, 0, 2),
        BorderSizePixel  = 0,
        ZIndex           = 2,
        Parent           = ChatFrame,
    })

    --// Title bar
    local TitleBar = New("Frame", {
        BackgroundColor3 = L.Scheme.MainColor,
        BorderSizePixel  = 0,
        Size             = UDim2.new(1, 0, 0, 28),
        Parent           = ChatFrame,
    })

    --// Bottom line под title
    New("Frame", {
        BackgroundColor3 = L.Scheme.OutlineColor,
        AnchorPoint      = Vector2.new(0, 1),
        Position         = UDim2.fromScale(0, 1),
        Size             = UDim2.new(1, 0, 0, 1),
        BorderSizePixel  = 0,
        Parent           = TitleBar,
    })

    --// Title label
    New("TextLabel", {
        BackgroundTransparency = 1,
        Size             = UDim2.new(1, -40, 1, 0),
        Position         = UDim2.fromOffset(8, 0),
        Text             = "Global Chat",
        TextColor3       = L.Scheme.FontColor,
        TextSize         = 13,
        Font             = Enum.Font.Code,
        TextXAlignment   = Enum.TextXAlignment.Left,
        Parent           = TitleBar,
    })

    --// Online count label
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

    --// Draggable за title bar
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

    --// Messages area
    local MsgArea = New("Frame", {
        BackgroundColor3 = L.Scheme.BackgroundColor,
        BorderSizePixel  = 0,
        Position         = UDim2.fromOffset(0, 29),
        Size             = UDim2.new(1, 0, 1, -75),
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

    --// Автопрокрутка вниз
    Layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        SF.CanvasPosition = Vector2.new(0, SF.AbsoluteCanvasSize.Y)
    end)

    --// Input area
    local InputArea = New("Frame", {
        BackgroundColor3 = L.Scheme.MainColor,
        BorderSizePixel  = 0,
        AnchorPoint      = Vector2.new(0, 1),
        Position         = UDim2.fromScale(0, 1),
        Size             = UDim2.new(1, 0, 0, 44),
        Parent           = ChatFrame,
    })

    --// Top line над инпутом
    New("Frame", {
        BackgroundColor3 = L.Scheme.OutlineColor,
        Size             = UDim2.new(1, 0, 0, 1),
        BorderSizePixel  = 0,
        Parent           = InputArea,
    })

    --// TextBox
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

    --// Send button — accent цвет как gamesense кнопка
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

    --// Hover эффект на кнопку
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

    --// Send logic
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

    --// Сохраняем ссылки
    self.ChatWindow  = ChatFrame
    self.ScrollFrame = SF
    self.TextBox     = TB
    self.SendButton  = SendBtn
    self.OnlineLabel = OnlineLabel

    --// Registry для автообновления цветов
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

    --// Fetch loop
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

    --// Синхронизация видимости с основным меню
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

    --// Обновление онлайн счётчика
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

    --// Cleanup старых bubbles
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

    --// Bubble для новых игроков
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
