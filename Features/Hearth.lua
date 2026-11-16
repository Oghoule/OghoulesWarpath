-- Oghoule's Warpath : moteur (Hearth.lua) - pierre de foyer strategique + journal de quetes plein, voir Core.lua
local ADDON, ns = ...
local _ENV = ns.CoreEnv
if setfenv then setfenv(1, _ENV) end

-- Un seul conseil a la fois sous l'etape (le plus utile d'abord) :
--   1. journal presque plein (Forever : 40 quetes max) -> quoi abandonner
--   2. pierre de foyer : l'utiliser maintenant / la garder pour plus tard / attendre qu'elle revienne
--   3. lier la pierre a l'auberge ou tu es, si le guide revient souvent pres d'ici
do
    local HS_ITEM, HS_SPELL = 6948, 8690
    local LOG_MAX, LOG_WARN = 40, 37
    local HS_COST = 25                  -- secondes : incantation (10 s) + ecran de chargement
    local MIN_GAIN = 120                -- on ne conseille rien sous 2 minutes gagnees
    local LOOK = 150                    -- etapes regardees en avance au plus (on s'arrete apres une recharge complete)
    local SMALL = 300                   -- gain "petit" (moins de 5 min) : on la garde des qu'un usage aussi bon arrive dans l'heure
    local cache = { key = nil, adv = nil }
    local hearthCast

    local function Now() return GetTime and GetTime() or 0 end

    -- ou est liee la pierre : apprise en jeu (lien ou retour par la pierre), sinon devinee par le nom de l'auberge
    function HearthPos()
        local name = GetBindLocation and GetBindLocation()
        local h = DB.hearth
        if h and h.m and (not name or h.name == name) then return h end
        if name then
            for _, inn in ipairs(ns.Inns or {}) do
                if inn.m and (inn.bind == name or (inn.alias and inn.alias[name])) then
                    return { m = inn.m, x = inn.x, y = inn.y, name = name, inn = inn.id }
                end
            end
        end
    end

    -- temps de recharge restant (secondes), duree totale ; nil si tu n'as pas de pierre
    function HearthCD()
        local count = (C_Item and C_Item.GetItemCount and C_Item.GetItemCount(HS_ITEM)) or (GetItemCount and GetItemCount(HS_ITEM)) or 0
        if not count or count == 0 then return nil end
        local start, dur
        if C_Container and C_Container.GetItemCooldown then start, dur = C_Container.GetItemCooldown(HS_ITEM)
        elseif GetItemCooldown then start, dur = GetItemCooldown(HS_ITEM) end
        if dur and dur > 60 then DB.hearthLen = dur end
        local len = DB.hearthLen or 3600
        if not start or start == 0 or not dur or dur <= 1.5 then return 0, len end
        return math.max(0, start + dur - Now()), len
    end

    local function Known() return KnownFlights() end

    -- positions des prochaines etapes, avec le temps estime pour y arriver
    local function Upcoming(i, from, horizon)
        local out, eta, prev = {}, 0, from
        local known = Known()
        for j = i, math.min(#steps, i + LOOK) do
            local s = steps[j]
            if s and Applies(s) and not doneCache[j] and s.m and s.x then
                local w = WP(s.m, s.x, s.y)
                if w then
                    local c = prev and TravelCost(prev, w, known)
                    if c then eta = eta + c / RUN end
                    out[#out + 1] = { j = j, w = w, s = s, leg = c, eta = eta }
                    eta = eta + (s.t == "do" and 150 or 15)
                    prev = w
                    if horizon and eta > horizon then break end
                end
            end
        end
        return out
    end

    -- ce que la pierre ferait gagner (secondes) sur un trajet a -> b
    local function Gain(H, a, b, known)
        if not (H and a and b) then return 0 end
        local normal = TravelCost(a, b, known)
        local via = TravelCost(H, b, known)
        if not normal or not via then return 0 end
        return (normal - via) / RUN - HS_COST
    end

    -- valeur d'une auberge sur la suite du guide : les meilleurs gains, un par recharge
    local function InnValue(H, up, len)
        if not H then return 0 end
        local known, gains, prev = Known(), {}, nil
        for _, u in ipairs(up) do
            if prev then
                local g = Gain(H, prev, u.w, known)
                if g > MIN_GAIN then gains[#gains + 1] = g end
            end
            prev = u.w
        end
        table.sort(gains, function(a, b) return a > b end)
        local total = up[#up] and up[#up].eta or 0
        local k = 1 + math.floor(total / len)
        local v = 0
        for n = 1, math.min(k, #gains) do v = v + gains[n] end
        return v
    end

    local function LogAdvice(i)
        local n, ids = 0, {}
        for id, v in pairs(logById) do if v ~= nil then n = n + 1; ids[#ids + 1] = id end end
        if n < LOG_WARN then return nil end
        -- quetes encore utiles pour la suite du guide
        local needed = {}
        for j = i, #steps do
            local s = steps[j]
            if s and not doneCache[j] then for _, id in ipairs(Ids(s)) do needed[id] = true end end
        end
        local me = UnitLevel("player") or 1
        local cand = {}
        for _, id in ipairs(ids) do
            if not needed[id] and logById[id] == false then
                local e = EST[id]
                local grey = e and e.l and e.l < me - GreenRange(me)
                cand[#cand + 1] = { id = id, name = QuestTitle(id) or (e and e.n) or ("#" .. id), grey = grey }
            end
        end
        table.sort(cand, function(a, b) if a.grey ~= b.grey then return a.grey and true or false end return a.name < b.name end)
        local names = {}
        for k = 1, math.min(3, #cand) do names[#names + 1] = cand[k].name .. (cand[k].grey and (" (" .. T("grey") .. ")") or "") end
        return { kind = "log", icon = "Interface\\GossipFrame\\AvailableQuestIcon",
                 text = T(n >= LOG_MAX and "logFull" or "logNear", n, LOG_MAX)
                     .. (#names > 0 and ("  " .. T("logDrop", table.concat(names, ", "))) or "") }
    end

    -- objets de quete qui s'achetent : rappel quand tu passes pres d'un marchand qui les vend,
    -- et alerte si l'etape en cours en a besoin et qu'ils manquent
    local SHOP_LOOK = 60
    local function Have(item)
        return (C_Item and C_Item.GetItemCount and C_Item.GetItemCount(item)) or (GetItemCount and GetItemCount(item)) or 0
    end
    local function ShopAdvice(i)
        local here = PlayerWP()
        if not here or not ns.Vendors then return nil end
        local seen = {}
        for j = i, math.min(#steps, i + SHOP_LOOK) do
            local s = steps[j]
            if s and Applies(s) and not doneCache[j] and (s.t == "accept" or s.t == "do" or s.t == "turnin") then
                for _, q in ipairs(Ids(s)) do
                    local e = EST[q]
                    for _, b in ipairs((e and e.b) or {}) do
                        local item, need, name = b[1], b[2], b[3]
                        local miss = need - Have(item)
                        if not seen[item] and miss > 0 and not Rendue(q) then
                            seen[item] = true
                            local best, bestD
                            for k = 4, #b do
                                local v = ns.Vendors[b[k]]
                                local w = v and v[1] and WP(v[1], v[2], v[3])
                                if w and w[3] == here[3] then
                                    local d = Dist(here[1], here[2], w[1], w[2])
                                    if not bestD or d < bestD then best, bestD = b[k], d end
                                end
                            end
                            local vn = best and (ns.NpcNames or {})[best] or "?"
                            if best and bestD < 120 then
                                return { kind = "buy", npc = best, icon = "Interface\\GossipFrame\\VendorGossipIcon",
                                         text = (j == i) and T("buyNow", miss, name, vn) or ((j - i == 1) and T("buyHere1", miss, name, vn, QName(s) or name) or T("buyHere", miss, name, vn, j - i, QName(s) or name)) }
                            elseif j == i and s.t ~= "accept" then
                                local v = best and ns.Vendors[best]
                                return { kind = "buyFar", npc = best, icon = "Interface\\GossipFrame\\VendorGossipIcon",
                                         text = T("buyMissing", miss, name, vn, v and (MAPNAME[v[1]] or "") or "") }
                            end
                        end
                    end
                end
            end
        end
    end

    local function HearthAdvice(i, g)
        if DB.hearthTips == false then return nil end
        if (IsInInstance and IsInInstance()) or (UnitOnTaxi and UnitOnTaxi("player")) then return nil end
        local cd, len = HearthCD()
        if not cd then return nil end
        local here = PlayerWP()
        if not here then return nil end
        local h = HearthPos()
        local H = h and WP(h.m, h.x, h.y)
        local up = Upcoming(i, here, len + 600)
        local known = Known()
        -- 1) lier ici ? (tu es pres d'un aubergiste et cette auberge rapporterait nettement plus)
        for _, inn in ipairs(ns.Inns or {}) do
            local w = inn.m and WP(inn.m, inn.x, inn.y)
            if w and w[3] == here[3] and Dist(here[1], here[2], w[1], w[2]) < 60 and not (h and h.inn == inn.id) then
                local vNew, vCur = InnValue(w, up, len), InnValue(H, up, len)
                if vNew > MIN_GAIN and vNew > vCur + 90 then
                    return { kind = "bind", npc = inn.id, icon = "Interface\\Minimap\\Tracking\\Innkeeper",
                             text = T("hsBind", (ns.NpcNames or {})[inn.id] or "?", math.floor(vNew / 60 + 0.5)) }
                end
            end
        end
        if not H or not g or not g.m or not g.x then return nil end
        local T1 = WP(g.m, g.x, g.y)
        local now = Gain(H, here, T1, known)
        if now < MIN_GAIN then return nil end
        local mins = math.floor(now / 60 + 0.5)
        if cd > 0 then
            -- en recharge : l'attendre vaut-il le coup ?
            if cd < now - MIN_GAIN then
                return { kind = "wait", icon = "Interface\\Icons\\INV_Misc_Rune_01",
                         text = T("hsWait", math.ceil(cd / 60), math.floor((now - cd) / 60 + 0.5)) }
            end
            return nil
        end
        -- pierre prete : si tu l'utilises maintenant, elle ne revient qu'apres une recharge complete (souvent 60 min).
        -- On regarde donc tout ce que le guide prevoit pendant ce temps : le meilleur usage gagne.
        --   petit gain (< 5 min) : on la garde des qu'un usage au moins aussi bon arrive avant son retour
        --   gros gain : on la garde seulement si plus tard rapporte nettement plus (30 %)
        local best, bestU, prev = 0, nil, nil
        for _, u in ipairs(up) do
            if u.eta >= len then break end
            if prev and u.j ~= i then
                local later = Gain(H, prev, u.w, known)
                if later > best then best, bestU = later, u end
            end
            prev = u.w
        end
        local need = (now < SMALL) and now or now * 1.3
        if bestU and best >= MIN_GAIN and best >= need then
            return { kind = "hold", icon = "Interface\\Icons\\INV_Misc_Rune_01",
                     text = T("hsHold", math.floor(best / 60 + 0.5), math.max(1, math.floor(bestU.eta / 60 + 0.5)), QName(bestU.s) or bestU.s.zone or MAPNAME[bestU.s.m] or "?") }
        end
        return { kind = "use", icon = "Interface\\Icons\\INV_Misc_Rune_01", text = T("hsUse", h.name or "?", mins, math.floor(len / 60 + 0.5)) }
    end

    -- appele par l'affichage ; resultat garde quelques secondes (calcul de trajets)
    function Advice(i, g)
        local here = PlayerWP()
        local cd = HearthCD()
        local key = i .. ":" .. (here and (math.floor(here[1] / 40) .. ":" .. math.floor(here[2] / 40)) or "") .. ":"
            .. tostring(cd and cd > 0) .. ":" .. (g and g.m and (g.m .. g.x .. g.y) or "") .. ":" .. tostring(DB.hearthTips)
        if cache.key == key and cache.t and Now() - cache.t < 5 then return cache.adv end
        local ok, adv = pcall(LogAdvice, i)
        if not ok then adv = nil end
        if not adv then ok, adv = pcall(ShopAdvice, i); if not ok then adv = nil end end
        if not adv then ok, adv = pcall(HearthAdvice, i, g); if not ok then adv = nil end end
        cache.key, cache.adv, cache.t = key, adv, Now()
        return adv
    end

    -- apprendre ou est liee la pierre
    local function Learn()
        local m, x, y = PlayerPos and PlayerPos()
        if not m or not x then return end
        local name = GetBindLocation and GetBindLocation()
        local best
        for _, inn in ipairs(ns.Inns or {}) do
            if inn.m == m and Dist(x, y, inn.x, inn.y) < 3 then best = inn.id end
        end
        DB.hearth = { m = m, x = x, y = y, name = name, inn = best }
        cache.key = nil
    end
    local ev = CreateFrame("Frame")
    pcall(ev.RegisterEvent, ev, "HEARTHSTONE_BOUND")
    pcall(ev.RegisterEvent, ev, "UNIT_SPELLCAST_SUCCEEDED")
    ev:RegisterEvent("PLAYER_ENTERING_WORLD")
    ev:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    ev:SetScript("OnEvent", function(_, event, unit, _, spell)
        if not DB then return end
        if event == "HEARTHSTONE_BOUND" then
            pcall(Learn)
        elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
            if unit == "player" and spell == HS_SPELL then hearthCast = Now() end
        elseif hearthCast and Now() - hearthCast < 60 then
            hearthCast = nil
            if C_Timer and C_Timer.After then C_Timer.After(3, function() pcall(Learn) end) else pcall(Learn) end
        end
    end)
    ns.Hearth = { Learn = Learn }
end
