-- Oghoule's Warpath : fiche de donjon (DungeonSheet.lua, v1.46)
-- Quetes d'un donjon pour TON perso : a prendre, en cours, plus tard (niveau trop bas), faites ; XP totale et
-- niveau atteint ; une fleche par PNJ ; « Prendre les quetes » lance le guide du donjon. Compteurs « ! N » / « +N »
-- pour la question « Faire le donjon ? » et la liste des donjons (Options). Tout est calcule depuis les guides.
-- Aucun bouton securise ici (fenetre libre, parent UIParent).
local ADDON, ns = ...
-- v1.50 : etat partage du guide (Core.lua, ns.State)
local State = ns.State
local DungeonSheet = ns.Mod.DungeonSheet -- v1.50 : module
local Core = ns.Mod.Core -- v1.50 : module
-- v1.50 : module ns.Mod.DungeonSheet (publie en fin de fichier pour les autres fichiers)
local DungeonAskLine, DungeonBadge, DungeonSheetDefault, DungeonSheetHide, DungeonSheetOpen
local Skin = ns.Mod.Skin -- v1.50 : module
local Flow = ns.Mod.Flow -- v1.50 : module
local Near = ns.Mod.Near -- v1.50 : module
local Est = ns.Mod.Est -- v1.50 : module

-- XP pour passer au niveau suivant (1 a 59), comme le jeu classique
local XPL = { 400, 900, 1400, 2100, 2800, 3600, 4500, 5400, 6500, 7600, 8800, 10100, 11400, 12900, 14400, 16000,
    17700, 19400, 21300, 23200, 25200, 27300, 29400, 31700, 34000, 36400, 38900, 41400, 44300, 47400, 50800, 54500,
    58600, 62800, 67100, 71600, 76100, 80800, 85700, 90700, 95800, 101000, 106300, 111800, 117500, 123200, 129100,
    135100, 141200, 147500, 153900, 160400, 167100, 173900, 180800, 187900, 195000, 202300, 209800 }

local function dungeonOf(key) for _, d in ipairs(Core.DUNGEONS) do if d.key == key then return d end end end

-- Toutes les quetes du donjon pour toi, avec leur statut :
-- take (a prendre), pre (pre-quete manquante), inside (dans le donjon), ready (prete a rendre), log (en cours),
-- later (niveau trop bas), done (rendue), skip (ignoree).
function DungeonSheet.DungeonQuests(key)
    local g = Core.Guides[key]; if not (g and State.DB) then return nil end
    local me = UnitLevel and UnitLevel("player") or 1
    local en = Core.Lang and Core.Lang() == "en"
    local rows, seen = {}, {}
    local n = { take = 0, pre = 0, inside = 0, ready = 0, log = 0, later = 0, done = 0, skip = 0 }
    local laterLvl, xp, nxp, zone
    for _, s in ipairs(g.steps or {}) do
        if s.t == "go" and not zone then zone = s.zone end
        if s.t == "accept" and Core.Applies(s) then
            for _, id in ipairs(Core.Ids(s)) do
                if id and not seen[id] and Est.QAvailable(id) then
                    seen[id] = true
                    local e = Est.EST[id] or {}
                    local r = { id = id, name = Core.QuestTitle(id) or e.n or s.quest or ("#" .. id), req = s.req or e.r or 1,
                                m = s.m, x = s.x, y = s.y, zone = s.zone, xp = Est.QuestXP(e, me) }
                    local txt = (en and s.en or s.text) or ""
                    local npc = txt:match("^(.-)%s?: ")
                    if npc and #npc <= 40 and npc ~= r.name then r.npc = npc end
                    local miss
                    for _, p in ipairs(s.preg or {}) do if not Core.Rendue(p) and not miss then miss = p end end
                    if s.pre and not miss then
                        local ok = false
                        for _, p in ipairs(s.pre) do if Core.Rendue(p) then ok = true end end
                        if not ok then miss = s.pre[1] end
                    end
                    local st
                    if Core.Rendue(id) then st = "done"
                    elseif State.DB.ignored[id] then st = "skip"
                    elseif Core.logById[id] == true then st = "ready"
                    elseif Core.logById[id] == false then st = "log"
                    elseif miss then st = "pre"; r.miss = Core.QuestTitle(miss) or (Est.EST[miss] and Est.EST[miss].n) or ("#" .. miss)
                    elseif r.req > me then st = "later"
                    elseif not s.m then st = "inside"
                    else st = "take" end
                    r.st = st
                    n[st] = n[st] + 1
                    if st == "later" and (not laterLvl or r.req < laterLvl) then laterLvl = r.req end
                    if st ~= "done" and st ~= "skip" and st ~= "later" then xp = (xp or 0) + r.xp; nxp = (nxp or 0) + 1 end
                    rows[#rows + 1] = r
                end
            end
        end
    end
    return { rows = rows, n = n, laterLvl = laterLvl, xp = xp or 0, nxp = nxp or 0, zone = zone }
end

-- compteurs : a prendre maintenant, bloquees par le niveau (et le 1er niveau qui en debloque une)
function DungeonBadge(key)
    local ok, q = pcall(DungeonSheet.DungeonQuests, key)
    if not (ok and q) then return 0, 0, nil end
    return q.n.take, q.n.later, q.laterLvl, q
end

-- texte pour la question « Faire le donjon ? »
function DungeonAskLine(key)
    local take, later, lvl, q = DungeonBadge(key)
    if not q or #q.rows == 0 then return "" end
    local G, R, S = "|cff" .. Skin.HEX.accent, "|cff" .. Skin.HEX.red, "|cff" .. Skin.HEX.soft
    local out = "\n\n" .. (take > 0 and (G .. "! " .. take .. "|r  " .. Core.T(take == 1 and "dsAskLine1" or "dsAskLine", Est.FormatNum(q.xp)))
        or (S .. Core.T("dsAskNone", Est.FormatNum(q.xp)) .. "|r"))
    local extra = {}
    if later > 0 then extra[#extra + 1] = R .. "+" .. later .. "|r " .. Core.T("dsAskLater", lvl) end
    if q.n.inside > 0 then extra[#extra + 1] = Core.T("dsAskInside", q.n.inside) end
    if q.n.pre > 0 then extra[#extra + 1] = Core.T("dsAskPre", q.n.pre) end
    if #extra > 0 then out = out .. "\n" .. S .. table.concat(extra, " · ") .. "|r" end
    return out
end

-- niveau et pourcentage apres avoir gagne « gain » XP
local function project(gain)
    local lvl = UnitLevel and UnitLevel("player") or 1
    local cur = (UnitXP and UnitXP("player") or 0) + gain
    local need = (UnitXPMax and UnitXPMax("player")) or XPL[lvl] or 1
    while lvl < 60 and cur >= need do
        cur = cur - need; lvl = lvl + 1; need = XPL[lvl] or need
    end
    return lvl, math.floor(cur / math.max(1, need) * 100)
end

------------------------------------------------------------------
-- La fenetre
------------------------------------------------------------------
local SW, SP, ROW = 330, 14, 34
local sheet, curKey
local pool, rules = {}, {}
local ORDER = { take = 1, pre = 2, inside = 3, ready = 1, log = 2, later = 1, done = 1, skip = 2 }
local SECTIONS = {
    { key = "dsTake", sts = { take = true, pre = true, inside = true } },
    { key = "dsLog", sts = { ready = true, log = true } },
    { key = "dsLater", sts = { later = true }, red = true },
    { key = "dsDone", sts = { done = true, skip = true }, done = true },
}
local TAG = { take = { "dsTagTake", "accent" }, pre = { "dsTagPre", "warn" }, inside = { "dsTagInside", "dim" },
              ready = { "dsTagReady", "green" }, log = { "dsTagLog", "soft" }, later = { "dsTagLater", "red" },
              done = { "dsTagDone", "dim" }, skip = { "dsTagSkip", "dim" } }

local function rowFrame(k)
    if pool[k] then return pool[k] end
    local r = CreateFrame("Button", nil, sheet)
    r:SetSize(SW - 2 * SP, ROW)
    local hl = Skin.Tex(r, Skin.COL.accent, 0.06, "HIGHLIGHT"); hl:SetAllPoints()
    r.gem = Skin.Diamond(r, 8, Skin.COL.accent); r.gem:SetPoint("TOPLEFT", 0, -4)
    r.name = Skin.FS(r, 12, Skin.COL.white, Skin.FONT, "LEFT"); r.name:SetPoint("TOPLEFT", 18, -2)
    r.xp = Skin.FS(r, 10, Skin.COL.gold, Skin.FONT, "RIGHT"); r.xp:SetPoint("TOPRIGHT", -24, -3)
    r.name:SetPoint("RIGHT", r.xp, "LEFT", -6, 0)
    if r.name.SetWordWrap then r.name:SetWordWrap(false) end
    r.sub = Skin.FS(r, 10, Skin.COL.soft, Skin.FONT, "LEFT"); r.sub:SetPoint("TOPLEFT", 18, -18); r.sub:SetPoint("RIGHT", r, "RIGHT", -24, 0)
    if r.sub.SetWordWrap then r.sub:SetWordWrap(false) end
    local line = Skin.Tex(r, Skin.COL.faint, 0.6); line:SetHeight(1); line:SetPoint("BOTTOMLEFT"); line:SetPoint("BOTTOMRIGHT")
    -- fleche : la fleche du guide va vers ce PNJ (course), puis revient au guide
    r.go = CreateFrame("Button", nil, r); r.go:SetSize(18, 18); r.go:SetPoint("RIGHT", 0, 0)
    Skin.Border(r.go, Skin.COL.edge)
    r.go.icon = r.go:CreateTexture(nil, "ARTWORK"); r.go.icon:SetSize(12, 12); r.go.icon:SetPoint("CENTER")
    r.go.icon:SetTexture("Interface\\AddOns\\" .. (ADDON or "OghoulesWarpath") .. "\\Media\\IcoNav")
    if r.go.icon.SetVertexColor then r.go.icon:SetVertexColor(Skin.COL.accent[1], Skin.COL.accent[2], Skin.COL.accent[3]) end
    local gh = Skin.Tex(r.go, Skin.COL.accent, 0.15, "HIGHLIGHT"); gh:SetAllPoints()
    r.go:SetScript("OnClick", function(self)
        local q = self:GetParent().q
        if q and q.m and Near.SetErrand then Near.SetErrand(q.m, q.x, q.y, q.npc or q.name); Core.say(Core.T("dsArrowSay", q.npc or q.name)) end
    end)
    r.go:SetScript("OnEnter", function(self)
        local q = self:GetParent().q
        Skin.Tip():SetOwner(self, "ANCHOR_RIGHT"); Skin.Tip():AddLine(Core.T("dsArrowTip", q and (q.npc or q.name) or "?"), 1, 1, 1); Skin.Tip():Show()
    end)
    r.go:SetScript("OnLeave", function() Skin.Tip():Hide() end)
    r:SetScript("OnEnter", function(self)
        local q = self.q; if not q then return end
        local e = Est.EST[q.id] or {}
        Skin.Tip():SetOwner(self, "ANCHOR_LEFT"); Skin.Tip():AddLine(q.name)
        if e.t then Skin.Tip():AddLine(e.t, 1, 1, 1, true) end
        Skin.Tip():AddLine(Core.T("dsTipLvl", e.l or 0, q.req or 1), 0.84, 0.72, 0.4)
        Skin.Tip():Show()
    end)
    r:SetScript("OnLeave", function() Skin.Tip():Hide() end)
    pool[k] = r
    return r
end

local function ruleFrame(k)
    if rules[k] then return rules[k] end
    rules[k] = Skin.TitledRule(sheet, SW - 2 * SP)
    return rules[k]
end

local function render()
    if not (sheet and curKey) then return end
    local d = dungeonOf(curKey)
    local q = DungeonSheet.DungeonQuests(curKey)
    if not (d and q) then sheet:Hide(); return end
    sheet.title:SetText(Skin.Caps(Flow.DungeonName(d)))
    -- une seule ligne : police plus petite si le nom est long
    if sheet.title.SetFont then
        sheet.title:SetFont(Skin.FONT, 12, "")
        if (sheet.title:GetStringWidth() or 0) > SW - 64 then sheet.title:SetFont(Skin.FONT, 10, "") end
    end
    sheet.sub:SetText(Core.T("dsSub", q.zone or "?", d.min, d.max))
    -- XP et niveau
    sheet.big:SetText("+" .. Est.FormatNum(q.xp) .. " XP")
    sheet.nq:SetText(Core.T(q.nxp == 1 and "dsQuests1" or "dsQuests", q.nxp))
    local me = UnitLevel and UnitLevel("player") or 1
    local lvl, pct = project(q.xp)
    sheet.lvl:SetText(lvl > me and Core.T("dsAfter", me, lvl, pct) or Core.T("dsAfterSame", lvl, pct))
    local bw = SW - 2 * SP - 14
    sheet.fill:SetWidth(math.max(1, bw * pct / 100))
    sheet.full:SetShown(lvl > me)
    -- sections
    local y = -34 - 8 - 16 - 8 - 62
    local used, usedR = 0, 0
    for _, sec in ipairs(SECTIONS) do
        local list = {}
        for _, r in ipairs(q.rows) do if sec.sts[r.st] then list[#list + 1] = r end end
        table.sort(list, function(a, b)
            if ORDER[a.st] ~= ORDER[b.st] then return ORDER[a.st] < ORDER[b.st] end
            if a.req ~= b.req then return a.req < b.req end
            return a.name < b.name
        end)
        local hide = sec.done and State.DB.dsHideDone ~= false
        if #list > 0 then
            usedR = usedR + 1
            local ru = ruleFrame(usedR)
            ru:ClearAllPoints(); ru:SetPoint("TOPLEFT", SP, y - 6); ru:Show()
            ru.label:SetText(Skin.Caps(Core.T(sec.key)) .. "  ·  " .. #list)
            local c = sec.red and Skin.COL.red or Skin.COL.gold
            if ru.label.SetTextColor then ru.label:SetTextColor(c[1] + (sec.red and 0.2 or 0), c[2], c[3]) end
            y = y - 22
            if not hide then
                for _, r in ipairs(list) do
                    used = used + 1
                    local f = rowFrame(used)
                    f.q = r
                    f:ClearAllPoints(); f:SetPoint("TOPLEFT", SP, y); f:Show()
                    local tg = TAG[r.st]
                    local tc = Skin.COL[tg[2]] or Skin.COL.soft
                    local hex = string.format("%02x%02x%02x", math.floor(math.min(1, tc[1] + (r.st == "later" and 0.2 or 0)) * 255), math.floor(tc[2] * 255), math.floor(tc[3] * 255))
                    local tag = "|cff" .. hex .. Skin.Caps(Core.T(tg[1], r.req)) .. "|r"
                    local where = {}
                    if r.st == "pre" then where[#where + 1] = r.miss end
                    if r.npc then where[#where + 1] = r.npc end
                    if r.zone and r.st ~= "inside" then where[#where + 1] = r.zone end
                    f.sub:SetText(tag .. (#where > 0 and ("  " .. table.concat(where, " · ")) or ""))
                    f.name:SetText(r.name)
                    local dim = (r.st == "done" or r.st == "skip")
                    local nc = dim and Skin.COL.dim or Skin.COL.white
                    if f.name.SetTextColor then f.name:SetTextColor(nc[1], nc[2], nc[3]) end
                    f.xp:SetText(dim and "" or Est.FormatNum(r.xp))
                    f.gem:SetStyle((r.st == "take") and Skin.COL.accent or (r.st == "ready" or r.st == "log") and Skin.COL.gold
                        or (r.st == "later") and Skin.COL.red or Skin.COL.dim, not (r.st == "take" or r.st == "ready" or r.st == "log"))
                    f.go:SetShown(r.m ~= nil and not dim and r.st ~= "inside")
                    y = y - ROW
                end
            end
        end
    end
    for k = used + 1, #pool do pool[k]:Hide() end
    for k = usedR + 1, #rules do rules[k]:Hide() end
    if #q.rows == 0 then
        sheet.empty:Show(); sheet.empty:ClearAllPoints(); sheet.empty:SetPoint("TOPLEFT", SP, y - 8); y = y - 28
    else sheet.empty:Hide() end
    -- bas : masquer les faites, boutons
    sheet.hide:ClearAllPoints(); sheet.hide:SetPoint("TOPLEFT", SP - 2, y - 8)
    sheet.hide.mark:SetOn(State.DB.dsHideDone ~= false)
    sheet.hide.label:SetText(Core.T("dsHideDone"))
    sheet.hide:SetShown((q.n.done + q.n.skip) > 0)
    y = y - 34
    local active = State.DB.guide == curKey
    sheet.go:SetLabel(Skin.Caps(Core.T(active and "dsActive" or "dsGo")))
    sheet.go:SetEnabled(not active)
    sheet.close:SetLabel(Skin.Caps(Core.T("dsClose")))
    sheet.go:ClearAllPoints(); sheet.go:SetPoint("TOPRIGHT", sheet, "TOPRIGHT", -SP, y)
    sheet.close:ClearAllPoints(); sheet.close:SetPoint("TOPLEFT", sheet, "TOPLEFT", SP, y)
    sheet:SetHeight(-y + 26 + SP)
end

local function makeSheet()
    sheet = CreateFrame("Frame", "WarpathDungeonSheet", UIParent)
    sheet:SetSize(SW, 300)
    sheet:SetFrameStrata("DIALOG"); sheet:SetToplevel(true); sheet:EnableMouse(true); sheet:SetClampedToScreen(true)
    sheet:SetMovable(true); sheet:RegisterForDrag("LeftButton")
    sheet:SetScript("OnDragStart", sheet.StartMoving); sheet:SetScript("OnDragStop", sheet.StopMovingOrSizing)
    local bg = Skin.Tex(sheet, Skin.COL.bg, 0.97, "BACKGROUND"); bg:SetAllPoints()
    Skin.Border(sheet, Skin.COL.line)
    local hbg = Skin.Tex(sheet, Skin.COL.panel or Skin.COL.bg, 1, "BORDER"); hbg:SetHeight(34); hbg:SetPoint("TOPLEFT", 1, -1); hbg:SetPoint("TOPRIGHT", -1, -1)
    local hln = Skin.Tex(sheet, Skin.COL.line, 1, "ARTWORK"); hln:SetHeight(1); hln:SetPoint("TOPLEFT", 0, -34); hln:SetPoint("TOPRIGHT", 0, -34)
    local gem = Skin.Diamond(sheet, 8, Skin.COL.red); gem:SetPoint("LEFT", sheet, "TOPLEFT", 14, -17)
    sheet.title = Skin.FS(sheet, 12, Skin.COL.white, Skin.FONT, "LEFT"); sheet.title:SetPoint("LEFT", sheet, "TOPLEFT", 30, -17)
    sheet.title:SetPoint("RIGHT", sheet, "TOPRIGHT", -30, -17)
    if sheet.title.SetWordWrap then sheet.title:SetWordWrap(false) end
    local x = Skin.HeadButton(sheet, "x"); x:SetPoint("RIGHT", sheet, "TOPRIGHT", -6, -17)
    x:SetScript("OnClick", function() sheet:Hide() end)
    sheet.sub = Skin.FS(sheet, 10, Skin.COL.soft, Skin.FONT, "LEFT"); sheet.sub:SetPoint("TOPLEFT", SP, -34 - 8)
    -- bloc XP : liseré dore a gauche, gros chiffre, niveau atteint, barre
    local xb = CreateFrame("Frame", nil, sheet); xb:SetSize(SW - 2 * SP, 54); xb:SetPoint("TOPLEFT", SP, -34 - 8 - 16 - 6)
    local xbg = Skin.Tex(xb, Skin.COL.panel, 1, "BACKGROUND"); xbg:SetAllPoints()
    local xl = Skin.Tex(xb, Skin.COL.accent, 1, "ARTWORK"); xl:SetWidth(2); xl:SetPoint("TOPLEFT"); xl:SetPoint("BOTTOMLEFT")
    sheet.big = Skin.FS(xb, 16, Skin.COL.cream, Skin.FONT, "LEFT"); sheet.big:SetPoint("TOPLEFT", 10, -6)
    sheet.nq = Skin.FS(xb, 10, Skin.COL.soft, Skin.FONT, "LEFT"); sheet.nq:SetPoint("LEFT", sheet.big, "RIGHT", 8, -1)
    sheet.lvl = Skin.FS(xb, 10, Skin.COL.white, Skin.FONT, "LEFT"); sheet.lvl:SetPoint("TOPLEFT", 10, -26)
    local bar = Skin.Tex(xb, Skin.COL.faint, 1, "ARTWORK"); bar:SetHeight(5); bar:SetPoint("BOTTOMLEFT", 10, 7); bar:SetPoint("BOTTOMRIGHT", -4, 7)
    sheet.full = Skin.Tex(xb, Skin.COL.edge, 1, "ARTWORK"); sheet.full:SetHeight(5); sheet.full:SetPoint("BOTTOMLEFT", 10, 7); sheet.full:SetPoint("BOTTOMRIGHT", -4, 7)
    sheet.fill = Skin.Tex(xb, Skin.COL.accent, 1, "OVERLAY"); sheet.fill:SetHeight(5); sheet.fill:SetPoint("BOTTOMLEFT", 10, 7)
    sheet.empty = Skin.FS(sheet, 11, Skin.COL.soft, Skin.FONT, "LEFT"); sheet.empty:SetWidth(SW - 2 * SP); sheet.empty:SetText(Core.T("dsEmpty"))
    -- masquer les faites (case en losange)
    sheet.hide = CreateFrame("Button", nil, sheet); sheet.hide:SetSize(180, 18)
    sheet.hide.mark = Skin.DiamondCheck(sheet.hide, 10); sheet.hide.mark:SetPoint("LEFT", 0, 0)
    sheet.hide.label = Skin.FS(sheet.hide, 10, Skin.COL.soft, Skin.FONT, "LEFT"); sheet.hide.label:SetPoint("LEFT", sheet.hide.mark, "RIGHT", 4, 0)
    sheet.hide:SetScript("OnClick", function() State.DB.dsHideDone = (State.DB.dsHideDone == false); render() end)
    local bw = math.floor((SW - 2 * SP - 8) / 2)
    sheet.close = Skin.FlatButton(sheet, bw, 26, function() sheet:Hide() end)
    sheet.go = Skin.FlatButton(sheet, bw, 26, function()
        local key = curKey
        sheet:Hide()
        if not key then return end
        -- la question « Faire ce donjon ? » est ouverte : on y repond Oui (sinon sa fermeture dirait « Plus tard »)
        local dlg = _G.WarpathDialog
        if State.asking and State.asking.key == key and dlg and dlg:IsShown() and dlg.button1 then dlg.button1:Click()
        else Flow.StartDungeon(key) end
    end)
    Skin.Border(sheet.go, Skin.COL.accent)
    -- se met a jour pendant qu'elle est ouverte (journal de quetes, niveau)
    local acc = 0
    sheet:SetScript("OnUpdate", function(_, el)
        acc = acc + (el or 0); if acc < 2 then return end; acc = 0
        pcall(render)
    end)
    if UISpecialFrames then table.insert(UISpecialFrames, "WarpathDungeonSheet") end
    sheet:Hide()
end

-- ouvre la fiche d'un donjon (a cote de la fenetre du guide, sinon de la question, sinon au centre)
function DungeonSheetOpen(key)
    if not (key and Core.Guides[key] and dungeonOf(key)) then return false end
    if not CreateFrame or not UIParent then return false end
    if not sheet then makeSheet() end
    curKey = key
    sheet:ClearAllPoints()
    local dlg = _G.WarpathDialog
    local anchor = (dlg and dlg:IsShown() and dlg) or (Core.f and Core.f.IsShown and Core.f:IsShown() and Core.f) or nil
    if anchor and anchor.GetLeft and anchor:GetLeft() and UIParent.GetWidth then
        local mid = ((anchor:GetLeft() or 0) + (anchor:GetRight() or 0)) / 2 * (anchor:GetEffectiveScale() or 1)
        local half = (UIParent:GetWidth() or 0) * (UIParent:GetEffectiveScale() or 1) / 2
        if mid > half then sheet:SetPoint("TOPRIGHT", anchor, "TOPLEFT", -8, 0)
        else sheet:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 8, 0) end
    else
        sheet:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
    end
    render()
    sheet:Show()
    return true
end

-- ferme la fiche (seulement celle de ce donjon si une cle est donnee)
function DungeonSheetHide(key)
    if sheet and sheet:IsShown() and (not key or key == curKey) then sheet:Hide() end
end

-- /warpath donjon fiche : le donjon du guide en cours, sinon le 1er donjon a ton niveau
function DungeonSheetDefault()
    if State.DB and Core.IS_DUNGEON[State.DB.guide] then return DungeonSheetOpen(State.DB.guide) end
    local me = UnitLevel and UnitLevel("player") or 1
    for _, d in ipairs(Core.DUNGEONS) do
        if Core.Guides[d.key] and me >= d.min and me <= d.max and (DungeonBadge(d.key)) > 0 then return DungeonSheetOpen(d.key) end
    end
    return false
end

-- v1.50 : ce que ce fichier offre aux autres (ns.Mod.DungeonSheet)
do
    local M = ns.Mod.DungeonSheet
    M.DungeonAskLine = DungeonAskLine
    M.DungeonBadge = DungeonBadge
    M.DungeonSheetDefault = DungeonSheetDefault
    M.DungeonSheetHide = DungeonSheetHide
    M.DungeonSheetOpen = DungeonSheetOpen
end
