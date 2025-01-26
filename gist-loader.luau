--[[
    gist-loader.luau
    @jLn0n - 2024

    generalized gist loader thingy
--]]

local http_service = game:GetService("HttpService")

local function fetch_url(url: string, no_cache: boolean): string?
	local success, result = pcall(http_service.GetAsync, http_service, url, no_cache)

	if not success then
		warn(`Failed to load URL '{url}'\n{result}`)
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
return function(gist_owner: string, gist_id: string)
	local url = `{gist_owner}/{gist_id}`
	local gist_full_url = `https://gist.githubusercontent.com/{url}/raw/`

	return {
		fetch = function(path: string, no_cache: boolean): string?
			return fetch_url(gist_full_url .. path, no_cache)
		end,
		load_src = function(path: string, no_cache: boolean): ((...any) -> (...any))?
			return load_url(gist_full_url .. path, `github-gist/{url}/{path}`)
		end,
	}
end
