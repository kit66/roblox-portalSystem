local badgeS = game:GetService("BadgeService")

-- 4) badge system

local purchaseBadgeId = 3225353430882368


-- give badge to player
local function giveBadge(player, badgeId)
	-- get badge info
	local success, badgeInfo = pcall(function()
		return badgeS:GetBadgeInfoAsync(badgeId)
	end)
	if not success then
		warn("GetBadgeInfo error:", badgeInfo)
		return
	end

	-- if not active badge - return
	if not badgeInfo.IsEnabled then
		return
	end

	-- Try to award the badge
	local awardSuccess, result = pcall(function()
		return badgeS:AwardBadge(player.UserId, badgeId)
	end)
	if not awardSuccess or not result then
		warn("giveBadge error:", result)
	end
end

