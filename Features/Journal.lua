-- Oghoule's Warpath : moteur (Journal.lua) - temps de jeu ACTIF et XP, par etape et par guide (local, jamais partage)
-- Le temps ne compte que si tu joues vraiment : en mouvement, en combat, en vol, ou dans les 45 s qui suivent
-- (boire, manger, parler aux PNJ, piller). Il ne compte pas si tu es AFK, si une fenetre de metier est ouverte,
-- ou si tu ne bouges plus depuis 45 s (en ville, a coder, a faire autre chose).
local ADDON, ns = ...
local _ENV = ns.CoreEnv
if setfenv then setfenv(1, _ENV) end
-- v1.50 : etat partage du guide (Core.lua, ns.State)
local State = ns.State
local Core = ns.Mod.Core -- v1.50 : module
local Chronicle = ns.Mod.Chronicle -- v1.50 : module
-- v1.50 : module ns.Mod.Journal (publie en fin de fichier pour les autres fichiers)
local JournalReport
local Est = ns.Mod.Est -- v1.50 : module
-- v1.50 : noms propres a ce fichier (sortis de DECL, Core.lua)
local FmtDur

do
    local TICK, GRACE = 2, 45
    local lastAct, lastXP, lastMax, lastLvl = 0, nil, nil, nil
    local sessA, sessXP = 0, 0
    local sessT0
    -- duree courte et lisible : 12 min, 1 h 05
    function FmtDur(sec)
        sec = math.max(0, math.floor(sec + 0.5))
        if sec < 3600 then return math.max(1, math.floor(sec / 60 + 0.5)) .. " min" end
        return string.format("%d h %02d", math.floor(sec / 3600), math.floor(sec % 3600 / 60))
    end

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
        local k = g .. ":" .. (State.current or 0)
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
        if Chronicle.ChronTick then Chronicle.ChronTick(TICK) end
    end

    -- petite ligne discrete au bas de la fenetre du guide : XP/h actif de la session
    local nTick = 0
    local function line()
        nTick = nTick + 1
        if nTick % 5 ~= 0 then return end
        local fr = f and rawget(f, "xph"); if not fr then return end
        -- v1.41 : le pied n'est plus affiche (infos au survol de la barre de progression) ; on calcule quand meme
        -- les valeurs (f.footInfo) pour l'infobulle
        local want = DB ~= nil
        local lv, ss = rawget(f, "footLvl"), rawget(f, "footSess")
        sessT0 = sessT0 or now()
        local cur, mx = UnitXP and UnitXP("player") or 0, UnitXPMax and UnitXPMax("player") or 1
        local lvl = UnitLevel("player") or 1
        local rate = sessA >= 120 and sessXP * 3600 / sessA or 0
        local wall = now() - sessT0
        local dur = function(sec) return string.format("%d h %02d", math.floor(sec / 3600), math.floor(sec % 3600 / 60)) end
        if want and lv and ss then
            -- pied : niveau | XP/h actif | temps avant le niveau suivant (au rythme actif)
            lv:SetText(T("footLvl", lvl, math.floor((cur or 0) * 100 / math.max(1, mx or 1))))
            -- v1.41 (audit) : sans donnees encore (debut de seance), « calcul… » au lieu de « — XP/h » et « Niv. 25 dans — »
            fr:SetText(rate > 0 and T("footXph", Est.FormatNum(math.floor(rate))) or T("footCalc"))
            local left = (mx or 0) - (cur or 0)
            ss:SetText(rate > 0 and T("footNext", lvl + 1, FmtDur and FmtDur(left / rate * 3600) or (math.floor(left / rate * 60 + 0.5) .. " min")) or "")
            -- detail au survol du pied
            f.footInfo = { rate = rate, active = dur(sessA), wallRate = wall > 60 and sessXP * 3600 / wall or 0, wall = dur(wall), xp = sessXP,
                           lvl = lv:GetText(), xph = fr:GetText(), nxt = ss:GetText() }
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
                if Chronicle.ChronAdd then Chronicle.ChronAdd("xp", d) end
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
    local function rate(xp, a) return (a or 0) > 60 and Est.FormatNum(math.floor(xp * 3600 / a)) or "-" end

    function JournalReport(arg)
        local j = J(); if not j then return end
        if arg == "reset" then DB.jr = nil; sessA, sessXP = 0, 0; say(T("jrReset")); return end
        say(T("jrHead"))
        say(T("jrLine", T("jrSession"), hm(sessA), Est.FormatNum(sessXP), rate(sessXP, sessA)))
        say(T("jrLine", T("jrTotal"), hm(j.a), Est.FormatNum(j.xp), rate(j.xp, j.a)))
        local g = DB.guide and j.g[DB.guide]
        -- v1.50 : titre du guide (avant : G[DB.guide], toujours vide, donc la cle "stv1" s'affichait)
        local gd = Core.Guides and Core.Guides[DB.guide]
        if g then say(T("jrLine", (gd and (Lang and Lang() == "en" and gd.title_en or gd.title)) or DB.guide, hm(g.a), Est.FormatNum(g.xp), rate(g.xp, g.a))) end
        say(T("jrHelp"))
    end
end

-- v1.50 : ce que ce fichier offre aux autres (ns.Mod.Journal)
do
    local M = ns.Mod.Journal
    M.JournalReport = JournalReport
end
