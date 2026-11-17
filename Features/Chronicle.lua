-- Oghoule's Warpath : Chronique de guerre (Chronicle.lua) - resume de ta derniere seance de jeu
-- Une seance = de la connexion a la deconnexion. Un /reload ou une coupure de moins de 15 min ne la coupe pas.
-- A la connexion suivante (pas au /reload), une banniere de quelques secondes resume la seance terminee ;
-- la fenetre complete s'ouvre d'un clic, par le bouton des options ou /warpath chronique.
-- Rien n'est garde si la seance a dure moins de 15 min de jeu actif. Tout reste local (jamais partage).
local ADDON, ns = ...
local _ENV = ns.CoreEnv
if setfenv then setfenv(1, _ENV) end

do
    local GAP, MIN_ACTIVE, KEEP = 15 * 60, 15 * 60, 20
    local function now() return time and time() or 0 end
    local function money() return GetMoney and GetMoney() or 0 end
    local function lvl() return UnitLevel and UnitLevel("player") or 1 end
    local function lvlf()
        local l = lvl()
        local c, m = UnitXP and UnitXP("player") or 0, UnitXPMax and UnitXPMax("player") or 1
        return l + ((m or 0) > 0 and c / m or 0)
    end

    local function New()
        local t = now()
        return { t0 = t, t1 = t, a = 0, xp = 0, q = 0, k = 0, d = 0, pk = 0, pd = 0, dg = {}, lv0 = lvlf(), lv1 = lvlf(),
                 m0 = money(), m1 = money(), z = GetZoneText and GetZoneText() or nil }
    end
    local function S()
        if not DB then return nil end
        DB.chs = DB.chs or New()
        return DB.chs
    end

    -- note : XP/h ramenee a l'XP d'un monstre de ton niveau (= "monstres par heure"), pour comparer les seances
    -- entre elles malgre la montee de niveau
    local function Score(c)
        if (c.a or 0) < 60 then return 0 end
        local l = math.floor(c.lv0 or 1)
        local mob = MobXP and MobXP(l, l, 0) or (5 * l + 45)
        if mob <= 0 then mob = 5 * l + 45 end
        return (c.xp * 3600 / c.a) / mob
    end
    local function Grade(score, hist)
        local base, n = 0, 0
        for i = 1, math.min(#hist, 10) do if hist[i].sc and hist[i].sc > 0 then base = base + hist[i].sc; n = n + 1 end end
        if n >= 2 then base = base / n
        else base = 1.4 * 3600 / ((KillTime and KillTime()) or 22) end   -- sans historique : un peu mieux que le farm pur
        local r = base > 0 and score / base or 1
        return (r >= 1.25 and "S") or (r >= 1.05 and "A") or (r >= 0.85 and "B") or (r >= 0.65 and "C") or "D"
    end
    local function Mentions(c, hist)
        local m = {}
        local best = 0
        for i = 1, #hist do best = math.max(best, hist[i].sc or 0) end
        if #hist >= 3 and (c.sc or 0) > best then m[#m + 1] = "mRecord" end
        if (c.pk or 0) >= 3 then m[#m + 1] = "mBane" end
        if #(c.dg or {}) >= 1 then m[#m + 1] = "mRaider" end
        if (c.lv1 or 0) - (c.lv0 or 0) >= 2 then m[#m + 1] = "mRise" end
        if (c.q or 0) >= 20 then m[#m + 1] = "mQuests" end
        local span = (c.t1 or 0) - (c.t0 or 0)
        if (c.a or 0) >= 1800 and span > 0 and c.a / span >= 0.85 then m[#m + 1] = "mTireless" end
        if (c.d or 0) == 0 and (c.a or 0) >= 3600 then m[#m + 1] = "mUntouch" end
        if (c.d or 0) >= 5 then m[#m + 1] = "mSpirit" end
        if #m == 0 then m[1] = "mDuty" end
        while #m > 2 do table.remove(m) end
        return m
    end

    -- termine la seance en cours (si elle compte) et en ouvre une nouvelle
    local function Close()
        local c = DB.chs
        if c and (c.a or 0) >= MIN_ACTIVE then
            DB.chron = DB.chron or {}
            c.sc = Score(c)
            c.gr = Grade(c.sc, DB.chron)
            c.mt = Mentions(c, DB.chron)
            table.insert(DB.chron, 1, c)
            while #DB.chron > KEEP do table.remove(DB.chron) end
            DB.chronNew = true
        end
        DB.chs = New()
    end

    function ChronAdd(field, n)
        local c = S(); if not c then return end
        c[field] = (c[field] or 0) + (n or 1)
    end
    function ChronDungeon(key)
        local c = S(); if not c then return end
        local name = (Guides[key] and Title(Guides[key])) or key
        for _, v in ipairs(c.dg) do if v == name then return end end
        c.dg[#c.dg + 1] = name
    end
    function ChronTick(secs)
        local c = S(); if not c then return end
        c.a = c.a + secs
    end
    -- a la deconnexion, le jeu peut renvoyer un niveau ou un argent faux : on garde alors les dernieres valeurs
    local function Touch(timeOnly)
        local c = S(); if not c then return end
        c.t1 = now()
        if timeOnly then return end
        local l = lvlf()
        if l >= (c.lv1 or 0) - 0.001 then c.lv1 = l end
        c.m1 = money()
        if (c.z or "") == "" and GetZoneText then c.z = GetZoneText() end
    end

    ------------------------------------------------------------------
    -- affichage
    ------------------------------------------------------------------
    local function hm(s) s = math.floor(s or 0); return string.format("%dh%02d", math.floor(s / 3600), math.floor(s % 3600 / 60)) end
    local function lvTxt(c)
        local d = (c.lv1 or 0) - (c.lv0 or 0)
        return string.format("%+.1f", d):gsub("%.", Lang() == "fr" and "," or ".")
    end
    local function gold(cp)
        cp = math.floor(cp or 0)
        local sign = cp < 0 and "-" or "+"
        cp = math.abs(cp)
        return string.format("%s%d po %d pa", sign, math.floor(cp / 10000), math.floor(cp % 10000 / 100)):gsub("po", T("chGoldG")):gsub("pa", T("chGoldS"))
    end
    local GCOL = { S = "d6b866", A = "9cc7a8", B = "cdbb8e", C = "b5aa98", D = "c24a3e" }

    local function Panel(name, w, h)
        local p = CreateFrame("Frame", name, UIParent)
        p:SetSize(w, h); p:SetFrameStrata("FULLSCREEN_DIALOG"); p:EnableMouse(true); p:SetClampedToScreen(true)
        if p.SetToplevel then p:SetToplevel(true) end
        local bg = Tex(p, COL.bg, 0.97, "BACKGROUND"); bg:SetAllPoints()
        for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
            local t = Tex(p, COL.line)
            if side == "TOP" or side == "BOTTOM" then t:SetHeight(1); t:SetPoint(side .. "LEFT"); t:SetPoint(side .. "RIGHT")
            else t:SetWidth(1); t:SetPoint("TOP" .. side); t:SetPoint("BOTTOM" .. side) end
        end
        return p
    end

    local win, idx
    local function Fill()
        local list = DB.chron or {}
        local c, live = list[idx], false
        if idx == 0 or not c then c, live, idx = S(), true, 0; Touch() end
        win.head:SetText(Caps(T("chTitle")))
        local when = (date and c.t0) and date("%Y-%m-%d %H:%M", c.t0) or ""
        win.sub:SetText(live and T("chLive") or (T("chWhen", when, c.z or "")):gsub(" · $", ""))
        local sc = live and Score(c) or c.sc
        local gr = live and ((c.a or 0) >= 300 and Grade(sc, list) or "-") or c.gr or "-"
        win.grade:SetText("|cff" .. (GCOL[gr] or "cdbb8e") .. gr .. "|r")
        local xph = (c.a or 0) > 60 and math.floor(c.xp * 3600 / c.a) or 0
        local rows = {
            { "chActive", hm(c.a) },
            { "chXP", T("chXPv", FormatNum(c.xp or 0), FormatNum(xph)) },
            { "chLevels", lvTxt(c) },
            { "chQuests", tostring(c.q or 0) },
            { "chKills", tostring(c.k or 0) },
            { "chDungeons", #(c.dg or {}) > 0 and table.concat(c.dg, ", ") or "-" },
            { "chPvP", T("chPvPv", c.pk or 0, c.pd or 0) },
            { "chDeaths", tostring(c.d or 0) },
            { "chMoney", gold((c.m1 or 0) - (c.m0 or 0)) },
        }
        local out = {}
        for _, r in ipairs(rows) do out[#out + 1] = "|cff" .. HEX.faint .. T(r[1]) .. "|r   " .. r[2] end
        win.body:SetText(table.concat(out, "\n"))
        local mt = live and Mentions(c, list) or c.mt or {}
        local ms = {}
        for _, k in ipairs(mt) do ms[#ms + 1] = "|cff" .. HEX.accent .. Upper(T(k)) .. "|r\n|cff" .. HEX.soft .. T(k .. "D") .. "|r" end
        win.ment:SetText(table.concat(ms, "\n\n"))
        win.prev:SetEnabled(list[idx + 1] ~= nil)
        win.next:SetEnabled(idx > 0)
        win.count:SetText(live and "" or (idx .. " / " .. #list))
    end
    local function Create()
        if win then return end
        win = Panel("WarpathChronicle", 380, 420)
        win:SetPoint("CENTER", 0, 40); win:SetMovable(true); win:RegisterForDrag("LeftButton")
        win:SetScript("OnDragStart", win.StartMoving); win:SetScript("OnDragStop", win.StopMovingOrSizing)
        win.head = FS(win, 11, COL.gold, FONT, "CENTER"); win.head:SetPoint("TOP", 0, -14)
        win.rule = Divider(win, 340); win.rule:SetPoint("TOP", win.head, "BOTTOM", 0, -6)
        win.sub = FS(win, 10, COL.soft, FONT, "CENTER"); win.sub:SetPoint("TOP", win.rule, "BOTTOM", 0, -6)
        win.grade = FS(win, 44, COL.accent, DISPLAY, "CENTER"); win.grade:SetPoint("TOPRIGHT", -26, -64)
        win.glabel = FS(win, 9, COL.faint, FONT, "CENTER"); win.glabel:SetPoint("TOP", win.grade, "BOTTOM", 0, -2)
        win.body = FS(win, 12, COL.white, FONT, "LEFT"); win.body:SetPoint("TOPLEFT", 22, -66); win.body:SetWidth(250)
        if win.body.SetSpacing then win.body:SetSpacing(4) end
        win.ment = FS(win, 11, COL.white, FONT, "LEFT"); win.ment:SetPoint("TOPLEFT", win.body, "BOTTOMLEFT", 0, -18); win.ment:SetWidth(336)
        win.prev = FlatButton(win, 40, 22, function() idx = idx + 1; Fill() end); win.prev:SetPoint("BOTTOMLEFT", 18, 14); win.prev:SetLabel("<")
        win.next = FlatButton(win, 40, 22, function() idx = math.max(0, idx - 1); Fill() end); win.next:SetPoint("LEFT", win.prev, "RIGHT", 6, 0); win.next:SetLabel(">")
        win.count = FS(win, 10, COL.faint, FONT, "LEFT"); win.count:SetPoint("LEFT", win.next, "RIGHT", 8, 0)
        win.close = FlatButton(win, 110, 22, function() win:Hide() end); win.close:SetPoint("BOTTOMRIGHT", -18, 14)
        if UISpecialFrames then table.insert(UISpecialFrames, "WarpathChronicle") end
        win:Hide()
    end
    -- k : 1 = derniere seance terminee (defaut), 0 = seance en cours
    function ChronShow(k)
        if not DB then return end
        Create()
        idx = k or ((DB.chron and DB.chron[1]) and 1 or 0)
        win.glabel:SetText(Caps(T("chGrade"))); win.close:SetLabel(Caps(T("chClose")))
        Fill(); win:Show(); if win.Raise then win:Raise() end
        DB.chronNew = nil
    end

    local banner
    local function Banner()
        local c = DB.chron and DB.chron[1]
        if not c then return end
        if not banner then
            banner = Panel("WarpathChronBanner", 380, 52)
            banner:SetPoint("TOP", UIParent, "TOP", 0, -110)
            banner.l1 = FS(banner, 9, COL.gold, FONT, "LEFT"); banner.l1:SetPoint("TOPLEFT", 14, -10)
            banner.l2 = FS(banner, 12, COL.white, FONT, "LEFT"); banner.l2:SetPoint("TOPLEFT", banner.l1, "BOTTOMLEFT", 0, -6); banner.l2:SetWidth(270)
            banner.btn = FlatButton(banner, 70, 22, function() banner:Hide(); ChronShow(1) end)
            banner.btn:SetPoint("RIGHT", -12, 0)
            banner:SetScript("OnMouseUp", function() banner:Hide(); ChronShow(1) end)
            banner:SetScript("OnLeave", function() if banner.expired and not (banner.IsMouseOver and banner:IsMouseOver()) then banner:Hide() end end)
        end
        banner.l1:SetText(Caps(T("chBanner")))
        local m = c.mt and c.mt[1] and T(c.mt[1]) or ""
        banner.l2:SetText(T("chBannerLine", hm(c.a), lvTxt(c), "|cff" .. (GCOL[c.gr] or "cdbb8e") .. (c.gr or "-") .. "|r", m))
        banner.btn:SetLabel(Caps(T("chView")))
        banner:SetAlpha(1); banner.expired = false; banner:Show()
        DB.chronNew = nil
        if C_Timer and C_Timer.After then
            C_Timer.After(10, function()
                banner.expired = true
                if banner:IsShown() and not (banner.IsMouseOver and banner:IsMouseOver()) then banner:Hide() end
            end)
        end
    end

    ------------------------------------------------------------------
    -- evenements
    ------------------------------------------------------------------
    local killPat
    local function isKill(msg)
        if not killPat then
            local tpl = _G.COMBATLOG_XPGAIN_FIRSTPERSON
            if type(tpl) == "string" then
                local head = tpl:match("^(.-)%%d") or tpl
                head = head:gsub("([%(%)%.%+%-%*%?%[%]%^%$%%])", "%%%1"):gsub("%%%%s", ".+")
                killPat = "^" .. head
            else killPat = false end
        end
        if killPat == false then return false end
        return type(msg) == "string" and msg:find(killPat) ~= nil
    end

    local fr = CreateFrame("Frame")
    for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_LOGOUT", "QUEST_TURNED_IN", "PLAYER_DEAD", "CHAT_MSG_COMBAT_XP_GAIN",
                         "PLAYER_LEVEL_UP", "PLAYER_MONEY" }) do pcall(fr.RegisterEvent, fr, e) end
    fr:SetScript("OnEvent", function(_, e, a1, a2)
        if not DB then return end
        if e == "PLAYER_ENTERING_WORLD" then
            local login, reload = a1, a2
            local c = S()
            if login and not reload and now() - (c.t1 or 0) > GAP then Close() end
            if (c.lv1 or 0) < (c.lv0 or 0) then c.lv1 = c.lv0 end
            Touch()
            if login and not reload and DB.chronNew and DB.chronBanner ~= false and DB.chron and DB.chron[1] then
                if C_Timer and C_Timer.After then C_Timer.After(6, function() pcall(Banner) end) else pcall(Banner) end
            end
        elseif e == "PLAYER_LOGOUT" then Touch(true)
        elseif e == "QUEST_TURNED_IN" then ChronAdd("q")
        elseif e == "PLAYER_DEAD" then
            local inI, kind = false, nil
            if IsInInstance then inI, kind = IsInInstance() end
            if not (inI and (kind == "pvp" or kind == "arena")) then ChronAdd("d") end
        elseif e == "CHAT_MSG_COMBAT_XP_GAIN" then if isKill(a1) then ChronAdd("k") end
        else Touch() end
    end)
    if C_Timer and C_Timer.NewTicker then C_Timer.NewTicker(30, function() if DB then Touch() end end) end
end
