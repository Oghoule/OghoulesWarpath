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
local itemBtn, itemWanted, itemDockKey
-- v1.52 (demande de l'auteur) : meme regle que « Cibles de l'objectif » (UI/Targets.lua) : colle a droite de ce
-- panneau, en haut, et le suit ; sans panneau, sous la fenetre du guide (ou la petite fenetre), la ou il serait.
-- Bouton securise : pas d'ancrage direct, on recopie la position hors combat (toutes les 0,25 s, si elle a change).
-- Deplace a la main (Maj + glisser) : il reste ou tu l'as mis ; Maj + clic droit le recolle.
local function DockItem()
    if not itemBtn or State.DB.itemPos or (InCombatLockdown and InCombatLockdown()) then return end
    local tp = _G.WarpathTargets
    local ref, side = nil, nil
    if tp and tp.IsShown and tp:IsShown() and tp:GetRight() then ref, side = tp, "right"
    else
        local f = _G.WarpathFrame
        local mini = _G.WarpathMini
        if mini and mini.IsShown and mini:IsShown() then f = mini end
        if f and f.IsShown and f:IsShown() and f:GetLeft() then ref, side = f, "below" end
    end
    if not ref then return end
    local sc = ref:GetScale() or 1
    local x, y = (side == "right") and (ref:GetRight() + 4) or ref:GetLeft(), (side == "right") and ref:GetTop() or (ref:GetBottom() - 2)
    local key = side .. sc .. ":" .. math.floor(x) .. ":" .. math.floor(y)
    if key == itemDockKey then return end
    itemDockKey = key
    itemBtn:SetScale(sc)
    itemBtn:ClearAllPoints()
    itemBtn:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, y)
end
do
    local tick, acc = CreateFrame("Frame"), 0
    tick:SetScript("OnUpdate", function(_, el)
        acc = acc + (el or 0)
        if acc < 0.25 then return end
        acc = 0
        if itemBtn and itemBtn:IsShown() then pcall(DockItem) end
    end)
end
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
    -- v1.52 (bug vu par l'auteur) : pas de bouton d'objet pendant l'Intendance (tournee ou ecran de choix) ni quand
    -- le guide est cache : l'objet est celui de l'etape du guide, pas celui de la tournee
    local QM = ns.Mod.Quartermaster
    local qmOn = State.DB.qm or (QM and QM.QMPanelState and QM.QMPanelState())
    local it = (State.DB.itemBtn ~= false and State.DB.shown ~= false and not qmOn) and StepItem() or nil
    if not itemBtn then
        if not it then return end
        ns.Trace("bouton d'objet (creation)")
        itemBtn = CreateFrame("Button", "WarpathItemButton", UIParent, "SecureActionButtonTemplate")
        -- v1.52 (demande de l'auteur) : meme hauteur que « Cibles de l'objectif » avec une cible (26 + 6 + 18 px)
        itemBtn:SetSize(50, 50)
        itemBtn:SetAttribute("type", "item")
        -- v1.52 (demande de l'auteur) : habille comme l'addon : fond sombre, filet dore
        local bg = Skin.Tex(itemBtn, Skin.COL.bg, 0.92, "BACKGROUND"); bg:SetAllPoints()
        Skin.Border(itemBtn, Skin.COL.accent, 0.8)
        itemBtn.icon = itemBtn:CreateTexture(nil, "ARTWORK"); itemBtn.icon:SetPoint("TOPLEFT", 3, -3); itemBtn.icon:SetPoint("BOTTOMRIGHT", -3, 3)
        itemBtn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)   -- sans le bord gris des icones du jeu
        local hl = itemBtn:CreateTexture(nil, "HIGHLIGHT"); hl:SetPoint("TOPLEFT", 3, -3); hl:SetPoint("BOTTOMRIGHT", -3, 3); hl:SetColorTexture(1, 1, 1, 0.15)
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
            if point then State.DB.itemPos = { point, rel or point, math.floor(x + 0.5), math.floor(y + 0.5), itemBtn:GetScale() } end
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
        local p = State.DB.itemPos
        itemDockKey = nil
        if p then itemBtn:SetScale(p[5] or 1); itemBtn:ClearAllPoints(); itemBtn:SetPoint(p[1], UIParent, p[2], p[3], p[4])
        else DockItem() end
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
-- v1.52 (Eclaireur) : aussi A L'AVANCE : si les quetes qui restent avant la prochaine etape « Monte au niveau » ne
-- suffiront pas (il manquera au moins AHEAD_MIN d'un niveau), le donjon est propose tout de suite, pendant qu'on est
-- dans la zone, au lieu de farmer a la fin. Une seule question par etape « Monte au niveau » (meme cle DB.lvlAsked).
local AHEAD_MIN = 0.25
Comfort.aheadFor = nil   -- etape courante deja examinee (le calcul n'est refait que si elle change ; les tests la remettent a nil)
local function bestDungeon(lvl)
    local best
    for _, d in ipairs(Core.DUNGEONS) do
        if Core.Guides[d.key] and lvl >= d.min and lvl <= d.max and State.DB.dAnswer[d.key] ~= "no" and not Flow.DungeonDone(d.key) and Flow.DungeonOpen(d.key) then
            if not best or d.min > best.min then best = d end
        end
    end
    return best
end
-- XP qu'il faut encore pour atteindre le niveau « target »
local function xpTo(target)
    local lvl = UnitLevel("player") or 1
    if lvl >= target then return 0 end
    local XPL = DungeonSheet.XPL or {}
    local need = ((UnitXPMax and UnitXPMax("player")) or XPL[lvl] or 0) - ((UnitXP and UnitXP("player")) or 0)
    for l = lvl + 1, target - 1 do need = need + (XPL[l] or 0) end
    return math.max(0, need)
end
-- Prochaine etape « Monte au niveau » pas encore faite, et XP qui manquera en y arrivant
function Comfort.LevelShortfall()
    local ids, seen, j = {}, {}, nil
    local dc = State.doneCache or {}   -- etat de chaque etape au dernier recalcul (done / skip / false)
    for i = State.current, #State.steps do
        local t = State.steps[i]
        if t.t == "level" and t.level and not dc[i] then j = i; break end
        if t.id and (t.t == "accept" or t.t == "do" or t.t == "turnin") and not dc[i] then
            for _, q in ipairs(Core.Ids(t)) do if not seen[q] and not Core.Rendue(q) then seen[q] = true; ids[#ids + 1] = q end end
        end
    end
    if not j then return nil end
    local gain = (#ids > 0 and Est.Estimate(ids, false).xp) or 0
    return j, xpTo(State.steps[j].level) - gain
end
function Comfort.SuggestDungeonForLevel()
    if not State.DB or not State.steps or Core.IS_DUNGEON[State.DB.guide] or State.DB.guide == "chain" or State.asking or not StaticPopup_Show then return end
    local st = Style.StyleGet()
    if st.xpMode ~= "dungeon" and st.xpMode ~= "both" then return end
    if Core.Parcours() == "warband" then return end   -- v1.52 : la Bande de guerre a deja ses donjons dans le parcours
    if IsInInstance and IsInInstance() then return end
    if InCombatLockdown and InCombatLockdown() then return end
    local s = State.steps[State.current]
    if not s then return end
    State.DB.lvlAsked = State.DB.lvlAsked or {}
    local lvl = UnitLevel("player") or 1
    local j, short = State.current, nil
    if s.t == "level" then
        if lvl >= (s.level or 0) then return end
        if State.DB.lvlAsked[Core.SeenKey(j)] then return end
    else
        if Comfort.aheadFor == State.current then return end
        Comfort.aheadFor = State.current
        j, short = Comfort.LevelShortfall()
        if not j or State.DB.lvlAsked[Core.SeenKey(j)] then return end
        local XPL = DungeonSheet.XPL or {}
        if not short or short < AHEAD_MIN * (XPL[lvl] or 1000) then return end
    end
    local best = bestDungeon(lvl)
    if not best then return end
    State.DB.lvlAsked[Core.SeenKey(j)] = true
    State.asking = best
    local text
    if short then
        local n = math.floor(short / 100 + 0.5) * 100
        text = Core.T("dAskAhead", n, State.steps[j].level, Flow.DungeonName(best), best.min, best.max)
    else
        text = Core.T("dAskXP", s.level, Flow.DungeonName(best), best.min, best.max)
    end
    ns.Trace("popup WARPATH_DUNGEON"); Skin.Popup("WARPATH_DUNGEON", text .. ((DungeonSheet.DungeonAskLine and DungeonSheet.DungeonAskLine(best.key)) or Flow.DungeonReqText(best.key)))
end

-- v1.52 : Cozy Sleeping Bag (fin d'une chaine des guides) : +3 % sur toute l'XP pendant 2 h ; on renouvelle le bonus en se
-- couchant 1 min dedans. Rappel toutes les 10 min au plus, hors combat et hors instance, si tu as le sac et que le bonus
-- est absent ou finit dans moins de 10 min. Case « Rappel du sac de couchage » (Comportement), DB.bagRemind.
local BAG_ITEM, BAG_SOON, BAG_EVERY = 211527, 600, 600
local bagLast = -BAG_EVERY
local function BagAura()
    if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return nil end
    -- le nom du bonus n'est pas connu sur Forever : nom du sort de l'objet, nom de l'objet (traduits par le jeu), ou anglais
    local sname = C_Item and C_Item.GetItemSpell and C_Item.GetItemSpell(BAG_ITEM)
    local iname = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(BAG_ITEM)
    for i = 1, 40 do
        local a = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
        if not a then break end
        local n = a.name or ""
        if (sname and n == sname) or (iname and n == iname) or n:find("Cozy", 1, true) or n:find("Sleeping Bag", 1, true) then return a end
    end
end
function Comfort.BagCheck()
    if not State.DB or State.DB.bagRemind == false then return end
    if (UnitLevel and UnitLevel("player") or 60) >= 60 then return end
    if (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player")) then return end
    if IsInInstance and IsInInstance() then return end
    if not (C_Item and C_Item.GetItemCount and (C_Item.GetItemCount(BAG_ITEM) or 0) > 0) then return end
    local now = GetTime and GetTime() or 0
    if now - bagLast < BAG_EVERY then return end
    local ok, a = pcall(BagAura)
    if not ok then return end
    local left = a and a.expirationTime and a.expirationTime > 0 and (a.expirationTime - now) or nil
    if a and (not left or left > BAG_SOON) then return end
    bagLast = now
    local msg = a and Core.T("bagSoon", math.max(1, math.floor(left / 60))) or Core.T("bagMissing")
    if Skin.Toast then Skin.Toast(Core.T("bagHead"), msg) else Core.say(msg) end
end
if not WARPATH_TEST and C_Timer and C_Timer.NewTicker then
    C_Timer.NewTicker(60, function() pcall(Comfort.BagCheck) end)
end

-- v1.50 : ce que ce fichier offre aux autres (ns.Mod.Comfort)
do
    local M = ns.Mod.Comfort
end
