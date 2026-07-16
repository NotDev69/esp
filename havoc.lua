-- ESP Script with working teleport re-execution

if not game:IsLoaded() then game.Loaded:Wait() end

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local TeleportService = game:GetService("TeleportService")

-- Queue on teleport for re-execution
local queueteleport = queue_on_teleport or (syn and syn.queue_on_teleport) or (fluxus and fluxus.queue_on_teleport)

if queueteleport then
    LocalPlayer.OnTeleport:Connect(function(State)
        queueteleport("loadstring(game:HttpGet('https://raw.githubusercontent.com/NotDev69/esp/main/havoc.lua'))()")
    end)
end

-- ==================== MAIN ESP FUNCTION ====================

local function RunESP()

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")

local Camera = workspace.CurrentCamera
local LocalPlayer = Players.LocalPlayer

local FRIEND_UIDS = {
    456976947,
    585685128,
    53491365,
    9433536577,
    8904938915,
    476384850,
}

local Flags = {
    ESP       = true,
    Arrows    = true,
    Skeleton  = true,
    HealthBar = true,
    Names     = true,
}

local COLOR_VISIBLE  = Color3.fromRGB(255, 105, 180)
local COLOR_OCCLUDED = Color3.fromRGB(168, 82, 50)
local COLOR_ON       = Color3.fromRGB(0, 220, 80)
local COLOR_OFF      = Color3.fromRGB(110, 110, 110)
local CORNER_RATIO   = 0.25

local NPC_COLOR_VISIBLE  = Color3.fromRGB(100, 180, 255)
local NPC_COLOR_OCCLUDED = Color3.fromRGB(255, 255, 0)
local HOSTAGE_COLOR      = Color3.fromRGB(0, 0, 139)  -- Dark Blue
local NPC_MAX_DISTANCE   = 50000

local PASSABLE_MATERIALS = {
    [Enum.Material.Air]        = true,
    [Enum.Material.Water]      = true,
    [Enum.Material.Glass]      = true,
    [Enum.Material.LeafyGrass] = true,
    [Enum.Material.Grass]      = true,
}

local PASSABLE_NAMES = {
    ["HumanoidRootPart"] = true,
    ["Hitbox"]           = true,
    ["TriggerVolume"]    = true,
    ["ForceField"]       = true,
}

local MAX_RAY_SEGMENTS = 8
local RAY_NUDGE        = 0.05

local function IsPassableHit(hit)
    if not hit then return true end
    if PASSABLE_NAMES[hit.Name] then return true end
    if PASSABLE_MATERIALS[hit.Material] then return true end
    if not hit.CanCollide then return true end
    if hit.Transparency >= 0.9 then return true end
    return false
end

-- ==================== Use camera directly, no roll removal ====================

local function ToScreen(worldPos)
    local cf = Camera.CFrame
    local vp = Camera.ViewportSize
    local fov = math.rad(Camera.FieldOfView)
    local halfH = math.tan(fov / 2)
    local halfW = halfH * (vp.X / vp.Y)
    local local3 = cf:PointToObjectSpace(worldPos)
    local depth = -local3.Z
    if depth <= 0 then
        return Vector3.new(-99999, -99999, depth), false
    end
    local sx = vp.X * (0.5 + (local3.X / depth) / (2 * halfW))
    local sy = vp.Y * (0.5 - (local3.Y / depth) / (2 * halfH))
    local onScreen = sx >= 0 and sx <= vp.X and sy >= 0 and sy <= vp.Y
    return Vector3.new(sx, sy, depth), onScreen
end

local function IsVisible(targetChar)
    local head = targetChar and targetChar:FindFirstChild("Head")
    if not head then return false end
    local destination = head.Position
    local origin      = Camera.CFrame.Position
    local totalDist   = (destination - origin).Magnitude
    if totalDist < 0.1 then return true end
    local ignoreList = {}
    local lChar = LocalPlayer.Character
    if lChar then ignoreList[#ignoreList + 1] = lChar end
    ignoreList[#ignoreList + 1] = targetChar
    local params = RaycastParams.new()
    params.FilterType                 = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = ignoreList
    params.IgnoreWater                = true
    local currentOrigin = origin
    local travelledDist = 0
    for _ = 1, MAX_RAY_SEGMENTS do
        local dir     = destination - currentOrigin
        local segDist = dir.Magnitude
        if segDist < 0.01 then break end
        local result = workspace:Raycast(currentOrigin, dir.Unit * segDist, params)
        if not result then return true end
        if not IsPassableHit(result.Instance) then return false end
        local hitDist = (result.Position - currentOrigin).Magnitude
        travelledDist = travelledDist + hitDist + RAY_NUDGE
        if travelledDist >= totalDist then return true end
        currentOrigin = currentOrigin + dir.Unit * (hitDist + RAY_NUDGE)
    end
    return true
end

local rainbowHue = 0
RunService.Heartbeat:Connect(function(dt)
    rainbowHue = (rainbowHue + dt * 0.3) % 1
end)

local function RainbowColor()
    return Color3.fromHSV(rainbowHue, 1, 1)
end

local function IsFriend(plr)
    if not plr then return false end
    for _, id in ipairs(FRIEND_UIDS) do
        if plr.UserId == id then return true end
    end
    return false
end

local function IsNPC(entity)
    if not entity or not entity:IsA("Model") then return false end
    local attrs = entity:GetAttributes()
    if attrs and attrs.AI == true then return true end
    local hum = entity:FindFirstChildOfClass("Humanoid")
    if hum and not Players:GetPlayerFromCharacter(entity) then return true end
    return false
end

-- ==================== Check if entity is a Hostage (DIRECT PATH ONLY) ====================

local function IsHostage(entity)
    if not entity or not entity:IsA("Model") then return false end
    -- Check by name first (fastest)
    if entity.Name == "Hostage" then
        return true
    end
    return false
end

-- Find all Hostages - ONLY in workspace.Buildings.Loots.Objects
local function FindAllHostages()
    local hostages = {}
    local buildings = workspace:FindFirstChild("Buildings")
    if not buildings then return hostages end
    
    local loots = buildings:FindFirstChild("Loots")
    if not loots then return hostages end
    
    local objects = loots:FindFirstChild("Objects")
    if not objects then return hostages end
    
    -- Only check children of Objects folder
    for _, child in ipairs(objects:GetChildren()) do
        if child:IsA("Model") and child.Name == "Hostage" then
            table.insert(hostages, child)
        end
    end
    return hostages
end

-- ==================== Check Rendered attribute ====================

local function ShouldRender(entity)
    if not entity then return false end
    if entity:IsA("Model") then
        local attrs = entity:GetAttributes()
        if attrs and attrs.Rendered == false then
            return false
        end
        -- Also check if any parent has Rendered = false
        local parent = entity.Parent
        while parent do
            local parentAttrs = parent:GetAttributes()
            if parentAttrs and parentAttrs.Rendered == false then
                return false
            end
            parent = parent.Parent
        end
        return true
    end
    return true
end

-- ==================== Get ESP Color with Hostage override ====================

local function GetESPColor(plr, visible, isNPC, entity)
    -- Check if entity is a Hostage first - always dark blue
    if entity and IsHostage(entity) then
        return HOSTAGE_COLOR
    end
    if isNPC then 
        return visible and NPC_COLOR_VISIBLE or NPC_COLOR_OCCLUDED 
    end
    if IsFriend(plr) then return RainbowColor() end
    return visible and COLOR_VISIBLE or COLOR_OCCLUDED
end

local function GetNameLabel(plr, char, isNPC, entity)
    if entity and IsHostage(entity) then
        return "Hostage"
    end
    if isNPC then
        return "(bot) " .. (char and char.Name or "Unknown")
    end
    if not plr then return "Unknown" end
    local name    = plr.Name or "Unknown"
    local display = plr.DisplayName or ""
    if display ~= "" and display ~= name then
        return ("(%s) %s"):format(display, name)
    end
    return name
end

local function GetTeamLabel(plr)
    if plr and plr.Team then
        local n = plr.Team.Name
        return (n and n ~= "") and n or nil
    end
    return nil
end

local function Part(char, name)
    return char and char:FindFirstChild(name) or nil
end

local function GetHeldTool(char)
    if not char then return nil end
    for _, v in ipairs(char:GetChildren()) do
        if v:IsA("Tool") then return v.Name end
    end
    return nil
end

local function GetHealth(char)
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if hum then return hum.Health, hum.MaxHealth end
    return nil, nil
end

local AllDrawings = {}

local function Track(d)
    AllDrawings[d] = true
    return d
end

local function RemoveDrawing(d)
    if AllDrawings[d] then
        AllDrawings[d] = nil
        d:Remove()
    end
end

local function NewLine()
    local l = Track(Drawing.new("Line"))
    l.Visible = false; l.From = Vector2.zero; l.To = Vector2.zero
    l.Color = Color3.fromRGB(255,255,255); l.Thickness = 1; l.Transparency = 1
    return l
end

local function NewText(size)
    local t = Track(Drawing.new("Text"))
    t.Visible = false; t.Text = ""; t.Color = Color3.fromRGB(255,255,255)
    t.Size = size; t.Center = false; t.Outline = true; t.Transparency = 1
    return t
end

local function NewTextCentered(size)
    local t = NewText(size); t.Center = true; return t
end

local function NewTriangle()
    local t = Track(Drawing.new("Triangle"))
    t.Visible = false; t.Filled = true; t.Thickness = 1
    t.Color = Color3.fromRGB(255,255,255)
    t.PointA = Vector2.zero; t.PointB = Vector2.zero; t.PointC = Vector2.zero
    return t
end

local function NewCornerBox()
    local lines = {}
    for i = 1, 8 do lines[i] = NewLine() end
    return lines
end

local function UpdateCornerBox(lines, minX, maxX, minY, maxY, color, visible, transparency)
    if not visible then
        for i = 1, 8 do lines[i].Visible = false end
        return
    end
    local cx = (maxX - minX) * CORNER_RATIO
    local cy = (maxY - minY) * CORNER_RATIO
    local tl = Vector2.new(minX, minY)
    local tr = Vector2.new(maxX, minY)
    local bl = Vector2.new(minX, maxY)
    local br = Vector2.new(maxX, maxY)
    lines[1].From = tl; lines[1].To = tl + Vector2.new(cx,  0)
    lines[2].From = tl; lines[2].To = tl + Vector2.new(0,  cy)
    lines[3].From = tr; lines[3].To = tr + Vector2.new(-cx, 0)
    lines[4].From = tr; lines[4].To = tr + Vector2.new(0,  cy)
    lines[5].From = bl; lines[5].To = bl + Vector2.new(cx,  0)
    lines[6].From = bl; lines[6].To = bl + Vector2.new(0, -cy)
    lines[7].From = br; lines[7].To = br + Vector2.new(-cx, 0)
    lines[8].From = br; lines[8].To = br + Vector2.new(0, -cy)
    for i = 1, 8 do
        lines[i].Color        = color
        lines[i].Transparency = transparency or 1
        lines[i].Visible      = true
    end
end

local function DestroyCornerBox(lines)
    for i = 1, 8 do RemoveDrawing(lines[i]) end
end

local KEYBIND_DEFS = {
    { "F1", "ESP",       "ESP" },
    { "F2", "Arrows",    "Arrows" },
    { "F3", "Skeleton",  "Skeleton" },
    { "F4", "HealthBar", "Health Bar" },
    { "F5", "Names",     "Names" },
}

local HUD_RIGHT_MARGIN = 10
local HUD_TOP_MARGIN   = 10
local HUD_LINE_HEIGHT  = 18
local HUD_FONT_SIZE    = 14

local hudLabels  = {}
local hudVisible = true

for i, def in ipairs(KEYBIND_DEFS) do
    local t = Track(Drawing.new("Text"))
    t.Size = HUD_FONT_SIZE; t.Center = false; t.Outline = true
    t.Transparency = 1; t.Visible = true
    t.Text  = string.format("[%s] %s: %s", def[1], def[3], Flags[def[2]] and "ON" or "OFF")
    t.Color = Flags[def[2]] and COLOR_ON or COLOR_OFF
    hudLabels[i] = { drawing = t, flag = def[2] }
end

local function UpdateHUDPositions()
    local vp = Camera.ViewportSize
    for i, entry in ipairs(hudLabels) do
        local t = entry.drawing
        t.Position = Vector2.new(vp.X - #t.Text * 6 - HUD_RIGHT_MARGIN, HUD_TOP_MARGIN + (i-1) * HUD_LINE_HEIGHT)
        t.Color    = Flags[entry.flag] and COLOR_ON or COLOR_OFF
        t.Text     = string.format("[%s] %s: %s", KEYBIND_DEFS[i][1], KEYBIND_DEFS[i][3], Flags[entry.flag] and "ON" or "OFF")
    end
end

local function UpdateHUDVisibility()
    for _, entry in ipairs(hudLabels) do
        entry.drawing.Visible = hudVisible
    end
end

local KEY_TO_FLAG = {
    [Enum.KeyCode.F1] = "ESP",
    [Enum.KeyCode.F2] = "Arrows",
    [Enum.KeyCode.F3] = "Skeleton",
    [Enum.KeyCode.F4] = "HealthBar",
    [Enum.KeyCode.F5] = "Names",
}

UIS.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    if input.KeyCode == Enum.KeyCode.F1 then
        local newState = not Flags.ESP
        for k in pairs(Flags) do Flags[k] = newState end
        hudVisible = newState
        UpdateHUDVisibility()
        for i, entry in ipairs(hudLabels) do
            entry.drawing.Color = Flags[entry.flag] and COLOR_ON or COLOR_OFF
            entry.drawing.Text  = string.format("[%s] %s: %s", KEYBIND_DEFS[i][1], KEYBIND_DEFS[i][3], Flags[entry.flag] and "ON" or "OFF")
        end
        return
    end
    local flag = KEY_TO_FLAG[input.KeyCode]
    if flag then
        if not Flags.ESP then
            for k in pairs(Flags) do Flags[k] = true end
            hudVisible = true
            UpdateHUDVisibility()
        else
            Flags[flag] = not Flags[flag]
        end
        for i, entry in ipairs(hudLabels) do
            if entry.flag == flag then
                entry.drawing.Color = Flags[flag] and COLOR_ON or COLOR_OFF
                entry.drawing.Text  = string.format("[%s] %s: %s", KEYBIND_DEFS[i][1], KEYBIND_DEFS[i][3], Flags[flag] and "ON" or "OFF")
                break
            end
        end
    end
end)

local R15_PAIRS = {
    {"Head","UpperTorso"},{"UpperTorso","LowerTorso"},
    {"UpperTorso","LeftUpperArm"},{"LeftUpperArm","LeftLowerArm"},{"LeftLowerArm","LeftHand"},
    {"UpperTorso","RightUpperArm"},{"RightUpperArm","RightLowerArm"},{"RightLowerArm","RightHand"},
    {"LowerTorso","LeftUpperLeg"},{"LeftUpperLeg","LeftLowerLeg"},{"LeftLowerLeg","LeftFoot"},
    {"LowerTorso","RightUpperLeg"},{"RightUpperLeg","RightLowerLeg"},{"RightLowerLeg","RightFoot"},
}

local R6_PAIRS = {
    {"Head",Vector3.new(0,0,0),"Torso",Vector3.new(0,1,0)},
    {"Torso",Vector3.new(0,1,0),"Torso",Vector3.new(0,-1,0)},
    {"Torso",Vector3.new(0,1,0),"Left Arm",Vector3.new(0,1,0)},
    {"Left Arm",Vector3.new(0,1,0),"Left Arm",Vector3.new(0,-1,0)},
    {"Torso",Vector3.new(0,1,0),"Right Arm",Vector3.new(0,1,0)},
    {"Right Arm",Vector3.new(0,1,0),"Right Arm",Vector3.new(0,-1,0)},
    {"Torso",Vector3.new(0,-1,0),"Left Leg",Vector3.new(0,1,0)},
    {"Left Leg",Vector3.new(0,1,0),"Left Leg",Vector3.new(0,-1,0)},
    {"Torso",Vector3.new(0,-1,0),"Right Leg",Vector3.new(0,1,0)},
    {"Right Leg",Vector3.new(0,1,0),"Right Leg",Vector3.new(0,-1,0)},
}

local function MakeBones(isR15)
    local bones = {}
    if isR15 then
        for _, p in ipairs(R15_PAIRS) do
            bones[#bones+1] = {line=NewLine(), fromName=p[1], toName=p[2]}
        end
    else
        for _, p in ipairs(R6_PAIRS) do
            bones[#bones+1] = {line=NewLine(), fromPart=p[1], fromOff=p[2], toPart=p[3], toOff=p[4], isR6=true}
        end
    end
    return bones
end

local function UpdateBones(bones, char)
    for _, b in ipairs(bones) do
        if b.isR6 then
            local pF = Part(char, b.fromPart)
            local pT = Part(char, b.toPart)
            if pF and pT then
                local wF = (pF.CFrame * CFrame.new(b.fromOff)).Position
                local wT = (pT.CFrame * CFrame.new(b.toOff)).Position
                local sF = ToScreen(wF)
                local sT = ToScreen(wT)
                b.line.From = Vector2.new(sF.X, sF.Y)
                b.line.To   = Vector2.new(sT.X, sT.Y)
            end
        else
            local pF = Part(char, b.fromName)
            local pT = Part(char, b.toName)
            if pF and pT then
                local sF = ToScreen(pF.Position)
                local sT = ToScreen(pT.Position)
                b.line.From = Vector2.new(sF.X, sF.Y)
                b.line.To   = Vector2.new(sT.X, sT.Y)
            end
        end
    end
end

local function SetBonesVisible(bones, state)
    for _, b in ipairs(bones) do b.line.Visible = state end
end

local function SetBonesColor(bones, color, transparency)
    for _, b in ipairs(bones) do
        b.line.Color        = color
        b.line.Transparency = transparency or 1
    end
end

local function DestroyBones(bones)
    for _, b in ipairs(bones) do RemoveDrawing(b.line) end
end

local BODY_PARTS_R15 = {
    "Head","UpperTorso","LowerTorso",
    "LeftUpperArm","LeftLowerArm","LeftHand",
    "RightUpperArm","RightLowerArm","RightHand",
    "LeftUpperLeg","LeftLowerLeg","LeftFoot",
    "RightUpperLeg","RightLowerLeg","RightFoot",
}
local BODY_PARTS_R6 = {
    "Head","Torso","Left Arm","Right Arm","Left Leg","Right Leg"
}

local CORNERS_3D = {
    Vector3.new(-0.5,-0.5,-0.5), Vector3.new( 0.5,-0.5,-0.5),
    Vector3.new(-0.5, 0.5,-0.5), Vector3.new( 0.5, 0.5,-0.5),
    Vector3.new(-0.5,-0.5, 0.5), Vector3.new( 0.5,-0.5, 0.5),
    Vector3.new(-0.5, 0.5, 0.5), Vector3.new( 0.5, 0.5, 0.5),
}

local function CalcScreenBounds(char, isR15)
    local partNames = isR15 and BODY_PARTS_R15 or BODY_PARTS_R6
    local minX, minY =  math.huge,  math.huge
    local maxX, maxY = -math.huge, -math.huge
    local anyVisible = false
    local vp = Camera.ViewportSize
    for _, name in ipairs(partNames) do
        local part = char:FindFirstChild(name)
        if part and part:IsA("BasePart") then
            local cf   = part.CFrame
            local size = part.Size
            for _, corner in ipairs(CORNERS_3D) do
                local worldPos = cf * (corner * size)
                local screen   = ToScreen(worldPos)
                if screen.Z > 0 then
                    anyVisible = true
                    local sx = math.clamp(screen.X, -vp.X * 0.5, vp.X * 1.5)
                    local sy = math.clamp(screen.Y, -vp.Y * 0.5, vp.Y * 1.5)
                    if sx < minX then minX = sx end
                    if sy < minY then minY = sy end
                    if sx > maxX then maxX = sx end
                    if sy > maxY then maxY = sy end
                end
            end
        end
    end
    if not anyVisible or minX == math.huge then return nil, nil, nil, nil end
    if maxX - minX < 1 or maxY - minY < 1  then return nil, nil, nil, nil end
    return minX, maxX, minY, maxY
end

local function StartArrow(char, plr, isNPC, entity)
    local arrow = NewTriangle()
    local conn
    conn = RunService.RenderStepped:Connect(function()
        if not char or not char.Parent then
            RemoveDrawing(arrow); conn:Disconnect(); return
        end
        arrow.Visible = false
        if not Flags.Arrows then return end
        
        -- Check Rendered attribute
        if not ShouldRender(char) then return end
        
        local hum = char:FindFirstChildOfClass("Humanoid")
        if not hum or hum.Health <= 0 or not char.PrimaryPart then return end
        local sPos, onScreen = ToScreen(char.PrimaryPart.Position)
        if not onScreen then
            local vp     = Camera.ViewportSize
            local center = vp / 2
            local dir    = Vector2.new(sPos.X, sPos.Y) - center
            if dir.Magnitude < 0.001 then return end
            dir = dir.Unit
            local angle  = math.atan2(dir.Y, dir.X)
            local cos, sin = math.cos(angle), math.sin(angle)
            local halfW  = vp.X / 2 - 40
            local halfH  = vp.Y / 2 - 40
            local scaleX = math.abs(cos) > 0.001 and halfW / math.abs(cos) or math.huge
            local scaleY = math.abs(sin) > 0.001 and halfH / math.abs(sin) or math.huge
            local tip    = center + Vector2.new(cos, sin) * math.min(scaleX, scaleY)
            local perp   = Vector2.new(-sin, cos)
            arrow.PointA      = tip + dir * 15
            arrow.PointB      = tip - dir * 7.5 + perp * 7.5
            arrow.PointC      = tip - dir * 7.5 - perp * 7.5
            local visible     = IsVisible(char)
            arrow.Color       = GetESPColor(plr, visible, isNPC, entity or char)
            arrow.Transparency = (isNPC and not visible) and 0.75 or 1
            arrow.Visible     = true
        end
    end)
end

local function StartESP(char, plr, isNPC, entity)
    if not char then return end
    local humanoid = char:FindFirstChildOfClass("Humanoid")
    if not humanoid then return end
    local isR15 = (humanoid.RigType == Enum.HumanoidRigType.R15)

    local cornerLines = NewCornerBox()
    local nameLbl     = NewTextCentered(14)
    local teamLbl     = NewTextCentered(13)
    local heldLbl     = NewTextCentered(12)
    local hpBG        = NewLine()
    local hpFill      = NewLine()
    hpBG.Color = Color3.fromRGB(0,0,0); hpBG.Thickness = 3
    hpFill.Thickness = 1.5

    local bones = MakeBones(isR15)

    local function HideAll()
        UpdateCornerBox(cornerLines, 0, 0, 0, 0, Color3.new(), false)
        nameLbl.Visible = false; teamLbl.Visible = false
        heldLbl.Visible = false; hpBG.Visible    = false
        hpFill.Visible  = false
        SetBonesVisible(bones, false)
    end

    local function Cleanup()
        HideAll()
        DestroyCornerBox(cornerLines)
        RemoveDrawing(nameLbl); RemoveDrawing(teamLbl)
        RemoveDrawing(heldLbl); RemoveDrawing(hpBG); RemoveDrawing(hpFill)
        DestroyBones(bones)
    end

    local renderConn
    renderConn = RunService.RenderStepped:Connect(function()
        if not char or not char.Parent then
            Cleanup(); renderConn:Disconnect(); return
        end
        
        -- Check Rendered attribute - if false, hide everything
        if not ShouldRender(char) then
            HideAll()
            return
        end
        
        local hum  = char:FindFirstChildOfClass("Humanoid")
        local root = Part(char, "HumanoidRootPart")
        if not hum or not root or hum.Health <= 0 then HideAll(); return end
        if isNPC then
            local dist = (root.Position - Camera.CFrame.Position).Magnitude
            if dist > NPC_MAX_DISTANCE then HideAll(); return end
        end
        local _, onScreen = ToScreen(root.Position)
        if not onScreen or not Flags.ESP then HideAll(); return end
        local visible      = IsVisible(char)
        local isHostage    = IsHostage(entity or char)
        local color        = GetESPColor(plr, visible, isNPC, entity or char)
        local transparency = (isNPC and not visible) and 0.75 or 1
        
        -- Hostage is always opaque
        if isHostage then
            transparency = 1
        end
        
        if Flags.Skeleton then
            SetBonesColor(bones, color, transparency)
            UpdateBones(bones, char)
            SetBonesVisible(bones, true)
        else
            SetBonesVisible(bones, false)
        end
        local minX, maxX, minY, maxY = CalcScreenBounds(char, isR15)
        if minX then
            UpdateCornerBox(cornerLines, minX, maxX, minY, maxY, color, true, transparency)
            local midX = (minX + maxX) / 2
            if Flags.Names then
                nameLbl.Text         = GetNameLabel(plr, char, isNPC, entity or char)
                nameLbl.Color        = color
                nameLbl.Transparency = transparency
                nameLbl.Position     = Vector2.new(midX, minY - 16)
                nameLbl.Visible      = true
                if not isNPC and not isHostage then
                    local tl = GetTeamLabel(plr)
                    if tl then
                        teamLbl.Text         = tl
                        teamLbl.Color        = color
                        teamLbl.Transparency = transparency
                        teamLbl.Position     = Vector2.new(midX, maxY + 4)
                        teamLbl.Visible      = true
                    else
                        teamLbl.Visible = false
                    end
                else
                    teamLbl.Visible = false
                end
                local tool = GetHeldTool(char)
                if tool then
                    heldLbl.Text         = tool
                    heldLbl.Color        = color
                    heldLbl.Transparency = transparency
                    heldLbl.Position     = Vector2.new(midX, maxY + 17)
                    heldLbl.Visible      = true
                else
                    heldLbl.Visible = false
                end
            else
                nameLbl.Visible = false; teamLbl.Visible = false; heldLbl.Visible = false
            end
            if Flags.HealthBar then
                local hp, maxHp = GetHealth(char)
                if hp and maxHp and maxHp > 0 then
                    local pct  = math.clamp(hp / maxHp, 0, 1)
                    local barX = minX - 4
                    local h    = maxY - minY
                    hpBG.From         = Vector2.new(barX, minY)
                    hpBG.To           = Vector2.new(barX, maxY)
                    hpBG.Transparency = transparency
                    hpBG.Visible      = true
                    hpFill.From         = Vector2.new(barX, maxY)
                    hpFill.To           = Vector2.new(barX, maxY - h * pct)
                    hpFill.Color        = Color3.fromRGB(255,0,0):Lerp(Color3.fromRGB(0,255,0), pct)
                    hpFill.Transparency = transparency
                    hpFill.Visible      = true
                else
                    hpBG.Visible = false; hpFill.Visible = false
                end
            else
                hpBG.Visible = false; hpFill.Visible = false
            end
        else
            UpdateCornerBox(cornerLines, 0, 0, 0, 0, color, false)
            nameLbl.Visible = false; teamLbl.Visible = false
            heldLbl.Visible = false; hpBG.Visible    = false
            hpFill.Visible  = false
        end
    end)
end

RunService.RenderStepped:Connect(UpdateHUDPositions)

local function FindAllNPCs()
    local npcs = {}
    for _, model in ipairs(workspace:GetDescendants()) do
        if model:IsA("Model") then
            local attrs = model:GetAttributes()
            if attrs and attrs.AI == true and model:FindFirstChildOfClass("Humanoid") then
                table.insert(npcs, model)
            end
        end
    end
    return npcs
end

local trackedNPCs = {}
local trackedHostages = {}

-- Initialize a Hostage
local function InitHostage(hostage)
    if trackedHostages[hostage] then return end
    trackedHostages[hostage] = true
    coroutine.wrap(function()
        -- Wait for Humanoid to load
        local hum = hostage:FindFirstChildOfClass("Humanoid")
        if not hum then
            hum = hostage:WaitForChild("Humanoid", 5)
        end
        if hum then
            StartESP(hostage, nil, false, hostage)
            StartArrow(hostage, nil, false, hostage)
        end
    end)()
end

-- Find and initialize all Hostages (ONLY in Buildings.Loots.Objects)
local function InitAllHostages()
    local hostages = FindAllHostages()
    for _, hostage in ipairs(hostages) do
        InitHostage(hostage)
    end
end

local function InitNPC(npc)
    if trackedNPCs[npc] then return end
    trackedNPCs[npc] = true
    coroutine.wrap(function()
        StartESP(npc, nil, true, npc)
        StartArrow(npc, nil, true, npc)
    end)()
end

local function TryInitNPC(model)
    if not model:IsA("Model") then return end
    
    -- Check if it's a Hostage (by name)
    if IsHostage(model) then
        if not trackedHostages[model] then
            InitHostage(model)
        end
        return
    end
    
    local attrs = model:GetAttributes()
    if not (attrs and attrs.AI == true) then return end
    if trackedNPCs[model] then return end
    local hum = model:FindFirstChildOfClass("Humanoid")
    if hum then
        InitNPC(model)
    else
        local conn
        conn = model.ChildAdded:Connect(function(child)
            if child:IsA("Humanoid") then
                conn:Disconnect()
                if IsHostage(model) then
                    InitHostage(model)
                else
                    InitNPC(model)
                end
            end
        end)
        task.delay(5, function()
            if conn then conn:Disconnect() end
        end)
    end
end

local function SetupNPCWatcher()
    -- Check existing NPCs and Hostages
    InitAllHostages()
    
    for _, model in ipairs(workspace:GetDescendants()) do
        if model:IsA("Model") then
            local attrs = model:GetAttributes()
            if attrs and attrs.AI == true then
                TryInitNPC(model)
            end
        end
    end
    
    workspace.DescendantAdded:Connect(function(descendant)
        TryInitNPC(descendant)
        if descendant:IsA("Model") then
            task.defer(function() TryInitNPC(descendant) end)
        end
    end)
    
    -- Watch specifically for new Hostages in Buildings.Loots.Objects
    local buildings = workspace:FindFirstChild("Buildings")
    if buildings then
        buildings.DescendantAdded:Connect(function(descendant)
            if descendant:IsA("Model") and IsHostage(descendant) then
                InitHostage(descendant)
            end
        end)
    end
end

local function InitPlayer(plr)
    if plr == LocalPlayer then return end
    coroutine.wrap(function()
        local char = plr.Character or plr.CharacterAdded:Wait()
        StartESP(char, plr, false, char)
        StartArrow(char, plr, false, char)
        plr.CharacterAdded:Connect(function(newChar)
            StartESP(newChar, plr, false, newChar)
            StartArrow(newChar, plr, false, newChar)
        end)
    end)()
end

for _, plr in ipairs(Players:GetPlayers()) do
    InitPlayer(plr)
end
Players.PlayerAdded:Connect(InitPlayer)
SetupNPCWatcher()

end -- end RunESP()

-- ==================== Start ESP ====================

RunESP()
