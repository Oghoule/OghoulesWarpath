-- Oghoule's Warpath : moteur (Arrow.lua) - fleche de l'addon (style "pointe fine"), voir Core.lua
local ADDON, ns = ...
local _ENV = ns.CoreEnv
if setfenv then setfenv(1, _ENV) end

-- La fleche tourne vers la prochaine position du trajet (distTarget) a partir de ta position et de ton
-- orientation. Hors instance seulement : en donjon et en raid, le jeu ne donne plus ces informations.
do
    local frame, tex, gem, dist, last
    local ON_COURSE = math.rad(12) -- losange rouge si on vise a moins de 12 degres
    local ARRIVE = 8          -- metres : en dessous, la fleche devient un losange "tu y es"
    local AREA_IN, AREA_OUT = 50, 250  -- zone de chasse : cachee des que tu y es (50 m), revient seulement au-dela de 250 m
    local inArea, areaKey = false, nil

    local function Create()
        if frame then return end
        frame = CreateFrame("Frame", "WarpathArrow", UIParent)
        frame:SetSize(64, 84)
        frame:SetFrameStrata("MEDIUM")
        frame:SetClampedToScreen(true)
        local p = DB.arrowPos
        if p then frame:SetPoint(p[1], UIParent, p[1], p[2], p[3]) else frame:SetPoint("TOP", UIParent, "TOP", 0, -140) end
        tex = frame:CreateTexture(nil, "ARTWORK")
        tex:SetSize(64, 64); tex:SetPoint("TOP")
        tex:SetTexture("Interface\\AddOns\\" .. ADDON .. "\\Media\\Arrow")
        gem = frame:CreateTexture(nil, "OVERLAY")
        gem:SetSize(64, 64); gem:SetPoint("TOP")
        gem:SetTexture("Interface\\AddOns\\" .. ADDON .. "\\Media\\ArrowGem")
        dist = FS(frame, 11, COL.gold, FONT, "CENTER"); dist:SetPoint("TOP", tex, "BOTTOM", 0, -2)
        -- deplacement (si la fenetre n'est pas verrouillee)
        frame:EnableMouse(true)
        frame:RegisterForDrag("LeftButton")
        frame:SetMovable(true)
        frame:SetScript("OnDragStart", function(self) if not DB.locked then self:StartMoving() end end)
        frame:SetScript("OnDragStop", function(self)
            self:StopMovingOrSizing()
            local point, _, _, x, y = self:GetPoint(1)
            DB.arrowPos = { point, math.floor(x + 0.5), math.floor(y + 0.5) }
        end)
        frame:SetScript("OnEnter", function(self)
            Tip():SetOwner(self, "ANCHOR_BOTTOM"); Tip():AddLine(T("arrowTipShort"), 1, 1, 1, true); Tip():Show()
        end)
        frame:SetScript("OnLeave", function() Tip():Hide() end)
        frame:Hide()
    end

    local function Update()
        if not DB or DB.wp == false or DB.ownArrow == false or not distTarget then
            if frame then frame:Hide() end; return
        end
        local inst = IsInInstance and IsInInstance()
        if inst then if frame then frame:Hide() end; return end
        local facing = GetPlayerFacing and GetPlayerFacing()
        local me = PlayerWP()
        local w = WP(distTarget[1], distTarget[2], distTarget[3])
        if type(facing) ~= "number" or not me or not w or me[3] ~= w[3] then
            if frame then frame:Hide() end; return
        end
        Create()
        local dx, dy = w[1] - me[1], w[2] - me[2]          -- x : nord, y : ouest
        local d = math.sqrt(dx * dx + dy * dy)
        local tk = distTarget[1] .. ":" .. distTarget[2] .. ":" .. distTarget[3]
        if tk ~= areaKey then areaKey = tk; inArea = false end   -- nouvelle etape : on repart de zero
        if distTarget[4] then
            if d < AREA_IN then inArea = true elseif d > AREA_OUT then inArea = false end
            if inArea then frame:Hide(); return end
        else inArea = false end
        if d < ARRIVE then
            tex:SetTexture("Interface\\AddOns\\" .. ADDON .. "\\Media\\ArrowHere"); tex:SetRotation(0); gem:Hide()
            dist:SetText(Caps(T("arrowHere")))
        else
            tex:SetTexture("Interface\\AddOns\\" .. ADDON .. "\\Media\\Arrow")
            local ang = math.atan2(dy, dx) - facing
            ang = (ang + math.pi) % (2 * math.pi) - math.pi      -- ramene entre -pi et pi
            tex:SetRotation(ang); gem:SetRotation(ang); gem:Show()
            if math.abs(ang) < ON_COURSE then gem:SetVertexColor(0.80, 0.14, 0.18) else gem:SetVertexColor(0.55, 0.55, 0.55) end
            dist:SetText(Caps(T("dist", math.floor(d + 0.5))))
        end
        frame:SetScale(DB.arrowScale or 1)
        frame:Show()
    end

    -- Icone Warpath sur la minicarte (losange de l'addon), calculee comme le font les addons de cartes :
    -- taille de la minicarte en metres selon le zoom (exterieur / interieur), rotation si la minicarte tourne,
    -- et collee au bord quand l'objectif est hors de la minicarte.
    local pin, pinTex
    local OUT = { 466 + 2 / 3, 400, 333 + 1 / 3, 266 + 2 / 3, 200, 133 + 1 / 3 }
    local IN = { 300, 240, 180, 120, 80, 50 }
    local function UpdatePin()
        local mmap = _G.Minimap
        if not mmap or not DB or DB.wp == false or DB.mmPin == false or not distTarget
            or (IsInInstance and IsInInstance()) then
            if pin then pin:Hide() end; return
        end
        local me = PlayerWP()
        local w = WP(distTarget[1], distTarget[2], distTarget[3])
        if not me or not w or me[3] ~= w[3] then if pin then pin:Hide() end; return end
        if not pin then
            pin = CreateFrame("Frame", "WarpathMinimapPin", mmap)
            pin:SetSize(16, 16)
            pin:SetFrameStrata(mmap:GetFrameStrata())
            pin:SetFrameLevel(mmap:GetFrameLevel() + 8)
            pinTex = pin:CreateTexture(nil, "OVERLAY"); pinTex:SetAllPoints()
            pinTex:SetTexture("Interface\\AddOns\\" .. ADDON .. "\\Media\\ArrowHere")
        end
        local zoom = (mmap.GetZoom and mmap:GetZoom() or 0) + 1
        local diam = ((IsIndoors and IsIndoors()) and IN or OUT)[zoom] or OUT[1]
        local dx, dy = w[1] - me[1], w[2] - me[2]          -- x : nord, y : ouest
        local sx, sy = -dy, dx                               -- a l'ecran : droite = est, haut = nord
        if GetCVar and GetCVar("rotateMinimap") == "1" then
            local f = -(GetPlayerFacing and GetPlayerFacing() or 0)
            local c, s = math.cos(f), math.sin(f)
            sx, sy = sx * c - sy * s, sx * s + sy * c
        end
        local half = mmap:GetWidth() / 2
        local k = half / (diam / 2)
        sx, sy = sx * k, sy * k
        local r = half - 7
        local d = math.sqrt(sx * sx + sy * sy)
        local square = GetMinimapShape and GetMinimapShape() == "SQUARE"
        local edge = false
        if square then
            local m = math.max(math.abs(sx), math.abs(sy))
            if m > r then sx, sy = sx * r / m, sy * r / m; edge = true end
        elseif d > r then
            sx, sy = sx * r / d, sy * r / d; edge = true
        end
        pin:ClearAllPoints()
        pin:SetPoint("CENTER", mmap, "CENTER", sx, sy)
        pin:SetAlpha(edge and 0.75 or 1)
        pin:SetSize(edge and 13 or 16, edge and 13 or 16)
        pin:Show()
    end

    -- v1.43 (demande de l'auteur) : la petite fleche du bloc destination (fenetre du guide) tourne comme la
    -- grande, meme si la grande est coupee dans les options. Fixe (vers le haut) sans direction : instance,
    -- autre carte, pas de destination, arrive. L'icone IcoNav pointe vers le haut comme Media/Arrow.
    -- Interieur (Media/IcoNavFill, meme forme) : rouge discret en fondu quand on vise juste (< 12 degres,
    -- comme le losange de la grande fleche), sous le contour.
    local fill, fillA = nil, 0
    local FILL_MAX, FILL_SPEED = 0.65, 2.5 -- opacite au maximum ; vitesse du fondu (par seconde)
    local function UpdateDestIcon(el)
        local ic = f and rawget(f, "dest") and f.dest.arrow
        if not (ic and ic.SetRotation) then return end
        if not fill then
            fill = ic:GetParent():CreateTexture(nil, "ARTWORK", nil, -1)
            fill:SetAllPoints(ic)
            fill:SetTexture("Interface\\AddOns\\" .. ADDON .. "\\Media\\IcoNavFill")
            fill:SetVertexColor(COL.red[1], COL.red[2], COL.red[3])
            fill:SetAlpha(0)
        end
        local ang, aim = 0, false
        local facing = GetPlayerFacing and GetPlayerFacing()
        if distTarget and type(facing) == "number" and not (IsInInstance and IsInInstance()) then
            local me = PlayerWP()
            local w = WP(distTarget[1], distTarget[2], distTarget[3])
            if me and w and me[3] == w[3] then
                local dx, dy = w[1] - me[1], w[2] - me[2]
                if dx * dx + dy * dy >= ARRIVE * ARRIVE then
                    ang = math.atan2(dy, dx) - facing
                    ang = (ang + math.pi) % (2 * math.pi) - math.pi
                    aim = math.abs(ang) < ON_COURSE
                end
            end
        end
        ic:SetRotation(ang); fill:SetRotation(ang)
        local target = aim and FILL_MAX or 0
        local step = FILL_SPEED * FILL_MAX * (el or 0.04)
        if fillA < target then fillA = math.min(target, fillA + step) elseif fillA > target then fillA = math.max(target, fillA - step) end
        fill:SetAlpha(fillA)
    end

    local ticker = CreateFrame("Frame")
    local acc = 0
    ticker:SetScript("OnUpdate", function(_, el)
        acc = acc + el
        if acc < 0.04 then return end
        acc = 0
        local ok = pcall(Update)
        if not ok and frame then frame:Hide() end
        if not pcall(UpdatePin) and pin then pin:Hide() end
        pcall(UpdateDestIcon, 0.04)
    end)

    ns.Arrow = { Reset = function() DB.arrowPos = nil; if frame then frame:ClearAllPoints(); frame:SetPoint("TOP", UIParent, "TOP", 0, -140) end end }
end
