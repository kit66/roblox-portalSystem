-- Initializes a detection sphere centered on the player with the specified radius
-- When collectible objects enter this sphere, they are picked up
local character = script.Parent
local RS = game:GetService("ReplicatedStorage")
local part = character.UpperTorso

local radius = RS.objects.radius:Clone()

radius.Parent = character

local weld = Instance.new("Weld")

weld.Part0 = part
weld.Part1 = radius
weld.Parent = workspace

