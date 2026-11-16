-- Oghoule's Warpath : moteur (Skin.lua) - voir Core.lua
local ADDON, ns = ...
local _ENV = ns.CoreEnv
if setfenv then setfenv(1, _ENV) end

------------------------------------------------------------------
-- Habillage "cinematique" : noir, filets fins, losanges, capitales espacees
------------------------------------------------------------------
FONT, DISPLAY = "Fonts\\FRIZQT__.TTF", "Fonts\\MORPHEUS.TTF"
COL = {
    bg = { 0.047, 0.043, 0.039 }, white = { 0.93, 0.90, 0.85 }, soft = { 0.79, 0.75, 0.68 },
    gold = { 0.66, 0.60, 0.48 }, accent = { 0.80, 0.73, 0.56 }, line = { 0.35, 0.32, 0.26 },
    faint = { 0.23, 0.21, 0.17 }, red = { 0.62, 0.16, 0.16 }, green = { 0.61, 0.78, 0.66 },
}
-- memes teintes pour le texte du chat, des fiches et des listes (|cff..)
HEX = { gold = "cdbb8e", accent = "d6b866", soft = "b5aa98", faint = "8c7f62", red = "c24a3e", green = "9cc7a8", chain = "a99cc0" }
ACCENTS = { ["à"] = "À", ["â"] = "Â", ["ç"] = "Ç", ["é"] = "É", ["è"] = "È", ["ê"] = "Ê", ["ë"] = "Ë",
                  ["î"] = "Î", ["ï"] = "Ï", ["ô"] = "Ô", ["ù"] = "Ù", ["û"] = "Û", ["ü"] = "Ü", ["ö"] = "Ö" }
function Upper(str)
    str = tostring(str or ""):upper()
    return (str:gsub("\195[\128-\191]", function(c) return ACCENTS[c] or c end))
end
-- capitales espacees (le jeu n'a pas d'espacement de lettres)
function Spaced(str)
    local out = {}
    for ch in tostring(str or ""):gmatch("[%z\1-\127\194-\244][\128-\191]*") do out[#out + 1] = ch end
    return table.concat(out, " ")
end
function Caps(str) return Spaced(Upper(str)) end

function FS(parent, size, col, font, justify, layer)
    local fs = parent:CreateFontString(nil, layer or "OVERLAY")
    if fs.SetFont then fs:SetFont(font or FONT, size, "") end
    if fs.SetTextColor then fs:SetTextColor(col[1], col[2], col[3]) end
    if fs.SetJustifyH then fs:SetJustifyH(justify or "LEFT") end
    if fs.SetShadowOffset then fs:SetShadowOffset(1, -1); fs:SetShadowColor(0, 0, 0, 0.9) end
    return fs
end
function Tex(parent, col, a, layer)
    local t = parent:CreateTexture(nil, layer or "ARTWORK")
    if t.SetColorTexture then t:SetColorTexture(col[1], col[2], col[3], a or 1) end
    return t
end
function Diamond(parent, size, col, hollow)
    local d = CreateFrame("Frame", nil, parent)
    d:SetSize(size + 4, size + 4)
    d.outer = Tex(d, col, 1, "ARTWORK"); d.outer:SetSize(size, size); d.outer:SetPoint("CENTER")
    d.inner = Tex(d, COL.bg, 1, "OVERLAY"); d.inner:SetSize(size - 2, size - 2); d.inner:SetPoint("CENTER")
    if d.outer.SetRotation then d.outer:SetRotation(math.rad(45)); d.inner:SetRotation(math.rad(45)) end
    function d:SetStyle(c, h)
        if self.outer.SetColorTexture then self.outer:SetColorTexture(c[1], c[2], c[3], 1) end
        self.inner:SetShown(h and true or false)
    end
    d:SetStyle(col, hollow)
    return d
end
-- filet ——◆—— (centre, losange rouge)
function Divider(parent, w)
    local d = CreateFrame("Frame", nil, parent)
    d:SetSize(w, 10)
    local l = Tex(d, COL.line); l:SetHeight(1); l:SetPoint("LEFT"); l:SetPoint("RIGHT", d, "CENTER", -8, 0)
    local r = Tex(d, COL.line); r:SetHeight(1); r:SetPoint("RIGHT"); r:SetPoint("LEFT", d, "CENTER", 8, 0)
    d.gem = Diamond(d, 6, COL.red); d.gem:SetPoint("CENTER")
    return d
end
-- filet avec un titre au centre : ——— ENSUITE ———
function TitledRule(parent, w)
    local d = CreateFrame("Frame", nil, parent)
    d:SetSize(w, 12)
    d.label = FS(d, 9, COL.gold, FONT, "CENTER"); d.label:SetPoint("CENTER")
    local l = Tex(d, COL.faint); l:SetHeight(1); l:SetPoint("LEFT"); l:SetPoint("RIGHT", d.label, "LEFT", -8, 0)
    local r = Tex(d, COL.faint); r:SetHeight(1); r:SetPoint("RIGHT"); r:SetPoint("LEFT", d.label, "RIGHT", 8, 0)
    return d
end
-- bouton plat : filet de 1 px, texte en capitales espacees
function FlatButton(parent, w, h, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(w, h)
    for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        local t = Tex(b, COL.line)
        if side == "TOP" or side == "BOTTOM" then t:SetHeight(1); t:SetPoint(side .. "LEFT"); t:SetPoint(side .. "RIGHT")
        else t:SetWidth(1); t:SetPoint("TOP" .. side); t:SetPoint("BOTTOM" .. side) end
    end
    local hl = Tex(b, COL.accent, 0.10, "HIGHLIGHT"); hl:SetAllPoints()
    b.fs = FS(b, 10, COL.white, FONT, "CENTER"); b.fs:SetPoint("CENTER")
    if b.SetFontString then b:SetFontString(b.fs) end
    function b:SetLabel(t) self.fs:SetText(t) end
    b:SetScript("OnClick", onClick)
    return b
end

function WarpathName()
    local n = UnitName and UnitName("player")
    if type(n) ~= "string" or n == "" then n = "?" end
    return T(n:sub(-1) == "s" and "warpathS" or "warpath", n)
end

W, PAD = 300, 18
INNER = W - 2 * PAD
distTarget = nil -- { m, x, y } : prochaine position a atteindre (pour la distance affichee)

function SetUpcoming(items)
    if not f or not f.up then return end
    f.nUp = #items
    for k = 1, 4 do
        local b, it = f.up[k], items[k]
        if it then b.idx = it.idx; b.fs:SetText(it.text); b:Show() else b.idx = nil; b:Hide() end
    end
end

-- Place les blocs visibles les uns sous les autres et ajuste la hauteur
function Layout()
    local y = -16
    local function put(obj, h, gap, x)
        obj:ClearAllPoints()
        obj:SetPoint("TOPLEFT", f, "TOPLEFT", x or PAD, y)
        y = y - h - (gap or 0)
    end
    local function sh(fs, min) local h = fs.GetStringHeight and fs:GetStringHeight(); return (type(h) == "number" and h > 0) and h or (min or 12) end
    put(f.title, sh(f.title, 10), 6); put(f.name, sh(f.name, 13), 6); put(f.div, 10, 12)
    local il = rawget(f, "infoLine")
    if il and il:IsShown() then put(il, sh(il, 10), 8) end
    if f.kind:IsShown() then put(f.kindRow, 12, 4) end
    if f.qtitle:IsShown() then put(f.qtitle, sh(f.qtitle, 20), 5) end
    if f.text:IsShown() then put(f.text, sh(f.text), 12) end
    local any = false
    for k = 1, 3 do if f.route[k]:IsShown() then put(f.route[k], 16, 2); any = true end end
    if any then y = y - 2 end
    if DB.compact then f.coord:Hide() end
    if f.coord:IsShown() then put(f.coord, 10, 10) elseif any then y = y - 8 end
    if f.chainBtn:IsShown() then put(f.chainBtn, 16, 10) end
    if f.lockBtn:IsShown() then
        local lh = math.max(16, (f.lockBtn.label.GetStringHeight and f.lockBtn.label:GetStringHeight() or 12) + 4)
        f.lockBtn:SetHeight(lh); put(f.lockBtn, lh, 10)
    end
    if f.advice and f.advice:IsShown() then
        local ah = math.max(16, (f.advice.label.GetStringHeight and f.advice.label:GetStringHeight() or 12) + 4)
        f.advice:SetHeight(ah); put(f.advice, ah, 10)
    end
    put(f.btnRow, 26, 12)
    if DB.compact then for k = 1, 4 do f.up[k]:Hide() end end
    if (f.nUp or 0) > 0 and not DB.compact then
        f.nextRule:Show(); put(f.nextRule, 12, 6)
        for k = 1, 4 do if f.up[k]:IsShown() then put(f.up[k], 16, 1) end end
    else
        f.nextRule:Hide()
    end
    local xl = rawget(f, "xph")
    if xl and xl:IsShown() then put(xl, 10, 4) end
    f:SetHeight(-y + 12)
end

function SetRoute(legs)
    for k = 1, 3 do
        local row, leg = f.route[k], legs[k]
        if leg then
            row.name:SetText(leg.name or "")
            row.mode:SetText(Caps(leg.mode or ""))
            local now = (k == 1)
            row.gem:SetStyle(now and COL.white or COL.line, not now)
            if row.name.SetTextColor then
                local c = now and COL.white or COL.gold
                row.name:SetTextColor(c[1], c[2], c[3])
                c = now and COL.accent or COL.gold
                row.mode:SetTextColor(c[1], c[2], c[3])
            end
            row:Show()
        else
            row:Hide()
        end
    end
end

function SetChain(ch)
    if not ch then f.chainBtn:Hide(); return end
    f.chainBtn.label:SetText(T("chainLine", ch.pos, ch.len))
    for k = 1, 10 do
        local g = f.chainBtn.gems[k]
        if ch.len <= 10 and k <= ch.len then
            g:SetStyle(k < ch.pos and COL.accent or (k == ch.pos and COL.white or COL.line), k > ch.pos)
            g:Show()
        else
            g:Hide()
        end
    end
    f.chainBtn:Show()
end

function UpdateDistance()
    if not f or not f.dist then return end
    local me = PlayerWP()
    local w = distTarget and WP(distTarget[1], distTarget[2], distTarget[3])
    if me and w and me[3] == w[3] then
        f.dist:SetText(Caps(T("dist", math.floor(Dist(me[1], me[2], w[1], w[2]) + 0.5))))
    else
        f.dist:SetText("")
    end
end

function RefreshInner(forceWP)
    if not f then return end
    f.name:SetText(Caps(WarpathName()))
    if not steps then
        f.title:SetText(""); f.summary = T("noGuide")
        f.kind:Hide(); f.qtitle:Hide(); f.text:SetText(T("noGuide")); f.text:Show()
        f.coord:SetText(""); f.coord:Hide(); f.list:SetText(""); SetUpcoming({}); SetRoute({}); SetChain(nil)
        distTarget = nil; Layout()
        return
    end
    local n = #steps
    local i = peek or focus or current
    local s = steps[i]
    if not s then
        f.title:SetText(Caps(Title(G)) .. "  |cff8c7f62·|r  " .. T("finished"))
        f.summary = T("endGuide")
        f.kind:Hide(); f.qtitle:Hide(); f.text:SetText(T("endGuide")); f.text:Show()
        f.coord:SetText(""); f.coord:Hide(); f.list:SetText(""); SetUpcoming({}); SetRoute({}); SetChain(nil)
        ClearWaypoint(); lastWP = nil; distTarget = nil
        f.skip:SetLabel(Caps(T("ok")))
        UpdateDistance(); Layout()
    else
        local zone = Title(G):gsub("%s*%b()", ""):gsub("%s+%d+%-%d+$", "")
        if IS_DUNGEON[DB.guide] then zone = zone:gsub("^[^:]+:%s*", "") end
        f.title:SetText(Caps(zone) .. "   |cff8c7f62·|r   " .. i .. " / " .. n)
        local st = peek and doneCache[i]
        -- prise impossible tant qu'un prerequis du journal n'est pas fini : on guide vers ce prerequis
        local det = (not peek) and PrereqDetour and PrereqDetour(s) or nil
        local g = det and { t = det.done and "turnin" or "do", id = det.id, m = det.m, x = det.x, y = det.y,
                            zone = MAPNAME[det.m] or s.zone, quest = det.name } or s
        local tr = (not peek) and TransportFor(g) or nil
        -- vol conseille pour la prochaine etape du trajet (vers le transport, ou vers l'objectif)
        local fl
        flightPlan = nil
        if not peek and DB.useFlights ~= false and not (UnitOnTaxi and UnitOnTaxi("player")) then
            local here = PlayerWP()
            local leg = tr and WP(tr.from[1], tr.from[2], tr.from[3]) or (g.m and g.x and WP(g.m, g.x, g.y))
            if here and leg then
                fl = BestFlight(here, leg, KnownFlights())
                if fl then flightPlan = fl end
            end
        end
        -- texte complet (journal de debug et tests)
        f.summary = (fl and (T("takeFlight", fl.from.name, fl.to.name) .. "\n") or "")
            .. (tr and (T(tr.kind == "boat" and "takeBoat" or "takeZep", tr.dest, T(tr.where)) .. "\n") or "")
            .. (st == "done" and (CHECK .. " ") or st == "skip" and (T("skipped") .. " ") or "")
            .. (PREFIX[s.t] or "") .. (s.optional and (" " .. T("optional")) or "")
            .. (s.quest and (" " .. QName(s)) or "")
            .. (chainOf[i] and ("\n" .. T("chainLbl", QuestTitle(chainOf[i].qid) or chainOf[i].name, chainOf[i].pos, chainOf[i].len)) or "")
            .. "\n" .. StepText(s)
        -- type d'etape + etat
        local kc = PCOL[s.t] or "cdbb8e"
        f.kind:SetText("|cff" .. kc .. Caps(T(s.t)) .. "|r"
            .. (s.optional and ("   |cff8c7f62" .. T("optional") .. "|r") or "")
            .. (st == "done" and ("  " .. CHECK) or st == "skip" and ("   |cff8c7f62" .. T("skipped") .. "|r") or "")
            .. (peek and ("   |cffd69a66" .. T("preview") .. "|r") or (focus and ("   |cffcdbb8e" .. T("chosen") .. "|r")) or ""))
        -- rendement estime (quete + monstres) compare au simple farm de monstres de ton niveau
        if (s.t == "do" or (s.optional and s.t == "accept")) and type(s.id) == "number" and EST[s.id] then
            local e = Estimate({ s.id }, false)
            if e.secs > 0 and e.perHour > 0 then
                local p = UnitLevel("player") or 1
                local grind = MobXP(p, p, 0) * 3600 / KillTime()
                local tag = (e.perHour >= grind * 1.3) and ("  |cff9cc7a8" .. T("rateGood") .. "|r")
                    or (e.perHour < grind * 0.7) and ("  |cffd69a66" .. T("rateBad") .. "|r") or ""
                f.kind:SetText(f.kind:GetText() .. "   |cff8c7f62" .. T("xpRate", FormatNum(e.perHour)) .. "|r" .. tag)
            end
        end
        f.kind:Show()
        local qn = s.quest and QName(s)
        if qn and qn ~= "" then
            -- niveau de la quete, colore selon la difficulte (gris / vert / jaune / orange / rouge)
            local qid = type(s.id) == "number" and s.id or (type(s.id) == "table" and s.id[1])
            local ql = qid and EST[qid] and EST[qid].l
            if ql and ql > 0 and GetQuestDifficultyColor then
                local c = GetQuestDifficultyColor(ql)
                qn = string.format("|cff%02x%02x%02x[%d]|r %s", (c.r or 1) * 255, (c.g or 1) * 255, (c.b or 1) * 255, ql, qn)
            end
            f.qtitle:SetText(qn); f.qtitle:Show()
        else f.qtitle:Hide() end
        local body = StepText(s)
        -- astuce de quete (Tips.lua)
        if DB.tips ~= false and ns.Tips and s.t ~= "note" then
            local qid = type(s.id) == "number" and s.id or (type(s.id) == "table" and s.id[1])
            local tip = qid and ns.Tips[qid]
            if tip then body = body .. "\n\n|cffd6b866" .. T("tipLbl") .. "|r  " .. ((Lang() == "en") and tip[2] or tip[1]) end
        end
        -- taux de drop des objets encore a trouver (tes mesures + groupe/guilde, sinon Questie)
        if s.t == "do" or (det and not det.done) then
            local lines = {}
            for _, q in ipairs(det and { det.id } or Ids(s)) do
                if logById[q] == false and EST[q] then
                    for _, dr in ipairs(Estimate({ q }, false).drops) do
                        local pct = math.floor(dr.rate * 100 + 0.5)
                        local how = (dr.how == "unique") and T("dropHowUnique") or (dr.how == "measured") and T("dropHowMeasured", dr.k)
                            or (dr.how == "questie") and T("dropHowQuestie", dr.k or 0) or T("dropHowAssumed", dr.k or 0)
                        lines[#lines + 1] = (dr.name or "?") .. " : |cffffd100" .. pct .. " %|r  |cff8c7f62" .. how .. "|r"
                    end
                end
            end
            if #lines > 0 then body = body .. "\n\n|cffd6b866" .. T("dropLbl") .. "|r\n" .. table.concat(lines, "\n") end
        end
        if det then body = "|cffd69a66" .. T(det.done and "preTurnin" or "preDo", det.name) .. "|r\n\n" .. body end
        f.text:SetText(body); f.text:SetShown(body ~= "")
        -- itineraire : au plus 3 etapes (vol, zeppelin/bateau, puis l'objectif)
        local legs = {}
        if fl then
            legs[#legs + 1] = { name = fl.from.name, mode = T("modeWalk"), m = fl.from.m, x = fl.from.x, y = fl.from.y }
            legs[#legs + 1] = { name = fl.to.name, mode = T("modeFly"), m = fl.to.m, x = fl.to.x, y = fl.to.y }
        end
        if tr and #legs < 3 then
            local wh = T(tr.where)
            legs[#legs + 1] = { name = wh:sub(1, 1):upper() .. wh:sub(2), mode = (#legs == 0) and T("modeWalk") or T("modeWalk"),
                                m = tr.from[1], x = tr.from[2], y = tr.from[3] }
            if #legs < 3 then legs[#legs + 1] = { name = tr.dest, mode = T(tr.kind == "boat" and "modeBoat" or "modeZep") } end
        end
        if g.x and g.y and #legs < 3 and #legs > 0 then
            legs[#legs + 1] = { name = g.zone or T("arrival"), mode = T("modeWalk"), m = g.m, x = g.x, y = g.y }
        end
        SetRoute(legs)
        local first = legs[1] or (g.x and g.y and { name = g.zone, m = g.m, x = g.x, y = g.y }) or nil
        if first and first.x then
            -- zone de chasse/ramassage (etape "faire", ou prerequis a faire) : la fleche se cache une fois sur place
            local area = (#legs == 0) and ((det and not det.done) or (not det and s.t == "do")) or false
            distTarget = first.m and { first.m, first.x, first.y, area } or nil
            f.coord:SetText(string.format("%s  %.1f, %.1f", first.name or "", first.x, first.y)); f.coord:Show()
        else
            distTarget = nil
            f.coord:SetText(""); f.coord:Hide()
        end
        if tr and not fl then
            f.coord:SetText(string.format("%s  %.1f, %.1f  (%s)", MAPNAME[tr.from[1]] or "", tr.from[2], tr.from[3],
                T(tr.kind == "boat" and "boat" or "zep")))
        elseif fl then
            f.coord:SetText(string.format("%s  %.1f, %.1f  (%s)", fl.from.name, fl.from.x, fl.from.y, T("flight")))
        end
        -- A suivre : les 4 prochaines etapes (ordre optimise pour les donjons), cliquables
        local seq = {}
        if dynOrder then
            local after = false
            for _, j in ipairs(dynOrder) do
                if after then seq[#seq + 1] = j end
                if j == i then after = true end
            end
            if not after then seq = {} for _, j in ipairs(dynOrder) do if j ~= i then seq[#seq + 1] = j end end end
            local entrance
            for j = 1, n do if steps[j].t == "go" then entrance = j; break end end
            for j = (entrance or n + 1), n do
                if Applies(steps[j]) and j ~= i then seq[#seq + 1] = j end
            end
        else
            local j = i
            while #seq < 4 do
                j = NextApplicable(j)
                if j > n then break end
                seq[#seq + 1] = j
            end
        end
        local items = {}
        for _, j in ipairs(seq) do
            if #items >= 4 then break end
            local t = steps[j]
            local st2 = doneCache[j]
            local label
            if st2 then
                label = "|cff6b6355" .. (Short(t):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) .. (st2 == "skip" and (" " .. T("skipped")) or "") .. "|r"
                if st2 == "done" then label = CHECK .. " " .. label end
            else
                local nm = QName(t) or StepText(t):sub(1, 45)
                label = (PREFIX[t.t] or "") .. "   " .. (chainOf[j] and ("|cffa99cc0" .. nm .. "|r") or nm)
            end
            items[#items + 1] = { idx = j, text = label }
        end
        f.list:SetText(#items > 0 and (Caps(T("thenLbl")) .. (dynOrder and ("   |cffcdbb8e" .. T("optimized") .. "|r") or "")) or "")
        SetUpcoming(items)
        -- chaine : cliquer ramene a la premiere etape de la chaine qui reste a faire
        local ch = chainOf[i]
        local firstTodo
        if ch then
            for _, j in ipairs(ch.idx) do
                if Applies(steps[j]) and not doneCache[j] then firstTodo = j; break end
            end
        end
        f.chainBtn.target = (firstTodo and firstTodo ~= i) and firstTodo or nil
        SetChain(ch)
        f.skip:SetLabel(Caps((s.t == "note" or s.t == "go" or s.t == "level") and T("ok") or T("ignore")))
        -- quete sautee faute de prerequis : on la montre, cliquable
        local locks = (not peek) and LockCandidates() or {}
        f.lockBtn.list = locks
        local li = locks[1]
        if li then
            local need = ChainFor(steps[li].id) or {}
            f.lockBtn.idx = li
            f.lockBtn.label:SetText("|cffd69a66" .. T("lockLine", QName(steps[li]) or "?") .. "|r  |cff8c7f62"
                .. T("lockNeed", #need) .. (#locks > 1 and ("  (+" .. (#locks - 1) .. ")") or "") .. "|r")
            f.lockBtn:Show()
        else
            f.lockBtn.idx = nil
            f.lockBtn:Hide()
        end
        -- conseil : journal plein, pierre de foyer
        local adv = (not peek) and Advice and Advice(i, g) or nil
        currentAdvice = adv
        if adv and f.advice then
            f.advice.icon:SetTexture(adv.icon); f.advice.label:SetText(adv.text); f.advice:Show()
        elseif f.advice then f.advice:Hide() end
        if ns.Targets then ns.Targets.Update(det and g or s) end
        local wpKey = (det and ("pre" .. det.id .. (det.done and "d" or "") .. ">") or "") .. i .. (tr and (":" .. tr.id) or "") .. (fl and (":fl:" .. fl.from.key .. ">" .. fl.to.key) or "")
        if not peek and (forceWP or lastWP ~= wpKey) then
            lastWP = wpKey
            if fl then
                SetWaypoint({ m = fl.from.m, x = fl.from.x, y = fl.from.y, quest = T("flight") .. " -> " .. fl.to.name })
            elseif tr then
                SetWaypoint({ m = tr.from[1], x = tr.from[2], y = tr.from[3],
                    quest = T(tr.kind == "boat" and "boat" or "zep") .. " -> " .. tr.dest })
            else
                SetWaypoint(g)
            end
        end
        UpdateDistance()
        Layout()
    end
    if ns.UI and ns.UI.RefreshOptions then ns.UI.RefreshOptions() end
end

-- Refresh protege : une erreur d'affichage est signalee clairement dans le chat (une fois par message)
local shownErr = {}
function Refresh(forceWP)
    local ok, err = pcall(RefreshInner, forceWP)
    if not ok then
        local m = tostring(err)
        if not shownErr[m] then shownErr[m] = true; say(T("errDisplay", m)) end
    end
end

------------------------------------------------------------------
-- Bulle d'info aux couleurs de l'addon (une bulle a nous : celle du jeu reste intacte pour les autres addons)
------------------------------------------------------------------
do
    local tip
    function Tip()
        if tip then return tip end
        if WARPATH_TEST or not (CreateFrame and UIParent) then return GameTooltip end
        local ok, t = pcall(CreateFrame, "GameTooltip", "WarpathTooltip", UIParent, "GameTooltipTemplate")
        if not ok or not t then return GameTooltip end
        if type(t.NineSlice) == "table" and t.NineSlice.SetAlpha then t.NineSlice:SetAlpha(0) end
        if t.SetBackdrop then pcall(t.SetBackdrop, t, nil) end
        local bg = t:CreateTexture(nil, "BACKGROUND", nil, -8); bg:SetColorTexture(COL.bg[1], COL.bg[2], COL.bg[3], 0.95); bg:SetAllPoints()
        for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
            local e = t:CreateTexture(nil, "BACKGROUND", nil, -7)
            e:SetColorTexture(COL.line[1], COL.line[2], COL.line[3], 1)
            if side == "TOP" or side == "BOTTOM" then e:SetHeight(1); e:SetPoint(side .. "LEFT"); e:SetPoint(side .. "RIGHT")
            else e:SetWidth(1); e:SetPoint("TOP" .. side); e:SetPoint("BOTTOM" .. side) end
        end
        local gem = t:CreateTexture(nil, "ARTWORK"); gem:SetSize(8, 8); gem:SetPoint("CENTER", t, "TOP", 0, 0)
        gem:SetTexture("Interface\\AddOns\\" .. (ADDON or "OghoulesWarpath") .. "\\Media\\Gem")
        -- texte : premiere ligne en accent, les autres en creme si aucune couleur n'est donnee ; police de l'addon
        local add = t.AddLine
        t.AddLine = function(self, text, r, g, b, wrap)
            if r == nil then
                local c = (self:NumLines() == 0) and COL.accent or COL.white
                r, g, b = c[1], c[2], c[3]
            end
            return add(self, text, r, g, b, wrap)
        end
        t:HookScript("OnShow", function(self)
            for i = 1, self:NumLines() do
                local l = _G["WarpathTooltipTextLeft" .. i]
                if l and l.SetFont then l:SetFont(FONT, i == 1 and 12 or 11, "") end
            end
        end)
        tip = t
        return t
    end
end

------------------------------------------------------------------
-- Fenetre de question aux couleurs de l'addon. Reprend la definition StaticPopupDialogs[nom] (libelles,
-- OnShow, OnAccept, OnCancel, OnAlt, OnHide) : bouton 1 = OnAccept, bouton 2 = OnCancel("clicked"),
-- bouton 3 = OnAlt, Echap = OnCancel("escape"). Sans interface (tests), on passe par StaticPopup_Show.
------------------------------------------------------------------
do
    local dlg, cur, curName, answered, replacing
    local queue = {} -- une question a la fois : les suivantes attendent leur tour
    -- comme le jeu : le choix d'abord (OnAccept/OnCancel/OnAlt), puis la fermeture (OnHide)
    local function finish(fn, ...)
        answered = true
        local d = cur
        if d and d[fn] then pcall(d[fn], dlg, nil, ...) end
        if cur == d then dlg:Hide() end
    end
    local function build()
        if dlg then return dlg end
        dlg = CreateFrame("Frame", "WarpathDialog", UIParent)
        dlg:SetSize(380, 140); dlg:SetPoint("TOP", UIParent, "TOP", 0, -150)
        dlg:SetFrameStrata("DIALOG"); dlg:SetToplevel(true); dlg:EnableMouse(true); dlg:SetClampedToScreen(true)
        dlg:SetMovable(true); dlg:RegisterForDrag("LeftButton")
        dlg:SetScript("OnDragStart", dlg.StartMoving); dlg:SetScript("OnDragStop", dlg.StopMovingOrSizing)
        local bg = Tex(dlg, COL.bg, 0.97, "BACKGROUND"); bg:SetAllPoints()
        for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
            local t = Tex(dlg, COL.line)
            if side == "TOP" or side == "BOTTOM" then t:SetHeight(1); t:SetPoint(side .. "LEFT"); t:SetPoint(side .. "RIGHT")
            else t:SetWidth(1); t:SetPoint("TOP" .. side); t:SetPoint("BOTTOM" .. side) end
        end
        dlg.head = FS(dlg, 10, COL.gold, FONT, "CENTER"); dlg.head:SetPoint("TOP", 0, -12)
        dlg.head:SetText(Caps("Oghoule's Warpath"))
        dlg.rule = Divider(dlg, 340); dlg.rule:SetPoint("TOP", dlg.head, "BOTTOM", 0, -5)
        dlg.text = FS(dlg, 12, COL.white, FONT, "LEFT"); dlg.text:SetPoint("TOP", dlg.rule, "BOTTOM", 0, -8); dlg.text:SetWidth(340)
        if dlg.text.SetSpacing then dlg.text:SetSpacing(2) end
        dlg.buttons = {}
        for i = 1, 3 do
            local b = FlatButton(dlg, 110, 24, function()
                if i == 1 then finish("OnAccept") elseif i == 2 then finish("OnCancel", "clicked") else finish("OnAlt") end
            end)
            dlg.buttons[i] = b
            dlg["button" .. i] = b
        end
        dlg:SetScript("OnHide", function()
            local d = cur
            if not answered and d and d.OnCancel then pcall(d.OnCancel, dlg, nil, "escape") end
            answered = true
            cur, curName = nil, nil
            if d and d.OnHide then pcall(d.OnHide, dlg) end
            local nxt = (not replacing) and table.remove(queue, 1)
            if nxt then
                if C_Timer and C_Timer.After then C_Timer.After(0.3, function() Popup(nxt[1], nxt[2]) end) else Popup(nxt[1], nxt[2]) end
            end
        end)
        if UISpecialFrames then table.insert(UISpecialFrames, "WarpathDialog") end
        dlg:Hide()
        return dlg
    end

    function PopupVisible() return dlg and dlg:IsShown() or false end

    function Popup(name, txt)
        local d = StaticPopupDialogs and StaticPopupDialogs[name]
        if WARPATH_TEST or not (d and CreateFrame and UIParent) then
            if StaticPopup_Show then return StaticPopup_Show(name, txt) end
            return
        end
        build()
        if dlg:IsShown() then
            if name ~= curName then
                for _, q in ipairs(queue) do if q[1] == name then q[2] = txt; return end end
                queue[#queue + 1] = { name, txt }
                return
            end
            -- la meme question, mise a jour : on remplace le texte sans rien declencher
            answered = true; cur = nil; replacing = true; dlg:Hide(); replacing = false
        end
        cur, curName, answered = d, name, false
        local text = d.text or "%s"
        if txt and text:find("%%s") then text = text:format(txt) end
        dlg.text:SetText(text)
        local labels = { d.button1, d.button2, d.button3 }
        for i, b in ipairs(dlg.buttons) do b:SetText(labels[i] or ""); b:SetShown(labels[i] ~= nil) end
        if d.OnShow then pcall(d.OnShow, dlg) end
        local n = 0
        for _, b in ipairs(dlg.buttons) do if b:IsShown() then n = n + 1 end end
        local bw = 110
        for i, b in ipairs(dlg.buttons) do
            b:SetWidth(math.max(bw, (b.fs:GetStringWidth() or 0) + 24))
        end
        local total = 0
        for _, b in ipairs(dlg.buttons) do if b:IsShown() then total = total + b:GetWidth() end end
        total = total + (n - 1) * 10
        local x = -total / 2
        for _, b in ipairs(dlg.buttons) do
            if b:IsShown() then b:ClearAllPoints(); b:SetPoint("BOTTOMLEFT", dlg, "BOTTOM", x, 14); x = x + b:GetWidth() + 10 end
        end
        local h = 12 + 12 + 5 + 10 + 8 + (dlg.text:GetStringHeight() or 40) + 16 + 24 + 14
        dlg:SetSize(math.max(380, total + 40), math.max(120, h))
        dlg:Show()
        if PlaySound and SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPEN then pcall(PlaySound, SOUNDKIT.IG_MAINMENU_OPEN) end
    end
end
