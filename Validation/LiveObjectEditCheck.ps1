# Tests only newly created objects in unused layers through the public Named Pipe.
param([switch]$FunctionsOnly)
$ErrorActionPreference = 'Stop'

function Invoke-MIRAI([hashtable]$Request, [string]$ExpectedError = '') {
  $Request.protocol_version = 1
  $Request.protocol = 'Aul2MIRAI'
  $pipe = [IO.Pipes.NamedPipeClientStream]::new('.', 'Aul2MIRAI.v1',
    [IO.Pipes.PipeDirection]::InOut, [IO.Pipes.PipeOptions]::Asynchronous)
  $stream = [IO.MemoryStream]::new()
  try {
    $pipe.Connect(5000)
    $pipe.ReadMode = [IO.Pipes.PipeTransmissionMode]::Message
    $bytes = [Text.Encoding]::UTF8.GetBytes(($Request | ConvertTo-Json -Compress -Depth 20))
    $pipe.Write($bytes, 0, $bytes.Length)
    $buffer = [byte[]]::new(65536)
    do {
      $read = $pipe.ReadAsync($buffer, 0, $buffer.Length)
      if (-not $read.Wait(15000)) { throw 'Named Pipe read timed out.' }
      if ($read.Result -eq 0) { throw 'Named Pipe closed before the complete response.' }
      $stream.Write($buffer, 0, $read.Result)
      if ($stream.Length -gt 16777216) { throw 'Response exceeds 16 MiB.' }
    } until ($pipe.IsMessageComplete)
    $response = [Text.Encoding]::UTF8.GetString($stream.ToArray()) | ConvertFrom-Json
    if ($ExpectedError) {
      if ($response.status -ne 'error' -or $response.error.code -ne $ExpectedError) {
        throw "Expected $ExpectedError : $($response | ConvertTo-Json -Depth 20 -Compress)"
      }
    } elseif ($response.status -ne 'ok') {
      throw ($response | ConvertTo-Json -Depth 20 -Compress)
    }
    return $response
  } finally {
    $pipe.Dispose()
    $stream.Dispose()
  }
}

function Get-Objects { Invoke-MIRAI @{command='get_scene_objects'} }

function Find-TestObject($Objects, [int]$Layer) {
  $found = @($Objects.snapshot.objects | Where-Object {
    $_.layer -eq $Layer -and $_.start_frame -eq 0 -and $_.end_frame -eq 29 -and $_.primary_effect -eq '図形'
  })
  if ($found.Count -ne 1) { throw "Test object not uniquely identified in layer $Layer." }
  return $found[0]
}

function Focus-TestObject([int]$Layer) {
  $objects = Get-Objects
  $target = Find-TestObject $objects $Layer
  $request = @{command='preview_set_focus_object'; state_token=$objects.state_token; target_index=$target.index}
  $null = Invoke-MIRAI $request
  $request.command = 'set_focus_object'
  $request.apply = $true
  $null = Invoke-MIRAI $request
  return Get-Objects
}

function Object-Fingerprint($Objects) {
  return ConvertTo-Json -InputObject @($Objects | Select-Object layer,start_frame,end_frame,name,
    content_digest,section_frames,effect_states) -Depth 20 -Compress
}

if ($FunctionsOnly) { return }

$baseline = Get-Objects
$firstLayer = [int]$baseline.snapshot.layer_max + 2
$layers = @($firstLayer, ($firstLayer + 1))
$created = [Collections.Generic.List[int]]::new()
$completed = $false
try {
  foreach ($layer in $layers) {
    $objects = Get-Objects
    $request = @{command='preview_create_object_from_alias'; state_token=$objects.state_token;
      effect='図形'; layer=$layer; frame=0; length=30}
    $null = Invoke-MIRAI $request
    $request.command = 'create_object_from_alias'
    $request.apply = $true
    $null = Invoke-MIRAI $request
    $created.Add($layer)
  }
  $objects = Focus-TestObject $firstLayer
  $target = Find-TestObject $objects $firstLayer
  $staleToken = $objects.state_token
  $request = @{command='preview_set_object_name'; state_token=$objects.state_token;
    target_index=$target.index; name='検証_日本語の表示名'}
  $preview = Invoke-MIRAI $request
  if (-not $preview.preview.will_change) { throw 'Rename preview was a no-op.' }
  $request.command = 'set_object_name'
  $request.apply = $true
  $renamed = Invoke-MIRAI $request
  if (-not $renamed.change.verified) { throw 'Rename was not verified.' }
  $null = Invoke-MIRAI @{command='set_object_name'; state_token=$staleToken;
    target_index=$target.index; name='stale'; apply=$true} 'state_changed'

  $objects = Get-Objects
  $target = Find-TestObject $objects $firstLayer
  if ($target.name -ne '検証_日本語の表示名') { throw 'Japanese name was not retained.' }
  $request = @{command='set_object_name'; state_token=$objects.state_token;
    target_index=$target.index; name=$target.name; apply=$true}
  $noop = Invoke-MIRAI $request
  if ($noop.change.applied -or -not $noop.change.verified) { throw 'Same-name request performed an edit.' }
  $request.name = ''
  $null = Invoke-MIRAI $request
  $objects = Get-Objects
  $target = Find-TestObject $objects $firstLayer
  if ($target.name -ne '') { throw 'Resetting the default name failed.' }
  $other = Find-TestObject $objects ($firstLayer + 1)
  $null = Invoke-MIRAI @{command='preview_delete_objects'; state_token=$objects.state_token;
    target_indices=@($other.index)} 'target_not_selected'
  $null = Invoke-MIRAI @{command='delete_objects'; state_token=$objects.state_token;
    target_indices=@($target.index); apply=$false} 'apply_required'
  $null = Invoke-MIRAI @{command='preview_delete_objects'; state_token=$objects.state_token;
    target_indices=@($target.index,$target.index)} 'duplicate_target'

  foreach ($layer in $layers) {
    $objects = Focus-TestObject $layer
    $target = Find-TestObject $objects $layer
    $request = @{command='preview_delete_objects'; state_token=$objects.state_token;
      target_indices=@($target.index)}
    $preview = Invoke-MIRAI $request
    $afterPreview = Get-Objects
    if ((Object-Fingerprint $objects.snapshot.objects) -ne (Object-Fingerprint $afterPreview.snapshot.objects)) {
      throw 'Delete preview modified the scene.'
    }
    $request.command = 'delete_objects'
    $request.apply = $true
    $deleted = Invoke-MIRAI $request
    if (-not $deleted.change.verified -or $deleted.change.deleted_count -ne 1) {
      throw 'Deletion was not verified.'
    }
    $null = $created.Remove($layer)
  }
  $final = Get-Objects
  if ((Object-Fingerprint $baseline.snapshot.objects) -ne (Object-Fingerprint $final.snapshot.objects)) {
    throw 'Existing objects differ after the test.'
  }
  $completed = $true
  Write-Output 'PASS: live create, rename/reset/no-op, stale token, selection/apply/duplicate rejection, delete preview/apply and unchanged existing objects'
} finally {
  if (-not $completed -and $created.Count -gt 0) {
    Write-Warning "Test did not complete. Inspect test layers $($created -join ', '); existing objects were not cleanup targets."
  }
}
