local HttpService = game:GetService("HttpService")

local REPO_OWNER = "jLn0n"
local REPO_NAME = "sb-scripts"
local PATH_KEYWORD = "movement-system"

local current_commit_hash: string

local function directory_url_format(commit_id: string, path: string): string
	return `https://github.com/{REPO_OWNER}/{REPO_NAME}/blob/{commit_id}/{path}?raw=true`
end

local function fetch_url(url: string, no_cache: boolean): string?
	local success, result = pcall(HttpService.GetAsync, HttpService, url, no_cache)

	if not success then
		warn(`Failed to load URL '{url}'{"\n"}{result}`)
		return nil
	end
	return result
end

local function get_latest_commit_hash(branch: string): (string, string?)
	local branches_raw = fetch_url(`https://api.github.com/repos/{REPO_OWNER}/{REPO_NAME}/branches`, true)
	if not branches_raw then
		return branch, nil
	end

	local branches = HttpService:JSONDecode(branches_raw)
	local commit_hash: string
	for _, branch_data in branches do
		if branch_data.name ~= branch then
			continue
		end

		commit_hash = branch_data.commit.sha
		break
	end

	return branch, commit_hash
end

local __import_cache = {}
local function import_dir(path: string): any
	local sure_path = if not string.match(path, "(.*%.luau)$") then path .. ".luau" else path
	local loaded_module = __import_cache[sure_path]
	if not loaded_module then
		print(`loading script of path '{REPO_NAME}/{sure_path}'`)

		local module_src = fetch_url(directory_url_format(current_commit_hash, sure_path), true)
		if not module_src then
			return
		end

		local module, err = loadstring(module_src, sure_path)
		if module then
			loaded_module = module()
			__import_cache[sure_path] = loaded_module

			return loaded_module
		end

		error(`Module '{sure_path} cannot be loaded, error:\n{err}'`)
	end

	return loaded_module
end

local orig_require = require;
local j_require: typeof(require) = (function(target: any)
	if typeof(target) == "string" then
		if string.find(target, `@{PATH_KEYWORD}/`, 1, true) then
			return import_dir(string.sub(target, 2))
		end
	end

	return orig_require(target)
end):: any
getfenv().require = j_require

do
	print(`fetching commit hash of 'github/{REPO_OWNER}/{REPO_NAME}'`)

	local branch_parent, fetched_hash = get_latest_commit_hash("main")
	if fetched_hash then
		print(`successfully fetched, commit hash: '{fetched_hash}'`)
		current_commit_hash = fetched_hash
	else
		warn("failed to fetch latest commit hash, defaulting to main")
		current_commit_hash = branch_parent
	end

	print("movement system server loading...")
	require("@movement-system/server")
end
