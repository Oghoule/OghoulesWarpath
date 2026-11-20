-- Oghoule's Warpath : moteur (Trail.lua) - fil d'Ariane (v1.42)
-- L'addon garde EN MEMOIRE seulement (rien sur le disque) tes 5 dernieres minutes de marche : un point tous les ~15 m.
-- Quand tu arrives a l'objectif de l'etape apres un grand detour (grotte, tunnel, montagne), il propose de garder
-- ce chemin : clic sur le message, ou /warpath chemin garde. Un chemin garde est lie au LIEU d'arrivee, pas a la quete :
-- toute etape dont l'objectif est au bout du chemin s'en sert, et la fleche le suit.
-- Sur un chemin dont le bout ne sert pas a l'etape en cours : la fleche te fait ressortir par ou tu es entre.
-- Le brouillon repart a zero apres une cueillette/un minage, un marchand, un entraineur, la boite aux lettres,
-- un vol, une mort, une teleportation, une instance. Les boucles (aller-retour vers un monstre, une herbe) sont retirees.
-- Sauvegardes (par compte) : WarpathDropDB._trail[cle] = { p = { carte, x, y, carte, x, y, ... } }
--                            WarpathDropDB._trailNo[cle] = true : deja propose, on ne redemande pas
-- cle = "carte:x:y" de l'objectif de l'etape.
local ADDON, ns = ...
local _ENV = ns.CoreEnv
if setfenv then setfenv(1, _ENV) end

local STEP = 15          -- distance entre deux points du brouillon
local KEEP_SECS = 300    -- 5 minutes de marche gardees en memoire
local MAX_CRUMBS = 200
local LOOP = 20          -- repasser a moins de 20 m d'un point deja vu = boucle, retiree
local MIN_EXCESS = 60    -- au moins ~60 m de plus que la ligne droite...
local MIN_RATIO = 1.4    -- ...et 1,4 fois la ligne droite sur la partie tordue
local END_NEAR = 40      -- un chemin sert a une etape si son bout est a moins de 40 m de l'objectif
local ON_TRAIL = 25      -- a moins de 25 m du chemin : tu es dessus
local AIM = 20           -- la fleche vise un point ~20 m plus loin sur le chemin
local MAX_PTS = 60
local MAX_TRAILS = 200

local crumbs = {}        -- brouillon : { wx, wy, continent, carte, x, y, temps }
local last               -- dernier echantillon, pour reperer les sauts (teleportation)
local arrived = {}       -- objectifs deja traites a l'arrivee pendant cette seance
local candidate          -- dernier chemin propose (pour /warpath chemin garde)
local cache              -- chemins gardes en coordonnees monde (refait apres un ajout/effacement)
local prog = {}          -- segment ou tu en es sur chaque chemin (evite de sauter d'un etage a l'autre)

local function now() return GetTime and GetTime() or 0 end
local function r1(v) return math.floor(v * 10 + 0.5) / 10 end
local function saved()
    if not WarpathDropDB then return nil end
    WarpathDropDB._trail = WarpathDropDB._trail or {}
    return WarpathDropDB._trail
end
local function refused()
    if not WarpathDropDB then return {} end
    WarpathDropDB._trailNo = WarpathDropDB._trailNo or {}
    return WarpathDropDB._trailNo
end

-- distance d'un point p au segment a-b
local function perp(p, a, b)
    local dx, dy = b[1] - a[1], b[2] - a[2]
    local l2 = dx * dx + dy * dy
    if l2 == 0 then return Dist(p[1], p[2], a[1], a[2]) end
    local t = math.max(0, math.min(1, ((p[1] - a[1]) * dx + (p[2] - a[2]) * dy) / l2))
    return Dist(p[1], p[2], a[1] + t * dx, a[2] + t * dy)
end

-- Douglas-Peucker : on ne garde que les virages (les points alignes sont retires)
local function simplify(pts, eps)
    local keep = { [1] = true, [#pts] = true }
    local stack = { { 1, #pts } }
    while #stack > 0 do
        local seg = table.remove(stack)
        local a, b = seg[1], seg[2]
        local best, bi = 0, nil
        for k = a + 1, b - 1 do
            local d = perp(pts[k], pts[a], pts[b])
            if d > best then best, bi = d, k end
        end
        if bi and best > eps then stack[#stack + 1] = { a, bi }; stack[#stack + 1] = { bi, b }; keep[bi] = true end
    end
    local out = {}
    for k = 1, #pts do if keep[k] then out[#out + 1] = pts[k] end end
    return out
end

function TrailBreak() wipe(crumbs); last = nil end

-- chemins gardes, en coordonnees monde
local function trails()
    if cache then return cache end
    cache = {}
    for k, v in pairs(saved() or {}) do
        local pts, p = {}, type(v) == "table" and v.p or {}
        for i = 1, #p - 2, 3 do
            local w = WP(p[i], p[i + 1], p[i + 2])
            if w then pts[#pts + 1] = { w[1], w[2], w[3], p[i], p[i + 1], p[i + 2] } end
        end
        if #pts >= 2 then cache[#cache + 1] = { k = k, pts = pts, c = pts[1][3] } end
    end
    return cache
end

-- un chemin garde finit-il pres de ce point (monde) ?
local function trailEndingNear(g)
    for _, tr in ipairs(trails()) do
        local B = tr.pts[#tr.pts]
        if tr.c == g[3] and Dist(B[1], B[2], g[1], g[2]) <= END_NEAR then return tr end
    end
end

-- Le brouillon devient-il un chemin a proposer ? (boucles retirees, partie tordue seulement, simplifie)
local function buildCandidate(here)
    local pts = {}
    for _, p in ipairs(crumbs) do if p[3] == here[3] then pts[#pts + 1] = p end end
    pts[#pts + 1] = here
    if #pts < 4 then return nil end
    -- 1) boucles : si on repasse pres d'un point deja vu, tout ce qui est entre les deux disparait
    local out, i = {}, 1
    while i <= #pts do
        local p = pts[i]
        out[#out + 1] = p
        local jump
        for j = #pts, i + 2, -1 do
            if Dist(p[1], p[2], pts[j][1], pts[j][2]) < LOOP then jump = j; break end
        end
        i = jump and (jump + 1) or (i + 1)
    end
    if out[#out] ~= here then out[#out + 1] = here end
    local n = #out
    if n < 3 then return nil end
    -- 2) detour : E[k] = longueur marchee de k jusqu'au bout, moins la ligne droite (grandit en remontant)
    local e, L, E = out[n], 0, { [n] = 0 }
    for k = n - 1, 1, -1 do
        L = L + Dist(out[k][1], out[k][2], out[k + 1][1], out[k + 1][2])
        E[k] = L - Dist(out[k][1], out[k][2], e[1], e[2])
    end
    local total = E[1]
    if total < MIN_EXCESS then return nil end
    -- 3) on garde seulement la partie tordue (+ 2 points de marge, ~30 m)
    local start = 1
    for k = n, 1, -1 do if E[k] >= total - 10 then start = k; break end end
    start = math.max(1, start - 2)
    local part, Lt = {}, 0
    for k = start, n do
        part[#part + 1] = out[k]
        if k < n then Lt = Lt + Dist(out[k][1], out[k][2], out[k + 1][1], out[k + 1][2]) end
    end
    if Lt < MIN_RATIO * Dist(part[1][1], part[1][2], e[1], e[2]) then return nil end
    -- 4) simplification (au plus MAX_PTS points)
    local eps, res = 4, nil
    repeat res = simplify(part, eps); eps = eps * 1.5 until #res <= MAX_PTS
    local flat = {}
    for _, p in ipairs(res) do flat[#flat + 1] = p[4]; flat[#flat + 1] = p[5]; flat[#flat + 1] = p[6] end
    return { p = flat, ex = total }
end

local function TrailKeep()
    local t = saved()
    if not (candidate and t) then say(T("trailNone")); return end
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    if n >= MAX_TRAILS and not t[candidate.key] then say(T("trailFull", MAX_TRAILS)); return end
    t[candidate.key] = { p = candidate.p }
    refused()[candidate.key] = nil
    say(T("trailKept", #candidate.p / 3))
    candidate, cache = nil, nil
    lastWP = nil; Refresh(true)
end

-- arrivee a l'objectif de l'etape en cours : proposer de garder le chemin s'il a fait un grand detour
local function checkArrival(here)
    if not (DB and DB.trailAsk ~= false and DB.smartArrow ~= false) then return end
    local s = steps and steps[current]
    if not (s and s.m and s.x and (s.t == "do" or s.t == "turnin" or s.t == "accept")) then return end
    local g = WP(s.m, s.x, s.y)
    if not (g and g[3] == here[3]) then return end
    local key = s.m .. ":" .. s.x .. ":" .. s.y
    if arrived[key] or Dist(here[1], here[2], g[1], g[2]) > (s.t == "do" and 40 or 25) then return end
    arrived[key] = true
    if refused()[key] or trailEndingNear(g) then return end
    local cand = buildCandidate(here)
    if not cand then return end
    cand.key = key
    candidate = cand
    -- v1.43 : « non » seulement si le joueur ferme avec le « x ». Sans reponse (toast efface), on
    -- reproposera a la prochaine seance (arrived[] evite de redemander dans la meme seance).
    Toast(T("trailHead"), T("trailAsk", math.floor(cand.ex)), TrailKeep,
        function() refused()[key] = true end)
end

-- Appele chaque seconde (Window.lua, a cote de LearnGates)
function TrailTick()
    if (UnitOnTaxi and UnitOnTaxi("player")) or (UnitIsDeadOrGhost and UnitIsDeadOrGhost("player")) then TrailBreak(); return end
    if IsInInstance then
        local ok, inst = pcall(IsInInstance)
        if ok and inst then TrailBreak(); return end
    end
    local pm, px, py = PlayerPos()
    if not (pm and px) then return end
    local wx, wy = WorldPos(pm, px, py)
    if not wx then return end
    local c, t = Continent(pm), now()
    -- saut de plus de 60 m par seconde (teleportation, pierre de foyer) : on repart a zero
    if last and (last.c ~= c or Dist(last.wx, last.wy, wx, wy) > 60 * math.max(1, t - last.t)) then TrailBreak() end
    last = { wx = wx, wy = wy, c = c, t = t }
    local here = { wx, wy, c, pm, r1(px), r1(py), t }
    local p = crumbs[#crumbs]
    if not p or Dist(p[1], p[2], wx, wy) >= STEP then crumbs[#crumbs + 1] = here end
    while #crumbs > MAX_CRUMBS or (crumbs[1] and t - crumbs[1][7] > KEEP_SECS) do table.remove(crumbs, 1) end
    checkArrival(here)
end

-- segment du chemin le plus proche de toi (entre lo et hi)
local function nearestSeg(pts, me, lo, hi)
    local bd, bi
    for i = math.max(1, lo), math.min(#pts - 1, hi) do
        local d = perp(me, pts[i], pts[i + 1])
        if not bd or d <= bd then bd, bi = d, i end
    end
    return bd, bi
end

-- distance parcourue sur le chemin depuis son debut jusqu'a toi (tu es sur le segment bi)
local function alongTrail(pts, bi, me)
    local L = 0
    for k = 1, bi - 1 do L = L + Dist(pts[k][1], pts[k][2], pts[k + 1][1], pts[k + 1][2]) end
    -- + ta projection sur le segment bi
    local a, b = pts[bi], pts[bi + 1]
    local dx, dy = b[1] - a[1], b[2] - a[2]
    local l2 = dx * dx + dy * dy
    local t = l2 > 0 and math.max(0, math.min(1, ((me[1] - a[1]) * dx + (me[2] - a[2]) * dy) / l2)) or 0
    return L + t * math.sqrt(l2)
end

-- Point vise par la fleche sur un chemin garde (StepPoint, Near.lua), ou nil
function TrailPoint(s, me)
    if not (s and s.m and s.x and me) then return nil end
    local g = WP(s.m, s.x, s.y)
    local best
    for _, tr in ipairs(trails()) do
        local pts, n = tr.pts, #tr.pts
        if tr.c == me[3] then
            local A, B = pts[1], pts[n]
            local into = g and g[3] == me[3] and Dist(B[1], B[2], g[1], g[2]) <= END_NEAR
            local bd, bi
            local pr = prog[tr.k]
            if pr then bd, bi = nearestSeg(pts, me, pr - 2, pr + 4) end
            if not bd or bd > ON_TRAIL then bd, bi = nearestSeg(pts, me, 1, n - 1) end
            local on = bd and bd <= ON_TRAIL
            prog[tr.k] = on and bi or nil
            local aim
            if into then
                if on then
                    -- sur le chemin : un point ~20 m plus loin vers le bout
                    for k = bi + 1, n do aim = k; if Dist(me[1], me[2], pts[k][1], pts[k][2]) >= AIM then break end end
                    if aim == n and Dist(me[1], me[2], B[1], B[2]) < 12 then aim = nil end
                else
                    -- pas encore dessus : son entree, si elle est plus pres que l'objectif (tu es du mauvais cote)
                    local dA = Dist(me[1], me[2], A[1], A[2])
                    if dA < 500 and dA + 15 < Dist(me[1], me[2], g[1], g[2]) then aim = 1 end
                end
            elseif on and alongTrail(pts, bi, me) > 80 then
                -- le bout de ce chemin ne sert pas a l'etape : on ressort par ou on est entre
                -- (seulement si tu es bien engage dessus : passer pres de l'entree ne detourne pas la fleche)
                for k = bi, 1, -1 do aim = k; if Dist(me[1], me[2], pts[k][1], pts[k][2]) >= AIM then break end end
            end
            if aim then
                local cost = (into and 0 or 100000) + Dist(me[1], me[2], pts[aim][1], pts[aim][2])
                if not best or cost < best.cost then best = { cost = cost, p = pts[aim], out = not into } end
            end
        end
    end
    if best then
        return { m = best.p[4], x = best.p[5], y = best.p[6], name = T(best.out and "trailOut" or "trailIn"), kind = "trail", out = best.out }
    end
end

-- /warpath chemin [garde|efface|liste]
function TrailCmd(arg)
    arg = (arg or ""):lower()
    if arg == "garde" or arg == "keep" then TrailKeep(); return end
    local t = saved()
    if not t then return end
    if arg == "efface" or arg == "clear" or arg == "x" then
        local me = PlayerWP()
        local bestK, bd
        if me then
            for _, tr in ipairs(trails()) do
                if tr.c == me[3] then
                    local d = nearestSeg(tr.pts, me, 1, #tr.pts - 1)
                    if d and d <= 40 and (not bd or d < bd) then bestK, bd = tr.k, d end
                end
            end
        end
        if not bestK then say(T("trailNoneNear")); return end
        t[bestK] = nil
        refused()[bestK] = true        -- ne pas le reproposer au meme endroit
        cache = nil; wipe(prog)
        say(T("trailCleared"))
        lastWP = nil; Refresh(true)
    elseif arg == "liste" or arg == "list" then
        local n = 0
        for _, v in pairs(t) do
            local p = type(v) == "table" and v.p
            if p and #p >= 6 then
                n = n + 1
                say(string.format("  %s %.1f, %.1f  (%d)", MAPNAME[ZoneOf(p[#p - 2])] or tostring(p[#p - 2]), p[#p - 1], p[#p], #p / 3))
            end
        end
        say(n == 0 and T("trailEmpty") or T("trailCount", n))
    else
        say(T("trailHelp"))
    end
end

-- le brouillon repart a zero apres un detour volontaire : cueillette/minage, marchand, entraineur, courrier, vol, mort
do
    local GATHER = {}
    local function gatherNames()
        if next(GATHER) or not (C_Spell and C_Spell.GetSpellName) then return end
        for _, id in ipairs({ 2366, 2368, 3570, 11993, 2575, 2576, 3564, 10248 }) do
            local ok, nm = pcall(C_Spell.GetSpellName, id)
            if ok and type(nm) == "string" then GATHER[nm] = true end
        end
    end
    local f = CreateFrame("Frame")
    for _, e in ipairs({ "MERCHANT_SHOW", "TRAINER_SHOW", "MAIL_SHOW", "TAXIMAP_OPENED", "PLAYER_DEAD" }) do pcall(f.RegisterEvent, f, e) end
    if f.RegisterUnitEvent then pcall(f.RegisterUnitEvent, f, "UNIT_SPELLCAST_SUCCEEDED", "player") end
    f:SetScript("OnEvent", function(_, e, _, _, spellID)
        if e ~= "UNIT_SPELLCAST_SUCCEEDED" then TrailBreak(); return end
        if (issecretvalue and issecretvalue(spellID)) or type(spellID) ~= "number" then return end
        if not (C_Spell and C_Spell.GetSpellName) then return end
        gatherNames()
        local ok, nm = pcall(C_Spell.GetSpellName, spellID)
        if ok and nm and GATHER[nm] then TrailBreak() end
    end)
end
