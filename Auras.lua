-- LotusFrames: auras (beneficios y perjuicios) del objetivo y del jugador, encima de cada marco.
-- Dos estilos como ElvUI:
--   * iconos: contador de tiempo dentro y animacion de reloj que avanza
--   * barras: icono + nombre + tiempo, con una barra que se va vaciando

local _, ns = ...
local FLAT, Text = ns.FLAT, ns.Text

ns.AURA_DEFAULTS = {
	enabled = true,
	style = "icons",   -- "icons" o "bars"
	debuffs = true,
	buffs = true,
	onlyMine = false,  -- solo perjuicios lanzados por mi
	playerBuffs = true,   -- mis beneficios encima de mi marco
	playerDebuffs = true, -- mis perjuicios encima de mi marco
	showTimer = true,
	size = 28,         -- tamano de icono
	perRow = 7,
	max = 16,
	barHeight = 18,
	spacing = 3,
}

function ns.InitAuraDB(db)
	db.auras = db.auras or {}
	for k, v in pairs(ns.AURA_DEFAULTS) do
		if db.auras[k] == nil then db.auras[k] = v end
	end
end

local function Opt() return ns.GetDB().auras end

---------------------------------------------------------------------------
-- Tiempo restante
---------------------------------------------------------------------------

local function FormatTime(t)
	if t >= 3600 then return string.format("%dh", math.ceil(t / 3600)), 0.8, 0.8, 1 end
	if t >= 60 then return string.format("%dm", math.ceil(t / 60)), 0.8, 0.8, 1 end
	if t >= 10 then return string.format("%d", math.floor(t + 0.5)), 1, 1, 1 end
	if t >= 5 then return string.format("%d", math.floor(t + 0.5)), 1, 0.85, 0.2 end
	return string.format("%.1f", t), 1, 0.25, 0.2
end

-- Colores por tipo de perjuicio (los de Blizzard si existen en esta version)
local DEBUFF_COLORS = {
	none    = { r = 0.80, g = 0.00, b = 0.00 },
	Magic   = { r = 0.20, g = 0.60, b = 1.00 },
	Curse   = { r = 0.60, g = 0.00, b = 1.00 },
	Disease = { r = 0.60, g = 0.40, b = 0.00 },
	Poison  = { r = 0.00, g = 0.60, b = 0.00 },
}

local function AuraColor(aura)
	if aura.filter == "HELPFUL" then return 0.2, 0.65, 0.3 end
	local colors = DebuffTypeColor or DEBUFF_COLORS
	local dtype = (aura.dtype and aura.dtype ~= "") and aura.dtype or "none"
	local c = colors[dtype] or colors.none or DEBUFF_COLORS.none
	return c.r, c.g, c.b
end

local function ShowTooltip(self)
	if not self.index then return end
	GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
	GameTooltip:SetUnitAura(self.unit, self.index, self.filter)
end

---------------------------------------------------------------------------
-- Estilo iconos
---------------------------------------------------------------------------

local function IconOnUpdate(self, elapsed)
	self.tick = (self.tick or 0) + elapsed
	if self.tick < 0.1 then return end
	self.tick = 0
	local remaining = self.expiration - GetTime()
	if remaining > 0 then
		local text, r, g, b = FormatTime(remaining)
		self.timer:SetText(text)
		self.timer:SetTextColor(r, g, b)
	else
		self.timer:SetText("")
	end
end

local function NewIcon(f)
	local b = CreateFrame("Frame", nil, f.auraHolder, "BackdropTemplate")
	b.unit = f.unit
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	-- reloj: el oscurecimiento crece a medida que se acaba el tiempo
	b.cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
	b.cd:SetAllPoints(b.icon)
	b.cd:SetReverse(true)
	b.cd:SetDrawEdge(false)
	b.cd:SetHideCountdownNumbers(true)
	local over = CreateFrame("Frame", nil, b)
	over:SetAllPoints()
	over:SetFrameLevel(b.cd:GetFrameLevel() + 2)
	b.timer = Text(over, 13, "CENTER")
	b.timer:SetPoint("CENTER", 0, 0)
	b.count = Text(over, 11, "RIGHT")
	b.count:SetPoint("BOTTOMRIGHT", 0, 1)
	b:SetScript("OnEnter", ShowTooltip)
	b:SetScript("OnLeave", GameTooltip_Hide)
	b:Hide()
	return b
end

local function SetIcon(b, aura, o)
	b.index, b.filter = aura.index, aura.filter
	b.icon:SetTexture(aura.icon)
	b.count:SetText(aura.count and aura.count > 1 and aura.count or "")
	-- borde del color del tipo de perjuicio (magia, veneno...); beneficios con borde negro
	if aura.filter == "HARMFUL" then
		b:SetBackdropBorderColor(AuraColor(aura))
	else
		b:SetBackdropBorderColor(0, 0, 0)
	end
	if aura.duration and aura.duration > 0 and aura.expiration and aura.expiration > 0 then
		b.cd:SetCooldown(aura.expiration - aura.duration, aura.duration)
		b.cd:Show()
		b.expiration = aura.expiration
		if o.showTimer then
			b.tick = 1
			b:SetScript("OnUpdate", IconOnUpdate)
		else
			b.timer:SetText("")
			b:SetScript("OnUpdate", nil)
		end
	else
		b.cd:Clear()
		b.cd:Hide()
		b.timer:SetText("")
		b:SetScript("OnUpdate", nil)
	end
	b:Show()
end

---------------------------------------------------------------------------
-- Estilo barras
---------------------------------------------------------------------------

local function BarOnUpdate(self, elapsed)
	local remaining = self.expiration - GetTime()
	if remaining < 0 then remaining = 0 end
	self.bar:SetValue(remaining)
	self.tick = (self.tick or 0) + elapsed
	if self.tick < 0.1 then return end
	self.tick = 0
	if self.showTimer and remaining > 0 then
		self.time:SetText((FormatTime(remaining)))
	else
		self.time:SetText("")
	end
end

local function NewBar(f)
	local r = CreateFrame("Frame", nil, f.auraHolder, "BackdropTemplate")
	r.unit = f.unit
	r.iconFrame = CreateFrame("Frame", nil, r, "BackdropTemplate")
	r.icon = r.iconFrame:CreateTexture(nil, "ARTWORK")
	r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	r.count = Text(r.iconFrame, 10, "RIGHT")
	r.count:SetPoint("BOTTOMRIGHT", 0, 1)
	r.bar = CreateFrame("StatusBar", nil, r)
	r.bar:SetStatusBarTexture(FLAT)
	r.bar.bg = r.bar:CreateTexture(nil, "BACKGROUND")
	r.bar.bg:SetAllPoints()
	r.bar.bg:SetTexture(FLAT)
	r.name = Text(r.bar, 12, "LEFT")
	r.name:SetPoint("LEFT", 4, 0)
	r.time = Text(r.bar, 12, "RIGHT")
	r.time:SetPoint("RIGHT", -4, 0)
	r.name:SetPoint("RIGHT", r.time, "LEFT", -4, 0)
	r:SetScript("OnEnter", ShowTooltip)
	r:SetScript("OnLeave", GameTooltip_Hide)
	r:Hide()
	return r
end

local function SetBar(r, aura, o)
	r.index, r.filter = aura.index, aura.filter
	r.icon:SetTexture(aura.icon)
	r.count:SetText(aura.count and aura.count > 1 and aura.count or "")
	r.name:SetText(aura.name)
	local cr, cg, cb = AuraColor(aura)
	r.bar:SetStatusBarColor(cr, cg, cb)
	r.bar.bg:SetVertexColor(cr * 0.25, cg * 0.25, cb * 0.25, 0.9)
	r.showTimer = o.showTimer
	if aura.duration and aura.duration > 0 and aura.expiration and aura.expiration > 0 then
		r.expiration = aura.expiration
		r.bar:SetMinMaxValues(0, aura.duration)
		r.tick = 1
		r:SetScript("OnUpdate", BarOnUpdate)
	else
		-- sin duracion conocida: barra llena y sin tiempo
		r.bar:SetMinMaxValues(0, 1)
		r.bar:SetValue(1)
		r.time:SetText("")
		r:SetScript("OnUpdate", nil)
	end
	r:Show()
end

---------------------------------------------------------------------------
-- Creacion, distribucion y actualizacion
---------------------------------------------------------------------------

function ns.CreateAuras(f)
	f.auraHolder = CreateFrame("Frame", nil, f)
	f.auraHolder:SetAllPoints(f)
	f.auraIcons, f.auraBars = {}, {}
end

local function Pool(f, list, factory, i)
	local w = list[i]
	if not w then
		w = factory(f)
		list[i] = w
		w.needsLayout = true
	end
	return w
end

-- Tamanos, bordes de 1 pixel y posiciones (iconos crecen a la derecha y hacia arriba;
-- barras se apilan hacia arriba)
function ns.LayoutAuras(f)
	if not f.auraHolder then return end
	local o, px = Opt(), ns.Pixel(f)
	local size, gap = o.size, o.spacing
	for i, b in ipairs(f.auraIcons) do
		b:SetSize(size, size)
		b:SetBackdrop({ edgeFile = FLAT, edgeSize = px })
		b.icon:ClearAllPoints()
		b.icon:SetPoint("TOPLEFT", px, -px)
		b.icon:SetPoint("BOTTOMRIGHT", -px, px)
		local col, row = (i - 1) % o.perRow, math.floor((i - 1) / o.perRow)
		b:ClearAllPoints()
		b:SetPoint("BOTTOMLEFT", f, "TOPLEFT", col * (size + gap), 4 + row * (size + gap))
		b.needsLayout = nil
	end
	local h = o.barHeight
	for i, r in ipairs(f.auraBars) do
		r:SetHeight(h)
		r:ClearAllPoints()
		r:SetPoint("BOTTOMLEFT", f, "TOPLEFT", 0, 4 + (i - 1) * (h + 2))
		r:SetPoint("BOTTOMRIGHT", f, "TOPRIGHT", 0, 4 + (i - 1) * (h + 2))
		r.iconFrame:SetSize(h, h)
		r.iconFrame:ClearAllPoints()
		r.iconFrame:SetPoint("LEFT", r, "LEFT", 0, 0)
		r.iconFrame:SetBackdrop({ bgFile = FLAT, edgeFile = FLAT, edgeSize = px })
		r.iconFrame:SetBackdropColor(0, 0, 0, 1)
		r.iconFrame:SetBackdropBorderColor(0, 0, 0, 1)
		r.icon:ClearAllPoints()
		r.icon:SetPoint("TOPLEFT", px, -px)
		r.icon:SetPoint("BOTTOMRIGHT", -px, px)
		r:SetBackdrop({ bgFile = FLAT, edgeFile = FLAT, edgeSize = px })
		r:SetBackdropColor(0, 0, 0, 0.6)
		r:SetBackdropBorderColor(0, 0, 0, 1)
		r.bar:ClearAllPoints()
		r.bar:SetPoint("TOPLEFT", r.iconFrame, "TOPRIGHT", px, -px)
		r.bar:SetPoint("BOTTOMRIGHT", r, "BOTTOMRIGHT", -px, px)
		r.needsLayout = nil
	end
end

local collected = {}

-- Vista previa (desde las opciones): auras de ejemplo que se repiten
local I = "Interface\\Icons\\"
local SAMPLES = { -- spellID, segundos, acumulaciones, filtro, tipo, nombre, icono
	{ 7386, 30, 5, "HARMFUL", nil, "Hender armadura", I .. "Ability_Warrior_Sunder" },
	{ 772, 21, 1, "HARMFUL", nil, "Desgarrar", I .. "Ability_Gouge" },
	{ 1160, 30, 1, "HARMFUL", "Magic", "Grito desmoralizador", I .. "Ability_Warrior_WarCry" },
	{ 1715, 15, 1, "HARMFUL", nil, "Seccionar", I .. "Ability_ShockWave" },
	{ 6343, 10, 1, "HARMFUL", "Magic", "Atronar", I .. "Spell_Nature_ThunderClap" },
	{ 774, 12, 1, "HELPFUL", nil, "Rejuvenecimiento", I .. "Spell_Nature_Rejuvenation" },
	{ 1243, 1800, 1, "HELPFUL", nil, "Palabra de poder: entereza", I .. "Spell_Holy_WordFortitude" },
}

-- Nombre del hechizo en el idioma del juego si la API lo da; si no, el de la tabla
local function SpellName(id, fallback)
	local ok, name = pcall(function()
		if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(id) end
		if GetSpellInfo then return (GetSpellInfo(id)) end
	end)
	return ok and name or fallback
end
local previewStart = 0
local previewTicker

function ns.SetAuraPreview(on)
	local f = ns.frames.target
	if not f or InCombatLockdown() then return end
	ns.preview = on
	previewStart = GetTime()
	if previewTicker then previewTicker:Cancel(); previewTicker = nil end
	if on then
		UnregisterUnitWatch(f)
		f:Show()
		if not UnitExists(f.unit) and ns.PaintPreview then ns.PaintPreview(f) end
		previewTicker = C_Timer.NewTicker(1, function()
			for _, fr in pairs(ns.frames) do ns.UpdateAuras(fr) end
		end)
	elseif not ns.editing then
		RegisterUnitWatch(f)
	end
	ns.RefreshAuras()
end

local function CollectPreview(list, debuffs, buffs)
	local now = GetTime()
	for _, s in ipairs(SAMPLES) do
		local name, icon = SpellName(s[1], s[6]), s[7]
		local isDebuff = s[4] == "HARMFUL"
		if (isDebuff and debuffs) or (not isDebuff and buffs) then
			-- cada aura se "renueva" al terminar para que la animacion siga
			local elapsed = (now - previewStart) % s[2]
			list[#list + 1] = {
				filter = s[4], name = name, icon = icon, count = s[3], dtype = s[5],
				duration = s[2], expiration = now - elapsed + s[2],
			}
		end
	end
end

local function Collect(unit, filter, list, o)
	for i = 1, 40 do
		local name, icon, count, dtype, duration, expiration = ns.GetAura(unit, i, filter)
		if not name then break end
		list[#list + 1] = {
			index = i, filter = filter:find("HARMFUL") and "HARMFUL" or "HELPFUL", name = name, icon = icon,
			count = count, dtype = dtype, duration = duration, expiration = expiration,
		}
	end
end

function ns.UpdateAuras(f)
	if not f.auraHolder then return end
	local o = Opt()
	-- el marco del jugador tiene sus propias casillas; el objetivo, las de siempre
	local enabled, debuffs, buffs, onlyMine = o.enabled, o.debuffs, o.buffs, o.onlyMine
	if f.unit == "player" then
		enabled, debuffs, buffs, onlyMine = true, o.playerDebuffs, o.playerBuffs, false
	end
	wipe(collected)
	if ns.preview then
		CollectPreview(collected, debuffs, buffs)
	elseif enabled and UnitExists(f.unit) then
		-- con "solo mis perjuicios" usamos el filtro PLAYER del juego
		if debuffs then Collect(f.unit, onlyMine and "HARMFUL|PLAYER" or "HARMFUL", collected, o) end
		if buffs then Collect(f.unit, "HELPFUL", collected, o) end
		if o.style == "bars" then
			-- barras: las que se acaban antes, abajo (mas cerca del marco); las permanentes al final
			table.sort(collected, function(a, b)
				local ta = (a.expiration and a.expiration > 0) and a.expiration or math.huge
				local tb = (b.expiration and b.expiration > 0) and b.expiration or math.huge
				return ta < tb
			end)
		end
	end

	local shown = math.min(#collected, o.max)
	local useBars = o.style == "bars"
	local relayout = false
	for i = 1, shown do
		local w = useBars and Pool(f, f.auraBars, NewBar, i) or Pool(f, f.auraIcons, NewIcon, i)
		if w.needsLayout then relayout = true end
	end
	if relayout then ns.LayoutAuras(f) end

	for i = 1, shown do
		-- si un aura falla, las demas igual se muestran y el error sale en el chat (una vez)
		local ok, err
		if useBars then
			ok, err = pcall(SetBar, f.auraBars[i], collected[i], o)
		else
			ok, err = pcall(SetIcon, f.auraIcons[i], collected[i], o)
		end
		if not ok and err ~= ns.lastAuraError then
			ns.lastAuraError = err
			print("|cffff4040LotusFrames error (auras):|r " .. tostring(err))
		end
	end
	for i = useBars and shown + 1 or 1, #f.auraBars do f.auraBars[i]:Hide() end
	for i = useBars and 1 or shown + 1, #f.auraIcons do f.auraIcons[i]:Hide() end
end

-- La vista previa se apaga sola al entrar en combate
local combatWatcher = CreateFrame("Frame")
combatWatcher:RegisterEvent("PLAYER_REGEN_DISABLED")
combatWatcher:SetScript("OnEvent", function()
	if ns.preview then ns.SetAuraPreview(false) end
end)
