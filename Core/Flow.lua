-- Oghoule's Warpath : moteur (Flow.lua) - voir Core.lua
local ADDON, ns = ...
local _ENV = ns.CoreEnv
if setfenv then setfenv(1, _ENV) end
-- v1.50 : etat partage du guide (Core.lua, ns.State)
local State = ns.State
-- v1.50 : noms propres a ce fichier (sortis de DECL, Core.lua)
local CheckDungeonsFn, DG_LEFT_DIST, DungeonKeyForInstance, HasEvidence, StartChain, WovenCleanup, WovenReport
local chainAskQ, chainAskSelf

------------------------------------------------------------------
-- Guides
------------------------------------------------------------------
SetGuide = nil
AskChain, StartChain = nil, nil

function MyChain()
    local c = CHAIN[State.myRace]
    if not c and UnitFactionGroup and UnitFactionGroup("player") == "Horde" then c = CHAIN.Skyborne end
    return c
end

function Advance()
    if not DB or not State.steps then return end
    Compute()
    pcall(WovenCleanup)
    pcall(ns.Drops.Refresh, logById, EST)
    Refresh()
    pcall(SuggestDungeonForLevel)
    if State.current > #State.steps then
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
                say(T("dDone", Title(State.G)))
                SetGuide(back, true)
            end
            return
        end
        -- zone choisie pour la suite dans les options
        local nxt = DB.nextGuide
        if nxt and Guides[nxt] and nxt ~= DB.guide then
            DB.nextGuide = nil
            DB.manual = true
            say(T("nextChosen", Title(State.G), Title(Guides[nxt])))
            SetGuide(nxt, true)
            return
        end
        local c = MyChain()
        if c and not DB.manual then
            for k = 1, #c - 1 do
                if c[k] == DB.guide and Guides[c[k + 1]] then
                    say(T("chainNext", Title(State.G), Title(Guides[c[k + 1]])))
                    SetGuide(c[k + 1], true)
                    return
                end
            end
        end
    end
end

function ScheduleAdvance()
    if State.pending then return end
    State.pending = true
    if C_Timer and C_Timer.After then
        C_Timer.After(0.25, function()
            State.pending = false
            local ok, err = pcall(Advance)
            if not ok and not errShown then errShown = true; say(T("errInternal", tostring(err)), "error") end
        end)
    else
        State.pending = false
        Advance()
    end
end

SetGuide = function(key, quiet)
    if not Guides[key] then return false end
    DB.guide = key
    State.G = Guides[key]
    State.steps = State.G.steps
    -- v1.47 : chaines de classe integrees au guide (copie du guide, Data/Guides.lua n'est jamais modifie)
    local ok, woven, outside = pcall(WeaveSteps, State.G, key)
    if ok then
        if woven then State.steps = woven end
        if outside then pcall(WovenReport, outside) end
    end
    State.peek, State.lastWP, State.focus = nil, nil, nil
    AnalyzeChains()
    if not quiet then say(T("guideSet", Title(State.G))) end
    Advance()
    Refresh(true)
    return true
end

-- Choix automatique : le guide le plus avance de ta chaine selon ton niveau
-- OU selon les quetes deja rendues (utile apres une session sans l'addon).
function HasEvidence(key)
    local count = 0
    for _, s in ipairs(Guides[key].steps) do
        if s.t == "turnin" and ListHas(s.class, State.myClass) and ListHas(s.race, State.myRace) then
            for _, id in ipairs(Ids(s)) do
                if Rendue(id) then count = count + 1; break end
            end
        end
    end
    return count >= 3
end

function AllDone(key)
    -- evalue un autre guide sans toucher a l'etat du guide en cours
    local saveG, saveS, saveK, saveCur = State.G, State.steps, DB.guide, State.current
    local saveDone, savePend, saveStep = State.doneCache, State.pendingAccept, DB.step[key]
    State.doneCache, State.pendingAccept = {}, {}
    State.G, State.steps, DB.guide = Guides[key], Guides[key].steps, key
    State.computingOther = true
    local ok = pcall(Compute)
    State.computingOther = false
    local fini = ok and State.current > #State.steps
    State.G, State.steps, DB.guide, State.current = saveG, saveS, saveK, saveCur
    State.doneCache, State.pendingAccept, DB.step[key] = saveDone, savePend, saveStep
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
-- Est-ce bien le donjon suivi ? (numero d'instance connu, ou nom). En cas de doute on accepte :
-- le bouton OK de l'etape d'entree permet toujours de passer au journal a la main.
local INSTANCE_IDS = { rfc = 389, wc = 43, sfk = 33, bfd = 48, rfk = 47, gnomer = 90, sm_gy = 189, sm_lib = 189, sm_arm = 189,
    sm_cath = 189, rfd = 129, uld = 70, zf = 209, mara_out = 349, mara_in = 349, st = 109, brd = 230, dm_e = 429, dm_w = 429,
    lbrs = 229, ubrs = 229, scholo = 289, strat_live = 329, strat_ud = 329 }
function DungeonInstanceMatches(key)
    if not (GetInstanceInfo and key) then return true end
    local name, _, _, _, _, _, _, id = GetInstanceInfo()
    local want = INSTANCE_IDS[key]
    if want and id == want then return true end
    local dn
    for _, d in ipairs(DUNGEONS) do if d.key == key then dn = d.name end end
    dn = dn and dn:gsub("%s*:.*$", ""):gsub("%s*%b()", "")
    if type(name) == "string" and dn and (name:lower():find(dn:lower(), 1, true) or dn:lower():find(name:lower(), 1, true)) then return true end
    -- refus seulement si c'est clairement un AUTRE donjon connu (numero different d'un donjon de la liste)
    if type(id) == "number" and id ~= want then
        for k, v in pairs(INSTANCE_IDS) do if v == id and v ~= want then return false end end
    end
    return true
end

-- dans l'instance du donjon suivi ?
function InDgInstance()
    if not (DB and IS_DUNGEON[DB.guide] and IsInInstance) then return false end
    local inI, kind = IsInInstance()
    return (inI and kind == "party" and DungeonInstanceMatches(DB.guide)) and true or false
end
-- donjon connu correspondant a l'instance (le premier avec des quetes a faire, sinon le premier)
function DungeonKeyForInstance()
    if not GetInstanceInfo then return nil end
    local _, _, _, _, _, _, _, id = GetInstanceInfo()
    local first
    for _, d in ipairs(DUNGEONS) do
        if INSTANCE_IDS[d.key] == id and Guides[d.key] then
            first = first or d.key
            if (DungeonLeft(d.key)) > 0 then return d.key end
        end
    end
    return first
end
-- entree / sortie d'instance (appele par Events.lua)
local wasIn, askedInst = false, nil
function OnInstanceChange()
    if not DB or not IsInInstance then return end
    local inI, kind = IsInInstance()
    local party = inI and kind == "party"
    if party and IS_DUNGEON[DB.guide] and DungeonInstanceMatches(DB.guide) then
        DB.dgIn = DB.dgIn or {}
        if not wasIn and DB.dgOut and DB.dgOut[DB.guide] and DB.dgIn[DB.guide] then
            -- de retour dans le donjon apres l'avoir quitte : le journal revient
            DB.dgOut[DB.guide] = nil
        end
        DB.dgIn[DB.guide] = true
        if ChronDungeon then pcall(ChronDungeon, DB.guide) end
        State.focus = nil; wasIn = true
        return
    end
    if party then
        -- autre donjon que celui suivi (ou aucun) : on propose d'y basculer, une fois par entree
        local id = 0
        if GetInstanceInfo then id = select(8, GetInstanceInfo()) or 0 end
        local key = DungeonKeyForInstance()
        if key and key ~= DB.guide and askedInst ~= id and (DungeonLeft(key)) > 0 then
            askedInst = id
            StaticPopupDialogs["WARPATH_DGSWITCH"] = {
                text = "%s", button1 = T("dgSwitchYes"), button2 = T("dgSwitchNo"), timeout = 0, whileDead = true, hideOnEscape = true,
                OnAccept = function()
                    StartDungeon(key)
                    DB.dgIn = DB.dgIn or {}; DB.dgIn[key] = true
                    if ChronDungeon then pcall(ChronDungeon, key) end
                    wasIn = true; Advance(); Refresh(true)
                end,
            }
            Popup("WARPATH_DGSWITCH", T("dgSwitch", Title(Guides[key])))
        end
        return
    end
    askedInst = nil
    -- sortie de l'instance suivie : le journal se ferme si tu es vivant et que tes quetes sont faites
    -- (ou que le groupe est dissous). Une mort (course en fantome) ne compte pas.
    if wasIn and IS_DUNGEON[DB.guide] and DB.dgIn and DB.dgIn[DB.guide] then
        wasIn = false
        if UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") then wasIn = true; return end
        local allDone = true
        for _, r in ipairs(DungeonLogList and DungeonLogList() or {}) do if not r.later and not r.done then allDone = false end end
        local solo = (GetNumGroupMembers and GetNumGroupMembers() or 0) <= 1
        if allDone or solo then
            DB.dgOut = DB.dgOut or {}; DB.dgOut[DB.guide] = true
            say(T("dgAutoOut"), true)
        end
    end
    wasIn = false
    pcall(CheckDungeonLeft)
end

-- v1.41 : sortie du donjon jamais notee (sortie en groupe avec une quete pas finie, ou deconnexion dans
-- l'instance) : des que tu es dehors, vivant, a plus de 300 m de l'entree, le journal se ferme et le guide
-- passe aux remises. Seulement si tu es deja entre : le ramassage des quetes (partout) n'est pas touche.
-- Si tu y retournes, le journal revient tout seul (OnInstanceChange).
DG_LEFT_DIST = 300
-- v1.45 : resurrection a l'ange (vivant, au cimetiere a > 300 m de l'entree) : ce n'est pas une sortie.
-- Apres une mort, on attend 30 min ou ton retour dans le donjon avant de fermer le journal tout seul.
local DG_DEATH_GRACE = 1800
local dgDeathAt = nil
function CheckDungeonLeft()
    if not (DB and State.steps and IS_DUNGEON[DB.guide]) then return end
    if not (DB.dgIn and DB.dgIn[DB.guide]) or (DB.dgOut and DB.dgOut[DB.guide]) then return end
    if IsInInstance and IsInInstance() then dgDeathAt = nil; return end
    local now = GetTime and GetTime() or 0
    if UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") then dgDeathAt = now; return end
    if dgDeathAt and now - dgDeathAt < DG_DEATH_GRACE then return end
    dgDeathAt = nil
    local s
    for j = 1, #State.steps do if State.steps[j].t == "go" then s = State.steps[j]; break end end   -- etape d'entree du donjon
    if not (s and s.m and s.x) then return end
    local me, w = PlayerWP(), WP(s.m, s.x, s.y)
    if not me then return end
    if w and me[3] == w[3] and Dist(me[1], me[2], w[1], w[2]) <= DG_LEFT_DIST then return end
    DB.dgOut = DB.dgOut or {}; DB.dgOut[DB.guide] = true
    say(T("dgAutoOut"), true)
    State.lastWP = nil
    pcall(Advance); Refresh(true)
end

function StartDungeon(key)
    if not Guides[key] then return end
    if not IS_DUNGEON[DB.guide] then DB.main = DB.guide end
    DB.dAnswer[key] = "yes"
    DB.dgOut = DB.dgOut or {}; DB.dgOut[key] = nil
    DB.dgIn = DB.dgIn or {}; DB.dgIn[key] = nil
    SetGuide(key)
    say(T("dStart"))
end

function StopDungeon()
    if not IS_DUNGEON[DB.guide] then say(T("dNone")); return end
    local back = DB.main
    DB.main = nil
    if back and Guides[back] then SetGuide(back) end
end

State.asking = nil
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
            local b4 = self.button4
            if b4 then b4:SetText(T("dsBtn")) end
        end,
        button4 = "Voir les quêtes",
        OnButton4 = function() if State.asking and DungeonSheetOpen then DungeonSheetOpen(State.asking.key) end end,
        OnAccept = function() if State.asking then StartDungeon(State.asking.key) end end,
        OnCancel = function(_, _, reason)
            if not State.asking then return end
            if reason == "clicked" then DB.dAnswer[State.asking.key] = "no"
            else DB.dAnswer[State.asking.key] = "later"; DB.dLater[State.asking.key] = math.max(UnitLevel("player") or 1, (select(3, DungeonReq(State.asking.key)) or 0) - 1) end
        end,
        OnAlt = function()
            if State.asking then DB.dAnswer[State.asking.key] = "later"; DB.dLater[State.asking.key] = math.max(UnitLevel("player") or 1, (select(3, DungeonReq(State.asking.key)) or 0) - 1) end
        end,
        OnHide = function()
            -- v1.46 : la question se ferme (Oui, Non, Plus tard, Echap) : sa fiche de donjon aussi
            if State.asking and DungeonSheetHide then pcall(DungeonSheetHide, State.asking.key) end
            State.asking = nil
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
    -- v1.43 : fenetre lisible (titre, sous-titre, chiffres arrondis avec libelles, objets, etapes en gris)
    -- Quete de classe : meme nom que dans Options > Classe (la 1re quete de la chaine), la finale en sous-titre
    local label = e.n
    if withSelf and kind ~= "prof" then
        for _, c in ipairs(ClassQuestList()) do if c.q == q then label = c.label or c.name; break end end
    end
    local function round(n) n = n or 0; if n >= 1000 then n = math.floor(n / 100 + 0.5) * 100 end; return FormatNum(n) end
    local G, S, F = "|cffcdbb8e", "|cffb5aa98", "|cff8c7f62"   -- or, doux, discret (HEX de Skin.lua)
    local lines = {}
    local function add(s) lines[#lines + 1] = s end
    add(G .. Upper(withSelf and label or T("chainUnlock", e.n)) .. "|r")
    if not withSelf then add(S .. T("chainSubBefore", #order) .. "|r")
    elseif label ~= e.n then add(S .. T("chainSubEnds", #order, e.n) .. "|r")
    else add(S .. T("chainSubN", #order) .. "|r") end
    add("")
    add(G .. T("chainTime") .. "|r  ~" .. math.max(1, math.floor(est.secs / 60 + 0.5)) .. " min")
    add(G .. T("chainXP") .. "|r  ~" .. round(est.xp) .. "  " .. S .. T("chainPerHour", round(est.perHour)) .. "|r")
    if est.kills > 0 then
        add(G .. T("chainMobs") .. "|r  " .. (est.dropKills > 0 and T("chainKillsDrop", est.kills, est.dropKills) or T("chainKills", est.kills)))
    end
    if #est.drops > 0 then
        add(""); add(G .. T("chainItems") .. "|r")
        for _, dr in ipairs(est.drops) do
            local r = dr.rate or 0
            local how
            if dr.how == "unique" then how = T("dropSure")
            elseif r >= 0.6 or r <= 0 then how = T("dropOften")
            else how = T("dropOneIn", math.floor(1 / r + 0.5)) end
            add(" • " .. dr.name .. " " .. S .. "— " .. how .. "|r")
        end
    end
    add(""); add(F .. T("chainSteps") .. " " .. table.concat(names, " › ") .. "|r")
    local txt = table.concat(lines, "\n")
    chainAskQ, chainAskSelf = q, withSelf
    StaticPopupDialogs["WARPATH_CHAIN"] = StaticPopupDialogs["WARPATH_CHAIN"] or {
        text = "%s", button1 = "OK", button2 = "Non", timeout = 0, whileDead = true, hideOnEscape = true,
        OnAccept = function() StartChain(chainAskQ, chainAskSelf) end,
    }
    local d = StaticPopupDialogs["WARPATH_CHAIN"]
    d.button1, d.button2 = T("chainGo"), T("chainNo")
    -- v1.47 : 3e bouton pour une quete de classe : l'integrer au guide de zone (ou l'en retirer)
    if withSelf and kind ~= "prof" then
        d.button3 = T((DB.woven and DB.woven[q]) and "wovenBtnOff" or "wovenBtn")
    else
        d.button3 = nil
    end
    d.OnAlt = function()
        if not chainAskQ then return end
        if DB.woven and DB.woven[chainAskQ] then Unweave(chainAskQ) else Weave(chainAskQ) end
    end
    -- titre de la fenetre selon le type : quetes de classe, metiers ou chaine ordinaire
    d.headKey = (kind == "prof" and "popProfQuest") or (withSelf and "popClass") or "popChain"
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

-- v1.47 : INTEGRER une chaine de classe au guide de zone (au lieu du detour « chain »).
-- Les etapes de la chaine qui tombent sur une carte du guide sont glissees juste apres l'etape du guide
-- la plus proche (meme carte), sans jamais revenir avant l'etape precedente de la chaine (l'ordre
-- Prendre > Faire > Rendre reste vrai) ni avant l'ancre du guide (ce que tu as deja fait).
-- Les autres attendent le guide de leur zone (le guide est retisse a chaque SetGuide). Etapes marquees
-- woven = quete visee : elles ne servent jamais d'ancre et ne sont pas sautees par l'ancre (Core.lua).
local function wovenDist(a, b)
    local dx, dy = (a.x or 0) - (b.x or 0), (a.y or 0) - (b.y or 0)
    return math.sqrt(dx * dx + dy * dy)
end

function WeaveSteps(g, key)
    local base = g and g.steps
    if not (DB and DB.woven and next(DB.woven) and base) or key == "chain" or IS_DUNGEON[key] then return nil end
    -- ancre du guide sans les ajouts (borne basse : on n'insere rien dans ce que tu as deja fait)
    local saved = State.steps
    State.steps = base
    local okA, floor = pcall(FindAnchor)
    State.steps = saved
    floor = okA and floor or 0
    local have, maps = {}, {}
    for _, s in ipairs(base) do
        if Applies(s) then
            if s.m then maps[s.m] = true end
            if s.t == "accept" or s.t == "do" or s.t == "turnin" then
                for _, id in ipairs(Ids(s)) do have[s.t .. ":" .. id] = true end
            end
        end
    end
    local after, outside, any = {}, {}, false
    for q in pairs(DB.woven) do
        local list = ChainSteps(q, true)
        local pos = floor
        for _, cs in ipairs(list or {}) do
            if not have[cs.t .. ":" .. cs.id] then
                if cs.m and maps[cs.m] then
                    -- etape du guide la plus proche (meme carte) a partir de pos ; a distance presque egale
                    -- (meme camp), la premiere : on ne repousse pas la quete a un passage plus tardif
                    local best
                    for j = math.max(pos, 1), #base do
                        local b = base[j]
                        if b.m == cs.m and b.x and Applies(b) then
                            local d = wovenDist(b, cs)
                            if not best or d < best then best = d end
                        end
                    end
                    local at = pos
                    if best then
                        for j = math.max(pos, 1), #base do
                            local b = base[j]
                            if b.m == cs.m and b.x and Applies(b) and wovenDist(b, cs) <= best + 2 then at = j; break end
                        end
                    end
                    local row = {}
                    for k, v in pairs(cs) do row[k] = v end
                    row.woven = q
                    row.zone = base[at] and base[at].zone or nil
                    after[at] = after[at] or {}
                    table.insert(after[at], row)
                    pos = at
                    any = true
                elseif not Rendue(cs.id) then
                    outside[q] = outside[q] or { n = 0, maps = {} }
                    local o = outside[q]
                    o.n = o.n + 1
                    if cs.m then o.maps[cs.m] = true end
                end
            end
        end
    end
    if not any then return nil, outside end
    local out = {}
    for _, r in ipairs(after[0] or {}) do out[#out + 1] = r end
    for j, s in ipairs(base) do
        out[#out + 1] = s
        for _, r in ipairs(after[j] or {}) do out[#out + 1] = r end
    end
    return out, outside
end

-- Message : etapes d'une chaine integree qui se passent hors de ce guide
function WovenReport(outside)
    for q, o in pairs(outside or {}) do
        if o.n > 0 and EST[q] then
            local names = {}
            for m in pairs(o.maps) do
                local nm = MAPNAME[m]
                if not nm and C_Map and C_Map.GetMapInfo then
                    local okI, info = pcall(C_Map.GetMapInfo, m)
                    nm = okI and info and info.name or nil
                end
                if nm then names[#names + 1] = nm end
            end
            say(T("wovenOutside", EST[q].n, o.n, #names > 0 and table.concat(names, ", ") or "?"))
        end
    end
end

function Weave(q)
    if not (q and EST[q]) then return end
    if not ChainSteps(q, true) then say(T("chainNone", EST[q].n)); return end
    DB.woven = DB.woven or {}
    DB.woven[q] = true
    say(T("wovenStart", EST[q].n))
    local inLog = 0
    for _ in pairs(logById or {}) do inLog = inLog + 1 end
    if inLog >= 35 then say(T("wovenLogFull", inLog)) end
    -- depuis le detour « chain » : on revient au guide de zone, avec la chaine dedans
    local key = DB.guide
    if key == "chain" then
        key = DB.chainBack
        DB.chainBack, DB.chainQ, DB.chainSelf = nil, nil, nil
        Guides.chain = nil
    end
    if key and Guides[key] then SetGuide(key, true) end
end

function Unweave(q)
    if not (DB and DB.woven) then return end
    if q then DB.woven[q] = nil else wipe(DB.woven) end
    if q then say(T("wovenStop", EST[q] and EST[q].n or tostring(q))) else say(T("wovenStopAll")) end
    if DB.guide and Guides[DB.guide] then SetGuide(DB.guide, true) end
end

-- Chaine integree terminee (quete visee rendue) : on la retire, le guide se nettoie au prochain chargement
function WovenCleanup()
    if not (DB and DB.woven) then return end
    for q in pairs(DB.woven) do
        if Rendue(q) then
            DB.woven[q] = nil
            say(T("wovenDone", EST[q] and EST[q].n or tostring(q)))
        end
    end
end

-- v1.46 : nom du donjon dans la langue de l'addon (« en » de Data.lua, sinon « Scarlet Monastery: Graveyard »)
function DungeonName(d)
    if type(d) == "string" then d = IS_DUNGEON[d] end
    if not d then return "?" end
    if Lang and Lang() == "en" then return d.en or (d.name:gsub(" : ", ": ")) end
    return d.name
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

-- v1.42 : niveau ideal d'un donjon, tire du guide (quetes non optionnelles) : le plus haut entre le niveau
-- requis le plus eleve (toutes les quetes prenables) et le niveau median des quetes - 3 (XP complete sans
-- donjon trop dur), borne a la plage min-max. nil si le guide n'a aucune quete principale.
local idealCache = {}
function DungeonIdeal(key)
    if idealCache[key] ~= nil then return idealCache[key] or nil end
    local g, d = Guides[key], nil
    for _, x in ipairs(DUNGEONS) do if x.key == key then d = x end end
    local res = false
    if g and d then
        local reqMax, lvls = 0, {}
        for _, s in ipairs(g.steps or {}) do
            if s.t == "accept" and not s.optional and s.req then
                if s.req > reqMax then reqMax = s.req end
                if s.lvl then lvls[#lvls + 1] = s.lvl end
            end
        end
        if #lvls > 0 then
            table.sort(lvls)
            local v = math.max(reqMax, lvls[math.floor(#lvls / 2) + 1] - 3)
            res = math.min(d.max, math.max(d.min, v))
        end
    end
    idealCache[key] = res
    return res or nil
end

function CheckDungeons()
    if not DB or DB.noDungeonAsk or IS_DUNGEON[DB.guide] or not StaticPopup_Show or State.asking then return end
    local lvl = UnitLevel("player")
    -- les donjons "de chez toi" d'abord (ex. Shadowfang Keep pour un Undead)
    local HOME = { Scourge = "sfk", Undead = "sfk", Orc = "rfc", Troll = "rfc", Tauren = "wc" }
    local order = {}
    for _, d in ipairs(DUNGEONS) do
        if d.key == HOME[State.myRace] then table.insert(order, 1, d) else order[#order + 1] = d end
    end
    for _, d in ipairs(order) do
        local ans = DB.dAnswer[d.key]
        local later = ans == "later" and (DB.dLater[d.key] or 0) < lvl
        if Guides[d.key] and lvl >= d.min and lvl <= d.max and (ans == nil or later) and not DungeonDone(d.key) and DungeonOpen(d.key) then
            State.asking = d
            ns.Trace("popup WARPATH_DUNGEON"); Popup("WARPATH_DUNGEON", T("dAsk", lvl, DungeonName(d), d.min, d.max) .. ((DungeonAskLine and DungeonAskLine(d.key)) or DungeonReqText(d.key)))
            return
        end
    end
end

CheckDungeonsFn = CheckDungeons

-- Quetes de classe importantes (ClassQuests.lua) : la variante de ta race, si elle n'est pas deja faite
function ClassQuestList()
    local out, byName = {}, {}
    -- v1.47 : entre variantes d'une meme ligne, celle qui commence sur ton continent d'abord
    local myCont
    if C_Map and C_Map.GetBestMapForUnit then
        local okm, m = pcall(C_Map.GetBestMapForUnit, "player")
        if okm and m then local okc, c = pcall(Continent, m); myCont = okc and c or nil end
    end
    for _, r in ipairs((ns.ClassQuests or {})[State.myClass] or {}) do
        local pick, done, doneId, here = nil, false, nil, nil
        for _, id in ipairs(r[3]) do
            if EST[id] and QAvailable(id) then
                if Rendue(id) then done = true; doneId = doneId or id
                else
                    pick = pick or id
                    if myCont and not here then
                        local order = ChainFor(id, true)
                        local first = order and order[1] and EST[order[1]]
                        local okc, c = pcall(Continent, first and first.s and first.s[1])
                        if okc and c == myCont then here = id end
                    end
                end
            end
        end
        pick = here or pick
        if pick or done then
            local c = { lvl = r[1], lvl2 = r[4] or r[1], name = r[2], label = r[2], q = pick, done = done, endId = doneId or pick }
            out[#out + 1] = c
            byName[r[2]] = byName[r[2]] or {}
            table.insert(byName[r[2]], c)
        end
    end
    -- v1.47 : meme nom sur plusieurs lignes = quetes differentes (Path of Defense : Forged Steel dans les Barrens,
    -- Heirloom Weapon a Tirisfal) : on nomme la fin de chaque chaine, et une fois une version faite, les autres
    -- (alt) restent dans la liste mais ne sont plus proposees d'office. name reste la cle de DB.cqAsked.
    for nm, list in pairs(byName) do
        if #list > 1 then
            local anyDone = false
            for _, c in ipairs(list) do if c.done then anyDone = true end end
            for _, c in ipairs(list) do
                local e = c.endId and EST[c.endId]
                if e and e.n ~= nm then c.label = nm .. " › " .. e.n end
                c.alt = anyDone and not c.done or nil
            end
        end
    end
    return out
end

-- Propose une quete de classe quand tu atteins son niveau (une seule fois par quete)
function CheckClassQuests()
    if not DB or DB.noClassAsk or DB.guide == "chain" or IS_DUNGEON[DB.guide] or State.asking or not StaticPopup_Show then return end
    if PopupVisible() or (StaticPopup_Visible and (StaticPopup_Visible("WARPATH_CHAIN") or StaticPopup_Visible("WARPATH_DUNGEON"))) then return end
    DB.cqAsked = DB.cqAsked or {}
    local lvl = UnitLevel("player") or 1
    for _, c in ipairs(ClassQuestList()) do
        if c.q and not c.done and not c.alt and lvl >= c.lvl and lvl <= c.lvl + 8 and not DB.cqAsked[c.name] and logById[c.q] == nil then
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
        say(string.format("  %s%s - %s (%d-%d)%s%s|r", ok and "|cff9cc7a8" or "|cff8c7f62", d.key, DungeonName(d), d.min, d.max,
            ok and T("yourLevel") or "", DB.dAnswer[d.key] and (" [" .. LBL[DB.dAnswer[d.key]] .. "]") or "")
            .. (function() local l, t = DungeonLeft(d.key); return t > 0 and T("dQuests", t - l, t) or "" end)()
            .. (function() local n, now, need = DungeonReq(d.key); return (ok and need > 0) and T("dReqList", need) or "" end)())
    end
    say(T("dHelp"))
end

------------------------------------------------------------------
-- Actions
------------------------------------------------------------------
-- etape passee (ou validee a la main) qu'on peut remettre a faire
function Restorable(i)
    local s = State.steps and State.steps[i]
    if not s then return false end
    if s.t == "go" and IS_DUNGEON[DB.guide] then return false end
    if DB.seen[SeenKey(i)] and s.t ~= "level" then return true end
    for _, id in ipairs(Ids(s)) do if DB.ignored[id] then return true end end
    return false
end
function Restore(i)
    local s = State.steps[i]
    DB.seen[SeenKey(i)] = nil
    for _, id in ipairs(Ids(s)) do DB.ignored[id] = nil end
    say(T("restored", QName(s) or StepText(s):sub(1, 40)))
    if optCache then optCache.key = nil end
    State.peek = nil; State.focus = nil
    Advance()
    -- l'etape retablie s'affiche tout de suite (meme si un autre PNJ est un peu plus proche)
    if not State.doneCache[i] and i ~= State.current then State.focus = i end
    Refresh(true)
end

function Ignore()
    if not State.steps then return end
    -- mode donjon : le bouton sert a sortir du donjon (on passe aux remises de quetes)
    if not State.peek and not State.focus and DungeonLogActive and DungeonLogActive() then
        DB.dgOut = DB.dgOut or {}; DB.dgOut[DB.guide] = true
        Advance(); Refresh(true)
        return
    end
    -- etape "apprends tes sorts" : OK = on la passe pour ce niveau
    if not State.peek and not State.focus and TrainDetour and TrainDetour(State.steps[State.current]) then
        DB.trainSkip = DB.trainDue
        State.lastWP = nil; Refresh(true)
        return
    end
    -- journal quitte par erreur, toujours dans l'instance : on le fait revenir
    if not State.peek and not State.focus and DB.dgOut and DB.dgOut[DB.guide] and InDgInstance() then
        DB.dgOut[DB.guide] = nil
        Advance(); Refresh(true)
        return
    end
    local i = State.peek or State.focus or State.current
    local s = State.steps[i]
    if not s then return end
    if Restorable(i) then Restore(i); return end
    if s.t == "go" and IS_DUNGEON[DB.guide] then
        DB.dgIn = DB.dgIn or {}; DB.dgIn[DB.guide] = true
        State.peek = nil; State.focus = nil; Advance(); Refresh(true)
        return
    end
    State.focus = nil
    if s.id then
        local names = {}
        -- v1.41 : prise groupee dont une partie est deja dans ton journal : OK n'ignore que les quetes pas prises
        -- (avant, il ignorait tout, et les etapes Faire/Rendre des quetes prises disparaissaient aussi)
        local ids = Ids(s)
        if s.t == "accept" and #ids > 1 then
            local missing = {}
            for _, id in ipairs(ids) do
                if logById[id] == nil and not Rendue(id) and not DB.ignored[id] then missing[#missing + 1] = id end
            end
            if #missing > 0 and #missing < #ids then ids = missing end
        end
        for _, id in ipairs(ids) do
            DB.ignored[id] = true
            names[#names + 1] = tostring(id)
        end
        say(T("ignored", QName(s) or "?", table.concat(names, ", ")))
    else
        DB.seen[SeenKey(i)] = true
    end
    State.peek = nil
    Advance()
    Refresh(true)
end

function Peek(dir)
    if not State.steps then return end
    local n = #State.steps
    local i = State.peek or State.focus or State.current
    State.focus = nil
    repeat i = i + dir until i < 1 or i > n or Applies(State.steps[i])
    if i < 1 then i = (State.peek or State.current) end
    if i > n then i = math.min(State.peek or State.current, n) end
    State.peek = (i ~= State.current) and i or nil
    Refresh(true)
    if not State.peek then State.lastWP = nil; Refresh(true) end
end

------------------------------------------------------------------
-- Niveau de fin de zone atteint : on propose de passer a la suivante (une fois par zone),
-- en listant les quetes encore dans le journal : celles qui continuent dans la prochaine zone
-- (le guide les reprendra) et celles a finir ici avant de partir.
------------------------------------------------------------------
function CheckZoneLevel()
    if not DB or not State.steps or not State.G then return end
    local key = DB.guide
    if not key or key == "chain" or IS_DUNGEON[key] or State.current > #State.steps then return end
    local lvl = UnitLevel("player") or 1
    if lvl < (MAXLVL[key] or 99) then return end
    DB.zoneAsked = DB.zoneAsked or {}
    local asked = DB.zoneAsked[key]
    if asked and (asked == true or lvl < asked + 3) then return end   -- reposee une fois, 3 niveaux plus tard
    local c, nxt = MyChain(), nil
    if DB.nextGuide and Guides[DB.nextGuide] and DB.nextGuide ~= key then nxt = DB.nextGuide end
    if not nxt and c then for k = 1, #c - 1 do if c[k] == key then nxt = c[k + 1] end end end
    if not (nxt and Guides[nxt]) then return end
    DB.zoneAsked[key] = asked and true or lvl
    -- quetes du guide encore dans le journal
    local inNext = {}
    for _, s in ipairs(Guides[nxt].steps or {}) do
        if s.t == "do" or s.t == "turnin" then for _, id in ipairs(Ids(s)) do inNext[id] = true end end
    end
    local carry, finish, seen = {}, {}, {}
    for _, s in ipairs(State.steps) do
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
    local txt = T("zoneUp", lvl, Title(State.G), Title(Guides[nxt]))
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

-- retour a l'etape actuelle (apres avoir regarde d'autres etapes)
function BackToNow()
    State.peek = nil; State.focus = nil; State.lastWP = nil
    if optCache then optCache.key = nil end
    Advance(); Refresh(true)
end

-- clic sur le titre de la quete : l'ouvre dans le journal des quetes du jeu
function OpenStepQuest()
    local s = State.steps and State.steps[State.peek or State.focus or State.current]
    if not s then return end
    for _, q in ipairs(Ids(s)) do
        if logById[q] ~= nil then
            if QuestMapFrame_OpenToQuestDetails then pcall(QuestMapFrame_OpenToQuestDetails, q); return end
            if C_QuestLog and C_QuestLog.SetSelectedQuest then pcall(C_QuestLog.SetSelectedQuest, q) end
            if ToggleQuestLog then pcall(ToggleQuestLog) elseif OpenQuestLog then pcall(OpenQuestLog) end
            return
        end
    end
end
