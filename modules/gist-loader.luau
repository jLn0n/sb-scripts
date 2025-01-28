--[[
    gist-loader.luau
    @jLn0n - 2024

    generalized gist loader thingy
--]]

local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

local GITHUB_API_URL = "https://api.github.com"

type GistObject = {
	fetch: (path: string, no_cache: boolean) -> (string?),
	load_src: (path: string) -> ((...any) -> (...any))?
}

local function gist_url_constructor(gist_id: string, gist_owner: string, commit_hash: string): string
	return "https://gist.githubusercontent.com/" .. gist_owner .. "/" .. gist_id .. "/raw/" .. commit_hash .. "/"
end

local function fetch_url(url: string, no_cache: boolean, silent: boolean?): string?
	local success, result = pcall(HttpService.GetAsync, HttpService, url, no_cache)

	if not success then
		if not silent then
			warn(`Failed to load URL '{url}'\n{result}`)
		end
		return nil
	end
	return result
end

local function load_url(url: string, chunk_name: string?): ((...any) -> (...any))?
	local result = fetch_url(url, true)
	return (if result then loadstring(result, chunk_name or url) else nil)
end

--[=[
	Creates a new Gist fetcher object that can fetch anything inside a specified gist.
]=]
return function(gist_id: string): GistObject
	if not RunService:IsServer() then
		return error("This can only be utilized in server-side!", 2)
	end

	local _retries = 0
	local raw_gist_commits;

	repeat
		raw_gist_commits = fetch_url(`${GITHUB_API_URL}/gists/${gist_id}/commits`, true, true)
		if raw_gist_commits then
			break
		end

		task.wait(1)
		_retries += 1
	until _retries > 5

	if not raw_gist_commits then
		return error(`Failed to fetch gist '${gist_id}'!`, 2)
	end

	local gist_commits = HttpService:JSONDecode(raw_gist_commits)
	local gist_latest_commit = gist_commits[1]
	local commit_hash = gist_latest_commit.version
	local gist_owner = gist_latest_commit.user.login

	local gist_url = gist_url_constructor(gist_id, gist_owner, commit_hash)

	return {
		fetch = function(path: string, no_cache: boolean): string?
			return fetch_url(gist_url .. path, no_cache)
		end,
		load_src = function(path: string): ((...any) -> (...any))?
			return load_url(gist_url .. path, `github-gist/{gist_id}/{path}`)
		end,
	}
end
