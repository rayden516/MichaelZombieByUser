local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

local cfg = {
    ZombieESP     = { Visible = false },
    MysteryBoxESP = { Visible = false },
    WallBuyESP    = { Visible = false },
    PerkESP       = { Visible = false },
    NoCollide     = { Enabled = false },
    HitboxExpander = { Enabled = false, Size = 6 },
    Zombie = {
        ShowBox    = true,
        ShowLine   = true,
        ShowName   = true,
        ShowHealth = true,
        BoxColor   = Color3.new(0, 1, 0),
        LineColor  = Color3.new(1, 0.5, 0),
        TextColor  = Color3.new(0, 1, 0),
    },
    MysteryBox = {
        ShowBox   = true,
        ShowLine  = true,
        ShowName  = true,
        BoxColor  = Color3.new(1, 0, 1),
        LineColor = Color3.new(1, 1, 0),
        TextColor = Color3.new(1, 0, 1),
    },
    WallBuy = {
        BoxColor  = Color3.fromRGB(100, 160, 220),
        TextColor = Color3.fromRGB(150, 195, 240),
    },
    Perk = {
        BoxColor  = Color3.fromRGB(200, 130, 255),
        TextColor = Color3.fromRGB(220, 170, 255),
    },
}

local espPool    = {}
local activeKeys = { zombie = {}, mysteryBox = {}, wallBuy = {}, perk = {} }
local zombieData     = {}
local mysteryBoxData = {}
local wallBuyData    = {}
local perkData       = {}
local hitboxStore    = {}

local hasWorldToScreen    = type(WorldToScreen) == "function"
local cachedCam           = workspace.CurrentCamera
local cachedScreenCenterX = 960
local cachedScreenBottomY = 1080

local function updateViewportCache()
    cachedCam = workspace.CurrentCamera
    local vs = cachedCam and cachedCam.ViewportSize or Vector2.new(1920, 1080)
    cachedScreenCenterX = vs.X / 2
    cachedScreenBottomY = vs.Y
end

updateViewportCache()

local function toScreen(pos)
    if not pos then return nil, false end
    if hasWorldToScreen then
        local ok, scr, on = pcall(WorldToScreen, pos)
        if ok and scr then return scr, on end
    end
    if cachedCam then
        local ok, v, vis = pcall(cachedCam.WorldToViewportPoint, cachedCam, pos)
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
    local ok2, origCollide = pcall(function() return head.CanCollide end)
    local ok3, origTransparency = pcall(function() return head.Transparency end)
    hitboxStore[head] = {
        size         = origSize,
        collide      = ok2 and origCollide or true,
        transparency = ok3 and origTransparency or 0,
    }
    local s = cfg.HitboxExpander.Size
    pcall(function() head.Size = Vector3.new(s, s, s) end)
    pcall(function() head.CanCollide = false end)
    pcall(function() head.Transparency = 1 end)
end

local function restoreHitbox(model)
    if not model then return end
    local head = getHeadPart(model)
    if not head then return end
    local orig = hitboxStore[head]
    if orig then
        if head.Parent then
            pcall(function() head.Size = orig.size end)
            pcall(function() head.CanCollide = orig.collide end)
            pcall(function() head.Transparency = orig.transparency end)
        end
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
    for part, orig in pairs(hitboxStore) do
        if part and part.Parent then
            pcall(function() part.Size = orig.size end)
            pcall(function() part.CanCollide = orig.collide end)
            pcall(function() part.Transparency = orig.transparency end)
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

local function applyZombieNoCollide()
    for _, data in pairs(zombieData) do
        if data.model and data.model.Parent then
            for _, part in ipairs(data.model:GetDescendants()) do
                if part:IsA("BasePart") and part.Name ~= "Head" then
                    pcall(function() part.CanCollide = false end)
                end
            end
        end
    end
end

local function restoreZombieCollide()
    for _, data in pairs(zombieData) do
        if data.model and data.model.Parent then
            for _, part in ipairs(data.model:GetDescendants()) do
                if part:IsA("BasePart") and part.Name ~= "Head" then
                    pcall(function() part.CanCollide = true end)
                end
            end
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
                    zombieData[zombie] = {
                        model     = zombie,
                        root      = root,
                        sizeCache = nil,
                        hum       = getHumanoid(zombie),
                        lastDist  = nil,
                        lastHp    = nil,
                        lastMaxHp = nil,
                    }
                    if cfg.HitboxExpander.Enabled then applyHitbox(zombie) end
                    if cfg.NoCollide.Enabled then
                        for _, part in ipairs(zombie:GetDescendants()) do
                            if part:IsA("BasePart") and part.Name ~= "Head" then
                                pcall(function() part.CanCollide = false end)
                            end
                        end
                    end
                else
                    zombieData[zombie].root = root
                    if not zombieData[zombie].hum or not zombieData[zombie].hum.Parent then
                        zombieData[zombie].hum = getHumanoid(zombie)
                    end
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
    for key, data in pairs(zombieData) do
        local model = data.model
        local root  = data.root
        if not model or not model.Parent then
            hideEntry(espPool[key])
        else
            if not root or not root.Parent then
                root = getRootPart(model)
                data.root = root
            end
            if not root then
                hideEntry(espPool[key])
            else
                local pos = root.Position
                local scr, onScr = toScreen(pos)
                if not scr or not onScr then
                    hideEntry(espPool[key])
                else
                    seen[key]              = true
                    activeKeys.zombie[key] = true
                    local entry = getPoolEntry(key)
                    local scrX, scrY = scr.X, scr.Y
                    local dist = (playerPos - pos).Magnitude
                    local hum  = data.hum
                    if not hum or not hum.Parent then
                        hum = getHumanoid(model)
                        data.hum = hum
                    end
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
                        entry.box.Position = Vector2.new(scrX - boxW / 2, scrY - boxH / 2)
                        entry.box.Color    = zc.BoxColor
                        entry.box.Visible  = true
                    else
                        entry.box.Visible = false
                    end
                    if zc.ShowName then
                        local floorDist = math.floor(dist)
                        if floorDist ~= data.lastDist then
                            data.lastDist = floorDist
                            entry.label.Text = string.format("%s [%dm]", model.Name, floorDist)
                        end
                        entry.label.Position = Vector2.new(scrX, scrY - 40)
                        entry.label.Color    = zc.TextColor
                        entry.label.Visible  = true
                    else
                        entry.label.Visible = false
                    end
                    if zc.ShowHealth and hum then
                        local floorHp    = math.floor(hp)
                        local floorMaxHp = math.floor(maxHp)
                        if floorHp ~= data.lastHp or floorMaxHp ~= data.lastMaxHp then
                            data.lastHp    = floorHp
                            data.lastMaxHp = floorMaxHp
                            entry.healthLabel.Text = string.format("HP: %d/%d", floorHp, floorMaxHp)
                        end
                        local hpPct = math.clamp(hp / math.max(maxHp, 1), 0, 1)
                        entry.healthLabel.Position = Vector2.new(scrX, scrY - 27)
                        entry.healthLabel.Color    = Color3.new(1 - hpPct, hpPct, 0)
                        entry.healthLabel.Visible  = true
                    else
                        entry.healthLabel.Visible = false
                    end
                    if zc.ShowLine then
                        entry.line.From    = Vector2.new(cachedScreenCenterX, cachedScreenBottomY)
                        entry.line.To      = Vector2.new(scrX, scrY)
                        entry.line.Color   = zc.LineColor
                        entry.line.Visible = true
                    else
                        entry.line.Visible = false
                    end
                end
            end
        end
    end
    cleanupBucket(activeKeys.zombie, seen)
end

local function scanMysteryBoxes()
    local mapComponents = workspace:FindFirstChild("_MapComponents")
    local mysteryBox = mapComponents and mapComponents:FindFirstChild("MysteryBox")
    if not mysteryBox or not mysteryBox:IsA("Model") then
        local dead = {}
        for key in pairs(mysteryBoxData) do dead[#dead + 1] = key end
        for _, key in ipairs(dead) do
            removeEntry(key)
            activeKeys.mysteryBox[key] = nil
            mysteryBoxData[key] = nil
        end
        return
    end
    local found = {}
    local rootLoc = mysteryBox:FindFirstChild("PurchaseBox")
        or mysteryBox.PrimaryPart
        or mysteryBox:FindFirstChildWhichIsA("BasePart")
    if rootLoc then
        found[mysteryBox] = true
        if not mysteryBoxData[mysteryBox] then
            mysteryBoxData[mysteryBox] = { model = mysteryBox, root = rootLoc, lastDist = nil }
        else
            mysteryBoxData[mysteryBox].root = rootLoc
        end
    end
    local dead = {}
    for key in pairs(mysteryBoxData) do
        if not found[key] or not key.Parent then dead[#dead + 1] = key end
    end
    for _, key in ipairs(dead) do
        removeEntry(key)
        activeKeys.mysteryBox[key] = nil
        mysteryBoxData[key] = nil
    end
end

local function updateMysteryBoxEsp(playerPos)
    if not cfg.MysteryBoxESP.Visible then
        for key in pairs(activeKeys.mysteryBox) do hideEntry(espPool[key]) end
        activeKeys.mysteryBox = {}
        return
    end
    local seen = {}
    local mc   = cfg.MysteryBox
    for key, data in pairs(mysteryBoxData) do
        local model = data.model
        local root  = data.root
        if not model or not model.Parent then
            hideEntry(espPool[key])
        else
            if not root or not root.Parent then
                root = model:FindFirstChild("RootLocation")
                data.root = root
            end
            if not root then
                hideEntry(espPool[key])
            else
                local pos = root.Position
                local scr, onScr = toScreen(pos)
                if not scr or not onScr then
                    hideEntry(espPool[key])
                else
                    seen[key]                  = true
                    activeKeys.mysteryBox[key] = true
                    local entry = getPoolEntry(key)
                    local scrX, scrY = scr.X, scr.Y
                    local dist = (playerPos - pos).Magnitude
                    if mc.ShowBox then
                        local scale = math.clamp(1000 / math.max(dist, 1), 0.3, 8)
                        local boxH  = math.max(math.floor(30 * scale / 10), 20)
                        local boxW  = math.max(math.floor(20 * scale / 10), 14)
                        entry.box.Size     = Vector2.new(boxW, boxH)
                        entry.box.Position = Vector2.new(scrX - boxW / 2, scrY - boxH / 2)
                        entry.box.Color    = mc.BoxColor
                        entry.box.Visible  = true
                    else
                        entry.box.Visible = false
                    end
                    if mc.ShowName then
                        local floorDist = math.floor(dist)
                        if floorDist ~= data.lastDist then
                            data.lastDist = floorDist
                            entry.label.Text = string.format("Mystery Box [%dm]", floorDist)
                        end
                        entry.label.Position = Vector2.new(scrX, scrY - 30)
                        entry.label.Color    = mc.TextColor
                        entry.label.Visible  = true
                    else
                        entry.label.Visible = false
                    end
                    entry.healthLabel.Visible = false
                    if mc.ShowLine then
                        entry.line.From    = Vector2.new(cachedScreenCenterX, cachedScreenBottomY)
                        entry.line.To      = Vector2.new(scrX, scrY)
                        entry.line.Color   = mc.LineColor
                        entry.line.Visible = true
                    else
                        entry.line.Visible = false
                    end
                end
            end
        end
    end
    cleanupBucket(activeKeys.mysteryBox, seen)
end

local function scanWallBuys()
    local folder = workspace:FindFirstChild("_WallBuys")
    if not folder then
        for key in pairs(wallBuyData) do
            hideEntry(espPool[key])
            activeKeys.wallBuy[key] = nil
            wallBuyData[key] = nil
        end
        return
    end
    local found = {}
    for _, gun in ipairs(folder:GetChildren()) do
        if gun and gun:IsA("Model") then
            local part = gun:FindFirstChild("PurchaseWallGun")
            if part and part:IsA("BasePart") then
                found[part] = true
                if not wallBuyData[part] then
                    wallBuyData[part] = { name = gun.Name, part = part, lastDist = nil }
                end
            end
        end
    end
    for key in pairs(wallBuyData) do
        if not found[key] or not key.Parent then
            hideEntry(espPool[key])
            activeKeys.wallBuy[key] = nil
            wallBuyData[key] = nil
        end
    end
end

local function updateWallBuyEsp(playerPos)
    if not cfg.WallBuyESP.Visible then
        for key in pairs(activeKeys.wallBuy) do hideEntry(espPool[key]) end
        activeKeys.wallBuy = {}
        return
    end
    local seen = {}
    local wc   = cfg.WallBuy
    for key, data in pairs(wallBuyData) do
        local part = data.part
        if not part or not part.Parent then
            hideEntry(espPool[key])
            activeKeys.wallBuy[key] = nil
            wallBuyData[key] = nil
        else
            local pos = part.Position
            local scr, onScr = toScreen(pos)
            if not scr or not onScr then
                hideEntry(espPool[key])
            else
                seen[key] = true
                activeKeys.wallBuy[key] = true
                local entry = getPoolEntry(key)
                local scrX, scrY = scr.X, scr.Y
                local dist  = (playerPos - pos).Magnitude
                local scale = math.clamp(500 / math.max(dist, 1), 0.2, 4)
                local boxW  = math.max(math.floor(20 * scale), 10)
                local boxH  = math.max(math.floor(26 * scale), 12)
                entry.box.Size     = Vector2.new(boxW, boxH)
                entry.box.Position = Vector2.new(scrX - boxW / 2, scrY - boxH / 2)
                entry.box.Color    = wc.BoxColor
                entry.box.Visible  = true
                local floorDist = math.floor(dist)
                if floorDist ~= data.lastDist then
                    data.lastDist = floorDist
                    entry.label.Text = string.format("%s [%dm]", data.name, floorDist)
                end
                entry.label.Position    = Vector2.new(scrX, scrY - boxH / 2 - 14)
                entry.label.Color       = wc.TextColor
                entry.label.Visible     = true
                entry.healthLabel.Visible = false
                entry.line.Visible        = false
            end
        end
    end
    cleanupBucket(activeKeys.wallBuy, seen)
end

local function scanPerkMachines()
    local folder = workspace:FindFirstChild("_PerkMachines")
    if not folder then
        for key in pairs(perkData) do
            hideEntry(espPool[key])
            activeKeys.perk[key] = nil
            perkData[key] = nil
        end
        return
    end
    local found = {}
    for _, machine in ipairs(folder:GetChildren()) do
        if machine and machine:IsA("Model") then
            local part = machine.PrimaryPart or machine:FindFirstChildWhichIsA("BasePart")
            if part then
                found[part] = true
                if not perkData[part] then
                    perkData[part] = { name = machine.Name, part = part, lastDist = nil }
                end
            end
        end
    end
    for key in pairs(perkData) do
        if not found[key] or not key.Parent then
            hideEntry(espPool[key])
            activeKeys.perk[key] = nil
            perkData[key] = nil
        end
    end
end

local function updatePerkEsp(playerPos)
    if not cfg.PerkESP.Visible then
        for key in pairs(activeKeys.perk) do hideEntry(espPool[key]) end
        activeKeys.perk = {}
        return
    end
    local seen = {}
    local pc   = cfg.Perk
    for key, data in pairs(perkData) do
        local part = data.part
        if not part or not part.Parent then
            hideEntry(espPool[key])
            activeKeys.perk[key] = nil
            perkData[key] = nil
        else
            local pos = part.Position
            local scr, onScr = toScreen(pos)
            if not scr or not onScr then
                hideEntry(espPool[key])
            else
                seen[key] = true
                activeKeys.perk[key] = true
                local entry = getPoolEntry(key)
                local scrX, scrY = scr.X, scr.Y
                local dist  = (playerPos - pos).Magnitude
                local scale = math.clamp(500 / math.max(dist, 1), 0.2, 4)
                local boxW  = math.max(math.floor(28 * scale), 12)
                local boxH  = math.max(math.floor(36 * scale), 14)
                entry.box.Size     = Vector2.new(boxW, boxH)
                entry.box.Position = Vector2.new(scrX - boxW / 2, scrY - boxH / 2)
                entry.box.Color    = pc.BoxColor
                entry.box.Visible  = true
                local floorDist = math.floor(dist)
                if floorDist ~= data.lastDist then
                    data.lastDist = floorDist
                    entry.label.Text = string.format("%s [%dm]", data.name, floorDist)
                end
                entry.label.Position    = Vector2.new(scrX, scrY - boxH / 2 - 14)
                entry.label.Color       = pc.TextColor
                entry.label.Visible     = true
                entry.healthLabel.Visible = false
                entry.line.Visible        = false
            end
        end
    end
    cleanupBucket(activeKeys.perk, seen)
end

local function BuildESP(Tab)
    local zc = cfg.Zombie
    local S = Tab:Section("ESP", "Left")
    S:Toggle("ZombieESP", "Zombie ESP", cfg.ZombieESP.Visible, function(state)
        cfg.ZombieESP.Visible = state
        notify(state and "Zombie ESP ON" or "Zombie ESP OFF", "", 2)
        if state then
            scanZombies()
        else
            for key in pairs(activeKeys.zombie) do hideEntry(espPool[key]) end
        end
    end)
    S:Spacing()
    S:Toggle("ZombieBox", "Box", zc.ShowBox, function(state)
        zc.ShowBox = state
        if not state then
            for _, e in pairs(espPool) do if e.box then e.box.Visible = false end end
        end
    end)
    S:Toggle("ZombieLine", "Direction Line", zc.ShowLine, function(state)
        zc.ShowLine = state
        if not state then
            for _, e in pairs(espPool) do if e.line then e.line.Visible = false end end
        end
    end)
    S:Toggle("ZombieName", "Name & Distance", zc.ShowName, function(state)
        zc.ShowName = state
        if not state then
            for _, e in pairs(espPool) do if e.label then e.label.Visible = false end end
        end
    end)
    S:Toggle("ZombieHealth", "Health", zc.ShowHealth, function(state)
        zc.ShowHealth = state
        if not state then
            for _, e in pairs(espPool) do if e.healthLabel then e.healthLabel.Visible = false end end
        end
    end)
end

local function BuildZombieColors(Tab)
    local zc = cfg.Zombie
    local S = Tab:Section("Zombie Colors", "Left")
    S:Text("Box Color")
    S:ColorPicker("ZBoxColor", zc.BoxColor.R, zc.BoxColor.G, zc.BoxColor.B, 1, function(c)
        zc.BoxColor = c
        syncZombieColors()
    end)
    S:Spacing()
    S:Text("Line Color")
    S:ColorPicker("ZLineColor", zc.LineColor.R, zc.LineColor.G, zc.LineColor.B, 1, function(c)
        zc.LineColor = c
        syncZombieColors()
    end)
    S:Spacing()
    S:Text("Text Color")
    S:ColorPicker("ZTextColor", zc.TextColor.R, zc.TextColor.G, zc.TextColor.B, 1, function(c)
        zc.TextColor = c
        syncZombieColors()
    end)
end

local function BuildMysteryBox(Tab)
    local mc = cfg.MysteryBox
    local S = Tab:Section("Mystery Box ESP", "Right")
    S:Toggle("MysteryBoxESP", "Mystery Box ESP", cfg.MysteryBoxESP.Visible, function(state)
        cfg.MysteryBoxESP.Visible = state
        notify(state and "Mystery Box ESP ON" or "Mystery Box ESP OFF", "", 2)
        if state then
            scanMysteryBoxes()
        else
            for key in pairs(activeKeys.mysteryBox) do hideEntry(espPool[key]) end
        end
    end)
    S:Spacing()
    S:Toggle("MBBox", "Box", mc.ShowBox, function(state) mc.ShowBox = state end)
    S:Toggle("MBLine", "Direction Line", mc.ShowLine, function(state) mc.ShowLine = state end)
    S:Toggle("MBName", "Name & Distance", mc.ShowName, function(state) mc.ShowName = state end)
end

local function BuildMysteryBoxColors(Tab)
    local mc = cfg.MysteryBox
    local S = Tab:Section("Mystery Box Colors", "Right")
    S:Text("Box Color")
    S:ColorPicker("MBBoxColor", mc.BoxColor.R, mc.BoxColor.G, mc.BoxColor.B, 1, function(c)
        mc.BoxColor = c
    end)
    S:Spacing()
    S:Text("Line Color")
    S:ColorPicker("MBLineColor", mc.LineColor.R, mc.LineColor.G, mc.LineColor.B, 1, function(c)
        mc.LineColor = c
    end)
    S:Spacing()
    S:Text("Text Color")
    S:ColorPicker("MBTextColor", mc.TextColor.R, mc.TextColor.G, mc.TextColor.B, 1, function(c)
        mc.TextColor = c
    end)
end

local function BuildWallBuyESP(Tab)
    local wc = cfg.WallBuy
    local S = Tab:Section("Wall Buy ESP", "Left")
    S:Toggle("WallBuyESP", "Wall Buy ESP", cfg.WallBuyESP.Visible, function(state)
        cfg.WallBuyESP.Visible = state
        notify(state and "Wall Buy ESP ON" or "Wall Buy ESP OFF", "", 2)
        if state then
            scanWallBuys()
        else
            for key in pairs(activeKeys.wallBuy) do hideEntry(espPool[key]) end
            activeKeys.wallBuy = {}
        end
    end)
    S:Spacing()
    S:Text("Box Color")
    S:ColorPicker("WBBoxColor", wc.BoxColor.R, wc.BoxColor.G, wc.BoxColor.B, 1, function(c)
        wc.BoxColor = c
    end)
    S:Spacing()
    S:Text("Text Color")
    S:ColorPicker("WBTextColor", wc.TextColor.R, wc.TextColor.G, wc.TextColor.B, 1, function(c)
        wc.TextColor = c
    end)
end

local function BuildPerkESP(Tab)
    local pc = cfg.Perk
    local S = Tab:Section("Perk Machine ESP", "Right")
    S:Toggle("PerkESP", "Perk Machine ESP", cfg.PerkESP.Visible, function(state)
        cfg.PerkESP.Visible = state
        notify(state and "Perk ESP ON" or "Perk ESP OFF", "", 2)
        if state then
            scanPerkMachines()
        else
            for key in pairs(activeKeys.perk) do hideEntry(espPool[key]) end
            activeKeys.perk = {}
        end
    end)
    S:Spacing()
    S:Text("Box Color")
    S:ColorPicker("PKBoxColor", pc.BoxColor.R, pc.BoxColor.G, pc.BoxColor.B, 1, function(c)
        pc.BoxColor = c
    end)
    S:Spacing()
    S:Text("Text Color")
    S:ColorPicker("PKTextColor", pc.TextColor.R, pc.TextColor.G, pc.TextColor.B, 1, function(c)
        pc.TextColor = c
    end)
end

local function BuildHitbox(Tab)
    local S = Tab:Section("Hitbox Expander", "Left")
    S:Toggle("HitboxExpander", "Hitbox Expander", cfg.HitboxExpander.Enabled, function(state)
        cfg.HitboxExpander.Enabled = state
        if state then
            applyAllHitboxes()
            notify("Hitbox ON", string.format("Head size: %.0f", cfg.HitboxExpander.Size), 2)
        else
            restoreAllHitboxes()
            notify("Hitbox OFF", "Original sizes restored", 2)
        end
    end)
    S:Spacing()
    S:SliderInt("HitboxSize", "Head Size (studs)", 2, 6, cfg.HitboxExpander.Size, function(v)
        cfg.HitboxExpander.Size = v
        if cfg.HitboxExpander.Enabled then
            restoreAllHitboxes()
            applyAllHitboxes()
        end
    end)
    S:Spacing()
    S:Toggle("NoCollide", "No Zombie Collision", cfg.NoCollide.Enabled, function(state)
        cfg.NoCollide.Enabled = state
        if state then
            applyZombieNoCollide()
            notify("No Collision ON", "Zombies won't push you", 3)
        else
            restoreZombieCollide()
            notify("No Collision OFF", "Zombie collision restored", 2)
        end
    end)
    S:Spacing()
    S:Tip("No Collision prevents zombies from pushing you out of corners.")
end

local function BuildDebug(Tab)
    local S = Tab:Section("Debug", "Right")
    S:Button("Rescan Zombies", function()
        local before = 0
        for _ in pairs(zombieData) do before = before + 1 end
        scanZombies()
        scanMysteryBoxes()
        local after = 0
        for _ in pairs(zombieData) do after = after + 1 end
        printl(string.format("[ZombieESP] Rescan: %d -> %d", before, after))
        notify(string.format("Rescanned: %d zombie(s)", after), "", 3)
    end)
    S:Spacing()
    S:Button("List Active Zombies", function()
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
        notify(count .. " zombie(s) tracked", "Check console", 3)
    end)
    S:Spacing()
    S:Button("Restore All Hitboxes", function()
        restoreAllHitboxes()
        notify("Hitboxes Restored", "All head sizes reset", 2)
    end)
    S:Spacing()
    S:Button("List Hitbox Store", function()
        local count = 0
        for part, orig in pairs(hitboxStore) do
            printl(string.format("  [HB] %s -> orig: %.1f %.1f %.1f | cur: %.1f",
                part.Name, orig.size.X, orig.size.Y, orig.size.Z, part.Size.X))
            count = count + 1
        end
        printl("[HB] Total expanded: " .. count)
        notify(count .. " head(s) expanded", "", 2)
    end)
end

UI.AddTab("Zombie Tracker", function(tab)
    BuildESP(tab)
    BuildZombieColors(tab)
    BuildMysteryBox(tab)
    BuildMysteryBoxColors(tab)
    BuildWallBuyESP(tab)
    BuildPerkESP(tab)
    BuildHitbox(tab)
    BuildDebug(tab)
end)

printl("[Zombie Tracker] Loaded")

RunService.RenderStepped:Connect(function()
    if not isrbxactive() then return end
    updateViewportCache()
    local char = LocalPlayer.Character
    local hrp  = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    pcall(updateZombieEsp, hrp.Position)
    pcall(updateMysteryBoxEsp, hrp.Position)
    pcall(updateWallBuyEsp, hrp.Position)
    pcall(updatePerkEsp, hrp.Position)
end)

task.spawn(function()
    while true do
        if isrbxactive() then
            pcall(scanZombies)
            pcall(scanMysteryBoxes)
            pcall(scanWallBuys)
            pcall(scanPerkMachines)
            if cfg.NoCollide.Enabled then
                pcall(applyZombieNoCollide)
            end
        end
        task.wait(0.5)
    end
end)

notify("Zombie Tracker", "Loaded successfully", 4)
