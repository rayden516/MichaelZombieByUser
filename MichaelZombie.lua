local RunService  = game:GetService("RunService")
local Players     = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

local cfg = {
    ZombieESP       = { Visible = false },
    MysteryBoxESP   = { Visible = false },
    WallBuyESP      = { Visible = false },
    PerkESP         = { Visible = false },
    TrickOrTreatESP = { Visible = false },
    PumpkinESP      = { Visible = false },
    NoCollide       = { Enabled = false },
    HitboxExpander  = { Enabled = false, Size = 6, KeepVisible = false },
    AutoFarm        = { Enabled = false, Mode = "nearest", ClickAttack = true, FaceTarget = true, AimCamera = true, HeightOffset = 6, ClickInterval = 0.1, RetargetInterval = 1.0 },
    BringZombies    = { Enabled = false, Radius = 6, MaxRange = 200 },
    Zombie = {
        ShowBox = true, ShowLine = true, ShowName = true, ShowHealth = true,
        BoxColor  = Color3.new(0, 1, 0),
        LineColor = Color3.new(1, 0.5, 0),
        TextColor = Color3.new(0, 1, 0),
    },
    MysteryBox = {
        ShowBox = true, ShowLine = true, ShowName = true,
        BoxColor  = Color3.new(1, 0, 1),
        LineColor = Color3.new(1, 1, 0),
        TextColor = Color3.new(1, 0, 1),
    },
    WallBuy      = { BoxColor = Color3.fromRGB(100, 160, 220), TextColor = Color3.fromRGB(150, 195, 240) },
    Perk         = { BoxColor = Color3.fromRGB(200, 130, 255), TextColor = Color3.fromRGB(220, 170, 255) },
    TrickOrTreat = { BoxColor = Color3.fromRGB(255, 140, 0),   LineColor = Color3.fromRGB(180, 0, 255),   TextColor = Color3.fromRGB(255, 200, 80) },
    Pumpkin      = { BoxColor = Color3.fromRGB(255, 90, 0),    LineColor = Color3.fromRGB(255, 200, 0),   TextColor = Color3.fromRGB(255, 150, 30) },
}

local espPool        = {}
local activeKeys     = { zombie = {}, mysteryBox = {}, wallBuy = {}, perk = {}, trickOrTreat = {}, pumpkin = {} }
local zombieData     = {}
local mysteryBoxData = {}
local simpleEspData  = { wallBuy = {}, perk = {}, trickOrTreat = {}, pumpkin = {} }
local hitboxStore    = {}
local noCollideStore = {}
local _afCycleList   = {}
local _afCycleIdx    = 0

local _afClickLast   = 0
local _afTarget      = nil
local _afStickTime   = 0
local _afHeightVec   = Vector3.new(0, cfg.AutoFarm.HeightOffset, 0)
local _afHrp         = nil
local _afSelfHum     = nil

local hasWorldToScreen    = type(WorldToScreen) == "function"
local cachedCam           = workspace.CurrentCamera
local cachedScreenCenterX = 960
local cachedScreenCenterY = 540
local cachedScreenBottomY = 1080
local lineFrom             = Vector2.new(960, 1080)
local AIM_OFFSET           = Vector3.new(0, 0.5, 0)

local function updateViewportCache()
    cachedCam = workspace.CurrentCamera
    local vs  = cachedCam and cachedCam.ViewportSize or Vector2.new(1920, 1080)
    cachedScreenCenterX = vs.X / 2
    cachedScreenCenterY = vs.Y / 2
    cachedScreenBottomY = vs.Y
    lineFrom            = Vector2.new(cachedScreenCenterX, cachedScreenBottomY)
end

updateViewportCache()

local function refreshAfChar()
    local char = LocalPlayer.Character
    _afHrp     = char and char:FindFirstChild("HumanoidRootPart")
    _afSelfHum = char and char:FindFirstChildWhichIsA("Humanoid")
end

refreshAfChar()

local function toScreen(pos)
    if not pos then return nil, false end
    if hasWorldToScreen then
        local scr, on = WorldToScreen(pos)
        if scr then return scr, on end
    end
    if cachedCam then
        local v, vis = cachedCam:WorldToViewportPoint(pos)
        return Vector2.new(v.X, v.Y), vis
    end
    return nil, false
end

local function drawCorners(corners, x, y, w, h, color)
    local cl = math.max(math.floor(w * 0.25), 4)
    local cv = math.max(math.floor(h * 0.25), 4)
    local x2, y2 = x + w, y + h
    corners[1].From = Vector2.new(x,  y);   corners[1].To = Vector2.new(x + cl, y)
    corners[2].From = Vector2.new(x,  y);   corners[2].To = Vector2.new(x,  y + cv)
    corners[3].From = Vector2.new(x2, y);   corners[3].To = Vector2.new(x2 - cl, y)
    corners[4].From = Vector2.new(x2, y);   corners[4].To = Vector2.new(x2, y + cv)
    corners[5].From = Vector2.new(x,  y2);  corners[5].To = Vector2.new(x + cl, y2)
    corners[6].From = Vector2.new(x,  y2);  corners[6].To = Vector2.new(x,  y2 - cv)
    corners[7].From = Vector2.new(x2, y2);  corners[7].To = Vector2.new(x2 - cl, y2)
    corners[8].From = Vector2.new(x2, y2);  corners[8].To = Vector2.new(x2, y2 - cv)
    for _, l in ipairs(corners) do l.Color = color; l.Visible = true end
end

local function getPoolEntry(key)
    if espPool[key] then return espPool[key] end
    local entry   = {}
    local corners = {}
    for i = 1, 8 do
        local l = Drawing.new("Line")
        l.Thickness = 1; l.Transparency = 1; l.Color = cfg.Zombie.BoxColor; l.Visible = false
        corners[i]  = l
    end
    entry.corners = corners
    local label = Drawing.new("Text")
    label.Center = true; label.Outline = true; label.Font = 2; label.Size = 13
    label.Transparency = 1; label.Color = cfg.Zombie.TextColor; label.Visible = false
    entry.label = label
    local healthLabel = Drawing.new("Text")
    healthLabel.Center = true; healthLabel.Outline = true; healthLabel.Font = 2; healthLabel.Size = 12
    healthLabel.Transparency = 1; healthLabel.Color = Color3.new(1, 0, 0); healthLabel.Visible = false
    entry.healthLabel = healthLabel
    local line = Drawing.new("Line")
    line.Thickness = 1; line.Transparency = 1; line.Color = cfg.Zombie.LineColor; line.Visible = false
    entry.line  = line
    espPool[key] = entry
    return entry
end

local function hideEntry(entry)
    if not entry then return end
    if entry.corners     then for _, l in ipairs(entry.corners) do l.Visible = false end end
    if entry.label       then entry.label.Visible       = false end
    if entry.healthLabel then entry.healthLabel.Visible = false end
    if entry.line        then entry.line.Visible        = false end
end

local function removeEntry(key)
    local entry = espPool[key]
    if not entry then return end
    hideEntry(entry)
    if entry.corners     then for _, l in ipairs(entry.corners) do l:Remove() end end
    if entry.label       then entry.label:Remove()       end
    if entry.healthLabel then entry.healthLabel:Remove() end
    if entry.line        then entry.line:Remove()        end
    espPool[key] = nil
end

local function cleanupBucket(bucket, seen)
    for key in pairs(bucket) do
        if not seen[key] then hideEntry(espPool[key]); bucket[key] = nil end
    end
end

local function getRootPart(model)
    if not model or not model:IsA("Model") then return nil end
    local hrp = model:FindFirstChild("HumanoidRootPart")
    if hrp then return hrp end
    if model.PrimaryPart then return model.PrimaryPart end
    for _, child in ipairs(model:GetChildren()) do
        if child:IsA("BasePart") then return child end
    end
    return nil
end

local function getHumanoid(model) return model:FindFirstChildWhichIsA("Humanoid") end

local function getHeadPart(model)
    local head = model:FindFirstChild("Head")
    if head and head:IsA("BasePart") then return head end
    for _, child in ipairs(model:GetChildren()) do
        if child:IsA("BasePart") and child.Name:lower() == "head" then return child end
    end
    return nil
end

local function applyHitbox(model)
    if not model or not model.Parent then return end
    local head = getHeadPart(model)
    if not head or not head.Parent or hitboxStore[head] then return end
    hitboxStore[head] = {
        size         = head.Size,
        collide      = head.CanCollide,
        transparency = head.Transparency,
    }
    local s = cfg.HitboxExpander.Size
    head.Size       = Vector3.new(s, s, s)
    head.CanCollide = false
    if not cfg.HitboxExpander.KeepVisible then
        head.Transparency = 1
    end
end

local function resizeAllHitboxes()
    local s = cfg.HitboxExpander.Size
    for part in pairs(hitboxStore) do
        if part and part.Parent then
            part.Size = Vector3.new(s, s, s)
        end
    end
end

local function setHitboxVisibility(keepVisible)
    for part, orig in pairs(hitboxStore) do
        if part and part.Parent then
            part.Transparency = keepVisible and orig.transparency or 1
        end
    end
end

local function restoreAllHitboxes()
    for part, orig in pairs(hitboxStore) do
        if part and part.Parent then
            part.Size         = orig.size
            part.CanCollide   = orig.collide
            part.Transparency = orig.transparency
        end
    end
    hitboxStore = {}
end

local function cleanHitboxStore()
    for part in pairs(hitboxStore) do
        if not part or not part.Parent then hitboxStore[part] = nil end
    end
end

local function applyAllHitboxes()
    for _, data in pairs(zombieData) do
        if data.model and data.model.Parent then applyHitbox(data.model) end
    end
end

local function applyNoCollideToRoot(root)
    if not root or not root.Parent then return end
    if noCollideStore[root] and noCollideStore[root].Parent then return end
    local char = LocalPlayer.Character
    local hrp  = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    local c = Instance.new("NoCollisionConstraint")
    c.Part0 = hrp; c.Part1 = root; c.Parent = hrp
    noCollideStore[root] = c
end

local function applyZombieNoCollide()
    for _, data in pairs(zombieData) do applyNoCollideToRoot(data.root) end
end

local function restoreZombieCollide()
    for _, c in pairs(noCollideStore) do c:Destroy() end
    noCollideStore = {}
end

local function cleanNoCollideStore()
    for root, c in pairs(noCollideStore) do
        if not root or not root.Parent or not c or not c.Parent then
            if c and c.Parent then c:Destroy() end
            noCollideStore[root] = nil
        end
    end
end

local function isZombieAlive(data)
    return data.model and data.model.Parent
        and data.root  and data.root.Parent
        and data.hum   and data.hum.Parent
        and data.hum.Health > 0
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
    zombieData[key]        = nil
end

local function scanZombies()
    local ignore       = workspace:FindFirstChild("Ignore")
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
                        model = zombie, root = root, sizeCache = nil,
                        hum = getHumanoid(zombie),
                        lastDist = nil, lastHp = nil, lastMaxHp = nil,
                    }
                    if cfg.HitboxExpander.Enabled then applyHitbox(zombie)          end
                    if cfg.NoCollide.Enabled      then applyNoCollideToRoot(root)   end
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
        if not found[key] or not key.Parent then dead[#dead + 1] = key end
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
            if not root or not root.Parent then root = getRootPart(model); data.root = root end
            if not root then
                hideEntry(espPool[key])
            else
                local pos = root.Position
                local scr, onScr = toScreen(pos)
                if not scr or not onScr then
                    hideEntry(espPool[key])
                else
                    seen[key] = true; activeKeys.zombie[key] = true
                    local entry          = getPoolEntry(key)
                    local scrX, scrY     = scr.X, scr.Y
                    local dist           = (playerPos - pos).Magnitude
                    local hum            = data.hum
                    if not hum or not hum.Parent then hum = getHumanoid(model); data.hum = hum end
                    local hp    = hum and hum.Health    or 0
                    local maxHp = hum and hum.MaxHealth or 100
                    if zc.ShowBox then
                        if not data.sizeCache then
                            data.sizeCache = root.Size
                        end
                        local scale = math.clamp(1000 / math.max(dist, 1), 0.3, 8)
                        local boxH  = math.max(math.floor(data.sizeCache.Y * 11 * scale / 10), 20)
                        local boxW  = math.max(math.floor(data.sizeCache.X * 5  * scale / 10), 10)
                        drawCorners(entry.corners, scrX - boxW / 2, scrY - boxH / 2, boxW, boxH, zc.BoxColor)
                    else
                        for _, l in ipairs(entry.corners) do l.Visible = false end
                    end
                    if zc.ShowName then
                        local fd = math.floor(dist)
                        if fd ~= data.lastDist then
                            data.lastDist    = fd
                            entry.label.Text = string.format("%s [%dm]", model.Name, fd)
                        end
                        entry.label.Position = Vector2.new(scrX, scrY - 40)
                        entry.label.Color    = zc.TextColor
                        entry.label.Visible  = true
                    else
                        entry.label.Visible = false
                    end
                    if zc.ShowHealth and hum then
                        local fHp    = math.floor(hp)
                        local fMaxHp = math.floor(maxHp)
                        if fHp ~= data.lastHp or fMaxHp ~= data.lastMaxHp then
                            data.lastHp = fHp; data.lastMaxHp = fMaxHp
                            entry.healthLabel.Text = string.format("HP: %d/%d", fHp, fMaxHp)
                        end
                        local hpPct = math.clamp(hp / math.max(maxHp, 1), 0, 1)
                        entry.healthLabel.Position = Vector2.new(scrX, scrY - 27)
                        entry.healthLabel.Color    = Color3.new(1 - hpPct, hpPct, 0)
                        entry.healthLabel.Visible  = true
                    else
                        entry.healthLabel.Visible = false
                    end
                    if zc.ShowLine then
                        entry.line.From    = lineFrom
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
    local mysteryBox    = mapComponents and mapComponents:FindFirstChild("MysteryBox")
    if not mysteryBox or not mysteryBox:IsA("Model") then
        for key in pairs(mysteryBoxData) do
            removeEntry(key)
            activeKeys.mysteryBox[key] = nil
            mysteryBoxData[key]        = nil
        end
        return
    end
    local rootLoc = mysteryBox:FindFirstChild("PurchaseBox")
        or mysteryBox.PrimaryPart
        or mysteryBox:FindFirstChildWhichIsA("BasePart")
    if rootLoc then
        if not mysteryBoxData[mysteryBox] then
            mysteryBoxData[mysteryBox] = { model = mysteryBox, root = rootLoc, lastDist = nil }
        else
            mysteryBoxData[mysteryBox].root = rootLoc
        end
    end
    for key in pairs(mysteryBoxData) do
        if key ~= mysteryBox or not key.Parent then
            removeEntry(key)
            activeKeys.mysteryBox[key] = nil
            mysteryBoxData[key]        = nil
        end
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
                root = model:FindFirstChild("RootLocation"); data.root = root
            end
            if not root then
                hideEntry(espPool[key])
            else
                local pos = root.Position
                local scr, onScr = toScreen(pos)
                if not scr or not onScr then
                    hideEntry(espPool[key])
                else
                    seen[key] = true; activeKeys.mysteryBox[key] = true
                    local entry      = getPoolEntry(key)
                    local scrX, scrY = scr.X, scr.Y
                    local dist       = (playerPos - pos).Magnitude
                    if mc.ShowBox then
                        local scale = math.clamp(1000 / math.max(dist, 1), 0.3, 8)
                        local boxH  = math.max(math.floor(30 * scale / 10), 20)
                        local boxW  = math.max(math.floor(20 * scale / 10), 14)
                        drawCorners(entry.corners, scrX - boxW / 2, scrY - boxH / 2, boxW, boxH, mc.BoxColor)
                    else
                        for _, l in ipairs(entry.corners) do l.Visible = false end
                    end
                    if mc.ShowName then
                        local fd = math.floor(dist)
                        if fd ~= data.lastDist then
                            data.lastDist    = fd
                            entry.label.Text = string.format("Mystery Box [%dm]", fd)
                        end
                        entry.label.Position = Vector2.new(scrX, scrY - 30)
                        entry.label.Color    = mc.TextColor
                        entry.label.Visible  = true
                    else
                        entry.label.Visible = false
                    end
                    entry.healthLabel.Visible = false
                    if mc.ShowLine then
                        entry.line.From    = lineFrom
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

local simpleEspDefs = {
    wallBuy = {
        cfgKey    = "WallBuyESP",
        colorKey  = "WallBuy",
        bucketKey = "wallBuy",
        getFolder = function() return workspace:FindFirstChild("_WallBuys") end,
        getPart   = function(model)
            local p = model:FindFirstChild("PurchaseWallGun")
            return p and p:IsA("BasePart") and p or nil
        end,
        boxW = 20, boxH = 26, showLine = false,
    },
    perk = {
        cfgKey    = "PerkESP",
        colorKey  = "Perk",
        bucketKey = "perk",
        getFolder = function() return workspace:FindFirstChild("_PerkMachines") end,
        getPart   = function(model) return model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart") end,
        boxW = 28, boxH = 36, showLine = false,
    },
    trickOrTreat = {
        cfgKey    = "TrickOrTreatESP",
        colorKey  = "TrickOrTreat",
        bucketKey = "trickOrTreat",
        getFolder = function()
            local mc = workspace:FindFirstChild("_MapComponents")
            return mc and mc:FindFirstChild("_TrickOrTreatDoors")
        end,
        getPart = function(model) return model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart") end,
        boxW = 24, boxH = 32, showLine = true,
    },
    pumpkin = {
        cfgKey    = "PumpkinESP",
        colorKey  = "Pumpkin",
        bucketKey = "pumpkin",
        getFolder = function()
            local mc = workspace:FindFirstChild("_MapComponents")
            return mc and mc:FindFirstChild("PumpkinPatchPumpkins")
        end,
        getPart = function(model) return model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart") end,
        boxW = 20, boxH = 20, showLine = true,
    },
}

local simpleEspKeys = {"wallBuy", "perk", "trickOrTreat", "pumpkin"}

local function scanSimpleEsp(defKey)
    local def    = simpleEspDefs[defKey]
    local data   = simpleEspData[defKey]
    local bucket = activeKeys[def.bucketKey]
    local folder = def.getFolder()
    if not folder then
        for key in pairs(data) do
            hideEntry(espPool[key]); bucket[key] = nil; data[key] = nil
        end
        return
    end
    local found = {}
    for _, model in ipairs(folder:GetChildren()) do
        if model and model:IsA("Model") then
            local part = def.getPart(model)
            if part then
                found[part] = true
                if not data[part] then
                    data[part] = { part = part, label = model.Name, lastDist = nil }
                end
            end
        end
    end
    for key in pairs(data) do
        if not found[key] or not key.Parent then
            hideEntry(espPool[key]); bucket[key] = nil; data[key] = nil
        end
    end
end

local function updateSimpleEsp(defKey, playerPos)
    local def    = simpleEspDefs[defKey]
    local data   = simpleEspData[defKey]
    local bucket = activeKeys[def.bucketKey]
    local cc     = cfg[def.colorKey]
    if not cfg[def.cfgKey].Visible then
        for key in pairs(bucket) do hideEntry(espPool[key]) end
        activeKeys[def.bucketKey] = {}
        return
    end
    local seen = {}
    for key, d in pairs(data) do
        local part = d.part
        if not part or not part.Parent then
            hideEntry(espPool[key]); bucket[key] = nil; data[key] = nil
        else
            local pos = part.Position
            local scr, onScr = toScreen(pos)
            if not scr or not onScr then
                hideEntry(espPool[key])
            else
                seen[key]   = true
                bucket[key] = true
                local entry      = getPoolEntry(key)
                local scrX, scrY = scr.X, scr.Y
                local dist       = (playerPos - pos).Magnitude
                local scale      = math.clamp(500 / math.max(dist, 1), 0.2, 4)
                local boxW       = math.max(math.floor(def.boxW * scale), 10)
                local boxH       = math.max(math.floor(def.boxH * scale), 12)
                drawCorners(entry.corners, scrX - boxW / 2, scrY - boxH / 2, boxW, boxH, cc.BoxColor)
                local fd = math.floor(dist)
                if fd ~= d.lastDist then
                    d.lastDist       = fd
                    entry.label.Text = string.format("%s [%dm]", d.label, fd)
                end
                entry.label.Position    = Vector2.new(scrX, scrY - boxH / 2 - 14)
                entry.label.Color       = cc.TextColor
                entry.label.Visible     = true
                entry.healthLabel.Visible = false
                if def.showLine then
                    entry.line.From    = lineFrom
                    entry.line.To      = Vector2.new(scrX, scrY)
                    entry.line.Color   = cc.LineColor
                    entry.line.Visible = true
                else
                    entry.line.Visible = false
                end
            end
        end
    end
    cleanupBucket(bucket, seen)
end

local function bringZombies()
    local char = LocalPlayer.Character
    local hrp  = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    local playerPos = hrp.Position
    local maxRange  = cfg.BringZombies.MaxRange
    local alive     = {}
    for _, data in pairs(zombieData) do
        if isZombieAlive(data) then
            local d = (data.root.Position - playerPos).Magnitude
            if d <= maxRange then
                alive[#alive + 1] = { data = data, dist = d }
            end
        end
    end
    local count = #alive
    if count == 0 then return end
    table.sort(alive, function(a, b) return a.dist < b.dist end)
    local radius = cfg.BringZombies.Radius
    local step   = math.pi * 2 / count
    for i, entry in ipairs(alive) do
        local data    = entry.data
        local angle   = (i - 1) * step
        local zombieY = data.root.Position.Y
        data.hum:MoveTo(Vector3.new(
            playerPos.X + math.cos(angle) * radius,
            zombieY,
            playerPos.Z + math.sin(angle) * radius
        ))
    end
end

local function getAutoFarmTarget()
    if not _afHrp then return nil end
    local hrp  = _afHrp
    local mode = cfg.AutoFarm.Mode
    if mode == "cycle" then
        if #_afCycleList == 0 then
            for _, data in pairs(zombieData) do
                if isZombieAlive(data) then _afCycleList[#_afCycleList + 1] = data end
            end
            _afCycleIdx = 0
        end
        for _ = 1, #_afCycleList do
            _afCycleIdx = (_afCycleIdx % #_afCycleList) + 1
            local data  = _afCycleList[_afCycleIdx]
            if data and isZombieAlive(data) then return data end
        end
        _afCycleList = {}
        return nil
    elseif mode == "lowhp" then
        local best, bestHp = nil, math.huge
        for _, data in pairs(zombieData) do
            if isZombieAlive(data) and data.hum.Health < bestHp then
                bestHp = data.hum.Health; best = data
            end
        end
        return best
    else
        local best, bestDist = nil, math.huge
        for _, data in pairs(zombieData) do
            if isZombieAlive(data) then
                local d = (data.root.Position - hrp.Position).Magnitude
                if d < bestDist then bestDist = d; best = data end
            end
        end
        return best
    end
end

local function BuildESP(Tab)
    local zc = cfg.Zombie
    local S  = Tab:Section("ESP", "Left")
    S:Toggle("ZombieESP", "Zombie ESP", cfg.ZombieESP.Visible, function(state)
        cfg.ZombieESP.Visible = state
        notify(state and "Zombie ESP ON" or "Zombie ESP OFF", "", 2)
        if state then task.spawn(scanZombies) else
            for key in pairs(activeKeys.zombie) do hideEntry(espPool[key]) end
        end
    end)
    S:Toggle("ZombieBox", "Box", zc.ShowBox, function(state)
        zc.ShowBox = state
        if not state then
            for _, e in pairs(espPool) do
                if e.corners then for _, l in ipairs(e.corners) do l.Visible = false end end
            end
        end
    end)
    S:ColorPicker("ZBoxColor",  zc.BoxColor.R,  zc.BoxColor.G,  zc.BoxColor.B,  1, function(c) zc.BoxColor  = c; syncZombieColors() end)
    S:Toggle("ZombieLine", "Direction Line", zc.ShowLine, function(state)
        zc.ShowLine = state
        if not state then for _, e in pairs(espPool) do if e.line then e.line.Visible = false end end end
    end)
    S:ColorPicker("ZLineColor", zc.LineColor.R, zc.LineColor.G, zc.LineColor.B, 1, function(c) zc.LineColor = c; syncZombieColors() end)
    S:Toggle("ZombieName", "Name & Distance", zc.ShowName, function(state)
        zc.ShowName = state
        if not state then for _, e in pairs(espPool) do if e.label then e.label.Visible = false end end end
    end)
    S:ColorPicker("ZTextColor", zc.TextColor.R, zc.TextColor.G, zc.TextColor.B, 1, function(c) zc.TextColor = c; syncZombieColors() end)
    S:Toggle("ZombieHealth", "Health", zc.ShowHealth, function(state)
        zc.ShowHealth = state
        if not state then for _, e in pairs(espPool) do if e.healthLabel then e.healthLabel.Visible = false end end end
    end)
end

local function BuildMysteryBox(Tab)
    local mc = cfg.MysteryBox
    local S  = Tab:Section("Mystery Box ESP", "Left")
    S:Toggle("MysteryBoxESP", "Mystery Box ESP", cfg.MysteryBoxESP.Visible, function(state)
        cfg.MysteryBoxESP.Visible = state
        notify(state and "Mystery Box ESP ON" or "Mystery Box ESP OFF", "", 2)
        if state then scanMysteryBoxes() else
            for key in pairs(activeKeys.mysteryBox) do hideEntry(espPool[key]) end
        end
    end)
    S:Toggle("MBBox",  "Box",              mc.ShowBox,  function(state) mc.ShowBox  = state end)
    S:ColorPicker("MBBoxColor",  mc.BoxColor.R,  mc.BoxColor.G,  mc.BoxColor.B,  1, function(c) mc.BoxColor  = c end)
    S:Toggle("MBLine", "Direction Line",   mc.ShowLine, function(state) mc.ShowLine = state end)
    S:ColorPicker("MBLineColor", mc.LineColor.R, mc.LineColor.G, mc.LineColor.B, 1, function(c) mc.LineColor = c end)
    S:Toggle("MBName", "Name & Distance",  mc.ShowName, function(state) mc.ShowName = state end)
    S:ColorPicker("MBTextColor", mc.TextColor.R, mc.TextColor.G, mc.TextColor.B, 1, function(c) mc.TextColor = c end)
end

local function BuildSimpleEspSection(Tab, defKey, title)
    local def = simpleEspDefs[defKey]
    local cc  = cfg[def.colorKey]
    local S   = Tab:Section(title, "Left")
    S:Toggle(def.cfgKey, title, cfg[def.cfgKey].Visible, function(state)
        cfg[def.cfgKey].Visible = state
        notify(state and (title .. " ON") or (title .. " OFF"), "", 2)
        if state then
            scanSimpleEsp(defKey)
        else
            for key in pairs(activeKeys[def.bucketKey]) do hideEntry(espPool[key]) end
            activeKeys[def.bucketKey] = {}
        end
    end)
    S:ColorPicker2(
        defKey .. "Box",  { cc.BoxColor.R,  cc.BoxColor.G,  cc.BoxColor.B,  1 },
        defKey .. "Text", { cc.TextColor.R, cc.TextColor.G, cc.TextColor.B, 1 },
        function(c1, _, c2, _) cc.BoxColor = c1; cc.TextColor = c2 end
    )
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
    S:SliderInt("HitboxSize", "Head Size (studs)", 2, 15, cfg.HitboxExpander.Size, function(v)
        cfg.HitboxExpander.Size = v
        if cfg.HitboxExpander.Enabled then resizeAllHitboxes() end
    end)
    S:Toggle("HitboxKeepVisible", "Keep Heads Visible", cfg.HitboxExpander.KeepVisible, function(state)
        cfg.HitboxExpander.KeepVisible = state
        if cfg.HitboxExpander.Enabled then setHitboxVisibility(state) end
    end)
    S:Toggle("NoCollide", "No Zombie Collision", cfg.NoCollide.Enabled, function(state)
        cfg.NoCollide.Enabled = state
        if state then applyZombieNoCollide(); notify("No Collision ON", "Zombies won't push you", 3)
        else          restoreZombieCollide(); notify("No Collision OFF", "Zombie collision restored", 2) end
    end)
end

local function BuildAutoFarm(Tab)
    local S = Tab:Section("Auto Farm", "Right")
    S:Toggle("AutoFarm", "Auto Farm", cfg.AutoFarm.Enabled, function(state)
        cfg.AutoFarm.Enabled = state
        if not state then _afTarget = nil; _afCycleList = {} end
        notify(state and "Auto Farm ON" or "Auto Farm OFF", state and ("Mode: " .. cfg.AutoFarm.Mode) or "", 2)
    end)
    local afKb = S:Keybind("af_kb", 0x70, "toggle")
    afKb:AddToHotkey("Auto Farm", "AutoFarm")
    S:Spacing()
    S:Toggle("AFClick", "Click Attack",        cfg.AutoFarm.ClickAttack, function(state) cfg.AutoFarm.ClickAttack = state; notify(state and "Click Attack ON" or "Click Attack OFF", "", 2) end)
    S:Toggle("AFFace",  "Face Target (HRP)",   cfg.AutoFarm.FaceTarget,  function(state) cfg.AutoFarm.FaceTarget  = state end)
    S:Toggle("AFAim",   "Aim Camera (bullets)", cfg.AutoFarm.AimCamera,  function(state) cfg.AutoFarm.AimCamera   = state end)
    S:Spacing()
    S:SliderInt("AFHeight",    "Height Above Zombie",    3,    20,  cfg.AutoFarm.HeightOffset,     function(v) cfg.AutoFarm.HeightOffset = v; _afHeightVec = Vector3.new(0, v, 0) end)
    S:SliderFloat("AFClick2",  "Click Interval (s)",     0.05, 1.0, cfg.AutoFarm.ClickInterval,   "%.2f", function(v) cfg.AutoFarm.ClickInterval    = v end)
    S:SliderFloat("AFRetarget", "Retarget Interval (s)", 0.3,  5.0, cfg.AutoFarm.RetargetInterval, "%.1f", function(v) cfg.AutoFarm.RetargetInterval = v end)
    S:Spacing()
    S:Button("Target: Nearest",   function() cfg.AutoFarm.Mode = "nearest"; _afTarget = nil; _afCycleList = {}; notify("Farm Mode: Nearest",   "", 2) end)
    S:Button("Target: Low HP",    function() cfg.AutoFarm.Mode = "lowhp";   _afTarget = nil; _afCycleList = {}; notify("Farm Mode: Low HP",    "", 2) end)
    S:Button("Target: Cycle All", function() cfg.AutoFarm.Mode = "cycle";   _afTarget = nil; _afCycleList = {}; notify("Farm Mode: Cycle All", "", 2) end)
    S:Tip("Aim Camera is what makes bullets hit. Face Target only rotates the body.")
    local SB = Tab:Section("Bring Zombies", "Right")
    SB:Toggle("BringZombies", "Bring Zombies to Me", cfg.BringZombies.Enabled, function(state)
        cfg.BringZombies.Enabled = state
        notify(state and "Bring Zombies ON" or "Bring Zombies OFF", "", 2)
    end)
    SB:SliderInt("BringRadius",   "Bring Radius (studs)", 2,  15,  cfg.BringZombies.Radius,   function(v) cfg.BringZombies.Radius   = v end)
    SB:SliderInt("BringMaxRange", "Max Range (studs)",    20, 500, cfg.BringZombies.MaxRange, function(v) cfg.BringZombies.MaxRange = v end)
end

local function BuildDebug(Tab)
    local S = Tab:Section("Debug", "Right")
    S:Button("Rescan Zombies", function()
        local before = 0; for _ in pairs(zombieData) do before = before + 1 end
        scanZombies(); scanMysteryBoxes()
        local after = 0; for _ in pairs(zombieData) do after = after + 1 end
        printl(string.format("[ZombieESP] Rescan: %d -> %d", before, after))
        notify(string.format("Rescanned: %d zombie(s)", after), "", 3)
    end)
    S:Button("List Active Zombies", function()
        local count = 0
        local char  = LocalPlayer.Character
        local hrp   = char and char:FindFirstChild("HumanoidRootPart")
        for key, data in pairs(zombieData) do
            if data.root and data.root.Parent then
                local p = data.root.Position
                local d = hrp and (p - hrp.Position).Magnitude or 0
                printl(string.format("  %s | %.0fm | %.0f, %.0f, %.0f", tostring(key), d, p.X, p.Y, p.Z))
                count = count + 1
            end
        end
        printl("[ZombieESP] Total tracked: " .. count)
        notify(count .. " zombie(s) tracked", "Check console", 3)
    end)
    S:Button("Restore All Hitboxes", function()
        restoreAllHitboxes()
        notify("Hitboxes Restored", "All head sizes reset", 2)
    end)
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
    BuildMysteryBox(tab)
    BuildSimpleEspSection(tab, "wallBuy",      "Wall Buy ESP")
    BuildSimpleEspSection(tab, "perk",         "Perk Machine ESP")
    BuildSimpleEspSection(tab, "trickOrTreat", "Trick or Treat ESP")
    BuildSimpleEspSection(tab, "pumpkin",      "Pumpkin ESP")
    BuildHitbox(tab)
    BuildAutoFarm(tab)
    BuildDebug(tab)
end)

printl("[Zombie Tracker] Loaded")

local _espFrame = 0
RunService.RenderStepped:Connect(function()
    if not isrbxactive() then return end
    updateViewportCache()
    _espFrame = _espFrame + 1
    if _espFrame < 2 then return end
    _espFrame = 0
    local char = LocalPlayer.Character
    local hrp  = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    local pos = hrp.Position
    updateZombieEsp(pos)
    updateMysteryBoxEsp(pos)
    for _, defKey in ipairs(simpleEspKeys) do updateSimpleEsp(defKey, pos) end
end)

task.spawn(function()
    while true do
        if isrbxactive() then
            scanZombies()
            scanMysteryBoxes()
            for _, defKey in ipairs(simpleEspKeys) do scanSimpleEsp(defKey) end
            cleanNoCollideStore()
            if cfg.NoCollide.Enabled    then applyZombieNoCollide() end
            if cfg.BringZombies.Enabled then bringZombies()         end
        end
        task.wait(0.5)
    end
end)

RunService.Heartbeat:Connect(function()
    if not isrbxactive() then
        if cfg.AutoFarm.Enabled then _afTarget = nil end
        return
    end
    local af = cfg.AutoFarm
    if not af.Enabled then _afTarget = nil; return end

    if _afTarget and not isZombieAlive(_afTarget) then
        _afTarget = nil; _afStickTime = 0
    end

    if not _afTarget or (os.clock() - _afStickTime > af.RetargetInterval) then
        if not _afHrp or not _afHrp.Parent then refreshAfChar() end
        _afTarget    = getAutoFarmTarget()
        _afStickTime = os.clock()
        if not _afTarget then return end
    end

    local root = _afTarget.root
    if not root or not root.Parent then _afTarget = nil; return end

    if not _afHrp or not _afHrp.Parent then refreshAfChar() end
    local hrp     = _afHrp
    local selfHum = _afSelfHum
    if not hrp or not selfHum or selfHum.Health <= 0 then return end

    local zombiePos = root.Position
    local newPos    = zombiePos + _afHeightVec

    if af.FaceTarget then
        hrp.CFrame = CFrame.lookAt(newPos, zombiePos)
    else
        hrp.CFrame = CFrame.new(newPos)
    end

    if af.AimCamera then
        cachedCam:lookAt(newPos + AIM_OFFSET, zombiePos)
        mousemoveabs(cachedScreenCenterX, cachedScreenCenterY)
    end

    if af.ClickAttack then
        local now = os.clock()
        if now - _afClickLast >= af.ClickInterval then
            _afClickLast = now
            mouse1click()
        end
    end
end)

notify("Zombie Tracker", "Loaded successfully", 4)
