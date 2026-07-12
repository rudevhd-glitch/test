Set-StrictMode -Version Latest

function New-RkvBuildSeed {
	param(
		[Parameter(Mandatory = $true)][string]$MasterSeed,
		[Parameter(Mandatory = $true)][string]$BuildId,
		[Parameter(Mandatory = $true)][byte[]]$Nonce
	)

	$utf8 = [System.Text.UTF8Encoding]::new($false)
	$hmac = [System.Security.Cryptography.HMACSHA256]::new($utf8.GetBytes($MasterSeed))
	try {
		$material = $utf8.GetBytes("$BuildId`0RKV-KALEIDOSCOPE-1`0") + $Nonce
		return $hmac.ComputeHash($material)
	} finally {
		$hmac.Dispose()
	}
}

function Get-RkvUInt32 {
	param([Parameter(Mandatory = $true)][byte[]]$Bytes, [int]$Offset = 0)
	return [BitConverter]::ToUInt32($Bytes, $Offset)
}

function ConvertTo-RkvLuaArray {
	param([Parameter(Mandatory = $true)][System.Collections.IEnumerable]$Values)
	return "{" + (($Values | ForEach-Object { [string]$_ }) -join ",") + "}"
}

function Protect-RkvPayload {
	param(
		[Parameter(Mandatory = $true)][string]$Source,
		[Parameter(Mandatory = $true)][string]$MasterSeed,
		[Parameter(Mandatory = $true)][string]$BuildId,
		[byte[]]$Nonce,
		[ValidateRange(0, 8)][int]$DecoyCount = 2,
		[switch]$Compact
	)

	if (-not $Nonce) {
		$Nonce = [byte[]]::new(16)
		$rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
		try { $rng.GetBytes($Nonce) } finally { $rng.Dispose() }
	}
	if ($Nonce.Length -lt 8) {
		throw "Arcada Guard Security nonce must contain at least 8 bytes"
	}

	$seed = New-RkvBuildSeed -MasterSeed $MasterSeed -BuildId $BuildId -Nonce $Nonce
	$payload = [System.Text.UTF8Encoding]::new($false).GetBytes($Source)
	$keyState = [uint64](Get-RkvUInt32 -Bytes $seed -Offset 0)
	$rolling = [uint64](Get-RkvUInt32 -Bytes $seed -Offset 4)
	$selectorState = [uint64](Get-RkvUInt32 -Bytes $seed -Offset 8)
	if ($Compact) {
		$selectorState %= 65536
	}
	$initialKeyState = $keyState
	$initialRolling = $rolling
	$initialSelectorState = $selectorState
	$modulus = [uint64]4294967296
	$shards = @(
		[System.Collections.Generic.List[int]]::new(),
		[System.Collections.Generic.List[int]]::new(),
		[System.Collections.Generic.List[int]]::new()
	)
	$route = [System.Collections.Generic.List[int]]::new()
	$positions = [System.Collections.Generic.List[int]]::new()
	$encodedPayload = [System.Collections.Generic.List[int]]::new()
	$checksum = [uint64]2166136261

	for ($offset = 0; $offset -lt $payload.Length; $offset++) {
		$i = $offset + 1
		$keyState = (($keyState * 1664525) + 1013904223) % $modulus
		if ($Compact) {
			$selectorState = (($selectorState * 25173) + 13849) % 65536
		} else {
			$selectorState = (($selectorState * 1103515245) + 12345) % $modulus
		}
		$shardIndex = [int]($selectorState % 3)
		$mask = [int](($keyState + ($rolling % 256) + (($i * 17 + ($shardIndex + 1) * 29) % 256)) % 256)
		$plainByte = [int]$payload[$offset]
		$encodedByte = $plainByte -bxor $mask
		$encodedPayload.Add($encodedByte)
		$shards[$shardIndex].Add($encodedByte)
		$route.Add($shardIndex + 1)
		$positions.Add($shards[$shardIndex].Count)
		$rolling = ($rolling + [uint64]($plainByte * 257) + [uint64]($encodedByte * 17) + [uint64]($i * 131) + [uint64](($shardIndex + 1) * 8191)) % $modulus
		$checksum = (($checksum * 65599) + [uint64]$plainByte + [uint64]$i) % $modulus
	}

	if ($Compact) {
		$hexPayload = ($encodedPayload | ForEach-Object { $_.ToString('x2') }) -join ''
		$fingerprint = ([BitConverter]::ToString([byte[]]$seed[12..19]) -replace '-', '').ToLowerInvariant()
		$compactTemplate = @'
return(function(...)
local bx=bit32 and bit32.bxor or function(a,b)
 local v,p=0,1
 for _=1,8 do
  local x,y=a%2,b%2
  if x~=y then v=v+p end
  a=(a-x)/2 b=(b-y)/2 p=p*2
 end
 return v
end
local data="__HEX__"
local k,w,z=__KEY__,__ROLLING__,__SELECTOR__
local h,out=2166136261,{}
local n=0
for offset=1,#data,2 do
 n=n+1
 k=(k*1664525+1013904223)%4294967296
 z=(z*25173+13849)%65536
 local q=(z%3)+1
 local e=tonumber(data:sub(offset,offset+1),16)
 local m=(k+(w%256)+((n*17+q*29)%256))%256
 local v=bx(e,m)
 out[n]=string.char(v)
 w=(w+v*257+e*17+n*131+q*8191)%4294967296
 h=(h*65599+v+n)%4294967296
end
if h~=__CHECKSUM__ then error("RKV runtime integrity error",0) end
data=nil
local source=table.concat(out)
out=nil
local compile=loadstring or load
if type(compile)~="function" then error("RKV runtime integrity error",0) end
local chunk,reason=compile(source,"@RKV/__FP__")
source=nil
if type(chunk)~="function" then error("RKV runtime integrity error: "..tostring(reason),0) end
return chunk(...)
end)(...)
'@
		$compactProtected = $compactTemplate.
			Replace('__HEX__', $hexPayload).
			Replace('__KEY__', [string]$initialKeyState).
			Replace('__ROLLING__', [string]$initialRolling).
			Replace('__SELECTOR__', [string]$initialSelectorState).
			Replace('__CHECKSUM__', [string]$checksum).
			Replace('__FP__', $fingerprint)
		return (($compactProtected -split "`r?`n" | ForEach-Object { $_.Trim() }) -join ' ')
	}

	# Shuffle physical shard storage and rewrite the per-byte position map.
	for ($shardIndex = 0; $shardIndex -lt 3; $shardIndex++) {
		$count = $shards[$shardIndex].Count
		$permutation = 0..([Math]::Max(0, $count - 1))
		if ($count -eq 0) { $permutation = @() }
		for ($i = $count - 1; $i -gt 0; $i--) {
			$selectorState = (($selectorState * 1103515245) + 12345) % $modulus
			$j = [int]($selectorState % ($i + 1))
			$temp = $permutation[$i]; $permutation[$i] = $permutation[$j]; $permutation[$j] = $temp
		}
		$inverse = [int[]]::new($count)
		$shuffled = [System.Collections.Generic.List[int]]::new()
		for ($newIndex = 0; $newIndex -lt $count; $newIndex++) {
			$oldIndex = $permutation[$newIndex]
			$shuffled.Add($shards[$shardIndex][$oldIndex])
			$inverse[$oldIndex] = $newIndex + 1
		}
		$shards[$shardIndex] = $shuffled
		for ($i = 0; $i -lt $route.Count; $i++) {
			if ($route[$i] -eq $shardIndex + 1) {
				$positions[$i] = $inverse[$positions[$i] - 1]
			}
		}
	}

	# Build two structurally valid false descriptors. They are inert: the runtime
	# reads a little noise from each, but only the seed-selected descriptor can run.
	$descriptorTexts = [System.Collections.Generic.List[string]]::new()
	$realDescriptor = "{" +
		"{" + (ConvertTo-RkvLuaArray $shards[0]) + "," + (ConvertTo-RkvLuaArray $shards[1]) + "," + (ConvertTo-RkvLuaArray $shards[2]) + "}," +
		(ConvertTo-RkvLuaArray $route) + "," + (ConvertTo-RkvLuaArray $positions) + "," +
		([string]$initialKeyState) + "," + ([string]$initialRolling) + "," + ([string]$checksum) + "}"
	$descriptorTexts.Add($realDescriptor)
	for ($decoyIndex = 0; $decoyIndex -lt $DecoyCount; $decoyIndex++) {
		$fakeShards = @(
			[System.Collections.Generic.List[int]]::new(),
			[System.Collections.Generic.List[int]]::new(),
			[System.Collections.Generic.List[int]]::new()
		)
		for ($shardIndex = 0; $shardIndex -lt 3; $shardIndex++) {
			for ($i = 0; $i -lt $shards[$shardIndex].Count; $i++) {
				$selectorState = (($selectorState * 1103515245) + 12345) % $modulus
				$fakeShards[$shardIndex].Add([int]($selectorState % 256))
			}
		}
		$selectorState = (($selectorState * 1103515245) + 12345) % $modulus
		$fakeKey = $selectorState
		$selectorState = (($selectorState * 1103515245) + 12345) % $modulus
		$fakeRolling = $selectorState
		$selectorState = (($selectorState * 1103515245) + 12345) % $modulus
		$fakeChecksum = $selectorState
		$fakeDescriptor = "{" +
			"{" + (ConvertTo-RkvLuaArray $fakeShards[0]) + "," + (ConvertTo-RkvLuaArray $fakeShards[1]) + "," + (ConvertTo-RkvLuaArray $fakeShards[2]) + "}," +
			(ConvertTo-RkvLuaArray $route) + "," + (ConvertTo-RkvLuaArray $positions) + "," +
			([string]$fakeKey) + "," + ([string]$fakeRolling) + "," + ([string]$fakeChecksum) + "}"
		$descriptorTexts.Add($fakeDescriptor)
	}
	$descriptorCount = $DecoyCount + 1
	$descriptorOrder = @(0..($descriptorCount - 1))
	for ($i = $descriptorCount - 1; $i -gt 0; $i--) {
		$selectorState = (($selectorState * 1103515245) + 12345) % $modulus
		$j = [int]($selectorState % ($i + 1))
		$temp = $descriptorOrder[$i]; $descriptorOrder[$i] = $descriptorOrder[$j]; $descriptorOrder[$j] = $temp
	}
	$orderedDescriptors = $descriptorOrder | ForEach-Object { $descriptorTexts[$_] }
	$realDescriptorIndex = [Array]::IndexOf([object[]]$descriptorOrder, 0) + 1
	$selectorState = (($selectorState * 1103515245) + 12345) % $modulus
	$selectorA = [int]($selectorState % 100000) + 1000
	$selectorB = (($realDescriptorIndex - 1) - (($selectorA * 7) % $descriptorCount) + $descriptorCount) % $descriptorCount

	$fingerprint = ([BitConverter]::ToString([byte[]]$seed[12..19]) -replace '-', '').ToLowerInvariant()
	$template = @'
return(function(...)
local bx
if bit32 then
 bx=bit32.bxor
else
 bx=function(a,b)
  local v,p=0,1
  for _=1,8 do
   local x,y=a%2,b%2
   if x~=y then v=v+p end
   a=(a-x)/2 b=(b-y)/2 p=p*2
  end
  return v
 end
end
local all={__DESCRIPTORS__}
local noise=0
for j=1,#all do
 local x=all[j]
 local q=((j*13+#x[2])%3)+1
 local a=x[1][q]
 if #a>0 then noise=(noise+a[((j*17)%#a)+1]+x[4]%251)%4294967296 end
end
local chosen=all[((__SELECT_A__*7+__SELECT_B__)%__DESCRIPTOR_COUNT__)+1]
if not chosen or noise<0 then error("RKV runtime integrity error",0) end
all=nil
local s=chosen[1]
local r=chosen[2]
local p=chosen[3]
local k=chosen[4]
local w=chosen[5]
local h=2166136261
local out={}
for i=1,#r do
 k=(k*1664525+1013904223)%4294967296
 local q=r[i]
 local e=s[q][p[i]]
 if e==nil then error("RKV runtime integrity error",0) end
 local m=(k+(w%256)+((i*17+q*29)%256))%256
 local v=bx(e,m)
 out[i]=string.char(v)
 w=(w+v*257+e*17+i*131+q*8191)%4294967296
 h=(h*65599+v+i)%4294967296
end
if h~=chosen[6] then error("RKV runtime integrity error",0) end
chosen=nil
local source=table.concat(out)
out=nil
local compile=loadstring or load
if type(compile)~="function" then error("RKV runtime integrity error",0) end
local chunk,reason=compile(source,"@RKV/__FP__")
source=nil
if type(chunk)~="function" then error("RKV runtime integrity error: "..tostring(reason),0) end
return chunk(...)
end)(...)
'@

	$protected = $template.
		Replace('__FP__', $fingerprint).
		Replace('__DESCRIPTORS__', ($orderedDescriptors -join ',')).
		Replace('__DESCRIPTOR_COUNT__', [string]$descriptorCount).
		Replace('__SELECT_A__', [string]$selectorA).
		Replace('__SELECT_B__', [string]$selectorB)

	# Arcada Guard Security output is deliberately emitted as one physical line.
	return (($protected -split "`r?`n" | ForEach-Object { $_.Trim() }) -join ' ')
}
