-- Oghoule's Warpath : moteur (Flow.lua) - voir Core.lua
local ADDON, ns = ...
local _ENV = ns.CoreEnv
if setfenv then setfenv(1, _ENV) end

------------------------------------------------------------------
-- Guides
------------------------------------------------------------------
SetGuide = nil
AskChain, StartChain = nil, nil

function MyChain()
    local c = CHAIN[myRace]
    if not c and UnitFactionGroup and UnitFactionGroup("player") == "Horde" then c = CHAIN.Skyborne end
    return c
end

function Advance()
    if not DB or not steps then return end
    Compute()
    pcall(ns.Drops.Refresh, logById, EST)
    Refresh()
    pcall(SuggestDungeonForLevel)
    if current > #steps then
        if DB.guide == "chain" then
            local back = DB.chainBack
            DB.chainBack, DB.chainQ, DB.chainSelf = nil, nil, nil
            Guides.chain = nil
            say(T("chainBackMsg"))
            if back and Guides[back] then SetGuide(back, true) end
            return
        end
        if IS_DUNGEON[DB.guide] then
            local back = DB.main
            DB.main = nil
            if back and Guides[back] then
                say(T("dDone", Title(G)))
                SetGuide(back, true)
            end
            return
        end
        -- zone choisie pour la suite dans les options
        local nxt = DB.nextGuide
        if nxt and Guides[nxt] and nxt ~= DB.guide then
            DB.nextGuide = nil
            DB.manual = true
            say(T("nextChosen", Title(G), Title(Guides[nxt])))
            SetGuide(nxt, true)
            return
        end
        local c = MyChain()
        if c and not DB.manual then
            for k = 1, #c - 1 do
                if c[k] == DB.guide and Guides[c[k + 1]] then
                    say(T("chainNext", Title(G), Title(Guides[c[k + 1]])))
                    SetGuide(c[k + 1], true)
                    return
                end
            end
        end
    end
end

function ScheduleAdvance()
    if pending then return end
    pending = true
    if C_Timer and C_Timer.After then
        C_Timer.After(0.25, function()
            pending = false
            local ok, err = pcall(Advance)
            if not ok and not errShown then errShown = true; say(T("errInternal", tostring(err))) end
        end)
    else
        pending = false
        Advance()
    end
end

SetGuide = function(key, quiet)
    if not Guides[key] then return false end
    DB.guide = key
    G = Guides[key]
    steps = G.steps
    peek, lastWP, focus = nil, nil, nil
    AnalyzeChains()
    if not quiet then say(T("guideSet", Title(G))) end
    Advance()
    Refresh(true)
    return true
end

-- Choix automatique : le guide le plus avance de ta chaine selon ton niveau
-- OU selon les quetes deja rendues (utile apres une session sans l'addon).
function HasEvidence(key)
    local count = 0
    for _, s in ipairs(Guides[key].steps) do
        if s.t == "turnin" and ListHas(s.class, myClass) and ListHas(s.race, myRace) then
            for _, id in ipairs(Ids(s)) do
                if Rendue(id) then count = count + 1; break end
            end
        end
    end
    return count >= 3
end

function AllDone(key)
    -- evalue un autre guide sans toucher a l'etat du guide en cours
    local saveG, saveS, saveK, saveCur = G, steps, DB.guide, current
    local saveDone, savePend, saveStep = doneCache, pendingAccept, DB.step[key]
    doneCache, pendingAccept = {}, {}
    G, steps, DB.guide = Guides[key], Guides[key].steps, key
    computingOther = true
    local ok = pcall(Compute)
    computingOther = false
    local fini = ok and current > #steps
    G, steps, DB.guide, current = saveG, saveS, saveK, saveCur
    doneCache, pendingAccept, DB.step[key] = saveDone, savePend, saveStep
    return fini
end

-- Etat d'un guide pour la liste des zones : "done" (tu as fait la zone : au moins la moitie de ses quetes rendues),
-- "low" (zone trop basse pour toi : ses quetes ne valent plus la peine), ou nil (a faire)
function GuideStatus(key)
    local g = Guides[key]; if not g then return nil end
    local total, done, seen = 0, 0, {}
    for _, s in ipairs(g.steps or {}) do
        if s.t == "turnin" and Applies(s) then
            for _, id in ipairs(Ids(s)) do
                if not seen[id] and QAvailable(id) then
                    seen[id] = true; total = total + 1
                    if Rendue(id) then done = done + 1 end
                end
            end
        end
    end
    if total > 0 and done * 2 >= total then return "done" end
    local lvl = UnitLevel("player") or 1
    if not IS_DUNGEON[key] and lvl >= (MAXLVL[key] or 99) then return "low" end
    return nil
end

function AutoPick()
    local c = MyChain()
    if not c then return nil end
    local lvl = UnitLevel("player")
    local best = 1
    for k, key in ipairs(c) do
        if Guides[key] then
            if lvl >= (MAXLVL[key] or 99) and k < #c then best = math.max(best, k + 1) end
            if HasEvidence(key) then best = math.max(best, k) end
        end
    end
    while best < #c and AllDone(c[best]) do best = best + 1 end
    return c[best]
end

------------------------------------------------------------------
-- Donjons : proposition et mini-guide temporaire
------------------------------------------------------------------
function StartDungeon(key)
    if not Guides[key] then return end
    if not IS_DUNGEON[DB.guide] then DB.main = DB.guide end
    DB.dAnswer[key] = "yes"
    SetGuide(key)
    say(T("dStart"))
end

function StopDungeon()
    if not IS_DUNGEON[DB.guide] then say(T("dNone")); return end
    local back = DB.main
    DB.main = nil
    if back and Guides[back] then SetGuide(back) end
end

asking = nil
CheckDungeonsFn = nil
if StaticPopupDialogs then
    StaticPopupDialogs["WARPATH_DUNGEON"] = {
        text = "%s",
        button1 = "Oui",
        button2 = "Non",
        button3 = "Plus tard",
        OnShow = function(self)
            local b1 = self.button1 or _G[self:GetName() .. "Button1"]
            local b2 = self.button2 or _G[self:GetName() .. "Button2"]
            local b3 = self.button3 or _G[self:GetName() .. "Button3"]
            if b1 then b1:SetText(T("yes")) end
            if b2 then b2:SetText(T("no")) end
            if b3 then b3:SetText(T("later")) end
        end,
        OnAccept = function() if asking then StartDungeon(asking.key) end end,
        OnCancel = function(_, _, reason)
            if not asking then return end
            if reason == "clicked" then DB.dAnswer[asking.key] = "no"
            else DB.dAnswer[asking.key] = "later"; DB.dLater[asking.key] = math.max(UnitLevel("player") or 1, (select(3, DungeonReq(asking.key)) or 0) - 1) end
        end,
        OnAlt = function()
            if asking then DB.dAnswer[asking.key] = "later"; DB.dLater[asking.key] = math.max(UnitLevel("player") or 1, (select(3, DungeonReq(asking.key)) or 0) - 1) end
        end,
        OnHide = function()
            asking = nil
            -- propose le donjon suivant (s'il y en a un a ton niveau)
            if C_Timer and C_Timer.After then C_Timer.After(0.5, CheckDungeonsFn) end
        end,
        timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    }
end


-- Proposer la chaine qui debloque une quete
chainAskQ = nil
AskChain = function(q, withSelf, kind)
    local order, bad = ChainFor(q, withSelf)
    local e = EST[q]
    if not order or not e or #order == 0 then say(T("chainNone", (e and e.n) or tostring(q))); return end
    local names = {}
    for _, id in ipairs(order) do names[#names + 1] = EST[id].n end
    local est = Estimate(order, true)
    local kt, measured = KillTime()
    local pace = measured and T("paceMeasured", math.floor(kt + 0.5), DB.ktN or 0) or T("paceClass", math.floor(kt + 0.5))
    local txt = T(kind == "prof" and "profAsk" or (withSelf and "classAsk" or "chainAsk"), e.n, T(withSelf and "classList" or "chainList", #order, table.concat(names, ", ")),
        math.max(1, math.floor(est.secs / 60 + 0.5)), FormatNum(est.xp), FormatNum(est.qxp), FormatNum(est.mxp),
        FormatNum(est.perHour), est.kills, pace)
        .. (est.dropKills > 0 and ("\n" .. T("dropNote", est.dropKills)) or "")
    for _, dr in ipairs(est.drops) do
        local pct = math.floor(dr.rate * 100 + 0.5)
        if dr.how == "unique" then txt = txt .. "\n- " .. T("dropUnique", dr.name)
        elseif dr.how == "measured" then txt = txt .. "\n- " .. T("dropMeasured", dr.name, pct, dr.k)
        elseif dr.how == "questie" then txt = txt .. "\n- " .. T("dropQuestie", dr.name, pct)
        else txt = txt .. "\n- " .. T("dropAssumed", dr.name, pct, dr.k or 0) end
    end
    chainAskQ, chainAskSelf = q, withSelf
    StaticPopupDialogs["WARPATH_CHAIN"] = StaticPopupDialogs["WARPATH_CHAIN"] or {
        text = "%s", button1 = "OK", button2 = "Non", timeout = 0, whileDead = true, hideOnEscape = true,
        OnAccept = function() StartChain(chainAskQ, chainAskSelf) end,
    }
    local d = StaticPopupDialogs["WARPATH_CHAIN"]
    d.button1, d.button2 = T("chainGo"), T("chainNo")
    ns.Trace("popup WARPATH_CHAIN"); Popup("WARPATH_CHAIN", txt)
end

StartChain = function(q, withSelf)
    local g = BuildChainGuide(q, withSelf)
    if not g then say(T("chainNone", (EST[q] and EST[q].n) or tostring(q))); return end
    if DB.guide ~= "chain" then DB.chainBack = DB.guide end
    DB.chainQ, DB.chainSelf = q, withSelf or nil
    Guides.chain = g
    say(T(withSelf and "classStartMsg" or "chainStartMsg", EST[q].n, #g.steps))
    SetGuide("chain", true)
end

-- Quetes de donjon restantes pour toi : seules les quetes deja rendues comptent comme faites (une quete dans ton journal reste a faire)
function DungeonLeft(key)
    local g = Guides[key]; if not g then return 0, 0 end
    local seen, left, total = {}, 0, 0
    for _, s in ipairs(g.steps or {}) do
        if s.t == "turnin" or s.t == "accept" then
            for _, id in ipairs(Ids(s)) do
                if id and not seen[id] and QAvailable(id) then
                    seen[id] = true; total = total + 1
                    if not Rendue(id) then left = left + 1 end
                end
            end
        end
    end
    return left, total
end

-- Donjon deja fait : toutes ses quetes rendues, ou au moins les trois quarts
function DungeonDone(key)
    local left, total = DungeonLeft(key)
    return total > 0 and (left == 0 or left / total <= 0.25)
end

-- Quetes du donjon que tu peux prendre maintenant, et le niveau ou tu pourras toutes les prendre
function DungeonReq(key)
    local g = Guides[key]; if not g then return 0, 0, 0 end
    local lvl = UnitLevel("player") or 1
    local seen, n, now, need, total = {}, 0, 0, 0, 0
    local function open(s)
        for _, p in ipairs(s.preg or {}) do if not Rendue(p) and logById[p] == nil then return false end end
        if s.pre then
            for _, p in ipairs(s.pre) do if Rendue(p) or logById[p] ~= nil then return true end end
            return false
        end
        return true
    end
    for _, s in ipairs(g.steps or {}) do
        if s.t == "accept" then
            total = total + 1
            for _, id in ipairs(Ids(s)) do
                -- seulement les quetes que tu peux vraiment prendre (prerequis faits ou en cours)
                if id and not seen[id] and QAvailable(id) and not Rendue(id) and (logById[id] ~= nil or open(s)) then
                    seen[id] = true; n = n + 1
                    if (s.req or 0) <= lvl then now = now + 1 elseif s.req > need then need = s.req end
                end
            end
        end
    end
    return n, now, need, total
end

-- un donjon dont aucune quete n'est accessible (chaines pas commencees) n'est pas propose ; une aile sans quete l'est
function DungeonOpen(key)
    local n, _, _, total = DungeonReq(key)
    return n > 0 or total == 0
end

function DungeonReqText(key)
    local n, now, need = DungeonReq(key)
    if n == 0 then return "" end
    if need > 0 then return T(n == 1 and "dReqWait1" or "dReqWait", now, n, need) end
    return T(n == 1 and "dReqAll1" or "dReqAll", n)
end

function CheckDungeons()
    if not DB or DB.noDungeonAsk or IS_DUNGEON[DB.guide] or not StaticPopup_Show or asking then return end
    local lvl = UnitLevel("player")
    -- les donjons "de chez toi" d'abord (ex. Shadowfang Keep pour un Undead)
    local HOME = { Scourge = "sfk", Undead = "sfk", Orc = "rfc", Troll = "rfc", Tauren = "wc" }
    local order = {}
    for _, d in ipairs(DUNGEONS) do
        if d.key == HOME[myRace] then table.insert(order, 1, d) else order[#order + 1] = d end
    end
    for _, d in ipairs(order) do
        local ans = DB.dAnswer[d.key]
        local later = ans == "later" and (DB.dLater[d.key] or 0) < lvl
        if Guides[d.key] and lvl >= d.min and lvl <= d.max and (ans == nil or later) and not DungeonDone(d.key) and DungeonOpen(d.key) then
            asking = d
            ns.Trace("popup WARPATH_DUNGEON"); Popup("WARPATH_DUNGEON", T("dAsk", lvl, d.name, d.min, d.max) .. DungeonReqText(d.key))
            return
        end
    end
end

CheckDungeonsFn = CheckDungeons

-- Quetes de classe importantes (ClassQuests.lua) : la variante de ta race, si elle n'est pas deja faite
function ClassQuestList()
    local out = {}
    for _, r in ipairs((ns.ClassQuests or {})[myClass] or {}) do
        local pick, done = nil, false
        for _, id in ipairs(r[3]) do
            if EST[id] and QAvailable(id) then
                if Rendue(id) then done = true elseif not pick then pick = id end
            end
        end
        if pick or done then out[#out + 1] = { lvl = r[1], name = r[2], q = pick, done = done } end
    end
    return out
end

-- Propose une quete de classe quand tu atteins son niveau (une seule fois par quete)
function CheckClassQuests()
    if not DB or DB.noClassAsk or DB.guide == "chain" or IS_DUNGEON[DB.guide] or asking or not StaticPopup_Show then return end
    if PopupVisible() or (StaticPopup_Visible and (StaticPopup_Visible("WARPATH_CHAIN") or StaticPopup_Visible("WARPATH_DUNGEON"))) then return end
    DB.cqAsked = DB.cqAsked or {}
    local lvl = UnitLevel("player") or 1
    for _, c in ipairs(ClassQuestList()) do
        if c.q and not c.done and lvl >= c.lvl and lvl <= c.lvl + 8 and not DB.cqAsked[c.name] and logById[c.q] == nil then
            local order = ChainFor(c.q, true)
            if order and #order > 0 then
                DB.cqAsked[c.name] = true
                AskChain(c.q, true)
                return
            end
        end
    end
end

function ListDungeons()
    local lvl = UnitLevel("player")
    local LBL = { yes = T("ansYes"), no = T("ansNo"), later = T("ansLater") }
    for _, d in ipairs(DUNGEONS) do
        local ok = lvl >= d.min and lvl <= d.max
        say(string.format("  %s%s - %s (%d-%d)%s%s|r", ok and "|cff9cc7a8" or "|cff8c7f62", d.key, d.name, d.min, d.max,
            ok and T("yourLevel") or "", DB.dAnswer[d.key] and (" [" .. LBL[DB.dAnswer[d.key]] .. "]") or "")
            .. (function() local l, t = DungeonLeft(d.key); return t > 0 and T("dQuests", t - l, t) or "" end)()
            .. (function() local n, now, need = DungeonReq(d.key); return (ok and need > 0) and T("dReqList", need) or "" end)())
    end
    say(T("dHelp"))
end

------------------------------------------------------------------
-- Actions
------------------------------------------------------------------
function Ignore()
    if not steps then return end
    local i = peek or focus or current
    local s = steps[i]
    if not s then return end
    focus = nil
    if s.id then
        local names = {}
        for _, id in ipairs(Ids(s)) do
            DB.ignored[id] = true
            names[#names + 1] = tostring(id)
        end
        say(T("ignored", QName(s) or "?", table.concat(names, ", ")))
    else
        DB.seen[SeenKey(i)] = true
    end
    peek = nil
    Advance()
    Refresh(true)
end

function Peek(dir)
    if not steps then return end
    local n = #steps
    local i = peek or focus or current
    focus = nil
    repeat i = i + dir until i < 1 or i > n or Applies(steps[i])
    if i < 1 then i = (peek or current) end
    if i > n then i = math.min(peek or current, n) end
    peek = (i ~= current) and i or nil
    Refresh(true)
    if not peek then lastWP = nil; Refresh(true) end
end

------------------------------------------------------------------
-- Niveau de fin de zone atteint : on propose de passer a la suivante (une fois par zone),
-- en listant les quetes encore dans le journal : celles qui continuent dans la prochaine zone
-- (le guide les reprendra) et celles a finir ici avant de partir.
------------------------------------------------------------------
function CheckZoneLevel()
    if not DB or not steps or not G then return end
    local key = DB.guide
    if not key or key == "chain" or IS_DUNGEON[key] or current > #steps then return end
    local lvl = UnitLevel("player") or 1
    if lvl < (MAXLVL[key] or 99) then return end
    DB.zoneAsked = DB.zoneAsked or {}
    if DB.zoneAsked[key] then return end
    local c, nxt = MyChain(), nil
    if DB.nextGuide and Guides[DB.nextGuide] and DB.nextGuide ~= key then nxt = DB.nextGuide end
    if not nxt and c then for k = 1, #c - 1 do if c[k] == key then nxt = c[k + 1] end end end
    if not (nxt and Guides[nxt]) then return end
    DB.zoneAsked[key] = true
    -- quetes du guide encore dans le journal
    local inNext = {}
    for _, s in ipairs(Guides[nxt].steps or {}) do
        if s.t == "do" or s.t == "turnin" then for _, id in ipairs(Ids(s)) do inNext[id] = true end end
    end
    local carry, finish, seen = {}, {}, {}
    for _, s in ipairs(steps) do
        if (s.t == "accept" or s.t == "do" or s.t == "turnin") and Applies(s) then
            for _, id in ipairs(Ids(s)) do
                if not seen[id] and logById[id] ~= nil and not Rendue(id) then
                    seen[id] = true
                    local name = QuestTitle(id) or s.quest or tostring(id)
                    if inNext[id] then carry[#carry + 1] = name
                    elseif not IsGrey(s) then finish[#finish + 1] = name end
                end
            end
        end
    end
    local function list(t) local o = {}; for i = 1, math.min(#t, 6) do o[i] = "- " .. t[i] end; if #t > 6 then o[#o + 1] = "- ..." end; return table.concat(o, "\n") end
    local txt = T("zoneUp", lvl, Title(G), Title(Guides[nxt]))
    if #finish > 0 then txt = txt .. "\n\n" .. T("zoneUpFinish") .. "\n" .. list(finish) end
    if #carry > 0 then txt = txt .. "\n\n" .. T("zoneUpCarry", Title(Guides[nxt])) .. "\n" .. list(carry) end
    StaticPopupDialogs["WARPATH_ZONEUP"] = {
        text = "%s", button1 = T("zoneUpGo"), button2 = T("zoneUpStay"), timeout = 0, whileDead = true, hideOnEscape = true,
        OnAccept = function()
            if DB.guide ~= key then return end
            if DB.nextGuide == nxt then DB.nextGuide = nil end
            DB.manual = nil
            say(T("zoneUpGoMsg", Title(Guides[nxt])))
            SetGuide(nxt, true)
        end,
        OnCancel = function() if DB.guide == key then DB.nextGuide = nxt end; say(T("zoneUpStayMsg", Title(Guides[nxt]))) end,
    }
    Popup("WARPATH_ZONEUP", txt)
end
