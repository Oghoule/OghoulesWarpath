-- Oghoule's Warpath : moteur (Near.lua) - moins d'allers-retours
-- 1) Groupe de prises/remises consecutives : on va d'abord au PNJ le plus proche.
-- 2) En passant : un PNJ a moins de 25 m dont une etape proche a besoin passe en premier.
-- 3) Explications : quetes a prendre plus tard / jamais prises pres de toi, quetes en attente d'un niveau.
local ADDON, ns = ...
local _ENV = ns.CoreEnv
if setfenv then setfenv(1, _ENV) end

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
    local ok, pk = pcall(function() return StepPointKey(steps[current]) .. (TrainDetour(steps[current]) and "T" or "") end)
    if ok and pk ~= lastPointKey then lastPointKey = pk; lastWP = nil; Refresh(true); return end
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
                    if has then out[#out + 1] = T("lvlWait", QuestTitle(q) or a.quest or ("#" .. q), a.req, a.req); break end
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
                        if #later < 3 then later[#later + 1] = (QuestTitle(q) or a.quest or ("#" .. q)) .. " (" .. j .. ")" end
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
    if #later > 0 then lines[#lines + 1] = T("hubLater", table.concat(later, ", ")) end
    if #skip > 0 then lines[#lines + 1] = T("hubSkip", table.concat(skip, ", ")) end
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
    return T("thenGo", (PREFIX[nx.t] or "") .. " " .. what .. (nx.zone and (" · " .. nx.zone) or ""))
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
    return T("turninGroup", #names, table.concat(names, ", "))
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
function StepPoint(s)
    if not (s and DB and DB.smartArrow ~= false) then return nil end
    local me = PlayerWP(); if not me then return nil end
    -- mort (fantome) : la fleche va a ton corps
    if UnitIsGhost and UnitIsGhost("player") and C_DeathInfo and C_DeathInfo.GetCorpseMapPosition then
        local pm = PlayerPos()
        local ok, p = pcall(C_DeathInfo.GetCorpseMapPosition, pm)
        if ok and p then
            local x, y = p.x, p.y
            if (not x) and p.GetXY then x, y = p:GetXY() end
            if x and y then return { m = pm, x = math.floor(x * 1000) / 10, y = math.floor(y * 1000) / 10, name = T("corpse"), kind = "corpse" } end
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
    return objPoint(s, me)
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
    return T("onTheWay", table.concat(names, ", "))
end
