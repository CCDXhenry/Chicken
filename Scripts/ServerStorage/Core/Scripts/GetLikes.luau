--!strict
local id: string = "AKfycbyXWCSxn9zfGKzWFLB6bPSaiNPX8Hqwe5eBwL5kUYZOm0zQpU8dRt-3kVw4UY9mS2oxDQ"
local url: string = "https://script.google.com/macros/s/" .. id .. "/exec"
local https: HttpService = game:GetService("HttpService")
local GetLikes = {}

function GetLikes.GetLikeCount(universeId: number): string?
	local response: any = https:GetAsync(url .. "?UniverseId=" .. tostring(universeId))
	response = https:JSONDecode(response)
	if response.result == "error" then
		warn("Failed to get likes!")
		return nil
	else
		local likes: string = response.response.response.data[1].upVotes
		return likes
	end
end

return GetLikes
