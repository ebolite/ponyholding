if SERVER then
    AddCSLuaFile()
    AddCSLuaFile("ponyholding/sh_core.lua")
    AddCSLuaFile("ponyholding/cl_render.lua")
end

include("ponyholding/sh_core.lua")

if CLIENT then
    include("ponyholding/cl_render.lua")
end
