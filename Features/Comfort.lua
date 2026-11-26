-- Oghoule's Warpath : moteur (Comfort.lua) - voir Core.lua
local ADDON, ns = ...
-- v1.50 : etat partage du guide (Core.lua, ns.State)
local State = ns.State
local Comfort = ns.Mod.Comfort -- v1.50 : module
local Core = ns.Mod.Core -- v1.50 : module
local DungeonSheet = ns.Mod.DungeonSheet -- v1.50 : module
-- v1.50 : module ns.Mod.Comfort (publie en fin de fichier pour les autres fichiers)
local Skin = ns.Mod.Skin -- v1.50 : module
local Flow = ns.Mod.Flow -- v1.50 : module
local Est = ns.Mod.Est -- v1.50 : module
local Style = ns.Mod.Style -- v1.50 : module

------------------------------------------------------------------
-- Confort : quetes automatiques, duree des vols, suivi du leveling, rappel d'entraineur,
-- bouton d'objet de quete, compte a rebours de vol.  (Maj enfoncee = rien d'automatique)
------------------------------------------------------------------
do
local function AutoOK(key) return State.DB and State.DB[key] ~= false and not (IsShiftKeyDown and IsShiftKeyDown()) end

-- quetes que le guide veut prendre bientot / rendre
local function GuideQuests()
    local acc, turn = {}, {}
    if not State.steps then return acc, turn end
    local from = State.current or 1
    for i = 1, #State.steps do
        local s = State.steps[i]
        local ids = type(s.id) == "table" and s.id or { s.id }
        if s.t == "accept" and i >= from and i <= from + 12 and State.doneCache[i] ~= "done" and State.doneCache[i] ~= "skip" then
            for _, id in ipairs(ids) do if id then acc[id] = true end end
        elseif s.t == "turnin" then
            for _, id in ipairs(ids) do if id and Core.logById[id] == true then turn[id] = true end end
        end
    end
    return acc, turn
end
local function TitleMatch(title, set)
    for id in pairs(set) do
        local e = Est.EST[id]
        if title and ((e and e.n == title) or Core.QuestTitle(id) == title) then return id end
    end
end
local function OnQuestFrame(event)
    if not AutoOK("autoQuest") then return end
    local acc, turn = GuideQuests()
    if event == "QUEST_DETAIL" then
        local id = GetQuestID and GetQuestID()
        if id and acc[id] and AcceptQuest then ns.Trace("AcceptQuest"); AcceptQuest() end
    elseif event == "QUEST_PROGRESS" then
        local id = GetQuestID and GetQuestID()
        if id and turn[id] and IsQuestCompletable and IsQuestCompletable() and CompleteQuest then ns.Trace("CompleteQuest"); CompleteQuest() end
    elseif event == "QUEST_COMPLETE" then
        local id = GetQuestID and GetQuestID()
        if id and turn[id] and GetQuestReward and (GetNumQuestChoices and GetNumQuestChoices() or 0) <= 1 then ns.Trace("GetQuestReward"); GetQuestReward(1) end
    elseif event == "GOSSIP_SHOW" and C_GossipInfo then
        for _, q in ipairs(C_GossipInfo.GetActiveQuests and C_GossipInfo.GetActiveQuests() or {}) do
            if q.isComplete and turn[q.questID] then ns.Trace("Gossip"); return C_GossipInfo.SelectActiveQuest(q.questID) end
        end
        for _, q in ipairs(C_GossipInfo.GetAvailableQuests and C_GossipInfo.GetAvailableQuests() or {}) do
            if acc[q.questID] then ns.Trace("Gossip"); return C_GossipInfo.SelectAvailableQuest(q.questID) end
        end
    elseif event == "QUEST_GREETING" then
        for k = 1, (GetNumActiveQuests and GetNumActiveQuests() or 0) do
            if TitleMatch(GetActiveTitle(k), turn) then ns.Trace("Gossip"); return SelectActiveQuest(k) end
        end
        for k = 1, (GetNumAvailableQuests and GetNumAvailableQuests() or 0) do
            if TitleMatch(GetAvailableTitle(k), acc) then ns.Trace("Gossip"); return SelectAvailableQuest(k) end
        end
    end
end

-- suivi du leveling (session) : XP gagnee, XP/h, temps jusqu'au prochain niveau
local sess = { t0 = nil, gained = 0, lastXP = nil, lastMax = nil }
local function TrackXP()
    local xp, mx = UnitXP and UnitXP("player") or 0, UnitXPMax and UnitXPMax("player") or 1
    if not sess.t0 then sess.t0 = GetTime and GetTime() or 0 end
    if sess.lastXP then
        if xp >= sess.lastXP then sess.gained = sess.gained + (xp - sess.lastXP)
        else sess.gained = sess.gained + (sess.lastMax - sess.lastXP) + xp end
    end
    sess.lastXP, sess.lastMax = xp, mx
end
local function FmtTime(s)
    s = math.max(0, math.floor(s or 0))
    if s >= 3600 then return string.format("%dh%02d", s / 3600, (s % 3600) / 60) end
    return string.format("%d:%02d", s / 60, s % 60)
end
local function LevelInfo()
    if not sess.t0 or not GetTime then return nil end
    local el = GetTime() - sess.t0
    if el < 300 or sess.gained <= 0 then return nil end
    local rate = sess.gained * 3600 / el
    local left = (UnitXPMax("player") or 0) - (UnitXP("player") or 0)
    return Core.T("infoLevel", Est.FormatNum(rate), FmtTime(left / rate * 3600))
end

-- vols : on apprend la duree de chaque trajet la premiere fois
local flight = nil      -- { from, to, t0 }
local taxiFrom
if hooksecurefunc then
    hooksecurefunc("TakeTaxiNode", function(i)
        local to = TaxiNodeName and TaxiNodeName(i)
        flight = { from = taxiFrom, to = to, t0 = GetTime and GetTime() or 0 }
    end)
end
local function FlightKey() return flight and ((flight.from or "?") .. ">" .. (flight.to or "?")) end
local function OnLanded()
    if flight and GetTime then
        local secs = GetTime() - flight.t0
        if secs > 10 and secs < 1800 then
            WarpathDropDB._fly = WarpathDropDB._fly or {}
            WarpathDropDB._fly[FlightKey()] = math.floor(secs)
        end
    end
    flight = nil
end
local function FlightInfo()
    if not flight or not GetTime then return nil end
    if UnitOnTaxi and not UnitOnTaxi("player") and GetTime() - flight.t0 > 5 then OnLanded(); return nil end
    local known = WarpathDropDB._fly and WarpathDropDB._fly[FlightKey()]
    local el = GetTime() - flight.t0
    if known then return Core.T("infoFlight", flight.to or "?", FmtTime(known - el)) end
    return Core.T("infoFlightUnk", flight.to or "?", FmtTime(el))
end

-- bouton de l'objet a utiliser pour l'etape (seulement les objets avec un effet "Utiliser")
local itemBtn, itemWanted
local function StepItem()
    if not State.steps or not State.current or not State.steps[State.current] then return nil end
    local s = State.steps[State.current]
    for _, id in ipairs(Core.Ids(s)) do
        local e = Est.EST[id]
        for _, it in ipairs(e and e.u or {}) do
            local cnt = (C_Item and C_Item.GetItemCount and C_Item.GetItemCount(it)) or (GetItemCount and GetItemCount(it)) or 0
            -- (Forever ne renvoie pas toujours le sort de l'objet : l'objet a utiliser de la quete suffit)
            if cnt > 0 then return it end
        end
    end
end
local function UpdateItemButton()
    if not Core.f or (InCombatLockdown and InCombatLockdown()) then return end
    local it = State.DB.itemBtn ~= false and StepItem() or nil
    if not itemBtn then
        if not it then return end
        ns.Trace("bouton d'objet (creation)")
        itemBtn = CreateFrame("Button", "WarpathItemButton", UIParent, "SecureActionButtonTemplate")
        itemBtn:SetSize(36, 36)
        itemBtn:SetAttribute("type", "item")
        itemBtn.icon = itemBtn:CreateTexture(nil, "ARTWORK"); itemBtn.icon:SetAllPoints()
        local hl = itemBtn:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.15)
        if itemBtn.RegisterForClicks then itemBtn:RegisterForClicks("AnyUp", "AnyDown") end
        -- Maj + glisser : deplacer le bouton (hors combat, fenetre non verrouillee) ; Maj + clic droit : le recoller
        -- a cote du guide. Maj + clic n'utilise pas l'objet (pour ne pas gaspiller son temps de recharge).
        itemBtn:SetAttribute("shift-type*", "")
        itemBtn:SetMovable(true); itemBtn:SetClampedToScreen(true); itemBtn:RegisterForDrag("LeftButton")
        -- v1.49 : en combat, le jeu bloque StopMovingOrSizing (bouton securise) ; un deplacement en cours est
        -- donc termine juste avant le verrou du combat (PLAYER_REGEN_DISABLED, encore permis a ce moment)
        local moving = false
        local function EndMove()
            if not moving then return end
            moving = false
            itemBtn:StopMovingOrSizing()
            local point, _, rel, x, y = itemBtn:GetPoint(1)
            if point then State.DB.itemPos = { point, rel or point, math.floor(x + 0.5), math.floor(y + 0.5) } end
        end
        itemBtn:SetScript("OnDragStart", function(self)
            if IsShiftKeyDown() and not State.DB.locked and not (InCombatLockdown and InCombatLockdown()) then self:StartMoving(); moving = true end
        end)
        itemBtn:SetScript("OnDragStop", function() if not (InCombatLockdown and InCombatLockdown()) then EndMove() end end)
        local combatEv = CreateFrame("Frame")
        combatEv:RegisterEvent("PLAYER_REGEN_DISABLED")
        combatEv:SetScript("OnEvent", function() pcall(EndMove) end)
        itemBtn:HookScript("OnMouseUp", function(_, btn)
            if btn == "RightButton" and IsShiftKeyDown() and State.DB.itemPos and not (InCombatLockdown and InCombatLockdown()) then
                State.DB.itemPos = nil; itemWanted = nil; UpdateItemButton()
            end
        end)
        itemBtn:SetScript("OnEnter", function(self)
            if itemWanted then
                Skin.Tip():SetOwner(self, "ANCHOR_LEFT"); Skin.Tip():SetItemByID(itemWanted)
                Skin.Tip():AddLine(Core.T(State.DB.itemPos and "itemMoved" or "itemMove"), 0.55, 0.5, 0.4, true); Skin.Tip():Show()
            end
        end)
        itemBtn:SetScript("OnLeave", function() Skin.Tip():Hide() end)
    end
    if it == itemWanted and itemBtn:IsShown() == (it ~= nil) then return end
    itemWanted = it
    if it then
        itemBtn:ClearAllPoints()
        local l, t = Core.f:GetLeft(), Core.f:GetTop()
        local sc = (Core.f:GetEffectiveScale() or 1) / (UIParent:GetEffectiveScale() or 1)
        local r = Core.f:GetRight()
        local p = State.DB.itemPos
        if p then itemBtn:SetPoint(p[1], UIParent, p[2], p[3], p[4])
        elseif l and t and l * sc >= 50 then itemBtn:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", l * sc - 6, t * sc - 16)
        elseif r and t then itemBtn:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", r * sc + 6, t * sc - 16)   -- fenetre collee a gauche : a droite
        else itemBtn:SetPoint("CENTER", UIParent, "CENTER", -300, 0) end
        ns.Trace("bouton d'objet (objet)"); itemBtn:SetAttribute("item", "item:" .. it)
        local icon = (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(it)) or (GetItemIcon and GetItemIcon(it))
        itemBtn.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
        itemBtn:Show()
    else
        itemBtn:Hide()
    end
end

-- ligne d'infos sous le titre : vol en cours, entraineur, rythme de leveling
local function UpdateInfo()
    if not Core.f then return end
    if not rawget(Core.f, "infoLine") then
        Core.f.infoLine = Skin.FS(Core.f, 10, Skin.COL.gold, Skin.FONT, "LEFT"); Core.f.infoLine:SetWidth(Skin.INNER)
    end
    local parts = {}
    local fl = FlightInfo(); if fl then parts[#parts + 1] = fl end
    if State.DB.trainDue and State.DB.trainer ~= false then parts[#parts + 1] = Core.T("infoTrain") end
    -- (le rythme et le temps avant le niveau suivant sont maintenant dans le pied de la fenetre)
    local txt = table.concat(parts, "\n")
    local was = Core.f.infoLine:IsShown()
    Core.f.infoLine:SetText(txt); Core.f.infoLine:SetShown(txt ~= "")
    if was ~= (txt ~= "") then Skin.Layout() end
    UpdateItemButton()
end
ns.Comfort = { OnQuestFrame = OnQuestFrame, TrackXP = TrackXP, UpdateInfo = UpdateInfo, OnLanded = OnLanded,
    SetTaxiFrom = function(k) taxiFrom = k end, LevelInfo = LevelInfo, UpdateItemButton = UpdateItemButton,
    -- pour /warpath diag : objet de l'etape, nombre en sac, sort, bouton affiche
    ItemDiag = function()
        local s = State.steps and State.steps[State.current]
        local it
        for _, id in ipairs(s and Core.Ids(s) or {}) do local e = Est.EST[id]; if e and e.u then it = e.u[1]; break end end
        if not it then return "-" end
        local cnt = (C_Item and C_Item.GetItemCount and C_Item.GetItemCount(it)) or 0
        local sp = C_Item and C_Item.GetItemSpell and C_Item.GetItemSpell(it)
        return it .. " x" .. tostring(cnt) .. ", sort=" .. tostring(sp) .. ", bouton=" .. tostring(itemBtn and itemBtn:IsShown() or false)
            .. ", option=" .. tostring(State.DB.itemBtn ~= false)
    end }
end


-- Etape "Monte au niveau X" : proposer le donjon de ton niveau (une fois par etape)
function Comfort.SuggestDungeonForLevel()
    if not State.DB or not State.steps or Core.IS_DUNGEON[State.DB.guide] or State.DB.guide == "chain" or State.asking or not StaticPopup_Show then return end
    local st = Style.StyleGet()
    if st.xpMode ~= "dungeon" and st.xpMode ~= "both" then return end
    local s = State.steps[State.current]
    if not s or s.t ~= "level" or (UnitLevel("player") or 0) >= (s.level or 0) then return end
    State.DB.lvlAsked = State.DB.lvlAsked or {}
    local key = Core.SeenKey(State.current)
    if State.DB.lvlAsked[key] then return end
    local lvl = UnitLevel("player") or 1
    local best
    for _, d in ipairs(Core.DUNGEONS) do
        if Core.Guides[d.key] and lvl >= d.min and lvl <= d.max and State.DB.dAnswer[d.key] ~= "no" and not Flow.DungeonDone(d.key) and Flow.DungeonOpen(d.key) then
            if not best or d.min > best.min then best = d end
        end
    end
    if not best then return end
    State.DB.lvlAsked[key] = true
    State.asking = best
    ns.Trace("popup WARPATH_DUNGEON"); Skin.Popup("WARPATH_DUNGEON", Core.T("dAskXP", s.level, Flow.DungeonName(best), best.min, best.max) .. ((DungeonSheet.DungeonAskLine and DungeonSheet.DungeonAskLine(best.key)) or Flow.DungeonReqText(best.key)))
end

-- v1.50 : ce que ce fichier offre aux autres (ns.Mod.Comfort)
do
    local M = ns.Mod.Comfort
end
