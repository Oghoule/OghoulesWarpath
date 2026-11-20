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
    panel = { 0.082, 0.078, 0.071 }, warn = { 0.84, 0.60, 0.40 }, edge = { 0.29, 0.25, 0.16 },
    cream = { 0.945, 0.886, 0.722 }, ink = { 0.91, 0.87, 0.78 }, dim = { 0.44, 0.39, 0.31 },
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
-- cadre de 1 px autour d'un frame
function Border(fr, col, a, layer)
    local out = {}
    for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        local t = Tex(fr, col or COL.line, a or 1, layer)
        if side == "TOP" or side == "BOTTOM" then t:SetHeight(1); t:SetPoint(side .. "LEFT"); t:SetPoint(side .. "RIGHT")
        else t:SetWidth(1); t:SetPoint("TOP" .. side); t:SetPoint("BOTTOM" .. side) end
        out[#out + 1] = t
    end
    return out
end
-- case oui/non en losange : contour dore toujours visible, petit losange rouge dedans quand c'est actif
-- (le losange plein seul = un choix parmi plusieurs)
function DiamondCheck(parent, size)
    size = size or 11
    local d = CreateFrame("Frame", nil, parent)
    d:SetSize(size + 6, size + 6)
    d.ring = Diamond(d, size, COL.accent, true); d.ring:SetPoint("CENTER")
    d.dot = Diamond(d, math.max(5, size - 4), COL.red); d.dot:SetPoint("CENTER")
    -- toujours au-dessus du contour (sinon le fond du contour peut le cacher)
    if d.dot.SetFrameLevel and d.ring.GetFrameLevel then d.dot:SetFrameLevel((d.ring:GetFrameLevel() or 1) + 2) end
    function d:SetOn(v)
        -- niveaux remis a chaque fois : contour au-dessus du cadre, losange rouge au-dessus du contour
        if self.GetFrameLevel and self.ring.SetFrameLevel then
            local l = self:GetFrameLevel() or 1
            self.ring:SetFrameLevel(l + 1); self.dot:SetFrameLevel(l + 3)
        end
        self.dot:SetShown(v and true or false)
        self.ring:SetStyle(v and COL.red or COL.gold, true)
    end
    d:SetOn(false)
    return d
end
-- boutons de la carte du monde : taille normale en plein ecran, plus petits sur la carte reduite
-- barre commune des boutons de la carte (en bas a gauche) : rangee 1 = trophees, rangee 2 = entraineurs.
-- Une seule echelle pour tous : 100 % en plein ecran, 72 % sur la carte reduite.
function MapBar()
    if MAPBAR then return MAPBAR end
    if not (WorldMapFrame and WorldMapFrame.ScrollContainer) then return nil end
    local bar = CreateFrame("Frame", "WarpathMapBar", WorldMapFrame.ScrollContainer)
    bar:SetSize(10, 10); bar:SetPoint("BOTTOMLEFT", WorldMapFrame.ScrollContainer, "BOTTOMLEFT", 8, 8)
    bar:SetFrameStrata("HIGH"); if bar.SetFrameLevel then bar:SetFrameLevel(50) end
    bar.rows = { {}, {} }
    function bar:Add(chip, row)
        chip:SetParent(self)
        if chip.SetFrameLevel then chip:SetFrameLevel(51) end
        if chip.mark and chip.mark.SetFrameLevel then chip.mark:SetFrameLevel(52) end
        local list = self.rows[row]
        chip:ClearAllPoints()
        if #list == 0 then chip:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", 0, (row - 1) * 26)
        else chip:SetPoint("LEFT", list[#list], "RIGHT", 6, 0) end
        list[#list + 1] = chip
    end
    local function scale()
        local big = WorldMapFrame.IsMaximized and WorldMapFrame:IsMaximized()
        local sc = big and 1 or 0.72
        if bar._sc ~= sc then bar._sc = sc; bar:SetScale(sc) end
    end
    WorldMapFrame:HookScript("OnShow", scale)
    local acc = 0
    WorldMapFrame:HookScript("OnUpdate", function(_, el) acc = acc + (el or 0); if acc < 0.2 then return end; acc = 0; scale() end)
    scale()
    MAPBAR = bar
    return bar
end
function ChipScale(...)
    local big = WorldMapFrame and WorldMapFrame.IsMaximized and WorldMapFrame:IsMaximized()
    local sc = big and 1 or 0.72
    if MAPBAR then return end -- la barre commune s'en charge
    for _, b in ipairs({ ... }) do if b and b.SetScale and b._sc ~= sc then b._sc = sc; b:SetScale(sc) end end
end
-- titre de section aligne a gauche : LA SUITE
function SectionHead(parent, w)
    local d = CreateFrame("Frame", nil, parent)
    d:SetSize(w, 12)
    d.label = FS(d, 10, COL.gold, FONT, "LEFT"); d.label:SetPoint("LEFT")
    return d
end
-- bouton a bascule (carte du monde) : case + libelle, liseré rouge a gauche quand c'est actif
function Chip(parent, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(150, 22)
    local bg = Tex(b, COL.bg, 0.90, "BACKGROUND"); bg:SetAllPoints()
    Border(b, COL.line)
    b.bar = Tex(b, COL.red, 1, "ARTWORK"); b.bar:SetWidth(2); b.bar:SetPoint("TOPLEFT"); b.bar:SetPoint("BOTTOMLEFT")
    local hl = Tex(b, COL.accent, 0.10, "HIGHLIGHT"); hl:SetAllPoints()
    b.mark = DiamondCheck(b, 10); b.mark:SetPoint("LEFT", 6, 0)
    b.label = FS(b, 9, COL.gold, FONT, "LEFT"); b.label:SetPoint("LEFT", b.mark, "RIGHT", 5, 0)
    function b:SetState(text, on)
        self.label:SetText(text)
        self:SetWidth(math.max(110, (self.label:GetStringWidth() or 130) + 34))
        self.bar:SetShown(on and true or false); self.mark:SetOn(on)
        local c = on and COL.white or COL.faint
        if self.label.SetTextColor then self.label:SetTextColor(c[1], c[2], c[3]) end
    end
    b:SetScript("OnClick", onClick)
    return b
end
-- bouton plat : fond sombre, filet de 1 px, texte en capitales espacees
function FlatButton(parent, w, h, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(w, h)
    Border(b, COL.edge)
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
FIXED_H = math.floor(W * 640 / 340 + 0.5) -- proportions de la maquette (340 x 640) (plus utilise pour la hauteur)
MIN_H = 330                                 -- v1.41 : hauteur minimale ; au-dela, la fenetre suit son contenu
DL = { rows = {}, n = 0 }   -- mode donjon : lignes du journal, detail ouvert
INNER = W - 2 * PAD
distTarget = nil -- { m, x, y } : prochaine position a atteindre (pour la distance affichee)

-- icone de la liste « La suite » selon le type d'etape (textures du jeu)
-- icones de l'addon (blanches, teintees ici) : rendre = fleche retour verte, prendre = ! dore, faire = epees
STEP_ICON = {
    accept = "Interface\\AddOns\\OghoulesWarpath\\Media\\IcoAccept", turnin = "Interface\\AddOns\\OghoulesWarpath\\Media\\IcoTurnin",
    ["do"] = "Interface\\AddOns\\OghoulesWarpath\\Media\\IcoDo",
}
STEP_TINT = { accept = COL.accent, turnin = COL.green, ["do"] = COL.gold }
function SetUpcoming(items, passed)
    if not f or not f.up then return end
    -- v1.41 (audit, proposition A) : 2 etapes a venir, « +N ▾ » pour deplier jusqu'a 4 (DB.upOpen)
    local limit = DB.upOpen and 4 or 2
    local more = math.max(0, math.min(#items, 4) - 2)
    f.nUp = math.min(#items, limit)
    local tg = rawget(f, "upToggle")
    if tg then
        -- (la police du jeu n'a pas les fleches ▾ ▴ : un petit carre s'affichait)
        tg.fs:SetText(more > 0 and (DB.upOpen and "-" or ("+" .. more)) or "")
        tg:SetShown(more > 0)
    end
    for k = 1, 4 do
        local b, it = f.up[k], (k <= limit) and items[k] or nil
        if it then
            b.idx = it.idx; b.fs:SetText(it.text)
            if b.fs.SetTextColor then local c = (k == 1) and COL.white or COL.soft; b.fs:SetTextColor(c[1], c[2], c[3]) end
            if b.right then b.right:SetText(it.right or "") end
            if b.icon then
                b.icon:SetTexture(it.icon or ("Interface\\AddOns\\" .. (ADDON or "OghoulesWarpath") .. "\\Media\\Gem"))
                b.icon:SetSize(it.icon and 14 or 8, it.icon and 14 or 8)
                local c = it.tint or COL.gold
                if b.icon.SetVertexColor then b.icon:SetVertexColor(c[1], c[2], c[3]) end
            end
            b:Show()
        else b.idx = nil; b:Hide() end
    end
    if f.passed then
        f.passed:SetText((passed or 0) > 0 and T("passedN", passed) or "")
        f.passed:SetShown((passed or 0) > 0 and #items > 0)
    end
end

-- Place les blocs visibles les uns sous les autres et ajuste la hauteur
function Layout()
    -- (v1.41 : 24 px sous l'en-tete au lieu de 14, pour que « Step x / y » au-dessus de la barre respire)
    local y = -(HEAD_H or 34) - 24
    local function put(obj, h, gap, x)
        obj:ClearAllPoints()
        obj:SetPoint("TOPLEFT", f, "TOPLEFT", x or PAD, y)
        y = y - h - (gap or 0)
    end
    local function sh(fs, min) local h = fs.GetStringHeight and fs:GetStringHeight(); return (type(h) == "number" and h > 0) and h or (min or 12) end
    if f.name then f.name:Hide() end
    if f.div then f.div:Hide() end
    if f.progBg then put(f.progBg, 3, 18) end
    local il = rawget(f, "infoLine")
    if il and il:IsShown() then put(il, sh(il, 10), 14) end
    -- Intendance : icone de l'en-tete en capitale (pas pendant une tournee ni dans un donjon)
    local qb = rawget(f, "qmBtn")
    if qb then
        local inCity = QMCity and QMCity() and not DB.qm and not (IS_DUNGEON and IS_DUNGEON[DB.guide] and DungeonLogActive and DungeonLogActive())
        qb:SetShown(inCity and true or false)
        -- icones de l'en-tete, de droite a gauche : « - », sac (en capitale), « ? » ; le titre s'arrete avant
        local hb = rawget(f, "helpBtn")
        if hb then hb:ClearAllPoints(); hb:SetPoint("RIGHT", inCity and qb or f.miniBtn, "LEFT", -2, 0) end
        f.title:ClearAllPoints(); f.title:SetPoint("LEFT", f, "TOPLEFT", PAD + 12, -(HEAD_H or 34) / 2)
        f.title:SetPoint("RIGHT", f, "TOPRIGHT", inCity and -62 or -44, -(HEAD_H or 34) / 2)
    end
    -- en-tete de l'etape : badge de niveau a gauche, type + titre a droite
    local badge = f.badge and f.badge:IsShown()
    local bx = badge and (PAD + 42) or PAD
    local bw = badge and (INNER - 42) or INNER
    local top = y
    if badge then f.badge:ClearAllPoints(); f.badge:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, y - 1) end
    if f.kind:IsShown() then f.kindRow:SetWidth(bw); f.kind:SetWidth(bw); put(f.kindRow, 15, 5, bx) end   -- (11 px depuis la v1.41)
    if f.qtitle:IsShown() then f.qtitle:SetWidth(bw); put(f.qtitle, sh(f.qtitle, 20), 5, bx) end
    if f.qsub and f.qsub:IsShown() then f.qsub:SetWidth(bw); put(f.qsub, sh(f.qsub, 12), 0, bx) end
    if badge and (top - y) < 46 then y = top - 46 end
    y = y - 18
    if f.dest and f.dest:IsShown() then
        if DB.compact then f.coord:Hide() end
        -- hauteur selon le lieu (1 ou 2 lignes) et la ligne de precision
        local dh = math.max(34, 18 + sh(f.destName, 12) + (f.coord:IsShown() and 15 or 0))
        f.dest:SetHeight(dh); put(f.dest, dh, 18)
    end
    local any = false
    for k = 1, 3 do if f.route[k]:IsShown() then put(f.route[k], 16, 2); any = true end end
    if any then y = y - 12 end
    local no = rawget(f, "nObj") or 0
    if no > 0 then
        for k = 1, no do
            local w = f.obj[k]
            if w.kind == "obj" then put(w, 20, 2)
            else
                if k > 1 then y = y - 6 end
                put(w, w.kind == "verb" and 14 or 16, 2)
            end
        end
        y = y - 16
    end
    if f.text:IsShown() then put(f.text, sh(f.text), 18) end
    if (DL.n or 0) > 0 then
        for k = 1, DL.n do
            local r = DL.rows[k]
            if r and r:IsShown() then
                put(r, 17, 1)
                if DL.tip and DL.tip:IsShown() and DL.after == k then put(DL.tip, sh(DL.tip), 6, PAD + 14) end
            end
        end
        y = y - 8
    end
    -- v1.41 (audit, proposition A) : chaine et quetes bloquees ne prennent plus de ligne : deux pastilles a droite
    -- de la ligne du type d'etape. Les anciennes lignes gardent leur logique (etat, clic) mais restent invisibles.
    for _, b in ipairs({ f.chainBtn, f.lockBtn }) do
        if b.SetAlpha then b:SetAlpha(0) end
        if b.EnableMouse then b:EnableMouse(false) end
    end
    local cc, cl = rawget(f, "chipChain"), rawget(f, "chipLock")
    if cc and cl then
        local ch = f.chainBtn:IsShown() and f.chainInfo
        cc:SetShown(ch and true or false)
        if ch then
            cc.fs:SetText(ch.pos .. "/" .. ch.len); cc:SetWidth(22 + (cc.fs.GetStringWidth and cc.fs:GetStringWidth() or 18))
            cc.tipText = T("chainLine", ch.pos, ch.len)
        end
        local nl = f.lockBtn:IsShown() and #(f.lockBtn.list or {}) or 0
        cl:SetShown(nl > 0)
        if nl > 0 then cl.fs:SetText(tostring(nl)); cl:SetWidth(22 + (cl.fs.GetStringWidth and cl.fs:GetStringWidth() or 8)) end
        cl:ClearAllPoints(); cl:SetPoint("RIGHT", f.kindRow, "RIGHT", 0, 0)
        cc:ClearAllPoints(); cc:SetPoint("RIGHT", nl > 0 and cl or f.kindRow, nl > 0 and "LEFT" or "RIGHT", nl > 0 and -5 or 0, 0)
        -- le texte du type d'etape s'arrete avant les pastilles
        local cw = (cc:IsShown() and (cc:GetWidth() + 6) or 0) + (cl:IsShown() and (cl:GetWidth() + 6) or 0)
        if f.kind.SetWidth then f.kind:SetWidth(math.max(40, bw - cw)) end
    end
    if f.caveBtn and f.caveBtn:IsShown() then put(f.caveBtn, 18, 14) end
    if f.nowBtn and f.nowBtn:IsShown() then put(f.nowBtn, 24, 14) end
    if f.advice and f.advice:IsShown() then
        local ah = math.max(16, (f.advice.label.GetStringHeight and f.advice.label:GetStringHeight() or 12) + 4)
        f.advice:SetHeight(ah); put(f.advice, ah, 14)
    end
    if DB.compact then for k = 1, 4 do f.up[k]:Hide() end; if f.passed then f.passed:Hide() end end
    if (f.nUp or 0) > 0 and not DB.compact then
        f.nextRule:Show(); put(f.nextRule, 12, 8)
        for k = 1, 4 do if f.up[k]:IsShown() then put(f.up[k], 26, 0) end end
        if f.passed and f.passed:IsShown() then put(f.passed, 22, 0, PAD + 22) end
    else
        f.nextRule:Hide(); if f.passed then f.passed:Hide() end
    end
    -- bas de la fenetre : boutons et pied ancres en bas, hauteur fixe aux proportions de la maquette
    -- (la fenetre ne grandit que si le contenu depasse)
    local xl = rawget(f, "xph")
    local foot = rawget(f, "foot")
    -- v1.41 : plus de pied (niveau, XP/h) a la demande de l'auteur : ces infos sont au survol de la barre
    -- de progression de la zone (f.progHit, Window.lua)
    local footOn = false
    if xl then xl:Hide() end
    local BOT = 16
    local bottomH = 34 + (footOn and (16 + 13) or 0) + BOT
    -- v1.41 (audit) : la hauteur suit le contenu (plus de bande vide), avec un minimum pour que la fenetre
    -- ne change pas trop de taille d'une etape a l'autre (avant : hauteur fixe aux proportions de la maquette)
    local h = math.max(DB.compact and 0 or MIN_H, -y + 24 + bottomH)
    f:SetHeight(h)
    if foot then
        foot:SetShown(footOn and true or false)
        if footOn then foot:ClearAllPoints(); foot:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", PAD, BOT) end
    elseif xl and xl:IsShown() then xl:ClearAllPoints(); xl:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", PAD, BOT) end
    f.btnRow:ClearAllPoints(); f.btnRow:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", PAD, BOT + (footOn and 29 or 0))
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

-- v1.41 (audit) : le bouton du bas change de role selon l'etape ; une icone de l'addon devant le mot le montre
SKIP_ICON = { ok = "IcoOk", ignore = "IcoSkip", dgBack = "IcoTurnin", restore = "IcoUndo", dgExit = "IcoTurnin" }
function SetSkip(key)
    if not (f and f.skip) then return end
    f.skip:SetLabel(Caps(T(key)))
    local ic = rawget(f.skip, "icon")
    if ic then
        local name = SKIP_ICON[key]
        if name then ic:SetTexture("Interface\\AddOns\\" .. (ADDON or "OghoulesWarpath") .. "\\Media\\" .. name) end
        ic:SetShown(name ~= nil)
    end
end

function SetChain(ch)
    f.chainInfo = ch   -- (lu par la pastille de chaine, Layout)
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
    if NearTick then pcall(NearTick) end
    if CheckDungeonLeft then pcall(CheckDungeonLeft) end
    -- v1.41 : conseil (pierre de foyer...) recalcule quand tu te deplaces : avant, il restait celui de l'endroit
    -- ou la fenetre avait ete mise a jour (ex. « retour a Sun Rock » alors que tu y etais deja arrive a pied)
    if adviceArgs and Advice and GetTime and GetTime() - (adviceT or 0) > 3 then
        adviceT = GetTime()
        local ok, adv = pcall(Advice, adviceArgs[1], adviceArgs[2])
        if ok and (adv and adv.text) ~= (currentAdvice and currentAdvice.text) then Refresh() end
    end
    local me = PlayerWP()
    local w = distTarget and WP(distTarget[1], distTarget[2], distTarget[3])
    if me and w and me[3] == w[3] then
        f.dist:SetText(T("dist", math.floor(Dist(me[1], me[2], w[1], w[2]) + 0.5)))
    else
        f.dist:SetText("")
    end
    -- etape "va a" : validee toute seule quand tu arrives (moins de 20 m), comme si tu cliquais OK
    if not peek and steps and me and not autoGoBusy then
        local i = focus or current
        local s = steps[i]
        if s and s.t == "go" and s.m and s.x and not doneCache[i] and not IS_DUNGEON[DB.guide] then
            local g = WP(s.m, s.x, s.y)
            if g and g[3] == me[3] and Dist(me[1], me[2], g[1], g[2]) < 20 then
                autoGoBusy = true
                DB.seen[SeenKey(i)] = true
                focus = nil; lastWP = nil
                pcall(Advance); Refresh(true)
                autoGoBusy = false
            end
        end
    end
end

-- objectifs en direct, une ligne chacun : case, nom, compteur aligne a droite
function SetObjRows(rows)
    f.obj = rawget(f, "obj") or {}
    local n = 0
    for k, r in ipairs(rows or {}) do
        if k > 14 then break end
        local w = f.obj[k]
        if not w then
            w = CreateFrame("Frame", nil, f); w:SetSize(INNER, 20)
            w.icon = w:CreateTexture(nil, "ARTWORK"); w.icon:SetSize(14, 14); w.icon:SetPoint("LEFT", 0, 0)
            w.count = FS(w, 12, COL.gold, FONT, "RIGHT"); w.count:SetPoint("RIGHT", 0, 0)
            w.name = FS(w, 12, COL.ink, FONT, "LEFT"); w.name:SetPoint("LEFT", 22, 0); w.name:SetPoint("RIGHT", w.count, "LEFT", -8, 0)
            if w.name.SetWordWrap then w.name:SetWordWrap(false) end
            f.obj[k] = w
        end
        w.kind = r.k
        w.done = r.done and true or false   -- (lu par le mode compact)
        w.name:ClearAllPoints()
        if r.k == "obj" then
            w.icon:SetTexture("Interface\\AddOns\\" .. (ADDON or "OghoulesWarpath") .. "\\Media\\" .. (r.done and "BoxDone" or "Box")); w.icon:Show()
            w.name:SetPoint("LEFT", 22, 0); w.name:SetPoint("RIGHT", w.count, "LEFT", -8, 0)
            if w.name.SetFont then w.name:SetFont(FONT, 12, "") end
            w.name:SetText(r.text); w.count:SetText(r.count or "")
            local c = r.done and COL.dim or COL.ink
            if w.name.SetTextColor then w.name:SetTextColor(c[1], c[2], c[3]) end
            c = r.done and COL.dim or COL.gold
            if w.count.SetTextColor then w.count:SetTextColor(c[1], c[2], c[3]) end
        else
            w.icon:Hide(); w.count:SetText("")
            w.name:SetPoint("LEFT", 0, 0); w.name:SetPoint("RIGHT", 0, 0)
            if w.name.SetFont then w.name:SetFont(FONT, r.k == "verb" and 9 or 11, "") end
            w.name:SetText(r.k == "verb" and Caps(r.text) or r.text)
            local c = r.k == "verb" and COL.accent or COL.gold
            if w.name.SetTextColor then w.name:SetTextColor(c[1], c[2], c[3]) end
        end
        w:Show(); n = k
    end
    for k = n + 1, #f.obj do f.obj[k]:Hide() end
    f.nObj = n
end
-- en-tete : zone a gauche, etape a droite, barre de progression rouge
function SetHeader(zone, right, frac)
    f.title:SetText(Caps(zone or ""))
    -- nom long (ex. STONETALON MOUNTAINS) : capitales sans espacement s'il ne tient pas ; sinon coupe avec « … »
    local sw = (f.title.GetUnboundedStringWidth and f.title:GetUnboundedStringWidth()) or (f.title.GetStringWidth and f.title:GetStringWidth())
    local aw = f.title.GetWidth and f.title:GetWidth()
    if type(sw) == "number" and type(aw) == "number" and aw > 0 and sw > aw then f.title:SetText(Upper(zone or "")) end
    if f.stepNo then f.stepNo:SetText(right or "") end
    if f.progFill then
        frac = math.max(0, math.min(1, frac or 0))
        f.progFill:SetWidth(math.max(1, INNER * frac)); f.progFill:SetShown(frac > 0)
    end
end
-- coupe « Lieu (precision) » en deux pour le bloc destination
function SplitPlace(txt)
    txt = (txt or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("%s+$", "")
    txt = txt:gsub("%.$", "")
    -- « Prends la quete aupres de X » / « Rends la quete a X » : seul le PNJ compte
    for _, pre in ipairs({ "Prends la quête auprès de ", "Prends la quête auprès d'", "Rends la quête à ", "Rends la quête au ",
                           "Accept the quest from ", "Turn in the quest to " }) do
        if txt:sub(1, #pre) == pre then txt = txt:sub(#pre + 1); break end
    end
    local zp, rest = txt:match("^(.-) %- (.+)$")
    if zp and rest then return rest, zp end
    local a, b = txt:match("^(.-)%s*%((.-)%)%s*$")
    if a and a ~= "" then return a, b end
    for _, sep in ipairs({ ", à ", ", au ", ", aux ", ", in ", ", at ", ", near ", ", près de " }) do
        local i = txt:find(sep, 1, true)
        if i and i > 1 then return txt:sub(1, i - 1), txt:sub(i + #sep) end
    end
    return txt, nil
end
function RefreshInner(forceWP)
    if not f then return end
    SetObjRows(nil)
    f.name:SetText(Caps(WarpathName()))
    if not steps then
        SetHeader("", "", 0); f.summary = T("noGuide")
        if f.badge then f.badge:Hide(); f.qsub:Hide(); f.dest:Hide() end
        f.kind:Hide(); f.qtitle:Hide(); f.text:SetText(T("noGuide")); f.text:Show()
        f.coord:SetText(""); f.coord:Hide(); f.list:SetText(""); SetUpcoming({}); SetRoute({}); SetChain(nil)
        distTarget = nil; Layout()
        return
    end
    local n = #steps
    if not peek and not focus and DungeonLogActive() then
        DungeonLogRender()
        if ns.UI and ns.UI.RefreshOptions then ns.UI.RefreshOptions() end
        return
    end
    DungeonLogHide()
    if f.caveBtn then f.caveBtn:Hide() end
    local i = peek or focus or current
    if f.nowBtn then
        local away = (peek or focus) and steps[current] and (peek or focus) ~= current
        if away then f.nowBtn.label:SetText(T("backNow", current, (QName(steps[current]) and QName(steps[current]) ~= "") and QName(steps[current]) or (StepText(steps[current]):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):sub(1, 32) .. "…"))) end
        f.nowBtn:SetShown(away and true or false)
    end
    local s = steps[i]
    if not s then
        SetHeader(Title(G), T("finished"), 1)
        if f.badge then f.badge:Hide(); f.qsub:Hide(); f.dest:Hide() end
        f.summary = T("endGuide")
        f.kind:Hide(); f.qtitle:Hide(); f.text:SetText(T("endGuide")); f.text:Show()
        f.coord:SetText(""); f.coord:Hide(); f.list:SetText(""); SetUpcoming({}); SetRoute({}); SetChain(nil)
        ClearWaypoint(); lastWP = nil; distTarget = nil
        SetSkip("ok")
        UpdateDistance(); Layout()
    else
        local zone = Title(G):gsub("%s*%b()", ""):gsub("%s+%d+%-%d+$", "")
        if IS_DUNGEON[DB.guide] then zone = zone:gsub("^[^:]+:%s*", "") end
        SetHeader(zone, T("stepOf", i, n), i / n)
        local st = peek and doneCache[i]
        -- prise impossible tant qu'un prerequis du journal n'est pas fini : on guide vers ce prerequis
        local det = (not peek) and ((TrainDetour and TrainDetour(s)) or (PrereqDetour and PrereqDetour(s))) or nil
        local g = det and { t = det.done and "turnin" or "do", id = det.id, m = det.m, x = det.x, y = det.y,
                            zone = MAPNAME[det.m] or s.zone, quest = det.name } or s
        -- grotte (entree/sortie) ou objet au sol le plus proche : la fleche vise ce point
        local sp = (not peek and (not det or DB.errand or DB.qm) and StepPoint) and StepPoint(s) or nil
        if sp then g = { t = s.t, id = s.id, m = sp.m, x = sp.x, y = sp.y, zone = sp.name or s.zone, quest = s.quest } end
        if f.caveBtn then
            local cave = sp and (sp.kind == "enter" or sp.kind == "exit")
            if cave then f.caveBtn.label:SetText("|cff8c7f62" .. T("caveWrong") .. "|r") end
            f.caveBtn:SetShown(cave and true or false)
        end
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
        local nq = (s.quest and type(s.id) == "table") and #s.id or 1
        kc = "cdbb8e"
        f.kind:SetText("|cff" .. kc .. Caps(T(s.t)) .. "|r" .. (nq > 1 and ("  |cff8c7f62·|r  |cff" .. kc .. Caps(T("nQuests", nq)) .. "|r") or "")
            .. (s.optional and ("   |cff8c7f62" .. T("optional") .. "|r") or "")
            .. (st == "done" and ("  " .. CHECK .. " |cff9cc7a8" .. T("stepDone") .. "|r")
                or st == "skip" and ("   |cff8c7f62" .. T("skipped") .. "|r")
                or peek and ("   |cffd69a66" .. T("stepTodo") .. "|r") or "")
            .. ((not peek and focus) and ("   |cffcdbb8e" .. T("chosen") .. "|r") or "")
            .. ((not peek and not focus and nearKind and i == current) and ("   |cff9cc7a8" .. T(nearKind == "pass" and "nearPass" or "nearNear") .. "|r") or ""))
        -- rendement estime (quete + monstres) compare au simple farm de monstres de ton niveau
        f.rateTip = nil
        if (s.t == "do" or (s.optional and s.t == "accept")) and type(s.id) == "number" and EST[s.id] then
            local e = Estimate({ s.id }, false)
            if e.secs > 0 and e.perHour > 0 then
                local p = UnitLevel("player") or 1
                local grind = MobXP(p, p, 0) * 3600 / KillTime()
                local tag = (e.perHour >= grind * 1.3) and ("  |cff9cc7a8" .. T("rateGood") .. "|r")
                    or (e.perHour < grind * 0.7) and ("  |cffd69a66" .. T("rateBad") .. "|r") or ""
                f.kind:SetText(f.kind:GetText() .. tag)
                f.rateTip = T("xpRate", FormatNum(e.perHour))
            end
        end
        f.kind:Show()
        local qn = s.quest and QName(s)
        if qn and qn ~= "" then
            -- niveau de la quete, colore selon la difficulte (gris / vert / jaune / orange / rouge)
            local qid = type(s.id) == "number" and s.id or (type(s.id) == "table" and s.id[1])
            local ql = qid and EST[qid] and EST[qid].l
            if f.badge then
                if ql and ql > 0 then
                    local c = GetQuestDifficultyColor and GetQuestDifficultyColor(ql)
                    f.badge.num:SetText(ql); f.badge.lbl:SetText(T("lvlShort"))
                    -- niveau de la QUETE, colore selon la difficulte pour toi (comme le journal de quetes)
                    if type(c) == "table" and f.badge.num.SetTextColor then f.badge.num:SetTextColor(c.r or 1, c.g or 1, c.b or 1) end
                    f.badge:Show()
                else f.badge:Hide() end
            end
            -- plusieurs quetes : la premiere en titre, les autres dessous
            local main, rest = qn:match("^(.-) %+ (.+)$")
            f.qtitle:SetText(main or qn); f.qtitle:Show()
            if f.qsub then
                f.qsub:SetText(rest and (rest:gsub(" %+ ", " · ")) or ""); f.qsub:SetShown(rest ~= nil)
                -- v1.41 : prise groupee commencee : combien sont prises, et lesquelles manquent (OK les saute)
                if s.t == "accept" and type(s.id) == "table" and #s.id > 1 then
                    local have, miss = 0, {}
                    for _, id in ipairs(s.id) do
                        if logById[id] ~= nil or Rendue(id) or DB.ignored[id] then have = have + 1
                        else miss[#miss + 1] = (QuestTitle and QuestTitle(id)) or (EST[id] and EST[id].n) or tostring(id) end
                    end
                    if have > 0 and #miss > 0 then
                        f.qsub:SetText((f.qsub:GetText() or "") .. "\n|cffd69a66" .. T("grpMissing", have, #s.id, table.concat(miss, ", ")) .. "|r")
                        f.qsub:Show()
                    end
                end
            end
        else
            f.qtitle:Hide()
            if f.badge then f.badge:Hide(); f.qsub:Hide() end
        end
        -- etape "faire" : objectifs en direct (le texte complet passe dans l'infobulle du titre)
        local live, lead, orows
        if LiveObjectives then live, lead, orows = LiveObjectives(s) end
        f.objPlain = live
        if orows and #orows > 0 then SetObjRows(orows); live = "" end
        -- prendre / rendre : le PNJ et son lieu vont dans le bloc destination (texte court d'une ligne)
        local st0 = StepText(s) or ""
        if not live and not det and (s.t == "accept" or s.t == "turnin") and not st0:find("\n") and #st0 <= 80 and st0 ~= "" then
            lead = st0
        end
        local body = live or (lead and "" or st0)
        f.qtitleTip = live and StepText(s) or nil
        -- astuce de quete (Tips.lua)
        f.tipText = nil
        if DB.tips ~= false and ns.Tips and s.t ~= "note" then
            local qid = type(s.id) == "number" and s.id or (type(s.id) == "table" and s.id[1])
            local tip = qid and ns.Tips[qid]
            f.tipText = tip and ((Lang() == "en") and tip[2] or tip[1]) or nil
            if tip then body = body .. "\n\n|cffd6b866" .. T("tipLbl") .. "|r  |cff8c7f62" .. T("tipHint") .. "|r" end
        end
        -- taux de drop des objets encore a trouver (tes mesures + groupe/guilde, sinon Questie)
        if s.t == "do" or (det and not det.done) then
            local lines = {}
            for _, q in ipairs(det and { det.id } or Ids(s)) do
                if logById[q] == false and EST[q] then
                    for _, dr in ipairs(Estimate({ q }, false).drops) do
                      -- deja affiche a cote des monstres dans « Cibles de l'objectif » : pas de doublon ici
                      if not (dr.mobs and DB.targets ~= false) then
                        local pct = math.floor(dr.rate * 100 + 0.5)
                        local how = (dr.how == "unique") and T("dropHowUnique") or (dr.how == "measured") and T("dropHowMeasured", dr.k)
                            or (dr.how == "questie") and T("dropHowQuestie", dr.k or 0) or T("dropHowAssumed", dr.k or 0)
                        lines[#lines + 1] = (dr.name or "?") .. " : |cffffd100" .. pct .. " %|r  |cff8c7f62" .. how .. "|r"
                      end
                    end
                end
            end
            if #lines > 0 then body = body .. "\n\n|cffd6b866" .. T("dropLbl") .. "|r\n" .. table.concat(lines, "\n") end
        end
        -- donjon : un objectif a faire apres l'entree se fait avec le groupe (les monstres pres de l'entree sont
        -- souvent elites, meme hors du portail)
        if s.t == "do" and IS_DUNGEON[DB.guide] and s.m then
            local ent
            for j = 1, n do if steps[j].t == "go" then ent = j; break end end
            if ent and i > ent then body = "|cffd69a66" .. T("dgGroup") .. "|r\n\n" .. body end
        end
        if det and det.train then body = "|cffd69a66" .. T("trainStep", det.name) .. "|r\n\n" .. body
        elseif det then body = "|cffd69a66" .. T(det.done and "preTurnin" or "preDo", det.name) .. "|r\n\n" .. body end
        -- quetes pas encore prises faute de niveau, quetes laissees pour plus tard, et la suite
        if not peek then
            local lw = LevelWaitLines and LevelWaitLines(s) or {}
            if #lw > 0 then body = body .. "\n\n" .. ListBlock(T("lvlWaitHdr"), lw, "d69a66") end
            local hn = HubNotes and HubNotes(i)
            if hn then body = body .. "\n\n" .. hn end
            local tg = TurninGroup and TurninGroup(i)
            if tg then body = tg .. "\n\n" .. body end
            local ag = AcceptGroup and AcceptGroup(i)
            if ag then body = ag .. "\n\n" .. body end
            local fu = FollowUpAccepts and FollowUpAccepts(i)
            if fu then body = body .. "\n\n" .. fu end
            local ow = OnTheWay and OnTheWay(i)
            if ow then body = body .. "\n\n" .. ow end
            local dt = DeathTip and DeathTip(i)
            -- conseil de mort : dans l'infobulle du titre, une seule ligne dans la fenetre
            if dt then
                local had = type(rawget(f, "tipText")) == "string"
                f.tipText = (had and (f.tipText .. "\n\n") or "") .. dt
                if not had then body = body .. "\n\n|cffd6b866" .. T("tipLbl") .. "|r  |cff8c7f62" .. T("tipHint") .. "|r" end
            end
        end
        -- donjon : toutes les quetes en main, on marche sur l'entree
        if s.t == "go" and IS_DUNGEON[DB.guide] and not peek then body = "|cffd6b866" .. DungeonLore(zone) .. "|r\n\n" .. body end
        body = body:gsub("^%s+", "")
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
            local area = (#legs == 0) and ((sp and sp.kind == "farm") or ((not sp or sp.kind == "zone") and ((det and not det.done) or (not det and s.t == "do")))) or false
            distTarget = first.m and { first.m, first.x, first.y, area } or nil
            -- bloc destination : le lieu (celui du texte de l'etape s'il est precise), puis precision et coordonnees
            local nm, extra = first.name or "", nil
            if lead and lead ~= "" and #legs == 0 and not sp then nm, extra = SplitPlace(lead)
            elseif lead and lead ~= "" and not live then
                body = lead .. (body ~= "" and ("\n\n" .. body) or ""); f.text:SetText(body); f.text:Show()
            end
            if sp and sp.kind == "farm" then nm, extra = sp.name, T("farmSub", sp.lmin, sp.lmax, sp.n)
            elseif sp and sp.kind == "pass" then extra = T("tunnelVia")
            elseif sp and sp.kind == "trail" then extra = T(sp.out and "trailOutSub" or "trailInSub")
            elseif sp and sp.kind == "gate" then extra = T("gateVia")
            elseif sp and sp.kind == "citycave" then nm, extra = sp.name or nm, T("caveEnter")
            elseif sp and sp.kind == "errand" then nm, extra = sp.name or nm, T("errandSub")
            elseif sp and sp.kind == "qm" then nm, extra = sp.label or nm, T("qmStopN", sp.idx or 1, sp.n or 1)
            elseif sp and sp.kind == "zone" then nm, extra = sp.name ~= "" and sp.name or nm, T("zoneCamp", sp.idx or 1, sp.n or 2)
            elseif sp and sp.kind == "enter" then extra = T("caveEnter") elseif sp and sp.kind == "exit" then extra = T("caveExit"):lower() end
            if fl then nm, extra = fl.from.name, T("flight") .. " > " .. fl.to.name
            elseif tr then nm, extra = MAPNAME[tr.from[1]] or nm, T(tr.kind == "boat" and "boat" or "zep") .. " > " .. tr.dest end
            if f.destName then f.destName:SetText(nm ~= "" and nm or (MAPNAME[first.m] or "")) end
            local cx, cy = first.x, first.y
            if fl then cx, cy = fl.from.x, fl.from.y elseif tr then cx, cy = tr.from[2], tr.from[3] end
            -- v1.41 (audit) : la precision seulement ; les coordonnees passent dans l'infobulle du bloc
            f.coord:SetText(extra or ""); f.coord:SetShown(extra ~= nil and extra ~= "")
            f.destCoord = string.format("%.1f, %.1f", cx, cy) .. ((MAPNAME[fl and fl.from.m or (tr and tr.from[1]) or first.m]) and ("  ·  " .. MAPNAME[fl and fl.from.m or (tr and tr.from[1]) or first.m]) or "")
            if f.dest then f.dest:Show() end
        else
            distTarget = nil
            f.coord:SetText(""); f.coord:Hide()
            if f.dest then f.dest:Hide() end
            -- pas de point sur la carte : le lieu reste dans le texte
            if lead and lead ~= "" then
                body = live and (lead .. " :\n" .. body) or (lead .. (body ~= "" and ("\n\n" .. body) or ""))
                f.text:SetText(body); f.text:SetShown(body ~= "")
            end
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
            -- apres l'entree : seulement les remises (les objectifs du donjon sont dans le journal du donjon)
            for j = (entrance or n + 1), n do
                if Applies(steps[j]) and j ~= i and steps[j].t ~= "do" and not doneCache[j] then seq[#seq + 1] = j end
            end
        else
            local j = i
            -- etape choisie par proximite : l'etape du guide qu'on a devancee reste en tete de la liste
            if not peek and not focus and baseCurrent and baseCurrent < i then seq[1] = baseCurrent; j = baseCurrent end
            while #seq < 4 do
                j = NextApplicable(j)
                if j == i then j = NextApplicable(j) end
                if j > n then break end
                seq[#seq + 1] = j
            end
        end
        local items, passed = {}, 0
        local me = PlayerWP()
        for _, j in ipairs(seq) do
            if #items >= 4 then break end
            local t = steps[j]
            if doneCache[j] then
                passed = passed + 1
            else
                local nm = QName(t) or StepText(t):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):sub(1, 45)
                local verb = T(t.t) or ""
                verb = verb ~= "" and (Upper(verb:sub(1, 1)) .. verb:sub(2):lower() .. " ") or ""
                local label = verb .. (chainOf[j] and ("|cffa99cc0" .. nm .. "|r") or nm)
                local right
                local w = me and t.m and t.x and WP(t.m, t.x, t.y)
                if w and w[3] == me[3] then right = T("dist", math.floor(Dist(me[1], me[2], w[1], w[2]) + 0.5)) end
                items[#items + 1] = { idx = j, text = label, icon = STEP_ICON[t.t], tint = STEP_TINT[t.t], right = right }
            end
        end
        f.list:SetText(#items > 0 and (Caps(T("thenLbl")) .. (dynOrder and ("   |cffcdbb8e" .. T("optimized") .. "|r") or "")) or "")
        SetUpcoming(items, passed)
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
        if not peek and not focus and DB.dgOut and DB.dgOut[DB.guide] and InDgInstance() then
            SetSkip("dgBack")
        elseif Restorable(i) then
            SetSkip("restore")
            f.kind:SetText(f.kind:GetText() .. "   |cffd69a66" .. T("restoreHint") .. "|r")
        else
            SetSkip((s.t == "note" or s.t == "go" or s.t == "level") and "ok" or "ignore")
        end
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
        adviceArgs = (not peek) and { i, g } or nil   -- pour le revoir quand tu te deplaces (UpdateDistance)
        if adv and f.advice then
            f.advice.icon:SetTexture(adv.icon); f.advice.label:SetText(adv.text); f.advice:Show()
            local c = adv.tint or { 1, 1, 1 }
            if f.advice.icon.SetVertexColor then f.advice.icon:SetVertexColor(c[1], c[2], c[3]) end
            if HearthButton then pcall(HearthButton, adv.kind == "use") end
        elseif f.advice then f.advice:Hide(); if HearthButton then pcall(HearthButton, false) end end
        if ns.Targets then ns.Targets.Update(det and g or s) end
        local wpKey = (det and ("pre" .. det.id .. (det.done and "d" or "") .. ">") or "") .. (sp and (sp.kind .. sp.x .. ":" .. sp.y .. ">") or "") .. i .. (tr and (":" .. tr.id) or "") .. (fl and (":fl:" .. fl.from.key .. ">" .. fl.to.key) or "")
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
    if ok and UpdateMini then ok, err = pcall(UpdateMini) end
    if HearthPlace then pcall(HearthPlace) end
    if not ok then
        local m = tostring(err)
        if not shownErr[m] then shownErr[m] = true; say(T("errDisplay", m), "error") end
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
------------------------------------------------------------------
-- v1.41 (audit) : bandeau d'information au-dessus du guide (ne demande rien) ; disparait seul apres 10 s.
-- Clic = action (ex. ouvrir le detail) ; « x » = fermer. Les vraies questions restent des fenetres (Popup).
------------------------------------------------------------------
-- v1.42 : fondus et reflet pour les bannieres (Chronique, Quoi de neuf).
-- Un simple OnUpdate qui change l'opacite (pas d'AnimationGroup) ; tout est protege : si un appel manque
-- sur Forever, le cadre s'affiche / se cache d'un coup comme avant.
local function fxDriver(fr)
    if not fr.fxDrv then fr.fxDrv = CreateFrame("Frame") end
    return fr.fxDrv
end
-- apparition : opacite 0 -> 1 en dur s ; dy = petite descente vers sa place (pixels), facultative
function FadeIn(fr, dur, dy)
    if not fr then return end
    dur = dur or 0.4
    local ok, d = pcall(fxDriver, fr)
    local p, rel, rp, x, y
    if dy and fr.GetPoint then p, rel, rp, x, y = fr:GetPoint(1) end
    if not ok or not d then fr:SetAlpha(1); fr:Show(); return end
    fr:SetAlpha(0); fr:Show()
    local t = 0
    d:SetScript("OnUpdate", function(self, el)
        t = t + (el or 0)
        local k = math.min(1, t / dur)
        local e = 1 - (1 - k) * (1 - k)   -- ralentit a l'arrivee
        fr:SetAlpha(e)
        if p then pcall(fr.SetPoint, fr, p, rel, rp, x, y + dy * (1 - e)) end
        if k >= 1 then self:SetScript("OnUpdate", nil) end
    end)
end
-- disparition : opacite actuelle -> 0 en dur s, puis Hide
function FadeOut(fr, dur)
    if not (fr and fr:IsShown()) then return end
    dur = dur or 0.6
    local ok, d = pcall(fxDriver, fr)
    if not ok or not d then fr:Hide(); return end
    local a0, t = fr:GetAlpha() or 1, 0
    d:SetScript("OnUpdate", function(self, el)
        t = t + (el or 0)
        local k = math.min(1, t / dur)
        fr:SetAlpha(a0 * (1 - k))
        if k >= 1 then self:SetScript("OnUpdate", nil); fr:Hide(); fr:SetAlpha(1) end
    end)
end
-- reflet : un trait de lumiere doree traverse le cadre une fois, de gauche a droite
function Shine(fr, delay)
    if not (fr and CreateFrame) then return end
    local clip = fr.fxClip
    if clip == false then return end   -- deja essaye : le jeu ne sait pas faire le degrade
    if not clip then
        local ok = pcall(function()
            clip = CreateFrame("Frame", nil, fr); clip:SetAllPoints()
            if clip.SetClipsChildren then clip:SetClipsChildren(true) end
            clip:SetFrameLevel((fr:GetFrameLevel() or 1) + 5)
            local band = CreateFrame("Frame", nil, clip); band:SetWidth(90)
            local l = band:CreateTexture(nil, "OVERLAY"); l:SetPoint("TOPLEFT"); l:SetPoint("BOTTOMRIGHT", band, "BOTTOM")
            local r = band:CreateTexture(nil, "OVERLAY"); r:SetPoint("TOPRIGHT"); r:SetPoint("BOTTOMLEFT", band, "BOTTOM")
            local c0, c1 = CreateColor(1, 0.88, 0.6, 0), CreateColor(1, 0.88, 0.6, 0.30)
            for _, t in ipairs({ l, r }) do t:SetColorTexture(1, 1, 1, 1); t:SetBlendMode("ADD") end
            l:SetGradient("HORIZONTAL", c0, c1); r:SetGradient("HORIZONTAL", c1, c0)
            clip.band = band
        end)
        if not ok then if clip then clip:Hide() end; fr.fxClip = false; return end
        fr.fxClip = clip
    end
    local band, w = clip.band, fr:GetWidth() or 300
    band:SetHeight(fr:GetHeight() or 50)
    band:ClearAllPoints(); band:SetPoint("LEFT", clip, "LEFT", -90, 0)
    clip:Show(); band:Show()
    local t, dur = -(delay or 0.35), 0.8
    clip:SetScript("OnUpdate", function(self, el)
        t = t + (el or 0)
        if t < 0 then return end
        local k = math.min(1, t / dur)
        band:SetPoint("LEFT", self, "LEFT", -90 + (w + 90) * k, 0)
        if k >= 1 then self:SetScript("OnUpdate", nil); band:Hide() end
    end)
end

do
    local toast, gen = nil, 0
    -- v1.43 : onX = appele seulement si le joueur ferme avec le « x » (un vrai « non ») ;
    -- le compte a rebours de 10 s est en pause tant que la carte du monde est ouverte (elle cache le toast)
    local function mapOpen()
        local wm = _G.WorldMapFrame
        return wm and wm.IsShown and wm:IsShown()
    end
    function Toast(head, text, onClick, onX)
        if not (CreateFrame and UIParent) then return end
        if not toast then
            toast = CreateFrame("Button", "WarpathToast", UIParent)
            toast:SetSize(W, 38); toast:SetFrameStrata("HIGH")
            local bg = Tex(toast, COL.panel or COL.bg, 0.97, "BACKGROUND"); bg:SetAllPoints()
            Border(toast, COL.accent, 0.6)
            local bar = Tex(toast, COL.accent, 1, "ARTWORK"); bar:SetWidth(3); bar:SetPoint("TOPLEFT"); bar:SetPoint("BOTTOMLEFT")
            toast.head = FS(toast, 9, COL.gold, FONT, "LEFT"); toast.head:SetPoint("TOPLEFT", 12, -6)
            toast.text = FS(toast, 11, COL.white, FONT, "LEFT"); toast.text:SetPoint("TOPLEFT", toast.head, "BOTTOMLEFT", 0, -3)
            toast.text:SetPoint("RIGHT", toast, "RIGHT", -24, 0)
            if toast.text.SetWordWrap then toast.text:SetWordWrap(false) end
            toast.x = CreateFrame("Button", nil, toast); toast.x:SetSize(16, 16); toast.x:SetPoint("TOPRIGHT", -4, -4)
            toast.x.fs = FS(toast.x, 11, COL.soft, FONT, "CENTER"); toast.x.fs:SetPoint("CENTER")
            toast.x.fs:SetText(Glyph(toast.x, "x", COL.soft, 7) and "" or "x")
            toast.x:SetScript("OnClick", function()
                toast:Hide(); local fn = toast.onX; toast.onX = nil
                if fn then pcall(fn) end
            end)
            local hl = Tex(toast, COL.accent, 0.06, "HIGHLIGHT"); hl:SetAllPoints()
            toast:SetScript("OnClick", function(self) self:Hide(); if self.action then pcall(self.action) end end)
        end
        -- v1.42 : en haut au centre de l'ecran (au-dessus du guide, il cachait la minicarte quand le guide est
        -- colle dessous) ; sous la banniere de la Chronique si elle est affichee
        toast:ClearAllPoints()
        local cb = _G.WarpathChronBanner
        if cb and cb:IsShown() then toast:SetPoint("TOP", cb, "BOTTOM", 0, -8)
        else toast:SetPoint("TOP", UIParent, "TOP", 0, -110) end
        toast.head:SetText(Caps(head or "")); toast.text:SetText(text or ""); toast.action = onClick; toast.onX = onX
        FadeIn(toast, 0.4)
        gen = gen + 1
        local mine = gen
        if C_Timer and C_Timer.After then
            local left = 10
            local function tick()
                if gen ~= mine or not toast:IsShown() then return end
                if mapOpen() then left = 10          -- carte ouverte : on repart pour 10 s a sa fermeture
                else left = left - 1 end
                if left <= 0 then FadeOut(toast, 0.6) else C_Timer.After(1, tick) end
            end
            C_Timer.After(1, tick)
        end
    end
end

------------------------------------------------------------------
-- v1.41 (uniformisation) : elements communs a toutes les fenetres de l'addon
--   HeadButton(parent, label) : bouton carre 16 px a contour dore (« ? », « x », « - »...)
--   ScaleGrip(frame, get, set) : poignee en bas a droite ; glisser = echelle de la fenetre (coin haut-gauche fixe)
------------------------------------------------------------------
-- v1.42 : « x », « - », « + » dessines avec deux traits au lieu d'une lettre : la lettre de la police n'est pas
-- centree verticalement dans sa case (le « x » est une minuscule posee sur la ligne de base).
-- Renvoie true si le dessin a marche ; sinon on garde la lettre (fallback).
function Glyph(b, label, c, size)
    if label ~= "x" and label ~= "-" and label ~= "+" then return false end
    size = size or 8
    local ok = pcall(function()
        local function bar(w, h, rot)
            local t = b:CreateTexture(nil, "ARTWORK")
            t:SetColorTexture(c[1], c[2], c[3], 1)
            t:SetSize(w, h); t:SetPoint("CENTER", b, "CENTER", 0, 0)
            if rot then t:SetRotation(rot) end
            return t
        end
        if label == "x" then
            local d = size * 1.25   -- diagonale : meme encombrement visuel que les autres signes
            b.g1 = bar(d, 1.5, math.pi / 4); b.g2 = bar(d, 1.5, -math.pi / 4)
        elseif label == "-" then
            b.g1 = bar(size, 1.5)
        else
            b.g1 = bar(size, 1.5); b.g2 = bar(1.5, size)
        end
    end)
    if not ok then
        if b.g1 then b.g1:Hide() end
        if b.g2 then b.g2:Hide() end
        b.g1, b.g2 = nil, nil
    end
    return ok
end

function HeadButton(parent, label)
    local b = CreateFrame("Button", nil, parent); b:SetSize(16, 16)
    Border(b, COL.accent, 0.6)
    b.fs = FS(b, 11, COL.accent, FONT, "CENTER"); b.fs:SetPoint("CENTER", 0, 0)
    b.fs:SetText(Glyph(b, label, COL.accent) and "" or (label or ""))
    local h = Tex(b, COL.accent, 0.15, "HIGHLIGHT"); h:SetAllPoints()
    b:SetScript("OnLeave", function() Tip():Hide() end)
    return b
end
function ScaleGrip(frame, get, set)
    local grip = CreateFrame("Button", nil, frame)
    grip:SetSize(12, 12); grip:SetPoint("BOTTOMRIGHT", -1, 1)
    if grip.SetFrameLevel and frame.GetFrameLevel then grip:SetFrameLevel((frame:GetFrameLevel() or 1) + 10) end
    local gt = grip:CreateTexture(nil, "OVERLAY"); gt:SetAllPoints()
    gt:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    if gt.SetVertexColor then gt:SetVertexColor(COL.accent[1], COL.accent[2], COL.accent[3]) end
    local gh = grip:CreateTexture(nil, "HIGHLIGHT"); gh:SetAllPoints(); gh:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetScript("OnMouseDown", function(self)
        if (DB and DB.locked) or (InCombatLockdown and InCombatLockdown()) or not GetCursorPosition then return end
        local s, left, top = frame:GetScale() or 1, frame:GetLeft(), frame:GetTop()
        if not (left and top) then return end
        local ui = (UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()) or 1
        local w = (frame:GetWidth() or 300) * s
        self.drag = { s = s, left = left * s, top = top * s, x0 = GetCursorPosition() / ui, w = w, ui = ui }
        self:SetScript("OnUpdate", function()
            local d = self.drag; if not d then return end
            local sc = math.max(0.6, math.min(1.5, d.s * (d.w + GetCursorPosition() / d.ui - d.x0) / d.w))
            frame:SetScale(sc); frame:ClearAllPoints(); frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", d.left / sc, d.top / sc)
        end)
    end)
    grip:SetScript("OnMouseUp", function(self)
        self:SetScript("OnUpdate", nil)
        if not self.drag then return end
        self.drag = nil
        if set then set(math.floor((frame:GetScale() or 1) * 100 + 0.5) / 100) end
    end)
    grip:SetScript("OnEnter", function(self) Tip():SetOwner(self, "ANCHOR_RIGHT"); Tip():AddLine(T("winResize"), 1, 1, 1, true); Tip():Show() end)
    grip:SetScript("OnLeave", function() Tip():Hide() end)
    if get and frame.SetScale then frame:SetScale(get() or 1) end
    return grip
end

POPUP_HEAD = { WARPATH_DUNGEON = "popDungeon", WARPATH_DGSWITCH = "popDungeon", WARPATH_CHAIN = "popChain",
               WARPATH_ZONEUP = "popZone", WARPATH_PROFS = "popProfs", WARPATH_WEAPON = "popWeapon", WARPATH_NEWS = "popNews" }
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
        -- v1.41 (uniformisation) : en-tete standard (34 px, losange rouge, titre a gauche, « x » = comme Echap)
        local hbg = Tex(dlg, COL.panel or COL.bg, 1, "BORDER"); hbg:SetHeight(34); hbg:SetPoint("TOPLEFT", 1, -1); hbg:SetPoint("TOPRIGHT", -1, -1)
        local hln = Tex(dlg, COL.line, 1, "ARTWORK"); hln:SetHeight(1); hln:SetPoint("TOPLEFT", 0, -34); hln:SetPoint("TOPRIGHT", 0, -34)
        local gem = Diamond(dlg, 8, COL.red); gem:SetPoint("LEFT", dlg, "TOPLEFT", 14, -17)
        dlg.head = FS(dlg, 12, COL.white, FONT, "LEFT"); dlg.head:SetPoint("LEFT", dlg, "TOPLEFT", 30, -17)
        dlg.head:SetText(Caps("Oghoule's Warpath"))
        local x = HeadButton(dlg, "x"); x:SetPoint("RIGHT", dlg, "TOPRIGHT", -6, -17)
        x:SetScript("OnClick", function() finish("OnCancel", "escape") end)
        dlg.rule = CreateFrame("Frame", nil, dlg); dlg.rule:SetSize(340, 1); dlg.rule:SetPoint("TOP", dlg, "TOP", 0, -36)
        dlg.text = FS(dlg, 12, COL.white, FONT, "LEFT"); dlg.text:SetPoint("TOP", dlg.rule, "BOTTOM", 0, -12); dlg.text:SetWidth(340)
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
        -- v1.41 : titre propre a chaque question (« DONJON SUGGÉRÉ »...) au lieu de « OGHOULE'S WARPATH » partout
        local hk = POPUP_HEAD[name]
        dlg.head:SetText(Caps(hk and T(hk) or "Oghoule's Warpath"))
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
        local h = 36 + 12 + (dlg.text:GetStringHeight() or 40) + 18 + 24 + 14
        dlg:SetSize(math.max(380, total + 40), math.max(120, h))
        dlg:Show()
        if PlaySound and SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPEN then pcall(PlaySound, SOUNDKIT.IG_MAINMENU_OPEN) end
    end
end

------------------------------------------------------------------
-- Mode donjon : une fois a l'entree, la fenetre montre le journal des quetes du donjon (progression,
-- crochet quand c'est complete, details au clic) au lieu d'une liste d'etapes "fais ceci".
-- "Sortie du donjon" (ou toutes les quetes completes) : le guide reprend pour aller les rendre.
------------------------------------------------------------------
local function DgEntrance()
    if not steps then return nil end
    for j = 1, #steps do if steps[j].t == "go" then return j end end
end
-- texte d'ambiance de l'entree du donjon (Lore.lua), sinon le message general
function DungeonLore(zone)
    local name = (UnitName and UnitName("player")) or "?"
    local l = ns.Lore and ns.Lore[DB.guide]
    if l then return string.format((Lang() == "en") and l.en or l.fr, name) end
    return T("dgAssemble", name, zone)
end
function DungeonLogActive()
    if not (DB and steps and IS_DUNGEON[DB.guide]) then return false end
    if DB.dgOut and DB.dgOut[DB.guide] then return false end
    local ent = DgEntrance()
    if not ent or not doneCache[ent] or current <= ent then return false end
    local s = steps[current]
    return s ~= nil and s.t ~= "turnin"
end
local function QProg(q)
    if logById[q] == true then return CHECK end
    local have, need = 0, 0
    if C_QuestLog and C_QuestLog.GetQuestObjectives then
        local ok, objs = pcall(C_QuestLog.GetQuestObjectives, q)
        if ok and type(objs) == "table" then
            for _, o in ipairs(objs) do have = have + (o.numFulfilled or 0); need = need + (o.numRequired or 0) end
        end
    end
    if need > 0 then return "|cffd6b866" .. have .. "/" .. need .. "|r" end
    return "|cffd6b866…|r"
end
function DungeonLogList()
    local out, seen = {}, {}
    local ent = DgEntrance(); if not ent then return out end
    for j = ent + 1, #steps do
        local s = steps[j]
        if Applies(s) and (s.t == "do" or s.t == "accept" or s.t == "turnin") then
            for _, q in ipairs(Ids(s)) do
                if not seen[q] and not Rendue(q) and not (DB.ignored and DB.ignored[q]) then
                    if logById[q] ~= nil then
                        seen[q] = true
                        out[#out + 1] = { q = q, name = QuestTitle(q) or (EST[q] and EST[q].n) or s.quest or ("#" .. q), prog = QProg(q), done = logById[q] == true }
                    elseif s.t == "accept" then
                        seen[q] = true
                        out[#out + 1] = { q = q, name = QuestTitle(q) or (EST[q] and EST[q].n) or s.quest or ("#" .. q), prog = "", later = true, acc = s }
                    end
                end
            end
        end
    end
    return out
end
local function HasQ(s, q) for _, id in ipairs(Ids(s)) do if id == q then return true end end return false end
local function QDetails(row)
    local q = row.q
    local ent = DgEntrance() or 0
    local lines = {}
    if row.later then lines[#lines + 1] = "|cff8c7f62" .. T("dgStartsIn") .. "|r  " .. StepText(row.acc) end
    -- v1.41 : quete dans ton journal : une ligne par objectif (monstre ou objet) avec son compteur, plutot que
    -- le long texte de l'etape (« tue 7 Deviate Ravagers, 7 Deviate Vipers... »). Les objectifs finis sont grises.
    local objLines = {}
    if logById[q] ~= nil and C_QuestLog and C_QuestLog.GetQuestObjectives then
        local ok, objs = pcall(C_QuestLog.GetQuestObjectives, q)
        if ok and type(objs) == "table" then
            for _, o in ipairs(objs) do
                local txt = type(o.text) == "string" and o.text or ""
                if not (issecretvalue and issecretvalue(txt)) and txt ~= "" then
                    -- « Deviate Ravager slain: 3/7 » -> nom a gauche, compteur a droite
                    local name = txt:gsub("^%s*%d+/%d+%s*", ""):gsub(":?%s*%d+/%d+%s*$", ""):gsub("%s+slain$", ""):gsub("%s+tué[e]?s?$", "")
                    local cnt = (o.numRequired and o.numRequired > 0) and ((o.numFulfilled or 0) .. "/" .. o.numRequired) or ""
                    local col = o.finished and "|cff6f6450" or "|cffe6dcc8"
                    objLines[#objLines + 1] = col .. name .. "|r" .. (cnt ~= "" and ("   " .. (o.finished and "|cff6f6450" or "|cffd6b866") .. cnt .. "|r") or "")
                end
            end
        end
    end
    if #objLines > 0 then
        lines[#lines + 1] = table.concat(objLines, "\n")
    else
        for j = ent + 1, #steps do
            local s = steps[j]
            if s.t == "do" and Applies(s) and HasQ(s, q) then lines[#lines + 1] = StepText(s); break end
        end
    end
    if EST[q] and logById[q] == false then
        for _, dr in ipairs(Estimate({ q }, false).drops) do
            lines[#lines + 1] = "|cff8c7f62" .. T("dropLbl") .. " :|r " .. (dr.name or "?") .. " |cffffd100" .. math.floor(dr.rate * 100 + 0.5) .. " %|r"
        end
    end
    local tip = ns.Tips and ns.Tips[q]
    if DB.tips ~= false and tip then lines[#lines + 1] = "|cffd6b866" .. T("tipLbl") .. "|r  " .. ((Lang() == "en") and tip[2] or tip[1]) end
    for j = ent + 1, #steps do
        local s = steps[j]
        if s.t == "turnin" and Applies(s) and HasQ(s, q) then lines[#lines + 1] = "|cff8c7f62" .. T("dgTurnin") .. "|r  " .. StepText(s); break end
    end
    return table.concat(lines, "\n\n")
end
local function DlogRow(k)
        local r = DL.rows[k]
    if r then return r end
    r = CreateFrame("Button", nil, f); r:SetSize(INNER, 17)
    local hl = Tex(r, COL.accent, 0.08, "HIGHLIGHT"); hl:SetAllPoints()
    r.arrow = FS(r, 10, COL.gold, FONT, "LEFT"); r.arrow:SetPoint("LEFT", 0, 0)
    r.name = FS(r, 12, COL.white, FONT, "LEFT"); r.name:SetPoint("LEFT", 14, 0); r.name:SetWidth(INNER - 70)
    if r.name.SetWordWrap then r.name:SetWordWrap(false) end
    r.prog = FS(r, 11, COL.accent, FONT, "RIGHT"); r.prog:SetPoint("RIGHT", 0, 0)
    r:SetScript("OnClick", function(self)
        if DL.open == self.q then DL.open = nil else DL.open = self.q end
        Refresh(true)
    end)
    DL.rows[k] = r
    return r
end
function DungeonLogHide()
    if f and DL.rows then for _, r in ipairs(DL.rows) do r:Hide() end end
    if f and DL.tip then DL.tip:Hide() end
    if f then DL.n = 0 end
end
function DungeonLogRender()
    SetObjRows(nil)
    local list = DungeonLogList()
    local zone = Title(G):gsub("%s*%b()", ""):gsub("%s+%d+%-%d+$", ""):gsub("^[^:]+:%s*", "")
    local done = 0
    for _, r in ipairs(list) do if r.done then done = done + 1 end end
    local nq = 0; for _, r in ipairs(list) do if not r.later then nq = nq + 1 end end
    SetHeader(zone, T("dgCount", done, nq), nq > 0 and done / nq or 0)
    if f.badge then f.badge:Hide(); f.qsub:Hide(); f.dest:Hide() end
    f.kind:SetText("|cffcdbb8e" .. Caps(T("dgLog")) .. "|r"); f.kind:Show(); f.dist:SetText("")
    f.qtitle:Hide(); f.text:SetText("|cffd69a66" .. T("dgGroup") .. "|r"); f.text:Show(); SetRoute({}); f.coord:Hide(); f.chainBtn:Hide(); f.lockBtn:Hide()
    if f.caveBtn then f.caveBtn:Hide() end
    if f.nowBtn then f.nowBtn:Hide() end
    if f.advice then f.advice:Hide() end
    SetUpcoming({}); SetChain(nil); distTarget = nil
    if not DL.tip then
        DL.tip = FS(f, 11, COL.soft, FONT, "LEFT"); DL.tip:SetWidth(INNER - 14)
        if DL.tip.SetSpacing then DL.tip:SetSpacing(2) end
    end
    DungeonLogHide()
    for k, row in ipairs(list) do
        if k > 12 then break end
        local r = DlogRow(k)
        r.q = row.q
        local open = DL.open == row.q
        r.arrow:SetText(open and "v" or ">")
        r.name:SetText(row.later and ("|cff8c7f62" .. row.name .. "|r") or row.name)
        r.prog:SetText(row.later and ("|cff8c7f62" .. T("dgLater") .. "|r") or row.prog)
        r:Show()
        if open then DL.tip:SetText(QDetails(row)); DL.tip:Show(); DL.after = k end
    end
    DL.n = math.min(#list, 12)
    if #list > 12 then f.text:SetText("|cffd69a66" .. T("dgGroup") .. "|r\n|cff8c7f62" .. T("dgMore", #list - 12) .. "|r") end
    if #list == 0 then f.text:SetText(T("dgEmpty")); f.text:Show() end
    SetSkip("dgExit")
    if ns.Targets then ns.Targets.Update(steps[current]) end
    Layout()
end
