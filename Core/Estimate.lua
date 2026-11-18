-- Oghoule's Warpath : moteur (Estimate.lua) - voir Core.lua
local ADDON, ns = ...
local _ENV = ns.CoreEnv
if setfenv then setfenv(1, _ENV) end

------------------------------------------------------------------
-- Estimations : XP (quetes + monstres) et temps de jeu
------------------------------------------------------------------
EST = ns.Est or {}
RACEBIT = { Human = 1, Orc = 2, Dwarf = 4, NightElf = 8, Scourge = 16, Undead = 16, Tauren = 32, Gnome = 64, Troll = 128 }
CLASSBIT = { WARRIOR = 1, PALADIN = 2, HUNTER = 4, ROGUE = 8, PRIEST = 16, SHAMAN = 64, MAGE = 128, WARLOCK = 256, DRUID = 1024 }
DROP_PRIOR = 0.35     -- taux suppose tant qu'on n'a rien mesure (prudent)
DROP_WEIGHT = 6       -- poids de cette supposition, en "monstres" : les vrais drops la remplacent vite
OBJ_SECS = 15         -- un objet au sol, deplacement compris
RUN = 7               -- metres par seconde a pied
function HasBit(mask, b) return b and math.floor(mask / b) % 2 == 1 end

function QAvailable(q)
    local e = EST[q]
    if not e then return false end
    if e.rc and e.rc > 0 then
        if RACEBIT[myRace] then
            if not HasBit(e.rc, RACEBIT[myRace]) and not (e.rc >= 2 ^ 32 and e.rc % 2 ^ 32 == 0 and HasBit(e.rc, 2 ^ 33)) then return false end
        elseif e.rc >= 2 ^ 32 and not HasBit(e.rc, 2 ^ 33) then
            return false                                   -- nouvelle race (Skyborne) : quete reservee a l'Alliance
        end
    end
    if e.cl and e.cl > 0 and CLASSBIT[myClass] and not HasBit(e.cl, CLASSBIT[myClass]) then return false end
    return true
end

function ZeroDiff(p)
    if p < 8 then return 5 elseif p < 10 then return 6 elseif p < 12 then return 7 elseif p < 16 then return 8
    elseif p < 20 then return 9 elseif p < 30 then return 11 elseif p < 40 then return 12 elseif p < 45 then return 13
    elseif p < 50 then return 14 elseif p < 55 then return 15 elseif p < 60 then return 16 end
    return 17
end

-- XP d'un monstre (formule classique), elite x2
function MobXP(m, p, elite)
    if not m or m <= 0 then m = p end
    local base = p * 5 + 45
    local xp
    if m >= p then xp = base * (1 + 0.05 * math.min(m - p, 4))
    else
        local zd = ZeroDiff(p)
        if p - m >= zd then return 0 end
        xp = base * (1 - (p - m) / zd)
    end
    return math.floor(xp * (elite == 1 and 2 or 1))
end

function QuestXP(e, p)
    local diff = p - (e.l or p)
    local f = 1
    if diff >= 10 then f = 0.1 elseif diff == 9 then f = 0.2 elseif diff == 8 then f = 0.4
    elseif diff == 7 then f = 0.6 elseif diff == 6 then f = 0.8 end
    return math.floor((e.x or 0) * f)
end

-- Secondes par monstre (temps de recuperation compris) : mesure si possible, sinon selon classe et talents
BASE_KILL = { HUNTER = 24, WARLOCK = 26, MAGE = 28, ROGUE = 30, DRUID = 30, SHAMAN = 30, PALADIN = 34, PRIEST = 32, WARRIOR = 34 }
SPEC = { PRIEST = { 1, 1.05, 0.85 }, PALADIN = { 1.1, 1.05, 0.95 }, DRUID = { 1.05, 0.9, 1.1 },
               SHAMAN = { 0.95, 0.9, 1.05 }, WARRIOR = { 0.95, 0.95, 1.15 }, ROGUE = { 1, 0.95, 1 },
               HUNTER = { 0.95, 1, 1 }, MAGE = { 1, 0.95, 1 }, WARLOCK = { 0.95, 1, 1 } }
-- specialisation : 1, 2 ou 3 (ordre des arbres de talents : sacre/sacre/ombre pour un pretre...), nil si inconnue
-- talents en "traits" (C_ClassTalents / C_Traits) : points depenses par arbre ; renvoie l'arbre le plus rempli
function TraitTrees()
    if not (C_ClassTalents and C_ClassTalents.GetActiveConfigID and C_Traits and C_Traits.GetConfigInfo) then return nil end
    local okC, cfg = pcall(C_ClassTalents.GetActiveConfigID)
    if not okC or not cfg then return nil, "config=nil" end
    local okI, info = pcall(C_Traits.GetConfigInfo, cfg)
    if not okI or type(info) ~= "table" or type(info.treeIDs) ~= "table" then return nil, "config=" .. tostring(cfg) .. " arbres=nil" end
    local out = {}
    for t, tree in ipairs(info.treeIDs) do
        local spent, pts = 0, {}
        local okN, nodes = pcall(C_Traits.GetTreeNodes, tree)
        if okN and type(nodes) == "table" then
            for _, node in ipairs(nodes) do
                local okD, ni = pcall(C_Traits.GetNodeInfo, cfg, node)
                if okD and type(ni) == "table" then
                    local r = type(ni.currentRank) == "number" and ni.currentRank or 0
                    spent = spent + r
                    if type(ni.posX) == "number" then pts[#pts + 1] = { x = ni.posX, r = r } end
                end
            end
        end
        out[t] = { id = tree, n = (okN and type(nodes) == "table") and #nodes or 0, spent = spent, pts = pts }
    end
    -- Forever : les 3 arbres classiques sont dans un seul arbre de traits, cote a cote.
    -- On les separe par position horizontale (les 2 plus grands ecarts entre colonnes).
    if #out == 1 and #out[1].pts >= 9 then
        local xs, seen = {}, {}
        for _, p in ipairs(out[1].pts) do if not seen[p.x] then seen[p.x] = true; xs[#xs + 1] = p.x end end
        table.sort(xs)
        if #xs >= 3 then
            local gaps = {}
            for k = 1, #xs - 1 do gaps[#gaps + 1] = { g = xs[k + 1] - xs[k], at = (xs[k] + xs[k + 1]) / 2 } end
            table.sort(gaps, function(a, b) return a.g > b.g end)
            local c1, c2 = math.min(gaps[1].at, gaps[2].at), math.max(gaps[1].at, gaps[2].at)
            local split = { { id = out[1].id, n = 0, spent = 0, part = 1 }, { id = out[1].id, n = 0, spent = 0, part = 2 }, { id = out[1].id, n = 0, spent = 0, part = 3 } }
            for _, p in ipairs(out[1].pts) do
                local k = (p.x < c1) and 1 or (p.x < c2) and 2 or 3
                split[k].n = split[k].n + 1; split[k].spent = split[k].spent + p.r
            end
            return split, "config=" .. tostring(cfg) .. " (1 arbre coupe en 3)"
        end
    end
    return out, "config=" .. tostring(cfg)
end
function MySpec()
    -- (C_SpecializationInfo.GetSpecialization renvoie 1 sur Forever meme pour un paladin rétribution : ignore)
    do  -- plusieurs arbres de traits : celui ou tu as mis le plus de points (5 au moins)
        local trees = TraitTrees()
        if trees and #trees >= 2 then
            local best, bp = nil, 0
            for t, tr in ipairs(trees) do if tr.spent > bp then best, bp = t, tr.spent end end
            if best and bp >= 5 then return best end
        end
    end
    if GetSpecialization then
        local ok, i = pcall(GetSpecialization)
        if ok and type(i) == "number" and i >= 1 and i <= 4 then return i end
    end
    if GetTalentTabInfo then
        local bestTab, bestPts = nil, 0
        for tab = 1, 3 do
            -- classique : nom, icone, points ; Wrath et suivants : id, nom, description, icone, points
            local ok, a, b, c, d, e = pcall(GetTalentTabInfo, tab)
            local pts
            if type(a) == "string" then pts = c
            elseif type(a) == "number" and type(b) == "string" then pts = e end
            if type(pts) ~= "number" then pts = nil end
            if ok and pts and pts > bestPts then bestTab, bestPts = tab, pts end
        end
        if bestTab and bestPts >= 5 then return bestTab end
    end
    return nil
end
function KillTime()
    local sp = MySpec()
    if sp then DB._spec = sp end
    -- mesure dans ta specialisation actuelle (un pretre sacre et un pretre ombre ne tuent pas au meme rythme)
    local m = sp and DB.ktS and DB.ktS[sp]
    if m and (m[2] or 0) >= 8 then return m[1], true end
    -- ancienne mesure sans specialisation connue : valable seulement si on ne connait pas la specialisation
    if not sp and DB.ktN and DB.ktN >= 8 and DB.kt then return DB.kt, true end
    local t = BASE_KILL[myClass] or 30
    if sp and SPEC[myClass] and SPEC[myClass][sp] then t = t * SPEC[myClass][sp] end
    local lvl = UnitLevel("player") or 1
    return t * (1 + math.max(0, lvl - 20) * 0.004), false
end

-- Taux de drop d'un objet de quete : ce que tu as vraiment obtenu (tous tes personnages), lisse par une
-- petite supposition de depart. Un objet sur un seul monstre nomme (une tete de chef) tombe toujours.
function DropRate(d)
    if d[5] == 1 then return 1, "unique" end
    local st = WarpathDropDB and WarpathDropDB[d[1]]
    local k, n = st and st.k or 0, st and st.n or 0
    -- mesures des autres joueurs de l'addon (groupe / guilde) : comptent pour moitie
    local pk, pn = ns.PeerDrops(d[1])
    local K, N = k + pk * 0.5, n + pn * 0.5
    -- point de depart : le taux de Questie pour cet objet (Wowhead / serveur / corrections), sinon 35 %
    local qd = ns.QuestieDrop and ns.QuestieDrop[d[1]]
    local prior, weight = qd or DROP_PRIOR, qd and 12 or DROP_WEIGHT
    local rate = (N + prior * weight) / (K + weight)
    local how = (K >= 10) and "measured" or (qd and "questie" or "assumed")
    return math.max(0.01, math.min(1, rate)), how, math.floor(K + 0.5), (K > 0) and (N / K) or nil
end

-- Estime une liste de quetes faites dans l'ordre (trajets compris, a partir de ta position).
function Estimate(list, withTravel)
    local p = UnitLevel("player") or 1
    local kt = KillTime()
    local r = { qxp = 0, mxp = 0, secs = 0, kills = 0, dropKills = 0, travel = 0, drops = {} }
    local pos = withTravel and PlayerWP() or nil
    local known = (DB.useFlights ~= false) and KnownFlights() or {}
    local function go(t)
        if not (pos and t) then return end
        local w = WP(t[1], t[2], t[3])
        if not w then return end
        local c = TravelCost(pos, w, known)
        if c then r.travel = r.travel + c / RUN end
        pos = w
    end
    for _, q in ipairs(list) do
        local e = EST[q]
        if e then
            r.qxp = r.qxp + QuestXP(e, p)
            if logById[q] == nil then go(e.s) end
            go(e.h)
            for _, k in ipairs(e.k or {}) do
                local n = k[2] or 1
                r.kills = r.kills + n
                r.mxp = r.mxp + n * MobXP(k[3], p, k[4])
                r.secs = r.secs + n * kt * (k[4] == 1 and 3 or 1)
            end
            for _, d in ipairs(e.d or {}) do
                local need = d[2] or 1
                if #d >= 7 then
                    local rate, how, k, seen = DropRate(d)
                    local n = math.ceil(need / rate)
                    r.kills = r.kills + n; r.dropKills = r.dropKills + n
                    r.mxp = r.mxp + n * MobXP(d[3], p, d[4])
                    r.secs = r.secs + n * kt * (d[4] == 1 and 3 or 1)
                    r.drops[#r.drops + 1] = { name = d[6], rate = rate, how = how, k = k, seen = seen, mobs = #d >= 7 }
                else
                    r.secs = r.secs + need * OBJ_SECS
                end
            end
            r.secs = r.secs + (e.o or 0) * OBJ_SECS
            go(e.e)
        end
    end
    r.secs = r.secs + r.travel
    r.xp = r.qxp + r.mxp
    r.perHour = r.secs > 0 and math.floor(r.xp * 3600 / r.secs) or 0
    return r
end

function FormatNum(n)
    local s = tostring(math.floor(n + 0.5))
    local out = s:reverse():gsub("(%d%d%d)", "%1 "):reverse()
    return (out:gsub("^ ", ""))
end

------------------------------------------------------------------
-- Quetes bloquees par un prerequis : chaine a faire pour les debloquer
------------------------------------------------------------------
function ChainFor(q, withSelf)
    local order, seen, bad = {}, {}, nil
    local function visit(id)
        if seen[id] or bad then return end
        seen[id] = true
        if Rendue(id) then return end
        if not QAvailable(id) then bad = id; return end
        local e = EST[id]
        for _, pq in ipairs(e.p or {}) do visit(pq) end
        if e.p1 then
            local ok = false
            for _, pq in ipairs(e.p1) do if Rendue(pq) or logById[pq] ~= nil then ok = true end end
            if not ok then
                local pick
                for _, pq in ipairs(e.p1) do if QAvailable(pq) then pick = pq; break end end
                if pick then visit(pick) else bad = id end
            end
        end
        if id ~= q or withSelf then order[#order + 1] = id end
    end
    visit(q)
    if bad then return nil, bad end
    return order
end

function BuildChainGuide(q, withSelf)
    local order = ChainFor(q, withSelf)
    local target = EST[q]
    if not order or #order == 0 or not target then return nil end
    local list = {}
    local function at(row, p) if p then row.m, row.x, row.y = p[1], p[2], p[3] end; return row end
    for _, id in ipairs(order) do
        local e = EST[id]
        if logById[id] == nil then
            list[#list + 1] = at({ t = "accept", id = id, quest = e.n, lvl = e.l,
                text = e.it and "Cette quete commence sur un objet (butin) : utilise-le." or "Prends la quete.",
                en = e.it and "This quest starts from an item (loot): use it." or "Pick up the quest." }, e.s)
        end
        if e.k or e.d or e.o then
            list[#list + 1] = at({ t = "do", id = id, quest = e.n, lvl = e.l,
                text = "Objectif : " .. (e.t or ""), en = "Objective: " .. (e.t or "") }, e.h)
        end
        list[#list + 1] = at({ t = "turnin", id = id, quest = e.n, lvl = e.l, text = "Rends la quete.", en = "Turn in the quest." }, e.e)
    end
    if withSelf then return { title = "Classe : " .. target.n, title_en = "Class: " .. target.n, races = { myRace }, steps = list, side = true } end
    return { title = "Chaine : " .. target.n, title_en = "Chain: " .. target.n, races = { myRace }, steps = list, side = true }
end

function LockCandidates()
    local out = {}
    if not steps then return out end
    for i = math.max(1, current - 25), #steps do
        local s = steps[i]
        if blockedBy[i] and s.t == "accept" and not DB.lockHide[s.id] and type(s.id) == "number" and ChainFor(s.id) then
            out[#out + 1] = i
        end
    end
    return out
end

-- Rythme reel : temps entre deux monstres tues (combat et recuperation compris)
lastKill = nil
KILL_WORD = (COMBATLOG_XPGAIN_FIRSTPERSON or "%s dies, you gain %d experience."):match("%%s(.-),") or " dies"
function OnXPGain(msg)
    if type(msg) ~= "string" or not msg:find(KILL_WORD, 1, true) then return end
    local now = GetTime and GetTime() or 0
    if lastKill and now - lastKill < 150 then
        local sample = math.max(8, math.min(120, now - lastKill))
        DB.kt = DB.kt and (DB.kt * 0.9 + sample * 0.1) or sample
        DB.ktN = (DB.ktN or 0) + 1
        local sp = MySpec()
        if sp then
            DB.ktS = DB.ktS or {}
            local m = DB.ktS[sp]
            DB.ktS[sp] = m and { m[1] * 0.9 + sample * 0.1, m[2] + 1 } or { sample, 1 }
            DB._spec = sp
        end
    end
    lastKill = now
end

------------------------------------------------------------------
-- Zones ajoutees par Forever : on retrouve leur numero de carte par leur nom (une fois, a la connexion)
------------------------------------------------------------------
function ResolveNewMaps()
    local NEW = D.NEWMAPS or {}
    local want, found = {}, {}
    local function norm(n) return (n:lower():gsub("^the ", ""):gsub("^les? ", ""):gsub("^la ", ""):gsub("[%s'%-]", "")) end
    for neg, names in pairs(NEW) do for _, n in ipairs(names) do want[norm(n)] = neg end end
    -- cartes deja trouvees lors d'une session precedente (au cas ou le nom change ou est traduit)
    local memo = WarpathDropDB and WarpathDropDB._maps
    if memo and C_Map and C_Map.GetMapInfo then
        for neg, id in pairs(memo) do if NEW[neg] and C_Map.GetMapInfo(id) then found[neg] = id end end
    end
    if C_Map and C_Map.GetMapInfo then
        for pass = 1, 2 do
            for id = 1, 3000 do
                local info = C_Map.GetMapInfo(id)
                if info and info.name then
                    local neg = want[norm(info.name)]
                    if neg and not found[neg] and ((pass == 1 and info.mapType == 3) or pass == 2) then found[neg] = id end
                end
            end
        end
    end
    if WarpathDropDB then
        WarpathDropDB._maps = WarpathDropDB._maps or {}
        for neg, id in pairs(found) do WarpathDropDB._maps[neg] = id end
    end
    local function fixRow(t)
        if t and type(t.m) == "number" and t.m < 0 then
            t.m = found[t.m]
            if not t.m then t.x, t.y = nil, nil end
        end
    end
    local function fixPos(p)
        if p and type(p[1]) == "number" and p[1] < 0 then
            if found[p[1]] then return { found[p[1]], p[2], p[3] } end
            return nil
        end
        return p
    end
    for _, g in pairs(Guides) do for _, st in ipairs(g.steps or {}) do fixRow(st) end end
    for _, e in pairs(EST) do e.s, e.e, e.h = fixPos(e.s), fixPos(e.e), fixPos(e.h) end
    for _, n in ipairs(FLIGHTS) do fixRow(n) end
    for _, n in ipairs(ns.Inns or {}) do fixRow(n) end
    for _, n in ipairs(ns.Trainers or {}) do fixRow(n) end
    for k, p in pairs(ns.Vendors or {}) do ns.Vendors[k] = fixPos(p) end
    for _, g in ipairs(GATES) do fixRow(g) end
    for k = #TRANSPORTS, 1, -1 do
        local tr = TRANSPORTS[k]
        tr.from, tr.to = fixPos(tr.from), fixPos(tr.to)
        if not tr.from or not tr.to then table.remove(TRANSPORTS, k) end
    end
    wipe(wpCache)
    return found
end

MAPNAME = { [1411] = "Durotar", [1420] = "Tirisfal Glades", [1434] = "Stranglethorn Vale", [1413] = "The Barrens" }

