AddCSLuaFile()

SWEP.PrintName       = "Inferno"
SWEP.Author          = "Earu"
SWEP.Instructions    = "O B L I T E R A T E"
SWEP.Purpose         = "O B L I T E R A T E"
SWEP.Contact         = "nah man"
SWEP.Spawnable       = true
SWEP.AdminOnly       = true
SWEP.HoldType        = "crossbow"
SWEP.FiresUnderwater = true
SWEP.AnimPrefix      = "crossbow"

SWEP.Primary.ClipSize	  = -1
SWEP.Primary.DefaultClip  = -1
SWEP.Primary.Automatic    = false
SWEP.Primary.Ammo		  = "none"

SWEP.Secondary.ClipSize	   = -1
SWEP.Secondary.DefaultClip = -1
SWEP.Secondary.Automatic   = false
SWEP.Secondary.Ammo		   = "none"

SWEP.Weight			= 5
SWEP.AutoSwitchTo   = false
SWEP.AutoSwitchFrom	= false

SWEP.Slot		   = 1
SWEP.SlotPos	   = 2
SWEP.DrawAmmo	   = false
SWEP.DrawCrosshair = true

SWEP.UseHands      = false
SWEP.ViewModelFOV  = 64
SWEP.ViewModel     = "models/weapons/inferno.mdl"
SWEP.ViewModelFlip = false

SWEP.WorldModel        = "models/weapons/inferno.mdl"
SWEP.CustomPositon     = true
SWEP.CustomAttatchment = "anim_attachment_rh"
SWEP.CustomVector      = Vector(0,5,3)
SWEP.CustomAngle       = Angle(0,0,180)

for _,f in pairs((file.Find("sound/inferno/*","GAME"))) do
    util.PrecacheSound("sound/inferno/" .. f)
end

function SWEP:CanSecondaryaAttack()
    return false
end

function SWEP:IsFiring()
    return self:GetNWBool("Firing",false)
end

function SWEP:GetAttachmentPos()
    local owner = self:GetOwner()
    if not IsValid(owner) then return self:GetPos() end
    local attachid = self:GetOwner():LookupAttachment(self.CustomAttatchment)
    if not attachid then return self:GetPos() end

    local attachment = self:GetOwner():GetAttachment(attachid)
    return attachment and attachment.Pos or self:GetPos()
end

if SERVER then
    local DistanceToSqr = FindMetaTable("Vector").DistToSqr
    local IsValid = _G.IsValid
    local TraceHull = util.TraceHull
    local Vector = _G.Vector

    util.AddNetworkString("vfire_inferno_ent")

    local function AddResourceDir(dir)
        for _,f in pairs((file.Find(dir .. "/*","GAME"))) do
            local path = dir .. "/" .. f
            resource.AddFile(path)
        end
    end

    AddResourceDir("materials/models/weapons/inferno")
    AddResourceDir("materials/egon")
    AddResourceDir("sound/inferno")

    local removeprops = CreateConVar("inferno_remove_props","1",FCVAR_ARCHIVE,"Allows inferno to obliterate props")
    local adminonly = CreateConVar("inferno_admin_only","0",FCVAR_ARCHIVE,"Should inferno be usable for admins only")
    local usevire = CreateConVar("inferno_use_vfire","1",FCVAR_ARCHIVE,"Should inferno use vfire")

    cvars.AddChangeCallback("inferno_admin_only",function()
        SWEP.AdminOnly = adminonly:GetBool()
    end)

    function SWEP:Initialize()
        self:CreateDissolver()
        self:CreateSounds()
    end

    function SWEP:Deploy()
        self:SetModelScale(0.85)
        self:SetHoldType("crossbow")

        local owner = self:GetOwner()
        if IsValid(owner) and owner:IsPlayer() then
            if adminonly:GetBool() and not owner:IsAdmin() then
                self:Remove()
            end
            self.DefaultRunSpeed = owner:GetRunSpeed()
            self.DefaultWalkSpeed = owner:GetWalkSpeed()
        end
    end

    function SWEP:CanUseVFire()
        return usevire:GetBool() and vFireInstalled
    end

    function SWEP:CreateDissolver()
        local dissolver = ents.Create("env_entity_dissolver")
		dissolver:SetPos(self:GetPos())
		dissolver:Spawn()
        dissolver:Activate()
        dissolver:SetNotSolid(true)

        self.Dissolver = dissolver
    end

    function SWEP:CreateSounds()
        local e = ents.Create("prop_physics")
        e:SetPos(self:GetAttachmentPos())
        e:SetParent(self)
        e:SetModel("models/props_junk/watermelon01.mdl")
        e:SetModelScale(0.1)
        e:Spawn()
        e:Activate()
        e:SetNotSolid(true)
        --e:SetNoDraw(true)

        self.SoundEntity = e
        self.ChargeSound = CreateSound(e,"inferno/start.wav")
        self.LoopSound = CreateSound(e,"inferno/loop.wav")
        self.EndSound = CreateSound(e,"inferno/end.wav")
        self.ChargeSound:ChangeVolume(2)
        self.LoopSound:ChangeVolume(2)
        self.EndSound:ChangeVolume(2)
    end

    function SWEP:OnRemove()
        SafeRemoveEntity(self.Dissolver)
        self.LoopSound:Stop()
        self.ChargeSound:Stop()
        self.EndSound:Stop()
    end

    local function DamageEnt(self,ent,forcedir)
        if ent:IsPlayer() and ent:HasGodMode() then return end

        local info = DamageInfo()
        info:SetInflictor(self)
        info:SetAttacker(IsValid(self:GetOwner()) and self:GetOwner() or self)
        info:SetDamage(150)
        info:SetDamageType(DMG_DISSOLVE)
        info:SetDamageForce(forcedir)

        ent:TakeDamageInfo(info)
    end

    local explsounds = {
        "^weapons/explode3.wav",
        "^weapons/explode4.wav",
    }
    local function ObliterateEnt(self,ent,forcedir)
        if not ent or ent:CreatedByMap() then return end
        if not removeprops:GetBool() then
            DamageEnt(self,ent,forcedir)
            return
        end

        local pos = ent:WorldSpaceCenter()
        local maxs = ent:OBBMaxs()
        local scale = (maxs.x + maxs.y + maxs.z) / 3
        if self:CanUseVFire() then
            net.Start("vfire_inferno_ent")
            net.WriteVector(pos)
            net.WriteInt(scale,32)
            net.SendPVS(pos)
        else
            local data = EffectData()
            data:SetOrigin(pos)
            data:SetScale(scale / 50)
            util.Effect("inferno_explosion",data,true,true)
        end

        local s = explsounds[math.random(1,#explsounds)]
        ent:EmitSound(s,100)

        local gpo = ent:GetPhysicsObject()
        if IsValid(gpo) then
            gpo:EnableGravity(true)
            gpo:EnableMotion(true)
        end

        constraint.RemoveAll(ent)
        ent:SetNotSolid(true)
        if IsValid(self.Dissolver) then
            SafeRemoveEntityDelayed(ent,0.1)
            local name = "dissolvemenao" .. ent:EntIndex()
            ent:SetName(name)
            self.Dissolver:SetKeyValue("target",name)
            self.Dissolver:SetKeyValue("dissolvetype","2")
            self.Dissolver:SetKeyValue("magnitude",1500)
            self.Dissolver:Fire("Dissolve",name,0)
        else
            SafeRemoveEntity(ent)
        end
    end

    local function Obliterate(self,ent)
        if not IsValid(ent) then return end
        if not IsValid(self.Dissolver) then
            self:CreateDissolver()
        end

        local forcedir = (ent:GetPos() - (self:GetPos() + Vector(0,0,90))):GetNormalized() * 20000
        if ent:IsPlayer() then
            DamageEnt(self,ent,forcedir)
            local ragdoll = ent:GetRagdollEntity()
            if IsValid(ragdoll) then
                ObliterateEnt(self,ragdoll,forcedir)
            end
        else
            ObliterateEnt(self,ent,forcedir)
        end
    end

    local lastpos = Vector(0,0,0)
    function SWEP:Obliterate()
        local owner = self:GetOwner()
        if self:IsFiring() and IsValid(owner) then
            local dirn = owner:GetAimVector()
            local dir = dirn * (4096 * 8)
            local pos = owner:GetShootPos()
            local endpos = pos + dir
            local tr = util.TraceHull({
                start = pos,
                endpos = endpos,
                mins = Vector(-10,-10,-10),
                maxs = Vector(10,10,10),
                filter = { owner, self },
            })

            if IsValid(tr.Entity) then
                Obliterate(self, tr.Entity)
            else
                if tr.HitSky then return end
                local hitpos = tr.HitPos
                if DistanceToSqr(lastpos,hitpos) >= 400 then
                    if self:CanUseVFire() and util.IsInWorld(hitpos) then
                        local fire = CreateVFire(game.GetWorld(),hitpos,tr.HitNormal,1)
                        if fire then
                            fire:ChangeLife(5)
                        end
                    end
                    lastpos = hitpos
                end
            end
        end
    end

    function SWEP:PrimaryAttack()
        self.StartFiring = CurTime() + 2
        self.ChargeSound:Play()
        local data = EffectData()
        timer.Simple(1.9,function()
            if IsValid(self) then
                self.LoopSound:Play()
            end
        end)
    end

    function SWEP:StopFiring()
        local owner = self:GetOwner()
        if not IsValid(owner) then return end

        if self.ChargeSound:IsPlaying() then
            self.ChargeSound:Stop()
        end

        if self.LoopSound:IsPlaying() then
            self.LoopSound:FadeOut(0.1)
            self.EndSound:Play()
        end

        self.StartFiring = nil
        self:SetNWBool("Firing",false)
        if owner:IsPlayer() then
            owner:SetRunSpeed(self.DefaultRunSpeed or 400)
            owner:SetWalkSpeed(self.SetWalkSpeed or 200)
        end
    end

    function SWEP:Holster()
        self:StopFiring()

        return true
    end

    function SWEP:Think()
        local owner = self:GetOwner()
        if not IsValid(owner) then return end
        if owner:IsNPC() and owner:GetActivity() == ACT_RANGE_ATTACK1 or owner:KeyDown(IN_ATTACK) then
            if self.EndSound:IsPlaying() then
                self.EndSound:Stop()
            end

            if self.StartFiring and self.StartFiring <= CurTime() then
                self:SetNWBool("Firing",true)
                self:Obliterate()
            end

            if owner:IsPlayer() then
                owner:SetRunSpeed(150)
                owner:SetWalkSpeed(150)
            end
        else
            self:StopFiring()
        end
    end
end

if CLIENT then
    local vec            = Vector(2000, 2000, 2000)
    local beammat        = Material("egon/dark_beam")
    local refractionmat	 = Material("egon/refract_ring")
    local spritemat      = Material("egon/muzzlelight")
    local col_white = Color(255,255,255,255)

    if beammat:IsError() then
        beammat = Material("trails/physbeam")
    end
    if refractionmat:IsError() then
        refractionmat = Material("trails/physbeam")
    end

    local function DrawMainBeam(startpos,endpos)
		local offset = CurTime() * -2.0
		local dist = startpos:Distance(endpos)

		render.SetMaterial(beammat)
		local txstart = offset * 0.4
		local txend = offset * 0.4 + dist / 2048
		render.DrawBeam(startpos,endpos,45,txstart,txend,col_white)

		render.SetMaterial(refractionmat)
		render.UpdateRefractTexture()
		txstart = offset * 0.5
		txend = offset * 0.5 + dist / 1024
		render.DrawBeam(startpos,endpos,50,txstart,txend,col_white)
	end

	local function DrawCurlyBeam(startpos,endpos,ang)
		local offset        = CurTime() * 3
		local forward       = ang:Forward()
		local right         = ang:Right()
		local up 	        = ang:Up()
		local lastpos       = startpos
		local dist          = startpos:Distance(endpos)
		local stepsize      = dist / 8
		local ringtightness = 0.1

		render.SetMaterial(beammat)

		for i = 0, dist, stepsize do
			local val = CurTime() * -30 + i * ringtightness
			local sin = math.sin(val)
			local cos = math.cos(val)
			local pos = startpos + (forward * i) + (up * sin * 8) + (right * cos * 8)

			if lastpos then
				local sin = math.sin(i * 0.02)
				local w = (sin <= 0 and sin + 1.0 or sin) + 1.0 * 5
				render.DrawBeam(lastpos,pos,w,offset + i,offset + dist / 4096 + i,col_white)
			end

			lastpos = pos
		end
	end

	local function DrawBeamPoint(pos,mult)
		render.SetMaterial(spritemat)
		local size = 10 * mult
		render.DrawSprite(pos,size,size,Color(255,255,255,200))
		render.DrawSprite(pos,14 * mult,1.5 * mult,Color(255,255,255,200))
		size = 16 * mult
		render.DrawSprite(pos,size,size,Color(255,0,0))
		render.DrawSprite(pos,28 * mult,1.5 * mult,Color(255,0,0))
    end

	local function DrawBeam(startpos,endpos)
		DrawBeamPoint(startpos,15)
		DrawMainBeam(startpos,endpos)
		DrawCurlyBeam(startpos,endpos,(endpos - startpos):Angle())
		DrawBeamPoint(endpos,75)
    end


    local targetmat = Material("models/weapons/inferno/viewfinder.png")
    function SWEP:Initialize()
        hook.Add("RenderScreenspaceEffects",self,self.DrawBeam)
        hook.Add("HUDPaint",self,function(self)
            local owner = self:GetOwner()
            if owner == LocalPlayer() and owner:GetActiveWeapon() == self then
                surface.SetDrawColor(255,255,255,255)
                surface.SetMaterial(targetmat)
                surface.DrawTexturedRect(0,0,ScrW(),ScrH())
            end
        end)
    end

    local function InThirdPerson(ent)
        if not ent:IsPlayer() then return false end
        return hook.Run("ShouldDrawLocalPlayer",ent) or false
    end

    function SWEP:DrawLight(pos,size)
        local dlight = DynamicLight(self:EntIndex())
        if dlight then
            dlight.pos = pos
            dlight.r = 255
            dlight.g = 0
            dlight.b = 0
            dlight.brightness = 2
            dlight.Decay = 1000
            dlight.Size = size
            dlight.DieTime = CurTime() + 1
        end
    end

    function SWEP:DrawBeam()
        local owner = self:GetOwner()
        if IsValid(owner) and self:IsFiring() then
            local dir = owner:GetAimVector()
            local pos = self:GetAttachmentPos()
            if not InThirdPerson(owner) then
                pos = pos + self:GetUp() * 12 + self:GetRight() * 5
            else
                pos = pos + self:GetUp() * 2 + self:GetRight() * - 3
            end
            local tr = util.TraceLine({
                start = pos,
                endpos = pos + (dir * (4096 * 8)),
                filter = { owner, self }
            })
            util.ScreenShake(pos,2,1,0.2,500)
            cam.Start3D()
                local startpos = pos + dir * 37
                DrawBeam(startpos,tr.HitPos)
                self:DrawLight(tr.HitPos,512)
            cam.End3D()
        end
    end

    function SWEP:HandleWorldModelArrangments()
        if not self.CustomPositon then return end

        local hand, vector = nil, self.CustomVector
        if not self:GetOwner():IsValid() then return end

        if self:GetOwner():IsValid() and self:GetOwner():LookupAttachment(self.CustomAttatchment) then
            hand = self:GetOwner():LookupAttachment(self.CustomAttatchment)
        end

        if not hand then return end
        hand = self:GetOwner():GetAttachment(hand)
        if not hand or not hand.Ang then return end
        vector = hand.Ang:Right() * self.CustomVector.x + hand.Ang:Forward() * self.CustomVector.y + hand.Ang:Up() * self.CustomVector.z

        hand.Ang:RotateAroundAxis(hand.Ang:Right(), self.CustomAngle.x)
        hand.Ang:RotateAroundAxis(hand.Ang:Forward(), self.CustomAngle.y)
        hand.Ang:RotateAroundAxis(hand.Ang:Up(), self.CustomAngle.z)

        self:SetRenderOrigin(hand.Pos + vector)
        self:SetRenderAngles(hand.Ang)
    end

    function SWEP:DrawWorldModel()
        self:HandleWorldModelArrangments()
        self:DrawModel()
    end

    function SWEP:CalcViewModelView(_,_,_,pos,ang)
        pos = pos + (ang:Right() * 15)
        pos = pos + (ang:Forward() * 40)
        pos = pos + (ang:Up() * -20)

        ang:RotateAroundAxis(ang:Up(), 180)
        ang:RotateAroundAxis(ang:Right(), 0)

        return pos,ang
    end

    function SWEP:PrimaryAttack() end

    net.Receive("vfire_inferno_ent",function()
        local pos = net.ReadVector()
        local scale = net.ReadInt(32)

        if vFireInstalled then
            CreateVFireExplosionEffect(pos,scale / 100)
        end
    end)
end