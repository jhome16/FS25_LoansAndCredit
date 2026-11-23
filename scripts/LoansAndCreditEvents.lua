-- Network events for Loans And Credit. The server owns all loan data; clients get a full copy
-- whenever something changes and send requests for anything they want to do.

-- ---------------------------------------------------------------- full state (server -> clients)

LCStateEvent = {}
local LCStateEvent_mt = Class(LCStateEvent, Event)
InitEventClass(LCStateEvent, "LCStateEvent")

function LCStateEvent.emptyNew()
    return Event.new(LCStateEvent_mt)
end

function LCStateEvent.new()
    return LCStateEvent.emptyNew()
end

function LCStateEvent:writeStream(streamId, connection)
    local LC = LoansAndCredit
    streamWriteInt32(streamId, LC.month)
    streamWriteUInt8(streamId, #LC.SETTINGS)
    for _, def in ipairs(LC.SETTINGS) do
        streamWriteFloat32(streamId, LC:getSetting(def.key))
    end

    local farms = {}
    for _, farm in pairs(LC.farms) do
        table.insert(farms, farm)
    end
    streamWriteUInt16(streamId, #farms)
    for _, farm in ipairs(farms) do
        streamWriteUInt16(streamId, farm.id)
        streamWriteInt32(streamId, farm.score)
        streamWriteInt32(streamId, farm.blockedUntil)
        streamWriteUInt8(streamId, #farm.history)
        for _, h in ipairs(farm.history) do
            streamWriteInt32(streamId, h.month)
            streamWriteUInt8(streamId, h.code)
            streamWriteFloat32(streamId, h.amount)
            streamWriteString(streamId, h.label)
        end
    end

    streamWriteUInt16(streamId, #LC.loans)
    for _, loan in ipairs(LC.loans) do
        streamWriteInt32(streamId, loan.id)
        streamWriteUInt16(streamId, loan.farmId)
        streamWriteUInt8(streamId, loan.type)
        streamWriteFloat32(streamId, loan.principal)
        streamWriteFloat32(streamId, loan.balance)
        streamWriteFloat32(streamId, loan.apr)
        streamWriteUInt16(streamId, loan.termMonths)
        streamWriteUInt16(streamId, loan.paymentsLeft)
        streamWriteFloat32(streamId, loan.payment)
        streamWriteFloat32(streamId, loan.arrears)
        streamWriteUInt8(streamId, loan.missed)
        streamWriteUInt16(streamId, loan.totalMissed)
        streamWriteFloat32(streamId, loan.unpaidInterest)
        streamWriteString(streamId, loan.collKind)
        streamWriteString(streamId, loan.collId)
        streamWriteString(streamId, loan.collLabel)
        streamWriteInt32(streamId, loan.collNetId or 0)
        streamWriteInt32(streamId, loan.startMonth)
        streamWriteBool(streamId, loan.needsTerm == true)
    end
end

function LCStateEvent:readStream(streamId, connection)
    local LC = LoansAndCredit
    LC.month = streamReadInt32(streamId)
    local count = streamReadUInt8(streamId)
    for i = 1, count do
        local value = streamReadFloat32(streamId)
        local def = LC.SETTINGS[i]
        if def ~= nil then
            LC.settings[def.key] = value
        end
    end

    LC.farms = {}
    local farmCount = streamReadUInt16(streamId)
    for _ = 1, farmCount do
        local farm = { id = streamReadUInt16(streamId), history = {} }
        farm.score = streamReadInt32(streamId)
        farm.blockedUntil = streamReadInt32(streamId)
        local hCount = streamReadUInt8(streamId)
        for _ = 1, hCount do
            local h = {}
            h.month = streamReadInt32(streamId)
            h.code = streamReadUInt8(streamId)
            h.amount = streamReadFloat32(streamId)
            h.label = streamReadString(streamId)
            table.insert(farm.history, h)
        end
        LC.farms[farm.id] = farm
    end

    LC.loans = {}
    local loanCount = streamReadUInt16(streamId)
    for _ = 1, loanCount do
        local loan = {}
        loan.id = streamReadInt32(streamId)
        loan.farmId = streamReadUInt16(streamId)
        loan.type = streamReadUInt8(streamId)
        loan.principal = streamReadFloat32(streamId)
        loan.balance = streamReadFloat32(streamId)
        loan.apr = streamReadFloat32(streamId)
        loan.termMonths = streamReadUInt16(streamId)
        loan.paymentsLeft = streamReadUInt16(streamId)
        loan.payment = streamReadFloat32(streamId)
        loan.arrears = streamReadFloat32(streamId)
        loan.missed = streamReadUInt8(streamId)
        loan.totalMissed = streamReadUInt16(streamId)
        loan.unpaidInterest = streamReadFloat32(streamId)
        loan.collKind = streamReadString(streamId)
        loan.collId = streamReadString(streamId)
        loan.collLabel = streamReadString(streamId)
        loan.collNetId = streamReadInt32(streamId)
        loan.startMonth = streamReadInt32(streamId)
        loan.needsTerm = streamReadBool(streamId)
        table.insert(LC.loans, loan)
    end
    LC.stateReceived = true
end

function LCStateEvent:run(connection)
end

-- ---------------------------------------------------------------- request (client -> server)

LCRequestEvent = {}
local LCRequestEvent_mt = Class(LCRequestEvent, Event)
InitEventClass(LCRequestEvent, "LCRequestEvent")

function LCRequestEvent.emptyNew()
    return Event.new(LCRequestEvent_mt)
end

function LCRequestEvent.new(farmId, action, a, b, c, f, object)
    local self = LCRequestEvent.emptyNew()
    self.farmId = farmId
    self.action = action
    self.a = a or 0
    self.b = b or 0
    self.c = c or 0
    self.f = f or 0
    self.object = object
    return self
end

function LCRequestEvent:writeStream(streamId, connection)
    streamWriteUInt16(streamId, self.farmId)
    streamWriteUInt8(streamId, self.action)
    streamWriteInt32(streamId, self.a)
    streamWriteInt32(streamId, self.b)
    streamWriteInt32(streamId, self.c)
    streamWriteFloat32(streamId, self.f)
    if streamWriteBool(streamId, self.object ~= nil) then
        NetworkUtil.writeNodeObject(streamId, self.object)
    end
end

function LCRequestEvent:readStream(streamId, connection)
    self.farmId = streamReadUInt16(streamId)
    self.action = streamReadUInt8(streamId)
    self.a = streamReadInt32(streamId)
    self.b = streamReadInt32(streamId)
    self.c = streamReadInt32(streamId)
    self.f = streamReadFloat32(streamId)
    if streamReadBool(streamId) then
        self.object = NetworkUtil.readNodeObject(streamId)
    end
    self:run(connection)
end

function LCRequestEvent:run(connection)
    if not connection:getIsServer() then
        LoansAndCredit:handleRequest(connection, self.farmId, self.action, self.a, self.b, self.c, self.f, self.object)
    end
end

-- ---------------------------------------------------------------- notification (server -> clients)

LCNotifyEvent = {}
local LCNotifyEvent_mt = Class(LCNotifyEvent, Event)
InitEventClass(LCNotifyEvent, "LCNotifyEvent")

function LCNotifyEvent.emptyNew()
    return Event.new(LCNotifyEvent_mt)
end

function LCNotifyEvent.new(farmId, code, amount, label)
    local self = LCNotifyEvent.emptyNew()
    self.farmId = farmId
    self.code = code
    self.amount = amount or 0
    self.label = label or ""
    return self
end

function LCNotifyEvent:writeStream(streamId, connection)
    streamWriteUInt16(streamId, self.farmId)
    streamWriteUInt8(streamId, self.code)
    streamWriteFloat32(streamId, self.amount)
    streamWriteString(streamId, self.label)
end

function LCNotifyEvent:readStream(streamId, connection)
    self.farmId = streamReadUInt16(streamId)
    self.code = streamReadUInt8(streamId)
    self.amount = streamReadFloat32(streamId)
    self.label = streamReadString(streamId)
    self:run(connection)
end

function LCNotifyEvent:run(connection)
    if g_currentMission ~= nil and g_currentMission:getFarmId() == self.farmId then
        LoansAndCredit:showNotification(self.code, self.amount, self.label)
    end
end
