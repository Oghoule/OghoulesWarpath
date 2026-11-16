-- Oghoule's Warpath : moteur (Targets.lua) - petite fenetre de ciblage, voir Core.lua
local ADDON, ns = ...
local _ENV = ns.CoreEnv
if setfenv then setfenv(1, _ENV) end

-- Une ligne cliquable par PNJ utile a l'etape (donneur, a qui rendre, monstres, maitre de vol).
-- Chaque ligne est un bouton securise de Blizzard qui lance "/targetexact Nom" : c'est TON clic qui
-- cible, ce que Forever autorise. Les boutons securises ne peuvent pas changer pendant un combat :
-- la liste se met a jour des la fin du combat.
do
    local MAX, W, RH = 6, 190, 18
    local ICON = {
        fly    = "Interface\\Minimap\\Tracking\\FlightMaster",
        giver  = "Interface\\GossipFrame\\AvailableQuestIcon",
        turnin = "Interface\\GossipFrame\\ActiveQuestIcon",
        mob    = "Interface\\CURSOR\\Attack",
        inn    = "Interface\\Minimap\\Tracking\\Innkeeper",
        buy    = "Interface\\GossipFrame\\VendorGossipIcon",
    }
    local panel, title, rows = nil, nil, {}
    local wanted, shownKey, waiting

    local function Create()
        if panel then return end
        panel = CreateFrame("Frame", "WarpathTargets", UIParent)
        panel:SetSize(W, 16 + RH)
        panel:SetFrameStrata("MEDIUM")
        panel:SetClampedToScreen(true)
        local p = DB.tgtPos
        if p then panel:SetScale(p[4] or 1); panel:SetPoint(p[1], UIParent, p[1], p[2], p[3]) else panel:SetPoint("CENTER", UIParent, "CENTER", -300, -120) end
        -- clic droit : la recoller sous la fenetre du guide
        panel:SetScript("OnMouseUp", function(_, btn) if btn == "RightButton" then ns.Targets.Reset() end end)
        local bg = Tex(panel, COL.bg, 0.85, "BACKGROUND"); bg:SetAllPoints()
        local top = Tex(panel, COL.line); top:SetHeight(1); top:SetPoint("TOPLEFT"); top:SetPoint("TOPRIGHT")
        local bot = Tex(panel, COL.line); bot:SetHeight(1); bot:SetPoint("BOTTOMLEFT"); bot:SetPoint("BOTTOMRIGHT")
        title = FS(panel, 9, COL.gold, FONT, "LEFT"); title:SetPoint("TOPLEFT", 6, -3)
        panel:EnableMouse(true); panel:SetMovable(true); panel:RegisterForDrag("LeftButton")
        panel:SetScript("OnDragStart", function(self) if not DB.locked and not (InCombatLockdown and InCombatLockdown()) then self:StartMoving() end end)
        panel:SetScript("OnDragStop", function(self)
            self:StopMovingOrSizing()
            local point, _, _, x, y = self:GetPoint(1)
            DB.tgtPos = { point, math.floor(x + 0.5), math.floor(y + 0.5), self:GetScale() }
        end)
        for i = 1, MAX do
            local b = CreateFrame("Button", "WarpathTarget" .. i, panel, "SecureActionButtonTemplate")
            b:SetSize(W - 8, RH)
            b:SetPoint("TOPLEFT", 4, -14 - (i - 1) * RH)
            b:RegisterForClicks("AnyUp", "AnyDown")
            b:SetAttribute("type", "macro")
            local hl = Tex(b, COL.accent, 0.12, "HIGHLIGHT"); hl:SetAllPoints()
            -- icone du jeu (reconnue au premier coup d'oeil) dans un cadre au style de l'addon
            b.box = CreateFrame("Frame", nil, b); b.box:SetSize(16, 16); b.box:SetPoint("LEFT", 1, 0)
            local boxBg = Tex(b.box, COL.faint, 0.55, "BACKGROUND"); boxBg:SetAllPoints()
            b.edge = {}
            for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
                local e = Tex(b.box, COL.line)
                if side == "TOP" or side == "BOTTOM" then e:SetHeight(1); e:SetPoint(side .. "LEFT"); e:SetPoint(side .. "RIGHT")
                else e:SetWidth(1); e:SetPoint("TOP" .. side); e:SetPoint("BOTTOM" .. side) end
                b.edge[#b.edge + 1] = e
            end
            b.icon = b.box:CreateTexture(nil, "ARTWORK"); b.icon:SetSize(12, 12); b.icon:SetPoint("CENTER")
            b.fs = FS(b, 11, COL.white, FONT, "LEFT"); b.fs:SetPoint("LEFT", b.box, "RIGHT", 6, 0); b.fs:SetPoint("RIGHT", -2, 0)
            if i > 1 then local sep = Tex(b, COL.faint, 0.8); sep:SetHeight(1); sep:SetPoint("TOPLEFT", 20, 0); sep:SetPoint("TOPRIGHT", 0, 0) end
            if b.fs.SetWordWrap then b.fs:SetWordWrap(false) end
            b:SetScript("OnEnter", function(self)
                Tip():SetOwner(self, "ANCHOR_RIGHT")
                Tip():AddLine(self.name or "")
                Tip():AddLine(T("tgtClick"), 0.8, 0.73, 0.56, true)
                if not DB.tgtPos then Tip():AddLine(T("tgtDock"), 0.55, 0.5, 0.4, true) end
                Tip():Show()
            end)
            b:SetScript("OnLeave", function() Tip():Hide() end)
            b:Hide()
            rows[i] = b
        end
        panel:Hide()
    end

    -- liste des PNJ de l'etape (sans rien toucher a l'ecran)
    local function Build(s)
        local L, seen = {}, {}
        local names = ns.NpcNames or {}
        local function add(id, kind)
            if id and not seen[id] and names[id] and #L < MAX then
                seen[id] = true; L[#L + 1] = { id = id, name = names[id], kind = kind }
            end
        end
        if currentAdvice and currentAdvice.kind == "bind" then add(currentAdvice.npc, "inn") end
        if currentAdvice and currentAdvice.kind == "buy" then add(currentAdvice.npc, "buy") end
        if flightPlan and flightPlan.from and ns.FlightNodeNpc then add(ns.FlightNodeNpc[flightPlan.from.key], "fly") end
        if s then
            for _, qid in ipairs(Ids(s)) do
                local e = EST[qid]
                if e then
                    if s.t == "accept" then for _, g in ipairs(e.g or {}) do add(g, "giver") end
                    elseif s.t == "turnin" then for _, g in ipairs(e.en or {}) do add(g, "turnin") end
                    elseif s.t == "do" then
                        for _, k in ipairs(e.k or {}) do add(k[1], "mob") end
                        for _, d in ipairs(e.d or {}) do for j = 7, #d do add(d[j], "mob") end end
                    end
                end
            end
        end
        return L
    end

    local function Apply()
        if InCombatLockdown and InCombatLockdown() then waiting = true; return end
        waiting = false
        local L = wanted or {}
        local off = DB.targets == false or #L == 0 or DB.shown == false
        local key = off and "off" or ""
        if not off then for _, t in ipairs(L) do key = key .. t.id .. "," end end
        if key == shownKey then return end
        shownKey = key
        if off then if panel then panel:Hide() end; return end
        Create()
        title:SetText(Caps(T("tgtTitle")))
        for i, b in ipairs(rows) do
            local t = L[i]
            if t then
                b.name = t.name
                b:SetAttribute("macrotext", "/targetexact " .. t.name)
                b.icon:SetTexture(ICON[t.kind])
                local KC = { giver = COL.accent, turnin = COL.green, mob = COL.red, fly = COL.gold, inn = COL.soft, buy = COL.gold }
                local c = KC[t.kind] or COL.line
                for _, e in ipairs(b.edge) do e:SetColorTexture(c[1], c[2], c[3], 1) end
                b.fs:SetText(t.name)
                b:Show()
            else
                b:SetAttribute("macrotext", nil); b:Hide()
            end
        end
        panel:SetHeight(16 + #L * RH)
        panel:Show()
        lastDock = nil; Dock()
    end

    -- Par defaut, collee sous la fenetre du guide. Pas d'ancrage direct (un bouton securise ancre a la
    -- fenetre bloquerait ses changements de taille en combat) : on recopie sa position hors combat.
    local lastDock
    local function Dock()
        if not panel or DB.tgtPos or (InCombatLockdown and InCombatLockdown()) then return end
        local f = _G.WarpathFrame
        if not (f and f:IsShown() and f:GetLeft()) then return end
        local sc, l, b, w = f:GetScale(), f:GetLeft(), f:GetBottom(), f:GetWidth()
        local key = sc .. ":" .. math.floor(l) .. ":" .. math.floor(b) .. ":" .. math.floor(w)
        if key == lastDock then return end
        lastDock = key
        panel:SetScale(sc)
        panel:ClearAllPoints()
        panel:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", l, b - 2)
        panel:SetWidth(w)
        for _, r in ipairs(rows) do r:SetWidth(w - 8) end
    end
    local dockTick = CreateFrame("Frame")
    local dacc = 0
    dockTick:SetScript("OnUpdate", function(_, el)
        dacc = dacc + el
        if dacc < 0.25 then return end
        dacc = 0
        if panel and panel:IsShown() then pcall(Dock) end
    end)

    local ev = CreateFrame("Frame")
    ev:RegisterEvent("PLAYER_REGEN_ENABLED")
    ev:SetScript("OnEvent", function() if waiting then pcall(Apply) end end)

    ns.Targets = {
        Update = function(s) wanted = Build(s); local ok = pcall(Apply); if not ok then shownKey = nil end end,
        Refresh = function() shownKey = nil; pcall(Apply) end,
        Reset = function()
            DB.tgtPos = nil
            lastDock = nil
            pcall(Dock)
        end,
    }
end
