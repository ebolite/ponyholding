if SERVER then
    AddCSLuaFile()
    AddCSLuaFile("ponyholding/sh_core.lua")
    AddCSLuaFile("ponyholding/cl_render.lua")
    AddCSLuaFile("ponyholding/cl_diagnostics.lua")
end

include("ponyholding/sh_core.lua")

if CLIENT then
    include("ponyholding/cl_render.lua")
    include("ponyholding/cl_diagnostics.lua")
end
