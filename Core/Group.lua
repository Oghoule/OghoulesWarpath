-- Oghoule's Warpath : mode equipe, etape 1 (Group.lua, v1.53)
-- Groupe avec d'autres joueurs qui ont Warpath : chacun envoie au groupe (et seulement au groupe) son niveau,
-- son parcours, son guide, les quetes des guides deja rendues et les quetes de son journal. La fenetre du guide
-- montre une pastille par coequipier sur chaque etape (Skin.lua) : or = deja faite, vert = dans son journal,
-- sombre = a faire. Exception voulue au « tout reste local » (DECISIONS.md, mode equipe) ; case DB.teamShare.
-- Sans l'addon chez l'autre : seulement « dans son journal » (C_QuestLog.IsUnitOnQuest), si le jeu le permet.
-- Pour tester seul : /warpath equipe test (faux coequipier construit depuis ton etat, passe par les vrais messages).
--
-- Messages (prefixe OWTEAM1, champs separes par |, nombres en base 36) :
--   I|version|niveau|parcours|guide|q   debut d'un envoi complet : remet a zero ce qu'on sait du joueur ;
--                                        q = 1 : « envoie-moi aussi le tien » (apres un /reload)
--   D|a,b,c...    quetes rendues (1er nombre entier, les suivants = ecarts : messages courts et independants)
--   L|id.c,...    quetes du journal (c = 1 : objectifs finis)
--   +|id  rendue   A|id|c  prise / mise a jour   X|id  retiree   N|niveau   G|guide|parcours
local ADDON, ns = ...
local State = ns.State
local Core = ns.Mod.Core
local Skin = ns.Mod.Skin
local Team = ns.Mod.Team   -- v1.53 etape 2 : fenetres du mode equipe (UI/Team.lua)
local Flow = ns.Mod.Flow
local Est = ns.Mod.Est
local Route = ns.Mod.Route
local Near = ns.Mod.Near

-- noms propres a ce fichier
local PREFIX, MAXLEN, KEEP = "OWTEAM1", 240, 5
local DIG = "0123456789abcdefghijklmnopqrstuvwxyz"
local GEM = "|TInterface\\AddOns\\OghoulesWarpath\\Media\\Gem:10:10:0:0:64:64:0:64:0:64:%d:%d:%d|t"
local COLORS = { done = { 214, 184, 102 }, log = { 156, 199, 168 }, todo = { 70, 62, 48 } }
local peers = {}        -- nom -> { lvl, route, guide, ver, done = {id=true}, log = {id=bool}, t, fake }
local guideIds          -- liste triee des quetes presentes dans les guides (calculee une fois)
local lastLog, lastLvl, lastGuide, lastXP = nil, nil, nil, nil
local roster = {}       -- nom -> unite (party1..)
local diffPending, refreshPending = false, false
local lastFull = 0
local B36, Encode, Decode, MyName, Channel, Send, SendFull, OnMessage, OnRoster, Members, Marks, Report
local sess = nil        -- etape 2 : { peer, state = "ask"|"active", myYes, theirYes, refused, chooser, key, fake }
local asked = {}        -- nom -> true : deja invite pendant cette session de jeu
local teamDone = 0      -- quetes rendues pendant la soiree en equipe (bilan)
local OnSession, EndTeam

local function After(sec, fn)
    if C_Timer and C_Timer.After then C_Timer.After(sec, fn) else fn() end
end

function B36(n)
    n = math.floor(n)
    if n <= 0 then return "0" end
    local s = ""
    while n > 0 do
        local r = n % 36
        s = DIG:sub(r + 1, r + 1) .. s
        n = math.floor(n / 36)
    end
    return s
end

-- liste triee d'ID -> messages « D|... » independants (le 1er nombre de chaque message est entier)
function Encode(tag, ids)
    local out, parts, len, prev = {}, {}, 0, nil
    for _, id in ipairs(ids) do
        local piece = prev and B36(id - prev) or B36(id)
        if len + #piece + 1 > MAXLEN - #tag - 2 and #parts > 0 then
            out[#out + 1] = tag .. "|" .. table.concat(parts, ",")
            parts, len = {}, 0
            piece = B36(id)
        end
        parts[#parts + 1] = piece; len = len + #piece + 1
        prev = id
    end
    if #parts > 0 then out[#out + 1] = tag .. "|" .. table.concat(parts, ",") end
    return out
end

function Decode(payload)
    local ids, prev = {}, nil
    for piece in tostring(payload or ""):gmatch("[^,]+") do
        local v = tonumber(piece, 36)
        if v then
            local id = prev and (prev + v) or v
            ids[#ids + 1] = id; prev = id
        end
    end
    return ids
end

local function GuideIds()
    if guideIds then return guideIds end
    local seen, list = {}, {}
    for key, g in pairs(Core.Guides or {}) do
        if key ~= "chain" and type(g) == "table" and type(g.steps) == "table" then
            for _, s in ipairs(g.steps) do
                if s.id then
                    for _, id in ipairs(Core.Ids(s)) do
                        if type(id) == "number" and id > 0 and not seen[id] then seen[id] = true; list[#list + 1] = id end
                    end
                end
            end
        end
    end
    table.sort(list)
    guideIds = list
    return list
end

local function Short(name)
    if type(name) ~= "string" then return nil end
    if Ambiguate then local ok, s = pcall(Ambiguate, name, "none"); if ok and type(s) == "string" then return s end end
    return (name:gsub("%-.*$", ""))
end

function MyName()
    local n = UnitName and UnitName("player")
    return type(n) == "string" and n or "?"
end

local function ShareOn() return not (State.DB and State.DB.teamShare == false) end

function Channel()
    if not (IsInGroup and IsInGroup()) then return nil end
    local ok, inst = pcall(function() return IsInGroup(2) and not IsInGroup(1) end)
    if ok and inst then return "INSTANCE_CHAT" end
    if IsInRaid and IsInRaid() then return "RAID" end
    return "PARTY"
end

-- envoi espace (le jeu limite le debit des messages d'addon : environ 10 d'un coup, puis 1 par seconde)
function Send(msgs)
    local ch = Channel()
    if not ch or not ShareOn() or not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then return end
    for i, m in ipairs(msgs) do
        local delay = (i <= 8) and ((i - 1) * 0.2) or (1.4 + (i - 8) * 1.1)
        After(delay, function() pcall(C_ChatInfo.SendAddonMessage, PREFIX, m, ch) end)
    end
end

local function CopyLog()
    local t = {}
    for id, c in pairs(Core.logById or {}) do t[id] = c and true or false end
    return t
end

local function MyDone()
    local list = {}
    for _, id in ipairs(GuideIds()) do
        local ok, r = pcall(Core.Rendue, id)
        if ok and r then list[#list + 1] = id end
    end
    return list
end

local function LogMsgs(log)
    local ids = {}
    for id in pairs(log) do ids[#ids + 1] = id end
    table.sort(ids)
    local out, parts, len = {}, {}, 0
    for _, id in ipairs(ids) do
        local piece = B36(id) .. "." .. (log[id] and "1" or "0")
        if len + #piece + 1 > MAXLEN - 3 and #parts > 0 then out[#out + 1] = "L|" .. table.concat(parts, ","); parts, len = {}, 0 end
        parts[#parts + 1] = piece; len = len + #piece + 1
    end
    if #parts > 0 then out[#out + 1] = "L|" .. table.concat(parts, ",") end
    return out
end

-- envoi complet : en arrivant dans un groupe, apres un /reload, ou en reponse a une demande
function SendFull(ask)
    if not Channel() or not ShareOn() then return end
    lastFull = GetTime and GetTime() or 0
    lastLog = CopyLog()
    lastLvl = UnitLevel and UnitLevel("player") or 0
    lastGuide = (State.DB and State.DB.guide or "") .. "|" .. Core.Parcours()
    -- (etape 3) + XP dans le niveau et XP du niveau : niveau prevu en fin de soiree
    local xp, mx = UnitXP and UnitXP("player") or 0, UnitXPMax and UnitXPMax("player") or 0
    lastXP = xp
    local msgs = { table.concat({ "I", Core.VERSION or "?", B36(lastLvl), Core.Parcours(), tostring(State.DB and State.DB.guide or ""), ask and "1" or "0", B36(xp), B36(mx) }, "|") }
    for _, m in ipairs(Encode("D", MyDone())) do msgs[#msgs + 1] = m end
    for _, m in ipairs(LogMsgs(lastLog)) do msgs[#msgs + 1] = m end
    Send(msgs)
end

local function ScheduleRefresh()
    if refreshPending then return end
    refreshPending = true
    After(0.5, function() refreshPending = false; if Skin.Refresh then pcall(Skin.Refresh) end end)
end

local function Peer(name, fake)
    local p = peers[name]
    if not p then
        p = { done = {}, log = {}, lvl = 0, fake = fake or nil }
        peers[name] = p
        -- memoire du coequipier (pour preparer la prochaine soiree) ; jamais le faux coequipier de test
        if not fake and State.DB then
            State.DB.team = State.DB.team or {}
            State.DB.team[name] = p
            local names = {}
            for n in pairs(State.DB.team) do names[#names + 1] = n end
            if #names > KEEP then
                table.sort(names, function(a, b) return (State.DB.team[a].t or 0) < (State.DB.team[b].t or 0) end)
                for k = 1, #names - KEEP do if names[k] ~= name then State.DB.team[names[k]] = nil end end
            end
        end
    end
    p.t = time and time() or 0
    return p
end

function OnMessage(msg, sender, fake)
    if type(msg) ~= "string" then return end
    local name = Short(sender)
    if not name or (name == MyName() and not fake) then return end
    local tag, rest = msg:match("^(.)|(.*)$")
    if not tag then return end
    local p = Peer(name, fake)
    if tag == "I" then
        local f = {}
        for v in (rest .. "|"):gmatch("([^|]*)|") do f[#f + 1] = v end
        local ver, lvl, route, guide, ask = f[1], f[2], f[3], f[4], f[5]
        p.ver, p.lvl, p.route, p.guide = ver, tonumber(lvl or "", 36) or 0, route, guide
        p.xp, p.xpmax = tonumber(f[6] or "", 36), tonumber(f[7] or "", 36)
        p.done, p.log = {}, {}
        local now = GetTime and GetTime() or 0
        if ask == "1" and not fake and now - lastFull > 10 then After(1 + math.random() * 2, function() SendFull(false) end) end
        OnSession("I", name, nil, fake)
    elseif tag == "P" or tag == "R" or tag == "C" or tag == "S" or tag == "Q" or tag == "M" then
        -- etape 2 : invitation et soiree en equipe (le dernier champ = joueur vise)
        local a, target = rest:match("^([^|]*)|?(.*)$")
        if target == "" or target == MyName() or fake then OnSession(tag, name, a, fake) end
        return
    elseif tag == "D" then
        for _, id in ipairs(Decode(rest)) do p.done[id] = true end
    elseif tag == "L" then
        for piece in rest:gmatch("[^,]+") do
            local id, c = piece:match("^(%w+)%.(%d)$")
            id = id and tonumber(id, 36)
            if id then p.log[id] = (c == "1") end
        end
    elseif tag == "+" then
        local id = tonumber(rest, 36); if id then p.done[id] = true; p.log[id] = nil end
    elseif tag == "A" then
        local id, c = rest:match("^(%w+)|(%d)$")
        id = id and tonumber(id, 36); if id then p.log[id] = (c == "1") end
    elseif tag == "X" then
        local id = tonumber(rest, 36); if id then p.log[id] = nil end
    elseif tag == "N" then
        local l, x, m = rest:match("^(%w+)|?(%w*)|?(%w*)$")
        p.lvl = tonumber(l or "", 36) or p.lvl
        if x and x ~= "" then p.xp, p.xpmax = tonumber(x, 36), tonumber(m or "", 36) end
    elseif tag == "G" then
        local guide, route = rest:match("^([^|]*)|?(.*)$")
        p.guide, p.route = guide, route
    end
    ScheduleRefresh()
end

-- changements locaux : un seul envoi des differences, 1,5 s apres le dernier evenement
local function SendDiff()
    diffPending = false
    if not lastLog or not Channel() or not ShareOn() then return end
    local msgs, cur = {}, CopyLog()
    for id, c in pairs(cur) do
        if lastLog[id] == nil or lastLog[id] ~= c then msgs[#msgs + 1] = "A|" .. B36(id) .. "|" .. (c and "1" or "0") end
    end
    for id in pairs(lastLog) do
        if cur[id] == nil then
            local ok, r = pcall(Core.Rendue, id)
            msgs[#msgs + 1] = ((ok and r) and "+|" or "X|") .. B36(id)
        end
    end
    lastLog = cur
    local lvl = UnitLevel and UnitLevel("player") or 0
    local xp, mx = UnitXP and UnitXP("player") or 0, UnitXPMax and UnitXPMax("player") or 0
    -- niveau, ou XP qui a bouge de plus de 5 % du niveau (etape 3 : niveaux prevus)
    if lvl ~= lastLvl or math.abs(xp - (lastXP or 0)) > mx * 0.05 then
        lastLvl, lastXP = lvl, xp
        msgs[#msgs + 1] = "N|" .. B36(lvl) .. "|" .. B36(xp) .. "|" .. B36(mx)
    end
    local g = (State.DB and State.DB.guide or "") .. "|" .. Core.Parcours()
    if g ~= lastGuide then lastGuide = g; msgs[#msgs + 1] = "G|" .. g end
    if #msgs > 12 then SendFull(false) else Send(msgs) end
end

local function OnLocalChange()
    if diffPending or not lastLog then return end
    diffPending = true
    After(1.5, SendDiff)
end

-- quete rendue sans etre passee par le journal connu (remise immediate) : envoyee tout de suite
local function OnTurnIn(id)
    if type(id) == "number" and lastLog and lastLog[id] == nil then Send({ "+|" .. B36(id) }) end
    if sess and sess.state == "active" then teamDone = teamDone + 1 end
    OnLocalChange()
end

-- composition du groupe : un nouveau membre -> envoi complet (il en fait autant de son cote)
function OnRoster(login)
    local now, fresh = {}, false
    local n = (GetNumGroupMembers and GetNumGroupMembers()) or 0
    if n > 1 then
        local raid = IsInRaid and IsInRaid()
        for k = 1, raid and n or (n - 1) do
            local unit = (raid and "raid" or "party") .. k
            local nm, realm = UnitName and UnitName(unit)
            if type(nm) == "string" and nm ~= "" and nm ~= UNKNOWNOBJECT then
                local full = (realm and realm ~= "") and (nm .. "-" .. realm) or nm
                local s = Short(full)
                if s ~= MyName() then
                    now[s] = unit
                    if not roster[s] then fresh = true end
                end
            end
        end
    end
    roster = now
    -- etape 2 : le coequipier a quitte le groupe -> fin de la soiree en equipe (ou de l'invitation)
    if sess and not sess.fake and not now[sess.peer] then
        if sess.state == "active" then EndTeam("teamLeft") else sess = nil; pcall(Team.HideInvite) end
    end
    -- apres un /reload : la soiree reprend si le coequipier est encore la
    if login and not sess and State.DB and type(State.DB.teamSess) == "table" then
        local ts = State.DB.teamSess
        if ts.peer and now[ts.peer] then
            sess = { peer = ts.peer, state = "active", key = ts.key, chooser = ts.chooser, plan = ts.plan, planMin = ts.planMin, idx = ts.idx,
                     t0 = GetTime and GetTime() or 0 }
            asked[ts.peer] = true
        else State.DB.teamSess, State.DB.teamBack = nil, nil end
    end
    if (fresh or login) and next(now) then After(1 + math.random() * 2, function() SendFull(login and true or false) end) end
    if not next(now) then lastLog = nil end
    ScheduleRefresh()
end

-- coequipiers a montrer : membres du groupe (avec ou sans l'addon), puis le faux coequipier de test
function Members()
    local list = {}
    for name, unit in pairs(roster) do list[#list + 1] = { name = name, unit = unit, peer = peers[name] } end
    table.sort(list, function(a, b) return a.name < b.name end)
    for name, p in pairs(peers) do if p.fake then list[#list + 1] = { name = name, peer = p } end end
    while #list > 4 do table.remove(list) end
    return list
end

local function StatusFor(m, ids)
    local p = m.peer
    if p and (p.ver or p.fake) then
        local all, inlog = true, false
        for _, id in ipairs(ids) do
            if not p.done[id] then all = false end
            if p.log[id] ~= nil then inlog = true end
        end
        if all then return "done" end
        return inlog and "log" or "todo"
    end
    if m.unit and C_QuestLog and C_QuestLog.IsUnitOnQuest then
        for _, id in ipairs(ids) do
            local ok, on = pcall(C_QuestLog.IsUnitOnQuest, m.unit, id)
            if ok and on then return "log" end
        end
    end
    return "todo"
end

-- pastilles d'une etape (chaine vide sans coequipier, ou pour une etape sans quete)
function Marks(s)
    if not s or not s.id or (s.t ~= "accept" and s.t ~= "do" and s.t ~= "turnin") then return "" end
    local list = Members()
    if #list == 0 then return "" end
    local ids = {}
    for _, id in ipairs(Core.Ids(s)) do if type(id) == "number" then ids[#ids + 1] = id end end
    if #ids == 0 then return "" end
    local out = {}
    for _, m in ipairs(list) do
        local c = COLORS[StatusFor(m, ids)]
        out[#out + 1] = string.format(GEM, c[1], c[2], c[3])
    end
    return table.concat(out, "")
end

-- noms des coequipiers dans l'ordre des pastilles (infobulles)
local function Names()
    local t = {}
    for _, m in ipairs(Members()) do t[#t + 1] = m.name end
    return t
end

-- faux coequipier : ton etat, modifie, passe par les vrais messages (encodage + decodage)
local function Test(off)
    local name = Core.T("teamTestName")
    -- (etape 2) la soiree ou l'invitation du faux coequipier s'arrete avec lui
    if sess and sess.fake then
        if sess.state == "active" then EndTeam("teamEnd") else sess = nil; pcall(Team.HideInvite); pcall(Team.HideChoice) end
    end
    for n, p in pairs(peers) do if p.fake then peers[n] = nil end end
    if off then Core.say(Core.T("teamTestOff")); ScheduleRefresh(); return end
    asked[name] = nil   -- le faux coequipier invite a chaque test (fenetre, reponses automatiques, choix)
    local done = {}
    for _, id in ipairs(MyDone()) do if id % 3 ~= 0 then done[#done + 1] = id end end
    local log, k = {}, 0
    for i = State.current or 1, #(State.steps or {}) do
        local s = State.steps[i]
        if s and s.id and (s.t == "accept" or s.t == "do" or s.t == "turnin") then
            k = k + 1
            if k % 2 == 0 then for _, id in ipairs(Core.Ids(s)) do if type(id) == "number" then log[id] = (k % 4 == 0) end end end
            if k >= 8 then break end
        end
    end
    local lvl = math.max(1, (UnitLevel and UnitLevel("player") or 2) - 1)
    local msgs = { table.concat({ "I", Core.VERSION or "?", B36(lvl), Core.Parcours(), tostring(State.DB and State.DB.guide or ""), "0" }, "|") }
    for _, m in ipairs(Encode("D", done)) do msgs[#msgs + 1] = m end
    for _, m in ipairs(LogMsgs(log)) do msgs[#msgs + 1] = m end
    for _, m in ipairs(msgs) do OnMessage(m, name, true) end
    Core.say(Core.T("teamTestOn", name, #msgs))
end

function Report(arg)
    arg = arg or ""
    if arg == "off" then State.DB.teamShare = false
    elseif arg == "on" then State.DB.teamShare = nil; SendFull(true)
    elseif arg == "test" then Test(false); Report(""); return
    elseif arg == "test off" then Test(true); return
    elseif arg == "suite" or arg == "next" then pcall(ns.Mod.Group.GoNext); return end
    Core.say(Core.T("teamShare", ShareOn() and Core.T("shareOn") or Core.T("shareOff")))
    local list = Members()
    if #list == 0 then Core.say(Core.T("teamNone")); return end
    for _, m in ipairs(list) do
        local p = m.peer
        if p and (p.ver or p.fake) then
            local nd, nl = 0, 0
            for _ in pairs(p.done) do nd = nd + 1 end
            for _ in pairs(p.log) do nl = nl + 1 end
            local g = Core.Guides and Core.Guides[p.guide or ""]
            local route = Core.T(p.route == "warband" and "teamWarband" or "teamScout")
            Core.say(Core.T("teamLine", m.name, p.lvl or 0, route, g and Core.Title(g) or "?", nd, nl)
                .. (p.fake and ("  |cff8c7f62" .. Core.T("teamFake") .. "|r") or ""))
        else
            Core.say(Core.T("teamNoAddon", m.name))
        end
    end
    Core.say(Core.T("teamLegend", string.format(GEM, 214, 184, 102), string.format(GEM, 156, 199, 168), string.format(GEM, 70, 62, 48)))
end

------------------------------------------------------------------
-- Etape 2 : soiree en equipe (invitation, choix de l'activite, consignes)
-- Les deux joueurs voient la meme fenetre ; il faut deux oui. Boutons fixes : gauche = oui (Jouer ensemble ->
-- Accepter), droite = non (Chacun son guide -> Refuser / Annuler). Celui qui propose en premier choisit ;
-- deux propositions croisees (P|0 des deux cotes) : le chef de groupe, sinon l'ordre alphabetique.
-- Le calcul des etapes reste propre a chaque joueur : la soiree met tout le monde dans la meme zone et ajoute
-- des consignes (StepHints) et la liste des quetes ou aider (HelpBlock).
------------------------------------------------------------------
local guideQ = {}       -- cle de guide -> liste des quetes (etapes « Rendre », sans classe ni race)

local function TeamOn() return sess and sess.state == "active" end

local function GuideQuests(key)
    if guideQ[key] then return guideQ[key] end
    local g, seen, list = Core.Guides and Core.Guides[key], {}, {}
    if g and type(g.steps) == "table" then
        for _, s in ipairs(g.steps) do
            if s.t == "turnin" and s.id and not s.class and not s.race and not s.races then
                for _, id in ipairs(Core.Ids(s)) do
                    if type(id) == "number" and not seen[id] then seen[id] = true; list[#list + 1] = id end
                end
            end
        end
    end
    guideQ[key] = list
    return list
end

-- la quete vaut-elle le coup pour ce joueur (p = nil : toi) ?
local function Need(p, id, lvl)
    local e = Est.EST and Est.EST[id]
    if not e then return false end
    if p then if p.done[id] then return false end
    else local ok, r = pcall(Core.Rendue, id); if ok and r then return false end end
    if (e.r or 0) > lvl + 2 then return false end
    local l = e.l or e.r or lvl
    return l >= lvl - 7 and l <= lvl + 4
end

-- l'equipe : toi + le coequipier de la soiree (ou de l'invitation)
local function Crew()
    local crew = { { name = MyName(), lvl = UnitLevel and UnitLevel("player") or 1 } }
    if sess and peers[sess.peer] then crew[2] = { name = sess.peer, peer = peers[sess.peer], lvl = peers[sess.peer].lvl or 1 } end
    return crew
end

-- activites classees : quetes utiles a chacun, en commun, et score (XP de tous + XP du moins servi)
local function Activities()
    local crew, out = Crew(), {}
    local keys = {}
    for _, k in ipairs(Core.D and Core.D.MAIN_ORDER or {}) do if Core.Guides[k] then keys[#keys + 1] = k end end
    for k in pairs(Core.IS_DUNGEON or {}) do if Core.Guides[k] then keys[#keys + 1] = k end end
    for _, key in ipairs(keys) do
        local counts, xps, common, need, ids = {}, {}, 0, {}, {}
        for _, id in ipairs(GuideQuests(key)) do
            local all, any = true, false
            for c, m in ipairs(crew) do
                if Need(m.peer, id, m.lvl) then
                    counts[c] = (counts[c] or 0) + 1
                    xps[c] = (xps[c] or 0) + ((Est.EST[id] and Est.EST[id].x) or 0)
                    need[c] = need[c] or {}; need[c][#need[c] + 1] = id
                    any = true
                else all = false end
            end
            if all then common = common + 1 end
            if any then ids[#ids + 1] = id end
        end
        local sum, low = 0, nil
        for c = 1, #crew do sum = sum + (xps[c] or 0); low = math.min(low or math.huge, xps[c] or 0) end
        if sum > 0 then
            out[#out + 1] = { key = key, counts = counts, xps = xps, common = common, score = sum + (low or 0) * #crew, need = need, ids = ids,
                              dungeon = Core.IS_DUNGEON[key] and true or false }
        end
    end
    table.sort(out, function(a, b) return a.score > b.score end)
    return out, crew
end

-- au plus 3 propositions : meilleure zone, meilleur donjon, puis rattrapage (ecart de 3 niveaux) ou 2e zone
local function Proposals()
    local acts, crew = Activities()
    local list, used = {}, {}
    local function add(a, kind) if a and not used[a.key] then used[a.key] = true; a.kind = kind; list[#list + 1] = a end end
    for _, a in ipairs(acts) do if not a.dungeon then add(a, "zone"); break end end
    for _, a in ipairs(acts) do if a.dungeon and a.common > 0 then add(a, "dungeon"); break end end
    if #crew > 1 and math.abs((crew[1].lvl or 0) - (crew[2].lvl or 0)) >= 3 then
        local lowC = (crew[1].lvl < crew[2].lvl) and 1 or 2
        local best
        for _, a in ipairs(acts) do
            if not a.dungeon and not used[a.key] and (not best or (a.xps[lowC] or 0) > (best.xps[lowC] or 0)) then best = a end
        end
        if best then best.low = crew[lowC].name; add(best, "catchup") end
    end
    for _, a in ipairs(acts) do if #list >= 3 then break end; if not a.dungeon then add(a, "zone") end end
    return list, crew
end

local function GuideName(key)
    local g = Core.Guides and Core.Guides[key]
    return g and Core.Title(g) or tostring(key)
end

-- textes d'une proposition pour l'ecran de choix
local function ProposalText(a, crew)
    local l1 = GuideName(a.key)
    if a.kind == "catchup" then l1 = Core.T("teamCatchup", l1) end
    local parts = {}
    for c, m in ipairs(crew) do parts[#parts + 1] = (c == 1 and Core.T("teamYou") or m.name) .. " " .. (a.counts[c] or 0) end
    local l2 = Core.T("teamCommonN", a.common) .. "  ·  " .. table.concat(parts, "  ·  ")
    if a.kind == "catchup" and a.low then l2 = Core.T("teamCatchupSub", a.low, a.counts[a.low == crew[1].name and 1 or 2] or 0) end
    return l1, l2
end

local function SendTo(tag, arg)
    local msg = tag .. "|" .. (arg or "") .. "|" .. (sess and sess.peer or "")
    if sess and sess.fake then
        -- faux coequipier : il repond tout seul (pour tester sans 2e compte)
        local name = sess.peer
        if tag == "P" and arg == "0" then After(1.5, function() OnMessage("P|1|", name, true) end)
        elseif tag == "P" and arg == "1" then
            After(2, function()
                local list = Proposals()
                if sess and sess.state == "active" and list[1] then OnMessage("S|" .. list[1].key .. "|", name, true) end
            end)
        end
        return
    end
    Send({ msg })
end

-- vue de la fenetre d'invitation : titre, 2 lignes, libelles et etat des 2 boutons (toujours a la meme place)
local function InviteView()
    local o, p = sess.peer, peers[sess.peer] or {}
    local v = { peer = o, title = Core.T("teamUses", o), l1 = "", l2 = "", L = Core.T("teamPlay"), R = Core.T("teamSolo"), lOn = true, rOn = true }
    if sess.state == "active" then
        v.title, v.l1, v.lOn, v.rOn = Core.T("teamModeTitle"), Core.T("teamWaitChoice", sess.chooser or o), false, false
        v.L, v.R = sess.theirYes and Core.T("teamAccept") or Core.T("teamPlay"), sess.theirYes and Core.T("teamRefuse") or Core.T("teamCancel")
    elseif sess.refused then
        v.l1 = (sess.refused == MyName()) and Core.T("teamKeep") or Core.T("teamRefused", o)
        v.lOn, v.rOn = false, false
        if sess.theirYes then v.L, v.R = Core.T("teamAccept"), Core.T("teamRefuse") end
    elseif sess.myYes then
        v.l1, v.l2 = "|cff9cc7a8" .. Core.T("teamSent") .. "|r", Core.T("teamWaiting", o)
        v.lOn, v.R = false, Core.T("teamCancel")
    elseif sess.theirYes then
        v.title, v.l1 = Core.T("teamWants", o), Core.T("teamChooses", o)
        v.L, v.R = Core.T("teamAccept"), Core.T("teamRefuse")
    end
    if v.l1 == "" or (not sess.myYes and not sess.refused and sess.state ~= "active") then
        local route = Core.T(p.route == "warband" and "teamWarband" or "teamScout")
        local best = sess.best
        local info = Core.T("teamInfo", p.lvl or 0, route)
        if v.l1 == "" then v.l1 = info else v.l2 = info end
        if best and v.l2 == "" then v.l2 = Core.T("teamBest", GuideName(best.key), best.common) end
    end
    return v
end

local function Redraw()
    if not sess then pcall(Team.HideInvite); return end
    if sess.state == "active" and sess.chooser == MyName() and not sess.key then return end
    if sess.state == "active" and sess.key then pcall(Team.HideInvite); return end
    pcall(Team.Invite, InviteView())
end

local function SaveSess()
    if not (sess and State.DB) then return end
    State.DB.teamSess = { peer = sess.peer, key = sess.key, chooser = sess.chooser, plan = sess.plan, planMin = sess.planMin, idx = sess.idx }
end

local function ApplyActivity(key)
    if not (key and Core.Guides[key] and State.DB) then return end
    State.DB.teamBack = State.DB.teamBack or { guide = State.DB.guide, manual = State.DB.manual }
    if Core.IS_DUNGEON[key] then Flow.StartDungeon(key)
    else State.DB.manual = true; Flow.SetGuide(key) end
    sess.key = key
    -- (etape 3) position dans le plan de la soiree ; chrono de l'activite
    if sess.plan then for k, pk in ipairs(sess.plan) do if pk == key then sess.idx = k end end end
    sess.t0, sess.nextAsked = GetTime and GetTime() or 0, nil
    SaveSess()
    pcall(Team.HideInvite); pcall(Team.HideChoice)
    Core.say(Core.T("teamStart", sess.peer, GuideName(key)))
    ScheduleRefresh()
end

------------------------------------------------------------------
-- Etape 3 : planificateur de soiree (« on a 2 h ») et niveaux prevus
------------------------------------------------------------------
-- XP pour passer au niveau suivant (table classique 1-59) ; mise a l'echelle par l'XP reelle du niveau
local XPT = { 400, 900, 1400, 2100, 2800, 3600, 4500, 5400, 6500, 7600, 8800, 10100, 11400, 12900, 14400, 16000, 17700, 19400,
    21300, 23200, 25200, 27300, 29400, 31700, 34000, 36400, 38900, 41400, 44300, 47400, 50800, 54500, 58600, 62800, 67100, 71600,
    76100, 80800, 85700, 90700, 95800, 101000, 106300, 111800, 117500, 123200, 129100, 135100, 141200, 147500, 153900, 160400,
    167100, 173900, 180800, 187900, 195000, 202300, 209800 }
local DURS = { 60, 120, 180 }

local function LevelAfter(lvl, xp, mx, gain)
    local L, need = lvl or 1, (mx and mx > 0) and mx or XPT[lvl or 1] or 200000
    local scale = need / (XPT[L] or need)
    local cur = (xp or 0) + (gain or 0)
    while L < 60 and cur >= need do cur = cur - need; L = L + 1; need = math.floor((XPT[L] or need) * scale) end
    if L >= 60 then return 60 end
    return L + cur / need
end

local function FmtLvl(v)
    local s = string.format("%.1f", v)
    return (Core.Lang() == "fr") and (s:gsub("%.", ",")) or s
end

local function FmtMin(m)
    m = math.floor(m + 0.5)
    if m < 60 then return Core.T("teamMin", m) end
    return Core.T("teamHMin", math.floor(m / 60), string.format("%02d", m % 60))
end

-- duree (minutes) et XP de chacun pour une activite
local function Cost(a, crew)
    local mins, xp = 0, {}
    if a.dungeon then
        local run = (Core.D.DUNGEON_RUN or {})[a.key] or 60
        mins = run + 13   -- (comme Est.DungeonStepEstimate : un passage + la recherche de groupe)
        for c, m in ipairs(crew) do
            local q = 0
            for _, id in ipairs(a.need[c] or {}) do q = q + ((Est.EST[id] and Est.EST[id].x) or 0) * 2.7 end
            xp[c] = q + math.floor(0.6 * run) * Est.MobXP(m.lvl, m.lvl, 0)
        end
    else
        local ok, r = pcall(Est.Estimate, a.ids, false)
        local secs, mxp = (ok and r and r.secs or 0), (ok and r and r.mxp or 0)
        mins = (secs + 75 * #a.ids) / 60   -- + trajets (75 s par quete, a la louche)
        for c, m in ipairs(crew) do
            local q = 0
            for _, id in ipairs(a.need[c] or {}) do q = q + Est.QuestXP(Est.EST[id], m.lvl) end
            xp[c] = q + mxp
        end
    end
    return math.max(5, mins), xp
end

-- plan glouton : l'activite qui rapporte le plus par minute a l'equipe, jusqu'a la duree choisie (3 au plus)
local function Plan(minutes)
    local acts, crew = Activities()
    local cands = {}
    for k = 1, math.min(#acts, 10) do
        local a = acts[k]
        a.mins, a.gain = Cost(a, crew)
        local sum, low = 0, math.huge
        for c = 1, #crew do sum = sum + (a.gain[c] or 0); low = math.min(low, a.gain[c] or 0) end
        a.rate = (sum + low * #crew) / a.mins
        cands[#cands + 1] = a
    end
    local plan, left, total, used = {}, minutes, {}, {}
    while left > 10 and #plan < 3 do
        local best
        -- un donjon ne se fait pas a moitie : seulement s'il tient dans le temps qui reste (une zone peut etre raccourcie)
        for _, a in ipairs(cands) do
            if not used[a.key] and (not a.dungeon or a.mins <= left * 1.1) and (not best or a.rate > best.rate) then best = a end
        end
        if not best then break end
        used[best.key] = true
        local f = math.min(1, left / best.mins)
        plan[#plan + 1] = { key = best.key, mins = best.mins * f, partial = f < 1 }
        for c = 1, #crew do total[c] = (total[c] or 0) + (best.gain[c] or 0) * f end
        left = left - best.mins * f
    end
    local ends = {}
    for c, m in ipairs(crew) do
        local xp, mx
        if c == 1 then xp, mx = UnitXP and UnitXP("player") or 0, UnitXPMax and UnitXPMax("player") or 0
        else xp, mx = m.peer and m.peer.xp, m.peer and m.peer.xpmax end
        ends[c] = LevelAfter(m.lvl, xp, mx, total[c] or 0)
    end
    return plan, ends, crew
end

-- ecran de choix : duree, plan de la soiree, ou une seule activite
local function ShowChoice(dur)
    sess.dur = dur or sess.dur or 120
    local plan, ends, crew = Plan(sess.dur)
    sess.pending = plan
    local steps = {}
    for _, p in ipairs(plan) do steps[#steps + 1] = GuideName(p.key) .. " (" .. FmtMin(p.mins) .. ")" end
    local lv = {}
    for c, m in ipairs(crew) do lv[#lv + 1] = (c == 1 and Core.T("teamYou") or m.name) .. " " .. Core.T("teamLvlShort", FmtLvl(ends[c])) end
    local view = { dur = sess.dur, durs = DURS, opts = {} }
    if #plan > 0 then
        view.planL1 = table.concat(steps, "  >  ")
        view.planL2 = Core.T("teamEndLvl", table.concat(lv, "  ·  "))
    end
    local list = Proposals()
    for _, a in ipairs(list) do local l1, l2 = ProposalText(a, crew); view.opts[#view.opts + 1] = { key = a.key, l1 = l1, l2 = l2 } end
    pcall(Team.HideInvite)
    pcall(Team.Choice, view)
end

local function Pick(kind, value)
    if not TeamOn() or sess.chooser ~= MyName() then return end
    if kind == "dur" then ShowChoice(value); return end
    local key
    if kind == "plan" and sess.pending and sess.pending[1] then
        sess.plan, sess.planMin = {}, {}
        for k, p in ipairs(sess.pending) do sess.plan[k] = p.key; sess.planMin[k] = p.mins end
        SendTo("M", table.concat(sess.plan, ","))
        key = sess.plan[1]
    else
        sess.plan, sess.planMin = nil, nil
        key = (kind == "one") and value or (State.DB and State.DB.guide)
    end
    SendTo("S", key); ApplyActivity(key)
end

-- activite suivante du plan
local function GoNext()
    if not (TeamOn() and sess.plan and sess.idx and sess.plan[sess.idx + 1]) then return end
    local key = sess.plan[sess.idx + 1]
    SendTo("S", key); ApplyActivity(key)
end

-- toutes les 30 s (celui qui a choisi) : activite finie ou temps depasse -> on propose la suivante
local lastTick = 0
local function Tick()
    local now = GetTime and GetTime() or 0
    if now - lastTick < 30 then return end
    lastTick = now
    if not (TeamOn() and sess.chooser == MyName() and sess.plan and sess.idx and sess.plan[sess.idx + 1]) then return end
    if sess.nextAsked == sess.idx then return end
    local key, mins = sess.plan[sess.idx], (sess.planMin and sess.planMin[sess.idx]) or 60
    local over = sess.t0 and (now - sess.t0) >= mins * 60 * 1.1
    local left = Core.IS_DUNGEON[key] and State.DB.guide ~= key and sess.t0 and (now - sess.t0) > 300   -- sorti du donjon
    local ended = State.steps and State.current and State.current > #State.steps
    if over or left or ended then
        sess.nextAsked = sess.idx
        local nk = sess.plan[sess.idx + 1]
        pcall(Skin.Toast, Core.T("teamNextHead"), Core.T("teamNext", GuideName(nk)), GoNext)
        Core.say(Core.T("teamNextChat", GuideName(nk)))
    end
end

local function Activate(chooser)
    sess.state, sess.chooser = "active", chooser
    teamDone = 0
    if chooser == MyName() then
        local acts = Activities()
        if #acts == 0 then
            pcall(Team.HideInvite)
            Core.say(Core.T("teamNoActivity")); sess.key = State.DB.guide; SaveSess(); ScheduleRefresh(); return
        end
        ShowChoice(120)
    else
        Redraw()
    end
end

-- egalite : le chef de groupe choisit, sinon le premier nom dans l'ordre alphabetique
local function TieChooser(o)
    if UnitIsGroupLeader and UnitIsGroupLeader("player") then return MyName() end
    if roster[o] and UnitIsGroupLeader and UnitIsGroupLeader(roster[o]) then return o end
    return (MyName() < o) and MyName() or o
end

local function CloseLater(sec)
    local s = sess
    After(sec, function() if sess == s and sess.state ~= "active" then sess = nil; pcall(Team.HideInvite) end end)
end

-- clics dans la fenetre d'invitation (gauche = oui, droite = non / annuler)
local function Click(yes)
    if not sess or sess.state == "active" or sess.refused then return end
    if yes then
        if sess.myYes then return end
        if sess.theirYes then SendTo("P", "1"); Activate(sess.peer); return end
        sess.myYes = true; SendTo("P", "0")
    elseif sess.myYes then
        sess.myYes = false; SendTo("C", "")
    else
        sess.refused = MyName(); SendTo("R", ""); CloseLater(2.5)
    end
    Redraw()
end

function OnSession(tag, name, a, fake)
    if tag == "I" then
        -- un coequipier avec Warpath arrive : invitation (une fois par joueur et par session de jeu)
        if asked[name] or sess or not ShareOn() or (State.DB and State.DB.teamAsk == false) then return end
        if not fake and not roster[name] then return end
        asked[name] = true
        After(fake and 0.2 or 2, function()
            if sess then return end
            sess = { peer = name, state = "ask", fake = fake or nil }
            local list = Proposals(); sess.best = list[1]
            Redraw()
            -- faux coequipier : s'il ne se passe rien, il propose lui-meme (pour voir Accepter / Refuser)
            if fake then After(8, function() if sess and sess.fake and sess.state == "ask" and not sess.myYes and not sess.refused then OnMessage("P|0|", name, true) end end) end
            -- personne ne clique : la fenetre se ferme seule
            After(45, function() if sess and sess.peer == name and sess.state == "ask" and not sess.myYes and not sess.theirYes then sess = nil; pcall(Team.HideInvite) end end)
        end)
        return
    end
    if tag == "Q" then
        if sess and sess.peer == name and sess.state == "active" then EndTeam("teamPeerQuit") end
        return
    end
    if tag == "S" then
        if sess and sess.peer == name and sess.state == "active" then ApplyActivity(a) end
        return
    end
    if tag == "M" then
        -- (etape 3) plan de la soiree choisi par l'autre : pour le bandeau (1/2...)
        if sess and sess.peer == name and sess.state == "active" then
            sess.plan, sess.planMin = {}, nil
            for k in tostring(a or ""):gmatch("[^,]+") do sess.plan[#sess.plan + 1] = k end
        end
        return
    end
    if not sess then
        -- proposition recue sans fenetre ouverte (invitation fermee) : on la rouvre
        if tag ~= "P" or not ShareOn() then return end
        sess = { peer = name, state = "ask", fake = fake or nil }; asked[name] = true
    end
    if sess.peer ~= name or sess.state == "active" then return end
    if tag == "P" then
        if sess.myYes then Activate((a == "1") and MyName() or TieChooser(name)); return end
        sess.theirYes = true
    elseif tag == "R" then
        sess.refused = name; CloseLater(3)
    elseif tag == "C" then
        sess.theirYes = false
    end
    Redraw()
end

function EndTeam(reason)
    if not sess then return end
    local peer = sess.peer
    sess = nil
    pcall(Team.HideInvite); pcall(Team.HideChoice)
    local back = State.DB and State.DB.teamBack
    if State.DB then State.DB.teamBack, State.DB.teamSess = nil, nil end
    if back then
        if Core.IS_DUNGEON[State.DB.guide] and not Core.IS_DUNGEON[back.guide or ""] then State.DB.main = nil end
        State.DB.manual = back.manual
        local k = back.manual and back.guide or Flow.AutoPick()
        if k and Core.Guides[k] then Flow.SetGuide(k) end
    end
    Core.say(Core.T(reason or "teamEnd", peer) .. " " .. Core.T("teamSummary", teamDone))
    ScheduleRefresh()
end

local function Quit()
    if not TeamOn() then return end
    SendTo("Q", "")
    EndTeam("teamEnd")
end

-- bandeau : nom du coequipier et distance (meme carte seulement)
local function BannerInfo()
    if not TeamOn() then return nil end
    local info = { name = sess.peer }
    if sess.plan and #sess.plan > 1 then info.plan = (sess.idx or 1) .. "/" .. #sess.plan end
    local unit = roster[sess.peer]
    if unit and C_Map and C_Map.GetBestMapForUnit then
        pcall(function()
            local m = C_Map.GetBestMapForUnit("player")
            local a, b = ns.MapAPI.PlayerPos(m, "player"), ns.MapAPI.PlayerPos(m, unit)
            if a and b and a.x and b.x then
                local p, q = Route.WP(m, a.x * 100, a.y * 100), Route.WP(m, b.x * 100, b.y * 100)
                if p and q then info.dist = math.floor(Route.Dist(p[1], p[2], q[1], q[2]) + 0.5) end
            end
        end)
    end
    return info
end

local function QTitle(id)
    local e = Est.EST and Est.EST[id]
    local ok, t = pcall(Core.QName, { id = id, quest = e and e.n or tostring(id) })
    return ok and t or (e and e.n) or tostring(id)
end

-- consignes d'equipe pour l'etape affichee (nil sans soiree en cours)
local function StepHints(s)
    if not TeamOn() or not s or not s.id then return nil end
    local p, o = peers[sess.peer], sess.peer
    if not p then return nil end
    local ids = {}
    for _, id in ipairs(Core.Ids(s)) do if type(id) == "number" then ids[#ids + 1] = id end end
    if #ids == 0 then return nil end
    local done, inlog, fin = true, false, true
    for _, id in ipairs(ids) do
        if not p.done[id] then done = false end
        if p.log[id] ~= nil then inlog = true; if not p.log[id] then fin = false end end
    end
    local key
    if s.t == "accept" then key = done and "teamHAcceptDone" or (inlog and "teamHAcceptHas" or "teamHAcceptBoth")
    elseif s.t == "do" then key = done and "teamHDoDone" or (inlog and "teamHDoBoth" or "teamHDoShare")
    elseif s.t == "turnin" then key = (inlog and not fin) and "teamHWait" or (inlog and "teamHTurninBoth" or nil) end
    if not key then return nil end
    return "|cffd6b866" .. Core.T("teamHLbl") .. "|r  " .. Core.T(key, o)
end

-- quetes du coequipier dans cette zone qu'il n'a pas finies et que tu ne fais pas (deja faite ou pas prise)
local function HelpBlock()
    if not TeamOn() then return nil end
    local p = peers[sess.peer]
    if not p or not State.DB then return nil end
    local inGuide = {}
    for _, id in ipairs(GuideQuests(State.DB.guide or "")) do inGuide[id] = true end
    local lines = {}
    for id, fin in pairs(p.log) do
        if not fin and inGuide[id] and Core.logById[id] == nil then
            local ok, r = pcall(Core.Rendue, id)
            lines[#lines + 1] = QTitle(id) .. "  |cff8c7f62" .. Core.T((ok and r) and "teamHelpDone" or "teamHelpNot") .. "|r"
            if #lines >= 4 then break end
        end
    end
    if #lines == 0 then return nil end
    table.sort(lines)
    return Near.ListBlock(Core.T("teamHelpHdr", sess.peer), lines, "9cc7a8")
end

local function Init()
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX) end
    -- coequipiers deja connus (memoire) : repris tels quels, montres seulement s'ils sont dans le groupe
    if State.DB and type(State.DB.team) == "table" then
        for name, p in pairs(State.DB.team) do
            if type(p) == "table" then p.done = p.done or {}; p.log = p.log or {}; p.fake = nil; peers[name] = p end
        end
    end
    pcall(Team.Start)
    After(5, function() OnRoster(true) end)
end

-- v1.53 : ce que ce fichier offre aux autres (ns.Mod.Group)
do
    local M = ns.Mod.Group
    M.PREFIX = PREFIX
    M.Init, M.OnMessage, M.OnRoster, M.OnLocalChange, M.OnTurnIn = Init, OnMessage, OnRoster, OnLocalChange, OnTurnIn
    M.Marks, M.Names, M.Report, M.Members = Marks, Names, Report, Members
    M.Encode, M.Decode, M.B36 = Encode, Decode, B36   -- (tests)
    -- etape 2 : soiree en equipe
    M.Click, M.Quit, M.BannerInfo, M.StepHints, M.HelpBlock, M.TeamOn = Click, Quit, BannerInfo, StepHints, HelpBlock, TeamOn
    M.Proposals = Proposals   -- (tests)
    -- etape 3 : planificateur
    M.Pick, M.Tick, M.GoNext, M.Plan, M.LevelAfter = Pick, Tick, GoNext, Plan, LevelAfter
end
