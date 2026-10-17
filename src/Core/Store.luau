--[[
	Owns all persisted state: profiles (bindings + tuning) and global settings.

	Data lives in plugin settings under SETTINGS_KEY, so it follows the user
	across places. Everything that comes back from storage or an import is
	sanitized against the current action / input / tuning catalogs, which also
	migrates data saved by older versions (new actions get their defaults).
]]

local HttpService = game:GetService("HttpService")

local Actions = require(script.Parent.Actions)
local Inputs = require(script.Parent.Inputs)
local Tuning = require(script.Parent.Tuning)
local Signal = require(script.Parent.Parent.Util.Signal)

local SETTINGS_KEY = "StudioControllerPro.Data.v1"
local EXPORT_FORMAT = "StudioControllerPro.Profile"
local SCHEMA = 1
local MAX_PROFILES = 32
local MAX_NAME_LENGTH = 32

export type Binding = Actions.Binding

export type Profile = {
	id: string,
	name: string,
	preset: string?,
	bindings: { [string]: Binding | false },
	tuning: { [string]: any },
}

type Preset = {
	id: string,
	name: string,
	tuning: { [string]: any }?,
	bindings: { [string]: Binding | false }?,
}

local PRESETS: { Preset } = {
	{ id = "default", name = "Default" },
	{
		id = "cinematic",
		name = "Cinematic",
		tuning = {
			moveSpeed = 14,
			lookSpeed = 55,
			rollSpeed = 20,
			fovSpeed = 12,
			moveSmoothing = 0.85,
			lookSmoothing = 0.8,
			curve = 2.2,
			precisionMultiplier = 0.3,
		},
	},
	{
		id = "builder",
		name = "Builder",
		tuning = {
			moveSpeed = 64,
			lookSpeed = 200,
			moveSmoothing = 0.15,
			lookSmoothing = 0.1,
			curve = 1.3,
			boostMultiplier = 4,
		},
	},
	{
		id = "southpaw",
		name = "Southpaw",
		bindings = {
			move = { key = "Thumbstick2" },
			look = { key = "Thumbstick1" },
			boost = { key = "ButtonR3" },
			resetRoll = { key = "ButtonL3" },
		},
	},
}

local PRESETS_BY_ID = {}
for _, preset in PRESETS do
	PRESETS_BY_ID[preset.id] = preset
end

local Store = {}
Store.__index = Store
Store.Presets = PRESETS

local function sanitizeName(name: any, fallback: string): string
	if type(name) ~= "string" then
		return fallback
	end
	name = string.gsub(name, "[%c]", "")
	name = string.match(name, "^%s*(.-)%s*$") or ""
	if name == "" then
		return fallback
	end
	if utf8.len(name) and (utf8.len(name) :: number) > MAX_NAME_LENGTH then
		name = string.sub(name, 1, utf8.offset(name, MAX_NAME_LENGTH + 1) - 1)
	end
	return name
end

local function sanitizeBinding(action: Actions.Action, raw: any): Binding | false | nil
	if raw == false then
		return false
	end
	if type(raw) ~= "table" or not Inputs.IsValid(raw.key) then
		return nil
	end
	local info = Inputs.ByKey[raw.key]
	if (action.kind == "stick") ~= (info.kind == "stick") then
		return nil
	end
	local mod = raw.mod
	if mod ~= nil then
		if not Inputs.IsValid(mod) or Inputs.ByKey[mod].kind == "stick" or mod == raw.key then
			mod = nil
		end
	end
	return { key = raw.key, mod = mod }
end

local function presetBindings(presetId: string?): { [string]: Binding | false }
	local bindings = Actions.DefaultBindings()
	local preset = presetId and PRESETS_BY_ID[presetId]
	if preset and preset.bindings then
		for actionId, binding in preset.bindings do
			bindings[actionId] = if binding then table.clone(binding) else false
		end
	end
	return bindings
end

local function presetTuning(presetId: string?): { [string]: any }
	local preset = presetId and PRESETS_BY_ID[presetId]
	return Tuning.Defaults(preset and preset.tuning)
end

local function sanitizeProfile(raw: any, fallbackName: string): Profile
	raw = if type(raw) == "table" then raw else {}
	local preset = if type(raw.preset) == "string" and PRESETS_BY_ID[raw.preset] then raw.preset else nil
	local defaults = presetBindings(preset)
	local bindings = {}
	local rawBindings = if type(raw.bindings) == "table" then raw.bindings else {}
	for _, action in Actions.List do
		local binding = sanitizeBinding(action, rawBindings[action.id])
		if binding == nil then
			binding = defaults[action.id]
		end
		bindings[action.id] = binding
	end

	local baseTuning = presetTuning(preset)
	local tuning = {}
	local rawTuning = if type(raw.tuning) == "table" then raw.tuning else {}
	for _, spec in Tuning.Profile do
		local value = rawTuning[spec.key]
		tuning[spec.key] = if value == nil then baseTuning[spec.key] else Tuning.Sanitize(spec, value)
	end

	return {
		id = if type(raw.id) == "string" and #raw.id > 0 then raw.id else HttpService:GenerateGUID(false),
		name = sanitizeName(raw.name, fallbackName),
		preset = preset,
		bindings = bindings,
		tuning = tuning,
	}
end

local function newPresetProfile(preset: Preset): Profile
	return {
		id = HttpService:GenerateGUID(false),
		name = preset.name,
		preset = preset.id,
		bindings = presetBindings(preset.id),
		tuning = presetTuning(preset.id),
	}
end

local function defaultData()
	local profiles = {}
	for _, preset in PRESETS do
		table.insert(profiles, newPresetProfile(preset))
	end
	return {
		schema = SCHEMA,
		activeProfileId = profiles[1].id,
		profiles = profiles,
		settings = Tuning.GlobalDefaults(),
		runtime = { speedIndex = 5, gamepad = "Auto" },
	}
end

local function sanitizeData(raw: any)
	if type(raw) ~= "table" or type(raw.profiles) ~= "table" or #raw.profiles == 0 then
		return defaultData()
	end
	local data = defaultData()
	data.profiles = {}
	local seenIds = {}
	for index, rawProfile in raw.profiles do
		if #data.profiles >= MAX_PROFILES then
			break
		end
		local profile = sanitizeProfile(rawProfile, "Profile " .. index)
		if seenIds[profile.id] then
			profile.id = HttpService:GenerateGUID(false)
		end
		seenIds[profile.id] = true
		table.insert(data.profiles, profile)
	end
	data.activeProfileId = if seenIds[raw.activeProfileId] then raw.activeProfileId else data.profiles[1].id

	local rawSettings = if type(raw.settings) == "table" then raw.settings else {}
	for _, spec in Tuning.Global do
		data.settings[spec.key] = Tuning.Sanitize(spec, rawSettings[spec.key])
	end

	local rawRuntime = if type(raw.runtime) == "table" then raw.runtime else {}
	if type(rawRuntime.speedIndex) == "number" then
		data.runtime.speedIndex = math.floor(rawRuntime.speedIndex)
	end
	if type(rawRuntime.gamepad) == "string" then
		data.runtime.gamepad = rawRuntime.gamepad
	end
	return data
end

function Store.new(plugin: Plugin?)
	local self = setmetatable({}, Store)
	self._plugin = plugin
	self._saveQueued = false
	-- Fired with (kind: string, ...) where kind is "profile", "bindings",
	-- "tuning", "settings", "profiles" or "runtime".
	self.Changed = Signal.new()

	local raw = nil
	if plugin then
		local ok, result = pcall(plugin.GetSetting, plugin, SETTINGS_KEY)
		if ok then
			raw = result
		else
			warn("[Studio Controller Pro] Couldn't read saved settings:", result)
		end
	end
	self.data = sanitizeData(raw)
	return self
end

function Store:_queueSave()
	if not self._plugin or self._saveQueued then
		return
	end
	self._saveQueued = true
	task.delay(0.4, function()
		self._saveQueued = false
		self:SaveNow()
	end)
end

function Store:SaveNow()
	if not self._plugin then
		return
	end
	local ok, err = pcall(self._plugin.SetSetting, self._plugin, SETTINGS_KEY, self.data)
	if not ok then
		warn("[Studio Controller Pro] Couldn't save settings:", err)
	end
end

function Store:_changed(kind: string, ...)
	self:_queueSave()
	self.Changed:Fire(kind, ...)
end

-- Profiles -------------------------------------------------------------------

function Store:GetProfiles(): { Profile }
	return self.data.profiles
end

function Store:GetProfile(id: string): Profile?
	for _, profile in self.data.profiles do
		if profile.id == id then
			return profile
		end
	end
	return nil
end

function Store:GetActiveProfile(): Profile
	return self:GetProfile(self.data.activeProfileId) or self.data.profiles[1]
end

function Store:SetActiveProfile(id: string)
	if self.data.activeProfileId == id or not self:GetProfile(id) then
		return
	end
	self.data.activeProfileId = id
	self:_changed("profile", id)
end

function Store:CycleProfile(direction: number): Profile
	local profiles = self.data.profiles
	local current = table.find(profiles, self:GetActiveProfile()) or 1
	local nextIndex = (current - 1 + direction) % #profiles + 1
	self:SetActiveProfile(profiles[nextIndex].id)
	return profiles[nextIndex]
end

function Store:_uniqueName(base: string): string
	local taken = {}
	for _, profile in self.data.profiles do
		taken[string.lower(profile.name)] = true
	end
	if not taken[string.lower(base)] then
		return base
	end
	local stem = string.gsub(base, "%s%(%d+%)$", "")
	for n = 2, 999 do
		local candidate = sanitizeName(string.format("%s (%d)", stem, n), base)
		if not taken[string.lower(candidate)] then
			return candidate
		end
	end
	return base
end

function Store:CanAddProfile(): boolean
	return #self.data.profiles < MAX_PROFILES
end

function Store:CreateProfile(name: string?): Profile?
	if not self:CanAddProfile() then
		return nil
	end
	local profile = newPresetProfile(PRESETS[1])
	profile.name = self:_uniqueName(sanitizeName(name, "New profile"))
	table.insert(self.data.profiles, profile)
	self.data.activeProfileId = profile.id
	self:_changed("profiles")
	self.Changed:Fire("profile", profile.id)
	return profile
end

function Store:DuplicateProfile(id: string): Profile?
	local source = self:GetProfile(id)
	if not source or not self:CanAddProfile() then
		return nil
	end
	local copy = sanitizeProfile({
		name = self:_uniqueName(source.name .. " copy"),
		preset = source.preset,
		bindings = source.bindings,
		tuning = source.tuning,
	}, "Profile")
	table.insert(self.data.profiles, (table.find(self.data.profiles, source) :: number) + 1, copy)
	self.data.activeProfileId = copy.id
	self:_changed("profiles")
	self.Changed:Fire("profile", copy.id)
	return copy
end

function Store:RenameProfile(id: string, name: string): boolean
	local profile = self:GetProfile(id)
	if not profile then
		return false
	end
	local clean = sanitizeName(name, profile.name)
	if clean == profile.name then
		return false
	end
	profile.name = clean
	self:_changed("profiles")
	return true
end

function Store:DeleteProfile(id: string): boolean
	local profiles = self.data.profiles
	if #profiles <= 1 then
		return false
	end
	local profile = self:GetProfile(id)
	if not profile then
		return false
	end
	local index = table.find(profiles, profile) :: number
	table.remove(profiles, index)
	local wasActive = self.data.activeProfileId == id
	if wasActive then
		self.data.activeProfileId = profiles[math.min(index, #profiles)].id
	end
	self:_changed("profiles")
	if wasActive then
		self.Changed:Fire("profile", self.data.activeProfileId)
	end
	return true
end

function Store:MoveProfile(id: string, direction: number)
	local profiles = self.data.profiles
	local profile = self:GetProfile(id)
	if not profile then
		return
	end
	local index = table.find(profiles, profile) :: number
	local target = index + direction
	if target < 1 or target > #profiles then
		return
	end
	profiles[index], profiles[target] = profiles[target], profiles[index]
	self:_changed("profiles")
end

function Store:ResetBindings(id: string)
	local profile = self:GetProfile(id)
	if not profile then
		return
	end
	profile.bindings = presetBindings(profile.preset)
	self:_changed("bindings", id)
end

function Store:ResetTuning(id: string)
	local profile = self:GetProfile(id)
	if not profile then
		return
	end
	profile.tuning = presetTuning(profile.preset)
	self:_changed("tuning", id)
end

-- Bindings -------------------------------------------------------------------

local function sameBinding(a: Binding, b: Binding): boolean
	return a.key == b.key and a.mod == b.mod
end

-- Assigns a binding and unbinds any other action that used the exact same
-- input, returning the ids of the actions that lost their binding.
function Store:SetBinding(profileId: string, actionId: string, binding: Binding | false): { string }
	local profile = self:GetProfile(profileId)
	local action = Actions.ById[actionId]
	if not profile or not action then
		return {}
	end
	local clean = sanitizeBinding(action, binding)
	if clean == nil then
		return {}
	end
	local displaced = {}
	if clean then
		for otherId, other in profile.bindings do
			if otherId ~= actionId and other and sameBinding(other, clean) then
				profile.bindings[otherId] = false
				table.insert(displaced, otherId)
			end
		end
	end
	profile.bindings[actionId] = clean
	self:_changed("bindings", profileId)
	return displaced
end

-- Tuning & settings ----------------------------------------------------------

function Store:SetTuning(profileId: string, key: string, value: any)
	local profile = self:GetProfile(profileId)
	local spec = Tuning.ByKey[key]
	if not profile or not spec then
		return
	end
	local clean = Tuning.Sanitize(spec, value)
	if profile.tuning[key] == clean then
		return
	end
	profile.tuning[key] = clean
	self:_changed("tuning", profileId, key)
end

function Store:GetSetting(key: string): any
	return self.data.settings[key]
end

function Store:SetSetting(key: string, value: any)
	local spec = Tuning.GlobalByKey[key]
	if not spec then
		return
	end
	local clean = Tuning.Sanitize(spec, value)
	if self.data.settings[key] == clean then
		return
	end
	self.data.settings[key] = clean
	self:_changed("settings", key)
end

function Store:GetRuntime(key: string): any
	return self.data.runtime[key]
end

function Store:SetRuntime(key: string, value: any)
	if self.data.runtime[key] == value then
		return
	end
	self.data.runtime[key] = value
	self:_changed("runtime", key)
end

-- Import / export ------------------------------------------------------------

function Store:Export(profileId: string): string?
	local profile = self:GetProfile(profileId)
	if not profile then
		return nil
	end
	local bindings = {}
	for _, action in Actions.List do
		local binding = profile.bindings[action.id]
		bindings[action.id] = if binding then { key = binding.key, mod = binding.mod } else false
	end
	return HttpService:JSONEncode({
		format = EXPORT_FORMAT,
		version = SCHEMA,
		name = profile.name,
		bindings = bindings,
		tuning = profile.tuning,
	})
end

function Store:Import(json: string): (Profile?, string?)
	if type(json) ~= "string" or not string.find(json, "%S") then
		return nil, "Paste a profile first."
	end
	local ok, decoded = pcall(HttpService.JSONDecode, HttpService, json)
	if not ok or type(decoded) ~= "table" then
		return nil, "That isn't valid JSON."
	end
	if decoded.format ~= EXPORT_FORMAT then
		return nil, "That isn't a Studio Controller Pro profile."
	end
	if type(decoded.version) == "number" and decoded.version > SCHEMA then
		return nil, "That profile is from a newer version of the plugin."
	end
	if not self:CanAddProfile() then
		return nil, string.format("You can keep up to %d profiles. Delete one first.", MAX_PROFILES)
	end
	local profile = sanitizeProfile({
		name = decoded.name,
		bindings = decoded.bindings,
		tuning = decoded.tuning,
	}, "Imported profile")
	profile.id = HttpService:GenerateGUID(false)
	profile.name = self:_uniqueName(profile.name)
	table.insert(self.data.profiles, profile)
	self.data.activeProfileId = profile.id
	self:_changed("profiles")
	self.Changed:Fire("profile", profile.id)
	return profile, nil
end

Store.MaxNameLength = MAX_NAME_LENGTH
Store._sanitizeData = sanitizeData

return Store
