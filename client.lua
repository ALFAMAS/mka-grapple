local QBCore = exports['qb-core']:GetCoreObject()

Citizen.CreateThread(function()
  -- Constants
  local EARLY_STOP_MULTIPLIER = 0.5
  local DEFAULT_GTA_FALL_DISTANCE = 8.3
  local DEFAULT_OPTIONS = {waitTime=0.5, grappleSpeed=20.0}

  -- Grapple table to hold functions
  Grapple = {}

  -- Utility Functions
  local function DirectionToRotation(dir, roll)
    local z = -math.deg(math.atan2(dir.x, dir.y))
    local rotpos = vector3(dir.z, math.sqrt(dir.x * dir.x + dir.y * dir.y), 0.0)
    local x = math.deg(math.atan2(rotpos.x, rotpos.y))
    local y = roll
    return vector3(x, y, z)
  end

  local function RotationToDirection(rot)
    local rotZ = math.rad(rot.z)
    local rotX = math.rad(rot.x)
    local cosRotX = math.abs(math.cos(rotX))
    return vector3(-math.sin(rotZ) * cosRotX, math.cos(rotZ) * cosRotX, math.sin(rotX))
  end

  local function RayCastGamePlayCamera(dist)
    local camRot = GetGameplayCamRot()
    local camPos = GetGameplayCamCoord()
    local dir = RotationToDirection(camRot)
    local dest = camPos + (dir * dist)
    local ray = StartShapeTestRay(camPos, dest, 17, -1, 0)
    local _, hit, endPos, surfaceNormal, entityHit = GetShapeTestResult(ray)
    if hit == 0 then endPos = dest end
    return hit, endPos, entityHit, surfaceNormal
  end

  function GrappleCurrentAimPoint(dist)
    return RayCastGamePlayCamera(dist)
  end

  -- Fill in defaults for any options that aren't present
  local function ensureOptions(options)
    for k, v in pairs(DEFAULT_OPTIONS) do
      if options[k] == nil then options[k] = v end
    end
  end

  local function waitForFall(pid, ped, stopDistance)
    SetPlayerFallDistance(pid, 10.0)
    while GetEntityHeightAboveGround(ped) > stopDistance do
      SetPedCanRagdoll(ped, false)
      Citizen.Wait(0)
    end
    SetPlayerFallDistance(pid, DEFAULT_GTA_FALL_DISTANCE)
    Citizen.Wait(1500)
    SetPedCanRagdoll(ped, true)
  end

  local function PinRope(rope, ped, boneId, dest)
    PinRopeVertex(rope, 0, dest)
    PinRopeVertex(rope, GetRopeVertexCount(rope) - 1, GetPedBoneCoords(ped, boneId, 0.0, 0.0, 0.0))
  end

  -- Grapple object constructor
  function Grapple.new(dest, options)
    local self = {}
    options = options or {}
    ensureOptions(options)
    local grappleId = math.random((-2^31), 2^31-1)
    if options.grappleId then
      grappleId = options.grappleId
    end
    local pid = PlayerId()
    if options.plyServerId then
      pid = GetPlayerFromServerId(options.plyServerId)
    end
    local ped = GetPlayerPed(pid)
    local start = GetEntityCoords(ped)
    local notMyPed = options.plyServerId and options.plyServerId ~= GetPlayerServerId(PlayerId())
    local fromStartToDest = dest - start
    local dir = fromStartToDest / math.sqrt(fromStartToDest.x^2 + fromStartToDest.y^2 + fromStartToDest.z^2)
    local length = math.sqrt(fromStartToDest.x^2 + fromStartToDest.y^2 + fromStartToDest.z^2)
    local finished = false
    local rope
    if pid ~= -1 then
      RopeLoadTextures()
      rope = AddRope(dest, 0.0, 0.0, 0.0, 0.0, 5, 0.0, 0.0, 1.0, false, false, false, 5.0, false)
      if notMyPed then
        local headingToSet = GetEntityHeading(ped)
        ped = ClonePed(ped, 0, 0, 0)
        SetEntityHeading(ped, headingToSet)
        NetworkConcealPlayer(pid, true, false)
      end
    end

    local function setupDestroyEventHandler()
      local eventName = 'mka-grapple:ropeDestroyed:' .. tostring(grappleId)
      RegisterNetEvent(eventName)
      local event = AddEventHandler(eventName, function()
        self.destroy(false)
        RemoveEventHandler(event)
      end)
    end

    function self.handleRope(rope, ped, boneIndex, dest)
      Citizen.CreateThread(function()
        while not finished do
          PinRope(rope, ped, boneIndex, dest)
          Citizen.Wait(0)
        end
        DeleteChildRope(rope)
        DeleteRope(rope)
      end)
    end

    function self.activateSync()
      if pid == -1 then return end
      local distTraveled = 0.0
      local currentPos = start
      local lastPos = currentPos
      local rotationMultiplier = notMyPed and -1 or 1
      local rot = DirectionToRotation(-dir * rotationMultiplier, 0.0)
      local lastRot = rot
      rot = rot + vector3(90.0 * rotationMultiplier, 0.0, 0.0)
      Citizen.Wait(options.waitTime * 1000)
      while not finished and distTraveled < length do
        local fwdPerFrame = dir * options.grappleSpeed * GetFrameTime()
        distTraveled = distTraveled + math.sqrt(fwdPerFrame.x^2 + fwdPerFrame.y^2 + fwdPerFrame.z^2)
        if distTraveled > length then
          distTraveled = length
          currentPos = dest
        else
          currentPos = currentPos + fwdPerFrame
        end
        SetEntityCoords(ped, currentPos)
        SetEntityRotation(ped, rot)
        if distTraveled > 3 and HasEntityCollidedWithAnything(ped) then
          SetEntityCoords(ped, lastPos - (dir * EARLY_STOP_MULTIPLIER))
          SetEntityRotation(ped, lastRot)
          break
        end
        lastPos = currentPos
        lastRot = rot
        Citizen.Wait(0)
      end
      self.destroy()
      waitForFall(pid, ped, 3.0)
    end

    function self.activate()
      Citizen.CreateThread(self.activateSync)
    end

    function self.destroy(shouldTriggerDestroyEvent)
      finished = true
      if pid ~= -1 and notMyPed then
        DeleteEntity(ped)
        NetworkConcealPlayer(pid, false, false)
      end
      if shouldTriggerDestroyEvent == nil or shouldTriggerDestroyEvent then
        TriggerServerEvent('mka-grapple:destroyRope', grappleId)
      end
    end

    if pid ~= -1 then
      self.handleRope(rope, ped, 0x49D9, dest)
      if notMyPed then
        self.activate()
      end
    end
    if options.plyServerId == nil then
      TriggerServerEvent('mka-grapple:createRope', grappleId, dest)
    else
      setupDestroyEventHandler()
    end
    return self
  end

  -- Grapple gun variables
  local grappleGunHash = -2009644972
  local grappleGunSuppressor = "COMPONENT_AT_PI_SUPP_02"
  local grappleGunEquipped = false
  local shownGrappleButton = false

  -- Command to use grapple
  RegisterCommand("grapple", function()
    TriggerEvent("mka-grapple:useGrapple")
  end)

  -- Event handler for using grapple
  RegisterNetEvent('mka-grapple:useGrapple')
  AddEventHandler('mka-grapple:useGrapple', function()
    grappleGunEquipped = not grappleGunEquipped
    if grappleGunEquipped then
      GiveWeaponComponentToPed(PlayerPedId(), grappleGunHash, grappleGunSuppressor)
      SetPedWeaponTintIndex(PlayerPedId(), grappleGunHash, grappleGunTintIndex)
      SetAmmoInClip(PlayerPedId(), grappleGunHash, 0)
    else
      RemoveWeaponFromPed(PlayerPedId(), grappleGunHash)
    end
    local ply = PlayerId()

    Citizen.CreateThread(function()
      while grappleGunEquipped do
        local veh = GetVehiclePedIsIn(PlayerPedId(), false)
        if veh ~= 0 or GetSelectedPedWeapon(PlayerPedId()) ~= grappleGunHash then
          grappleGunEquipped = false
          RemoveWeaponFromPed(PlayerPedId(), grappleGunHash)
          return
        end
        local freeAiming = IsPlayerFreeAiming(ply)
        local hit, pos, _, _ = GrappleCurrentAimPoint(4000)
        if not shownGrappleButton and freeAiming and hit == 1 then
          shownGrappleButton = true
          Citizen.Wait(250)
          exports["np-ui"]:showInteraction('[Shoot] Grapple!', 'inform')
        elseif shownGrappleButton and (not freeAiming or hit ~= 1) then
          shownGrappleButton = false
          exports["np-ui"]:hideInteraction()
        end
        if IsControlJustReleased(0, 24) and freeAiming and grappleGunEquipped then  -- mouse left click
          hit, pos, _, _ = GrappleCurrentAimPoint(4000)
          exports["np-ui"]:hideInteraction()
          if hit == 1 then
            exports["np-ui"]:hideInteraction()
            grappleGunEquipped = false
            Citizen.Wait(50)
            local grapple = Grapple.new(pos, { waitTime = 1.5 })
            grapple.activate()
            Citizen.Wait(50)
            RemoveWeaponFromPed(PlayerPedId(), grappleGunHash)
            shownGrappleButton = false
          end
        end
        Citizen.Wait(0)
      end
    end)
  end)

    --[[ Test Stuff ]]
  --[[ Test Stuff ]]

  --[[
  Citizen.CreateThread(function ()
     while true do
      Wait(1000)
       --local hit, pos, _, _ = RayCastGamePlayCamera(40)
       local hit, pos, _, _ = GrappleCurrentAimPoint(4000)
       if hit == 1 then
         --DrawSphere(pos, 0.1, 255, 0, 0, 255)
         --if IsControlJustReleased(0, 51) then
         shownGrappleButton = true
         exports["np-ui"]:showInteraction('[Shoot] Grapple!', 'inform')
       elseif shownGrappleButton and (not freeAiming or hit ~= 1) then
          shownGrappleButton = false
          exports["np-ui"]:hideInteraction()
       end
         if IsControlJustReleased(0, 24) then
          exports["np-ui"]:hideInteraction()
           
           local grapple = Grapple.new(pos)
           grapple.activate()
         end
       RemoveWeaponFromPed(PlayerPedId(), grappleGunHash)
       Wait(0)
     end
  end)
  ]]

  --[[ Test Stuff ]]
  --[[ Test Stuff ]]

  -- Event handler for when a rope is created
  RegisterNetEvent('mka-grapple:ropeCreated')
  AddEventHandler('mka-grapple:ropeCreated', function(grappleId, dest)
    local plyServerId = GetPlayerServerId(PlayerId())
    if plyServerId == source then return end
    TriggerServerEvent("InteractSound:PlayOnSource", "grapple-shot", 0.5)
    Grapple.new(dest, {plyServerId = plyServerId, grappleId = grappleId})
  end)
end)
