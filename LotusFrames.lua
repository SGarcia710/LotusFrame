-- LotusFrames: marcos de jugador y objetivo estilo ElvUI.
-- Igual que ElvUI/oUF: crea botones seguros propios y esconde PlayerFrame/TargetFrame de Blizzard.
-- Retrato 3D (PlayerModel) superpuesto en la barra de vida, bordes de 1 pixel y valores siempre visibles.

local ADDON = ...

local FONT = "Interface\\AddOns\\LotusFrames\\Media\\PTSansNarrow.ttf"
local FLAT = "Interface\\Buttons\\WHITE8X8"
local STATE_ICONS = "Interface\\CharacterFrame\\UI-StateIcon"

local WIDTH    = 220
local HEALTH_H = 36
local POWER_H  = 12
local INFO_H   = 18
local MODEL_ALPHA = 0.5
local MODEL_CAM_DISTANCE = 2
local EXECUTE_PCT = 20

local DEFAULTS = {
	scale = 1,
	player = { "TOPLEFT", "UIParent", "TOPLEFT", 20, -20 },
	target = { "TOPLEFT", "UIParent", "TOPLEFT", 280, -20 },
}

-- Paleta de ElvUI
local COLORS = {
	friendly = { 0.29, 0.68, 0.30 },
	neutral  = { 0.85, 0.77, 0.36 },
	hostile  = { 0.78, 0.25, 0.25 },
	tapped   = { 0.55, 0.57, 0.61 },
	dead     = { 0.35, 0.35, 0.35 },
	power = {
		MANA   = { 0.31, 0.45, 0.63 },
		RAGE   = { 0.78, 0.25, 0.25 },
		ENERGY = { 0.65, 0.63, 0.35 },
		FOCUS  = { 0.71, 0.43, 0.27 },
	},
}

local frames = {}
local db
local ns = select(2, ...)
ns.editing = false
local CreateEditOverlay -- definida en la seccion "Modo edicion"

-- Precarga la fuente: un FontString cuyo archivo de fuente aun no termino de cargar
-- se queda en blanco hasta que su texto cambia (por eso el nombre no aparecia al entrar).
local fontPreload = UIParent:CreateFontString(nil, "BACKGROUND")
fontPreload:SetFont(FONT, 13, "OUTLINE")
fontPreload:SetText("Lotus")
fontPreload:SetAlpha(0)

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

-- Tamano de 1 pixel fisico en unidades del frame (bordes nitidos a cualquier escala)
local function Pixel(frame)
	return PixelUtil.GetPixelToUIUnitFactor() / frame:GetEffectiveScale()
end

local function Text(parent, size, justify)
	local fs = parent:CreateFontString(nil, "OVERLAY")
	if not fs:SetFont(FONT, size, "OUTLINE") then
		fs:SetFont(STANDARD_TEXT_FONT, size, "OUTLINE")
	end
	fs:SetShadowColor(0, 0, 0, 0.6)
	fs:SetShadowOffset(1, -1)
	fs:SetJustifyH(justify or "CENTER")
	fs:SetWordWrap(false)
	return fs
end

-- Brillo sutil arriba para dar volumen a las barras planas
local function AddSheen(parent, layer)
	local sheen = parent:CreateTexture(nil, layer or "OVERLAY")
	sheen:SetTexture(FLAT)
	sheen:SetAllPoints()
	if not pcall(sheen.SetGradient, sheen, "VERTICAL", CreateColor(0, 0, 0, 0.25), CreateColor(1, 1, 1, 0.12)) then
		sheen:Hide()
	end
	return sheen
end

local function CreateBar(parent)
	local bar = CreateFrame("StatusBar", nil, parent)
	bar:SetStatusBarTexture(FLAT)
	bar.bg = bar:CreateTexture(nil, "BACKGROUND")
	bar.bg:SetAllPoints()
	bar.bg:SetTexture(FLAT)
	return bar
end

local function SetBarColor(bar, r, g, b)
	bar:SetStatusBarColor(r, g, b)
	bar.bg:SetVertexColor(r * 0.22, g * 0.22, b * 0.22, 1)
end

local function Hex(r, g, b)
	return string.format("|cff%02x%02x%02x", math.floor(r * 255), math.floor(g * 255), math.floor(b * 255))
end

local function GetAura(unit, index, filter)
	if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
		local a = C_UnitAuras.GetAuraDataByIndex(unit, index, filter)
		if a then return a.name, a.icon, a.applications, a.dispelName, a.duration, a.expirationTime end
		return
	end
	local name, icon, count, debuffType, duration, expiration = UnitAura(unit, index, filter)
	return name, icon, count, debuffType, duration, expiration
end

---------------------------------------------------------------------------
-- Actualizaciones
---------------------------------------------------------------------------

local function HealthColor(unit)
	if UnitIsDeadOrGhost(unit) or not UnitIsConnected(unit) then return unpack(COLORS.dead) end
	if UnitIsPlayer(unit) then
		local _, class = UnitClass(unit)
		local c = class and RAID_CLASS_COLORS[class]
		if c then return c.r, c.g, c.b end
	end
	if not UnitPlayerControlled(unit) and UnitIsTapDenied(unit) then return unpack(COLORS.tapped) end
	if UnitIsFriend("player", unit) then return unpack(COLORS.friendly) end
	if UnitReaction(unit, "player") == 4 then return unpack(COLORS.neutral) end
	return unpack(COLORS.hostile)
end

local function UpdateHealth(f)
	local unit = f.unit
	local cur, max = UnitHealth(unit), UnitHealthMax(unit)
	f.health:SetMinMaxValues(0, max > 0 and max or 1)
	f.health:SetValue(cur)
	SetBarColor(f.health, HealthColor(unit))

	if UnitIsGhost(unit) then
		f.healthText:SetText(GHOST or "Fantasma")
	elseif UnitIsDead(unit) then
		f.healthText:SetText(DEAD)
	elseif not UnitIsConnected(unit) then
		f.healthText:SetText(PLAYER_OFFLINE)
	else
		f.healthText:SetFormattedText("%d / %d", cur, max)
	end

	if f.percentText then
		if max > 0 and not UnitIsDeadOrGhost(unit) then
			local pct = math.floor(cur / max * 100 + 0.5)
			f.percentText:SetFormattedText("%d%%", pct)
			-- Debajo de 20% el objetivo esta en rango de Ejecutar
			if pct < EXECUTE_PCT then
				f.percentText:SetTextColor(1, 0.45, 0.1)
			else
				f.percentText:SetTextColor(1, 1, 1)
			end
		else
			f.percentText:SetText("")
		end
	end
end

local function UpdatePower(f)
	local unit = f.unit
	local pType, token = UnitPowerType(unit)
	local cur, max = UnitPower(unit, pType), UnitPowerMax(unit, pType)
	local c = (token and COLORS.power[token]) or (token and PowerBarColor[token]) or COLORS.power.MANA

	SetBarColor(f.power, c.r or c[1], c.g or c[2], c.b or c[3])
	f.power:SetMinMaxValues(0, max > 0 and max or 1)
	f.power:SetValue(max > 0 and cur or 0)

	if max > 0 then
		f.powerText:SetFormattedText("%d / %d", cur, max)
	else
		f.powerText:SetText("")
	end
end

local function UpdateInfo(f)
	local unit = f.unit
	local level = UnitLevel(unit)
	local levelText, r, g, b

	if level and level > 0 then
		levelText = tostring(level)
		if unit ~= "player" and GetCreatureDifficultyColor then
			local c = GetCreatureDifficultyColor(level)
			r, g, b = c.r, c.g, c.b
		else
			r, g, b = 1, 0.82, 0
		end
	else
		levelText, r, g, b = "??", 1, 0.1, 0.1
	end

	if unit ~= "player" then
		local class = UnitClassification(unit)
		if class == "elite" or class == "worldboss" then
			levelText = levelText .. "+"
		elseif class == "rareelite" then
			levelText = levelText .. "R+"
		elseif class == "rare" then
			levelText = levelText .. "R"
		end
	end

	local name = UnitName(unit) or ""
	f.infoText:SetText("") -- fuerza a redibujar aunque el texto sea igual
	if f.mirrored then
		f.infoText:SetText(name .. "  " .. Hex(r, g, b) .. levelText .. "|r")
	else
		f.infoText:SetText(Hex(r, g, b) .. levelText .. "|r  " .. name)
	end
end

local function UpdatePortrait(f)
	local model, unit = f.model, f.unit
	local ready = (not IsUnitModelReadyForUI or IsUnitModelReadyForUI(unit))
	local available = UnitIsConnected(unit) and UnitIsVisible(unit) and ready

	model:ClearModel()
	if available then
		model:SetPortraitZoom(1)
		model:SetPosition(0, 0, 0)
		model:SetUnit(unit)
		model:SetCamDistanceScale(MODEL_CAM_DISTANCE)
	else
		model:SetCamDistanceScale(0.25)
		model:SetPortraitZoom(0)
		model:SetPosition(0, 0, 0.25)
		model:SetModel([[Interface\Buttons\TalkToMeQuestionMark.m2]])
	end
	if model.SetModelAlpha then model:SetModelAlpha(MODEL_ALPHA) end
end

local function UpdateState(f)
	if not f.stateIcon then return end
	if UnitAffectingCombat("player") then
		f.stateIcon:SetTexCoord(0.5, 1, 0, 0.484375)
		f.stateIcon:Show()
	elseif IsResting() then
		f.stateIcon:SetTexCoord(0.0625, 0.4375, 0.0625, 0.4375)
		f.stateIcon:Show()
	else
		f.stateIcon:Hide()
	end
end

-- Las auras del objetivo y del jugador viven en Auras.lua (iconos o barras, configurables)
local function UpdateAuras(f)
	if ns.UpdateAuras then ns.UpdateAuras(f) end
end

local function UpdateCombo(f)
	if not f.combo then return end
	local points = GetComboPoints("player", "target") or 0
	f.combo:SetShown(points > 0)
	for i = 1, 5 do
		f.combo[i]:SetAlpha(i <= points and 1 or 0.15)
	end
end

local function UpdateAll(f)
	if not UnitExists(f.unit) then return end
	-- securecall: si una parte falla, las demas igual se actualizan
	securecall(UpdatePortrait, f)
	securecall(UpdateHealth, f)
	securecall(UpdatePower, f)
	securecall(UpdateInfo, f)
	securecall(UpdateState, f)
	securecall(UpdateAuras, f)
	securecall(UpdateCombo, f)
end

local UNIT_EVENTS = {
	UNIT_HEALTH = UpdateHealth,
	UNIT_HEALTH_FREQUENT = UpdateHealth,
	UNIT_MAXHEALTH = UpdateHealth,
	UNIT_CONNECTION = UpdateHealth,
	UNIT_FACTION = function(f) UpdateHealth(f); UpdateInfo(f) end,
	UNIT_POWER_UPDATE = UpdatePower,
	UNIT_POWER_FREQUENT = UpdatePower,
	UNIT_MAXPOWER = UpdatePower,
	UNIT_DISPLAYPOWER = UpdatePower,
	UNIT_LEVEL = UpdateInfo,
	UNIT_NAME_UPDATE = UpdateInfo,
	UNIT_CLASSIFICATION_CHANGED = UpdateInfo,
	UNIT_AURA = UpdateAuras,
	UNIT_PORTRAIT_UPDATE = UpdatePortrait,
	UNIT_MODEL_CHANGED = UpdatePortrait,
}

local function OnEvent(f, event, ...)
	local handler = UNIT_EVENTS[event]
	if handler then
		handler(f)
	elseif event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" or event == "PLAYER_UPDATE_RESTING" then
		UpdateState(f)
	elseif event == "PLAYER_LEVEL_UP" then
		UpdateInfo(f)
	elseif event == "PLAYER_COMBO_POINTS" then
		UpdateCombo(f)
	else
		UpdateAll(f)
	end
end

---------------------------------------------------------------------------
-- Construccion
---------------------------------------------------------------------------

local function SavePosition(f)
	local point, _, relPoint, x, y = f:GetPoint()
	db[f.unit] = { point, "UIParent", relPoint, x, y }
end

local function ApplyPosition(f)
	local p = db[f.unit] or DEFAULTS[f.unit]
	f:ClearAllPoints()
	f:SetPoint(p[1], _G[p[2]] or UIParent, p[3], p[4], p[5])
end

-- Coloca todo usando el tamano real de un pixel. Se vuelve a llamar si cambia la escala.
local function Layout(f)
	local px = Pixel(f)
	f:SetSize(WIDTH, HEALTH_H + POWER_H + INFO_H + px * 4)

	f.border:SetBackdrop({ bgFile = FLAT, edgeFile = FLAT, edgeSize = px })
	f.border:SetBackdropColor(0, 0, 0, 1)
	f.border:SetBackdropBorderColor(0, 0, 0, 1)
	f.shadow:SetBackdrop({ edgeFile = FLAT, edgeSize = px })
	f.shadow:SetBackdropBorderColor(0, 0, 0, 0.45)
	f.shadow:SetPoint("TOPLEFT", -px, px)
	f.shadow:SetPoint("BOTTOMRIGHT", px, -px)

	f.health:SetPoint("TOPLEFT", px, -px)
	f.health:SetPoint("TOPRIGHT", -px, -px)
	f.health:SetHeight(HEALTH_H)

	f.power:SetPoint("TOPLEFT", f.health, "BOTTOMLEFT", 0, -px)
	f.power:SetPoint("TOPRIGHT", f.health, "BOTTOMRIGHT", 0, -px)
	f.power:SetHeight(POWER_H)

	f.info:SetPoint("TOPLEFT", f.power, "BOTTOMLEFT", 0, -px)
	f.info:SetPoint("TOPRIGHT", f.power, "BOTTOMRIGHT", 0, -px)
	f.info:SetHeight(INFO_H)

	if ns.LayoutAuras then ns.LayoutAuras(f) end

	if f.combo then
		f.combo:SetBackdrop({ bgFile = FLAT, edgeFile = FLAT, edgeSize = px })
		f.combo:SetBackdropColor(0, 0, 0, 1)
		f.combo:SetBackdropBorderColor(0, 0, 0, 1)
		f.combo:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 0, -px * 2)
		f.combo:SetPoint("TOPRIGHT", f, "BOTTOMRIGHT", 0, -px * 2)
		local segment = (WIDTH - px * 6) / 5
		for i, pip in ipairs(f.combo) do
			pip:ClearAllPoints()
			pip:SetPoint("TOPLEFT", f.combo, "TOPLEFT", px + (i - 1) * (segment + px), -px)
			pip:SetPoint("BOTTOMLEFT", f.combo, "BOTTOMLEFT", px + (i - 1) * (segment + px), px)
			pip:SetWidth(segment)
		end
	end
end

local function CreateUnitFrame(unit, mirrored)
	local f = CreateFrame("Button", "LotusFrames_" .. unit, UIParent, "SecureUnitButtonTemplate")
	f.unit, f.mirrored = unit, mirrored
	f:SetFrameStrata("LOW")
	f:SetClampedToScreen(true)

	f:SetAttribute("unit", unit)
	f:SetAttribute("*type1", "target")
	f:SetAttribute("*type2", "togglemenu")
	f:RegisterForClicks("AnyUp")

	-- Shift + arrastrar para mover, o arrastrar libre con el Modo de edicion de Blizzard abierto
	f:SetMovable(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", function(self)
		if (IsShiftKeyDown() or ns.editing) and not InCombatLockdown() then self:StartMoving() end
	end)
	f:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		SavePosition(self)
	end)
	f:SetScript("OnEnter", function(self)
		GameTooltip_SetDefaultAnchor(GameTooltip, self)
		GameTooltip:SetUnit(self.unit)
	end)
	f:SetScript("OnLeave", GameTooltip_Hide)

	local near = mirrored and "RIGHT" or "LEFT"
	local far  = mirrored and "LEFT" or "RIGHT"

	-- Fondo negro + borde de 1px + sombra exterior
	f.shadow = CreateFrame("Frame", nil, f, "BackdropTemplate")
	f.shadow:SetFrameLevel(f:GetFrameLevel())
	f.border = CreateFrame("Frame", nil, f, "BackdropTemplate")
	f.border:SetAllPoints()
	f.border:SetFrameLevel(f:GetFrameLevel())

	-- Vida
	f.health = CreateBar(f)
	f.health:SetFrameLevel(f:GetFrameLevel() + 1)
	if mirrored then f.health:SetReverseFill(true) end

	-- Retrato 3D encima de la barra de vida, semitransparente (como ElvUI "overlay")
	f.model = CreateFrame("PlayerModel", nil, f.health)
	f.model:SetAllPoints(f.health)
	f.model:SetFrameLevel(f.health:GetFrameLevel() + 1)
	if f.model.SetIgnoreParentAlpha then f.model:SetIgnoreParentAlpha(true) end

	-- Capa de textos por encima del modelo
	local healthOverlay = CreateFrame("Frame", nil, f.health)
	healthOverlay:SetAllPoints()
	healthOverlay:SetFrameLevel(f.model:GetFrameLevel() + 1)
	AddSheen(healthOverlay, "BACKGROUND")

	f.healthText = Text(healthOverlay, 15, far)
	f.healthText:SetPoint(far, healthOverlay, far, mirrored and 6 or -6, 0)

	-- Poder (Ira, Mana, Energia)
	f.power = CreateBar(f)
	f.power:SetFrameLevel(f:GetFrameLevel() + 1)
	if mirrored then f.power:SetReverseFill(true) end
	AddSheen(f.power)
	f.powerText = Text(f.power, 11, far)
	f.powerText:SetPoint(far, f.power, far, mirrored and 6 or -6, 0)

	-- Panel de info: nivel + nombre
	f.info = CreateFrame("Frame", nil, f)
	f.info:SetFrameLevel(f:GetFrameLevel() + 1)
	local infoBg = f.info:CreateTexture(nil, "BACKGROUND")
	infoBg:SetAllPoints()
	infoBg:SetColorTexture(0.07, 0.07, 0.08, 0.92)
	f.infoText = Text(f.info, 13, near)
	f.infoText:SetPoint(near, f.info, near, mirrored and -6 or 6, 0)
	f.infoText:SetPoint(far, f.info, far, mirrored and 26 or -26, 0)

	f:SetScript("OnEvent", OnEvent)
	for event in pairs(UNIT_EVENTS) do
		-- algunos eventos no existen en todas las versiones del cliente
		pcall(f.RegisterUnitEvent, f, event, unit)
	end
	f:HookScript("OnShow", UpdateAll)

	return f
end

local function CreatePlayerFrame()
	local f = CreateUnitFrame("player", false)
	ns.CreateAuras(f)

	-- Icono de combate / descansando en el panel de info
	f.stateIcon = f.info:CreateTexture(nil, "OVERLAY")
	f.stateIcon:SetTexture(STATE_ICONS)
	f.stateIcon:SetSize(16, 16)
	f.stateIcon:SetPoint("RIGHT", f.info, "RIGHT", -4, 0)
	f.stateIcon:Hide()

	f:RegisterEvent("PLAYER_ENTERING_WORLD")
	f:RegisterEvent("PLAYER_REGEN_DISABLED")
	f:RegisterEvent("PLAYER_REGEN_ENABLED")
	f:RegisterEvent("PLAYER_UPDATE_RESTING")
	f:RegisterEvent("PLAYER_LEVEL_UP")
	return f
end

local function CreateTargetFrame()
	local f = CreateUnitFrame("target", true)
	ns.CreateAuras(f)

	-- Porcentaje de vida del lado opuesto (naranja en rango de Ejecutar)
	local overlay = f.healthText:GetParent()
	f.percentText = Text(overlay, 13, "RIGHT")
	f.percentText:SetPoint("RIGHT", overlay, "RIGHT", -6, 0)

	-- Puntos de combo (picaro / druida gato) como barra segmentada debajo
	f.combo = CreateFrame("Frame", nil, f, "BackdropTemplate")
	f.combo:SetHeight(7)
	f.combo:Hide()
	for i = 1, 5 do
		local pip = f.combo:CreateTexture(nil, "ARTWORK")
		pip:SetTexture(FLAT)
		pip:SetVertexColor(1, 0.82, 0.15)
		f.combo[i] = pip
	end

	f:RegisterEvent("PLAYER_TARGET_CHANGED")
	pcall(f.RegisterEvent, f, "PLAYER_COMBO_POINTS")
	f:RegisterEvent("UNIT_POWER_FREQUENT") -- combo points en clientes modernos (unidad "player")
	f:SetScript("OnEvent", function(self, event, ...)
		if event == "UNIT_POWER_FREQUENT" and ... == "player" then
			UpdateCombo(self)
		elseif event ~= "UNIT_POWER_FREQUENT" or ... == "target" then
			OnEvent(self, event, ...)
		end
	end)

	RegisterUnitWatch(f)
	return f
end

---------------------------------------------------------------------------
-- Esconder los marcos de Blizzard (mismo metodo que oUF/ElvUI)
---------------------------------------------------------------------------

local hiddenParent = CreateFrame("Frame", nil, UIParent)
hiddenParent:Hide()

local function HideBlizzard(frame)
	if not frame then return end
	frame:UnregisterAllEvents()
	frame:Hide()
	frame:SetParent(hiddenParent)
	for _, key in ipairs({ "healthbar", "manabar", "spellbar" }) do
		if frame[key] then frame[key]:UnregisterAllEvents() end
	end
end

---------------------------------------------------------------------------
-- Inicio
---------------------------------------------------------------------------

local function ApplyScale()
	for _, f in pairs(frames) do
		f:SetScale(db.scale)
		Layout(f)
	end
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:RegisterEvent("PLAYER_LOGIN")
loader:RegisterEvent("PLAYER_REGEN_ENABLED")
loader:RegisterEvent("UI_SCALE_CHANGED")
loader:RegisterEvent("DISPLAY_SIZE_CHANGED")
loader:SetScript("OnEvent", function(self, event, arg1)
	if event == "ADDON_LOADED" and arg1 == ADDON then
		LotusFramesDB = LotusFramesDB or {}
		db = LotusFramesDB
		db.scale = db.scale or DEFAULTS.scale
		ns.InitAuraDB(db)
	elseif event == "UI_SCALE_CHANGED" or event == "DISPLAY_SIZE_CHANGED" then
		if frames.player and not InCombatLockdown() then ApplyScale() end
	elseif event == "PLAYER_LOGIN" or (event == "PLAYER_REGEN_ENABLED" and self.pending) then
		if InCombatLockdown() then
			self.pending = true
			return
		end
		self.pending = nil
		self:UnregisterEvent("PLAYER_REGEN_ENABLED")

		HideBlizzard(PlayerFrame)
		HideBlizzard(TargetFrame)
		HideBlizzard(ComboFrame)

		frames.player = CreatePlayerFrame()
		frames.target = CreateTargetFrame()
		CreateEditOverlay(frames.player, "Jugador")
		CreateEditOverlay(frames.target, "Objetivo")
		ApplyScale()
		for _, f in pairs(frames) do ApplyPosition(f) end
		UpdateAll(frames.player)
		-- segunda pasada cuando el mundo y la fuente ya terminaron de cargar
		C_Timer.After(1, function()
			for _, f in pairs(frames) do UpdateAll(f) end
		end)
	end
end)

---------------------------------------------------------------------------
-- Modo de edicion de Blizzard (Menu principal > Modo de edicion)
-- Mientras esta abierto, los marcos se resaltan como los de Blizzard y se arrastran libres.
---------------------------------------------------------------------------

function CreateEditOverlay(f, label)
	local o = CreateFrame("Frame", nil, f, "BackdropTemplate")
	o:SetPoint("TOPLEFT", -2, 2)
	o:SetPoint("BOTTOMRIGHT", 2, -2)
	o:SetFrameLevel(f:GetFrameLevel() + 30)
	o:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 2 })
	o:SetBackdropColor(0.25, 0.65, 0.85, 0.35)
	o:SetBackdropBorderColor(0.55, 0.85, 1, 0.9)
	local text = o:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	text:SetPoint("CENTER")
	text:SetText(label)
	o:Hide()
	f.editOverlay = o
end

local function SetEditing(on)
	if not frames.player or InCombatLockdown() or on == ns.editing then return end
	ns.editing = on
	for _, f in pairs(frames) do f.editOverlay:SetShown(on) end
	-- el objetivo se muestra aunque no tengas objetivo, para poder ubicarlo
	if on then
		UnregisterUnitWatch(frames.target)
		frames.target:Show()
	else
		RegisterUnitWatch(frames.target)
	end
end

local editModeHooked = false
local function HookEditMode()
	if editModeHooked or not EditModeManagerFrame then return end
	editModeHooked = true
	EditModeManagerFrame:HookScript("OnShow", function() SetEditing(true) end)
	EditModeManagerFrame:HookScript("OnHide", function() SetEditing(false) end)
end
HookEditMode()

local editEvents = CreateFrame("Frame")
editEvents:RegisterEvent("PLAYER_REGEN_DISABLED")
editEvents:RegisterEvent("ADDON_LOADED") -- por si el modo de edicion se carga despues
editEvents:RegisterEvent("PLAYER_LOGIN")
editEvents:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_REGEN_DISABLED" then
		SetEditing(false) -- al entrar en combate
	else
		HookEditMode()
	end
end)

-- Para Auras.lua y Options.lua
ns.FLAT, ns.Text, ns.GetAura, ns.Pixel, ns.frames, ns.WIDTH = FLAT, Text, GetAura, Pixel, frames, WIDTH
ns.GetDB = function() return db end
-- Vista previa sin objetivo: datos de ejemplo en vez de barras vacias
function ns.PaintPreview(f)
	local hr, hg, hb = unpack(COLORS.hostile)
	f.health:SetMinMaxValues(0, 1000)
	f.health:SetValue(650)
	SetBarColor(f.health, hr, hg, hb)
	f.healthText:SetText("650 / 1000")
	if f.percentText then
		f.percentText:SetText("65%")
		f.percentText:SetTextColor(1, 1, 1)
	end
	local pr, pg, pb = unpack(COLORS.power.RAGE)
	f.power:SetMinMaxValues(0, 100)
	f.power:SetValue(40)
	SetBarColor(f.power, pr, pg, pb)
	f.powerText:SetText("40 / 100")
	f.infoText:SetText("Objetivo de ejemplo  |cffffd10013|r")
	f.model:ClearModel()
	f.model:SetUnit("player")
	if f.combo then f.combo:Hide() end
end

function ns.RefreshAuras()
	for _, f in pairs(frames) do
		ns.LayoutAuras(f)
		ns.UpdateAuras(f)
	end
end

SLASH_LOTUSFRAMES1 = "/lotus"
SlashCmdList.LOTUSFRAMES = function(msg)
	local cmd, arg = strsplit(" ", strlower(msg or ""), 2)
	if InCombatLockdown() and cmd ~= "auras" then
		print("|cffffd100LotusFrames|r: no se puede en combate.")
		return
	end
	if cmd == "auras" then
		-- diagnostico: lo que el juego reporta de las auras del objetivo
		if not UnitExists("target") then print("|cffffd100LotusFrames|r: selecciona un objetivo primero.") return end
		for _, filter in ipairs({ "HARMFUL", "HELPFUL" }) do
			local n = 0
			for i = 1, 40 do
				local name, _, count, dtype, duration, expiration = GetAura("target", i, filter)
				if not name then break end
				n = n + 1
				print(("  %s %d: %s  x%s  tipo=%s  duracion=%s  fin=%s"):format(filter, i, name, tostring(count),
					tostring(dtype), tostring(duration), tostring(expiration)))
			end
			print(("|cffffd100LotusFrames|r: %s = %d"):format(filter, n))
		end
		if ns.lastAuraError then print("  ultimo error: " .. tostring(ns.lastAuraError)) end
	elseif cmd == "opciones" or cmd == "options" or cmd == "config" then
		ns.OpenOptions()
	elseif cmd == "reset" then
		db.player, db.target, db.scale = nil, nil, 1
		ApplyScale()
		for _, f in pairs(frames) do ApplyPosition(f) end
		print("|cffffd100LotusFrames|r: posiciones y escala reiniciadas.")
	elseif cmd == "scale" and tonumber(arg) then
		db.scale = math.min(math.max(tonumber(arg), 0.5), 2)
		ApplyScale()
		print("|cffffd100LotusFrames|r: escala " .. db.scale)
	else
		print("|cffffd100LotusFrames|r comandos:")
		print("  Shift + arrastrar un marco para moverlo (o arrastrarlo con el Modo de edicion abierto)")
		print("  /lotus scale 1.2  - cambiar tamano (0.5 - 2)")
		print("  /lotus reset      - volver a la posicion original")
		print("  /lotus opciones   - opciones de auras (tambien en Opciones > AddOns)")
	end
end
