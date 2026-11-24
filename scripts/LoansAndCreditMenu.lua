-- In-game menu for Loans And Credit. Drawn by the mod itself; works with mouse and keyboard.
-- Open/close: Ctrl+B (rebindable in Controls). Esc closes, Tab switches tabs.

LCMenu = {}
local M = LCMenu
local LC = LoansAndCredit

M.isOpen = false
M.tab = 1
M.buttons = {}
M.mx, M.my = 0.5, 0.5
M.lastToggle = 0
M.loanSel = 1
M.loanScroll = 0
M.collSel = 1
M.collScroll = 0
M.setSel = 1
M.setScroll = 0
M.newType = 1
M.newAmount = 0
M.newMonths = 36
M.extraAmount = 10000
M.resetConfirmUntil = 0
M.popupLoanId = nil
M.popupMonths = 60
M.popupShown = {}
M.popupTimer = 0
M.confirmCmd = nil
M.confirmUntil = 0
M.pendingCmd = nil

-- save / quit actions: rebindable in Controls, but registered only in the menu's own input context,
-- so they work only while this menu is open. The raw keys are a fallback if a binding is missing.
M.ACTIONS = {
    { action = "LC_SAVE_GAME", cmd = "save", key = "KEY_s" },
    { action = "LC_QUIT_MENU", cmd = "quitMenu", key = "KEY_q" },
    { action = "LC_QUIT_DESKTOP", cmd = "quitDesktop", key = "KEY_x" }
}

M.TABS = { "tabOverview", "tabLoans", "tabNew", "tabSettings", "tabAppearance" }

-- layout
M.PX, M.PY, M.PW, M.PH = 0.16, 0.09, 0.68, 0.82
M.T_TITLE, M.T_NORMAL, M.T_SMALL, M.T_BIG = 0.022, 0.0145, 0.0125, 0.055
M.ROW = 0.03

-- colours
M.C = {
    bg = { 0.04, 0.06, 0.05, 0.95 }, header = { 0.07, 0.19, 0.12, 1 }, panel = { 0.08, 0.11, 0.09, 1 },
    stripe = { 0.11, 0.14, 0.12, 1 }, sel = { 0.20, 0.34, 0.22, 1 }, btn = { 0.15, 0.24, 0.17, 1 },
    btnHover = { 0.24, 0.38, 0.26, 1 }, btnActive = { 0.62, 0.48, 0.14, 1 }, btnOff = { 0.14, 0.14, 0.14, 1 },
    text = { 0.95, 0.95, 0.93, 1 }, dim = { 0.65, 0.68, 0.66, 1 }, off = { 0.42, 0.42, 0.42, 1 },
    gold = { 0.96, 0.77, 0.27, 1 }, red = { 0.93, 0.33, 0.27, 1 }, orange = { 0.95, 0.58, 0.2, 1 },
    yellow = { 0.93, 0.86, 0.3, 1 }, lime = { 0.62, 0.86, 0.35, 1 }, green = { 0.33, 0.85, 0.42, 1 },
    accent = { 0.80, 0.65, 0.22, 1 }
}

M.RATING_COLOR = { poor = "red", fair = "orange", good = "yellow", veryGood = "lime", excellent = "green" }

-- ---------------------------------------------------------------- lifecycle

function M:load()
    self.pixel = createImageOverlay(LC.modDir .. "textures/pixel.dds")
    LCTheme:load()
    LCTheme:apply(self.C)
end

function M:delete()
    if self.isOpen then
        self:close()
    end
    if self.pixel ~= nil and self.pixel ~= 0 then
        delete(self.pixel)
        self.pixel = nil
    end
end

function M:canOpen()
    if g_currentMission == nil or not g_currentMission:getIsClient() then
        return false
    end
    if g_gui ~= nil and g_gui:getIsGuiVisible() then
        return false
    end
    return true
end

function M:toggle()
    if g_time - self.lastToggle < 250 then
        return
    end
    self.lastToggle = g_time
    if self.isOpen then
        self:close()
    elseif self:canOpen() then
        self:open()
    end
end

function M:open()
    self.isOpen = true
    self.contextSet = false
    if g_inputBinding.setContext ~= nil then
        -- an empty input context, so menu keys don't also walk, drive or open game menus
        g_inputBinding:setContext("LC_MENU", true, false)
        self.contextSet = true
        self:registerMenuActions()
    end
    if g_inputBinding.setShowMouseCursor ~= nil then
        g_inputBinding:setShowMouseCursor(true)
    end
    self:hideOtherHuds()
    self:installGlobalDrawHook()
    self.hookTimer = 0
    self:resetNewLoan()
end

function M:close()
    self.isOpen = false
    self.popupLoanId = nil
    self.confirmCmd = nil
    self:restoreOtherHuds()
    if self.contextSet and g_inputBinding.revertContext ~= nil then
        g_inputBinding:revertContext(true)
    end
    self.contextSet = false
    if g_inputBinding.setShowMouseCursor ~= nil then
        g_inputBinding:setShowMouseCursor(false)
    end
end

function M:update(dt)
    self:updateSaveWatch()
    if self.pendingCmd ~= nil then
        local cmd = self.pendingCmd
        self.pendingCmd = nil
        self:runCommand(cmd)
    end
    if self.isOpen and g_gui ~= nil and g_gui:getIsGuiVisible() then
        self:close()
    end
    if not self.isOpen then
        self:checkTransferPopup(dt)
    end
    if self.isOpen then
        -- another mod may wrap the frame's draw after us; take the last spot back now and then
        self.hookTimer = (self.hookTimer or 0) + dt
        if self.hookTimer > 2000 then
            self.hookTimer = 0
            self:installGlobalDrawHook()
        end
    end
end

-- ---------------------------------------------------------------- staying on top of other HUDs

-- While the menu is open: the game's HUD is switched off and other mods' draw functions are skipped,
-- so their HUDs (for example the Markets And Futures HUD) can't draw over the menu. Both come back on close.
function M:hideOtherHuds()
    local hud = g_currentMission.hud
    self.hudWasVisible = nil
    if hud ~= nil and hud.setIsVisible ~= nil and hud.getIsVisible ~= nil then
        self.hudWasVisible = hud:getIsVisible()
        hud:setIsVisible(false)
    end
    self.suppressed = {}
    for _, listener in pairs(g_modEventListeners or {}) do
        if type(listener) == "table" and listener ~= LoansAndCredit and listener.draw ~= nil then
            table.insert(self.suppressed, { listener = listener, own = rawget(listener, "draw") })
            rawset(listener, "draw", M.noDraw)
        end
    end
    if not self.loggedSuppress then
        self.loggedSuppress = true
        Logging.info("[LoansAndCredit] menu open: hid game HUD %s, paused drawing of %d other mod(s)",
            tostring(self.hudWasVisible ~= nil), #self.suppressed)
    end
end

function M.noDraw()
end

function M:restoreOtherHuds()
    for _, entry in ipairs(self.suppressed or {}) do
        if rawget(entry.listener, "draw") == M.noDraw then
            rawset(entry.listener, "draw", entry.own)
        end
    end
    self.suppressed = {}
    local hud = g_currentMission.hud
    if self.hudWasVisible ~= nil and hud ~= nil and hud.setIsVisible ~= nil then
        hud:setIsVisible(self.hudWasVisible)
    end
    self.hudWasVisible = nil
end

-- Draws the menu at the very end of each frame, after the game and every mod, by wrapping the engine's
-- global draw(). The normal mod draw stays as a fallback and skips itself while this hook is working.
function M:installGlobalDrawHook()
    local G = _G
    if type(G.draw) ~= "function" or G.draw == M.globalWrapper then
        return
    end
    M.globalGen = (M.globalGen or 0) + 1
    local gen = M.globalGen
    local orig = G.draw
    local wrapped = function(...)
        local r1, r2 = orig(...)
        if gen == M.globalGen and M.isOpen and g_currentMission ~= nil then
            M.globalStamp = g_time
            M:drawPanel()
        end
        return r1, r2
    end
    M.globalWrapper = wrapped
    G.draw = wrapped
end

-- ---------------------------------------------------------------- drawing helpers

function M:rect(x, y, w, h, c)
    if self.pixel == nil then
        return
    end
    setOverlayColor(self.pixel, c[1], c[2], c[3], c[4] or 1)
    renderOverlay(self.pixel, x, y, w, h)
end

function M:text(x, y, size, str, align, c, bold)
    c = c or self.C.text
    setTextBold(bold == true)
    setTextColor(c[1], c[2], c[3], c[4] or 1)
    setTextAlignment(align or RenderText.ALIGN_LEFT)
    renderText(x, y, size, tostring(str))
end

function M:fit(str, size, width)
    str = tostring(str)
    if getTextWidth(size, str) <= width then
        return str
    end
    while string.len(str) > 1 and getTextWidth(size, str .. "...") > width do
        str = string.sub(str, 1, -2)
    end
    return str .. "..."
end

function M:isInside(x, y, w, h)
    return self.mx >= x and self.mx <= x + w and self.my >= y and self.my <= y + h
end

function M:button(x, y, w, h, label, callback, enabled, active)
    enabled = enabled ~= false
    local hover = enabled and self:isInside(x, y, w, h)
    local c = self.C.btn
    if not enabled then
        c = self.C.btnOff
    elseif active then
        c = self.C.btnActive
    elseif hover then
        c = self.C.btnHover
    end
    self:rect(x, y, w, h, c)
    local tc = self.C.text
    if not enabled then
        tc = self.C.off
    end
    self:text(x + w / 2, y + h / 2 - self.T_SMALL * 0.35, self.T_SMALL, self:fit(label, self.T_SMALL, w - 0.006),
        RenderText.ALIGN_CENTER, tc, active)
    if enabled then
        table.insert(self.buttons, { x = x, y = y, w = w, h = h, cb = callback })
    end
end

-- an invisible click area (list rows)
function M:clickArea(x, y, w, h, callback)
    table.insert(self.buttons, { x = x, y = y, w = w, h = h, cb = callback })
end

function M:pct(v)
    return string.format("%.2f%%", v)
end

function M:months(n)
    if n >= 12 and n % 12 == 0 then
        return LC.t("years", n / 12)
    end
    return LC.t("monthsN", n)
end

function M:farmId()
    return g_currentMission:getFarmId()
end

function M:isHost()
    return LC:isServer() and g_currentMission:getIsClient()
end

-- ---------------------------------------------------------------- main draw

function M:draw()
    if not self.isOpen then
        return
    end
    if self.globalStamp ~= nil and g_time - self.globalStamp < 300 then
        return
    end
    self:drawPanel()
end

function M:drawPanel()
    self.buttons = {}
    if self.popupLoanId ~= nil then
        self:drawPopup()
        return
    end
    local px, py, pw, ph = self.PX, self.PY, self.PW, self.PH
    self:rect(px, py, pw, ph, self.C.bg)

    -- header
    local hh = 0.05
    self:rect(px, py + ph - hh, pw, hh, self.C.header)
    self:rect(px, py + ph - hh, pw, 0.003, self.C.accent)
    self:text(px + 0.015, py + ph - hh + 0.016, self.T_TITLE, self:fit(LC.t("title"), self.T_TITLE, 0.175),
        RenderText.ALIGN_LEFT, self.C.gold, true)
    local farmId = self:farmId()
    local money = LC:getFarmMoney(farmId)
    self:button(px + pw - 0.04, py + ph - hh + 0.01, 0.03, 0.03, "X", function()
        self:close()
    end)

    -- save / quit
    local gx = px + 0.21
    local items = {
        { cmd = "save", label = self:isSaving() and "btnSaving" or "btnSave", w = 0.065,
            enabled = self:canSave() and not self:isSaving() },
        { cmd = "quitMenu", label = "btnQuitMenu", w = 0.085, enabled = not self:isSaving() },
        { cmd = "quitDesktop", label = "btnQuitDesktop", w = 0.075, enabled = not self:isSaving() }
    }
    for _, it in ipairs(items) do
        local confirming = self:isConfirming(it.cmd)
        local cmd = it.cmd
        local label = confirming and LC.t("btnConfirm") or LC.t(it.label)
        -- longer words in other languages: grow the button, up to a limit
        local bw = math.min(0.11, math.max(it.w, getTextWidth(self.T_SMALL, label) + 0.014))
        self:button(gx, py + ph - hh + 0.01, bw, 0.03, label, function()
            self:command(cmd)
        end, it.enabled, confirming)
        gx = gx + bw + 0.006
    end
    -- account balance, squeezed into whatever room the buttons leave
    local balRight = px + pw - 0.05
    self:text(balRight, py + ph - hh + 0.018, self.T_NORMAL,
        self:fit(LC.t("balance", LC.formatMoney(money)), self.T_NORMAL, math.max(0.02, balRight - gx - 0.01)),
        RenderText.ALIGN_RIGHT, self.C.text)

    -- tabs
    local ty = py + ph - hh - 0.042
    local tw = 0.118
    for i, key in ipairs(self.TABS) do
        self:button(px + 0.015 + (i - 1) * (tw + 0.006), ty, tw, 0.034, LC.t(key), function()
            self.tab = i
        end, true, self.tab == i)
    end

    -- content area
    local cx, cy, cw, ch = px + 0.015, py + 0.04, pw - 0.03, ty - py - 0.05
    if (farmId == nil or farmId <= 0) and self.tab < 4 then
        self:text(cx, cy + ch - 0.03, self.T_NORMAL, LC.t("noFarm"), RenderText.ALIGN_LEFT, self.C.dim)
    elseif self.tab == 1 then
        self:drawOverview(cx, cy, cw, ch, farmId)
    elseif self.tab == 2 then
        self:drawLoans(cx, cy, cw, ch, farmId)
    elseif self.tab == 3 then
        self:drawNew(cx, cy, cw, ch, farmId)
    elseif self.tab == 4 then
        self:drawSettings(cx, cy, cw, ch)
    end
    if self.tab == 5 then
        self:drawAppearance(cx, cy, cw, ch)
    end

    -- help lines
    self:text(px + 0.015, py + 0.022, self.T_SMALL, LC.t("help"), RenderText.ALIGN_LEFT, self.C.dim)
    self:text(px + 0.015, py + 0.006, self.T_SMALL, LC.t("help2"), RenderText.ALIGN_LEFT, self.C.dim)

    setTextBold(false)
    setTextColor(1, 1, 1, 1)
    setTextAlignment(RenderText.ALIGN_LEFT)
end

-- ---------------------------------------------------------------- overview

function M:drawOverview(x, y, w, h, farmId)
    local farm = LC:getFarm(farmId)
    local top = y + h
    local lw = w * 0.46
    self:rect(x, y, lw, h, self.C.panel)

    local rating = LC:getRatingKey(farm.score)
    local rc = self.C[self.RATING_COLOR[rating]]
    self:text(x + 0.015, top - 0.03, self.T_NORMAL, LC.t("creditScore"), RenderText.ALIGN_LEFT, self.C.dim)
    self:text(x + 0.015, top - 0.09, self.T_BIG, tostring(farm.score), RenderText.ALIGN_LEFT, rc, true)
    self:text(x + 0.13, top - 0.075, self.T_TITLE, LC.t("r_" .. rating), RenderText.ALIGN_LEFT, rc, true)

    -- gauge 300..850
    local gx, gy, gw, gh = x + 0.015, top - 0.125, lw - 0.03, 0.012
    local bands = { { 300, 580, "red" }, { 580, 670, "orange" }, { 670, 740, "yellow" }, { 740, 800, "lime" },
        { 800, 850, "green" } }
    for _, b in ipairs(bands) do
        local bx = gx + (b[1] - 300) / 550 * gw
        local bw = (b[2] - b[1]) / 550 * gw
        local c = self.C[b[3]]
        self:rect(bx, gy, bw, gh, { c[1] * 0.75, c[2] * 0.75, c[3] * 0.75, 1 })
    end
    local mx = gx + (farm.score - 300) / 550 * gw
    self:rect(mx - 0.0015, gy - 0.006, 0.003, gh + 0.012, self.C.text)
    self:text(gx, gy - 0.02, self.T_SMALL, "300", RenderText.ALIGN_LEFT, self.C.dim)
    self:text(gx + gw, gy - 0.02, self.T_SMALL, "850", RenderText.ALIGN_RIGHT, self.C.dim)

    -- figures
    local loans = LC:getLoansForFarm(farmId)
    local debt, monthly, overdue = 0, 0, 0
    for _, loan in ipairs(loans) do
        debt = debt + loan.balance
        monthly = monthly + math.min(loan.payment, loan.balance)
        overdue = overdue + loan.arrears
    end
    local limit = LC:getUnsecuredLimit(farm.score)
    local used = LC:getUnsecuredUsed(farmId)
    local rows = {
        { LC.t("rateTerm"), self:pct(LC:getApr(LC.TYPE_TERM, farm.score)) },
        { LC.t("rateEquip"), self:pct(LC:getApr(LC.TYPE_EQUIP, farm.score)) },
        { LC.t("rateLand"), self:pct(LC:getApr(LC.TYPE_LAND, farm.score)) },
        { LC.t("unsecured"), LC.formatMoney(used) .. " / " .. LC.formatMoney(limit) },
        { LC.t("totalDebt"), LC.formatMoney(debt) },
        { LC.t("monthlyTotal"), LC.formatMoney(monthly) },
        { LC.t("overdue"), LC.formatMoney(overdue), overdue > 0 and self.C.red or nil }
    }
    local ry = gy - 0.055
    for _, r in ipairs(rows) do
        self:text(x + 0.015, ry, self.T_NORMAL, r[1], RenderText.ALIGN_LEFT, self.C.dim)
        self:text(x + lw - 0.015, ry, self.T_NORMAL, r[2], RenderText.ALIGN_RIGHT, r[3] or self.C.text)
        ry = ry - 0.028
    end

    -- status
    ry = ry - 0.01
    local ok, err = LC:canBorrow(farmId)
    if ok then
        self:text(x + 0.015, ry, self.T_NORMAL, LC.t("statusOk"), RenderText.ALIGN_LEFT, self.C.green, true)
    elseif err == LC.CODE.ERR_BLOCKED then
        self:text(x + 0.015, ry, self.T_NORMAL, LC.t("statusBlocked", farm.blockedUntil - LC.month),
            RenderText.ALIGN_LEFT, self.C.red, true)
    else
        self:text(x + 0.015, ry, self.T_NORMAL, self:fit(LC:getCodeText(err, 0, ""), self.T_NORMAL, lw - 0.03),
            RenderText.ALIGN_LEFT, self.C.red, true)
    end
    if LC:getSetting("blockBaseLoan") == 1 then
        self:text(x + 0.015, y + 0.015, self.T_SMALL, self:fit(LC.t("baseNote"), self.T_SMALL, lw - 0.03),
            RenderText.ALIGN_LEFT, self.C.dim)
    end

    -- history
    local hx, hw = x + lw + 0.012, w - lw - 0.012
    self:rect(hx, y, hw, h, self.C.panel)
    self:text(hx + 0.012, top - 0.03, self.T_NORMAL, LC.t("history"), RenderText.ALIGN_LEFT, self.C.gold, true)
    local hy = top - 0.06
    if #farm.history == 0 then
        self:text(hx + 0.012, hy, self.T_SMALL, LC.t("noHistory"), RenderText.ALIGN_LEFT, self.C.dim)
    end
    for i, e in ipairs(farm.history) do
        if hy < y + 0.01 then
            break
        end
        if i % 2 == 0 then
            self:rect(hx + 0.004, hy - 0.007, hw - 0.008, 0.026, self.C.stripe)
        end
        local c = self.C.text
        if e.code == LC.CODE.MISSED or e.code == LC.CODE.DEFAULT or e.code == LC.CODE.REPO
            or e.code == LC.CODE.SEIZE or e.code == LC.CODE.CONVERTED then
            c = self.C.red
        elseif e.code == LC.CODE.PAIDOFF then
            c = self.C.green
        end
        self:text(hx + 0.012, hy, self.T_SMALL, LC.t("monthShort", e.month), RenderText.ALIGN_LEFT, self.C.dim)
        local txt = LC.t("h" .. e.code)
        txt = string.gsub(txt, "%%AMOUNT%%", LC.formatMoney(e.amount))
        txt = string.gsub(txt, "%%LABEL%%", e.label)
        self:text(hx + 0.06, hy, self.T_SMALL, self:fit(txt, self.T_SMALL, hw - 0.07), RenderText.ALIGN_LEFT, c)
        hy = hy - 0.026
    end
end

-- ---------------------------------------------------------------- active loans

function M:typeName(t)
    if t == LC.TYPE_EQUIP then
        return LC.t("typeEquip")
    elseif t == LC.TYPE_LAND then
        return LC.t("typeLand")
    end
    return LC.t("typeTerm")
end

function M:drawLoans(x, y, w, h, farmId)
    local loans = LC:getLoansForFarm(farmId)
    local top = y + h
    if #loans == 0 then
        self:text(x, top - 0.03, self.T_NORMAL, LC.t("noLoans"), RenderText.ALIGN_LEFT, self.C.dim)
        self:button(x, top - 0.08, 0.16, 0.034, LC.t("tabNew"), function()
            self.tab = 3
        end)
        return
    end
    self.loanSel = LC.clamp(self.loanSel, 1, #loans)

    local cols = { 0, 0.11, 0.30, 0.42, 0.50, 0.60, 0.70 }
    local heads = { "colType", "colCollateral", "colBalance", "colRate", "colMonthly", "colLeft", "colStatus" }
    self:rect(x, top - 0.03, w, 0.03, self.C.header)
    for i, k in ipairs(heads) do
        self:text(x + 0.008 + cols[i] * w, top - 0.02, self.T_SMALL, LC.t(k), RenderText.ALIGN_LEFT, self.C.gold, true)
    end

    local visible = 9
    self.loanScroll = LC.clamp(self.loanScroll, 0, math.max(0, #loans - visible))
    if self.loanSel <= self.loanScroll then
        self.loanScroll = self.loanSel - 1
    elseif self.loanSel > self.loanScroll + visible then
        self.loanScroll = self.loanSel - visible
    end
    local ry = top - 0.03
    for i = self.loanScroll + 1, math.min(#loans, self.loanScroll + visible) do
        local loan = loans[i]
        ry = ry - self.ROW
        local bg = self.C.panel
        if i == self.loanSel then
            bg = self.C.sel
        elseif i % 2 == 0 then
            bg = self.C.stripe
        end
        self:rect(x, ry, w, self.ROW, bg)
        local idx = i
        self:clickArea(x, ry, w, self.ROW, function()
            self.loanSel = idx
        end)
        local ty = ry + 0.009
        local coll = loan.collLabel
        if coll == "" then
            coll = "-"
        end
        local status, sc = LC.t("stOk"), self.C.green
        if loan.arrears > 0 then
            status, sc = LC.t("stOverdue", loan.missed, LC:getSetting("missesToDefault")), self.C.red
        end
        local cells = { self:typeName(loan.type), coll, LC.formatMoney(loan.balance), self:pct(loan.apr),
            LC.formatMoney(math.min(loan.payment, loan.balance)), self:months(loan.paymentsLeft), status }
        for c = 1, #cells do
            local cwid = ((cols[c + 1] or 1) - cols[c]) * w - 0.01
            local color = self.C.text
            if c == 7 then
                color = sc
            end
            self:text(x + 0.008 + cols[c] * w, ty, self.T_SMALL, self:fit(cells[c], self.T_SMALL, cwid),
                RenderText.ALIGN_LEFT, color)
        end
    end

    -- detail and actions for the selected loan
    local loan = loans[self.loanSel]
    local dy = y
    local dh = 0.2
    self:rect(x, dy, w, dh, self.C.panel)
    local lx = x + 0.015
    local ly = dy + dh - 0.03
    self:text(lx, ly, self.T_NORMAL, self:typeName(loan.type) .. "  -  " .. (loan.collLabel ~= "" and loan.collLabel
        or LC.t("unsecuredShort")), RenderText.ALIGN_LEFT, self.C.gold, true)
    local payoff, fee = LC:getPayoffAmount(loan)
    local info = {
        { LC.t("principal"), LC.formatMoney(loan.principal) },
        { LC.t("interestOwed"), LC.formatMoney(loan.unpaidInterest) },
        { LC.t("missedTotal"), tostring(loan.totalMissed) },
        { LC.t("payoffFee"), LC.formatMoney(fee) }
    }
    for i, r in ipairs(info) do
        local yy = ly - 0.03 * i
        self:text(lx, yy, self.T_SMALL, r[1], RenderText.ALIGN_LEFT, self.C.dim)
        self:text(lx + 0.2, yy, self.T_SMALL, r[2], RenderText.ALIGN_RIGHT, self.C.text)
    end

    local bx = x + w * 0.42
    local bw = 0.14
    local money = LC:getFarmMoney(farmId)
    local due = math.min(loan.arrears, loan.balance)
    self:button(bx, ly - 0.035, bw * 2 + 0.01, 0.032, LC.t("payOverdue", LC.formatMoney(due)), function()
        LC:request(2, loan.id, 1, 0, 0)
    end, due > 0 and money >= due)

    self.extraAmount = LC.clamp(self.extraAmount, 1000, math.max(1000, math.floor(loan.balance)))
    local ey = ly - 0.08
    local steps = { { "-10k", -10000 }, { "-1k", -1000 }, { "+1k", 1000 }, { "+10k", 10000 } }
    for i, s in ipairs(steps) do
        local step = s[2]
        self:button(bx + (i - 1) * 0.042, ey, 0.038, 0.03, s[1], function()
            self.extraAmount = self.extraAmount + step
        end)
    end
    self:button(bx + 0.172, ey, 0.13, 0.03, LC.t("payExtra", LC.formatMoney(self.extraAmount)), function()
        LC:request(2, loan.id, 2, 0, self.extraAmount)
    end, money >= self.extraAmount)

    self:button(bx, ey - 0.045, bw * 2 + 0.01, 0.032, LC.t("payOff", LC.formatMoney(payoff)), function()
        LC:request(2, loan.id, 3, 0, 0)
    end, money >= payoff)

    if loan.needsTerm then
        self:button(bx + bw * 2 + 0.02, ly - 0.035, 0.12, 0.032, LC.t("chooseTerm"), function()
            self:openPopup(loan)
        end, true, true)
    end
end

-- ---------------------------------------------------------------- base-game loan transfer popup

-- shows the popup a few seconds into the game, once per loan per session, when no other screen is open
function M:checkTransferPopup(dt)
    self.popupTimer = self.popupTimer + dt
    if self.popupTimer < 3000 then
        return
    end
    self.popupTimer = 2000
    if not self:canOpen() then
        return
    end
    local farmId = self:farmId()
    if farmId == nil or farmId <= 0 then
        return
    end
    for _, loan in ipairs(LC:getLoansForFarm(farmId)) do
        if loan.needsTerm and not self.popupShown[loan.id] then
            self.popupShown[loan.id] = true
            self:openPopup(loan)
            return
        end
    end
end

function M:openPopup(loan)
    self.popupFromMenu = self.isOpen
    self.popupLoanId = loan.id
    self.popupMonths = LC.clamp(loan.termMonths, LC.ROLL_TERMS.min, LC.ROLL_TERMS.max)
    if not self.isOpen then
        self:open()
    end
end

function M:closePopup()
    -- opened from My Loans: go back there; opened by itself: close everything
    if self.popupFromMenu then
        self.popupLoanId = nil
    else
        self:close()
    end
end

function M:wrap(text, size, width)
    local lines, line = {}, ""
    for word in string.gmatch(text, "%S+") do
        local test = line == "" and word or (line .. " " .. word)
        if getTextWidth(size, test) > width and line ~= "" then
            table.insert(lines, line)
            line = word
        else
            line = test
        end
    end
    if line ~= "" then
        table.insert(lines, line)
    end
    return lines
end

function M:confirmPopup()
    if self.popupLoanId ~= nil then
        LC:request(6, self.popupLoanId, self.popupMonths, 0, 0)
    end
    self:closePopup()
end

function M:drawPopup()
    local loan = LC:getLoanById(self.popupLoanId)
    if loan == nil or not loan.needsTerm then
        self.popupLoanId = nil
        return
    end
    local x, y, w, h = 0.3, 0.2, 0.4, 0.6
    self:rect(0, 0, 1, 1, { 0, 0, 0, 0.45 })
    self:rect(x - 0.002, y - 0.003, w + 0.004, h + 0.006, self.C.accent)
    self:rect(x, y, w, h, self.C.bg)
    local hh = 0.05
    self:rect(x, y + h - hh, w, hh, self.C.header)
    self:text(x + 0.015, y + h - hh + 0.016, self.T_TITLE, LC.t("popTitle"), RenderText.ALIGN_LEFT, self.C.gold, true)

    local lx, top = x + 0.02, y + h - hh - 0.035
    self:text(lx, top, self.T_NORMAL, LC.t("popAmount"), RenderText.ALIGN_LEFT, self.C.dim)
    self:text(x + w - 0.02, top - 0.005, self.T_TITLE, LC.formatMoney(loan.balance), RenderText.ALIGN_RIGHT, self.C.gold, true)

    local ty = top - 0.04
    for _, line in ipairs(self:wrap(LC.t("popBody"), self.T_SMALL, w - 0.04)) do
        self:text(lx, ty, self.T_SMALL, line, RenderText.ALIGN_LEFT, self.C.text)
        ty = ty - 0.02
    end

    -- term selector
    local t = LC.ROLL_TERMS
    local sy = ty - 0.045
    self:rect(x + 0.01, sy - 0.012, w - 0.02, 0.05, self.C.panel)
    self:text(lx, sy + 0.006, self.T_NORMAL, LC.t("popTerm"), RenderText.ALIGN_LEFT, self.C.text, true)
    self:button(x + w - 0.19, sy - 0.004, 0.035, 0.032, "-", function()
        self.popupMonths = math.max(t.min, self.popupMonths - t.step)
    end, self.popupMonths > t.min)
    self:text(x + w - 0.11, sy + 0.006, self.T_NORMAL, self:months(self.popupMonths), RenderText.ALIGN_CENTER, self.C.gold, true)
    self:button(x + w - 0.055, sy - 0.004, 0.035, 0.032, "+", function()
        self.popupMonths = math.min(t.max, self.popupMonths + t.step)
    end, self.popupMonths < t.max)

    local payment = LC:calcPayment(loan.balance, loan.apr, self.popupMonths)
    local rows = {
        { LC.t("rate"), self:pct(loan.apr) },
        { LC.t("monthlyPayment"), LC.formatMoney(payment) },
        { LC.t("totalInterest"), LC.formatMoney(math.max(0, payment * self.popupMonths - loan.balance)) }
    }
    local ry = sy - 0.05
    for _, r in ipairs(rows) do
        self:text(lx, ry, self.T_NORMAL, r[1], RenderText.ALIGN_LEFT, self.C.dim)
        self:text(x + w - 0.02, ry, self.T_NORMAL, r[2], RenderText.ALIGN_RIGHT, self.C.text)
        ry = ry - 0.028
    end

    self:text(lx, y + 0.075, self.T_SMALL, self:fit(LC.t("popLaterNote", self:months(loan.termMonths)), self.T_SMALL, w - 0.04), RenderText.ALIGN_LEFT, self.C.dim)
    self:button(lx, y + 0.02, (w - 0.05) / 2, 0.038, LC.t("popConfirm"), function()
        self:confirmPopup()
    end, true, true)
    self:button(lx + (w - 0.05) / 2 + 0.01, y + 0.02, (w - 0.05) / 2, 0.038, LC.t("popLater"), function()
        self:closePopup()
    end)
end

-- ---------------------------------------------------------------- new loan

function M:resetNewLoan()
    local terms = LC.TERMS[self.newType]
    self.newMonths = terms.def
    self.collSel = 1
    self.collScroll = 0
    self.newAmount = -1
end

-- collateral choices for the current type: { label, value, object, farmlandId, pledged }
function M:getCollateral(farmId)
    local list = {}
    if self.newType == LC.TYPE_EQUIP then
        for _, v in ipairs(LC:getOwnedVehicles(farmId)) do
            table.insert(list, { label = LC:getVehicleName(v), value = v:getSellPrice(), object = v,
                pledged = LC:isVehiclePledgedByNetId(LC:getNetId(v)) })
        end
    elseif self.newType == LC.TYPE_LAND then
        for _, f in ipairs(LC:getOwnedFarmlands(farmId)) do
            table.insert(list, { label = LC:getFarmlandName(f), value = f.price, farmlandId = f.id,
                pledged = LC:isPledged("f", tostring(f.id)) })
        end
    end
    return list
end

function M:getMaxAmount(farmId, choice)
    local farm = LC:getFarm(farmId)
    if self.newType == LC.TYPE_TERM then
        return math.max(0, LC:getUnsecuredLimit(farm.score) - LC:getUnsecuredUsed(farmId))
    end
    if choice == nil or choice.pledged then
        return 0
    end
    local ltv = LC:getSetting("ltvEquip")
    if self.newType == LC.TYPE_LAND then
        ltv = LC:getSetting("ltvLand")
    end
    return choice.value * ltv / 100
end

function M:drawNew(x, y, w, h, farmId)
    local top = y + h
    local types = { { LC.TYPE_TERM, "typeTerm" }, { LC.TYPE_EQUIP, "typeEquip" }, { LC.TYPE_LAND, "typeLand" } }
    for i, t in ipairs(types) do
        local lt = t[1]
        self:button(x + (i - 1) * 0.146, top - 0.034, 0.14, 0.034, LC.t(t[2]), function()
            if self.newType ~= lt then
                self.newType = lt
                self:resetNewLoan()
            end
        end, true, self.newType == lt)
    end
    self:text(x + 0.45, top - 0.022, self.T_SMALL, self:fit(LC.t("desc" .. self.newType), self.T_SMALL, w - 0.45),
        RenderText.ALIGN_LEFT, self.C.dim)

    -- left: collateral
    local lw = w * 0.45
    local ly = top - 0.05
    local listH = ly - y
    self:rect(x, y, lw, listH, self.C.panel)
    local list = self:getCollateral(farmId)
    local choice = nil
    if self.newType == LC.TYPE_TERM then
        self:text(x + 0.012, ly - 0.03, self.T_NORMAL, LC.t("noCollateral"), RenderText.ALIGN_LEFT, self.C.text, true)
        self:text(x + 0.012, ly - 0.06, self.T_SMALL, self:fit(LC.t("termInfo"), self.T_SMALL, lw - 0.024),
            RenderText.ALIGN_LEFT, self.C.dim)
    else
        local headKey = self.newType == LC.TYPE_EQUIP and "pickVehicle" or "pickLand"
        self:text(x + 0.012, ly - 0.025, self.T_NORMAL, LC.t(headKey), RenderText.ALIGN_LEFT, self.C.gold, true)
        if #list == 0 then
            local key = self.newType == LC.TYPE_EQUIP and "noVehicles" or "noLand"
            self:text(x + 0.012, ly - 0.055, self.T_SMALL, LC.t(key), RenderText.ALIGN_LEFT, self.C.dim)
        else
            self.collSel = LC.clamp(self.collSel, 1, #list)
            local visible = math.max(1, math.floor((listH - 0.045) / self.ROW))
            self.collVisible = visible
            self.collScroll = LC.clamp(self.collScroll, 0, math.max(0, #list - visible))
            if self.collSel <= self.collScroll then
                self.collScroll = self.collSel - 1
            elseif self.collSel > self.collScroll + visible then
                self.collScroll = self.collSel - visible
            end
            local ry = ly - 0.04
            for i = self.collScroll + 1, math.min(#list, self.collScroll + visible) do
                local item = list[i]
                ry = ry - self.ROW
                local bg = self.C.panel
                if i == self.collSel then
                    bg = self.C.sel
                elseif i % 2 == 0 then
                    bg = self.C.stripe
                end
                self:rect(x + 0.004, ry, lw - 0.008, self.ROW, bg)
                local idx = i
                self:clickArea(x, ry, lw, self.ROW, function()
                    if self.collSel ~= idx then
                        self.collSel = idx
                        self.newAmount = -1
                    end
                end)
                local c = self.C.text
                local right = LC.formatMoney(item.value)
                if item.pledged then
                    c = self.C.off
                    right = LC.t("pledged")
                end
                self:text(x + 0.012, ry + 0.009, self.T_SMALL, self:fit(item.label, self.T_SMALL, lw * 0.62), RenderText.ALIGN_LEFT, c)
                self:text(x + lw - 0.012, ry + 0.009, self.T_SMALL, right, RenderText.ALIGN_RIGHT, c)
            end
            choice = list[self.collSel]
        end
    end

    -- right: terms
    local rx = x + lw + 0.015
    local rw = w - lw - 0.015
    self:rect(rx, y, rw, listH, self.C.panel)
    local farm = LC:getFarm(farmId)
    local maxAmount = math.floor(self:getMaxAmount(farmId, choice) / 1000) * 1000
    if self.newAmount < 0 then
        self.newAmount = math.floor(maxAmount / 2 / 1000) * 1000
    end
    self.newAmount = LC.clamp(self.newAmount, 0, maxAmount)
    local terms = LC.TERMS[self.newType]
    self.newMonths = LC.clamp(self.newMonths, terms.min, terms.max)
    local apr = LC:getApr(self.newType, farm.score)
    local payment = LC:calcPayment(self.newAmount, apr, self.newMonths)
    local totalInterest = payment * self.newMonths - self.newAmount

    local ix = rx + 0.015
    local iy = ly - 0.03
    self:text(ix, iy, self.T_NORMAL, LC.t("amount"), RenderText.ALIGN_LEFT, self.C.dim)
    self:text(rx + rw - 0.015, iy, self.T_TITLE, LC.formatMoney(self.newAmount), RenderText.ALIGN_RIGHT, self.C.gold, true)
    iy = iy - 0.045
    local steps = { { "-10k", -10000 }, { "-1k", -1000 }, { "+1k", 1000 }, { "+10k", 10000 } }
    for i, s in ipairs(steps) do
        local step = s[2]
        self:button(ix + (i - 1) * 0.046, iy, 0.042, 0.03, s[1], function()
            self.newAmount = math.max(0, self.newAmount) + step
        end)
    end
    self:button(ix + 4 * 0.046, iy, 0.05, 0.03, LC.t("max"), function()
        self.newAmount = maxAmount
    end)
    iy = iy - 0.022
    self:text(ix, iy, self.T_SMALL, LC.t("maxAmount", LC.formatMoney(maxAmount)), RenderText.ALIGN_LEFT, self.C.dim)

    iy = iy - 0.045
    self:text(ix, iy + 0.008, self.T_NORMAL, LC.t("term"), RenderText.ALIGN_LEFT, self.C.dim)
    self:button(rx + rw - 0.15, iy, 0.03, 0.03, "-", function()
        self.newMonths = self.newMonths - terms.step
    end, self.newMonths > terms.min)
    self:text(rx + rw - 0.08, iy + 0.008, self.T_NORMAL, self:months(self.newMonths), RenderText.ALIGN_CENTER, self.C.text, true)
    self:button(rx + rw - 0.045, iy, 0.03, 0.03, "+", function()
        self.newMonths = self.newMonths + terms.step
    end, self.newMonths < terms.max)

    local rows = {
        { LC.t("rate"), self:pct(apr) },
        { LC.t("monthlyPayment"), LC.formatMoney(payment) },
        { LC.t("totalInterest"), LC.formatMoney(math.max(0, totalInterest)) },
        { LC.t("totalRepaid"), LC.formatMoney(payment * self.newMonths) }
    }
    iy = iy - 0.015
    for _, r in ipairs(rows) do
        iy = iy - 0.028
        self:text(ix, iy, self.T_NORMAL, r[1], RenderText.ALIGN_LEFT, self.C.dim)
        self:text(rx + rw - 0.015, iy, self.T_NORMAL, r[2], RenderText.ALIGN_RIGHT, self.C.text)
    end

    -- eligibility
    local ok, err = LC:canBorrow(farmId)
    if ok and self.newType ~= LC.TYPE_TERM and (choice == nil or choice.pledged) then
        ok, err = false, (choice == nil) and LC.CODE.ERR_COLLATERAL or LC.CODE.ERR_PLEDGED
    end
    if ok and self.newAmount < 1000 then
        ok, err = false, LC.CODE.ERR_LIMIT
    end
    if not ok then
        local msg = LC:getCodeText(err, 0, "")
        if err == LC.CODE.ERR_BLOCKED then
            msg = LC.t("statusBlocked", farm.blockedUntil - LC.month)
        end
        self:text(ix, y + 0.065, self.T_SMALL, self:fit(msg, self.T_SMALL, rw - 0.03), RenderText.ALIGN_LEFT, self.C.red)
    end
    self:button(ix, y + 0.015, rw - 0.03, 0.038, LC.t("sign"), function()
        self:signLoan(choice)
    end, ok)
    self.pendingChoice = choice
    self.canSign = ok
end

function M:signLoan(choice)
    local object, farmlandId = nil, 0
    if choice ~= nil then
        object = choice.object
        farmlandId = choice.farmlandId or 0
    end
    LC:request(1, self.newType, self.newMonths, farmlandId, self.newAmount, object)
    self.newAmount = -1
end

-- ---------------------------------------------------------------- settings

function M:getSettingRows()
    local rows = { { header = "grpPenalties" } }
    for i, def in ipairs(LC.SETTINGS) do
        if def.preset then
            table.insert(rows, { index = i, def = def })
        end
    end
    table.insert(rows, { header = "grpLending" })
    for i, def in ipairs(LC.SETTINGS) do
        if not def.preset then
            table.insert(rows, { index = i, def = def })
        end
    end
    return rows
end

function M:formatSetting(def, v)
    if def.fmt == "pct" then
        return string.format("%g%%", v)
    elseif def.fmt == "apr" then
        return string.format("%.2f%%", v)
    elseif def.fmt == "money" then
        return LC.formatMoney(v)
    elseif def.fmt == "bool" then
        return v >= 0.5 and LC.t("on") or LC.t("off")
    elseif def.fmt == "months" then
        return LC.t("monthsN", v)
    end
    return string.format("%d", v)
end

function M:changeSetting(row, dir)
    if row == nil or row.def == nil or not self:isHost() then
        return
    end
    local v = LC:getSetting(row.def.key) + dir * row.def.step
    if row.def.fmt == "bool" then
        v = 1 - LC:getSetting(row.def.key)
    end
    LC:request(3, row.index, 0, 0, v)
end

function M:drawSettings(x, y, w, h)
    local top = y + h
    local host = self:isHost()
    self:rect(x, top - 0.045, w, 0.045, self.C.panel)
    local preset = LC:getPresetName()
    self:text(x + 0.012, top - 0.028, self.T_NORMAL, LC.t("preset", LC.t("p_" .. preset)), RenderText.ALIGN_LEFT, self.C.gold, true)
    for i, p in ipairs(LC.PRESETS) do
        local idx = i
        self:button(x + 0.24 + (i - 1) * 0.09, top - 0.039, 0.085, 0.032, LC.t("p_" .. p.key), function()
            LC:request(4, idx, 0, 0, 0)
        end, host, preset == p.key)
    end
    local confirming = g_time < self.resetConfirmUntil
    local resetLabel = confirming and LC.t("resetConfirm") or LC.t("reset")
    self:button(x + w - 0.15, top - 0.039, 0.14, 0.032, resetLabel, function()
        if g_time < self.resetConfirmUntil then
            self.resetConfirmUntil = 0
            LC:request(5, 0, 0, 0, 0)
        else
            self.resetConfirmUntil = g_time + 3000
        end
    end, host, confirming)

    local rows = self:getSettingRows()
    local listTop = top - 0.055
    local noteH = host and 0 or 0.03
    local visible = math.max(1, math.floor((listTop - y - noteH) / self.ROW))
    self.setVisible = visible
    self.setRows = rows
    self.setSel = LC.clamp(self.setSel, 1, #rows)
    self.setScroll = LC.clamp(self.setScroll, 0, math.max(0, #rows - visible))
    if self.setSel <= self.setScroll then
        self.setScroll = self.setSel - 1
    elseif self.setSel > self.setScroll + visible then
        self.setScroll = self.setSel - visible
    end
    local ry = listTop
    for i = self.setScroll + 1, math.min(#rows, self.setScroll + visible) do
        local row = rows[i]
        ry = ry - self.ROW
        if row.header ~= nil then
            self:text(x + 0.008, ry + 0.008, self.T_NORMAL, LC.t(row.header), RenderText.ALIGN_LEFT, self.C.gold, true)
        else
            local bg = (i % 2 == 0) and self.C.stripe or self.C.panel
            if i == self.setSel then
                bg = self.C.sel
            end
            self:rect(x, ry, w, self.ROW - 0.002, bg)
            local idx = i
            self:clickArea(x, ry, w * 0.6, self.ROW, function()
                self.setSel = idx
            end)
            self:text(x + 0.012, ry + 0.009, self.T_SMALL, self:fit(LC.t("s_" .. row.def.key), self.T_SMALL, w * 0.55),
                RenderText.ALIGN_LEFT, self.C.text)
            local v = LC:getSetting(row.def.key)
            self:text(x + w - 0.1, ry + 0.009, self.T_SMALL, self:formatSetting(row.def, v), RenderText.ALIGN_RIGHT, self.C.text, true)
            self:button(x + w - 0.085, ry + 0.003, 0.034, self.ROW - 0.008, "-", function()
                self.setSel = idx
                self:changeSetting(row, -1)
            end, host and (row.def.fmt == "bool" and v >= 0.5 or v > row.def.min))
            self:button(x + w - 0.045, ry + 0.003, 0.034, self.ROW - 0.008, "+", function()
                self.setSel = idx
                self:changeSetting(row, 1)
            end, host and (row.def.fmt == "bool" and v < 0.5 or v < row.def.max))
        end
    end
    if not host then
        self:text(x, y + 0.008, self.T_SMALL, LC.t("hostOnly"), RenderText.ALIGN_LEFT, self.C.orange)
    end
end

-- ---------------------------------------------------------------- appearance (per player)

function M:swatch(x, y, w, h, colors, selected, callback)
    local hover = self:isInside(x, y, w, h)
    local frame = self.C.dim
    if selected then
        frame = self.C.text
    elseif hover then
        frame = self.C.accent
    end
    self:rect(x - 0.002, y - 0.003, w + 0.004, h + 0.006, frame)
    local part = h / #colors
    for i, c in ipairs(colors) do
        self:rect(x, y + h - part * i, w, part, c)
    end
    table.insert(self.buttons, { x = x, y = y, w = w, h = h, cb = callback })
end

function M:drawAppearance(x, y, w, h)
    local TH = LCTheme
    local top = y + h
    self:rect(x, y, w, h, self.C.panel)
    local lx = x + 0.015

    -- menu style
    self:text(lx, top - 0.03, self.T_NORMAL, LC.t("appStyle"), RenderText.ALIGN_LEFT, self.C.gold, true)
    self:text(lx + 0.2, top - 0.03, self.T_SMALL, LC.t(TH:getPreset(TH.preset).key), RenderText.ALIGN_LEFT, self.C.text)
    local perRow, sw, sh, gap = 7, 0.07, 0.05, 0.012
    for i = 1, #TH.PRESETS do
        local col = (i - 1) % perRow
        local row = math.floor((i - 1) / perRow)
        local sx = lx + col * (sw + gap)
        local sy = top - 0.105 - row * (sh + 0.035)
        local bg, btn, acc = TH:getSwatch(i)
        local idx = i
        self:swatch(sx, sy, sw, sh, { acc, btn, bg }, TH.preset == i, function()
            TH:set(idx, TH.accent, TH.bright)
        end)
        self:text(sx + sw / 2, sy - 0.018, self.T_SMALL * 0.9, self:fit(LC.t(TH.PRESETS[i].key), self.T_SMALL * 0.9, sw + gap),
            RenderText.ALIGN_CENTER, TH.preset == i and self.C.text or self.C.dim)
    end

    -- accent colour
    local ay = top - 0.29
    self:text(lx, ay, self.T_NORMAL, LC.t("appAccent"), RenderText.ALIGN_LEFT, self.C.gold, true)
    ay = ay - 0.05
    self:button(lx, ay, 0.07, 0.035, LC.t("appAuto"), function()
        TH:set(TH.preset, 0, TH.bright)
    end, true, TH.accent == 0)
    for i, c in ipairs(TH.ACCENTS) do
        local idx = i
        self:swatch(lx + 0.085 + (i - 1) * 0.045, ay, 0.035, 0.035, { { c[1], c[2], c[3], 1 } }, TH.accent == i, function()
            TH:set(TH.preset, idx, TH.bright)
        end)
    end

    -- brightness
    local by = ay - 0.07
    self:text(lx, by + 0.01, self.T_NORMAL, LC.t("appBright"), RenderText.ALIGN_LEFT, self.C.gold, true)
    self:button(lx + 0.2, by, 0.05, 0.032, "-10", function()
        TH:set(TH.preset, TH.accent, TH.bright - 10)
    end, TH.bright > 60)
    self:text(lx + 0.285, by + 0.01, self.T_NORMAL, string.format("%d%%", TH.bright), RenderText.ALIGN_CENTER, self.C.text, true)
    self:button(lx + 0.32, by, 0.05, 0.032, "+10", function()
        TH:set(TH.preset, TH.accent, TH.bright + 10)
    end, TH.bright < 140)

    -- reset
    self:button(lx, y + 0.05, 0.18, 0.034, LC.t("appReset"), function()
        TH:set(1, 0, 100)
    end)
    self:text(lx, y + 0.02, self.T_SMALL, LC.t("appNote"), RenderText.ALIGN_LEFT, self.C.dim)
end

-- ---------------------------------------------------------------- save and quit

function M:registerMenuActions()
    local ib = g_inputBinding
    if ib.registerActionEvent == nil then
        return
    end
    local began = false
    if ib.beginActionEventsModification ~= nil then
        ib:beginActionEventsModification("LC_MENU")
        began = true
    end
    for _, a in ipairs(self.ACTIONS) do
        if InputAction[a.action] ~= nil then
            local cmd = a.cmd
            local _, eventId = ib:registerActionEvent(InputAction[a.action], self, function()
                self:command(cmd)
            end, false, true, false, true)
            if eventId ~= nil and ib.setActionEventTextVisibility ~= nil then
                ib:setActionEventTextVisibility(eventId, false)
            end
        end
    end
    if began and ib.endActionEventsModification ~= nil then
        ib:endActionEventsModification()
    end
end

-- only the host (or a single player) can save
function M:canSave()
    return LC:isServer() and g_currentMission:getIsClient()
end

function M:isConfirming(cmd)
    return self.confirmCmd == cmd and g_time < self.confirmUntil
end

-- a button click or key press; quitting needs a second press within 3 seconds
function M:command(cmd)
    -- the same press can arrive as both the action and the raw key
    if self.lastCmd == cmd and g_time - (self.lastCmdTime or 0) < 250 then
        return
    end
    self.lastCmd, self.lastCmdTime = cmd, g_time
    -- quitting or saving again while a save is still being written would leave the savegame half saved
    if self:isSaving() then
        LC:showNotification(LC.CODE.SAVE_WAIT, 0, "")
        return
    end
    if cmd == "save" then
        if self:canSave() then
            self.pendingCmd = "save"
        end
        return
    end
    if self:isConfirming(cmd) then
        self.confirmCmd = nil
        self:close()
        self.pendingCmd = cmd
    else
        self.confirmCmd = cmd
        self.confirmUntil = g_time + 3000
    end
end

function M:onSaveStarted()
    self.saveBusySince = g_time
end

function M:isSaving()
    return self.saveBusySince ~= nil
end

function M:closeSavePopup()
    if g_gui ~= nil and g_gui.closeDialogByName ~= nil then
        g_gui:closeDialogByName("MessageDialog")
    end
end

-- the game reports the save as finished: only now is everything on disk
function M:onSaveComplete(errorCode)
    local ours = self.ownSave
    self.saveBusySince = nil
    self.ownSave = false
    if not ours then
        return
    end
    self:closeSavePopup()
    local ok = Savegame == nil or Savegame.ERROR_OK == nil or errorCode == Savegame.ERROR_OK
    if ok then
        Logging.info("[LoansAndCredit] save complete")
        LC:showNotification(LC.CODE.SAVED, 0, "")
    else
        Logging.warning("[LoansAndCredit] save failed, error code %s", tostring(errorCode))
        LC:showNotification(LC.CODE.SAVE_FAILED, 0, "")
    end
end

-- safety net only: if the game never reports the save as finished, stop waiting after a while
function M:updateSaveWatch()
    if self.saveBusySince == nil then
        return
    end
    local limit = 180000
    if not LC.saveCompleteHooked then
        limit = 20000
    end
    if g_time - self.saveBusySince > limit then
        Logging.warning("[LoansAndCredit] no save-complete signal after %d s, no longer waiting", limit / 1000)
        local ours = self.ownSave
        self.saveBusySince = nil
        self.ownSave = false
        if ours then
            self:closeSavePopup()
        end
    end
end

-- runs from update(), outside the menu's drawing and input handling
function M:runCommand(cmd)
    local mission = g_currentMission
    if cmd == "save" then
        if mission.startSaveCurrentGame ~= nil then
            -- the game shows its "saving" popup but only its own pause menu closes it again,
            -- so it is closed in onSaveComplete once the save has really finished
            self.ownSave = true
            self.saveBusySince = g_time
            mission:startSaveCurrentGame()
        elseif mission.saveSavegame ~= nil then
            mission:saveSavegame()
            LC:showNotification(LC.CODE.SAVED, 0, "")
        else
            Logging.warning("[LoansAndCredit] no save function found")
        end
    elseif cmd == "quitMenu" then
        if OnInGameMenuMenu ~= nil then
            OnInGameMenuMenu()
        elseif g_gui ~= nil then
            Logging.warning("[LoansAndCredit] quit-to-menu function not found, opening the game menu instead")
            g_gui:showGui("InGameMenu")
        end
    elseif cmd == "quitDesktop" then
        if requestExit ~= nil then
            requestExit()
        elseif doExit ~= nil then
            doExit()
        else
            Logging.warning("[LoansAndCredit] quit-to-desktop function not found")
        end
    end
end

-- ---------------------------------------------------------------- input

function M:isCtrl()
    if Input.isKeyPressed == nil then
        return false
    end
    return Input.isKeyPressed(Input.KEY_lctrl) or Input.isKeyPressed(Input.KEY_rctrl)
end

function M:isShift()
    if Input.isKeyPressed == nil then
        return false
    end
    return Input.isKeyPressed(Input.KEY_lshift) or Input.isKeyPressed(Input.KEY_rshift)
end

function M:keyEvent(unicode, sym, modifier, isDown)
    if not isDown then
        return
    end
    -- Ctrl+B fallback: also opens the menu in vehicles or if the action isn't registered
    if sym == Input.KEY_b and self:isCtrl() then
        self:toggle()
        return
    end
    if not self.isOpen then
        return
    end
    if self.popupLoanId ~= nil then
        local t = LC.ROLL_TERMS
        if sym == Input.KEY_esc then
            self:closePopup()
        elseif sym == Input.KEY_left or sym == Input.KEY_down then
            self.popupMonths = math.max(t.min, self.popupMonths - t.step)
        elseif sym == Input.KEY_right or sym == Input.KEY_up then
            self.popupMonths = math.min(t.max, self.popupMonths + t.step)
        elseif sym == Input.KEY_return or sym == Input.KEY_KP_enter then
            self:confirmPopup()
        end
        return
    end
    if self:isCtrl() then
        for _, a in ipairs(self.ACTIONS) do
            if Input[a.key] ~= nil and sym == Input[a.key] then
                self:command(a.cmd)
                return
            end
        end
    end
    if sym == Input.KEY_esc then
        self:close()
    elseif sym == Input.KEY_tab then
        local dir = self:isShift() and -1 or 1
        self.tab = (self.tab - 1 + dir) % #self.TABS + 1
    elseif sym >= Input.KEY_1 and sym <= Input.KEY_5 then
        self.tab = sym - Input.KEY_1 + 1
    elseif sym == Input.KEY_up or sym == Input.KEY_down then
        self:moveSelection(sym == Input.KEY_up and -1 or 1)
    elseif sym == Input.KEY_left or sym == Input.KEY_right then
        self:adjust(sym == Input.KEY_left and -1 or 1)
    elseif (sym == Input.KEY_return or sym == Input.KEY_KP_enter) and self.tab == 3 and self.canSign then
        self:signLoan(self.pendingChoice)
    end
end

function M:moveSelection(dir)
    if self.tab == 2 then
        self.loanSel = self.loanSel + dir
    elseif self.tab == 3 then
        self.collSel = math.max(1, self.collSel + dir)
        self.newAmount = -1
    elseif self.tab == 4 and self.setRows ~= nil then
        local i = self.setSel + dir
        -- skip group headers
        while self.setRows[i] ~= nil and self.setRows[i].header ~= nil do
            i = i + dir
        end
        if self.setRows[i] ~= nil then
            self.setSel = i
        end
    end
end

function M:adjust(dir)
    local big = self:isShift()
    if self.tab == 2 then
        self.extraAmount = self.extraAmount + dir * (big and 10000 or 1000)
    elseif self.tab == 3 then
        self.newAmount = math.max(0, self.newAmount) + dir * (big and 10000 or 1000)
    elseif self.tab == 4 and self.setRows ~= nil then
        self:changeSetting(self.setRows[self.setSel], dir)
    end
end

function M:mouseEvent(posX, posY, isDown, isUp, button)
    if not self.isOpen then
        return
    end
    self.mx, self.my = posX, posY
    if not isDown then
        return
    end
    if button == Input.MOUSE_BUTTON_LEFT then
        for i = #self.buttons, 1, -1 do
            local b = self.buttons[i]
            if posX >= b.x and posX <= b.x + b.w and posY >= b.y and posY <= b.y + b.h then
                b.cb()
                return
            end
        end
    elseif button == Input.MOUSE_BUTTON_WHEEL_UP or button == Input.MOUSE_BUTTON_WHEEL_DOWN then
        local dir = button == Input.MOUSE_BUTTON_WHEEL_UP and -1 or 1
        if self.tab == 2 then
            self.loanScroll = self.loanScroll + dir
            self.loanSel = LC.clamp(self.loanSel, self.loanScroll + 1, self.loanScroll + 9)
        elseif self.tab == 3 then
            self.collScroll = math.max(0, self.collScroll + dir)
            local vis = self.collVisible or 1
            self.collSel = LC.clamp(self.collSel, self.collScroll + 1, self.collScroll + vis)
        elseif self.tab == 4 then
            self.setScroll = math.max(0, self.setScroll + dir)
            local vis = self.setVisible or 1
            self.setSel = LC.clamp(self.setSel, self.setScroll + 1, self.setScroll + vis)
        end
    end
end
