-- Loans And Credit for Farming Simulator 25
-- Real loans (term, equipment, land mortgage), a credit score that sets your interest rate,
-- monthly payments, and adjustable penalties for missed payments.
--
-- DEDICATED SERVERS: settings can't be changed in-game there. Edit the "def" values in
-- LoansAndCredit.SETTINGS below, or edit loansAndCredit.xml inside the savegame folder.

LoansAndCredit = {}
LoansAndCredit.modName = g_currentModName
LoansAndCredit.modDir = g_currentModDirectory
local LC = LoansAndCredit

LC.TYPE_TERM = 1
LC.TYPE_EQUIP = 2
LC.TYPE_LAND = 3
LC.MAX_HISTORY = 30
LC.MIN_SCORE = 300
LC.MAX_SCORE = 850

-- loan term ranges in months (one in-game period = one month)
LC.TERMS = {
    [1] = { min = 6, max = 60, step = 6, def = 36 },
    [2] = { min = 12, max = 84, step = 6, def = 48 },
    [3] = { min = 60, max = 240, step = 12, def = 120 }
}
-- term choices for an old base-game loan moved into the mod
LC.ROLL_TERMS = { min = 12, max = 120, step = 12 }

-- history / notification codes
LC.CODE = {
    TAKEN = 1, PAYMENTS = 2, MISSED = 3, DEFAULT = 4, PAIDOFF = 5, REPO = 6, SEIZE = 7,
    CONVERTED = 8, BASE_BLOCKED = 9, EXTRA = 11, OVERDUE_PAID = 12, ROLLED = 13, TERM_SET = 14, SAVED = 15, SAVE_FAILED = 16, SAVE_WAIT = 17,
    ERR_SCORE = 20, ERR_BLOCKED = 21, ERR_LIMIT = 22, ERR_COLLATERAL = 23, ERR_PLEDGED = 24,
    ERR_MONEY = 25, ERR_MAXLOANS = 26, ERR_INVALID = 27, ERR_HOST = 28
}

-- Settings. "preset = true" values are set by the penalty presets.
-- fmt: pct (shown with %), apr (shown with % and 2 decimals), money, int, bool, months
LC.SETTINGS = {
    { key = "lateFeePct", def = 10, min = 0, max = 50, step = 1, fmt = "pct", preset = true },
    { key = "missHit", def = 30, min = 0, max = 100, step = 5, fmt = "int", preset = true },
    { key = "missesToDefault", def = 3, min = 1, max = 12, step = 1, fmt = "int", preset = true },
    { key = "defaultHit", def = 100, min = 0, max = 300, step = 10, fmt = "int", preset = true },
    { key = "blockMonths", def = 12, min = 0, max = 60, step = 3, fmt = "months", preset = true },
    { key = "recoveryPct", def = 70, min = 10, max = 100, step = 5, fmt = "pct", preset = true },
    { key = "repossess", def = 1, min = 0, max = 1, step = 1, fmt = "bool", preset = true },
    { key = "aprTerm", def = 7.0, min = 0.5, max = 25, step = 0.25, fmt = "apr" },
    { key = "aprEquip", def = 5.0, min = 0.5, max = 25, step = 0.25, fmt = "apr" },
    { key = "aprLand", def = 3.5, min = 0.5, max = 25, step = 0.25, fmt = "apr" },
    { key = "scoreSpread", def = 0.5, min = 0, max = 2, step = 0.1, fmt = "apr" },
    { key = "termLimit", def = 250000, min = 25000, max = 5000000, step = 25000, fmt = "money" },
    { key = "ltvEquip", def = 80, min = 10, max = 100, step = 5, fmt = "pct" },
    { key = "ltvLand", def = 70, min = 10, max = 100, step = 5, fmt = "pct" },
    { key = "minScore", def = 500, min = 300, max = 750, step = 10, fmt = "int" },
    { key = "startScore", def = 650, min = 300, max = 850, step = 10, fmt = "int" },
    { key = "onTimeGain", def = 2, min = 0, max = 10, step = 1, fmt = "int" },
    { key = "paidOffGain", def = 15, min = 0, max = 50, step = 5, fmt = "int" },
    { key = "convertApr", def = 2.0, min = 0, max = 10, step = 0.25, fmt = "apr" },
    { key = "prepayFeePct", def = 1, min = 0, max = 10, step = 0.5, fmt = "pct" },
    { key = "maxLoans", def = 10, min = 1, max = 30, step = 1, fmt = "int" },
    { key = "blockBaseLoan", def = 1, min = 0, max = 1, step = 1, fmt = "bool" },
    { key = "rollBaseLoan", def = 1, min = 0, max = 1, step = 1, fmt = "bool" },
    { key = "rollMonths", def = 60, min = 12, max = 120, step = 12, fmt = "months" }
}

LC.PRESETS = {
    { key = "lenient", values = { lateFeePct = 5, missHit = 15, missesToDefault = 5, defaultHit = 60,
        blockMonths = 6, recoveryPct = 85, repossess = 1 } },
    { key = "normal", values = { lateFeePct = 10, missHit = 30, missesToDefault = 3, defaultHit = 100,
        blockMonths = 12, recoveryPct = 70, repossess = 1 } },
    { key = "strict", values = { lateFeePct = 20, missHit = 50, missesToDefault = 2, defaultHit = 150,
        blockMonths = 24, recoveryPct = 55, repossess = 1 } }
}

LC.settingIndex = {}
for i, def in ipairs(LC.SETTINGS) do
    LC.settingIndex[def.key] = i
end

LC.settings = {}
LC.farms = {}
LC.loans = {}
LC.month = 0
LC.nextId = 1

-- ---------------------------------------------------------------- helpers

function LC.t(key, ...)
    local full = "lc_" .. key
    local text = full
    if g_i18n ~= nil and g_i18n:hasText(full) then
        text = g_i18n:getText(full)
    end
    if select("#", ...) > 0 then
        return string.format(text, ...)
    end
    return text
end

function LC.formatMoney(amount)
    if g_i18n ~= nil and g_i18n.formatMoney ~= nil then
        return g_i18n:formatMoney(amount, 0, true, true)
    end
    return string.format("$%d", math.floor(amount + 0.5))
end

function LC.clamp(v, a, b)
    if v < a then
        return a
    end
    if v > b then
        return b
    end
    return v
end

function LC:isServer()
    return g_currentMission ~= nil and g_currentMission:getIsServer()
end

function LC:getSetting(key)
    local v = self.settings[key]
    if v == nil then
        local def = self.SETTINGS[self.settingIndex[key]]
        return def.def
    end
    return v
end

function LC:resetSettings()
    for _, def in ipairs(self.SETTINGS) do
        self.settings[def.key] = def.def
    end
end

function LC:getPresetName()
    for _, preset in ipairs(self.PRESETS) do
        local match = true
        for k, v in pairs(preset.values) do
            if math.abs(self:getSetting(k) - v) > 0.001 then
                match = false
            end
        end
        if match then
            return preset.key
        end
    end
    return "custom"
end

function LC:getFarm(farmId)
    local farm = self.farms[farmId]
    if farm == nil then
        farm = { id = farmId, score = self:getSetting("startScore"), blockedUntil = 0, history = {} }
        self.farms[farmId] = farm
    end
    return farm
end

function LC:addHistory(farmId, code, amount, label)
    local farm = self:getFarm(farmId)
    table.insert(farm.history, 1, { month = self.month, code = code, amount = amount or 0, label = label or "" })
    while #farm.history > self.MAX_HISTORY do
        table.remove(farm.history)
    end
end

function LC:changeScore(farmId, delta)
    local farm = self:getFarm(farmId)
    farm.score = LC.clamp(math.floor(farm.score + delta + 0.5), self.MIN_SCORE, self.MAX_SCORE)
end

function LC:getRatingKey(score)
    if score >= 800 then
        return "excellent"
    elseif score >= 740 then
        return "veryGood"
    elseif score >= 670 then
        return "good"
    elseif score >= 580 then
        return "fair"
    end
    return "poor"
end

function LC:getApr(loanType, score)
    local base = self:getSetting("aprTerm")
    if loanType == self.TYPE_EQUIP then
        base = self:getSetting("aprEquip")
    elseif loanType == self.TYPE_LAND then
        base = self:getSetting("aprLand")
    end
    -- each 50 points below 700 adds the spread, each 50 above takes it off
    local spread = (700 - score) / 50 * self:getSetting("scoreSpread")
    return math.max(0.25, base + spread)
end

function LC:calcPayment(amount, apr, months)
    if months <= 0 then
        return amount
    end
    local r = apr / 100 / 12
    if r <= 0 then
        return amount / months
    end
    return amount * r / (1 - (1 + r) ^ (-months))
end

function LC:getUnsecuredLimit(score)
    local factor = LC.clamp((score - 500) / 200, 0, 2)
    return self:getSetting("termLimit") * factor
end

function LC:getLoansForFarm(farmId)
    local list = {}
    for _, loan in ipairs(self.loans) do
        if loan.farmId == farmId then
            table.insert(list, loan)
        end
    end
    return list
end

function LC:getUnsecuredUsed(farmId)
    local used = 0
    for _, loan in ipairs(self.loans) do
        if loan.farmId == farmId and loan.type == self.TYPE_TERM then
            used = used + loan.balance
        end
    end
    return used
end

function LC:getLoanById(id)
    for i, loan in ipairs(self.loans) do
        if loan.id == id then
            return loan, i
        end
    end
    return nil, nil
end

function LC:removeLoan(loan)
    local _, idx = self:getLoanById(loan.id)
    if idx ~= nil then
        table.remove(self.loans, idx)
    end
end

-- returns true, or false and an error code
function LC:canBorrow(farmId)
    local farm = self:getFarm(farmId)
    if farm.blockedUntil > self.month then
        return false, self.CODE.ERR_BLOCKED
    end
    if farm.score < self:getSetting("minScore") then
        return false, self.CODE.ERR_SCORE
    end
    if #self:getLoansForFarm(farmId) >= self:getSetting("maxLoans") then
        return false, self.CODE.ERR_MAXLOANS
    end
    return true, nil
end

-- ---------------------------------------------------------------- money

function LC:getMoneyType(name)
    if MoneyType ~= nil and MoneyType[name] ~= nil then
        return MoneyType[name]
    end
    if MoneyType ~= nil then
        return MoneyType.OTHER
    end
    return nil
end

function LC:getFarmMoney(farmId)
    if g_farmManager ~= nil then
        local farm = g_farmManager:getFarmById(farmId)
        if farm ~= nil and farm.money ~= nil then
            return farm.money
        end
    end
    return 0
end

function LC:addMoney(amount, farmId, typeName)
    if math.abs(amount) < 0.5 then
        return
    end
    g_currentMission:addMoney(amount, farmId, self:getMoneyType(typeName), true, true)
end

-- ---------------------------------------------------------------- collateral: vehicles

function LC:getVehicleList()
    local mission = g_currentMission
    if mission.vehicleSystem ~= nil and mission.vehicleSystem.vehicles ~= nil then
        return mission.vehicleSystem.vehicles
    end
    if mission.vehicles ~= nil then
        return mission.vehicles
    end
    return {}
end

function LC:isVehicleOwnedBy(vehicle, farmId)
    if vehicle == nil or vehicle.getOwnerFarmId == nil or vehicle:getOwnerFarmId() ~= farmId then
        return false
    end
    if vehicle.spec_enterable == nil and vehicle.spec_attachable == nil then
        return false
    end
    if vehicle.getSellPrice == nil or vehicle:getSellPrice() <= 0 then
        return false
    end
    -- leased and mission vehicles can't be pledged
    if VehiclePropertyState ~= nil and vehicle.propertyState ~= nil then
        return vehicle.propertyState == VehiclePropertyState.OWNED
    end
    if Vehicle.PROPERTY_STATE_OWNED ~= nil and vehicle.propertyState ~= nil then
        return vehicle.propertyState == Vehicle.PROPERTY_STATE_OWNED
    end
    return true
end

function LC:getVehicleUid(vehicle)
    if vehicle.uniqueId ~= nil then
        return tostring(vehicle.uniqueId)
    end
    if vehicle.id ~= nil then
        return "id" .. tostring(vehicle.id)
    end
    return ""
end

function LC:findVehicleByUid(uid)
    for _, vehicle in pairs(self:getVehicleList()) do
        if self:getVehicleUid(vehicle) == uid then
            return vehicle
        end
    end
    return nil
end

function LC:getNetId(object)
    if object ~= nil and NetworkUtil ~= nil and NetworkUtil.getObjectId ~= nil then
        return NetworkUtil.getObjectId(object) or 0
    end
    return 0
end

function LC:getVehicleName(vehicle)
    if vehicle.getFullName ~= nil then
        return vehicle:getFullName()
    end
    return tostring(vehicle.typeName or "Vehicle")
end

function LC:getOwnedVehicles(farmId)
    local list = {}
    for _, vehicle in pairs(self:getVehicleList()) do
        if self:isVehicleOwnedBy(vehicle, farmId) then
            table.insert(list, vehicle)
        end
    end
    table.sort(list, function(a, b)
        return a:getSellPrice() > b:getSellPrice()
    end)
    return list
end

-- ---------------------------------------------------------------- collateral: farmland

function LC:getFarmlandOwner(farmlandId)
    if g_farmlandManager ~= nil then
        return g_farmlandManager:getFarmlandOwner(farmlandId)
    end
    return 0
end

function LC:getFarmlandById(farmlandId)
    if g_farmlandManager ~= nil then
        return g_farmlandManager:getFarmlandById(farmlandId)
    end
    return nil
end

function LC:getOwnedFarmlands(farmId)
    local list = {}
    if g_farmlandManager == nil then
        return list
    end
    local all = g_farmlandManager.farmlands
    if g_farmlandManager.getFarmlands ~= nil then
        all = g_farmlandManager:getFarmlands()
    end
    for _, farmland in pairs(all or {}) do
        if farmland.id ~= nil and farmland.price ~= nil and farmland.price > 0
            and self:getFarmlandOwner(farmland.id) == farmId then
            table.insert(list, farmland)
        end
    end
    table.sort(list, function(a, b)
        return a.id < b.id
    end)
    return list
end

function LC:getFarmlandName(farmland)
    return LC.t("farmlandName", farmland.id)
end

function LC:isPledged(kind, collId)
    for _, loan in ipairs(self.loans) do
        if loan.collKind == kind and loan.collId == collId then
            return true
        end
    end
    return false
end

function LC:isVehiclePledgedByNetId(netId)
    if netId == 0 then
        return false
    end
    for _, loan in ipairs(self.loans) do
        if loan.collKind == "v" and loan.collNetId == netId then
            return true
        end
    end
    return false
end

-- true while the collateral is still owned by the farm
function LC:isCollateralHeld(loan)
    if loan.collKind == "v" then
        local vehicle = self:findVehicleByUid(loan.collId)
        return vehicle ~= nil and self:isVehicleOwnedBy(vehicle, loan.farmId)
    elseif loan.collKind == "f" then
        local id = tonumber(loan.collId)
        return id ~= nil and self:getFarmlandOwner(id) == loan.farmId
    end
    return true
end

-- refreshes the network id of pledged vehicles so clients can mark them in the list
function LC:refreshNetIds()
    for _, loan in ipairs(self.loans) do
        loan.collNetId = 0
        if loan.collKind == "v" then
            local vehicle = self:findVehicleByUid(loan.collId)
            if vehicle ~= nil then
                loan.collNetId = self:getNetId(vehicle)
            end
        end
    end
end

-- ---------------------------------------------------------------- server actions

function LC:serverTakeLoan(farmId, loanType, vehicle, farmlandId, amount, months)
    local terms = self.TERMS[loanType]
    if terms == nil or farmId == nil or farmId <= 0 then
        return false, self.CODE.ERR_INVALID
    end
    local ok, err = self:canBorrow(farmId)
    if not ok then
        return false, err
    end
    months = LC.clamp(math.floor(months), terms.min, terms.max)
    amount = math.floor(amount)
    if amount < 1000 then
        return false, self.CODE.ERR_INVALID
    end
    local farm = self:getFarm(farmId)
    local maxAmount = 0
    local collKind, collId, collLabel = "", "", ""
    if loanType == self.TYPE_TERM then
        maxAmount = self:getUnsecuredLimit(farm.score) - self:getUnsecuredUsed(farmId)
    elseif loanType == self.TYPE_EQUIP then
        if not self:isVehicleOwnedBy(vehicle, farmId) then
            return false, self.CODE.ERR_COLLATERAL
        end
        collKind, collId, collLabel = "v", self:getVehicleUid(vehicle), self:getVehicleName(vehicle)
        maxAmount = vehicle:getSellPrice() * self:getSetting("ltvEquip") / 100
    else
        local farmland = self:getFarmlandById(farmlandId)
        if farmland == nil or self:getFarmlandOwner(farmlandId) ~= farmId then
            return false, self.CODE.ERR_COLLATERAL
        end
        collKind, collId, collLabel = "f", tostring(farmlandId), self:getFarmlandName(farmland)
        maxAmount = farmland.price * self:getSetting("ltvLand") / 100
    end
    if collKind ~= "" and self:isPledged(collKind, collId) then
        return false, self.CODE.ERR_PLEDGED
    end
    if amount > maxAmount + 1 then
        return false, self.CODE.ERR_LIMIT
    end
    local apr = self:getApr(loanType, farm.score)
    local loan = {
        id = self.nextId, farmId = farmId, type = loanType, principal = amount, balance = amount,
        apr = apr, termMonths = months, paymentsLeft = months, payment = self:calcPayment(amount, apr, months),
        arrears = 0, missed = 0, totalMissed = 0, unpaidInterest = 0, collKind = collKind, collId = collId,
        collLabel = collLabel, collNetId = 0, startMonth = self.month
    }
    self.nextId = self.nextId + 1
    table.insert(self.loans, loan)
    self:addMoney(amount, farmId, "LOAN")
    self:addHistory(farmId, self.CODE.TAKEN, amount, collLabel)
    self:syncAll()
    return true, self.CODE.TAKEN, amount
end

-- applies money paid to a loan, interest first. Returns the part that went to interest.
function LC:applyPayment(loan, amount)
    local interestPart = math.min(amount, loan.unpaidInterest)
    loan.unpaidInterest = loan.unpaidInterest - interestPart
    loan.balance = math.max(0, loan.balance - amount)
    self:addMoney(-interestPart, loan.farmId, "LOAN_INTEREST")
    self:addMoney(-(amount - interestPart), loan.farmId, "LOAN")
end

function LC:finishLoan(loan)
    self:changeScore(loan.farmId, self:getSetting("paidOffGain"))
    self:addHistory(loan.farmId, self.CODE.PAIDOFF, loan.principal, loan.collLabel)
    self:notifyFarm(loan.farmId, self.CODE.PAIDOFF, loan.principal, loan.collLabel)
    self:removeLoan(loan)
end

-- mode 1 = pay overdue, 2 = pay extra amount, 3 = pay off
function LC:serverPay(farmId, loanId, mode, amount)
    local loan = self:getLoanById(loanId)
    if loan == nil or loan.farmId ~= farmId then
        return false, self.CODE.ERR_INVALID
    end
    local money = self:getFarmMoney(farmId)
    if mode == 1 then
        if loan.arrears <= 0 then
            return false, self.CODE.ERR_INVALID
        end
        local due = math.min(loan.arrears, loan.balance)
        if money < due then
            return false, self.CODE.ERR_MONEY
        end
        self:applyPayment(loan, due)
        loan.arrears = 0
        loan.missed = 0
        self:addHistory(farmId, self.CODE.OVERDUE_PAID, due, loan.collLabel)
        if loan.balance <= 0.5 then
            self:finishLoan(loan)
        end
        self:syncAll()
        return true, self.CODE.OVERDUE_PAID, due
    elseif mode == 2 then
        amount = math.min(math.floor(amount), loan.balance)
        if amount <= 0 then
            return false, self.CODE.ERR_INVALID
        end
        if money < amount then
            return false, self.CODE.ERR_MONEY
        end
        self:applyPayment(loan, amount)
        loan.arrears = math.max(0, loan.arrears - amount)
        if loan.arrears <= 0 then
            loan.missed = 0
        end
        self:addHistory(farmId, self.CODE.EXTRA, amount, loan.collLabel)
        if loan.balance <= 0.5 then
            self:finishLoan(loan)
        end
        self:syncAll()
        return true, self.CODE.EXTRA, amount
    elseif mode == 3 then
        local total, fee = self:getPayoffAmount(loan)
        if money < total then
            return false, self.CODE.ERR_MONEY
        end
        self:applyPayment(loan, loan.balance)
        self:addMoney(-fee, farmId, "OTHER")
        self:finishLoan(loan)
        self:syncAll()
        return true, self.CODE.PAIDOFF, total
    end
    return false, self.CODE.ERR_INVALID
end

function LC:getPayoffAmount(loan)
    local fee = loan.balance * self:getSetting("prepayFeePct") / 100
    return loan.balance + fee, fee
end

-- ---------------------------------------------------------------- monthly processing

function LC:onPeriodChanged()
    if not self:isServer() then
        return
    end
    self.month = self.month + 1
    local collected = {}
    -- copy, because loans can be removed while processing
    local list = {}
    for _, loan in ipairs(self.loans) do
        table.insert(list, loan)
    end
    for _, loan in ipairs(list) do
        local paid = self:processLoan(loan)
        if paid > 0 then
            collected[loan.farmId] = (collected[loan.farmId] or 0) + paid
        end
    end
    for farmId, amount in pairs(collected) do
        self:addHistory(farmId, self.CODE.PAYMENTS, amount, "")
        self:notifyFarm(farmId, self.CODE.PAYMENTS, amount, "")
    end
    self:syncAll()
end

-- returns the amount collected this month
function LC:processLoan(loan)
    -- collateral sold or lost: the loan becomes an unsecured term loan at a higher rate
    if loan.collKind ~= "" and not self:isCollateralHeld(loan) then
        self:addHistory(loan.farmId, self.CODE.CONVERTED, loan.balance, loan.collLabel)
        self:notifyFarm(loan.farmId, self.CODE.CONVERTED, loan.balance, loan.collLabel)
        loan.type = self.TYPE_TERM
        loan.apr = loan.apr + self:getSetting("convertApr")
        loan.collKind, loan.collId = "", ""
        loan.collLabel = LC.t("formerly", loan.collLabel)
    end

    local interest = loan.balance * loan.apr / 100 / 12
    loan.balance = loan.balance + interest
    loan.unpaidInterest = loan.unpaidInterest + interest

    local scheduled = math.min(loan.payment, loan.balance)
    if loan.paymentsLeft <= 1 then
        scheduled = loan.balance
    end
    local due = math.min(scheduled + loan.arrears, loan.balance)
    local money = self:getFarmMoney(loan.farmId)

    if money >= due then
        self:applyPayment(loan, due)
        loan.arrears = 0
        loan.missed = 0
        loan.paymentsLeft = math.max(0, loan.paymentsLeft - 1)
        self:changeScore(loan.farmId, self:getSetting("onTimeGain"))
        if loan.balance <= 0.5 then
            self:finishLoan(loan)
        end
        return due
    end

    -- missed payment
    local fee = scheduled * self:getSetting("lateFeePct") / 100
    loan.balance = loan.balance + fee
    loan.unpaidInterest = loan.unpaidInterest + fee
    loan.arrears = loan.arrears + scheduled + fee
    loan.missed = loan.missed + 1
    loan.totalMissed = loan.totalMissed + 1
    loan.paymentsLeft = math.max(0, loan.paymentsLeft - 1)
    self:changeScore(loan.farmId, -self:getSetting("missHit"))
    self:addHistory(loan.farmId, self.CODE.MISSED, scheduled + fee, loan.collLabel)

    if loan.missed >= self:getSetting("missesToDefault") then
        self:defaultLoan(loan)
    else
        local left = self:getSetting("missesToDefault") - loan.missed
        self:notifyFarm(loan.farmId, self.CODE.MISSED, scheduled + fee, tostring(left))
    end
    return 0
end

function LC:defaultLoan(loan)
    local farmId = loan.farmId
    local recovered = 0
    local recovery = self:getSetting("recoveryPct") / 100
    if self:getSetting("repossess") == 1 then
        if loan.collKind == "v" then
            local vehicle = self:findVehicleByUid(loan.collId)
            if vehicle ~= nil and self:isVehicleOwnedBy(vehicle, farmId) then
                recovered = vehicle:getSellPrice() * recovery
                self:removeVehicle(vehicle)
                self:addHistory(farmId, self.CODE.REPO, recovered, loan.collLabel)
                self:notifyFarm(farmId, self.CODE.REPO, recovered, loan.collLabel)
            end
        elseif loan.collKind == "f" then
            local id = tonumber(loan.collId)
            local farmland = self:getFarmlandById(id)
            if farmland ~= nil and self:getFarmlandOwner(id) == farmId then
                recovered = farmland.price * recovery
                self:seizeFarmland(id)
                self:addHistory(farmId, self.CODE.SEIZE, recovered, loan.collLabel)
                self:notifyFarm(farmId, self.CODE.SEIZE, recovered, loan.collLabel)
            end
        end
    end
    -- whatever the collateral didn't cover is taken from the account (it can go negative);
    -- if the collateral was worth more than the debt, the surplus is paid back
    local remaining = loan.balance - recovered
    if remaining > 0 then
        self:addMoney(-remaining, farmId, "LOAN")
    elseif remaining < 0 then
        self:addMoney(-remaining, farmId, "OTHER")
    end
    self:changeScore(farmId, -self:getSetting("defaultHit"))
    local farm = self:getFarm(farmId)
    farm.blockedUntil = math.max(farm.blockedUntil, self.month + self:getSetting("blockMonths"))
    self:addHistory(farmId, self.CODE.DEFAULT, math.max(0, remaining), loan.collLabel)
    self:notifyFarm(farmId, self.CODE.DEFAULT, math.max(0, remaining), loan.collLabel)
    self:removeLoan(loan)
end

function LC:removeVehicle(vehicle)
    local mission = g_currentMission
    if mission.vehicleSystem ~= nil and mission.vehicleSystem.removeVehicle ~= nil then
        mission.vehicleSystem:removeVehicle(vehicle)
    elseif mission.removeVehicle ~= nil then
        mission:removeVehicle(vehicle)
    elseif vehicle.delete ~= nil then
        vehicle:delete()
    end
end

function LC:seizeFarmland(farmlandId)
    local noOwner = 0
    if FarmlandManager ~= nil and FarmlandManager.NO_OWNER_FARM_ID ~= nil then
        noOwner = FarmlandManager.NO_OWNER_FARM_ID
    end
    g_farmlandManager:setLandOwnership(farmlandId, noOwner)
    if g_server ~= nil and FarmlandStateEvent ~= nil and FarmlandStateEvent.new ~= nil then
        g_server:broadcastEvent(FarmlandStateEvent.new(farmlandId, noOwner, 0), false)
    end
end

-- ---------------------------------------------------------------- settings (host only)

function LC:serverSetSetting(index, value)
    local def = self.SETTINGS[index]
    if def == nil then
        return
    end
    value = LC.clamp(value, def.min, def.max)
    value = math.floor(value / def.step + 0.5) * def.step
    self.settings[def.key] = value
    self:syncAll()
end

function LC:serverApplyPreset(index)
    local preset = self.PRESETS[index]
    if preset == nil then
        return
    end
    for k, v in pairs(preset.values) do
        self.settings[k] = v
    end
    self:syncAll()
end

function LC:serverResetDefaults()
    self:resetSettings()
    self:syncAll()
end

-- ---------------------------------------------------------------- client -> server

-- action: 1 take loan, 2 pay, 3 set setting, 4 preset, 5 reset defaults
function LC:request(action, a, b, c, f, object)
    local farmId = g_currentMission:getFarmId()
    if self:isServer() then
        self:handleRequest(nil, farmId, action, a, b, c, f, object)
    else
        g_client:getServerConnection():sendEvent(LCRequestEvent.new(farmId, action, a, b, c, f, object))
    end
end

function LC:getConnectionFarmId(connection, claimed)
    if connection == nil then
        return claimed
    end
    local mission = g_currentMission
    if mission.userManager ~= nil and mission.userManager.getUserByConnection ~= nil then
        local user = mission.userManager:getUserByConnection(connection)
        if user ~= nil and user.getFarmId ~= nil then
            return user:getFarmId()
        end
        if user ~= nil and user.getId ~= nil and g_farmManager.getFarmByUserId ~= nil then
            local farm = g_farmManager:getFarmByUserId(user:getId())
            if farm ~= nil then
                return farm.farmId
            end
        end
    end
    return claimed
end

-- connection is nil when the host makes the request
function LC:handleRequest(connection, farmId, action, a, b, c, f, object)
    farmId = self:getConnectionFarmId(connection, farmId)
    local ok, code, amount = false, self.CODE.ERR_INVALID, 0
    if action == 1 then
        ok, code, amount = self:serverTakeLoan(farmId, a, object, c, f, b)
    elseif action == 2 then
        ok, code, amount = self:serverPay(farmId, a, b, f)
    elseif action == 6 then
        ok, code, amount = self:serverSetRolledTerm(farmId, a, b)
    elseif action >= 3 and action <= 5 then
        -- only the host of a listen server can change settings
        if connection ~= nil then
            ok, code = false, self.CODE.ERR_HOST
        else
            ok, code = true, nil
            if action == 3 then
                self:serverSetSetting(a, f)
            elseif action == 4 then
                self:serverApplyPreset(a)
            else
                self:serverResetDefaults()
            end
        end
    end
    if code ~= nil then
        self:sendResult(connection, farmId, code, amount or 0)
    end
    return ok
end

function LC:sendResult(connection, farmId, code, amount)
    if connection == nil then
        self:showNotification(code, amount, "")
    else
        connection:sendEvent(LCNotifyEvent.new(farmId, code, amount, ""))
    end
end

-- ---------------------------------------------------------------- notifications and sync

function LC:notifyFarm(farmId, code, amount, label)
    if g_currentMission:getIsClient() and g_currentMission:getFarmId() == farmId then
        self:showNotification(code, amount, label)
    end
    if g_server ~= nil then
        g_server:broadcastEvent(LCNotifyEvent.new(farmId, code, amount, label or ""), false)
    end
end

LC.NOTIFY_TEXT = {
    [1] = "nTaken", [2] = "nPayments", [3] = "nMissed", [4] = "nDefault", [5] = "nPaidOff", [6] = "nRepo",
    [7] = "nSeize", [8] = "nConverted", [9] = "nBaseBlocked", [11] = "nExtra", [12] = "nOverdue", [13] = "nRolled", [14] = "nTermSet", [15] = "nSaved", [16] = "nSaveFailed", [17] = "nSaveWait",
    [20] = "eScore", [21] = "eBlocked", [22] = "eLimit", [23] = "eCollateral", [24] = "ePledged",
    [25] = "eMoney", [26] = "eMaxLoans", [27] = "eInvalid", [28] = "eHost"
}

function LC:getCodeText(code, amount, label)
    local key = self.NOTIFY_TEXT[code]
    if key == nil then
        return ""
    end
    local text = LC.t(key)
    text = string.gsub(text, "%%AMOUNT%%", LC.formatMoney(amount or 0))
    text = string.gsub(text, "%%LABEL%%", label or "")
    return text
end

function LC:showNotification(code, amount, label)
    local text = self:getCodeText(code, amount, label)
    if text == "" or g_currentMission.addIngameNotification == nil then
        return
    end
    local kind = FSBaseMission.INGAME_NOTIFICATION_OK
    if code == self.CODE.MISSED or code == self.CODE.DEFAULT or code == self.CODE.REPO or code == self.CODE.SEIZE
        or code == self.CODE.CONVERTED or code == self.CODE.SAVE_FAILED or code == self.CODE.SAVE_WAIT
        or code >= 20 then
        kind = FSBaseMission.INGAME_NOTIFICATION_CRITICAL
    elseif code == self.CODE.PAYMENTS or code == self.CODE.BASE_BLOCKED or code == self.CODE.ROLLED or code == self.CODE.TERM_SET then
        kind = FSBaseMission.INGAME_NOTIFICATION_INFO
    end
    if kind == nil then
        kind = FSBaseMission.INGAME_NOTIFICATION_OK
    end
    g_currentMission:addIngameNotification(kind, text)
end

function LC:syncAll()
    if not self:isServer() then
        return
    end
    self:refreshNetIds()
    if g_server ~= nil then
        g_server:broadcastEvent(LCStateEvent.new(), false)
    end
end

-- ---------------------------------------------------------------- save / load

function LC:getSavePath()
    local info = g_currentMission.missionInfo
    if info ~= nil and info.savegameDirectory ~= nil then
        return info.savegameDirectory .. "/loansAndCredit.xml"
    end
    return nil
end

function LC:saveToXML()
    local path = self:getSavePath()
    if not self.loaded or path == nil or not self:isServer() then
        return
    end
    local xml = XMLFile.create("loansAndCreditXML", path, "loansAndCredit")
    if xml == nil then
        Logging.warning("[LoansAndCredit] Could not create %s", path)
        return
    end
    xml:setInt("loansAndCredit#month", self.month)
    xml:setInt("loansAndCredit#nextId", self.nextId)
    for i, def in ipairs(self.SETTINGS) do
        local key = string.format("loansAndCredit.settings.setting(%d)", i - 1)
        xml:setString(key .. "#key", def.key)
        xml:setFloat(key .. "#value", self:getSetting(def.key))
    end
    local fi = 0
    for farmId, farm in pairs(self.farms) do
        local key = string.format("loansAndCredit.farms.farm(%d)", fi)
        xml:setInt(key .. "#id", farmId)
        xml:setInt(key .. "#score", farm.score)
        xml:setInt(key .. "#blockedUntil", farm.blockedUntil)
        for hi, h in ipairs(farm.history) do
            local hk = string.format("%s.entry(%d)", key, hi - 1)
            xml:setInt(hk .. "#month", h.month)
            xml:setInt(hk .. "#code", h.code)
            xml:setFloat(hk .. "#amount", h.amount)
            xml:setString(hk .. "#label", h.label)
        end
        fi = fi + 1
    end
    for li, loan in ipairs(self.loans) do
        local key = string.format("loansAndCredit.loans.loan(%d)", li - 1)
        xml:setInt(key .. "#id", loan.id)
        xml:setInt(key .. "#farmId", loan.farmId)
        xml:setInt(key .. "#type", loan.type)
        xml:setFloat(key .. "#principal", loan.principal)
        xml:setFloat(key .. "#balance", loan.balance)
        xml:setFloat(key .. "#apr", loan.apr)
        xml:setInt(key .. "#termMonths", loan.termMonths)
        xml:setInt(key .. "#paymentsLeft", loan.paymentsLeft)
        xml:setFloat(key .. "#payment", loan.payment)
        xml:setFloat(key .. "#arrears", loan.arrears)
        xml:setInt(key .. "#missed", loan.missed)
        xml:setInt(key .. "#totalMissed", loan.totalMissed)
        xml:setFloat(key .. "#unpaidInterest", loan.unpaidInterest)
        xml:setString(key .. "#collKind", loan.collKind)
        xml:setString(key .. "#collId", loan.collId)
        xml:setString(key .. "#collLabel", loan.collLabel)
        xml:setInt(key .. "#startMonth", loan.startMonth)
        xml:setBool(key .. "#needsTerm", loan.needsTerm == true)
    end
    xml:save()
    xml:delete()
end

function LC:loadFromXML()
    self:resetSettings()
    local path = self:getSavePath()
    if path == nil or not fileExists(path) then
        return
    end
    local xml = XMLFile.load("loansAndCreditXML", path)
    if xml == nil then
        return
    end
    self.month = xml:getInt("loansAndCredit#month", 0)
    self.nextId = xml:getInt("loansAndCredit#nextId", 1)
    local i = 0
    while true do
        local key = string.format("loansAndCredit.settings.setting(%d)", i)
        if not xml:hasProperty(key) then
            break
        end
        local k = xml:getString(key .. "#key")
        if k ~= nil and self.settingIndex[k] ~= nil then
            self.settings[k] = xml:getFloat(key .. "#value", self:getSetting(k))
        end
        i = i + 1
    end
    i = 0
    while true do
        local key = string.format("loansAndCredit.farms.farm(%d)", i)
        if not xml:hasProperty(key) then
            break
        end
        local farmId = xml:getInt(key .. "#id", 0)
        local farm = { id = farmId, score = xml:getInt(key .. "#score", self:getSetting("startScore")),
            blockedUntil = xml:getInt(key .. "#blockedUntil", 0), history = {} }
        local h = 0
        while true do
            local hk = string.format("%s.entry(%d)", key, h)
            if not xml:hasProperty(hk) then
                break
            end
            table.insert(farm.history, { month = xml:getInt(hk .. "#month", 0), code = xml:getInt(hk .. "#code", 0),
                amount = xml:getFloat(hk .. "#amount", 0), label = xml:getString(hk .. "#label", "") })
            h = h + 1
        end
        self.farms[farmId] = farm
        i = i + 1
    end
    i = 0
    while true do
        local key = string.format("loansAndCredit.loans.loan(%d)", i)
        if not xml:hasProperty(key) then
            break
        end
        table.insert(self.loans, {
            id = xml:getInt(key .. "#id", 0), farmId = xml:getInt(key .. "#farmId", 0),
            type = xml:getInt(key .. "#type", 1), principal = xml:getFloat(key .. "#principal", 0),
            balance = xml:getFloat(key .. "#balance", 0), apr = xml:getFloat(key .. "#apr", 5),
            termMonths = xml:getInt(key .. "#termMonths", 12), paymentsLeft = xml:getInt(key .. "#paymentsLeft", 0),
            payment = xml:getFloat(key .. "#payment", 0), arrears = xml:getFloat(key .. "#arrears", 0),
            missed = xml:getInt(key .. "#missed", 0), totalMissed = xml:getInt(key .. "#totalMissed", 0),
            unpaidInterest = xml:getFloat(key .. "#unpaidInterest", 0), collKind = xml:getString(key .. "#collKind", ""),
            collId = xml:getString(key .. "#collId", ""), collLabel = xml:getString(key .. "#collLabel", ""),
            collNetId = 0, startMonth = xml:getInt(key .. "#startMonth", 0),
            needsTerm = xml:getBool(key .. "#needsTerm", false)
        })
        i = i + 1
    end
    xml:delete()
end

-- ---------------------------------------------------------------- base game loan
-- While "Disable the base-game loan" is on:
-- 1) each farm's base loan limit is held at its current base loan, so Borrow has nothing left to give,
--    but Repay still works for an old base loan
-- 2) a farm with no base loan left gets no loan permission on the Finances page, so the buttons grey out

function LC:isBaseLoanBlocked()
    return self.loaded == true and self:getSetting("blockBaseLoan") == 1
end

function LC:getAllFarms()
    if g_farmManager == nil then
        return {}
    end
    if g_farmManager.getFarms ~= nil then
        return g_farmManager:getFarms() or {}
    end
    return g_farmManager.farms or {}
end

function LC:clampFarmLoanMax(farm)
    if farm.loan ~= nil and farm.loanMax ~= nil and farm.loanMax > math.max(0, farm.loan) then
        farm.loanMax = math.max(0, farm.loan)
        return true
    end
    return false
end

function LC:updateBaseLoanBlock()
    local blocked = self:isBaseLoanBlocked()
    if blocked then
        self:rollBaseLoans()
        for _, farm in pairs(self:getAllFarms()) do
            self:clampFarmLoanMax(farm)
            if farm.loanMax ~= nil then
                self.loanMaxFound = true
            end
        end
    elseif self.wasBlocked then
        -- setting switched off: let the game work out the normal limit again
        for _, farm in pairs(self:getAllFarms()) do
            if farm.updateMaxLoan ~= nil then
                farm:updateMaxLoan()
            end
        end
    end
    self.wasBlocked = blocked
    if not self.loggedBlock and blocked then
        self.loggedBlock = true
        Logging.info("[LoansAndCredit] base loan block: permission hook %s, loan limit field %s",
            tostring(LC.permissionHooked == true), tostring(self.loanMaxFound == true))
    end
end

-- ---------------------------------------------------------------- rolling the old base loan into a term loan
-- Server only. A base-game loan that a farm already has (for example from before the mod was added) is
-- taken over by the mod: the base loan is set to zero and the same amount becomes a term loan here.
-- No money moves; the debt just changes hands. Each farm is handled at most once per session.

function LC:getBaseLoan(farm)
    if farm.getLoan ~= nil then
        return farm:getLoan() or 0
    end
    return farm.loan or 0
end

function LC:rollBaseLoans()
    if not self:isServer() or not self:isBaseLoanBlocked() or self:getSetting("rollBaseLoan") ~= 1 then
        return
    end
    self.rolledFarms = self.rolledFarms or {}
    for _, farm in pairs(self:getAllFarms()) do
        local farmId = farm.farmId
        if farmId ~= nil and farmId > 0 and not self.rolledFarms[farmId] then
            local amount = self:getBaseLoan(farm)
            if amount >= 1 and farm.loan ~= nil then
                self.rolledFarms[farmId] = true
                self:rollBaseLoan(farm, farmId, amount)
            end
        end
    end
end

function LC:rollBaseLoan(farm, farmId, amount)
    local apr = self:getApr(self.TYPE_TERM, self:getFarm(farmId).score)
    local months = self:getSetting("rollMonths")
    local label = LC.t("baseLoanLabel")
    local loan = {
        id = self.nextId, farmId = farmId, type = self.TYPE_TERM, principal = amount, balance = amount,
        apr = apr, termMonths = months, paymentsLeft = months, payment = self:calcPayment(amount, apr, months),
        arrears = 0, missed = 0, totalMissed = 0, unpaidInterest = 0, collKind = "", collId = "",
        collLabel = label, collNetId = 0, startMonth = self.month, needsTerm = true
    }
    farm.loan = 0
    if farm.loanMax ~= nil then
        farm.loanMax = 0
    end
    -- make sure the change really took before adding the new loan, so the debt is never doubled
    if self:getBaseLoan(farm) >= 1 then
        Logging.warning("[LoansAndCredit] could not clear the base loan of farm %d, it was not rolled over", farmId)
        return
    end
    if farm.raiseDirtyFlags ~= nil and farm.dirtyFlag ~= nil then
        farm:raiseDirtyFlags(farm.dirtyFlag)
    end
    self.nextId = self.nextId + 1
    table.insert(self.loans, loan)
    self:addHistory(farmId, self.CODE.ROLLED, amount, label)
    self:notifyFarm(farmId, self.CODE.ROLLED, amount, label)
    Logging.info("[LoansAndCredit] rolled base loan of farm %d (%d) into a %d-month term loan at %.2f%%",
        farmId, math.floor(amount), months, apr)
    self:syncAll()
end

-- the player picked the term for a moved base-game loan; payments are worked out again from today's balance
function LC:serverSetRolledTerm(farmId, loanId, months)
    local loan = self:getLoanById(loanId)
    if loan == nil or loan.farmId ~= farmId or not loan.needsTerm then
        return false, self.CODE.ERR_INVALID
    end
    local t = self.ROLL_TERMS
    months = LC.clamp(math.floor(months / t.step + 0.5) * t.step, t.min, t.max)
    loan.termMonths = months
    loan.paymentsLeft = months
    loan.payment = self:calcPayment(loan.balance, loan.apr, months)
    loan.needsTerm = false
    self:addHistory(farmId, self.CODE.TERM_SET, loan.payment, LC.t("monthsN", months))
    self:syncAll()
    return true, self.CODE.TERM_SET, loan.payment
end

function LC.hasPlayerLoanPermission(frame, superFunc, ...)
    local allowed = superFunc(frame, ...)
    if allowed and LC:isBaseLoanBlocked() then
        local farm = g_farmManager:getFarmById(g_currentMission:getFarmId())
        if farm == nil or (farm.loan or 0) <= 0 then
            return false
        end
    end
    return allowed
end

if InGameMenuStatisticsFrame ~= nil and InGameMenuStatisticsFrame.hasPlayerLoanPermission ~= nil then
    InGameMenuStatisticsFrame.hasPlayerLoanPermission = Utils.overwrittenFunction(
        InGameMenuStatisticsFrame.hasPlayerLoanPermission, LC.hasPlayerLoanPermission)
    LC.permissionHooked = true
end

if Farm ~= nil and Farm.updateMaxLoan ~= nil then
    Farm.updateMaxLoan = Utils.appendedFunction(Farm.updateMaxLoan, function(farm)
        if LC:isBaseLoanBlocked() then
            LC:clampFarmLoanMax(farm)
        end
    end)
end

-- ---------------------------------------------------------------- mod event listener

-- Scripts are loaded again for every savegame, but hooks on game classes stay. "loaded" makes the hooks
-- of an earlier, unloaded copy of this mod do nothing.
function LC:loadMap()
    self.loaded = true
    if self:isServer() then
        self:loadFromXML()
    elseif not self.stateReceived then
        -- a client keeps whatever the server already sent
        self:resetSettings()
    end
    g_messageCenter:subscribe(MessageType.PERIOD_CHANGED, self.onPeriodChanged, self)
    LCMenu:load()
end

function LC:deleteMap()
    self.loaded = false
    g_messageCenter:unsubscribeAll(self)
    LCMenu:delete()
    -- forget this savegame's data so the next one starts clean
    self.settings = {}
    self.farms = {}
    self.loans = {}
    self.month = 0
    self.nextId = 1
    self.stateReceived = false
    self.wasBlocked = false
    self.rolledFarms = {}
end

function LC:update(dt)
    self.blockTimer = (self.blockTimer or 0) + dt
    if self.blockTimer >= 500 then
        self.blockTimer = 0
        self:updateBaseLoanBlock()
    end
    LCMenu:update(dt)
end

function LC:draw()
    LCMenu:draw()
end

function LC:keyEvent(unicode, sym, modifier, isDown)
    LCMenu:keyEvent(unicode, sym, modifier, isDown)
end

function LC:mouseEvent(posX, posY, isDown, isUp, button)
    LCMenu:mouseEvent(posX, posY, isDown, isUp, button)
end

-- saving
FSCareerMissionInfo.saveToXMLFile = Utils.appendedFunction(FSCareerMissionInfo.saveToXMLFile, function()
    LC:saveToXML()
end)

-- Saving runs in the background and takes a moment. Every save (ours, the pause menu's or an autosave)
-- marks the game as busy until the game reports it complete, so the menu can't quit in the middle of one.
if FSBaseMission ~= nil and FSBaseMission.startSaveCurrentGame ~= nil then
    FSBaseMission.startSaveCurrentGame = Utils.prependedFunction(FSBaseMission.startSaveCurrentGame, function()
        if LC.loaded then
            LCMenu:onSaveStarted()
        end
    end)
end
if SavegameController ~= nil and SavegameController.onSaveComplete ~= nil then
    SavegameController.onSaveComplete = Utils.appendedFunction(SavegameController.onSaveComplete,
        function(_, errorCode)
            if LC.loaded then
                LCMenu:onSaveComplete(errorCode)
            end
        end)
    LC.saveCompleteHooked = true
end

-- send the full state to players who join
if FSBaseMission.sendInitialClientState ~= nil then
    FSBaseMission.sendInitialClientState = Utils.appendedFunction(FSBaseMission.sendInitialClientState,
        function(mission, connection)
            if not LC.loaded then
                return
            end
            LC:refreshNetIds()
            connection:sendEvent(LCStateEvent.new())
        end)
end

-- open-menu key: registered for the player on foot; Ctrl+B also works in vehicles as a fallback
function LC.registerActionEvents()
    if not LC.loaded or g_inputBinding == nil or InputAction.LC_OPEN_MENU == nil then
        return
    end
    local _, eventId = g_inputBinding:registerActionEvent(InputAction.LC_OPEN_MENU, LC, LC.onOpenAction,
        false, true, false, true)
    if eventId ~= nil then
        g_inputBinding:setActionEventTextVisibility(eventId, false)
        LC.actionRegistered = true
    end
end

function LC:onOpenAction()
    LCMenu:toggle()
end

if PlayerInputComponent ~= nil and PlayerInputComponent.registerGlobalPlayerActionEvents ~= nil then
    PlayerInputComponent.registerGlobalPlayerActionEvents = Utils.appendedFunction(
        PlayerInputComponent.registerGlobalPlayerActionEvents, LC.registerActionEvents)
end

addModEventListener(LoansAndCredit)
