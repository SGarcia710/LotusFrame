-- LotusFrames: panel de opciones (Opciones > AddOns > LotusFrames)

local _, ns = ...

local panel = CreateFrame("Frame")
panel.name = "LotusFrames"
panel:Hide()

local widgets = {}
local function Opt() return ns.GetDB().auras end

local function Changed()
	ns.RefreshAuras()
end

---------------------------------------------------------------------------
-- Controles (hechos a mano para no depender de plantillas que cambian entre versiones)
---------------------------------------------------------------------------

local function Label(parent, text, size, r, g, b)
	local fs = parent:CreateFontString(nil, "ARTWORK", size == "big" and "GameFontNormalLarge" or "GameFontHighlight")
	fs:SetText(text)
	if r then fs:SetTextColor(r, g, b) end
	return fs
end

local function Checkbox(key, text, x, y, onChange)
	local cb = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
	cb:SetSize(26, 26)
	cb:SetPoint("TOPLEFT", x, y)
	local label = Label(panel, text)
	label:SetPoint("LEFT", cb, "RIGHT", 4, 1)
	cb:SetScript("OnClick", function(self)
		Opt()[key] = self:GetChecked() and true or false
		if onChange then onChange() end
		Changed()
	end)
	cb.Refresh = function(self) self:SetChecked(Opt()[key]) end
	widgets[#widgets + 1] = cb
	return cb
end

-- Dos casillas que funcionan como opcion unica (Iconos / Barras)
local function Radio(key, value, text, x, y)
	local cb = CreateFrame("CheckButton", nil, panel, "UIRadioButtonTemplate")
	cb:SetPoint("TOPLEFT", x, y)
	local label = Label(panel, text)
	label:SetPoint("LEFT", cb, "RIGHT", 4, 1)
	cb:SetScript("OnClick", function()
		Opt()[key] = value
		for _, w in ipairs(widgets) do w:Refresh() end
		Changed()
	end)
	cb.Refresh = function(self) self:SetChecked(Opt()[key] == value) end
	widgets[#widgets + 1] = cb
	return cb
end

local function Slider(key, text, minV, maxV, x, y)
	local label = Label(panel, text)
	label:SetPoint("TOPLEFT", x, y)
	local s = CreateFrame("Slider", nil, panel, "BackdropTemplate")
	s:SetOrientation("HORIZONTAL")
	s:SetSize(240, 17)
	s:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -6)
	s:SetBackdrop({
		bgFile = "Interface\\Buttons\\UI-SliderBar-Background",
		edgeFile = "Interface\\Buttons\\UI-SliderBar-Border",
		tile = true, tileSize = 8, edgeSize = 8,
		insets = { left = 3, right = 3, top = 6, bottom = 6 },
	})
	s:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
	s:SetMinMaxValues(minV, maxV)
	s:SetValueStep(1)
	s:SetObeyStepOnDrag(true)
	local value = Label(panel, "")
	value:SetPoint("LEFT", s, "RIGHT", 10, 0)
	local low = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	low:SetPoint("TOPLEFT", s, "BOTTOMLEFT", 2, 0)
	low:SetText(minV)
	local high = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	high:SetPoint("TOPRIGHT", s, "BOTTOMRIGHT", -2, 0)
	high:SetText(maxV)
	s:SetScript("OnValueChanged", function(self, v)
		v = math.floor(v + 0.5)
		value:SetText(v)
		if self.refreshing or Opt()[key] == v then return end
		Opt()[key] = v
		Changed()
	end)
	s.Refresh = function(self)
		self.refreshing = true
		self:SetValue(Opt()[key])
		value:SetText(Opt()[key])
		self.refreshing = false
	end
	widgets[#widgets + 1] = s
	return s
end

---------------------------------------------------------------------------
-- Contenido del panel
---------------------------------------------------------------------------

local title = Label(panel, "LotusFrames", "big")
title:SetPoint("TOPLEFT", 16, -16)
local subtitle = Label(panel, "Auras (beneficios y perjuicios) encima del marco del objetivo.", nil, 0.8, 0.8, 0.8)
subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)

Checkbox("enabled", "Mostrar auras del objetivo", 16, -64)

local styleTitle = Label(panel, "Estilo", nil, 1, 0.82, 0)
styleTitle:SetPoint("TOPLEFT", 20, -104)
Radio("style", "icons", "Iconos (contador dentro y animación de reloj)", 20, -124)
Radio("style", "bars", "Barras (ícono, nombre, tiempo y barra que se vacía)", 20, -148)

local showTitle = Label(panel, "Qué mostrar", nil, 1, 0.82, 0)
showTitle:SetPoint("TOPLEFT", 20, -186)
Checkbox("debuffs", "Perjuicios", 16, -204)
Checkbox("onlyMine", "Solo mis perjuicios (p. ej. tu Hender armadura)", 36, -230)
Checkbox("buffs", "Beneficios", 16, -256)
Checkbox("showTimer", "Mostrar el tiempo restante", 16, -282)

local sizeTitle = Label(panel, "Tamaño", nil, 1, 0.82, 0)
sizeTitle:SetPoint("TOPLEFT", 20, -322)
Slider("size", "Tamaño de los íconos", 16, 44, 20, -346)
Slider("perRow", "Íconos por fila", 3, 12, 20, -400)
Slider("barHeight", "Alto de las barras", 12, 32, 330, -346)
Slider("max", "Máximo de auras", 4, 32, 330, -400)

local previewBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
previewBtn:SetSize(200, 26)
previewBtn:SetPoint("TOPLEFT", 20, -460)
previewBtn:SetScript("OnClick", function(self)
	if InCombatLockdown() then
		print("|cffffd100LotusFrames|r: la vista previa no se puede usar en combate.")
		return
	end
	local ok, err = pcall(ns.SetAuraPreview, not ns.preview)
	if not ok then print("|cffff4040LotusFrames error:|r " .. tostring(err)) end
	self:SetText(ns.preview and "Ocultar vista previa" or "Vista previa")
end)
local previewHelp = Label(panel, "Muestra auras de ejemplo en el marco del objetivo para probar los ajustes.", nil, 0.7, 0.7, 0.7)
previewHelp:SetPoint("LEFT", previewBtn, "RIGHT", 10, 0)

panel:SetScript("OnShow", function()
	for _, w in ipairs(widgets) do w:Refresh() end
	previewBtn:SetText(ns.preview and "Ocultar vista previa" or "Vista previa")
end)
-- al cerrar las opciones se apaga la vista previa
panel:SetScript("OnHide", function()
	if ns.preview then ns.SetAuraPreview(false) end
end)

---------------------------------------------------------------------------
-- Registro en Opciones > AddOns
---------------------------------------------------------------------------

local category
if Settings and Settings.RegisterCanvasLayoutCategory then
	category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
	Settings.RegisterAddOnCategory(category)
elseif InterfaceOptions_AddCategory then
	InterfaceOptions_AddCategory(panel)
end

function ns.OpenOptions()
	if category and Settings.OpenToCategory then
		Settings.OpenToCategory(category:GetID())
	elseif InterfaceOptionsFrame_OpenToCategory then
		InterfaceOptionsFrame_OpenToCategory(panel)
		InterfaceOptionsFrame_OpenToCategory(panel) -- la primera vez a veces no abre la categoria
	end
end
