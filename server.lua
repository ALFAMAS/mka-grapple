-- Register an event for creating a grapple rope and trigger a client event to create the rope
RegisterServerEvent('mka-grapple:createRope')
AddEventHandler('mka-grapple:createRope', function(grappleId, dest)
    -- Validate the grappleId and destination before proceeding
    if type(grappleId) ~= "number" or type(dest) ~= "vector3" then
        -- Log an error or handle it as needed
        print("Invalid grappleId or destination received in createRope event")
        return
    end

    -- Trigger the client event to create the rope, passing the grappleId and destination
    TriggerClientEvent('mka-grapple:ropeCreated', source, grappleId, dest)
end)

-- Register an event for destroying a grapple rope and trigger a client event to destroy the rope
RegisterServerEvent('mka-grapple:destroyRope')
AddEventHandler('mka-grapple:destroyRope', function(grappleId)
    -- Validate the grappleId before proceeding
    if type(grappleId) ~= "number" then
        -- Log an error or handle it as needed
        print("Invalid grappleId received in destroyRope event")
        return
    end

    -- Trigger the client event to destroy the rope, passing the grappleId
    TriggerClientEvent('mka-grapple:ropeDestroyed', source, grappleId)
end)
