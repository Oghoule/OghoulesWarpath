-- Oghoule's Warpath : moteur (Window.lua) - voir Core.lua
local ADDON, ns = ...
local _ENV = ns.CoreEnv
if setfenv then setfenv(1, _ENV) end

------------------------------------------------------------------
-- Fenetre (sous la minimap par defaut)
------------------------------------------------------------------
function CreateUI()
    f = CreateFrame("Frame", "WarpathFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    f:SetSize(W, 200)
    if DB.wpos then
        f:SetPoint(DB.wpos[1], UIParent, DB.wpos[2], DB.wpos[3], DB.wpos[4])
    elseif Minimap then
        f:SetPoint("TOPRIGHT", Minimap, "BOTTOMRIGHT", 12, -36)
    else
        f:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -20, -240)
    end
    local bg = Tex(f, COL.bg, 0.90, "BACKGROUND"); bg:SetAllPoints()
    Border(f, COL.line, 0.8, "BORDER")
    -- en-tete : bande un peu plus claire, losange rouge, zone a gauche, etape a droite
    HEAD_H = 34
    local hbg = Tex(f, COL.panel, 1, "BORDER"); hbg:SetHeight(HEAD_H); hbg:SetPoint("TOPLEFT", 1, -1); hbg:SetPoint("TOPRIGHT", -1, -1)
    local hln = Tex(f, COL.line, 1, "ARTWORK"); hln:SetHeight(1); hln:SetPoint("TOPLEFT", 0, -HEAD_H); hln:SetPoint("TOPRIGHT", 0, -HEAD_H)
    f.gem = Diamond(f, 8, COL.red); f.gem:SetPoint("LEFT", f, "TOPLEFT", PAD - 4, -HEAD_H / 2)
    -- barre de progression de la zone
    f.progBg = Tex(f, COL.faint, 1, "ARTWORK"); f.progBg:SetSize(INNER, 3)
    f.progFill = Tex(f, COL.red, 1, "OVERLAY"); f.progFill:SetHeight(3); f.progFill:SetWidth(1); f.progFill:SetPoint("TOPLEFT", f.progBg, "TOPLEFT")
    -- bloc destination : fond un peu plus clair, liseré rouge, fleche, lieu, precision, distance
    f.dest = CreateFrame("Frame", nil, f); f.dest:SetSize(INNER, 38)
    local dbg = Tex(f.dest, COL.panel, 1, "BACKGROUND"); dbg:SetAllPoints()
    local dbar = Tex(f.dest, COL.red, 1, "ARTWORK"); dbar:SetWidth(2); dbar:SetPoint("TOPLEFT"); dbar:SetPoint("BOTTOMLEFT")
    f.dest.arrow = f.dest:CreateTexture(nil, "ARTWORK"); f.dest.arrow:SetSize(16, 16); f.dest.arrow:SetPoint("LEFT", 13, 0)
    f.dest.arrow:SetTexture("Interface\\AddOns\\" .. (ADDON or "OghoulesWarpath") .. "\\Media\\IcoNav")
    if f.dest.arrow.SetVertexColor then f.dest.arrow:SetVertexColor(COL.cream[1], COL.cream[2], COL.cream[3]) end
    f.dist = FS(f.dest, 16, COL.white, DISPLAY, "RIGHT"); f.dist:SetPoint("RIGHT", -12, 0)
    f.destName = FS(f.dest, 12, COL.white, FONT, "LEFT"); f.destName:SetPoint("TOPLEFT", 42, -9); f.destName:SetPoint("RIGHT", f.dist, "LEFT", -8, 0)
    if f.destName.SetWordWrap then f.destName:SetWordWrap(false) end
    f.dest:Hide()
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) if not DB.locked then self:StartMoving() end end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local p, _, rp, x, y = self:GetPoint()
        DB.wpos = { p, rp, x, y }
    end)

    -- (ordre de creation garde : title, text, list, coord)
    f.title = FS(f, 12, COL.white, FONT, "LEFT"); f.title:SetPoint("LEFT", f, "TOPLEFT", PAD + 12, -HEAD_H / 2)
    f.stepNo = FS(f, 10, COL.soft, FONT, "RIGHT"); f.stepNo:SetPoint("RIGHT", f, "TOPRIGHT", -PAD, -HEAD_H / 2)
    f.text = FS(f, 12, COL.soft, FONT, "LEFT"); f.text:SetWidth(INNER)
    if f.text.SetJustifyV then f.text:SetJustifyV("TOP") end
    if f.text.SetWordWrap then f.text:SetWordWrap(true) end
    if f.text.SetSpacing then f.text:SetSpacing(4) end
    f.nextRule = SectionHead(f, INNER)
    f.list = f.nextRule.label
    f.coord = FS(f.dest, 10, COL.soft, FONT, "LEFT"); f.coord:SetPoint("TOPLEFT", f.destName, "BOTTOMLEFT", 0, -5); f.coord:SetPoint("RIGHT", f.dist, "LEFT", -8, 0)
    if f.coord.SetWordWrap then f.coord:SetWordWrap(false) end
    -- pied : niveau, XP/h actif (Journal.lua), duree de la session
    f.foot = CreateFrame("Frame", nil, f); f.foot:SetSize(INNER, 12); f.foot:Hide()
    f.footLvl = FS(f.foot, 10, COL.gold, FONT, "LEFT"); f.footLvl:SetPoint("LEFT")
    f.xph = FS(f.foot, 10, COL.gold, FONT, "CENTER"); f.xph:SetPoint("CENTER"); f.xph:Hide()
    f.footSess = FS(f.foot, 10, COL.gold, FONT, "RIGHT"); f.footSess:SetPoint("RIGHT")
    if f.foot.EnableMouse then f.foot:EnableMouse(true) end
    f.foot:SetScript("OnEnter", function(self)
        local i = rawget(f, "footInfo"); if type(i) ~= "table" then return end
        local t = Tip(); t:SetOwner(self, "ANCHOR_TOP")
        t:AddLine(T("footTipHead"))
        t:AddLine(T("footTipActive", i.rate > 0 and FormatNum(math.floor(i.rate)) or "—", i.active), 1, 1, 1, true)
        t:AddLine(T("footTipWall", i.wallRate > 0 and FormatNum(math.floor(i.wallRate)) or "—", i.wall), 1, 1, 1, true)
        t:AddLine(T("footTipNote"), 0.66, 0.60, 0.48, true)
        t:Show()
    end)
    f.foot:SetScript("OnLeave", function() Tip():Hide() end)

    f.name = FS(f, 13, COL.white, FONT, "CENTER"); f.name:SetWidth(INNER); f.name:Hide() -- (garde pour les tests)
    f.div = Divider(f, INNER); f.div:Hide()
    -- badge du niveau de la quete
    f.badge = CreateFrame("Frame", nil, f); f.badge:SetSize(32, 46)
    local bb = CreateFrame("Frame", nil, f.badge); bb:SetSize(32, 32); bb:SetPoint("TOP")
    Border(bb, COL.accent)
    f.badge.num = FS(bb, 13, COL.cream, FONT, "CENTER"); f.badge.num:SetPoint("CENTER", 0, 0)
    f.badge.lbl = FS(f.badge, 9, COL.gold, FONT, "CENTER"); f.badge.lbl:SetPoint("TOP", bb, "BOTTOM", 0, -4)
    if f.badge.EnableMouse then f.badge:EnableMouse(true) end
    f.badge:SetScript("OnEnter", function(self)
        Tip():SetOwner(self, "ANCHOR_LEFT")
        Tip():AddLine(T("badgeTip", tonumber(f.badge.num:GetText()) or 0, UnitLevel("player") or 1))
        if type(f.rateTip) == "string" then Tip():AddLine(f.rateTip, 0.84, 0.72, 0.40) end
        Tip():Show()
    end)
    f.badge:SetScript("OnLeave", function() Tip():Hide() end)
    f.badge:Hide()

    f.kindRow = CreateFrame("Frame", nil, f); f.kindRow:SetSize(INNER, 12)
    f.kind = FS(f.kindRow, 9, COL.accent, FONT, "LEFT"); f.kind:SetPoint("LEFT")
    if f.kind.SetWordWrap then f.kind:SetWordWrap(false) end
    -- clic sur l'en-tete (le crochet) d'une etape passee ou validee a la main : on l'annule
    if f.kindRow.EnableMouse then f.kindRow:EnableMouse(true) end
    f.kindRow:SetScript("OnMouseUp", function()
        local i = peek or focus or current
        if steps and i and Restorable(i) then Restore(i) end
    end)

    f.qtitle = FS(f, 20, COL.white, DISPLAY, "LEFT"); f.qtitle:SetWidth(INNER)
    if f.qtitle.SetTextColor then f.qtitle:SetTextColor(0.95, 0.89, 0.72) end
    f.qsub = FS(f, 11, COL.soft, FONT, "LEFT"); f.qsub:SetWidth(INNER); f.qsub:Hide()
    -- survol du titre : texte complet de l'etape (quand la fenetre montre les objectifs en direct)
    f.qhit = CreateFrame("Frame", nil, f); f.qhit:SetAllPoints(f.qtitle); f.qhit:EnableMouse(true)
    f.qhit:SetScript("OnEnter", function(self)
        if type(f.qtitleTip) ~= "string" and type(f.rateTip) ~= "string" and type(f.tipText) ~= "string" then return end
        Tip():SetOwner(self, "ANCHOR_LEFT")
        if type(f.qtitleTip) == "string" then Tip():AddLine(f.qtitleTip, 1, 1, 1, true) end
        if type(f.tipText) == "string" then Tip():AddLine(" "); Tip():AddLine(T("tipLbl"), 0.84, 0.72, 0.40); Tip():AddLine(f.tipText, 1, 1, 1, true) end
        if type(f.rateTip) == "string" then Tip():AddLine(f.rateTip, 0.84, 0.72, 0.40) end
        Tip():AddLine(T("qtitleClick"), 0.66, 0.60, 0.48, true); Tip():Show()
    end)
    f.qhit:SetScript("OnLeave", function() Tip():Hide() end)
    f.qhit:SetScript("OnMouseDown", function(_, btn)
        f.qdown = { GetCursorPosition() }
        if btn == "LeftButton" and not DB.locked and f.StartMoving then f:StartMoving() end
    end)
    f.qhit:SetScript("OnMouseUp", function(_, btn)
        if f.StopMovingOrSizing then f:StopMovingOrSizing() end
        local p, _, rp, x, y = f:GetPoint(); DB.wpos = { p, rp, x, y }
        local cx, cy = GetCursorPosition()
        local d = f.qdown and math.abs(cx - (f.qdown[1] or cx)) + math.abs(cy - (f.qdown[2] or cy)) or 0
        if btn == "LeftButton" and d < 4 and OpenStepQuest then OpenStepQuest() end
    end)
    if f.qtitle.SetWordWrap then f.qtitle:SetWordWrap(true) end

    f.route = {}
    for k = 1, 3 do
        local row = CreateFrame("Frame", nil, f); row:SetSize(INNER, 16)
        row.gem = Diamond(row, 7, COL.white); row.gem:SetPoint("LEFT", -2, 0)
        row.mode = FS(row, 9, COL.accent, FONT, "RIGHT"); row.mode:SetPoint("RIGHT")
        row.name = FS(row, 12, COL.white, FONT, "LEFT"); row.name:SetPoint("LEFT", 16, 0); row.name:SetPoint("RIGHT", row.mode, "LEFT", -6, 0)
        if row.name.SetWordWrap then row.name:SetWordWrap(false) end
        row:Hide()
        f.route[k] = row
    end

    f.chainBtn = CreateFrame("Button", nil, f); f.chainBtn:SetSize(INNER, 16)
    f.chainBtn.label = FS(f.chainBtn, 11, COL.accent, FONT, "LEFT"); f.chainBtn.label:SetPoint("LEFT")
    local hl = Tex(f.chainBtn, COL.accent, 0.08, "HIGHLIGHT"); hl:SetAllPoints()
    f.chainBtn.gems = {}
    for k = 10, 1, -1 do
        local g = Diamond(f.chainBtn, 5, COL.line, true)
        g:SetPoint("RIGHT", f.chainBtn, "RIGHT", -(10 - k) * 9, 0)
        f.chainBtn.gems[k] = g
    end
    f.chainBtn:SetScript("OnClick", function(self)
        if self.target then focus = self.target; peek = nil; lastWP = nil; Refresh(true) end
    end)
    f.chainBtn:SetScript("OnEnter", function(self)
        if not self.target then return end
        Tip():SetOwner(self, "ANCHOR_LEFT")
        Tip():AddLine(T("chainStart"))
        Tip():Show()
    end)
    f.chainBtn:SetScript("OnLeave", function() Tip():Hide() end)
    f.chainBtn:Hide()

    -- conseil (journal plein, pierre de foyer)
    f.advice = CreateFrame("Frame", nil, f); f.advice:SetSize(INNER, 16)
    f.advice.icon = f.advice:CreateTexture(nil, "ARTWORK"); f.advice.icon:SetSize(14, 14); f.advice.icon:SetPoint("TOPLEFT", 0, -1)
    f.advice.label = FS(f.advice, 11, COL.gold, FONT, "LEFT"); f.advice.label:SetPoint("TOPLEFT", 20, -2)
    f.advice.label:SetWidth(INNER - 20); if f.advice.label.SetWordWrap then f.advice.label:SetWordWrap(true) end
    f.advice:Hide()
    -- pierre de foyer : l'icone du conseil devient un bouton qui l'utilise (bouton securise, change hors combat seulement)
    function HearthButton(on)
        if InCombatLockdown and InCombatLockdown() then return end
        if not f.hsBtn and on then
            local ok, b = pcall(CreateFrame, "Button", "WarpathHearthButton", f.advice, "SecureActionButtonTemplate")
            if not ok or not b then return end
            b:SetAllPoints(f.advice.icon)
            if b.RegisterForClicks then b:RegisterForClicks("AnyUp", "AnyDown") end
            b:SetAttribute("type", "item"); b:SetAttribute("item", "item:6948")
            local hl = b:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.25)
            Border(b, COL.accent)
            b:SetScript("OnEnter", function(self) Tip():SetOwner(self, "ANCHOR_LEFT"); Tip():AddLine(T("hsClick")); Tip():Show() end)
            b:SetScript("OnLeave", function() Tip():Hide() end)
            f.hsBtn = b
        end
        if f.hsBtn then
            f.hsBtn:SetShown(on and true or false)
            f.advice.icon:SetSize(on and 18 or 14, on and 18 or 14)
            f.advice.label:ClearAllPoints(); f.advice.label:SetPoint("TOPLEFT", on and 26 or 20, on and -4 or -2)
        end
    end

    f.lockBtn = CreateFrame("Button", nil, f); f.lockBtn:SetSize(INNER, 16)
    if f.lockBtn.RegisterForClicks then f.lockBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
    local lbg = Tex(f.lockBtn, COL.warn, 0.08, "BACKGROUND"); lbg:SetAllPoints()
    Border(f.lockBtn, COL.warn, 0.35)
    f.lockBtn.gem = Diamond(f.lockBtn, 7, COL.warn); f.lockBtn.gem:SetPoint("LEFT", 7, 0)
    f.lockBtn.label = FS(f.lockBtn, 11, COL.accent, FONT, "LEFT"); f.lockBtn.label:SetPoint("LEFT", 22, 0)
    f.lockBtn.label:SetWidth(INNER - 26); if f.lockBtn.label.SetWordWrap then f.lockBtn.label:SetWordWrap(true) end
    f.lockBtn.label:SetPoint("RIGHT", -6, 0)
    if f.lockBtn.label.SetWordWrap then f.lockBtn.label:SetWordWrap(false) end
    local lhl = Tex(f.lockBtn, COL.accent, 0.08, "HIGHLIGHT"); lhl:SetAllPoints()
    -- grotte : effacer une entree mal apprise (porte de maison prise pour l'entree)
    f.caveBtn = CreateFrame("Button", nil, f); f.caveBtn:SetSize(INNER, 16)
    f.caveBtn.gem = Diamond(f.caveBtn, 6, COL.gold); f.caveBtn.gem:SetPoint("LEFT", -1, 0)
    f.caveBtn.label = FS(f.caveBtn, 11, COL.accent, FONT, "LEFT"); f.caveBtn.label:SetPoint("LEFT", 14, 0)
    local chl = Tex(f.caveBtn, COL.accent, 0.08, "HIGHLIGHT"); chl:SetAllPoints()
    f.caveBtn:SetScript("OnClick", function() if ForgetCave then ForgetCave() end end)
    f.caveBtn:SetScript("OnEnter", function(self)
        Tip():SetOwner(self, "ANCHOR_LEFT"); Tip():AddLine(T("caveWrong")); Tip():AddLine(T("caveWrongTip"), 0.66, 0.60, 0.48, true); Tip():Show()
    end)
    f.caveBtn:SetScript("OnLeave", function() Tip():Hide() end)
    f.caveBtn:Hide()
    f.lockBtn:SetScript("OnClick", function(self, button)
        local i = self.idx
        if not i then return end
        if button == "RightButton" then
            DB.lockHide[steps[i].id] = true
            Refresh()
        else
            AskChain(steps[i].id)
        end
    end)
    f.lockBtn:SetScript("OnEnter", function(self)
        Tip():SetOwner(self, "ANCHOR_LEFT")
        Tip():AddLine(T("lockTitle"))
        for _, i in ipairs(self.list or {}) do
            local miss = {}
            for _, q in ipairs(blockedBy[i] or {}) do miss[#miss + 1] = (EST[q] and EST[q].n) or tostring(q) end
            Tip():AddLine((QName(steps[i]) or "?") .. "  |cff8c7f62(" .. table.concat(miss, ", ") .. ")|r", 0.84, 0.60, 0.40)
        end
        Tip():AddLine(T("lockTip"), 0.66, 0.60, 0.48, true)
        Tip():Show()
    end)
    f.lockBtn:SetScript("OnLeave", function() Tip():Hide() end)
    f.lockBtn:Hide()

    -- en regardant d'autres etapes (< > ou clic dans la liste) : retour a l'etape actuelle en un clic
    f.nowBtn = CreateFrame("Button", nil, f); f.nowBtn:SetSize(INNER, 18)
    local nbg = Tex(f.nowBtn, COL.accent, 0.10, "BACKGROUND"); nbg:SetAllPoints()
    f.nowBtn.gem = Diamond(f.nowBtn, 6, COL.accent); f.nowBtn.gem:SetPoint("LEFT", 4, 0)
    f.nowBtn.label = FS(f.nowBtn, 11, COL.accent, FONT, "LEFT"); f.nowBtn.label:SetPoint("LEFT", 16, 0)
    local nhl = Tex(f.nowBtn, COL.accent, 0.12, "HIGHLIGHT"); nhl:SetAllPoints()
    f.nowBtn:SetScript("OnClick", function() if BackToNow then BackToNow() end end)
    f.nowBtn:Hide()

    f.btnRow = CreateFrame("Frame", nil, f); f.btnRow:SetSize(INNER, 34)
    -- clic gauche : etape precedente / suivante ; clic droit : retour a l'etape actuelle (un seul des deux)
    local function nav(d) return function(_, btn) if btn == "RightButton" then if BackToNow then BackToNow() end else Peek(d) end end end
    local prev = FlatButton(f.btnRow, 46, 34, nav(-1)); prev:SetPoint("LEFT"); prev:SetLabel("<")
    local nxt = FlatButton(f.btnRow, 46, 34, nav(1)); nxt:SetPoint("RIGHT"); nxt:SetLabel(">")
    f.skip = FlatButton(f.btnRow, INNER - 104, 34, Ignore); f.skip:SetPoint("CENTER")
    if f.skip.fs.SetFont then f.skip.fs:SetFont(FONT, 10, ""); f.skip.fs:SetTextColor(COL.gold[1], COL.gold[2], COL.gold[3]) end
    for _, b in ipairs({ prev, nxt }) do
        if b.fs.SetFont then b.fs:SetFont(FONT, 13, ""); b.fs:SetTextColor(COL.accent[1], COL.accent[2], COL.accent[3]) end
        b:SetLabel(b == prev and "<" or ">")
    end
    for _, b in ipairs({ prev, nxt }) do
        if b.RegisterForClicks then b:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
    end
    -- infobulles des boutons
    for _, bt in ipairs({ { prev, "btnPrevTip" }, { nxt, "btnNextTip" }, { f.skip, "btnOkTip" } }) do
        bt[1]:HookScript("OnEnter", function(self)
            Tip():SetOwner(self, "ANCHOR_BOTTOM"); Tip():AddLine(T(bt[2]), 1, 1, 1, true); Tip():Show()
        end)
        bt[1]:HookScript("OnLeave", function() Tip():Hide() end)
    end

    f.up = {}
    for k = 1, 4 do
        local b = CreateFrame("Button", nil, f)
        b:SetSize(INNER, 26)
        local sep = Tex(b, COL.faint, 1, "ARTWORK"); sep:SetHeight(1); sep:SetPoint("TOPLEFT"); sep:SetPoint("TOPRIGHT")
        b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetSize(14, 14); b.icon:SetPoint("LEFT", 2, -1)
        b.right = FS(b, 10, COL.gold, FONT, "RIGHT"); b.right:SetPoint("RIGHT", 0, -1)
        local fs = FS(b, 11, COL.soft, FONT, "LEFT")
        fs:SetPoint("LEFT", 22, -1); fs:SetPoint("RIGHT", b.right, "LEFT", -6, 0)
        if fs.SetWordWrap then fs:SetWordWrap(false) end
        b.fs = fs
        local h = Tex(b, COL.accent, 0.08, "HIGHLIGHT"); h:SetAllPoints()
        b:SetScript("OnClick", function(self)
            if self.idx then focus = self.idx; peek = nil; lastWP = nil; Refresh(true) end
        end)
        b:SetScript("OnEnter", function(self)
            Tip():SetOwner(self, "ANCHOR_LEFT")
            Tip():AddLine(T("clickGo"))
            local st = self.idx and steps and steps[self.idx]
            if st and st.t == "do" and type(st.id) == "number" and EST[st.id] then
                local e = Estimate({ st.id }, false)
                Tip():AddLine(T("estTip", FormatNum(e.xp), FormatNum(e.qxp), FormatNum(e.mxp), math.max(1, math.floor(e.secs / 60 + 0.5)), FormatNum(e.perHour)), 0.8, 0.73, 0.56, true)
            end
            Tip():Show()
        end)
        b:SetScript("OnLeave", function() Tip():Hide() end)
        b:Hide()
        f.up[k] = b
    end

    f.passed = FS(f, 10, COL.gold, FONT, "LEFT"); f.passed:SetWidth(INNER - 22); f.passed:Hide()
    f.badge.lbl:SetText(T("lvlShort"))

    -- v1.40 : poignee en bas a droite = agrandir / reduire la fenetre (echelle, comme dans les options), hors combat
    local grip = CreateFrame("Button", nil, f)
    grip:SetSize(12, 12); grip:SetPoint("BOTTOMRIGHT", -1, 1)
    if grip.SetFrameLevel and f.GetFrameLevel then grip:SetFrameLevel((f:GetFrameLevel() or 1) + 10) end
    local gt = grip:CreateTexture(nil, "OVERLAY"); gt:SetAllPoints()
    gt:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    if gt.SetVertexColor then gt:SetVertexColor(COL.accent[1], COL.accent[2], COL.accent[3]) end
    local gh = grip:CreateTexture(nil, "HIGHLIGHT"); gh:SetAllPoints(); gh:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetScript("OnMouseDown", function(self)
        if DB.locked or (InCombatLockdown and InCombatLockdown()) or not GetCursorPosition then return end
        local s, left, top = f:GetScale() or 1, f:GetLeft(), f:GetTop()
        if not (left and top) then return end
        local ui = (UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()) or 1
        -- le coin haut-gauche reste en place ; la largeur suit la souris
        self.drag = { s = s, left = left * s, top = top * s, x0 = GetCursorPosition() / ui, w = W * s, ui = ui }
        self:SetScript("OnUpdate", function()
            local d = self.drag; if not d then return end
            local dx = GetCursorPosition() / d.ui - d.x0
            local sc = math.max(0.6, math.min(1.5, d.s * (d.w + dx) / d.w))
            f:SetScale(sc); f:ClearAllPoints(); f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", d.left / sc, d.top / sc)
        end)
    end)
    grip:SetScript("OnMouseUp", function(self)
        self:SetScript("OnUpdate", nil)
        if not self.drag then return end
        self.drag = nil
        DB.scale = math.floor((f:GetScale() or 1) * 100 + 0.5) / 100
        local p, _, rp, x, y = f:GetPoint(); DB.wpos = { p, rp, x, y }
        local mf = rawget(f, "mini"); if mf and mf.SetScale then mf:SetScale(DB.scale) end
        if ns.UI and ns.UI.RefreshOptions then ns.UI.RefreshOptions() end
    end)
    grip:SetScript("OnEnter", function(self) Tip():SetOwner(self, "ANCHOR_RIGHT"); Tip():AddLine(T("winResize"), 1, 1, 1, true); Tip():Show() end)
    grip:SetScript("OnLeave", function() Tip():Hide() end)

    -- bouton « - » en haut a droite : passer en mode compact
    local function miniBtn(parent, label, tipKey)
        local b = CreateFrame("Button", nil, parent); b:SetSize(16, 14)
        b.fs = FS(b, 12, COL.gold, FONT, "CENTER"); b.fs:SetPoint("CENTER"); b.fs:SetText(label)
        local h = Tex(b, COL.accent, 0.12, "HIGHLIGHT"); h:SetAllPoints()
        b:SetScript("OnClick", function() ToggleMini() end)
        b:SetScript("OnEnter", function(self) Tip():SetOwner(self, "ANCHOR_LEFT"); Tip():AddLine(T(tipKey), 1, 1, 1, true); Tip():Show() end)
        b:SetScript("OnLeave", function() Tip():Hide() end)
        return b
    end
    f.miniBtn = miniBtn(f, "-", "miniEnter"); f.miniBtn:SetPoint("TOPRIGHT", -2, -1)

    -- v1.40 : mode compact = une petite fenetre a part, seulement les objectifs (ou une ligne pour prendre/rendre)
    local mf = CreateFrame("Frame", "WarpathMini", UIParent)
    mf:SetSize(MINI_W, 30)
    if DB.mpos then mf:SetPoint(DB.mpos[1], UIParent, DB.mpos[2], DB.mpos[3], DB.mpos[4])
    else mf:SetPoint("TOPRIGHT", f, "TOPRIGHT") end
    local mbg = Tex(mf, COL.bg, 0.90, "BACKGROUND"); mbg:SetAllPoints()
    Border(mf, COL.line, 0.8, "BORDER")
    mf:SetClampedToScreen(true); mf:SetMovable(true); mf:EnableMouse(true); mf:RegisterForDrag("LeftButton")
    mf:SetScript("OnDragStart", function(self) if not DB.locked then self:StartMoving() end end)
    mf:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local p, _, rp, x, y = self:GetPoint(); DB.mpos = { p, rp, x, y }
    end)
    mf.plus = miniBtn(mf, "+", "miniExit"); mf.plus:SetPoint("TOPRIGHT", -2, -2)
    mf.rows = {}
    if mf.SetScale then mf:SetScale(DB.scale or 1) end
    mf:Hide()
    f.mini = mf

    f:SetShown(DB.shown ~= false)
    if f.SetScale then f:SetScale(DB.scale or 1) end
end

------------------------------------------------------------------
-- Mode compact (v1.40) : la grande fenetre est cachee, la petite montre l'essentiel de l'etape
------------------------------------------------------------------
MINI_W, MINI_PAD = 230, 10
local function miniRow(mf, k)
    local r = mf.rows[k]
    if r then return r end
    r = CreateFrame("Frame", nil, mf); r:SetSize(MINI_W - 2 * MINI_PAD - 14, 16)
    r.gem = Diamond(r, 7, COL.accent, true); r.gem:SetPoint("LEFT", -2, 0)
    r.count = FS(r, 12, COL.accent, FONT, "RIGHT"); r.count:SetPoint("RIGHT")
    r.name = FS(r, 12, COL.white, FONT, "LEFT"); r.name:SetPoint("LEFT", 14, 0); r.name:SetPoint("RIGHT", r.count, "LEFT", -8, 0)
    if r.name.SetWordWrap then r.name:SetWordWrap(false) end
    mf.rows[k] = r
    return r
end

function UpdateMini()
    local mf = f and rawget(f, "mini")
    if not mf then return end
    local dl = DungeonLogActive and DungeonLogActive()
    local on = DB.mini and DB.shown ~= false and steps and not dl and true or false
    f:SetShown(DB.shown ~= false and not on)
    mf:SetShown(on)
    if not on then return end
    -- objectifs de l'etape (ceux de la grande fenetre), sinon une ligne : type d'etape + PNJ ou lieu
    local lines = {}
    for k = 1, (rawget(f, "nObj") or 0) do
        local w = f.obj[k]
        if w and w.kind == "obj" then lines[#lines + 1] = { text = w.name:GetText() or "", count = w.count:GetText() or "", done = w.done } end
    end
    if #lines == 0 then
        local s = steps[peek or focus or current]
        if s then
            local nm = (s.t ~= "do" and f.dest and f.dest:IsShown() and f.destName:GetText()) or (s.t ~= "do" and s.quest and QName(s)) or ""
            if nm == "" and StepText then nm = (StepText(s) or ""):gsub("\n.*", "") end
            lines[1] = { verb = Caps(T(s.t)), text = nm }
        end
    end
    local y = -MINI_PAD
    for k, l in ipairs(lines) do
        if k > 8 then break end
        local r = miniRow(mf, k)
        r:ClearAllPoints(); r:SetPoint("TOPLEFT", mf, "TOPLEFT", MINI_PAD, y)
        r.name:SetText(l.verb and ("|cffd6b866" .. l.verb .. "|r  " .. l.text) or l.text)
        r.count:SetText(l.count or "")
        local c = l.done and COL.dim or COL.white
        if r.name.SetTextColor then r.name:SetTextColor(c[1], c[2], c[3]) end
        c = l.done and COL.dim or COL.accent
        if r.count.SetTextColor then r.count:SetTextColor(c[1], c[2], c[3]) end
        r.gem:SetStyle(l.done and COL.dim or COL.accent, not l.done)
        -- ligne unique (note, prise, remise) : le texte peut passer a la ligne ; objectifs : une ligne chacun
        if r.name.SetWordWrap then r.name:SetWordWrap(l.verb and true or false) end
        local h = 16
        if l.verb and r.name.GetStringHeight then
            local sh = r.name:GetStringHeight()
            if type(sh) == "number" and sh > h then h = math.min(sh, 60) end
        end
        r:SetHeight(h)
        r:Show()
        y = y - h - 4
    end
    for k = #lines + 1, #mf.rows do mf.rows[k]:Hide() end
    mf:SetHeight(-y + MINI_PAD - 4)
end

function ToggleMini()
    DB.mini = not DB.mini
    Refresh(true)
end

-- afficher / cacher le guide (grande ou petite fenetre selon le mode)
function ShowGuide(v)
    DB.shown = v and true or false
    if f then
        if UpdateMini then pcall(UpdateMini) end
        if not rawget(f, "mini") then f:SetShown(DB.shown) end
    end
    if ns.Targets then ns.Targets.Refresh() end
end

------------------------------------------------------------------
-- Ce que la fenetre d'options (Options.lua) utilise du moteur
------------------------------------------------------------------
ns.E = {
    T = T, Title = Title, Lang = Lang, say = say, Refresh = Refresh, SetGuide = SetGuide,
    StartDungeon = StartDungeon, StopDungeon = StopDungeon, ClearWaypoint = ClearWaypoint,
    AutoPick = AutoPick, AllDone = AllDone,
    ClassQuestList = function() return ClassQuestList() end, PlaceWaypointAgain = function() if steps and current and steps[current] then pcall(SetWaypoint, steps[current]) end end, StyleGet = function() return StyleGet() end,
    ApplyPreset = function(n) local ok, err = pcall(ApplyPreset, n); if not ok then say(T("errInternal", tostring(err))) end end, StyleChanged = function() styleCache = nil; local ok, err = pcall(Advance); if not ok then say(T("errInternal", tostring(err))) end; Refresh(true) end, AskClass = function(q) AskChain(q, true) end, ChronShow = function(k) ChronShow(k) end, BugWindow = function() BugWindow() end,
    Guides = Guides, ICON = ICON, VERSION = VERSION, CHECK = CHECK,
    MAIN_ORDER = MAIN_ORDER, IS_DUNGEON = IS_DUNGEON, DUNGEONS = DUNGEONS, MINLVL = MINLVL, MAXLVL = MAXLVL,
    DB = function() return DB end,
    Frame = function() return f end,
    Guide = function() return G end,
    Steps = function() return steps end,
    Current = function() return current end,
    Race = function() return myRace end,
    ResetWP = function() lastWP = nil end,
    ShowGuide = function(v) ShowGuide(v) end,
    WarpathName = WarpathName,
    Tip = function() return Tip() end, GuideStatus = function(k) return GuideStatus(k) end,
    ProfOrder = function() return PROF_ORDER end, ProfKey = function(id) return PROF_KEY[id] end, ProfName = function(id) return ProfName(id) end, TrainerPins = function() if TrainerPinsRefresh then pcall(TrainerPinsRefresh, true) end end,
    ProfQuestList = function() return ProfQuestList() end, ProfOn = function(id) return ProfOn(id) end,
    ProfSet = function(id, v) ProfSet(id, v) end, ProfDetect = function() return ProfDetect(true) end,
    AskProf = function(q) AskChain(q, true, "prof") end,
    Kit = { COL = COL, FONT = FONT, DISPLAY = DISPLAY, Caps = Caps, Upper = Upper, Spaced = Spaced, FS = FS, Tex = Tex,
            Diamond = Diamond, Divider = Divider, TitledRule = TitledRule, FlatButton = FlatButton,
            Border = Border, SectionHead = SectionHead, Chip = Chip, DiamondCheck = DiamondCheck },
}
ns.UI = ns.UI or {}

------------------------------------------------------------------
-- Carte de vol : apprendre les trajets connus et surligner la destination
------------------------------------------------------------------
taxiGlow = nil

function NodeKeyFor(name)
    if not name then return nil end
    for _, n in ipairs(FLIGHTS) do
        if name:find(n.key, 1, true) then return n.key end
    end
end

function OnTaxiOpened()
    if not NumTaxiNodes then return end
    DB.fp = DB.fp or {}
    DB.fpLinks = DB.fpLinks or {}
    local target, here
    local reach = {}
    for i = 1, NumTaxiNodes() do
        local name = TaxiNodeName and TaxiNodeName(i)
        local kind = TaxiNodeGetType and TaxiNodeGetType(i)
        local key = NodeKeyFor(name)
        if key then
            -- CURRENT = ici ; REACHABLE = connu et atteignable. Sur Forever, DISTANT designe aussi les points
            -- JAMAIS decouverts (Everlook, Moonglade... au niveau 23) : on ne les compte plus (v1.39).
            if kind == "CURRENT" or kind == "REACHABLE" then DB.fp[key] = true end
            if kind == "CURRENT" then here = key; ns.Comfort.SetTaxiFrom(name) end
            if kind == "REACHABLE" then reach[key] = true end
        end
        if flightPlan and key == flightPlan.to.key and kind == "REACHABLE" then target = i end
    end
    if here then DB.fpLinks[here] = reach end
    if target then
        local btn = _G["TaxiButton" .. target]
        if btn then
            if not taxiGlow then
                taxiGlow = CreateFrame("Frame", nil, UIParent)
                taxiGlow:SetSize(44, 44)
                local t = taxiGlow:CreateTexture(nil, "OVERLAY")
                t:SetAllPoints()
                t:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
                t:SetBlendMode("ADD")
                t:SetVertexColor(0.2, 1, 0.3)
                taxiGlow.tex = t
                local elapsed = 0
                taxiGlow:SetScript("OnUpdate", function(self, dt)
                    elapsed = elapsed + (dt or 0)
                    self.tex:SetAlpha(0.55 + 0.45 * math.sin(elapsed * 5))
                end)
            end
            taxiGlow:SetParent(btn)
            taxiGlow:ClearAllPoints()
            taxiGlow:SetPoint("CENTER", btn, "CENTER")
            taxiGlow:SetFrameLevel((btn:GetFrameLevel() or 1) + 5)
            taxiGlow:Show()
        end
        say(T("flyTo", flightPlan.to.name))
        if DB.autoFly ~= false and not (IsShiftKeyDown and IsShiftKeyDown()) and TakeTaxiNode then
            local node = target
            if C_Timer and C_Timer.After then C_Timer.After(0.4, function() if TaxiFrame and TaxiFrame:IsShown() or (TaxiNodeName and TaxiNodeName(node)) then ns.Trace("TakeTaxiNode"); TakeTaxiNode(node) end end) else ns.Trace("TakeTaxiNode"); TakeTaxiNode(node) end
        end
    end
    Refresh(true)
end

function OnTaxiClosed()
    if taxiGlow then taxiGlow:Hide() end
end

------------------------------------------------------------------
-- La fleche reste en place : si le jeu efface le waypoint a l'arrivee (ex. au maitre de vol),
-- on le remet des que tu t'en eloignes un peu, tant que le guide en a encore besoin.
------------------------------------------------------------------
wpTicker = CreateFrame("Frame")
wpElapsed = 0
distElapsed = 0
wpTicker:SetScript("OnUpdate", function(_, dt)
    distElapsed = distElapsed + (dt or 0)
    if distElapsed >= 0.5 then distElapsed = 0; UpdateDistance() end
    wpElapsed = wpElapsed + (dt or 0)
    if wpElapsed < 1 then return end
    wpElapsed = 0
    if DB then pcall(LearnGates) end
    if not (DB and DB.wp and desiredWP) then return end
    if not (C_Map and C_Map.HasUserWaypoint) or C_Map.HasUserWaypoint() then return end
    if UnitOnTaxi and UnitOnTaxi("player") then return end
    local me = PlayerWP()
    local w = WP(desiredWP.m, desiredWP.x, desiredWP.y)
    local d = me and w and me[3] == w[3] and Dist(me[1], me[2], w[1], w[2])
    if not d or d > 12 then PlaceNative(desiredWP) end
end)
