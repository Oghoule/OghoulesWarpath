-- Oghoule's Warpath : moteur (Comfort.lua) - voir Core.lua
local ADDON, ns = ...
local _ENV = ns.CoreEnv
if setfenv then setfenv(1, _ENV) end

------------------------------------------------------------------
-- Confort : quetes automatiques, duree des vols, suivi du leveling, rappel d'entraineur,
-- bouton d'objet de quete, compte a rebours de vol.  (Maj enfoncee = rien d'automatique)
------------------------------------------------------------------
do
local function AutoOK(key) return DB and DB[key] ~= false and not (IsShiftKeyDown and IsShiftKeyDown()) end

-- quetes que le guide veut prendre bientot / rendre
local function GuideQuests()
    local acc, turn = {}, {}
    if not steps then return acc, turn end
    local from = current or 1
    for i = 1, #steps do
        local s = steps[i]
        local ids = type(s.id) == "table" and s.id or { s.id }
        if s.t == "accept" and i >= from and i <= from + 12 and doneCache[i] ~= "done" and doneCache[i] ~= "skip" then
            for _, id in ipairs(ids) do if id then acc[id] = true end end
        elseif s.t == "turnin" then
            for _, id in ipairs(ids) do if id and logById[id] == true then turn[id] = true end end
        end
    end
    return acc, turn
end
local function TitleMatch(title, set)
    for id in pairs(set) do
        local e = EST[id]
        if title and ((e and e.n == title) or QuestTitle(id) == title) then return id end
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
    return T("infoLevel", FormatNum(rate), FmtTime(left / rate * 3600))
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
    if known then return T("infoFlight", flight.to or "?", FmtTime(known - el)) end
    return T("infoFlightUnk", flight.to or "?", FmtTime(el))
end

-- bouton de l'objet a utiliser pour l'etape (seulement les objets avec un effet "Utiliser")
local itemBtn, itemWanted
local function StepItem()
    if not steps or not current or not steps[current] then return nil end
    local s = steps[current]
    for _, id in ipairs(Ids(s)) do
        local e = EST[id]
        for _, it in ipairs(e and e.u or {}) do
            local cnt = (C_Item and C_Item.GetItemCount and C_Item.GetItemCount(it)) or (GetItemCount and GetItemCount(it)) or 0
            -- (Forever ne renvoie pas toujours le sort de l'objet : l'objet a utiliser de la quete suffit)
            if cnt > 0 then return it end
        end
    end
end
local function UpdateItemButton()
    if not f or (InCombatLockdown and InCombatLockdown()) then return end
    local it = DB.itemBtn ~= false and StepItem() or nil
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
        itemBtn:SetScript("OnDragStart", function(self)
            if IsShiftKeyDown() and not DB.locked and not (InCombatLockdown and InCombatLockdown()) then self:StartMoving() end
        end)
        itemBtn:SetScript("OnDragStop", function(self)
            self:StopMovingOrSizing()
            local point, _, rel, x, y = self:GetPoint(1)
            if point then DB.itemPos = { point, rel or point, math.floor(x + 0.5), math.floor(y + 0.5) } end
        end)
        itemBtn:HookScript("OnMouseUp", function(_, btn)
            if btn == "RightButton" and IsShiftKeyDown() and DB.itemPos and not (InCombatLockdown and InCombatLockdown()) then
                DB.itemPos = nil; itemWanted = nil; UpdateItemButton()
            end
        end)
        itemBtn:SetScript("OnEnter", function(self)
            if itemWanted then
                Tip():SetOwner(self, "ANCHOR_LEFT"); Tip():SetItemByID(itemWanted)
                Tip():AddLine(T(DB.itemPos and "itemMoved" or "itemMove"), 0.55, 0.5, 0.4, true); Tip():Show()
            end
        end)
        itemBtn:SetScript("OnLeave", function() Tip():Hide() end)
    end
    if it == itemWanted and itemBtn:IsShown() == (it ~= nil) then return end
    itemWanted = it
    if it then
        itemBtn:ClearAllPoints()
        local l, t = f:GetLeft(), f:GetTop()
        local sc = (f:GetEffectiveScale() or 1) / (UIParent:GetEffectiveScale() or 1)
        local r = f:GetRight()
        local p = DB.itemPos
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
    if not f then return end
    if not rawget(f, "infoLine") then
        f.infoLine = FS(f, 10, COL.gold, FONT, "LEFT"); f.infoLine:SetWidth(INNER)
    end
    local parts = {}
    local fl = FlightInfo(); if fl then parts[#parts + 1] = fl end
    if DB.trainDue and DB.trainer ~= false then parts[#parts + 1] = T("infoTrain") end
    -- (le rythme et le temps avant le niveau suivant sont maintenant dans le pied de la fenetre)
    local txt = table.concat(parts, "\n")
    local was = f.infoLine:IsShown()
    f.infoLine:SetText(txt); f.infoLine:SetShown(txt ~= "")
    if was ~= (txt ~= "") then Layout() end
    UpdateItemButton()
end
ns.Comfort = { OnQuestFrame = OnQuestFrame, TrackXP = TrackXP, UpdateInfo = UpdateInfo, OnLanded = OnLanded,
    SetTaxiFrom = function(k) taxiFrom = k end, LevelInfo = LevelInfo, UpdateItemButton = UpdateItemButton,
    -- pour /warpath diag : objet de l'etape, nombre en sac, sort, bouton affiche
    ItemDiag = function()
        local s = steps and steps[current]
        local it
        for _, id in ipairs(s and Ids(s) or {}) do local e = EST[id]; if e and e.u then it = e.u[1]; break end end
        if not it then return "-" end
        local cnt = (C_Item and C_Item.GetItemCount and C_Item.GetItemCount(it)) or 0
        local sp = C_Item and C_Item.GetItemSpell and C_Item.GetItemSpell(it)
        return it .. " x" .. tostring(cnt) .. ", sort=" .. tostring(sp) .. ", bouton=" .. tostring(itemBtn and itemBtn:IsShown() or false)
            .. ", option=" .. tostring(DB.itemBtn ~= false)
    end }
end

------------------------------------------------------------------
-- Style de jeu (s'applique a tous les guides 1-60, pas aux donjons ni aux mini-guides de chaine) :
--   elite = "always" | "group" | "never" ; xpMode = "farm" | "dungeon" | "both" ;
--   prio = "balanced" | "xp" | "travel" ; noEscort, prudent = true/false
-- Une quete sautee par le style ne l'est jamais si elle debloque une autre quete du guide.
------------------------------------------------------------------
function StyleGet()
    DB.style = DB.style or {}
    local st = DB.style
    st.elite = st.elite or "always"; st.xpMode = st.xpMode or "farm"; st.prio = st.prio or "balanced"
    return st
end

local PRESETS = {
    solo = { elite = "never", xpMode = "both", prio = "xp", noEscort = true, prudent = false },
    group = { elite = "always", xpMode = "dungeon", prio = "balanced", noEscort = false, prudent = false },
    calm = { elite = "group", xpMode = "farm", prio = "travel", noEscort = false, prudent = false },
    safe = { elite = "never", xpMode = "farm", prio = "balanced", noEscort = true, prudent = true },
}
function ApplyPreset(name)
    local p = PRESETS[name]; if not p then return end
    local st = StyleGet()
    for k, v in pairs(p) do st[k] = v end
    styleCache = nil
    if Advance then Advance() end
end

-- donnees par guide : quetes qui debloquent la suite, detours
styleCache = nil
local function GuideData()
    if styleCache and styleCache.G == G then return styleCache end
    local needed, pos, byQ = {}, {}, {}
    for i, s in ipairs(steps or {}) do
        local ids = Ids(s)
        for _, id in ipairs(ids) do
            local e = EST[id]
            if e then
                for _, p in ipairs(e.p or {}) do needed[p] = true end
                for _, p in ipairs(e.p1 or {}) do needed[p] = true end
            end
        end
        if s.m and s.x and s.y then
            pos[#pos + 1] = { m = s.m, x = s.x, y = s.y, ids = ids }
            for _, id in ipairs(ids) do byQ[id] = byQ[id] or {}; table.insert(byQ[id], pos[#pos]) end
        end
    end
    -- une quete qui debloque une quete d'un AUTRE guide (ex. Barrens -> Stonetalon) est aussi protegee
    if not ALL_NEEDED then
        ALL_NEEDED = {}
        for _, g in pairs(Guides or {}) do
            for _, st in ipairs(g.steps or {}) do
                for _, id in ipairs(Ids(st)) do
                    local e = EST[id]
                    if e then
                        for _, p in ipairs(e.p or {}) do ALL_NEEDED[p] = true end
                        for _, p in ipairs(e.p1 or {}) do ALL_NEEDED[p] = true end
                    end
                end
            end
        end
    end
    for p in pairs(ALL_NEEDED) do needed[p] = true end
    styleCache = { G = G, needed = needed, pos = pos, byQ = byQ, detour = {}, rate = {} }
    return styleCache
end

local function Has(list, id) for _, v in ipairs(list) do if v == id then return true end end end

-- grand detour : un des lieux de la quete est loin de tous les lieux des autres quetes du guide
local function Detour(gd, id)
    if gd.detour[id] ~= nil then return gd.detour[id] end
    local worst = 0
    for _, p in ipairs(gd.byQ[id] or {}) do
        local best = math.huge
        for _, o in ipairs(gd.pos) do
            if o.m == p.m and not Has(o.ids, id) then
                local d = math.sqrt((o.x - p.x) ^ 2 + (o.y - p.y) ^ 2)
                if d < best then best = d end
            end
        end
        if best > worst then worst = best end
    end
    gd.detour[id] = worst > 22
    return gd.detour[id]
end

-- peu rentable : moins de 60 % de l'XP/h du simple farm de monstres de ton niveau
local function LowRate(gd, id)
    local p = UnitLevel("player") or 1
    local key = id .. ":" .. p
    if gd.rate[key] ~= nil then return gd.rate[key] end
    local ok, e = pcall(Estimate, { id }, false)
    local res = false
    if ok and e and e.perHour and e.perHour > 0 then
        local grind = MobXP(p, p, 0) * 3600 / KillTime()
        res = e.perHour < grind * 0.6
    end
    gd.rate[key] = res
    return res
end

local function InGroup() return (IsInGroup and IsInGroup()) or ((GetNumGroupMembers and GetNumGroupMembers() or 0) > 0) end

function StyleSkip(i, s)
    if not DB or not steps or IS_DUNGEON[DB.guide] or DB.guide == "chain" or s.t ~= "accept" then return false end
    local st = StyleGet()
    local gd = GuideData()
    local ids = Ids(s)
    if #ids == 0 then return false end
    for _, id in ipairs(ids) do
        local e = EST[id]
        if not e or gd.needed[id] then return false end
        local drop = (e.el and (st.elite == "never" or (st.elite == "group" and not InGroup())))
            or (e.es and st.noEscort)
            or (st.prudent and (e.l or 0) > (UnitLevel("player") or 1) + 2)
            or (st.prio == "xp" and LowRate(gd, id))
            or (st.prio == "travel" and Detour(gd, id))
        if not drop then return false end
    end
    return true
end

-- Etape "Monte au niveau X" : proposer le donjon de ton niveau (une fois par etape)
function SuggestDungeonForLevel()
    if not DB or not steps or IS_DUNGEON[DB.guide] or DB.guide == "chain" or asking or not StaticPopup_Show then return end
    local st = StyleGet()
    if st.xpMode ~= "dungeon" and st.xpMode ~= "both" then return end
    local s = steps[current]
    if not s or s.t ~= "level" or (UnitLevel("player") or 0) >= (s.level or 0) then return end
    DB.lvlAsked = DB.lvlAsked or {}
    local key = SeenKey(current)
    if DB.lvlAsked[key] then return end
    local lvl = UnitLevel("player") or 1
    local best
    for _, d in ipairs(DUNGEONS) do
        if Guides[d.key] and lvl >= d.min and lvl <= d.max and DB.dAnswer[d.key] ~= "no" and not DungeonDone(d.key) and DungeonOpen(d.key) then
            if not best or d.min > best.min then best = d end
        end
    end
    if not best then return end
    DB.lvlAsked[key] = true
    asking = best
    ns.Trace("popup WARPATH_DUNGEON"); Popup("WARPATH_DUNGEON", T("dAskXP", s.level, DungeonName(best), best.min, best.max) .. ((DungeonAskLine and DungeonAskLine(best.key)) or DungeonReqText(best.key)))
end
