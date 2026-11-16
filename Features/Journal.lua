-- Oghoule's Warpath : moteur (Journal.lua) - temps de jeu ACTIF et XP, par etape et par guide (local, jamais partage)
-- Le temps ne compte que si tu joues vraiment : en mouvement, en combat, en vol, ou dans les 45 s qui suivent
-- (boire, manger, parler aux PNJ, piller). Il ne compte pas si tu es AFK, si une fenetre de metier est ouverte,
-- ou si tu ne bouges plus depuis 45 s (en ville, a coder, a faire autre chose).
local ADDON, ns = ...
local _ENV = ns.CoreEnv
if setfenv then setfenv(1, _ENV) end

do
    local TICK, GRACE = 2, 45
    local lastAct, lastXP, lastMax, lastLvl = 0, nil, nil, nil
    local sessA, sessXP = 0, 0

    local function J()
        if not DB then return nil end
        DB.jr = DB.jr or { a = 0, xp = 0, g = {}, s = {} }
        return DB.jr
    end
    local function now() return GetTime and GetTime() or 0 end
    local function act() lastAct = now() end
    local function crafting()
        local pf = _G.ProfessionsFrame or _G.TradeSkillFrame
        return pf and pf.IsShown and pf:IsShown()
    end
    local function slot()
        local j = J(); if not j then return end
        local g = DB.guide or "?"
        j.g[g] = j.g[g] or { a = 0, xp = 0, l0 = UnitLevel("player") }
        local k = g .. ":" .. (current or 0)
        j.s[k] = j.s[k] or { a = 0, xp = 0 }
        return j, j.g[g], j.s[k]
    end

    local function tick()
        if not DB then return end
        if UnitIsAFK and UnitIsAFK("player") then return end
        if crafting() then return end
        if (GetUnitSpeed and (GetUnitSpeed("player") or 0) > 0) or (UnitAffectingCombat and UnitAffectingCombat("player"))
            or (UnitOnTaxi and UnitOnTaxi("player")) then act() end
        if now() - lastAct > GRACE then return end
        local j, g, s = slot(); if not j then return end
        j.a = j.a + TICK; g.a = g.a + TICK; s.a = s.a + TICK; sessA = sessA + TICK
        g.l1 = UnitLevel("player")
        if ChronTick then ChronTick(TICK) end
    end

    -- petite ligne discrete au bas de la fenetre du guide : XP/h actif de la session
    local nTick = 0
    local function line()
        nTick = nTick + 1
        if nTick % 5 ~= 0 then return end
        local fr = f and rawget(f, "xph"); if not fr then return end
        local want = DB and DB.xphLine ~= false and sessA >= 120
        if want then
            fr:SetText(Caps(T("jrBar", FormatNum(math.floor(sessXP * 3600 / sessA)), string.format("%dh%02d", math.floor(sessA / 3600), math.floor(sessA % 3600 / 60)))))
        end
        if (fr:IsShown() and true or false) ~= (want and true or false) then
            fr:SetShown(want and true or false)
            if Layout then pcall(Layout) end
        end
    end

    local function xpUpdate()
        if not (UnitXP and UnitXPMax and UnitLevel) then return end
        local cur, max, lvl = UnitXP("player") or 0, UnitXPMax("player") or 1, UnitLevel("player") or 1
        if lastXP then
            local d = 0
            if lvl > lastLvl then d = (lastMax - lastXP) + cur elseif lvl == lastLvl then d = cur - lastXP end
            if d > 0 then
                local j, g, s = slot()
                if j then j.xp = j.xp + d; g.xp = g.xp + d; s.xp = s.xp + d; sessXP = sessXP + d end
                if ChronAdd then ChronAdd("xp", d) end
                act()
            end
        end
        lastXP, lastMax, lastLvl = cur, max, lvl
    end

    local f = CreateFrame("Frame")
    for _, e in ipairs({ "PLAYER_XP_UPDATE", "PLAYER_LEVEL_UP", "QUEST_ACCEPTED", "QUEST_TURNED_IN", "LOOT_OPENED",
                         "GOSSIP_SHOW", "QUEST_DETAIL", "QUEST_PROGRESS", "QUEST_COMPLETE", "MERCHANT_SHOW", "TAXIMAP_OPENED",
                         "PLAYER_ENTERING_WORLD" }) do
        pcall(f.RegisterEvent, f, e)
    end
    f:SetScript("OnEvent", function(_, e)
        if not DB then return end
        if e == "PLAYER_XP_UPDATE" or e == "PLAYER_LEVEL_UP" then xpUpdate()
        elseif e == "PLAYER_ENTERING_WORLD" then lastXP = nil; xpUpdate()
        else act() end
    end)
    if C_Timer and C_Timer.NewTicker then C_Timer.NewTicker(TICK, function() tick(); line() end) end

    local function hm(s) s = math.floor(s or 0); return string.format("%dh%02d", math.floor(s / 3600), math.floor(s % 3600 / 60)) end
    local function rate(xp, a) return (a or 0) > 60 and FormatNum(math.floor(xp * 3600 / a)) or "-" end

    function JournalReport(arg)
        local j = J(); if not j then return end
        if arg == "reset" then DB.jr = nil; sessA, sessXP = 0, 0; say(T("jrReset")); return end
        say(T("jrHead"))
        say(T("jrLine", T("jrSession"), hm(sessA), FormatNum(sessXP), rate(sessXP, sessA)))
        say(T("jrLine", T("jrTotal"), hm(j.a), FormatNum(j.xp), rate(j.xp, j.a)))
        local g = DB.guide and j.g[DB.guide]
        if g then say(T("jrLine", (G[DB.guide] and (Lang and Lang() == "en" and G[DB.guide].title_en or G[DB.guide].title)) or DB.guide, hm(g.a), FormatNum(g.xp), rate(g.xp, g.a))) end
        say(T("jrHelp"))
    end
end
