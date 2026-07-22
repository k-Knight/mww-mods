local InputController = require("scripts/input_controller")
local EventHandler = SE.event_handler

local GF_STATE = {}
local fx_name = "CloudVolumetricPerspective.fx"

local try_install_shader
try_install_shader = function (callback)
    repeat
        if not ReShadeBridge or not ReShadeBridge.installAssets then
            k_log("[GroundFog] ReShadeBridge framework is not initialized yet !!!")
            break
        end

        local success, asset_data = pcall(require, "GroundFog/shader_assets")
        if not success then
            k_log("[GroundFog] could not load GroundFog/shader_assets.lua ::\n" .. tostring(asset_data))
            break
        end

        local shaders_table = {
            [fx_name] = asset_data.fx_string
        }

        local textures_table = {
            ["fognoise.jpg"] = asset_data.texture_string
        }

        local changes_made = ReShadeBridge.installAssets("GroundFog", asset_data.shaders, asset_data.textures)
        if changes_made then
            k_log("[GroundFog] assets installed, waiting for game reboot ...")
            return
        else
            kUtil.task_scheduler.add(callback, 200)
            return
        end
    until true

    kUtil.task_scheduler.add(try_install_shader, 1000)
end

function stingray_quat_to_reshade_euler(qx, qy, qz, qw)
    local xx = qx * qx
    local yy = qy * qy
    local zz = qz * qz
    local xy = qx * qy
    local xz = qx * qz
    local yz = qy * qz
    local wx = qw * qx
    local wy = qw * qy
    local wz = qw * qz

    local m12 = 2.0 * (yz - wx)
    local m02 = 2.0 * (xz + wy)
    local m22 = 1.0 - 2.0 * (xx + yy)
    local m10 = 2.0 * (xy + wz)
    local m11 = 1.0 - 2.0 * (xx + zz)

    local pitch_rad = math.asin(m12)
    local yaw_rad   = math.atan2(-m02, m22)
    local roll_rad  = math.atan2(-m10, m11)

    local pitch = math.deg(pitch_rad)
    local yaw   = math.deg(yaw_rad)
    local roll  = math.deg(roll_rad)

    if pitch > 90 then pitch = pitch - 180 elseif pitch < -90 then pitch = pitch + 180 end
    if yaw > 180 then yaw = yaw - 360 elseif yaw < -180 then yaw = yaw + 360 end
    if roll > 180 then roll = roll - 360 elseif roll < -180 then roll = roll + 360 end

    if math.abs(roll) >= 179.99 then roll = 0.0 end

    pitch = pitch * (26.5 / 45.0)

    if math.abs(pitch) < 0.001 then pitch = 0.0 end
    if math.abs(yaw) < 0.001 then yaw = 0.0 end
    if math.abs(roll) < 0.001 then roll = 0.0 end

    return pitch, yaw, roll
end

function calculate_cloud_settings(camera_pos, intersect_pos, far_range)
    local look_distance = Vector3.length(intersect_pos - camera_pos)

    if look_distance < 0.01 then
        return 440.0, 6450.0
    end

    local depth_range_multiplier = 6450.0 / 1030.0
    local depth_max_range = far_range * depth_range_multiplier
    local cloud_base_altitude = look_distance * 15.5 - 87

    return cloud_base_altitude, depth_max_range
end

local function update_shader_values()
    if GF_STATE.camera_system then
        local game_camera = GF_STATE.camera_system.game_camera

        if game_camera then
            local camera_position = Camera.local_position(game_camera)
            local camera_rotation = Camera.local_rotation(game_camera)
            local camera_far_range = Camera.far_range(game_camera)
            local qx, qy, qz, qw = Quaternion.to_elements(camera_rotation)
            local pitch, yaw, roll = stingray_quat_to_reshade_euler(qx, qy, qz, qw)

            ReShadeBridge.setFloat3(fx_name, "CameraRotation", pitch, yaw, roll)

            local s_w, s_h = Application.resolution()
            local x, y = s_w / 2, s_h / 2
            local world_lookat_position = Camera.screen_to_world(game_camera, Vector3(x, 0, y))
            local camera_direction = Camera.screen_to_world(game_camera, Vector3(x, 1, y)) - world_lookat_position

            camera_direction = Vector3.normalize(camera_direction)

            local plane = Plane.from_point_and_normal(Vector3(1, 1, 0.01), Vector3.up())
            local plane_t = Intersect.ray_plane(world_lookat_position, camera_direction, plane)

            if plane_t then
                local intersect_pos = world_lookat_position + camera_direction * plane_t
                local cloud_base_altitude, depth_max_range = calculate_cloud_settings(camera_position, intersect_pos, camera_far_range)

                local base_camera_position = intersect_pos - camera_direction * 34.01
                local altitude_ratio = cloud_base_altitude / 440.0

                local new_x, new_y, z = Vector3.x(base_camera_position), Vector3.y(base_camera_position), Vector3.z(base_camera_position)
                new_y = new_y + altitude_ratio * 32
                new_x = new_x + altitude_ratio * 0.5
                camera_position = Vector3(new_x, new_y, z)

                ReShadeBridge.setFloat(fx_name, "CloudBaseAltitude", cloud_base_altitude)
                ReShadeBridge.setFloat(fx_name, "DepthMaxRange", depth_max_range)
            else
                k_log("[GroundFog] plane_t is missing !!!!!")
            end

            ReShadeBridge.setFloat2(fx_name, "CloudOffset",
                -Vector3.x(camera_position) / 45.0,
                -Vector3.y(camera_position) / 30.0
            )
        else
            k_log("[GroundFog] game_camera is missing !!!!!")
        end
    end
end

local mod_initialized = false

local function set_main_menu_cloud_settings()
    local res

    res = ReShadeBridge.setFloat(fx_name, "CloudBaseAltitude", -9)
    if not res then
        k_log("[GroundFog] failed to set CloudBaseAltitude !!!")
        return false
    end

    res = ReShadeBridge.setFloat(fx_name, "CloudLayerThickness", 621)
    if not res then
        k_log("[GroundFog] failed to set CloudLayerThickness !!!")
        return false
    end

    res = ReShadeBridge.setFloat(fx_name, "CloudScale", 0.0001)
    if not res then
        k_log("[GroundFog] failed to set CloudScale !!!")
        return false
    end

    res = ReShadeBridge.setFloat2(fx_name, "CloudSpeed", 0.01, -0.03)
    if not res then
        k_log("[GroundFog] failed to set CloudSpeed !!!")
        return false
    end

    res = ReShadeBridge.setFloat(fx_name, "MaxBlobDensity", 0.35)
    if not res then
        k_log("[GroundFog] failed to set MaxBlobDensity !!!")
        return false
    end

    res = ReShadeBridge.setFloat(fx_name, "CloudThreshold", 0.55)
    if not res then
        k_log("[GroundFog] failed to set CloudThreshold !!!")
        return false
    end

    res = ReShadeBridge.setFloat3(fx_name, "CameraRotation", -1.5, 0.0, 0.0)
    if not res then
        k_log("[GroundFog] failed to set CameraRotation !!!")
        return false
    end

    res = ReShadeBridge.setFloat(fx_name, "CloudCutoffDistance", 71.0)
    if not res then
        k_log("[GroundFog] failed to set CloudCutoffDistance !!!")
        return false
    end

    return true
end

local function reset_cloud_settings()
    k_log("[GroundFog] resetting cloud layer settings ...")
    ReShadeBridge.resetVariable(fx_name, "CloudBaseAltitude", true)
    ReShadeBridge.resetVariable(fx_name, "CloudLayerThickness", true)
    ReShadeBridge.resetVariable(fx_name, "CloudScale", true)
    ReShadeBridge.resetVariable(fx_name, "CloudOffset", true)
    ReShadeBridge.resetVariable(fx_name, "CloudSpeed", true)
    ReShadeBridge.resetVariable(fx_name, "CloudColor", true)
    ReShadeBridge.resetVariable(fx_name, "CloudDensityMultiplier", true)
    ReShadeBridge.resetVariable(fx_name, "MaxBlobDensity", true)
    ReShadeBridge.resetVariable(fx_name, "CloudThreshold", true)
    ReShadeBridge.resetVariable(fx_name, "CloudSharpness", true)
    ReShadeBridge.resetVariable(fx_name, "CloudRoundness", true)
    ReShadeBridge.resetVariable(fx_name, "CameraFOV", true)
    ReShadeBridge.resetVariable(fx_name, "CameraRotation", true)
    ReShadeBridge.resetVariable(fx_name, "DepthMaxRange", true)
    ReShadeBridge.resetVariable(fx_name, "CloudCutoffDistance", true)
    ReShadeBridge.resetVariable(fx_name, "CloudCreviceAO", true)
    ReShadeBridge.resetVariable(fx_name, "CloudEdgeHighlight", true)
    ReShadeBridge.resetVariable(fx_name, "CloudAOSensitivity", true)
    ReShadeBridge.resetVariable(fx_name, "CloudAOLookAhead", true)
end

local retry_set_settings
retry_set_settings = function ()
    if not set_main_menu_cloud_settings() then
        kUtil.task_scheduler.add(retry_set_settings, 0)
    end
end

local function enable_shader()
    local ok = ReShadeBridge.setStateAndOrder("VolumetricCloudPerspective", true, false)

    if ok then
        k_log("[GroundFog] effect enabled and pushed to end successfully !")
    else
        k_log("[GroundFog] failed to set effect runtime configuration state !!!")
    end

    return ok
end

local retry_enable_shader
retry_enable_shader = function ()
    if not enable_shader() then
        kUtil.task_scheduler.add(retry_enable_shader, 0)
    end
end

local function on_game_menu_init()
    GF_STATE.camera_system = nil
    kUtil.task_scheduler.add(retry_set_settings, 0)

    if mod_initialized then
        return
    end

    mod_initialized = true

    try_install_shader(retry_enable_shader)

    kUtil.add_on_render_handler(function ()
        local status, err = pcall(update_shader_values)

        if not status then
            k_log("[GroundFog] failure updating the shader ::\n" .. tostring(err))
        end
    end)

    kUtil.loop_try_prehook_function(_G, "CameraSystem", "post_update", function (self, dt, context)
        if not GF_STATE.camera_system then
            k_log("[GroundFog] got new camera system :: " .. tostring(self))
            reset_cloud_settings()
        end

        GF_STATE.camera_system = self
    end)
end

EventHandler.register_event("menu", "init", "GroundFog_init", on_game_menu_init)
