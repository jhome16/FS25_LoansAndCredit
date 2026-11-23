-- Colour themes for the Loans And Credit menu: the same presets as Markets And Futures,
-- plus an accent colour and a brightness setting. Saved per player on this computer.

LCTheme = {
    preset = 1, -- 1..#PRESETS
    accent = 0, -- 0 = the preset's own accent, otherwise 1..#ACCENTS
    bright = 100 -- background and button brightness in percent (60..140)
}
local TH = LCTheme

-- bg = panel body, tint = buttons / header, accent = frame lines, hi = titles and highlights
TH.PRESETS = {
    { key = "th1", bg = { 0.05, 0.07, 0.06 }, tint = { 0.20, 0.50, 0.28 }, accent = { 0.80, 0.65, 0.22 }, hi = { 1.00, 0.82, 0.25 } },
    { key = "th2", bg = { 0.04, 0.05, 0.10 }, tint = { 0.22, 0.38, 0.75 }, accent = { 0.45, 0.70, 1.00 }, hi = { 0.65, 0.85, 1.00 } },
    { key = "th3", bg = { 0.09, 0.07, 0.03 }, tint = { 0.70, 0.50, 0.12 }, accent = { 0.90, 0.72, 0.25 }, hi = { 1.00, 0.88, 0.40 } },
    { key = "th4", bg = { 0.09, 0.04, 0.04 }, tint = { 0.65, 0.20, 0.18 }, accent = { 0.85, 0.70, 0.50 }, hi = { 1.00, 0.85, 0.60 } },
    { key = "th5", bg = { 0.06, 0.07, 0.09 }, tint = { 0.30, 0.40, 0.52 }, accent = { 0.70, 0.78, 0.88 }, hi = { 0.85, 0.92, 1.00 } },
    { key = "th6", bg = { 0.07, 0.07, 0.07 }, tint = { 0.75, 0.40, 0.10 }, accent = { 0.95, 0.55, 0.15 }, hi = { 1.00, 0.70, 0.30 } },
    { key = "th7", bg = { 0.10, 0.04, 0.07 }, tint = { 0.75, 0.30, 0.40 }, accent = { 1.00, 0.60, 0.35 }, hi = { 1.00, 0.78, 0.50 } },
    { key = "th8", bg = { 0.07, 0.05, 0.10 }, tint = { 0.45, 0.32, 0.70 }, accent = { 0.78, 0.65, 0.95 }, hi = { 0.90, 0.80, 1.00 } },
    { key = "th9", bg = { 0.03, 0.08, 0.09 }, tint = { 0.10, 0.55, 0.58 }, accent = { 0.35, 0.85, 0.85 }, hi = { 0.55, 1.00, 0.95 } },
    { key = "th10", bg = { 0.10, 0.08, 0.05 }, tint = { 0.62, 0.48, 0.30 }, accent = { 0.85, 0.72, 0.50 }, hi = { 0.98, 0.88, 0.65 } },
    { key = "th11", bg = { 0.05, 0.08, 0.10 }, tint = { 0.35, 0.62, 0.78 }, accent = { 0.80, 0.92, 1.00 }, hi = { 1.00, 1.00, 1.00 } },
    { key = "th12", bg = { 0.00, 0.00, 0.00 }, tint = { 0.15, 0.45, 0.15 }, accent = { 1.00, 1.00, 0.00 }, hi = { 1.00, 1.00, 0.20 } },
    -- flat, translucent black panels like the game's own HUD
    { key = "th13", bg = { 0.00, 0.00, 0.00 }, tint = { 0.28, 0.28, 0.28 }, accent = { 0.45, 0.45, 0.45 }, hi = { 0.96, 0.96, 0.96 }, flat = true }
}

-- accent colours that replace the preset's frame and title colour
TH.ACCENTS = {
    { 1.00, 0.82, 0.25 }, { 1.00, 0.60, 0.15 }, { 0.95, 0.35, 0.30 }, { 1.00, 0.50, 0.70 }, { 0.70, 0.50, 0.95 },
    { 0.45, 0.70, 1.00 }, { 0.35, 0.90, 0.85 }, { 0.45, 0.90, 0.40 }, { 0.95, 0.95, 0.95 }
}

local function clamp(v, a, b)
    if v < a then
        return a
    end
    if v > b then
        return b
    end
    return v
end

local function mix(a, b, t)
    return { a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t }
end

local function mul(a, k, alpha)
    return { clamp(a[1] * k, 0, 1), clamp(a[2] * k, 0, 1), clamp(a[3] * k, 0, 1), alpha or 1 }
end

function TH:getPreset(i)
    return self.PRESETS[i] or self.PRESETS[1]
end

-- colours for a swatch preview: background, button, accent
function TH:getSwatch(i)
    local p = self:getPreset(i)
    return mul(p.bg, 1), mul(mix(p.bg, p.tint, 0.55), 1), mul(p.accent, 1)
end

-- writes the theme colours into the menu's colour table; fixed colours (text, red, green...) stay as they are
function TH:apply(C)
    local p = self:getPreset(self.preset)
    local k = self.bright / 100
    local accent, hi = p.accent, p.hi
    if self.accent > 0 and self.ACCENTS[self.accent] ~= nil then
        accent = self.ACCENTS[self.accent]
        hi = mix(accent, { 1, 1, 1 }, 0.15)
    end
    local bgAlpha = 0.95
    if p.flat then
        bgAlpha = 0.80
    end
    C.bg = mul(p.bg, k, bgAlpha)
    C.panel = mul(mix(p.bg, p.tint, 0.10), k, p.flat and 0.55 or 1)
    C.stripe = mul(mix(p.bg, p.tint, 0.18), k, p.flat and 0.65 or 1)
    C.header = mul(mix(p.bg, p.tint, 0.45), k, p.flat and 0.85 or 1)
    C.sel = mul(mix(p.bg, p.tint, 0.65), k)
    C.btn = mul(mix(p.bg, p.tint, 0.55), k)
    C.btnHover = mul(mix(p.tint, { 1, 1, 1 }, 0.15), k)
    C.btnActive = mul(accent, 0.75)
    C.btnOff = mul(mix(p.bg, { 0.3, 0.3, 0.3 }, 0.4), 1)
    C.accent = mul(accent, 1)
    C.gold = mul(hi, 1)
end

-- ---------------------------------------------------------------- saving (per player, not in the savegame)

function TH:getPath()
    if getUserProfileAppPath == nil then
        return nil
    end
    return getUserProfileAppPath() .. "modSettings/FS25_LoansAndCredit.xml"
end

function TH:load()
    local path = self:getPath()
    if path == nil or not fileExists(path) then
        return
    end
    local xml = XMLFile.load("lcThemeXML", path)
    if xml == nil then
        return
    end
    self.preset = clamp(xml:getInt("loansAndCredit.appearance#preset", 1), 1, #self.PRESETS)
    self.accent = clamp(xml:getInt("loansAndCredit.appearance#accent", 0), 0, #self.ACCENTS)
    self.bright = clamp(xml:getInt("loansAndCredit.appearance#brightness", 100), 60, 140)
    xml:delete()
end

function TH:save()
    local path = self:getPath()
    if path == nil then
        return
    end
    if createFolder ~= nil then
        createFolder(getUserProfileAppPath() .. "modSettings")
    end
    local xml = XMLFile.create("lcThemeXML", path, "loansAndCredit")
    if xml == nil then
        return
    end
    xml:setInt("loansAndCredit.appearance#preset", self.preset)
    xml:setInt("loansAndCredit.appearance#accent", self.accent)
    xml:setInt("loansAndCredit.appearance#brightness", self.bright)
    xml:save()
    xml:delete()
end

function TH:set(preset, accent, bright)
    self.preset = clamp(preset, 1, #self.PRESETS)
    self.accent = clamp(accent, 0, #self.ACCENTS)
    self.bright = clamp(bright, 60, 140)
    self:apply(LCMenu.C)
    self:save()
end
