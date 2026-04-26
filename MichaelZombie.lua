local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

local cfg = {
    ZombieESP = { Visible = false },
    HitboxExpander = { Enabled = false, Size = 10 },
    Zombie = {
        ShowBox    = true,
        ShowLine   = true,
        ShowName   = true,
        ShowHealth = true,
        BoxColor   = Color3.new(0, 1, 0),
        LineColor  = Color3.new(1, 0.5, 0),
        TextColor  = Color3.new(0, 1, 0),
    },
}

local espPool    = {}
local activeKeys = { zombie = {} }
local zombieData = {}
local frameCount = 0
local hitboxStore = {}

local function toScreen(pos)
    if not pos then return nil, false end
    if type(WorldToScreen) == "function" then
        local ok, scr, on = pcall(WorldToScreen, pos)
        if ok and scr then return scr, on end
    end
    local cam = workspace.CurrentCamera
    if cam then
        local ok, v, vis = pcall(function() return cam:WorldToViewportPoint(pos) end)
        if ok and v then return Vector2.new(v.X, v.Y), vis end
    end
    return nil, false
end

local function getPoolEntry(key)
    if espPool[key] then return espPool[key] end
    local entry = {}

    local box = Drawing.new("Square")
    box.Filled       = false
    box.Thickness    = 1
    box.Transparency = 1
    box.Color        = cfg.Zombie.BoxColor
    box.Visible      = false
    entry.box = box

    local label = Drawing.new("Text")
    label.Center       = true
    label.Outline      = true
    label.Font         = 2
    label.Size         = 13
    label.Transparency = 1
    label.Color        = cfg.Zombie.TextColor
    label.Visible      = false
    entry.label = label

    local healthLabel = Drawing.new("Text")
    healthLabel.Center       = true
    healthLabel.Outline      = true
    healthLabel.Font         = 2
    healthLabel.Size         = 12
    healthLabel.Transparency = 1
    healthLabel.Color        = Color3.new(1, 0, 0)
    healthLabel.Visible      = false
    entry.healthLabel = healthLabel

    local line = Drawing.new("Line")
    line.Thickness    = 1
    line.Transparency = 1
    line.Color        = cfg.Zombie.LineColor
    line.Visible      = false
    entry.line = line

    espPool[key] = entry
    return entry
end

local function hideEntry(entry)
    if not entry then return end
    if entry.box         then entry.box.Visible         = false end
    if entry.label       then entry.label.Visible       = false end
    if entry.healthLabel then entry.healthLabel.Visible = false end
    if entry.line        then entry.line.Visible        = false end
end

local function removeEntry(key)
    local entry = espPool[key]
    if not entry then return end
    hideEntry(entry)
    pcall(function()
        if entry.box         then entry.box:Remove()         end
        if entry.label       then entry.label:Remove()       end
        if entry.healthLabel then entry.healthLabel:Remove() end
        if entry.line        then entry.line:Remove()        end
    end)
    espPool[key] = nil
end

local function cleanupBucket(bucket, seen)
    for key in pairs(bucket) do
        if not seen[key] then
            hideEntry(espPool[key])
            bucket[key] = nil
        end
    end
end

local function getRootPart(model)
    if not model or not model:IsA("Model") then return nil end
    local hrp = model:FindFirstChild("HumanoidRootPart")
    if hrp then return hrp end
    local primary = model.PrimaryPart
    if primary then return primary end
    for _, child in ipairs(model:GetChildren()) do
        if child:IsA("BasePart") then return child end
    end
    return nil
end

local function getHumanoid(model)
    return model:FindFirstChildWhichIsA("Humanoid")
end

local function getHeadPart(model)
    local head = model:FindFirstChild("Head")
    if head and head:IsA("BasePart") then return head end
    for _, child in ipairs(model:GetChildren()) do
        if child:IsA("BasePart") and child.Name:lower() == "head" then
            return child
        end
    end
    return nil
end

local function applyHitbox(model)
    if not model or not model.Parent then return end
    local head = getHeadPart(model)
    if not head or not head.Parent then return end
    if hitboxStore[head] then return end
    local ok, origSize = pcall(function() return head.Size end)
    if not ok then return end
    hitboxStore[head] = origSize
    local s = cfg.HitboxExpander.Size
    pcall(function() head.Size = Vector3.new(s, s, s) end)
end

local function restoreHitbox(model)
    if not model then return end
    local head = getHeadPart(model)
    if not head then return end
    local orig = hitboxStore[head]
    if orig then
        if head.Parent then pcall(function() head.Size = orig end) end
        hitboxStore[head] = nil
    end
end

local function cleanHitboxStore()
    for part in pairs(hitboxStore) do
        if not part or not part.Parent then
            hitboxStore[part] = nil
        end
    end
end

local function restoreAllHitboxes()
    for part, origSize in pairs(hitboxStore) do
        if part and part.Parent then
            pcall(function() part.Size = origSize end)
        end
    end
    hitboxStore = {}
end

local function applyAllHitboxes()
    for _, data in pairs(zombieData) do
        if data.model and data.model.Parent then
            applyHitbox(data.model)
        end
    end
end

local function syncZombieColors()
    local zc = cfg.Zombie
    for key in pairs(zombieData) do
        local e = espPool[key]
        if e then
            if e.box   then e.box.Color   = zc.BoxColor  end
            if e.label then e.label.Color = zc.TextColor end
            if e.line  then e.line.Color  = zc.LineColor end
        end
    end
end

local function clearZombieKey(key)
    removeEntry(key)
    activeKeys.zombie[key] = nil
    zombieData[key] = nil
end

local function scanZombies()
    local ignore = workspace:FindFirstChild("Ignore")
    local zombieFolder = ignore and ignore:FindFirstChild("Zombies")

    cleanHitboxStore()

    if not zombieFolder then
        local dead = {}
        for key in pairs(zombieData) do dead[#dead + 1] = key end
        for _, key in ipairs(dead) do clearZombieKey(key) end
        return
    end

    local found = {}
    for _, zombie in ipairs(zombieFolder:GetChildren()) do
        if zombie and zombie:IsA("Model") then
            local root = getRootPart(zombie)
            if root then
                found[zombie] = true
                if not zombieData[zombie] then
                    zombieData[zombie] = { model = zombie, root = root, sizeCache = nil }
                    if cfg.HitboxExpander.Enabled then
                        applyHitbox(zombie)
                    end
                else
                    zombieData[zombie].root = root
                end
            end
        end
    end

    local dead = {}
    for key in pairs(zombieData) do
        if not found[key] or not key.Parent then
            dead[#dead + 1] = key
        end
    end
    for _, key in ipairs(dead) do clearZombieKey(key) end
end

local function updateZombieEsp(playerPos)
    if not cfg.ZombieESP.Visible then
        for key in pairs(activeKeys.zombie) do hideEntry(espPool[key]) end
        activeKeys.zombie = {}
        return
    end

    local seen = {}
    local zc   = cfg.Zombie
    local cam  = workspace.CurrentCamera
    local viewSize = cam and cam.ViewportSize or Vector2.new(1920, 1080)
    local screenCenterX = viewSize.X / 2
    local screenBottomY = viewSize.Y

    for key, data in pairs(zombieData) do
        local model = data.model
        local root  = data.root

        if not model or not model.Parent then
            hideEntry(espPool[key]); continue
        end

        if not root or not root.Parent then
            root = getRootPart(model)
            if not root then hideEntry(espPool[key]); continue end
            data.root = root
        end

        local ok, pos = pcall(function() return root.Position end)
        if not ok or not pos then hideEntry(espPool[key]); continue end

        local scr, onScr = toScreen(pos)
        if not scr or not onScr then hideEntry(espPool[key]); continue end

        seen[key]              = true
        activeKeys.zombie[key] = true
        local entry = getPoolEntry(key)

        local dist  = (playerPos - pos).Magnitude
        local hum   = getHumanoid(model)
        local hp    = hum and hum.Health    or 0
        local maxHp = hum and hum.MaxHealth or 100

        if zc.ShowBox then
            if not data.sizeCache then
                local ok2, sz = pcall(function() return root.Size end)
                data.sizeCache = ok2 and sz or Vector3.new(4, 5, 4)
            end
            local scale = math.clamp(1000 / math.max(dist, 1), 0.3, 8)
            local boxH  = math.floor(data.sizeCache.Y * 11 * scale / 10)
            local boxW  = math.floor(data.sizeCache.X * 5  * scale / 10)
            boxH = math.max(boxH, 20)
            boxW = math.max(boxW, 10)
            entry.box.Size     = Vector2.new(boxW, boxH)
            entry.box.Position = Vector2.new(scr.X - boxW / 2, scr.Y - boxH / 2)
            entry.box.Color    = zc.BoxColor
            entry.box.Visible  = true
        else
            entry.box.Visible = false
        end

        if zc.ShowName then
            entry.label.Text     = string.format("%s [%dm]", model.Name, math.floor(dist))
            entry.label.Position = Vector2.new(scr.X, scr.Y - 40)
            entry.label.Color    = zc.TextColor
            entry.label.Visible  = true
        else
            entry.label.Visible = false
        end

        if zc.ShowHealth and hum then
            local hpPct  = math.clamp(hp / math.max(maxHp, 1), 0, 1)
            entry.healthLabel.Text     = string.format("HP: %d/%d", math.floor(hp), math.floor(maxHp))
            entry.healthLabel.Position = Vector2.new(scr.X, scr.Y - 27)
            entry.healthLabel.Color    = Color3.new(1 - hpPct, hpPct, 0)
            entry.healthLabel.Visible  = true
        else
            entry.healthLabel.Visible = false
        end

        if zc.ShowLine then
            entry.line.From    = Vector2.new(screenCenterX, screenBottomY)
            entry.line.To      = Vector2.new(scr.X, scr.Y)
            entry.line.Color   = zc.LineColor
            entry.line.Visible = true
        else
            entry.line.Visible = false
        end
    end

    cleanupBucket(activeKeys.zombie, seen)
end

local loaderSource = game:HttpGet("https://raw.githubusercontent.com/shystemcito/ForMatcha-Testing/refs/heads/main/Libs/Loader.luau")
local fn, compErr = loadstring("MatchaLib = (function()\n" .. loaderSource .. "\nend)()")
if not fn then error("COMPILE ERROR: " .. tostring(compErr)) return end
fn()
local UiLib = MatchaLib.load("MatchaUI")

local Window = UiLib.CreateWindow({
    Title  = "Zombie Tracker",
    X      = 500,
    Y      = 100,
    Width  = 560,
    Height = 620,
    ZIndex = 100,
})

local catESP    = Window.AddCategory("ESP")
local catHitbox = Window.AddCategory("Hitbox")
local catDebug  = Window.AddCategory("Debug")

local function buildESPTab()
    Window.AddSection(catESP, "Zombie ESP")

    Window.AddToggle(catESP, "Zombie ESP", cfg.ZombieESP.Visible, function(state)
        cfg.ZombieESP.Visible = state
        UiLib.Notify(state and "Zombie ESP ON" or "Zombie ESP OFF", "", 2)
        if state then
            scanZombies()
        else
            for key in pairs(activeKeys.zombie) do hideEntry(espPool[key]) end
        end
    end)

    Window.AddSection(catESP, "Toggles")

    Window.AddToggle(catESP, "Box", cfg.Zombie.ShowBox, function(state)
        cfg.Zombie.ShowBox = state
        if not state then
            for _, e in pairs(espPool) do if e.box then e.box.Visible = false end end
        end
    end)

    Window.AddToggle(catESP, "Direction Line", cfg.Zombie.ShowLine, function(state)
        cfg.Zombie.ShowLine = state
        if not state then
            for _, e in pairs(espPool) do if e.line then e.line.Visible = false end end
        end
    end)

    Window.AddToggle(catESP, "Name & Distance", cfg.Zombie.ShowName, function(state)
        cfg.Zombie.ShowName = state
        if not state then
            for _, e in pairs(espPool) do if e.label then e.label.Visible = false end end
        end
    end)

    Window.AddToggle(catESP, "Health", cfg.Zombie.ShowHealth, function(state)
        cfg.Zombie.ShowHealth = state
        if not state then
            for _, e in pairs(espPool) do if e.healthLabel then e.healthLabel.Visible = false end end
        end
    end)

    Window.AddSection(catESP, "Colors")

    Window.AddColorPicker(catESP, "Box Color", cfg.Zombie.BoxColor, function(c)
        cfg.Zombie.BoxColor = c
        syncZombieColors()
    end)

    Window.AddColorPicker(catESP, "Line Color", cfg.Zombie.LineColor, function(c)
        cfg.Zombie.LineColor = c
        syncZombieColors()
    end)

    Window.AddColorPicker(catESP, "Text Color", cfg.Zombie.TextColor, function(c)
        cfg.Zombie.TextColor = c
        syncZombieColors()
    end)
end

local function buildHitboxTab()
    Window.AddSection(catHitbox, "Head Hitbox Expander")

    Window.AddToggle(catHitbox, "Hitbox Expander", cfg.HitboxExpander.Enabled, function(state)
        cfg.HitboxExpander.Enabled = state
        if state then
            applyAllHitboxes()
            UiLib.Notify("Hitbox ON", string.format("Head size: %.0f", cfg.HitboxExpander.Size), 2)
        else
            restoreAllHitboxes()
            UiLib.Notify("Hitbox OFF", "Original sizes restored", 2)
        end
    end)

    Window.AddSection(catHitbox, "Size")

    Window.AddSlider(catHitbox, "Head Size (studs)", 2, 50, cfg.HitboxExpander.Size, function(v)
        cfg.HitboxExpander.Size = v
        if cfg.HitboxExpander.Enabled then
            restoreAllHitboxes()
            applyAllHitboxes()
        end
    end)

    Window.AddSection(catHitbox, "Info")
    Window.AddSection(catHitbox, "Expands zombie head hitbox only.")
    Window.AddSection(catHitbox, "Sizes restore on toggle OFF or rescan.")
end

local function buildDebugTab()
    Window.AddSection(catDebug, "Scan")

    Window.AddButton(catDebug, "Rescan Zombies", function()
        local before = 0
        for _ in pairs(zombieData) do before = before + 1 end
        scanZombies()
        local after = 0
        for _ in pairs(zombieData) do after = after + 1 end
        printl(string.format("[ZombieESP] Rescan: %d -> %d", before, after))
        UiLib.Notify(string.format("Rescanned: %d zombie(s)", after), "", 3)
    end)

    Window.AddButton(catDebug, "List Active Zombies", function()
        local count = 0
        local char  = LocalPlayer.Character
        local hrp   = char and char:FindFirstChild("HumanoidRootPart")
        for key, data in pairs(zombieData) do
            if data.root and data.root.Parent then
                local p = data.root.Position
                local d = hrp and (p - hrp.Position).Magnitude or 0
                printl(string.format("  %s | %.0fm | %.0f, %.0f, %.0f",
                    tostring(key), d, p.X, p.Y, p.Z))
                count = count + 1
            end
        end
        printl("[ZombieESP] Total tracked: " .. count)
        UiLib.Notify(count .. " zombie(s) tracked", "Check console", 3)
    end)

    Window.AddSection(catDebug, "Hitbox")

    Window.AddButton(catDebug, "Restore All Hitboxes", function()
        restoreAllHitboxes()
        UiLib.Notify("Hitboxes Restored", "All head sizes reset", 2)
    end)

    Window.AddButton(catDebug, "List Hitbox Store", function()
        local count = 0
        for part, orig in pairs(hitboxStore) do
            printl(string.format("  [HB] %s -> orig: %.1f %.1f %.1f | cur: %.1f",
                part.Name, orig.X, orig.Y, orig.Z, part.Size.X))
            count = count + 1
        end
        printl("[HB] Total expanded: " .. count)
        UiLib.Notify(count .. " head(s) expanded", "", 2)
    end)
end

buildESPTab()
buildHitboxTab()
buildDebugTab()

Window.AddConfigPreset({})

printl("[Zombie Tracker] Loaded")

RunService.Heartbeat:Connect(function()
    if not isrbxactive() then return end
    frameCount = frameCount + 1
    if frameCount % 4 ~= 0 then return end

    local char = LocalPlayer.Character
    local hrp  = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end

    pcall(updateZombieEsp, hrp.Position)
end)

task.spawn(function()
    local scanFrame = 0
    while true do
        pcall(function()
            if isrbxactive() then
                scanFrame = scanFrame + 1
                if scanFrame % 30 == 0 then
                    scanZombies()
                end
            end
        end)
        task.wait(1 / 60)
    end
end)

UiLib.Notify("Zombie Tracker", "Loaded successfully", 4)
UiLib.Run()
