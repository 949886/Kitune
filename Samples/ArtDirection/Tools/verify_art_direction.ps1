param(
    [Parameter(Mandatory = $true)]
    [string]$GodotExecutable,
    # Resume a verified run after a probe-only fix; default still checks every module.
    [string]$StartAt = ''
)

$ErrorActionPreference = 'Stop'
$workspacePath = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$enginePath = (Resolve-Path -LiteralPath $GodotExecutable).Path
$logDirectory = Join-Path $workspacePath 'tmp/art-direction/verification'
New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null

$probes = @(
    @{ Script = 'InariControllerProbe'; Marker = 'INARI_CONTROLLER_PASS' },
    @{ Script = 'GroundSnapProbe'; Marker = 'GROUND_SNAP_PASS' },
    @{ Script = 'JumpCornerProbe'; Marker = 'JUMP_CORNER_PASS' },
    @{ Script = 'ClimbProbe'; Marker = 'CLIMB_PASS' },
    @{ Script = 'CeilingProbe'; Marker = 'CEILING_PASS' },
    @{ Script = 'TeleportProbe'; Marker = 'TELEPORT_PASS' },
    @{ Script = 'GravityMotionProbe'; Marker = 'GRAVITY_MOTION_PASS' },
    @{ Script = 'AttackContactProbe'; Marker = 'ATTACK_CONTACT_PASS' },
    @{ Script = 'EnemyContactProbe'; Marker = 'ENEMY_CONTACT_PASS' },
    @{ Script = 'AirAttackProbe'; Marker = 'AIR_ATTACK_PASS' },
    @{ Script = 'AimTimeProbe'; Marker = 'AIM_TIME_PASS' },
    @{ Script = 'StickInputProbe'; Marker = 'STICK_INPUT_PASS' },
    @{ Script = 'MovementInputProbe'; Marker = 'MOVEMENT_INPUT_PASS' },
    @{ Script = 'PlayerDamageProbe'; Marker = 'PLAYER_DAMAGE_PASS' },
    @{ Script = 'OriginalAnimationProbe'; Marker = 'ORIGINAL_ANIMATION_PASS' },
    @{ Script = 'ShrineAmbientProbe'; Marker = 'SHRINE_AMBIENT_PASS' },
    @{ Script = 'ViewportCaptureProbe'; Marker = 'VIEWPORT_CAPTURE_PASS' },
    @{ Script = 'PlayerRenderingProbe'; Marker = 'PLAYER_RENDERING_PASS' },
    @{ Script = 'StaminaFeedbackProbe'; Marker = 'STAMINA_FEEDBACK_PASS' },
    @{ Script = 'WindBuffProbe'; Marker = 'WIND_BUFF_PASS' },
    @{ Script = 'WindMaterialProbe'; Marker = 'WIND_MATERIAL_PASS' },
    @{ Script = 'WindAnimationProbe'; Marker = 'WIND_ANIMATION_PASS' },
    @{ Script = 'WindTrailProbe'; Marker = 'WIND_TRAIL_PASS' },
    @{ Script = 'WindAudioProbe'; Marker = 'WIND_AUDIO_PASS' },
    @{ Script = 'KunaiRenderingProbe'; Marker = 'KUNAI_RENDERING_PASS' },
    @{ Script = 'KunaiFadeProbe'; Marker = 'KUNAI_FADE_PASS' },
    @{ Script = 'KunaiEffectsProbe'; Marker = 'KUNAI_EFFECTS_PASS' },
    @{ Script = 'InariCameraProbe'; Marker = 'INARI_CAMERA_PASS' },
    @{ Script = 'CameraImpulseProbe'; Marker = 'CAMERA_IMPULSE_PASS' },
    @{ Script = 'OriginalUVProbe'; Marker = 'ORIGINAL_UV_PROBE_PASS' },
    @{ Script = 'FactoryUVProbe'; Marker = 'FACTORY_UV_PASS' },
    @{ Script = 'TiltedPlaneProbe'; Marker = 'TILTED_PLANE_PASS' },
    @{ Script = 'SpriteSlicingProbe'; Marker = 'SPRITE_SLICING_PASS' },
    @{ Script = 'WaterProbe'; Marker = 'WATER_PROBE_PASS' },
    @{ Script = 'WaterParticleProbe'; Marker = 'WATER_PARTICLE_PASS' },
    @{ Script = 'WaterArrowProbe'; Marker = 'WATER_ARROW_PASS' },
    @{ Script = 'WaterResourceProbe'; Marker = 'WATER_RESOURCE_PASS' },
    @{ Script = 'LightingProbe'; Marker = 'LIGHTING_PROBE_PASS' },
    @{ Script = 'BloomProbe'; Marker = 'BLOOM_PROBE_PASS' },
    @{ Script = 'EnemyProbe'; Marker = 'ENEMY_PROBE_PASS' },
    @{ Script = 'PatrolProbe'; Marker = 'PATROL_PROBE_PASS' },
    @{ Script = 'RiflePresentationProbe'; Marker = 'RIFLE_PRESENTATION_PASS' },
    @{ Script = 'BowPresentationProbe'; Marker = 'BOW_PRESENTATION_PASS' },
    @{ Script = 'BowFlashProbe'; Marker = 'BOW_FLASH_PASS' },
    @{ Script = 'BowAttackProbe'; Marker = 'BOW_ATTACK_PASS' },
    @{ Script = 'BowCombatProbe'; Marker = 'BOW_COMBAT_PASS' },
    @{ Script = 'BowDoorProbe'; Marker = 'BOW_DOOR_PASS' },
    @{ Script = 'BowAudioProbe'; Marker = 'BOW_AUDIO_PASS' },
    @{ Script = 'BowRecoveryProbe'; Marker = 'BOW_RECOVERY_PASS' },
    @{ Script = 'BombPresentationProbe'; Marker = 'BOMB_PRESENTATION_PASS' },
    @{ Script = 'BombCombatProbe'; Marker = 'BOMB_COMBAT_PASS' },
    @{ Script = 'BombAudioProbe'; Marker = 'BOMB_AUDIO_PASS' },
    @{ Script = 'HitAudioProbe'; Marker = 'HIT_AUDIO_PASS' },
    @{ Script = 'RifleCombatProbe'; Marker = 'RIFLE_COMBAT_PASS' },
    @{ Script = 'RifleLeashProbe'; Marker = 'RIFLE_LEASH_PASS' },
    @{ Script = 'RifleChaseProbe'; Marker = 'RIFLE_CHASE_PASS' },
    @{ Script = 'RifleRetreatProbe'; Marker = 'RIFLE_RETREAT_PASS' },
    @{ Script = 'RiflePositioningProbe'; Marker = 'RIFLE_POSITIONING_PASS' },
    @{ Script = 'RifleDoorProbe'; Marker = 'RIFLE_DOOR_PASS' },
    @{ Script = 'DoorPhysicsProbe'; Marker = 'DOOR_PHYSICS_PASS' },
    @{ Script = 'ParticleProbe'; Marker = 'PARTICLE_PROBE_PASS' },
    @{ Script = 'ParticleSamplingProbe'; Marker = 'PARTICLE_SAMPLING_PASS' },
    @{ Script = 'GlowTextureProbe'; Marker = 'GLOW_TEXTURE_PASS' },
    @{ Script = 'ShockwaveProbe'; Marker = 'SHOCKWAVE_PASS' },
    @{ Script = 'ParticleLightingProbe'; Marker = 'PARTICLE_LIGHTING_PASS' },
    @{ Script = 'ArrowParticleProbe'; Marker = 'ARROW_PARTICLE_PASS' },
    @{ Script = 'ArrowProbe'; Marker = 'ARROW_PROBE_PASS' },
    @{ Script = 'KunaiProbe'; Marker = 'KUNAI_PROBE_PASS' },
    @{ Script = 'WeakPointProbe'; Marker = 'WEAK_POINT_PASS' },
    @{ Script = 'WeakPointWarpProbe'; Marker = 'WEAK_POINT_WARP_PASS' },
    @{ Script = 'EnemyOutlineProbe'; Marker = 'ENEMY_OUTLINE_PASS' },
    @{ Script = 'WeakPointTargetingProbe'; Marker = 'WEAK_POINT_TARGETING_PASS' },
    @{ Script = 'TargetMarkerProbe'; Marker = 'TARGET_MARKER_PASS' },
    @{ Script = 'GamepadAimProbe'; Marker = 'GAMEPAD_AIM_PASS' },
    @{ Script = 'DashAttackMotionProbe'; Marker = 'DASH_ATTACK_MOTION_PASS' },
    @{ Script = 'WeakDashProbe'; Marker = 'WEAK_DASH_PASS' },
    @{ Script = 'ChromaticProbe'; Marker = 'CHROMATIC_PASS' },
    @{ Script = 'OutlineIsolationProbe'; Marker = 'OUTLINE_ISOLATION_PASS' },
    @{ Script = 'CharacterSelectionProbe'; Marker = 'CHARACTER_SELECTION_PASS' },
    @{ Script = 'LabProbe'; Marker = 'LAB_PROBE_PASS' },
    @{ Script = 'RouteProbe'; Marker = 'ROUTE_PROBE_PASS' }
)

if ($StartAt) {
    $startIndex = [Array]::IndexOf([string[]]$probes.Script, $StartAt)
    if ($startIndex -lt 0) { throw ('Unknown probe: ' + $StartAt) }
    $probes = $probes | Select-Object -Skip $startIndex
}

foreach ($probe in $probes) {
    $logPath = Join-Path $logDirectory ($probe.Script + '.log')
    $arguments = @(
        '--headless', '--fixed-fps', '60',
        '--path', ('"' + $workspacePath + '"'),
        '--script', ('res://Samples/ArtDirection/Tests/' + $probe.Script + '.gd'),
        '--log-file', ('"' + $logPath + '"'),
        '--quit-after', '18000'
    )

    # Godot's GUI executable may not propagate a script's exit code on Windows.
    # Require each probe's completion marker and inspect script errors as well.
    $process = Start-Process -FilePath $enginePath -ArgumentList $arguments -WindowStyle Hidden -PassThru -Wait
    $log = Get-Content -LiteralPath $logPath -Raw -Encoding utf8
    if (-not $log.Contains($probe.Marker) -or $log.Contains('SCRIPT ERROR:') -or $log.Contains('Failed loading resource:')) {
        throw ('Verification failed: ' + $probe.Script + '. See ' + $logPath)
    }

    Write-Output ($probe.Marker + ' (' + $logPath + ')')
}
