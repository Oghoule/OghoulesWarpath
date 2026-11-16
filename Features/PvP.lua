-- Oghoule's Warpath : moteur (PvP.lua) - trophees de guerre : X rouges sur la carte la ou tu as tue un joueur
-- de l'Alliance, tetes de mort grises la ou l'Alliance t'a tue. Fiche au survol / au clic. Bouton sur la carte.
-- Midnight : pas de journal de combat pour les addons, et certaines infos sont masquees en combat. Donc :
--   - la victoire est detectee par le compteur de victoires honorables (PLAYER_PVP_KILLS_CHANGED) ;
--   - l'ennemi (niveau, classe, race, nom) est memorise quand tu le cibles ou le survoles ;
--   - la difficulte (ta vie restante, la duree) est lue a la fin du combat.
local ADDON, ns = ...
local _ENV = ns.CoreEnv
if setfenv then setfenv(1, _ENV) end

do
    local function L(fr, en) return (Lang and Lang() == "en") and en or fr end
    local function ok(v) return v ~= nil and not (issecretvalue and issecretvalue(v)) end
    local function now() return GetTime and GetTime() or 0 end
    local function P()
        if not DB then return nil end
        DB.pvp = DB.pvp or { k = {}, d = {} }
        return DB.pvp
    end
    local function shown() return not (WarpathDropDB and WarpathDropDB._pvpShow == false) end

    -- ---------------------------------------------------------------- ennemis vus (cible, survol, focus)
    local seen, lastEnemy = {}, nil
    local function note(unit)
        if not (UnitExists and UnitExists(unit) and UnitIsPlayer(unit)) then return end
        local okE, enemy = pcall(UnitIsEnemy, "player", unit)
        if not (okE and ok(enemy) and enemy) then return end
        local g = UnitGUID and UnitGUID(unit); if not ok(g) then g = unit end
        local e = seen[g] or {}
        local lvl = UnitLevel(unit); if ok(lvl) then e.lvl = lvl end
        local cl, tok = UnitClass(unit); if ok(cl) then e.cl, e.ct = cl, tok end
        local rc = UnitRace(unit); if ok(rc) then e.rc = rc end
        local nm = UnitName(unit); if ok(nm) then e.nm = nm end
        e.t = now(); seen[g] = e; lastEnemy = e
        if UnitAffectingCombat and UnitAffectingCombat("player") then e.fight = now() end -- vu pendant un combat
    end
    local function recentEnemy(maxAge)
        if UnitExists and UnitExists("target") and UnitIsPlayer("target") then
            local g = UnitGUID("target"); if ok(g) and seen[g] then return seen[g] end
        end
        if lastEnemy and now() - (lastEnemy.t or 0) <= (maxAge or 30) then return lastEnemy end
    end

    -- ---------------------------------------------------------------- combats et victoires
    local fightStart, pending = nil, {}
    local function here()
        if not PlayerPos then return nil end
        local m, x, y = PlayerPos()
        if not m then return nil end
        return m, math.floor(x * 10) / 10, math.floor(y * 10) / 10
    end
    local function zoneName(m)
        local i = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(m)
        return i and i.name or (GetZoneText and GetZoneText()) or "?"
    end
    local function stamp() return date and date("%Y-%m-%d %H:%M") or "" end
    local function finish()
        if #pending == 0 then return end
        local hp, mx = UnitHealth("player"), UnitHealthMax("player")
        local pct = (ok(hp) and ok(mx) and mx > 0) and math.floor(hp * 100 / mx) or nil
        local dur = fightStart and math.floor(now() - fightStart) or nil
        for _, e in ipairs(pending) do e.hp, e.dur = pct, dur end
        wipe(pending)
    end
    local MAXREC = 300
    local function inPvPInstance()
        if not IsInInstance then return false end
        local inI, kind = IsInInstance()
        return inI and (kind == "pvp" or kind == "arena")
    end
    local function trim(t) while #t > MAXREC do table.remove(t, 1) end end
    local function onKill()
        if inPvPInstance() then return end     -- champs de bataille : des dizaines de victoires d'equipe, pas des trophees
        local p = P(); if not p then return end
        local m, x, y = here(); if not m then return end
        local en = recentEnemy(30) or {}
        local e = { m = m, x = x, y = y, z = zoneName(m), when = stamp(), me = UnitLevel("player"),
                    lvl = en.lvl, cl = en.cl, ct = en.ct, rc = en.rc, nm = en.nm }
        table.insert(p.k, e); trim(p.k)
        pending[#pending + 1] = e
        if not (UnitAffectingCombat and UnitAffectingCombat("player")) then finish() end
        if DB.pvpShot and Screenshot and C_Timer then C_Timer.After(0.3, function() pcall(Screenshot) end) end
        say(L("|cffc24a3eVictoire !|r Un X rouge marque l'endroit sur ta carte.", "|cffc24a3eVictory!|r A red X marks the spot on your map."))
        if WarpathPvPRefresh then WarpathPvPRefresh() end
    end
    local function onDeath()
        if inPvPInstance() then return end
        local p = P(); if not p then return end
        -- seulement si un joueur ennemi etait cible ou vu PENDANT un combat dans les 15 dernieres secondes
        -- (sinon c'est probablement un monstre qui t'a tue : on n'invente pas de tete de mort)
        local en = recentEnemy(15)
        if not (en and en.fight and now() - en.fight <= 15) then return end
        local m, x, y = here(); if not m then return end
        table.insert(p.d, { m = m, x = x, y = y, z = zoneName(m), when = stamp(), me = UnitLevel("player"),
                            lvl = en.lvl, cl = en.cl, ct = en.ct, rc = en.rc, nm = en.nm })
        trim(p.d)
        if WarpathPvPRefresh then WarpathPvPRefresh() end
    end

    local f = CreateFrame("Frame")
    for _, e in ipairs({ "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT", "PLAYER_FOCUS_CHANGED", "PLAYER_REGEN_DISABLED",
                         "PLAYER_REGEN_ENABLED", "PLAYER_PVP_KILLS_CHANGED", "PLAYER_DEAD" }) do pcall(f.RegisterEvent, f, e) end
    f:SetScript("OnEvent", function(_, e)
        if not DB then return end
        if e == "PLAYER_TARGET_CHANGED" then note("target")
        elseif e == "UPDATE_MOUSEOVER_UNIT" then note("mouseover")
        elseif e == "PLAYER_FOCUS_CHANGED" then note("focus")
        elseif e == "PLAYER_REGEN_DISABLED" then fightStart = now(); note("target")
        elseif e == "PLAYER_REGEN_ENABLED" then finish(); fightStart = nil
        elseif e == "PLAYER_PVP_KILLS_CHANGED" then onKill()
        elseif e == "PLAYER_DEAD" then onDeath() end
    end)

    -- ---------------------------------------------------------------- fiche
    local function diff(e)
        if not e.hp then return L("difficulté inconnue", "unknown difficulty") end
        if e.hp > 60 then return L("|cff9cc7a8facile|r", "|cff9cc7a8easy|r") end
        if e.hp >= 20 then return L("|cffd6b866serré|r", "|cffd6b866close|r") end
        return L("|cffc24a3ede justesse|r", "|cffc24a3ebarely|r")
    end
    local function who(e)
        if not (e.lvl or e.cl) then return L("ennemi inconnu (jamais ciblé)", "unknown enemy (never targeted)") end
        local c = e.ct and RAID_CLASS_COLORS and RAID_CLASS_COLORS[e.ct]
        local cls = e.cl and (c and ("|c" .. (c.colorStr or "ffffffff") .. e.cl .. "|r") or e.cl) or "?"
        return string.format("%s %s %s%s", L("niveau", "level") .. " " .. ((e.lvl and e.lvl > 0) and e.lvl or "??"),
            e.rc or "", cls, e.nm and (" (" .. e.nm .. ")") or "")
    end
    local function tooltip(owner, list, death)
        Tip():SetOwner(owner, "ANCHOR_RIGHT")
        local hc = death and COL.soft or { 0.76, 0.29, 0.24 }
        Tip():AddLine(Caps(death and L("Tué par l'Alliance", "Killed by the Alliance") or L("Victoire sur l'Alliance", "Victory over the Alliance")), hc[1], hc[2], hc[3])
        if #list > 1 then Tip():AddLine(string.format(death and L("%d morts ici", "%d deaths here") or L("%d victoires ici", "%d victories here"), #list), COL.accent[1], COL.accent[2], COL.accent[3]) end
        for i = #list, math.max(1, #list - 3), -1 do
            local e = list[i]
            Tip():AddLine(" ")
            Tip():AddLine(e.when .. " - " .. (e.z or ""), COL.gold[1], COL.gold[2], COL.gold[3])
            Tip():AddLine(who(e), COL.white[1], COL.white[2], COL.white[3])
            if not death then
                Tip():AddLine(string.format(L("Toi : niveau %s. Combat %s%s.", "You: level %s. Fight %s%s."), e.me or "?", diff(e),
                    (e.hp and string.format(L(", %d%% de vie", ", %d%% health"), e.hp) or "") .. (e.dur and string.format(L(", %d s", ", %d s"), e.dur) or "")), COL.soft[1], COL.soft[2], COL.soft[3], true)
            else
                Tip():AddLine(string.format(L("Toi : niveau %s.", "You: level %s."), e.me or "?"), COL.soft[1], COL.soft[2], COL.soft[3])
            end
        end
        Tip():Show()
    end

    -- ---------------------------------------------------------------- epingles sur la carte du monde
    local pins, used, lastKey = {}, 0, nil
    local function pin(i)
        local b = pins[i]
        if not b then
            local child = WorldMapFrame.ScrollContainer.Child
            b = CreateFrame("Button", nil, child)
            b:SetSize(18, 18); b:SetFrameStrata("HIGH")
            b.x = {}
            for k, spec in ipairs({ { 0, 0, 0, 0.9, 4, "ARTWORK" }, { 0.76, 0.29, 0.24, 1, 2, "OVERLAY" } }) do
                for _, ang in ipairs({ 45, -45 }) do
                    local t = b:CreateTexture(nil, spec[6]); t:SetColorTexture(spec[1], spec[2], spec[3], spec[4])
                    t:SetSize(18, spec[5]); t:SetPoint("CENTER"); if t.SetRotation then t:SetRotation(math.rad(ang)) end
                    b.x[#b.x + 1] = t
                end
            end
            b.tex = b:CreateTexture(nil, "OVERLAY"); b.tex:SetAllPoints()
            b.n = FS(b, 9, COL.accent, FONT, "LEFT"); b.n:SetPoint("BOTTOMLEFT", b, "BOTTOMRIGHT", -2, -2)
            b:SetScript("OnEnter", function(self) tooltip(self, self.list, self.death) end)
            b:SetScript("OnLeave", function() Tip():Hide() end)
            b:SetScript("OnClick", function(self) tooltip(self, self.list, self.death) end)
            pins[i] = b
        end
        return b
    end
    local function group(list, m)
        local cells, out = {}, {}
        for _, e in ipairs(list) do
            if e.m == m then
                local k = math.floor(e.x / 2) .. ":" .. math.floor(e.y / 2) -- regroupe ce qui est a moins de ~2 % de la carte
                if not cells[k] then cells[k] = { x = e.x, y = e.y }; out[#out + 1] = cells[k] end
                table.insert(cells[k], e)
            end
        end
        return out
    end
    function WarpathPvPRefresh(force)
        if not (WorldMapFrame and WorldMapFrame:IsShown() and WorldMapFrame.ScrollContainer) then return end
        local child = WorldMapFrame.ScrollContainer.Child
        local m = WorldMapFrame:GetMapID()
        local cs = child:GetScale() or 1
        local key = tostring(m) .. ":" .. string.format("%.3f", cs) .. ":" .. tostring(shown())
        if not force and key == lastKey then return end
        lastKey = key
        for i = 1, used do pins[i]:Hide() end
        used = 0
        local p = P(); if not (p and shown()) then return end
        local w, h = child:GetWidth(), child:GetHeight()
        for pass = 1, 2 do
            local death = pass == 2
            for _, c in ipairs(group(death and p.d or p.k, m)) do
                used = used + 1
                local b = pin(used)
                b.list, b.death = c, death
                b.tex:SetShown(death)
                for _, t in ipairs(b.x) do t:SetShown(not death) end
                if death then
                    b.tex:SetTexture("Interface\\TargetingFrame\\UI-TargetingFrame-Skull"); b.tex:SetDesaturated(true)
                    b.tex:SetVertexColor(COL.soft[1], COL.soft[2], COL.soft[3], 0.85)
                end
                b.n:SetText(#c > 1 and #c or "")
                local sz = (#c > 1) and 22 or 18
                b:SetSize(sz, sz)
                b:SetScale(1 / cs)
                b:ClearAllPoints()
                b:SetPoint("CENTER", child, "TOPLEFT", c.x / 100 * w * cs, -c.y / 100 * h * cs)
                b:Show()
            end
        end
    end

    local function setup()
        if not (WorldMapFrame and WorldMapFrame.ScrollContainer) or WorldMapFrame._warpathPvP then return end
        WorldMapFrame._warpathPvP = true
        local cb = CreateFrame("Button", nil, WorldMapFrame.ScrollContainer)
        cb:SetSize(170, 22); cb:SetPoint("BOTTOMLEFT", 8, 8); cb:SetFrameStrata("HIGH")
        local bg = Tex(cb, COL.bg, 0.88, "BACKGROUND"); bg:SetAllPoints()
        for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
            local t = Tex(cb, COL.line)
            if side == "TOP" or side == "BOTTOM" then t:SetHeight(1); t:SetPoint(side .. "LEFT"); t:SetPoint(side .. "RIGHT")
            else t:SetWidth(1); t:SetPoint("TOP" .. side); t:SetPoint("BOTTOM" .. side) end
        end
        local hl = Tex(cb, COL.accent, 0.10, "HIGHLIGHT"); hl:SetAllPoints()
        local gem = Diamond(cb, 8, COL.red); gem:SetPoint("LEFT", 6, 0)
        local lbl = FS(cb, 9, COL.gold, FONT, "LEFT"); lbl:SetPoint("LEFT", gem, "RIGHT", 4, 0)
        -- le libelle est remis a chaque affichage de la carte : il suit la langue choisie dans les options
        local function label()
            lbl:SetText(Caps(L("Trophées de guerre", "War Trophies")))
            cb:SetWidth(math.max(120, (lbl:GetStringWidth() or 150) + 28))
        end
        label()
        local function sync() label(); local on = shown(); gem:SetStyle(on and COL.red or COL.line, not on); lbl:SetTextColor((on and COL.gold or COL.faint)[1], (on and COL.gold or COL.faint)[2], (on and COL.gold or COL.faint)[3]) end
        cb.SetChecked = function() sync() end
        cb:SetScript("OnClick", function()
            if WarpathDropDB then WarpathDropDB._pvpShow = not shown() end
            sync(); WarpathPvPRefresh(true)
        end)
        sync()
        cb:SetScript("OnEnter", function(self)
            Tip():SetOwner(self, "ANCHOR_RIGHT")
            Tip():AddLine(L("X rouges : tes victoires sur l'Alliance. Têtes grises : là où l'Alliance t'a tué.", "Red X: your victories over the Alliance. Grey skulls: where the Alliance killed you."), COL.white[1], COL.white[2], COL.white[3], true)
            Tip():Show()
        end)
        cb:SetScript("OnLeave", function() Tip():Hide() end)
        WorldMapFrame:HookScript("OnShow", function() cb:SetChecked(shown()); WarpathPvPRefresh(true) end)
        local acc = 0
        WorldMapFrame:HookScript("OnUpdate", function(_, el)
            acc = acc + el; if acc < 0.2 then return end; acc = 0
            WarpathPvPRefresh()
        end)
    end
    if WorldMapFrame then setup()
    elseif C_Timer then C_Timer.After(2, setup) end

    -- ---------------------------------------------------------------- commande /warpath pvp
    function PvPReport(arg)
        local p = P(); if not p then return end
        arg = (arg or ""):lower()
        if arg == "photo on" or arg == "photo off" or arg == "shot on" or arg == "shot off" then
            DB.pvpShot = arg:find("on") and true or false
            say(DB.pvpShot and L("Capture d'écran automatique à chaque victoire : activée.", "Automatic screenshot on each victory: on.")
                or L("Capture d'écran automatique : désactivée.", "Automatic screenshot: off."))
        elseif arg == "test" then
            note("target")
            local e = recentEnemy(600)
            say(e and (L("Ennemi capté : ", "Enemy captured: ") .. who(e)) or L("Aucun joueur ennemi capté (cible-en un).", "No enemy player captured (target one)."))
        elseif arg == "clear" then
            DB.pvp = nil; WarpathPvPRefresh(true); say(L("Victoires et morts PvP effacées.", "PvP victories and deaths cleared."))
        else
            say(string.format(L("Trophées de guerre : %d victoire(s), %d mort(s) face à l'Alliance.", "War Trophies: %d victory(ies), %d death(s) against the Alliance."), #p.k, #p.d))
            for i = #p.k, math.max(1, #p.k - 4), -1 do local e = p.k[i]; say("  " .. e.when .. " - " .. (e.z or "") .. " : " .. who(e) .. ", " .. diff(e)) end
            say(L("/warpath pvp photo on|off, /warpath pvp test, /warpath pvp clear", "/warpath pvp shot on|off, /warpath pvp test, /warpath pvp clear"))
        end
    end
end
