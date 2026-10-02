#requires -Version 7.0
param(
    [Parameter(Mandatory = $true)]
    [string]$DataDirectory
)

$ErrorActionPreference = 'Stop'
$taskArtRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$taskProfilePath = Join-Path $taskArtRoot 'Original/INARI/input_processing.json'
$taskProfile = Get-Content -LiteralPath $taskProfilePath -Raw | ConvertFrom-Json
$taskMinimum = [float]$taskProfile.right_stick.minimum
$taskMaximum = [float]$taskProfile.right_stick.maximum
if ($taskMinimum -le 0 -or $taskMaximum -le 0) {
    throw 'Zero processor parameters require a live Unity InputSystem settings instance.'
}
$taskCore = Join-Path $DataDirectory 'Managed/UnityEngine.CoreModule.dll'
$taskAssembly = Join-Path $DataDirectory 'Managed/Assembly-CSharp.dll'
$taskInput = Join-Path $DataDirectory 'Managed/Unity.InputSystem.dll'
[Reflection.Assembly]::LoadFrom((Resolve-Path -LiteralPath $taskCore).Path) | Out-Null
[Reflection.Assembly]::LoadFrom((Resolve-Path -LiteralPath $taskInput).Path) | Out-Null
[Reflection.Assembly]::LoadFrom((Resolve-Path -LiteralPath $taskAssembly).Path) | Out-Null

# Call the installed implementation itself. This wrapper contains no copied
# deadzone formula; explicit nonzero parameters avoid Unity engine startup.
Add-Type -ReferencedAssemblies @($taskCore, $taskInput, $taskAssembly, (Join-Path $PSHOME 'ref/netstandard.dll')) -TypeDefinition @'
public static class NativeStickOracle {
    public static float[] Movement(float x, float y) {
        // Bypass MonoBehaviour construction; this callback only reads managed fields.
        var actor = (PlayerInputController)System.Runtime.CompilerServices.RuntimeHelpers.GetUninitializedObject(typeof(PlayerInputController));
        var flags = System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.NonPublic;
        typeof(PlayerInputController).GetField("isInputable", flags).SetValue(actor, true);
        actor.OnInputAction = delegate(KeyType key) {};
        typeof(PlayerInputController).GetMethod("HandleGamePadLeftStick", flags).Invoke(actor, new object[] { new UnityEngine.Vector2(x, y) });
        return new float[] { actor.InputX, actor.InputY };
    }
    public static float[] Run(float x, float y, float minimum, float maximum) {
        var processor = new UnityEngine.InputSystem.Processors.StickDeadzoneProcessor();
        processor.min = minimum;
        processor.max = maximum;
        var result = processor.Process(new UnityEngine.Vector2(x, y), null);
        return new float[] { result.x, result.y };
    }
}
'@

$taskMovementSamples = [Collections.Generic.List[object]]::new()
$taskSamples = [Collections.Generic.List[object]]::new()
$taskInputs = [Collections.Generic.List[object]]::new()
for ($taskX = -10; $taskX -le 10; $taskX++) {
    for ($taskY = -10; $taskY -le 10; $taskY++) {
        $taskInputs.Add(@([float]($taskX / 10.0), [float]($taskY / 10.0)))
    }
}
foreach ($taskEdge in @(0.09999999, 0.1, 0.10000001, 0.15, 0.18999999, 0.19, 0.19000001, 0.2, 0.9999999, 1.0)) {
    foreach ($taskSign in @(-1, 1)) {
        $taskInputs.Add(@([float]($taskEdge * $taskSign), [float]0))
        $taskInputs.Add(@([float]0, [float]($taskEdge * $taskSign)))
    }
}
foreach ($taskPoint in $taskInputs) {
    $taskResult = [NativeStickOracle]::Run($taskPoint[0], $taskPoint[1], $taskMinimum, $taskMaximum)
    $taskMovement = [NativeStickOracle]::Movement($taskResult[0], $taskResult[1])
    $taskMovementSamples.Add(@{
        input = @([double]$taskPoint[0], [double]$taskPoint[1])
        output = @([double]$taskMovement[0], [double]$taskMovement[1])
    })
    $taskSamples.Add(@{
        input = @([double]$taskPoint[0], [double]$taskPoint[1])
        output = @([double]$taskResult[0], [double]$taskResult[1])
    })
}
# Vertical movement has its own post-deadzone threshold, unlike right-stick aim.
foreach ($taskEdge in @(0.7299999, 0.73, 0.7300001)) {
    foreach ($taskSign in @(-1, 1)) {
        $taskRawY = [float]($taskEdge * $taskSign)
        $taskProcessed = [NativeStickOracle]::Run(0, $taskRawY, $taskMinimum, $taskMaximum)
        $taskMovement = [NativeStickOracle]::Movement($taskProcessed[0], $taskProcessed[1])
        $taskMovementSamples.Add(@{
            input = @(0.0, [double]$taskRawY)
            output = @([double]$taskMovement[0], [double]$taskMovement[1])
        })
    }
}
$taskFixture = @{
    implementation = 'Unity.InputSystem StickDeadzoneProcessor.Process via .NET'
    profile_sha256 = (Get-FileHash -LiteralPath $taskProfilePath -Algorithm SHA256).Hash.ToLowerInvariant()
    source_sha256 = @{
        'UnityEngine.CoreModule.dll' = (Get-FileHash -LiteralPath $taskCore -Algorithm SHA256).Hash.ToLowerInvariant()
        'Unity.InputSystem.dll' = (Get-FileHash -LiteralPath $taskInput -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    movement_samples = $taskMovementSamples
    movement_implementation = 'Assembly-CSharp PlayerInputController.HandleGamePadLeftStick via reflection; inputable=true, MaintainLastInput=false'
    movement_assembly_sha256 = (Get-FileHash -LiteralPath $taskAssembly -Algorithm SHA256).Hash.ToLowerInvariant()
    samples = $taskSamples
}
$taskOutput = Join-Path $taskArtRoot 'Original/INARI/stick_oracle.json'
[IO.File]::WriteAllText($taskOutput, ($taskFixture | ConvertTo-Json -Depth 8 -Compress) + "`n", [Text.UTF8Encoding]::new($false))
Write-Output ("Exported {0} original DLL results to {1}" -f $taskSamples.Count, $taskOutput)
