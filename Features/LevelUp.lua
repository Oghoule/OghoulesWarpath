-- Oghoule's Warpath : bilan de chaque niveau et cinematique de montee de niveau (LevelUp.lua)
-- Pendant chaque niveau, note d'ou vient l'XP : monstres (par nom), quetes (la meilleure), donjons (par nom),
-- exploration, le reste ; plus le temps actif (donne par Journal.lua), le temps reel et les morts.
-- A la montee de niveau, le bilan est range dans DB.lvh[niveau termine] (DB.lvc = niveau en cours), puis une
-- cinematique de quelques secondes le montre (bandes noires haut et bas, le jeu au milieu, les stats a gauche,
-- ton perso en 3D sans fond qui fait « flex », un titre selon ce
-- qui a ete le plus marquant). Elle attend la fin du combat ; un clic la ferme ; DB.lvupShow = false la coupe.
-- Purement visuel : aucune fonction protegee. /warpath niveau [n] = bilan ; /warpath apercu niveau = cinematique.
-- Tout reste local (jamais partage).
local ADDON, ns = ...
local State = ns.State
local Core = ns.Mod.Core
local Est = ns.Mod.Est
local Skin = ns.Mod.Skin
-- module ns.Mod.LevelUp (publie en fin de fichier)
local LvCurrent, LvGet, LvTick, LvReport, LvPreview

do
    local KEEP_MOBS = 8
    -- reglages du titre (a ajuster en jeu)
    local GRAVE, SLAYER, FAST = 3, 8, 1.3      -- morts, tues d'une meme famille, rythme x habituel
    local HOLD, FADE = 4.2, 0.6                -- duree de la cinematique, fondu de sortie
    local FLEX = 82                            -- animation « EmoteFlex » du modele 3D (verifie en jeu)
    local ROAR = 74                            -- animation « EmoteRoar » (/roar), pour le niveau 60 (verifie en jeu)
    local HOLD60 = 10                          -- niveau 60 : plus long (cri, flex, cri)
    local ZOOM, CAMDIST = 0.12, 1.25           -- cadrage du perso (zoom 0 = en pied, 1 = gros plan ; recul de la camera)
    local STATS_EXTRA = 2.5                    -- le bloc de gauche reste ce temps de plus, une fois le perso parti
    local SPLASH_H = 96                        -- hauteur de l'eclaboussure (image 512x128)
    local MAXLVL = 60
    local pending          -- bilan du niveau qui vient de se terminer, rempli encore 1 s (le gain qui a fait monter)
    local queued           -- cinematique en attente de la fin du combat
    local function now() return time and time() or 0 end
    local function lvl() return UnitLevel and UnitLevel("player") or 1 end
    local function xpNow() return UnitXP and UnitXP("player") or 0 end
    local function xpMax() return UnitXPMax and UnitXPMax("player") or 0 end
    local function T(...) return Core.T(...) end

    -- part = commence en cours de niveau (addon installe ou desactive en route) : bilan incomplet
    local function New(part)
        local t, x0 = now(), xpNow()
        return { lv = lvl(), t0 = t, t1 = t, a = 0, xp0 = x0, mx = xpMax(), part = (part and x0 > 0) or nil,
                 k = 0, kxp = 0, q = 0, qxp = 0, ex = 0, d = 0, mob = {}, dg = {} }
    end

    function LvCurrent()
        if pending then return pending end
        if not State.DB then return nil end
        local c = State.DB.lvc
        if not c or c.lv ~= lvl() then c = New(true); State.DB.lvc = c end
        return c
    end
    function LvGet(level) return State.DB and State.DB.lvh and State.DB.lvh[level] end
    function LvTick(secs)
        local c = LvCurrent(); if c then c.a = c.a + secs end
    end

    -- famille d'un monstre : 1er mot en francais (« Loup des prairies »), dernier sinon (« Prairie Wolf »)
    local function Family(name)
        name = tostring(name or "?"):gsub("%b()", ""):gsub("^%s+", ""):gsub("%s+$", "")
        if GetLocale and GetLocale() == "frFR" then return name:match("^(%S+)") or name end
        return name:match("(%S+)$") or name
    end
    -- familles d'un bilan (deja calculees pour un niveau termine, sinon depuis la liste des monstres)
    local function Fams(c)
        if c.fam then return c.fam end
        local fam = {}
        for key, m in pairs(c.mob or {}) do
            local f = Family(m.n or key)
            local e = fam[f] or { k = 0, xp = 0 }
            e.k = e.k + (m.k or 0); e.xp = e.xp + (m.xp or 0)
            fam[f] = e
        end
        return fam
    end

    -- over = XP deja gagnee dans le nouveau niveau (debordement du gain qui a fait monter, compte ici)
    local function Finish(c, over)
        c.t1 = now()
        c.xp = math.max(0, (c.mx or 0) - (c.xp0 or 0) + (over or 0))
        c.oth = math.max(0, c.xp - c.kxp - c.qxp - c.ex)
        c.fam = Fams(c)
        local list = {}
        for n, m in pairs(c.mob or {}) do list[#list + 1] = { n = n, k = m.k, xp = m.xp } end
        table.sort(list, function(a, b) return a.xp > b.xp end)
        for i = #list, KEEP_MOBS + 1, -1 do list[i] = nil end
        c.mob = list
        State.DB.lvh = State.DB.lvh or {}
        State.DB.lvh[c.lv] = c
    end

    ------------------------------------------------------------------
    -- titre : ce qui a ete le plus marquant pendant le niveau (premier cas qui s'applique)
    ------------------------------------------------------------------
    local function FmtDur(sec)
        sec = math.max(0, math.floor((sec or 0) + 0.5))
        if sec < 3600 then return math.max(1, math.floor(sec / 60 + 0.5)) .. " min" end
        return string.format("%d h %02d", math.floor(sec / 3600), math.floor(sec % 3600 / 60))
    end
    -- « de loups », « d'araignees » (seulement si le jeu est en francais : sinon « de Wolf »)
    local function FamLabel(f)
        if Core.Lang() ~= "fr" then return f end
        if not (GetLocale and GetLocale() == "frFR") then return "de " .. f end
        local w = f:sub(1, 1):lower() .. f:sub(2)
        if w:match("[sxz]$") then -- invariable (pas de -al -> -aux : chacal -> chacals)
        elseif w:match("[ae]u$") then w = w .. "x"
        else w = w .. "s" end
        return (w:match("^[aeiouyAEIOUY\195]") and "d'" or "de ") .. w
    end
    -- niveau fait bien plus vite que les 5 precedents (au moins 3 bilans complets pour comparer)
    local function Fast(c, total)
        if c.part or (c.a or 0) < 300 or total <= 0 then return false end
        local sum, n, h = 0, 0, State.DB.lvh or {}
        for l = c.lv - 1, math.max(1, c.lv - 5), -1 do
            local p = h[l]
            if p and not p.part and (p.a or 0) >= 300 and (p.xp or 0) > 0 then sum = sum + p.xp * 3600 / p.a; n = n + 1 end
        end
        return n >= 3 and total * 3600 / c.a >= FAST * sum / n
    end
    local function Pick(c, total)
        local dg, dgx = nil, 0
        for n, x in pairs(c.dg or {}) do if x > dgx then dg, dgx = n, x end end
        if dg then return T("lvtRaid"), dg end
        if (c.d or 0) >= GRAVE then return T("lvtGrave"), T("lvtGraveSub", c.d) end
        local bf, bk = nil, 0
        for f, e in pairs(Fams(c)) do if e.k > bk then bf, bk = f, e.k end end
        if bf and bk >= SLAYER then return T("lvtSlayer", FamLabel(bf)), T("lvtSlayerSub", bk) end
        if Fast(c, total) then return T("lvtFast"), T("lvtFastSub", FmtDur(c.a)) end
        if c.ex > c.qxp and c.ex > c.kxp then return T("lvtScout"), T("lvtScoutSub", c.ex) end
        if c.kxp > c.qxp then return T("lvtHunter"), T("lvtHunterSub", c.k) end
        return T("lvtQuest"), (c.bq and c.bq.n) or T("lvtQuestSub", c.q)
    end
    local function Stats(c, total)
        local parts = {}
        local function add(key, x)
            local p = total > 0 and math.floor(x * 100 / total + 0.5) or 0
            if p > 0 then parts[#parts + 1] = T("lvsPct", T(key), p) end
        end
        add("lvsQuests", c.qxp); add("lvsMobs", c.kxp); add("lvsExplo", c.ex)
        add("lvsOther", math.max(0, total - c.qxp - c.kxp - c.ex))
        if (c.a or 0) >= 60 then parts[#parts + 1] = FmtDur(c.a) end
        parts[#parts + 1] = T("lvsDeaths", c.d or 0)
        return table.concat(parts, "   ·   ")
    end
    -- niveau 60 : total du parcours (tous les niveaux enregistres)
    local function TotalStats(c)
        local q, k, d, seen = 0, 0, 0, {}
        for _, r in pairs(State.DB.lvh or {}) do q = q + (r.q or 0); k = k + (r.k or 0); d = d + (r.d or 0); seen[r] = true end
        if c and not seen[c] then q = q + (c.q or 0); k = k + (c.k or 0); d = d + (c.d or 0) end
        local fmt = Est.FormatNum or tostring
        return T("lvsTotal", fmt(q), fmt(k), d)
    end
    -- temps de jeu : « 5 j 3 h », sinon « 1 h 05 » / « 12 min »
    local function FmtPlayed(secs)
        secs = tonumber(secs) or 0
        if secs >= 86400 then return T("lvDays", math.floor(secs / 86400), math.floor(secs % 86400 / 3600)) end
        return FmtDur(secs)
    end
    -- /played sans sa ligne dans le chat : on retire l'evenement aux fenetres de chat le temps de la reponse
    -- (remis apres la reponse, ou au bout de 5 s quoi qu'il arrive)
    local playedCb, playedMuted
    local function Unmute()
        if not playedMuted then return end
        for _, cf in ipairs(playedMuted) do pcall(cf.RegisterEvent, cf, "TIME_PLAYED_MSG") end
        playedMuted = nil
    end
    local function AskPlayed(cb)
        if not RequestTimePlayed then return end
        playedCb = cb
        if not playedMuted then
            playedMuted = {}
            for i = 1, (NUM_CHAT_WINDOWS or 10) do
                local cf = _G["ChatFrame" .. i]
                if cf and cf.IsEventRegistered and cf:IsEventRegistered("TIME_PLAYED_MSG") then
                    if pcall(cf.UnregisterEvent, cf, "TIME_PLAYED_MSG") then playedMuted[#playedMuted + 1] = cf end
                end
            end
        end
        pcall(RequestTimePlayed)
        if C_Timer and C_Timer.After then C_Timer.After(5, Unmute) end
    end
    local function OnPlayed(total)
        local cb = playedCb; playedCb = nil
        if cb then pcall(cb, total) end
        if C_Timer and C_Timer.After then C_Timer.After(0.5, Unmute) else Unmute() end
    end

    ------------------------------------------------------------------
    -- cinematique
    ------------------------------------------------------------------
    -- couleurs (choix de l'auteur) : couleur de ta classe pour les filets, le losange et NIVEAU ; dore Warpath pour le titre
    local function Palette()
        local C = Skin.COL
        local k = C.accent
        local _, cls = UnitClass and UnitClass("player")
        local cc = cls and RAID_CLASS_COLORS and RAID_CLASS_COLORS[cls]
        if cc then k = { cc.r, cc.g, cc.b } end
        return { edge = k, lvl = k, splash = { k[1] * 0.35, k[2] * 0.35, k[3] * 0.35 }, title = C.cream, sub = C.soft, stats = C.gold }
    end
    local function color(t, c, a) if t.SetColorTexture then t:SetColorTexture(c[1], c[2], c[3], a or 1) end end
    local function tint(fs, c) if fs.SetTextColor then fs:SetTextColor(c[1], c[2], c[3]) end end
    local function ease(x) x = math.max(0, math.min(1, x)); return 1 - (1 - x) ^ 3 end

    local cine
    local function Build()
        -- attachee au monde (WorldFrame), pas a l'interface : elle reste visible quand l'interface est cachee
        local f = CreateFrame("Frame", "WarpathLevelUp", WorldFrame or UIParent)
        f:SetFrameStrata("FULLSCREEN_DIALOG")
        f:SetAllPoints(WorldFrame or UIParent)
        -- a la fermeture (fin, clic, combat), l'interface revient toujours
        f:SetScript("OnHide", function(self)
            if self.hidUI then self.hidUI = false; if UIParent then pcall(UIParent.Show, UIParent) end end
        end)
        local function stop() if not f.out then f.out = f.t end end
        -- deux grandes bandes noires (haut, bas) avec un filet de couleur sur le bord interieur ; un clic dessus ferme.
        -- Le milieu reste le jeu (rien ne bloque les clics la).
        f.top = CreateFrame("Frame", nil, f); f.top:SetPoint("TOPLEFT"); f.top:SetPoint("TOPRIGHT"); f.top:SetHeight(1)
        f.bot = CreateFrame("Frame", nil, f); f.bot:SetPoint("BOTTOMLEFT"); f.bot:SetPoint("BOTTOMRIGHT"); f.bot:SetHeight(1)
        for _, b in ipairs({ f.top, f.bot }) do
            b:EnableMouse(true); b:SetScript("OnMouseUp", stop)
            b.bg = b:CreateTexture(nil, "BACKGROUND"); b.bg:SetAllPoints(); color(b.bg, { 0, 0, 0 }, 0.94)
            b.line = b:CreateTexture(nil, "BORDER"); b.line:SetHeight(2)
        end
        f.top.line:SetPoint("BOTTOMLEFT"); f.top.line:SetPoint("BOTTOMRIGHT")
        f.bot.line:SetPoint("TOPLEFT"); f.bot.line:SetPoint("TOPRIGHT")
        -- ombre a gauche, qui s'efface vers la droite : les stats restent lisibles sur n'importe quel decor
        -- (SetGradient ne marche pas sur ce client, et des carreaux se voient : une image, Media/Shade.tga, noire,
        -- opaque a gauche au milieu, qui s'efface vers la droite et vers le haut et le bas ; generee par splash_tga.py)
        f.shade = f:CreateTexture(nil, "BACKGROUND"); f.shade:SetPoint("LEFT", f, "LEFT", 0, 0); f.shade:SetSize(1200, 520)
        f.shade:SetTexture("Interface\\AddOns\\OghoulesWarpath\\Media\\Shade")
        if f.shade.SetVertexColor then f.shade:SetVertexColor(1, 1, 1, 0.8) end
        -- ton personnage en grand, sans fond (comme pose dans le decor), qui fait jouer ses muscles
        f.model = CreateFrame("PlayerModel", nil, f)
        -- a la fin d'une animation : la suivante de la liste (niveau 60 : cri, flex, cri), sinon la pose normale
        pcall(f.model.SetScript, f.model, "OnAnimFinished", function(m)
            local nxt = f.anims and table.remove(f.anims, 1)
            pcall(m.SetAnimation, m, nxt or 0)
        end)
        -- textes, a gauche : ◆ NIVEAU 8, le titre sur son eclaboussure, le detail, les stats
        f.lvl = Skin.FS(f, 58, Skin.COL.accent, Skin.DISPLAY, "LEFT"); f.lvl:SetPoint("LEFT", f, "LEFT", 150, 95)
        f.gem = Skin.Diamond(f, 28, Skin.COL.red); f.gem:SetPoint("RIGHT", f.lvl, "LEFT", -18, 3)
        -- eclaboussure : trait de pinceau blanc (Media/Splash.tga, genere), teinte a la couleur de la classe,
        -- peint de gauche a droite (on devoile la texture, on ne l'etire pas)
        f.splash = f:CreateTexture(nil, "ARTWORK"); f.splash:SetHeight(SPLASH_H)
        f.splash:SetTexture("Interface\\AddOns\\OghoulesWarpath\\Media\\Splash")
        if f.splash.SetRotation then pcall(f.splash.SetRotation, f.splash, math.rad(-2)) end
        f.title = Skin.FS(f, 48, Skin.COL.cream, Skin.DISPLAY, "LEFT"); f.title:SetPoint("TOPLEFT", f.lvl, "BOTTOMLEFT", 16, -26)
        f.splash:SetPoint("LEFT", f.title, "LEFT", -44, -3)
        f.sub = Skin.FS(f, 24, Skin.COL.soft, Skin.FONT, "LEFT"); f.sub:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 2, -24)
        f.stats = Skin.FS(f, 19, Skin.COL.gold, Skin.FONT, "LEFT"); f.stats:SetPoint("TOPLEFT", f.sub, "BOTTOMLEFT", 0, -14)
        f:SetScript("OnUpdate", function(self, el)
            self.t = self.t + el
            local t = self.t
            if self.out then
                local a = 1 - (t - self.out) / FADE
                if a <= 0 then self:Hide(); return end
                self:SetAlpha(a); return
            end
            self:SetAlpha(1)
            if t >= self.hold then
                -- 2e temps : le perso s'efface, les bandes s'ouvrent ; le bloc de gauche reste encore un peu
                local k = ease((t - self.hold) / FADE)
                self.model:SetAlpha(1 - k)
                local ob = math.max(1, self.barH * (1 - k)); self.top:SetHeight(ob); self.bot:SetHeight(ob)
                if t >= self.hold + STATS_EXTRA then self.out = t end
                return
            end
            local b = math.max(1, self.barH * ease(t / 0.45))      -- les bandes noires se referment
            self.top:SetHeight(b); self.bot:SetHeight(b)
            local tx = ease((t - 0.3) / 0.4)
            self.shade:SetAlpha(tx); self.lvl:SetAlpha(tx); self.gem:SetAlpha(tx)
            local s = ease((t - 0.5) / 0.25)
            local sw = math.max(0.01, s)
            self.splash:SetWidth(self.splashW * sw); self.splash:SetTexCoord(0, sw, 0, 1); self.title:SetAlpha(s)
            if not self.drum and t >= 0.55 then
                self.drum = true    -- coup de tambour quand le titre se peint (son du jeu, comme l'appel)
                if PlaySound and SOUNDKIT and SOUNDKIT.READY_CHECK then pcall(PlaySound, SOUNDKIT.READY_CHECK, "Master") end
            end
            self.sub:SetAlpha(ease((t - 0.8) / 0.4)); self.stats:SetAlpha(ease((t - 1.1) / 0.4))
            self.model:SetAlpha(ease((t - 0.2) / 0.5))
            if not self.flexed and t >= 0.6 then
                self.flexed = true
                if self.model.SetAnimation then pcall(self.model.SetAnimation, self.model, self.anim) end
            end
        end)
        f:Hide()
        return f
    end

    -- c = bilan, level = nouveau niveau, total = XP du niveau, anim = animation du perso (defaut : flex)
    local function Play(c, level, total, anim)
        if not cine then cine = Build() end
        local P = Palette()
        -- meme echelle que l'interface (le monde n'en a pas) : tailles et textes comme ailleurs dans l'addon
        if WorldFrame and UIParent.GetEffectiveScale then
            local ws = WorldFrame:GetEffectiveScale() or 1
            if ws > 0 then pcall(cine.SetScale, cine, (UIParent:GetEffectiveScale() or 1) / ws) end
        end
        local W = cine:GetWidth() or 1920
        local H = cine:GetHeight() or 1080
        if W < 100 or H < 100 then W, H = UIParent:GetWidth() or 1920, UIParent:GetHeight() or 1080 end
        cine.barH = math.floor(H * 0.14)
        cine.model:ClearAllPoints()
        -- cadre large : les bras du flex ne sont plus coupes sur les cotes (haut et bas : caches par les bandes)
        cine.model:SetSize(W * 0.6, H - 2 * cine.barH)
        cine.model:SetPoint("BOTTOM", cine, "BOTTOM", W * 0.19, cine.barH)
        color(cine.top.line, P.edge); color(cine.bot.line, P.edge)
        if cine.splash.SetVertexColor then cine.splash:SetVertexColor(P.splash[1], P.splash[2], P.splash[3], 0.95) end
        pcall(cine.gem.SetStyle, cine.gem, P.edge, false)
        tint(cine.lvl, P.lvl); tint(cine.title, P.title); tint(cine.sub, P.sub); tint(cine.stats, P.stats)
        local title, sub = Pick(c, total)
        local final = level >= MAXLVL
        if final then
            -- niveau 60 : la fin du voyage. Le temps vient de /played (le Journal ne compte que depuis
            -- l'installation) : « Le voyage est termine » en attendant la reponse du jeu, puis le temps.
            title = T("lvt60")
            sub = T("lvt60SubNoTime")
            AskPlayed(function(secs) if cine and cine:IsShown() then cine.sub:SetText(T("lvt60Sub", FmtPlayed(secs))) end end)
        end
        cine.lvl:SetText(Skin.Caps(T("lvBig", level)))
        cine.title:SetText(Core.Upper(title))
        cine.sub:SetText(sub or "")
        cine.stats:SetText(final and TotalStats(c) or Stats(c, total))
        cine.splashW = (cine.title:GetStringWidth() or 300) + 120
        cine.splash:SetHeight(SPLASH_H)
        cine.t, cine.out, cine.flexed, cine.anim, cine.drum = 0, nil, false, anim or (final and ROAR or FLEX), false
        cine.hold = final and HOLD60 or HOLD
        cine.anims = (final and not anim) and { FLEX, ROAR } or nil   -- enchainees apres la 1re animation
        cine.top:SetHeight(1); cine.bot:SetHeight(1); cine.model:SetAlpha(0)
        cine:SetAlpha(1); cine:Show()
        if cine.Raise then cine:Raise() end
        -- cacher l'interface (comme Alt+Z), jamais en combat ; OnHide la remet
        if State.DB.lvupHideUI ~= false and not cine.hidUI and WorldFrame and cine:GetParent() == WorldFrame
            and UIParent:IsShown() and not (InCombatLockdown and InCombatLockdown()) then
            if pcall(UIParent.Hide, UIParent) then cine.hidUI = true end
        end
        local m = cine.model
        if m.SetUnit then pcall(m.SetUnit, m, "player") end
        if m.SetPortraitZoom then pcall(m.SetPortraitZoom, m, ZOOM) end
        if m.SetCamDistanceScale then pcall(m.SetCamDistanceScale, m, CAMDIST) end
        if m.SetFacing then pcall(m.SetFacing, m, -0.35) end      -- un peu tourne vers les stats
        if m.SetAnimation then pcall(m.SetAnimation, m, 0) end
    end
    local function inCombat()
        return (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player"))
    end
    local function Show(c, level, total, anim)
        if inCombat() then queued = { c, level, total, anim }; return end
        pcall(Play, c, level, total, anim)
    end

    -- /warpath apercu niveau [n] [fin] : rejoue la cinematique avec le dernier bilan
    -- (n = numero d'animation a essayer ; fin = la version du niveau 60)
    function LvPreview(anim, final)
        if not State.DB then return false end
        local c = LvGet(lvl() - 1)
        local level, total = lvl(), c and c.xp
        if not c then
            c = LvCurrent(); if not c then return false end
            level, total = lvl() + 1, math.max(0, xpNow() - (c.xp0 or 0))
        end
        if anim then Core.say(T("lvAnimShown", anim)) end
        Show(c, final and MAXLVL or level, total, anim)
        return true
    end

    ------------------------------------------------------------------
    -- evenements
    ------------------------------------------------------------------
    -- modele de message du jeu (« %s meurt, vous gagnez %d points... ») -> motif Lua qui capture nom et nombre.
    -- On coupe apres le premier %d : les variantes (repos, groupe) ajoutent du texte apres.
    local function ToPattern(tpl)
        if type(tpl) ~= "string" then return false end
        local head = tpl:match("^(.-%%d)")
        if not head then return false end
        head = head:gsub("([%(%)%.%+%-%*%?%[%]%^%$%%])", "%%%1")
        head = head:gsub("%%%%s", "(.+)"):gsub("%%%%d", "(%%d+)")
        return "^" .. head
    end
    local killPat, explPat
    local function ParseKill(msg)
        if killPat == nil then killPat = ToPattern(_G.COMBATLOG_XPGAIN_FIRSTPERSON) end
        if not killPat or type(msg) ~= "string" then return nil end
        local n, x = msg:match(killPat)
        return n, tonumber(x)
    end
    local function ParseExplore(msg)
        if explPat == nil then explPat = ToPattern(_G.ERR_ZONE_EXPLORED_XP) end
        if not explPat or type(msg) ~= "string" then return nil end
        local _, x = msg:match(explPat)
        return tonumber(x)
    end

    local function QuestName(id)
        local n
        if C_QuestLog and C_QuestLog.GetTitleForQuestID then
            local ok, r = pcall(C_QuestLog.GetTitleForQuestID, id)
            if ok and type(r) == "string" and r ~= "" then n = r end
        end
        if not n and Est.EST and Est.EST[id] then n = Est.EST[id].n end
        return n or ("#" .. tostring(id))
    end
    local function DungeonName()
        if not IsInInstance then return nil end
        local inI, kind = IsInInstance()
        if not (inI and (kind == "party" or kind == "raid")) then return nil end
        return GetInstanceInfo and (GetInstanceInfo()) or nil
    end

    local function OnKill(name, x)
        local c = LvCurrent(); if not c then return end
        c.k = c.k + 1; c.kxp = c.kxp + x
        local m = c.mob[name] or { k = 0, xp = 0 }
        m.k = m.k + 1; m.xp = m.xp + x
        c.mob[name] = m
        local dg = DungeonName()
        if dg then c.dg[dg] = (c.dg[dg] or 0) + x end
    end
    local function OnQuest(id, x)
        local c = LvCurrent(); if not c then return end
        x = tonumber(x) or 0
        c.q = c.q + 1; c.qxp = c.qxp + x
        if x > 0 and (not c.bq or x > (c.bq.xp or 0)) then c.bq = { id = id, n = QuestName(id), xp = x } end
    end
    local function OnLevelUp(newLevel)
        local c = State.DB.lvc
        if not c then State.DB.lvc = New(true); return end
        pending = c
        local function close()
            local done = pending
            if done then pcall(Finish, done, xpNow()) end
            pending = nil
            State.DB.lvc = New(false)
            -- un bilan commence en route (incomplet) ne merite pas de cinematique
            if done and not done.part and State.DB.lvupShow ~= false then
                Show(done, tonumber(newLevel) or lvl(), done.xp or 0)
            end
        end
        if C_Timer and C_Timer.After then C_Timer.After(1, close) else close() end
    end

    local fr = CreateFrame("Frame")
    for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "CHAT_MSG_COMBAT_XP_GAIN", "CHAT_MSG_SYSTEM", "QUEST_TURNED_IN",
                         "PLAYER_DEAD", "PLAYER_LEVEL_UP", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED", "TIME_PLAYED_MSG" }) do pcall(fr.RegisterEvent, fr, e) end
    fr:SetScript("OnEvent", function(_, e, a1, a2)
        if not State.DB then return end
        if e == "CHAT_MSG_COMBAT_XP_GAIN" then
            local n, x = ParseKill(a1)
            if n and x then OnKill(n, x) end
        elseif e == "CHAT_MSG_SYSTEM" then
            local x = ParseExplore(a1)
            if x then local c = LvCurrent(); if c then c.ex = c.ex + x end end
        elseif e == "QUEST_TURNED_IN" then OnQuest(a1, a2)
        elseif e == "PLAYER_DEAD" then
            local inI, kind = false, nil
            if IsInInstance then inI, kind = IsInInstance() end
            if not (inI and (kind == "pvp" or kind == "arena")) then
                local c = LvCurrent(); if c then c.d = c.d + 1 end
            end
        elseif e == "PLAYER_LEVEL_UP" then OnLevelUp(a1)
        elseif e == "TIME_PLAYED_MSG" then
            if playedCb or playedMuted then OnPlayed(a1) end
        elseif e == "PLAYER_REGEN_DISABLED" then
            -- un combat commence : on ferme tout de suite (avant le blocage de combat), l'interface revient
            if cine and cine:IsShown() then cine:Hide() end
        elseif e == "PLAYER_REGEN_ENABLED" then
            if queued then
                local q = queued; queued = nil
                if C_Timer and C_Timer.After then C_Timer.After(1, function() Show(q[1], q[2], q[3], q[4]) end) end
            end
        elseif e == "PLAYER_ENTERING_WORLD" then
            local c = LvCurrent(); if c then c.t1 = now() end
        end
    end)

    ------------------------------------------------------------------
    -- /warpath niveau [n] : bilan du niveau en cours, ou d'un niveau termine
    ------------------------------------------------------------------
    local function hm(s) s = math.floor(s or 0); return string.format("%dh%02d", math.floor(s / 3600), math.floor(s % 3600 / 60)) end
    local function num(n) return Est.FormatNum and Est.FormatNum(math.floor(n or 0)) or tostring(math.floor(n or 0)) end

    function LvReport(arg)
        local want = tonumber(arg)
        local c, live
        if want then c = LvGet(want) else c = LvCurrent(); live = true end
        if not c then Core.say(T("lvNone")); return end
        local total, oth = c.xp, c.oth
        if live then
            total = math.max(0, xpNow() - (c.xp0 or 0))
            oth = math.max(0, total - c.kxp - c.qxp - c.ex)
        end
        Core.say(T("lvHead", c.lv, c.part and T("lvPartial") or ""))
        Core.say(T("lvLine", hm(c.a), num(total), num(c.kxp), num(c.qxp), num(c.ex), num(oth)))
        local best
        if live then
            for n, m in pairs(c.mob) do if not best or m.xp > best.xp then best = { n = n, k = m.k, xp = m.xp } end end
        else best = c.mob[1] end
        if best then Core.say(T("lvMob", best.n, best.k, num(best.xp))) end
        if c.bq then Core.say(T("lvQuest", c.bq.n, num(c.bq.xp))) end
        for n, x in pairs(c.dg or {}) do Core.say(T("lvDg", n, num(x))) end
        Core.say(T("lvDeaths", c.d or 0))
        local prev = lvl() - 1
        if prev >= 1 then Core.say(T("lvHelp", prev)) end
    end
end

-- ce que ce fichier offre aux autres (ns.Mod.LevelUp)
do
    local M = ns.Mod.LevelUp
    M.LvCurrent = LvCurrent
    M.LvGet = LvGet
    M.LvTick = LvTick
    M.LvReport = LvReport
    M.LvPreview = LvPreview
end
