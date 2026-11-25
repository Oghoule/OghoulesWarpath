-- Oghoule's Warpath : moteur (Arrow.lua) - fleche de l'addon (style "pointe fine"), voir Core.lua
local ADDON, ns = ...
local _ENV = ns.CoreEnv
if setfenv then setfenv(1, _ENV) end

-- La fleche tourne vers la prochaine position du trajet (distTarget) a partir de ta position et de ton
-- orientation. Hors instance seulement : en donjon et en raid, le jeu ne donne plus ces informations.
do
    local frame, tex, gem, dist, last
    local ArrowMenu   -- (defini plus bas : menu du clic droit)
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
            Tip():SetOwner(self, "ANCHOR_BOTTOM"); Tip():AddLine(T("arrowTipShort"), 1, 1, 1, true)
            Tip():AddLine(T("arrowTipKeys"), COL.soft[1], COL.soft[2], COL.soft[3], true); Tip():Show()
        end)
        frame:SetScript("OnLeave", function() Tip():Hide() end)
        -- v1.46 : Ctrl + molette = taille (sans Ctrl, la molette ne fait rien sur la fleche)
        frame:EnableMouseWheel(true)
        frame:SetScript("OnMouseWheel", function(_, delta)
            if not (IsControlKeyDown and IsControlKeyDown()) then return end
            DB.arrowScale = math.max(0.6, math.min(1.6, math.floor(((DB.arrowScale or 1) + delta * 0.05) * 20 + 0.5) / 20))
            frame:SetScale(DB.arrowScale)
            if ns.UI and ns.UI.RefreshOptions then pcall(ns.UI.RefreshOptions) end
        end)
        -- v1.46 : clic droit = petit menu (options de la fleche, replacer, masquer)
        frame:SetScript("OnMouseUp", function(self, button)
            if button == "RightButton" and ArrowMenu then ArrowMenu(self) end
        end)
        frame:Hide()
    end

    -- menu du clic droit : trois boutons dans un cadre de l'addon ; se ferme apres un choix, au 2e clic droit,
    -- ou 2 s apres que la souris l'a quitte
    local menu
    function ArrowMenu(anchor)
        if menu and menu:IsShown() then menu:Hide(); return end
        if not menu then
            menu = CreateFrame("Frame", "WarpathArrowMenu", UIParent)
            menu:SetSize(196, 3 * 26 + 12); menu:SetFrameStrata("DIALOG"); menu:SetClampedToScreen(true)
            local bg = menu:CreateTexture(nil, "BACKGROUND"); bg:SetColorTexture(COL.bg[1], COL.bg[2], COL.bg[3], 0.96); bg:SetAllPoints()
            Border(menu, COL.accent, 0.6)
            local items = {
                { "arrowMenuOpts", function() if ns.UI and ns.UI.OpenOptionsTab then ns.UI.OpenOptionsTab(6) end end },
                { "arrowReset", function() if ns.Arrow then ns.Arrow.Reset() end end },
                { "arrowMenuHide", function()
                    DB.ownArrow = false; lastWP = nil; Refresh(true)
                    say(T("arrowHidden"))
                end },
            }
            menu.btns = {}
            for k, it in ipairs(items) do
                local b = FlatButton(menu, 184, 24, function() menu:Hide(); it[2]() end)
                b:SetPoint("TOP", menu, "TOP", 0, -6 - (k - 1) * 26)
                b.key = it[1]
                menu.btns[k] = b
            end
            local idle = 0
            menu:SetScript("OnUpdate", function(self, el)
                if self:IsMouseOver() then idle = 0 else idle = idle + el; if idle > 2 then self:Hide() end end
            end)
            menu:SetScript("OnShow", function() idle = 0 end)
        end
        for _, b in ipairs(menu.btns) do b:SetLabel(Caps(T(b.key))) end
        menu:ClearAllPoints(); menu:SetPoint("TOP", anchor, "BOTTOM", 0, -4)
        menu:Show()
    end

    -- v1.46 : apercu pendant le reglage (onglet Apparence ouvert) : la fleche reste visible, droite,
    -- meme sans objectif ou une fois arrive
    local preview = false
    local function Preview()
        if not (DB and DB.wp ~= false and DB.ownArrow ~= false) then return end
        Create()
        tex:SetTexture("Interface\\AddOns\\" .. ADDON .. "\\Media\\Arrow"); tex:SetRotation(0)
        gem:SetRotation(0); gem:SetVertexColor(0.80, 0.14, 0.18); gem:Show()
        dist:SetText(Caps(T("arrowPreview")))
        frame:SetScale(DB.arrowScale or 1)
        frame:Show()
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
    -- v1.46 (retour d'un joueur : il ne voyait pas ou etait l'objectif sur la carte) : halo en losange qui
    -- grandit et s'efface, derriere l'icone de la minicarte et le repere de la carte du monde (option mapPin)
    local PULSE = 1.6   -- secondes par pulsation
    local function Pulse(halo, base)
        if DB.mapPin == false then halo:Hide(); return end
        local ph = ((GetTime and GetTime() or 0) % PULSE) / PULSE
        local s = base * (1 + ph * 1.4)
        halo:SetSize(s, s); halo:SetAlpha(0.8 * (1 - ph)); halo:Show()
    end
    local function Halo(parent)
        local h = parent:CreateTexture(nil, "ARTWORK")
        h:SetPoint("CENTER"); h:SetTexture("Interface\\AddOns\\" .. ADDON .. "\\Media\\Gem")
        return h
    end
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
            pin.halo = Halo(pin)
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
        pin:SetSize(edge and 15 or 20, edge and 15 or 20)
        Pulse(pin.halo, edge and 15 or 20)
        pin:Show()
    end

    -- v1.46 : repere Warpath sur la carte du monde (le point jaune du jeu reste), seulement quand la carte
    -- affichee est celle de la destination. Place comme les entraineurs de Profs.lua (enfant du canevas,
    -- echelle inverse du zoom). Pas de souris : il ne gene pas les clics sur la carte.
    local wpin
    local WPIN = 26
    local function UpdateMapPin()
        local wm = _G.WorldMapFrame
        local child = wm and wm.ScrollContainer and wm.ScrollContainer.Child
        if not (child and wm:IsShown()) or not DB or DB.wp == false or DB.mapPin == false or not distTarget
            or not (wm.GetMapID and wm:GetMapID() == distTarget[1]) then
            if wpin then wpin:Hide() end; return
        end
        if not wpin then
            wpin = CreateFrame("Frame", "WarpathWorldMapPin", child)
            wpin:SetSize(WPIN, WPIN); wpin:SetFrameStrata("HIGH")
            wpin.halo = Halo(wpin)
            local gem = wpin:CreateTexture(nil, "OVERLAY"); gem:SetAllPoints()
            gem:SetTexture("Interface\\AddOns\\" .. ADDON .. "\\Media\\Gem")
        end
        local cs = child:GetScale() or 1
        wpin:SetScale(1 / cs)
        wpin:ClearAllPoints()
        wpin:SetPoint("CENTER", child, "TOPLEFT", distTarget[2] / 100 * child:GetWidth() * cs, -distTarget[3] / 100 * child:GetHeight() * cs)
        Pulse(wpin.halo, WPIN)
        wpin:Show()
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
        if preview and not (frame and frame:IsShown()) then pcall(Preview) end
        if not pcall(UpdatePin) and pin then pin:Hide() end
        if not pcall(UpdateMapPin) and wpin then wpin:Hide() end
        pcall(UpdateDestIcon, 0.04)
    end)

    ns.Arrow = {
        Reset = function() DB.arrowPos = nil; if frame then frame:ClearAllPoints(); frame:SetPoint("TOP", UIParent, "TOP", 0, -140) end end,
        Preview = function(on) preview = on and true or false end,
    }
end
