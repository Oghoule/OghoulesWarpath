-- Oghoule's Warpath : moteur (Near.lua) - moins d'allers-retours
-- 1) Groupe de prises/remises consecutives : on va d'abord au PNJ le plus proche.
-- 2) En passant : un PNJ a moins de 25 m dont une etape proche a besoin passe en premier.
-- 3) Explications : quetes a prendre plus tard / jamais prises pres de toi, quetes en attente d'un niveau.
local ADDON, ns = ...
local _ENV = ns.CoreEnv
if setfenv then setfenv(1, _ENV) end

-- titre en couleur + une ligne par element, en retrait avec un losange
-- icone de l'addon en ligne, teintee (r, g, b de 0 a 255)
function InlineIcon(name, size, rgb)
    rgb = rgb or { 205, 187, 142 }
    return string.format("|TInterface\\AddOns\\%s\\Media\\%s:%d:%d:0:0:32:32:0:32:0:32:%d:%d:%d|t", ADDON, name, size, size, rgb[1], rgb[2], rgb[3])
end
function ListBlock(title, items, col, icon)
    local out = { "|cff" .. (col or "cdbb8e") .. title .. "|r" }
    for _, it in ipairs(items) do
        out[#out + 1] = "   " .. (icon or ("|TInterface\\AddOns\\" .. ADDON .. "\\Media\\Gem:8|t")) .. " |cffe9dfc8" .. it .. "|r"
    end
    return table.concat(out, "\n")
end
baseCurrent = nil   -- etape courante dans l'ordre du guide (avant le choix par proximite)
nearKind = nil      -- "near" (le plus proche du groupe) ou "pass" (en passant), pour l'affichage
local PASS_R, LOOK, CLUSTER, HUB_R = 25, 15, 12, 80
local lastPick

-- etape "prendre" ou "rendre" faisable tout de suite
function Actionable(j)
    local s = steps and steps[j]
    if not s or doneCache[j] or not Applies(s) or not s.m then return false end
    if s.t == "turnin" then
        local any = false
        for _, id in ipairs(Ids(s)) do
            if logById[id] == true then any = true
            elseif not Rendue(id) then return false end
        end
        return any
    elseif s.t == "accept" then
        if (s.req or 0) > (UnitLevel("player") or 1) then return false end
        for _, p in ipairs(s.preg or {}) do if not Rendue(p) then return false end end
        if s.pre then
            local ok = false
            for _, p in ipairs(s.pre) do if Rendue(p) then ok = true end end
            if not ok then return false end
        end
        for _, id in ipairs(Ids(s)) do
            if logById[id] ~= nil or Rendue(id) or DB.ignored[id] then return false end
        end
        return true
    end
    return false
end

local function distTo(me, s)
    if not (s and s.m and s.x) then return nil end
    local g = WP(s.m, s.x, s.y)
    if not g or g[3] ~= me[3] then return nil end
    return Dist(me[1], me[2], g[1], g[2])
end

-- renvoie l'etape a faire en premier (ou nil = garder l'ordre du guide)
function NearPick(cur)
    nearKind = nil
    if not (steps and cur and steps[cur]) or IS_DUNGEON[DB.guide] or DB.near == false then return nil end
    local me = PlayerWP(); if not me then return nil end
    local s0 = steps[cur]
    local best, bd, kind
    if s0.t == "accept" or s0.t == "turnin" then
        local j = cur
        while j <= #steps and j <= cur + CLUSTER do
            local s = steps[j]
            if Applies(s) and not doneCache[j] then
                if s.t ~= "accept" and s.t ~= "turnin" then break end
                -- seulement dans le meme camp que l'etape du guide (pas de saut d'un camp a l'autre)
                local same = j == cur
                if not same and s0.m and s.m then
                    local a, b = WP(s0.m, s0.x, s0.y), WP(s.m, s.x, s.y)
                    same = a and b and a[3] == b[3] and Dist(a[1], a[2], b[1], b[2]) < HUB_R
                end
                if same and (j == cur or Actionable(j)) then
                    local dj = distTo(me, s)
                    if dj and (not bd or dj < bd) then best, bd, kind = j, dj, "near" end
                end
            end
            j = j + 1
        end
        -- on ne change pas d'avis pour quelques metres
        if lastPick and lastPick ~= best and steps[lastPick] and not doneCache[lastPick] and (lastPick == cur or Actionable(lastPick)) then
            local dl = distTo(me, steps[lastPick])
            if dl and bd and dl < bd + 15 then best, bd = lastPick, dl end
        end
    end
    local j, k, barrier = cur + 1, 0, false
    while j <= #steps do
        local s = steps[j]
        if Applies(s) and not doneCache[j] then
            k = k + 1
            if s.t == "go" or s.t == "level" then barrier = true end
            -- au-dela de 15 etapes (ou d'un changement de zone), seules les remises comptent : rendre plus tot ne coute rien
            if (barrier or k > LOOK) and s.t ~= "turnin" then s = nil end
        end
        if s and Applies(s) and not doneCache[j] then
            local esc = s.t == "accept" and ((s.text or "") .. (s.en or "")):lower():find("escort", 1, true)
            if (s.t == "accept" or s.t == "turnin") and not esc and Actionable(j) then
                local dj = distTo(me, s)
                if dj and dj < PASS_R and (not bd or dj < bd) then best, bd, kind = j, dj, "pass" end
            end
        end
        j = j + 1
    end
    lastPick = best
    if best and best ~= cur then nearKind = kind; return best end
    return nil
end

-- appele en marchant (toutes les 2 s) : change l'etape affichee si un PNJ plus proche devient pertinent
local lastTick = 0
local lastPointKey = ""
function NearTick()
    local t = GetTime and GetTime() or 0
    if t - lastTick < 2 then return end
    lastTick = t
    if not steps or peek or focus or not baseCurrent or computingOther then return end
    if DungeonLogActive and DungeonLogActive() then return end
    pcall(CaveTrack)
    local sp
    local ok, pk = pcall(function()
        sp = StepPoint(steps[current])
        return (sp and (sp.kind .. sp.m .. ":" .. sp.x .. ":" .. sp.y) or "") .. (TrainDetour(steps[current]) and "T" or "")
    end)
    if ok and pk ~= lastPointKey then
        lastPointKey = pk
        -- v1.46 : seul le point a bouge (meme etape, meme genre) : la fleche se deplace sans tout reconstruire
        local okL, light = false, false
        if pk:sub(-1) ~= "T" and RetargetLight then okL, light = pcall(RetargetLight, sp) end
        if not (okL and light) then lastWP = nil; Refresh(true) end
        return
    end
    local j = NearPick(baseCurrent) or baseCurrent
    if j ~= current and steps[j] then
        current = j; DB.step[DB.guide] = current
        lastWP = nil; Refresh(true)
    end
end

-- quetes d'une etape "faire" pas encore prises faute de niveau : on le dit
function LevelWaitLines(s)
    local out = {}
    if not (s and s.t == "do") then return out end
    local lvl = UnitLevel("player") or 1
    for _, q in ipairs(Ids(s)) do
        if logById[q] == nil and not Rendue(q) and not DB.ignored[q] then
            for _, a in ipairs(steps) do
                if a.t == "accept" and (a.req or 0) > lvl and Applies(a) then
                    local has = false
                    for _, id in ipairs(Ids(a)) do if id == q then has = true end end
                    if has then out[#out + 1] = T("lvlWaitItem", QuestTitle(q) or a.quest or ("#" .. q), a.req); break end
                end
            end
        end
    end
    return out
end

-- pres d'un camp : quetes que le guide prendra plus tard, ou ne prend pas (pas rentables)
function HubNotes(i)
    local s = steps and steps[i]
    if not s or (s.t ~= "accept" and s.t ~= "turnin") or IS_DUNGEON[DB.guide] then return nil end
    local me = PlayerWP(); if not me then return nil end
    local here = distTo(me, s)
    if not here or here > 40 then return nil end
    local later, skip, seen = {}, {}, {}
    for j = i + 1, #steps do
        local a = steps[j]
        if a.t == "accept" and Applies(a) and not doneCache[j] and j ~= current
            and not (Actionable(j) and j <= (baseCurrent or i) + LOOK) then
            local d = distTo(me, a)
            if d and d < 30 then
                for _, q in ipairs(Ids(a)) do
                    if not seen[q] and logById[q] == nil and not Rendue(q) then
                        seen[q] = true
                        if #later < 3 then later[#later + 1] = (QuestTitle(q) or a.quest or ("#" .. q)) .. " (" .. T("stepN", j) .. ")" end
                    end
                end
            end
        end
    end
    local pm = me[4]
    local lvl = UnitLevel("player") or 1
    for _, e in ipairs((ns.Skipped and ns.Skipped[pm]) or {}) do
        local q, x, y, rc, req, nm = e[1], e[2], e[3], e[4], e[5], e[6]
        if #skip < 3 and logById[q] == nil and not Rendue(q) and req <= lvl
            and (rc == 0 or not RACEBIT[myRace] or HasBit(rc, RACEBIT[myRace])) then
            local d = distTo(me, { m = pm, x = x, y = y })
            if d and d < 30 then skip[#skip + 1] = QuestTitle(q) or nm end
        end
    end
    local lines = {}
    if #later > 0 then lines[#lines + 1] = ListBlock(T("hubLater"), later, "8c7f62") end
    if #skip > 0 then lines[#lines + 1] = ListBlock(T("hubSkip"), skip, "8c7f62") end
    return #lines > 0 and table.concat(lines, "\n") or nil
end

-- "faire" : la prochaine etape est ailleurs -> on l'annonce pour avancer en tuant
function ThenLine(i)
    local s = steps and steps[i]
    if not s or s.t ~= "do" then return nil end
    local j = NextApplicable(i)
    while j <= #steps and doneCache[j] do j = NextApplicable(j) end
    local nx = steps[j]
    if not (nx and nx.m and nx.x and s.m and s.x) then return nil end
    local a, b = WP(s.m, s.x, s.y), WP(nx.m, nx.x, nx.y)
    if not (a and b) or a[3] ~= b[3] or Dist(a[1], a[2], b[1], b[2]) < 100 then return nil end
    local what = (QName(nx) and QName(nx) ~= "") and QName(nx) or StepText(nx):sub(1, 50)
    return ListBlock(T("thenHdr", (T(nx.t) or ""):lower()), { what .. (nx.zone and (" · " .. nx.zone) or "") })
end

-- plusieurs remises faisables au meme endroit : on les annonce ensemble
function TurninGroup(i)
    local s = steps and steps[i]
    if not s or s.t ~= "turnin" or not (s.m and s.x) then return nil end
    local a = WP(s.m, s.x, s.y); if not a then return nil end
    local names, seen = {}, {}
    for j = math.max(1, (baseCurrent or i) - 0), math.min(#steps, i + LOOK) do
        local t = steps[j]
        if t.t == "turnin" and (j == i or Actionable(j)) and t.m and t.x then
            local b = WP(t.m, t.x, t.y)
            if b and b[3] == a[3] and Dist(a[1], a[2], b[1], b[2]) < 30 then
                for _, q in ipairs(Ids(t)) do
                    if not seen[q] and (logById[q] == true or j == i) then
                        seen[q] = true; names[#names + 1] = QuestTitle(q) or t.quest or ("#" .. q)
                    end
                end
            end
        end
    end
    if #names < 2 then return nil end
    return ListBlock(T("turninHere"), names, "9cc7a8", InlineIcon("IcoTurnin", 12, { 156, 199, 168 }))
end

------------------------------------------------------------------
-- Point vise par la fleche a la place de la zone de l'etape :
--  - grotte : l'entree d'abord (apprise la premiere fois que tu y entres), puis l'objectif ; a la sortie, l'entree
--  - objets au sol : l'objet le plus proche pas encore visite, puis le suivant (objets deja en sac exclus)
------------------------------------------------------------------
local visited = {}
local function now() return GetTime and GetTime() or 0 end
local function itemCount(it)
    local n = (C_Item and C_Item.GetItemCount) and C_Item.GetItemCount(it) or 0
    return n or 0
end
local CAVE_PAT = { "caverne", "grotte", " mine", "coven", " cave", "tunnel" }
function IsCaveStep(s)
    if not (s and s.t == "do" and s.m and s.x) then return false end
    local t = ((s.text or "") .. " " .. (s.en or "")):lower()
    for _, p in ipairs(CAVE_PAT) do if t:find(p, 1, true) then return true end end
    return false
end
local function caves() WarpathDropDB._caves = WarpathDropDB._caves or {}; return WarpathDropDB._caves end
-- toutes les entrees connues (les tiennes + celles des autres joueurs), sauf celles que tu as effacees ("x")
local function entrances()
    local own, out = (WarpathDropDB and WarpathDropDB._caves) or {}, {}
    for k, v in pairs(own) do if type(v) == "table" then out[#out + 1] = { k = k, m = v[1], x = v[2], y = v[3] } end end
    for k, v in pairs(ns.BakedCaves or {}) do
        if own[k] == nil and type(v) == "table" then out[#out + 1] = { k = k, m = v[1], x = v[2], y = v[3] } end
    end
    return out
end
-- entree la plus proche d'un point (objectif de la grotte, ou toi), a moins de r metres
local function nearestEntrance(m, x, y, r)
    local g = WP(m, x, y); if not g then return nil end
    local best, bd
    for _, e in ipairs(entrances()) do
        local w = WP(e.m, e.x, e.y)
        if w and w[3] == g[3] then
            local d = Dist(g[1], g[2], w[1], w[2])
            if d < r and (not bd or d < bd) then best, bd = e, d end
        end
    end
    return best
end
local lastOut, caveOut   -- derniere position dehors ; entree de la grotte ou tu es
function CaveTrack()
    if not (DB and steps and WarpathDropDB) then return end
    local indoors = IsIndoors and IsIndoors() or false
    local pm, px, py = PlayerPos()
    if not (pm and px) then return end
    if not indoors then
        lastOut = { pm, px, py }
        caveOut = nil
        return
    end
    -- on vient d'entrer pres d'une grotte du guide (n'importe quelle etape, meme en avance) :
    -- l'endroit ou tu etais dehors est son entree
    if lastOut then
        local me = WP(lastOut[1], lastOut[2], lastOut[3])
        local near = false
        if me then
            for _, t in ipairs(steps) do
                if IsCaveStep(t) and Applies(t) then
                    local g = WP(t.m, t.x, t.y)
                    if g and g[3] == me[3] and Dist(me[1], me[2], g[1], g[2]) < 150 then near = true; break end
                end
            end
        end
        if near then
            local known = nearestEntrance(lastOut[1], lastOut[2], lastOut[3], 30)
            if known then caveOut = known
            else
                local x, y = math.floor(lastOut[2] * 10) / 10, math.floor(lastOut[3] * 10) / 10
                local k = "e:" .. lastOut[1] .. ":" .. x .. ":" .. y
                caves()[k] = { lastOut[1], x, y }
                caveOut = { k = k, m = lastOut[1], x = x, y = y }
            end
        end
    end
    lastOut = nil
end
local function objPoint(s, me)
    if not (s and s.t == "do" and ns.ObjSpawns) then return nil end
    local best, bd
    for _, q in ipairs(Ids(s)) do
        local e = EST[q]
        if e and logById[q] == false then
            for _, d in ipairs(e.d or {}) do
                local sp = ns.ObjSpawns[d[1]]
                if sp and #sp <= 7 and #d < 7 and itemCount(d[1]) < (d[2] or 1) then
                    local m = sp[1]
                    for k = 2, #sp - 1, 2 do
                        local g = WP(m, sp[k], sp[k + 1])
                        if g and g[3] == me[3] then
                            local key = m .. ":" .. sp[k] .. ":" .. sp[k + 1]
                            local dd = Dist(me[1], me[2], g[1], g[2])
                            if dd < 8 then visited[key] = now() end
                            if not (visited[key] and now() - visited[key] < 300) and (not bd or dd < bd) then
                                best, bd = { m = m, x = sp[k], y = sp[k + 1], name = d[6], kind = "obj" }, dd
                            end
                        end
                    end
                end
            end
        end
    end
    if best and bd < 400 then return best end
end
-- points de passage : les tiens (/warpath passage, gardes pour tous tes personnages), sinon ceux du guide
-- cle : numero de quete pour une etape "faire", "rendre:quete" / "prendre:quete" sinon
function PassageKey(s, q)
    if s.t == "do" then return q end
    return (s.t == "turnin" and "rendre:" or "prendre:") .. q
end
function PassageFor(s, q)
    local k = PassageKey(s, q)
    local own = WarpathDropDB and WarpathDropDB._pass and WarpathDropDB._pass[k]
    if own == "x" then return nil end
    local v = (type(own) == "table" and own) or (ns.Passages and ns.Passages[k])
    -- v1.41 : un passage loin de l'objectif (autre continent, ou a plus de 800 m) a ete enregistre par erreur
    -- (ex. l'ascenseur de Thunder Bluff sur Goblin Invaders, dans Stonetalon) : on l'ignore
    if v and s and s.m and s.x then
        local a, b = WP(v[1], v[2], v[3]), WP(s.m, s.x, s.y)
        if a and b and (a[3] ~= b[3] or Dist(a[1], a[2], b[1], b[2]) > 800) then return nil end
    end
    return v
end

-- Grottes des villes (Data.lua : D.CITYCAVES) : entree, eventuellement remplacee par la tienne (/warpath passage grotte)
local function caveEntrance(c)
    local own = WarpathDropDB and WarpathDropDB._cityCave and WarpathDropDB._cityCave[c.m]
    if type(own) == "table" then return own[1], own[2] end
    return c.x, c.y
end
-- la grotte qui contient ce PNJ (par son nom) ou ce point (a moins de 1,5 % de la carte d'un PNJ connu)
function CityCaveFor(m, x, y, npc)
    for _, c in ipairs(D.CITYCAVES or {}) do
        if c.m == m then
            for _, n in ipairs(c.npcs or {}) do if npc and n == npc then return c end end
            if x and y then
                for _, p in ipairs(c.at or {}) do
                    if math.abs(p[1] - x) <= 1.5 and math.abs(p[2] - y) <= 1.5 then return c end
                end
            end
        end
    end
end
-- dehors et loin de l'entree : la fleche vise l'entree de la grotte ; dedans (ou sur le seuil) : le PNJ
function CityCavePoint(m, x, y, npc, me)
    local c = CityCaveFor(m, x, y, npc)
    if not c or (IsIndoors and IsIndoors()) then return nil end
    local ex, ey = caveEntrance(c)
    local w = WP(c.m, ex, ey)
    if not (w and me and w[3] == me[3]) or Dist(me[1], me[2], w[1], w[2]) <= 8 then return nil end
    return { m = c.m, x = ex, y = ey, name = c.name, kind = "citycave" }
end
-- /warpath passage : ta position devient le point de passage de l'etape affichee ; "efface" le retire
function PassageCmd(arg)
    local s = steps and steps[focus or current]
    local q = s and Ids(s)[1]
    if not (s and q and s.m and s.x and (s.t == "do" or s.t == "turnin" or s.t == "accept")) then say(T("passNoStep")); return end
    WarpathDropDB._pass = WarpathDropDB._pass or {}
    local k = PassageKey(s, q)
    local name = QName(s) or ("#" .. q)
    arg = (arg or ""):lower()
    -- v1.41 : passages de ville, pas lies a une quete
    if arg == "ville" or arg == "city" or arg == "grotte" or arg == "cave" then
        local pm, px, py = PlayerPos()
        local city = pm and ZoneOf(pm)
        if not (city and px and (city == 1454 or city == 1456 or city == 1458)) then say(T("passNotCity")); return end
        local x, y = math.floor(px * 10 + 0.5) / 10, math.floor(py * 10 + 0.5) / 10
        if arg == "ville" or arg == "city" then
            WarpathDropDB._cityExit = WarpathDropDB._cityExit or {}
            WarpathDropDB._cityExit[city] = { pm, x, y }
            say(T("passCitySaved", MAPNAME[city] or tostring(city), x, y))
        else
            WarpathDropDB._cityCave = WarpathDropDB._cityCave or {}
            WarpathDropDB._cityCave[city] = { x, y }
            say(T("passCaveSaved", MAPNAME[city] or tostring(city), x, y))
        end
        lastWP = nil; Refresh(true)
        return
    end
    if arg == "efface" or arg == "clear" or arg == "x" then
        WarpathDropDB._pass[k] = "x"; say(T("passCleared", name))
    elseif arg == "liste" or arg == "list" then
        local n = 0
        for key, v in pairs(WarpathDropDB._pass) do
            if type(v) == "table" then n = n + 1; say(string.format("  %s : %s %.1f, %.1f", tostring(key), MAPNAME[v[1]] or tostring(v[1]), v[2], v[3])) end
        end
        if n == 0 then say(T("passNone")) end
        return
    else
        local pm, px, py = PlayerPos()
        if not (pm and px) then say(T("passNoPos")); return end
        local x, y = math.floor(px * 10 + 0.5) / 10, math.floor(py * 10 + 0.5) / 10
        WarpathDropDB._pass[k] = { pm, x, y }
        say(T("passSaved", name, MAPNAME[pm] or tostring(pm), x, y))
        say(T("passHint"))   -- rappel : ce point sert a CETTE quete ; pour une ville, /warpath passage ville ou grotte
    end
    lastWP = nil; Refresh(true)
end

-- Camps separes (Data/MobZones.lua) : la fleche va au camp dont les objectifs ne sont pas finis.
-- On reste sur un camp jusqu'a ce que ses objectifs soient faits, et on ne change pas en combat.
-- Si l'etat d'un objectif est inconnu, on ne fait rien (point habituel de l'etape).
local zoneSticky, zoneLast = {}, {}
local function zoneObjDone(q, ref, objs)
    if ref[1] == "d" then return itemCount(ref[2]) >= (ref[3] or 1) end
    local loc = WarpathDropDB and WarpathDropDB._npcLoc and WarpathDropDB._npcLoc[(GetLocale and GetLocale()) or "enUS"] or {}
    local nm = loc[ref[2]] or (ns.NpcNames or {})[ref[2]]
    if nm then
        for _, o in ipairs(objs) do
            if type(o.text) == "string" and o.text:find(nm, 1, true) then return o.finished and true or false end
        end
    end
    -- repli : les objectifs du jeu suivent l'ordre des donnees (monstres a tuer d'abord)
    local e = EST[q]
    if e and e.k and #objs == #e.k + #(e.d or {}) then
        for i, k in ipairs(e.k) do if k[1] == ref[2] and objs[i] then return objs[i].finished and true or false end end
    end
    return nil
end
local function zoneLabel(q, z)
    local loc = WarpathDropDB and WarpathDropDB._npcLoc and WarpathDropDB._npcLoc[(GetLocale and GetLocale()) or "enUS"] or {}
    local names = {}
    for r = 4, #z do
        local ref = z[r]
        local nm
        if ref[1] == "k" then nm = loc[ref[2]] or (ns.NpcNames or {})[ref[2]]
        else for _, d in ipairs((EST[q] or {}).d or {}) do if d[1] == ref[2] then nm = d[6] end end end
        if nm and #names < 2 then names[#names + 1] = nm end
    end
    return table.concat(names, " · ")
end
function MobZonePoint(s, me)
    if not (s and s.t == "do" and ns.MobZones and C_QuestLog and C_QuestLog.GetQuestObjectives) or IS_DUNGEON[DB.guide] then return nil end
    local list, total = {}, 0
    for _, q in ipairs(Ids(s)) do
        local zs = ns.MobZones[q]
        if zs and logById[q] == false then
            local ok, objs = pcall(C_QuestLog.GetQuestObjectives, q)
            if not ok or type(objs) ~= "table" or #objs == 0 then return nil end
            for zi, z in ipairs(zs) do
                total = total + 1
                local todo = false
                for r = 4, #z do
                    local f = zoneObjDone(q, z[r], objs)
                    if f == nil then return nil end
                    if not f then todo = true end
                end
                if todo then list[#list + 1] = { key = q .. ":" .. zi, q = q, z = z, idx = zi, n = #zs } end
            end
        end
    end
    if #list == 0 or total < 2 then return nil end
    local sk = (SeenKey and SeenKey(current)) or tostring(current)
    local function point(c)
        zoneSticky[sk] = c.key
        local p = { m = c.z[1], x = c.z[2], y = c.z[3], name = zoneLabel(c.q, c.z), kind = "zone", idx = c.idx, n = c.n }
        zoneLast[sk] = p
        return p
    end
    for _, c in ipairs(list) do if c.key == zoneSticky[sk] then return point(c) end end
    -- le camp en cours vient d'etre fini : pas de changement pendant le combat
    if zoneSticky[sk] and UnitAffectingCombat and UnitAffectingCombat("player") and zoneLast[sk] then return zoneLast[sk] end
    -- deja dans un camp : celui-la ; sinon d'abord le camp le plus loin de l'etape suivante (on finit pres d'elle)
    local nx = steps[NextApplicable(current)]
    local nw = nx and nx.m and nx.x and WP(nx.m, nx.x, nx.y)
    local best, bscore
    for _, c in ipairs(list) do
        local w = WP(c.z[1], c.z[2], c.z[3])
        if w and me and w[3] == me[3] and Dist(me[1], me[2], w[1], w[2]) < 120 then return point(c) end
        local score = (w and nw and w[3] == nw[3]) and Dist(w[1], w[2], nw[1], nw[2]) or 0
        if not bscore or score > bscore then best, bscore = c, score end
    end
    return best and point(best) or nil
end
-- Etape "Monte au niveau X" : coin de farm (Data/FarmSpots.lua) sur ta carte, monstres de ton niveau a +2,
-- le meilleur compromis entre densite, niveau (ideal : le tien +1) et distance. Pas avec "Manque d'XP : Donjon".
function FarmSpot(s, me)
    if not (s and s.t == "level" and ns.FarmSpots) then return nil end
    local st = StyleGet and StyleGet()
    if st and st.xpMode == "dungeon" then return nil end
    local pm = PlayerPos(); local list = pm and ns.FarmSpots[pm]
    if not list then return nil end
    local L = UnitLevel and UnitLevel("player") or 1
    local best, bs
    for _, sp in ipairs(list) do
        if sp[4] >= L and sp[3] <= L + 2 then
            local w = WP(pm, sp[1], sp[2])
            if w and me and w[3] == me[3] then
                local d = Dist(me[1], me[2], w[1], w[2])
                local fit = 1 - 0.25 * math.abs((sp[3] + sp[4]) / 2 - (L + 1))
                local score = sp[5] * math.max(0.1, fit) / (1 + d / 600)
                if not bs or score > bs then
                    local loc = WarpathDropDB and WarpathDropDB._npcLoc and WarpathDropDB._npcLoc[(GetLocale and GetLocale()) or "enUS"] or {}
                    best, bs = { m = pm, x = sp[1], y = sp[2], name = loc[sp[6]] or sp[7], lmin = sp[3], lmax = sp[4], n = sp[5], kind = "farm" }, score
                end
            end
        end
    end
    return best
end
-- Course en ville (v1.39) : maitre d'armes, entraineur... La fleche y va en priorite, puis revient au guide
-- une fois sur place (8 m), a l'ouverture de l'entraineur, ou apres 15 min.
function SetErrand(m, x, y, name)
    if not (DB and m and x and y) then return end
    DB.errand = { m = m, x = x, y = y, name = name, t = time and time() or 0 }
    lastWP = nil
    Refresh(true)
end
function ClearErrand()
    if not (DB and DB.errand) then return end
    DB.errand = nil
    lastWP = nil
    Refresh(true)
end
function ErrandPoint(me)
    local e = DB and DB.errand
    if not e then return nil end
    local w = WP(e.m, e.x, e.y)
    if (time and e.t and time() - e.t > 900) or (w and me and w[3] == me[3] and Dist(me[1], me[2], w[1], w[2]) < 8) then
        DB.errand = nil
        return nil
    end
    return { m = e.m, x = e.x, y = e.y, name = e.name, kind = "errand" }
end

-- Villes fermees (Orgrimmar, Thunder Bluff, Undercity) : on y entre et on en sort par la porte,
-- pas a vol d'oiseau a travers les murs (v1.39). Les portes sont dans D.GATES (Data.lua).
local WALLED = { [1454] = true, [1456] = true, [1458] = true }
local gateFly = { key = nil, t = 0, fly = false }
function CityGatePoint(s, me)
    if not (s and s.m and s.x) then return nil end
    local zMe, zTo = ZoneOf(me[4]), ZoneOf(s.m)
    if not (zMe and zTo) or zMe == zTo then return nil end
    local city = WALLED[zTo] and zTo or (WALLED[zMe] and zMe) or nil
    if not city then return nil end
    local other = (city == zTo) and zMe or zTo
    -- v1.45 : un vol fait gagner du temps (ex. Thunder Bluff -> Ratchet) : pas de porte, la fleche et le conseil
    -- de vol visent l'objectif. Avant : la porte (l'ascenseur) passait avant, et le vol n'etait jamais propose.
    if DB.useFlights ~= false and BestFlight and KnownFlights and not (UnitOnTaxi and UnitOnTaxi("player")) then
        local now = GetTime and GetTime() or 0
        local key = s.m .. ":" .. s.x .. ":" .. s.y .. ":" .. math.floor(me[1] / 30) .. ":" .. math.floor(me[2] / 30)
        if not (gateFly.key == key and now - gateFly.t < 5) then
            local g = WP(s.m, s.x, s.y)
            local ok, fl = pcall(BestFlight, me, g, KnownFlights())
            gateFly.key, gateFly.t, gateFly.fly = key, now, (ok and fl) and true or false
        end
        if gateFly.fly then return nil end
    end
    local best, bd
    for _, g in ipairs(D.GATES or {}) do
        local z1, z2 = g.z[1], g.z[2]
        -- dehors : seulement une porte qui donne sur ta zone ; dedans : n'importe quelle porte de la ville
        if (z1 == city or z2 == city) and (city == zMe or z1 == other or z2 == other) then
            local w = WP(g.m, g.x, g.y)
            if w and w[3] == me[3] then
                local d = Dist(me[1], me[2], w[1], w[2])
                if not bd or d < bd then best, bd = g, d end
            end
        end
    end
    if best and bd > 12 then
        -- dans la ville : on vise la sortie cote ville (haut de l'ascenseur de Thunder Bluff...), la tienne d'abord
        if city == zMe then
            local own = WarpathDropDB and WarpathDropDB._cityExit and WarpathDropDB._cityExit[city]
            local inner = (type(own) == "table" and own) or best.inner
            if inner then
                local w = WP(inner[1], inner[2], inner[3])
                if w and w[3] == me[3] and Dist(me[1], me[2], w[1], w[2]) > 12 then
                    return { m = inner[1], x = inner[2], y = inner[3], name = MAPNAME[city] or "", kind = "gate" }
                elseif w then return nil end
            end
        end
        return { m = best.m, x = best.x, y = best.y, name = MAPNAME[city] or "", kind = "gate" }
    end
end

function StepPoint(s)
    if not (s and DB) then return nil end
    local me = PlayerWP(); if not me then return nil end
    local smart = DB.smartArrow ~= false
    -- mort (fantome) : la fleche va a ton corps
    if smart and UnitIsGhost and UnitIsGhost("player") and C_DeathInfo and C_DeathInfo.GetCorpseMapPosition then
        local pm = PlayerPos()
        local ok, p = pcall(C_DeathInfo.GetCorpseMapPosition, pm)
        if ok and p then
            local x, y = p.x, p.y
            if (not x) and p.GetXY then x, y = p:GetXY() end
            if x and y then return { m = pm, x = math.floor(x * 1000) / 10, y = math.floor(y * 1000) / 10, name = T("corpse"), kind = "corpse" } end
        end
    end
    -- course en ville demandee par toi (maitre d'armes, entraineur)
    local er = ErrandPoint(me)
    if er then return er end
    -- Intendance : l'arret en cours de la tournee en ville
    local qp = QMPoint and QMPoint()
    if qp then
        -- PNJ dans une grotte de la ville (Pools of Vision...) : d'abord l'entree
        local cc = CityCavePoint(qp.m, qp.x, qp.y, qp.name, me)
        if cc then cc.label, cc.idx, cc.n, cc.kind = qp.label, qp.idx, qp.n, "qm"; cc.name = T("caveIn") .. " · " .. cc.name end
        return cc or qp
    end
    if not smart then return nil end
    if s.t == "level" then return FarmSpot(s, me) end
    -- ville fermee : passer par la porte
    local gate = CityGatePoint(s, me)
    if gate then return gate end
    -- etape dont le PNJ est dans une grotte de la ville (ex. Apothecary Zamah, Pools of Vision)
    local cc = s.m and s.x and CityCavePoint(s.m, s.x, s.y, nil, me)
    if cc then return cc end
    -- v1.42 : chemin garde (fil d'Ariane, Trail.lua) : la fleche le suit
    local tp = TrailPoint and TrailPoint(s, me)
    if tp then return tp end
    -- point de passage (tunnel, rampe, pont...) : l'entree tant que tu es du mauvais cote, puis l'objectif
    if s.m and s.x and (s.t == "do" or s.t == "turnin" or s.t == "accept") then
        for _, q in ipairs(Ids(s)) do
            local v = PassageFor(s, q)
            if v and (s.t ~= "do" or logById[q] == false) then
                local g, w = WP(s.m, s.x, s.y), WP(v[1], v[2], v[3])
                if g and w and g[3] == me[3] and w[3] == me[3] then
                    local dMe, dV = Dist(me[1], me[2], g[1], g[2]), Dist(w[1], w[2], g[1], g[2])
                    if dMe > dV + 15 and Dist(me[1], me[2], w[1], w[2]) > 10 then
                        return { m = v[1], x = v[2], y = v[3], name = T("tunnelIn"), kind = "pass" }
                    end
                end
            end
        end
    end
    local indoors = IsIndoors and IsIndoors() or false
    -- entree de la grotte de l'etape (apprise par toi ou par un autre joueur), a moins de 200 m de l'objectif
    local here = IsCaveStep(s) and nearestEntrance(s.m, s.x, s.y, 200) or nil
    -- sortie d'une grotte alors que l'etape en cours est ailleurs
    if indoors and caveOut and not (here and here.k == caveOut.k) then
        return { m = caveOut.m, x = caveOut.x, y = caveOut.y, name = T("caveExit"), kind = "exit" }
    end
    if here and not indoors then
        local g = WP(here.m, here.x, here.y)
        if g and g[3] == me[3] and Dist(me[1], me[2], g[1], g[2]) > 12 then
            return { m = here.m, x = here.x, y = here.y, name = T("caveIn"), kind = "enter" }
        end
    end
    return objPoint(s, me) or MobZonePoint(s, me) or DungeonDoorPoint(s)
end
-- v1.45 : etape de l'interieur du donjon (sans position) alors que tu es dehors, donjon pas quitte
-- (mort, course en fantome : le corps est dans l'instance, le jeu ne le situe pas) : l'entree du donjon
function DungeonDoorPoint(s)
    if not (DB and steps and IS_DUNGEON and IS_DUNGEON[DB.guide]) or (s and s.m and s.x) then return nil end
    if not (DB.dgIn and DB.dgIn[DB.guide]) or (DB.dgOut and DB.dgOut[DB.guide]) then return nil end
    if IsInInstance and IsInInstance() then return nil end
    for j = 1, #steps do
        local g = steps[j]
        if g.t == "go" and g.m and g.x then
            local name = Title and Guides and Title(Guides[DB.guide]) or ""
            return { m = g.m, x = g.x, y = g.y, name = T("dgBack", name), kind = "dgdoor" }
        end
    end
end
function StepPointKey(s)
    local p = StepPoint(s)
    return p and (p.kind .. p.m .. ":" .. p.x .. ":" .. p.y) or ""
end

-- sous le niveau 10, mourir ne coute rien : pour un long trajet de retour, ca peut etre plus rapide
function DeathTip(i)
    local s = steps and steps[i]
    if not s or (UnitLevel("player") or 1) >= 10 or s.t ~= "turnin" or not s.m then return nil end
    if DB.deathTip == false then return nil end
    local me = PlayerWP(); if not me then return nil end
    local g = WP(s.m, s.x, s.y)
    if not g or g[3] ~= me[3] or Dist(me[1], me[2], g[1], g[2]) < 450 then return nil end
    return T("deathTip")
end

-- etat des grottes pour /warpath diag : dedans ou dehors, etape de grotte, entree connue, cible de la fleche
function CaveDiag()
    local s = steps and steps[current]
    local out = { indoors = IsIndoors and IsIndoors() or false, cave = IsCaveStep(s), exitKnown = caveOut ~= nil }
    if out.cave then
        local e = nearestEntrance(s.m, s.x, s.y, 200)
        if e then
            out.entry = e
            out.own = WarpathDropDB and WarpathDropDB._caves and type(WarpathDropDB._caves[e.k]) == "table" or false
            local me, w = PlayerWP(), WP(e.m, e.x, e.y)
            if me and w and me[3] == w[3] then out.dist = math.floor(Dist(me[1], me[2], w[1], w[2]) + 0.5) end
        end
    end
    local p = s and StepPoint(s)
    out.aim = p and p.kind or "step"
    return out
end

-- entree de grotte mal apprise : on l'oublie, elle sera reapprise a la prochaine entree
function ForgetCave()
    local s = steps and steps[current]
    local cv = WarpathDropDB and WarpathDropDB._caves
    if not cv then return end
    -- "x" : ni ton entree, ni celle des autres joueurs ; reapprise a ta prochaine entree
    if IsCaveStep(s) then
        for _, e in ipairs(entrances()) do
            local g, w = WP(s.m, s.x, s.y), WP(e.m, e.x, e.y)
            if g and w and g[3] == w[3] and Dist(g[1], g[2], w[1], w[2]) < 200 then cv[e.k] = "x" end
        end
    end
    if caveOut then cv[caveOut.k] = "x"; caveOut = nil end
    say(T("caveForgot"))
    lastWP = nil; Refresh(true)
end

-- Nouveaux sorts (niveau pair) et entraineur de classe a moins de 250 m : etape temporaire avant l'etape en cours.
-- Elle s'efface quand tu ouvres la fenetre d'un entraineur (TRAINER_SHOW) ou avec OK (passee pour ce niveau).
local TRAIN_R = 250
local trainLatch
function TrainDetour(s)
    if not (DB and DB.trainDue and myClass and DB.trainer ~= false) then return nil end
    if DB.trainSkip == DB.trainDue or IS_DUNGEON[DB.guide] then return nil end
    if IsInInstance then local inI = IsInInstance(); if inI then return nil end end
    if s and s.t == "do" and ((s.text or "") .. (s.en or "")):lower():find("escort", 1, true) then return nil end
    if not NearestTrainer then return nil end
    local e, d = NearestTrainer((ns.ClassTrainers or {})[myClass])
    if not (e and d) then return nil end
    if d > TRAIN_R and trainLatch ~= DB.trainDue then return nil end
    trainLatch = DB.trainDue   -- une fois proposee, l'etape reste jusqu'a l'entraineur ou OK
    return { id = 0, done = true, train = true, m = e[1], x = e[2], y = e[3], name = e[4] }
end

-- En chemin : objets de quete encore a ramasser (semes un peu partout) pres du trajet vers l'etape en cours
function OnTheWay(i)
    local s = steps and steps[i]
    if not s or s.t == "do" or not (s.m and s.x) or not ns.ObjSpawns then return nil end
    local me = PlayerWP(); if not me then return nil end
    local b = WP(s.m, s.x, s.y)
    if not b or b[3] ~= me[3] then return nil end
    local L2 = (b[1] - me[1]) ^ 2 + (b[2] - me[2]) ^ 2
    if L2 < 60 * 60 then return nil end
    local names, seen = {}, {}
    for q, st in pairs(logById) do
        local e = EST[q]
        if st == false and e then
            for _, d in ipairs(e.d or {}) do
                local sp = ns.ObjSpawns[d[1]]
                if sp and #d < 7 and not seen[d[1]] and itemCount(d[1]) < (d[2] or 1) then
                    for k = 2, #sp - 1, 2 do
                        local g = WP(sp[1], sp[k], sp[k + 1])
                        if g and g[3] == me[3] then
                            local t = math.max(0, math.min(1, ((g[1] - me[1]) * (b[1] - me[1]) + (g[2] - me[2]) * (b[2] - me[2])) / L2))
                            local cx, cy = me[1] + t * (b[1] - me[1]), me[2] + t * (b[2] - me[2])
                            if Dist(g[1], g[2], cx, cy) < 40 then
                                seen[d[1]] = true
                                names[#names + 1] = (C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(d[1])) or d[6]
                                break
                            end
                        end
                    end
                end
            end
        end
    end
    if #names == 0 then return nil end
    return ListBlock(T("onTheWayHdr"), names, "9cc7a8")
end

-- Etape "faire" : intro de l'etape (avant les « : ») + objectifs du jeu en direct, groupes par action.
-- Renvoie nil si le jeu ne donne pas les objectifs (on garde alors le texte habituel).
local VERB = { monster = "objKill", item = "objLoot", object = "objUse", event = "objDo" }
local function cleanObj(t)
    if type(t) ~= "string" then return "?" end
    t = t:gsub("^%s*%d+%s*/%s*%d+%s*", ""):gsub("%s*:?%s*%d+%s*/%s*%d+%s*$", "")
    t = t:gsub("%s+slain$", ""):gsub("%s+tu[ée]+s?$", "")
    return t
end
function LiveObjectives(s)
    if not (s and s.t == "do" and C_QuestLog and C_QuestLog.GetQuestObjectives) or DB.liveObj == false then return nil end
    local txt = StepText(s) or ""
    local lead = txt:match("^(.-)%s*:%s") or txt:match("^(.-)%s*:$")
    local blocks, n = {}, 0
    local rows = {} -- meme contenu, ligne par ligne, pour la fenetre (compteur aligne a droite)
    local ids = {}
    for _, q in ipairs(Ids(s)) do if logById[q] ~= nil then ids[#ids + 1] = q end end
    if #ids == 0 then return nil end
    for _, q in ipairs(ids) do
        local ok, objs = pcall(C_QuestLog.GetQuestObjectives, q)
        if ok and type(objs) == "table" and #objs > 0 then
            local e = EST[q] or {}
            local lines = {}
            if #ids > 1 then
                lines[#lines + 1] = "|cff8c7f62" .. (QuestTitle(q) or e.n or ("#" .. q)) .. "|r"
                rows[#rows + 1] = { k = "quest", text = QuestTitle(q) or e.n or ("#" .. q) }
            end
            local lastVerb
            for _, o in ipairs(objs) do
                local key = VERB[o.type or ""] or "objOther"
                if key == "objKill" and e.u then key = "objUseOn" end
                local verb
                if key == "objUseOn" then
                    local it = e.u[1]
                    local nm = it and ((C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(it)) or "")
                    verb = T(key, nm ~= "" and nm or "?")
                elseif key == "objLoot" then
                    local src = ""
                    for _, d in ipairs(e.d or {}) do
                        if #d >= 7 and type(o.text) == "string" and d[6] and o.text:find(d[6], 1, true) then src = T("objFromMobs") end
                        if #d < 7 and type(o.text) == "string" and d[6] and o.text:find(d[6], 1, true) then src = T("objFromGround") end
                    end
                    verb = T(key) .. src
                else verb = T(key) end
                if verb ~= lastVerb then lines[#lines + 1] = "|cffcdbb8e" .. verb .. "|r"; rows[#rows + 1] = { k = "verb", text = verb }; lastVerb = verb end
                local have, need = o.numFulfilled or 0, o.numRequired or 1
                local name = cleanObj(o.text)
                if o.finished then
                    lines[#lines + 1] = "|TInterface\\AddOns\\" .. ADDON .. "\\Media\\BoxDone:16|t |cff6f6450" .. name .. "  " .. have .. "/" .. need .. "|r"
                else
                    lines[#lines + 1] = "|TInterface\\AddOns\\" .. ADDON .. "\\Media\\Box:16|t |cffe9dfc8" .. name .. "|r  |cffa89a7c" .. have .. "/" .. need .. "|r"
                end
                rows[#rows + 1] = { k = "obj", text = name, count = have .. "/" .. need, done = o.finished and true or false }
                n = n + 1
            end
            blocks[#blocks + 1] = table.concat(lines, "\n")
        end
    end
    if n == 0 then return nil end
    -- le lieu (texte avant « : ») va dans le bloc destination de la fenetre
    return table.concat(blocks, "\n"), lead, rows
end

-- etape "rendre" suivie de quetes a prendre chez le meme PNJ : on le dit tout de suite,
-- pour ne pas fermer la fenetre et repartir (le jeu n'enchaine pas toujours la quete suivante)
function FollowUpAccepts(i)
    local s = steps and steps[i]
    if not s or s.t ~= "turnin" then return nil end
    local npcs = {}
    for _, q in ipairs(Ids(s)) do for _, n in ipairs((EST[q] or {}).en or {}) do npcs[n] = true end end
    local a = s.m and s.x and WP(s.m, s.x, s.y)
    local names, seen = {}, {}
    local j = NextApplicable(i)
    while j <= #steps and #names < 4 do
        local t = steps[j]
        if t.t ~= "accept" then break end
        local same = false
        for _, q in ipairs(Ids(t)) do for _, n in ipairs((EST[q] or {}).g or {}) do if npcs[n] then same = true end end end
        if not same and a and t.m and t.x then
            local b = WP(t.m, t.x, t.y)
            same = b and b[3] == a[3] and Dist(a[1], a[2], b[1], b[2]) < 8 or false
        end
        if not same then break end
        for _, q in ipairs(Ids(t)) do
            if not seen[q] and logById[q] == nil and not Rendue(q) then seen[q] = true; names[#names + 1] = QuestTitle(q) or t.quest or ("#" .. q) end
        end
        j = NextApplicable(j)
    end
    if #names == 0 then return nil end
    return ListBlock(T("thenTalk"), names, "d6b866", InlineIcon("IcoAccept", 12, { 214, 184, 102 }))
end

-- plusieurs quetes a prendre au meme endroit : on les annonce ensemble
function AcceptGroup(i)
    local s = steps and steps[i]
    if not s or s.t ~= "accept" or not (s.m and s.x) then return nil end
    local a = WP(s.m, s.x, s.y); if not a then return nil end
    local names, seen = {}, {}
    for j = i, math.min(#steps, i + LOOK) do
        local t = steps[j]
        if t.t == "accept" and (j == i or Actionable(j)) and t.m and t.x and Applies(t) and not doneCache[j] then
            local b = WP(t.m, t.x, t.y)
            if b and b[3] == a[3] and Dist(a[1], a[2], b[1], b[2]) < 30 then
                for _, q in ipairs(Ids(t)) do
                    if not seen[q] and logById[q] == nil then seen[q] = true; names[#names + 1] = QuestTitle(q) or t.quest or ("#" .. q) end
                end
            end
        end
    end
    if #names < 2 then return nil end
    return ListBlock(T("acceptHere"), names, "d69a66", InlineIcon("IcoAccept", 12, { 214, 184, 102 }))
end
