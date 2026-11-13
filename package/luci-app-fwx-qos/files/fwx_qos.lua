module("luci.controller.fwx_qos", package.seeall)

local http = require "luci.http"
local json = require "luci.jsonc"
local translate = require("luci.i18n").translate
local util = require "luci.util"

local function json_out(data)
	http.prepare_content("application/json")
	http.write(json.stringify(data))
end

local function shell(cmd)
	local p = io.popen(cmd .. " 2>/dev/null")
	if not p then return "" end
	local out = p:read("*a") or ""
	p:close()
	return out
end

-- 解析 uci show 输出: { name = { type = "...", options = { ... } } }
local function read_config()
	local sections = {}
	for line in shell("uci -q show fwx_qos"):gmatch("[^\n]+") do
		local name, stype = line:match("^fwx_qos%.([^%.=]+)=([^%.=]+)$")
		if name then
			sections[name] = { type = stype, options = {} }
		else
			local sec, option, value = line:match("^fwx_qos%.([^%.]+)%.([^=]+)=(.*)$")
			if sec and sections[sec] then
				value = value:gsub("^'(.*)'$", "%1")
				sections[sec].options[option] = value
			end
		end
	end
	return sections
end

local function load_rules()
	local sections = read_config()
	local rules = {}
	for name, sec in pairs(sections) do
		if sec.type == "rule" then
			table.insert(rules, {
				id = name,
				name = sec.options.name or "",
				mac = sec.options.mac or "",
				ipv4 = sec.options.ipv4 or "",
				download = tonumber(sec.options.download or 0) or 0,
				upload = tonumber(sec.options.upload or 0) or 0,
				enabled = (sec.options.enabled == "1")
			})
		end
	end
	table.sort(rules, function(a, b) return a.id < b.id end)
	return rules
end

local function load_clients()
	local clients = {}
	local by_mac = {}
	local seen = {}

	for line in shell("cat /tmp/dhcp.leases"):gmatch("[^\n]+") do
		local expiry, mac, ip, host = line:match("^(%S+)%s+(%S+)%s+(%S+)%s+(%S+)%s+(%S+)")
		if mac and ip then
			mac = mac:lower()
			if not seen[mac] then
				seen[mac] = true
				local c = { mac = mac, ipv4 = ip, hostname = (host and host ~= "*" and host or "") }
				table.insert(clients, c)
				by_mac[mac] = c
			end
		end
	end

	for line in shell("ip -6 neigh show"):gmatch("[^\n]+") do
		local addr, rest = line:match("^(%S+)%s+(.*)$")
		local mac = rest and rest:match("lladdr%s+(%S+)")
		if addr and mac and not addr:match("^fe80:") then
			mac = mac:lower()
			local c = by_mac[mac]
			if not c then
				c = { mac = mac, ipv4 = "", hostname = "" }
				seen[mac] = true
				table.insert(clients, c)
				by_mac[mac] = c
			end
			c.ipv6 = c.ipv6 and (c.ipv6 .. "," .. addr) or addr
		end
	end

	table.sort(clients, function(a, b) return (a.hostname or "") < (b.hostname or "") end)
	return clients
end

function index()
	entry({ "admin", "system", "fwx_qos" }, template("fwx_qos/qos"), translate("Bandwidth Limit"), 60)
	entry({ "admin", "system", "fwx_qos_list" }, call("api_list")).leaf = true
	entry({ "admin", "system", "fwx_qos_save" }, post("api_save")).leaf = true
	entry({ "admin", "system", "fwx_qos_status" }, call("api_status")).leaf = true
end

function api_list()
	local sections = read_config()
	json_out({
		enabled = (sections.global and sections.global.options.enabled == "1"),
		rules = load_rules(),
		clients = load_clients()
	})
end

function api_save()
	local raw = http.formvalue("rules") or "[]"
	local data = json.parse(raw)
	if type(data) ~= "table" then
		json_out({ ok = false, message = "invalid payload" })
		return
	end

	local function q(value)
		return "'" .. tostring(value or ""):gsub("'", "'\\''") .. "'"
	end

	local batch = {}
	for name, _ in pairs(read_config()) do
		batch[#batch + 1] = "delete fwx_qos." .. name
	end
	batch[#batch + 1] = "set fwx_qos.global=qos"
	batch[#batch + 1] = "set fwx_qos.global.enabled=" .. q(http.formvalue("enabled") == "1" and "1" or "0")

	local idx = 0
	for _, r in ipairs(data) do
		if type(r) == "table" then
			idx = idx + 1
			local sec = "rule_" .. idx
			batch[#batch + 1] = "set fwx_qos." .. sec .. "=rule"
			batch[#batch + 1] = "set fwx_qos." .. sec .. ".enabled=" .. q(r.enabled and "1" or "0")
			batch[#batch + 1] = "set fwx_qos." .. sec .. ".name=" .. q(r.name)
			batch[#batch + 1] = "set fwx_qos." .. sec .. ".mac=" .. q(r.mac)
			batch[#batch + 1] = "set fwx_qos." .. sec .. ".ipv4=" .. q(r.ipv4)
			batch[#batch + 1] = "set fwx_qos." .. sec .. ".download=" .. q(tonumber(r.download or 0))
			batch[#batch + 1] = "set fwx_qos." .. sec .. ".upload=" .. q(tonumber(r.upload or 0))
		end
	end
	batch[#batch + 1] = "commit fwx_qos"

	local p = io.popen("uci -q batch 2>&1", "w")
	if p then
		p:write(table.concat(batch, "\n") .. "\n")
		p:close()
	end

	os.execute("/usr/sbin/fwx-qos-gen apply >/dev/null 2>&1")

	json_out({ ok = true, rules = load_rules() })
end

function api_status()
	json_out({ ruleset = shell("/usr/sbin/fwx-qos-gen status") })
end
