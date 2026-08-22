# Patches packages in the pub cache so Windows builds work:
#
# 1. cargokit's resolve_symlinks.ps1 (super_native_extensions): `Get-Item`
#    without `-Force` throws ObjectNotFound on hidden/system path segments
#    (e.g. C:\Users\<user>\AppData, the default pub cache location).
#    Fix: https://github.com/irondash/cargokit/pull/119 (open, unmerged as of
#    super_native_extensions 0.9.1).
# 2. tailscale's hook/build.dart: Flutter's native-assets hook runner executes
#    hooks with a stripped environment (no GOCACHE, no LocalAppData), so
#    `go build -buildmode=c-shared` fails with:
#      build cache is required, but could not be located:
#      GOCACHE is not defined and %LocalAppData% is not defined
#    We inject an explicit GOCACHE into the environment the hook passes to go.
# 3. tailscale's Windows Go stubs (go/*_unsupported.go): the 0.7.0 registry
#    refactor added node_gate.go / lib.go references to package-level registry
#    symbols (httpBindingMu, tcpFdListenerMu, udpFdBindingMu + registries,
#    tailnetHTTPTransports, closeAllUdpBindings, resetTailnetHTTPTransport),
#    the Identity struct fields (0.5.0), and the reactor FFI surface — but the
#    Windows stubs were never updated. The Go package fails to compile for
#    windows/amd64, which fails the native-assets build. We add the missing
#    symbols to the Windows stubs and create go/reactor_windows.go; every
#    fd-transport/reactor API stays "not supported on Windows" at runtime.
#
# Remove this script once upstream ships these fixes.
#
# Idempotent: safe to run on every `flutter pub get` / build.
$ErrorActionPreference = 'Stop'

Write-Host "PUB_CACHE=$env:PUB_CACHE"
Write-Host "LOCALAPPDATA=$env:LOCALAPPDATA"

$pubCache = if ($env:PUB_CACHE) { $env:PUB_CACHE } else { Join-Path $env:LOCALAPPDATA 'Pub\Cache' }
$hostedDir = Join-Path $pubCache 'hosted\pub.dev'

$script:found = 0
$script:patched = 0

function Patch-CargokitScript([string]$script) {
    if (-not (Test-Path -LiteralPath $script)) { return }
    $script:found++
    $content = Get-Content -LiteralPath $script -Raw
    $target = '$item = Get-Item $realPath'
    $fixedLine = '$item = Get-Item $realPath -Force'
    if ($content.Contains($fixedLine)) {
        Write-Host "OK (already patched): $script"
    } elseif ($content.Contains($target)) {
        Set-Content -LiteralPath $script -Value $content.Replace($target, $fixedLine) -NoNewline -Encoding ASCII
        $script:patched++
        Write-Host "Patched: $script"
    } else {
        Write-Host "WARN (cargokit layout changed?): $script"
    }
    $line = Get-Content -LiteralPath $script | Where-Object { $_ -like '*Get-Item $realPath*' }
    Write-Host "  Get-Item line: $line"
}

function Patch-TailscaleHook([string]$script) {
    if (-not (Test-Path -LiteralPath $script)) { return }
    $script:found++
    $content = Get-Content -LiteralPath $script -Raw
    if ($content.Contains("env['GOCACHE']")) {
        Write-Host "OK (already patched): $script"
        return
    }
    $target = '      final result = await Process.run('
    $insert = "      env['GOCACHE'] = p.join(input.outputDirectory.toFilePath(), 'go-build');`n"
    if ($content.Contains($target)) {
        Set-Content -LiteralPath $script -Value $content.Replace($target, $insert + $target) -NoNewline -Encoding ASCII
        $script:patched++
        Write-Host "Patched: $script"
    } else {
        Write-Host "WARN (tailscale hook layout changed?): $script"
    }
    $line = Get-Content -LiteralPath $script | Where-Object { $_ -like '*GOCACHE*' }
    Write-Host "  GOCACHE line: $line"
}

function Patch-TailscaleGoStubs([string]$goDir) {
    if (-not (Test-Path -LiteralPath $goDir)) { return }
    $script:found++
    $marker = '// MaidKit windows-build stub additions'

    # --- udp_fd_unsupported.go: registry vars + closeAllUdpBindings ---------
    $udp = Join-Path $goDir 'udp_fd_unsupported.go'
    if (Test-Path -LiteralPath $udp) {
        $content = Get-Content -LiteralPath $udp -Raw
        if ($content.Contains($marker)) {
            Write-Host "OK (already patched): $udp"
        } elseif ($content.Contains('func UdpCloseBinding(id int64) {}')) {
            $content = $content.Replace('import "errors"', "import (`n`t`"errors`"`n`t`"sync`"`n)")
            $add = @"

// MaidKit windows-build stub additions: node_gate.go's census and lib.go's stopLocked reference these symbols
// on every platform; the POSIX files define them, the Windows stubs must too.
// Windows never creates UDP bridges (UdpBindFd is unsupported), so the
// registry stays empty.
var (
	udpFdBindingMu       sync.Mutex
	udpFdBindingRegistry = map[int64]struct{}{}
)

func closeAllUdpBindings() {}
"@
            $content = $content + $add
            Set-Content -LiteralPath $udp -Value $content -NoNewline -Encoding ASCII
            $script:patched++
            Write-Host "Patched: $udp"
        } else {
            Write-Host "WARN (udp stub layout changed?): $udp"
        }
    }

    # --- tcp_fd_unsupported.go: registry vars + Identity field ---------------
    $tcp = Join-Path $goDir 'tcp_fd_unsupported.go'
    if (Test-Path -LiteralPath $tcp) {
        $content = Get-Content -LiteralPath $tcp -Raw
        if ($content.Contains($marker)) {
            Write-Host "OK (already patched): $tcp"
        } elseif ($content.Contains('type TcpFdConn struct')) {
            # 0.8.0 and earlier: errors, net, time. 0.9.0 inserts "fmt" between
            # errors and net. Insert "sync" after the "errors" line either way.
            if ($content.Contains("`t`"errors`"`n`t`"fmt`"`n`t`"net`"")) {
                $content = $content.Replace(
                    "`t`"errors`"`n`t`"fmt`"",
                    "`t`"errors`"`n`t`"fmt`"`n`t`"sync`"")
            } else {
                $content = $content.Replace(
                    "`t`"errors`"`n`t`"net`"",
                    "`t`"errors`"`n`t`"sync`"`n`t`"net`"")
            }
            $content = $content.Replace(
                "`tRemotePort    int`n}",
                "`tRemotePort    int`n`t// Identity is the resolved identity of the remote node, attached at`n`t// accept time. Never populated on Windows: TcpAcceptFd is unsupported.`n`tIdentity *nodeIdentity`n}")
            $add = @"

// MaidKit windows-build stub additions: node_gate.go's DebugNodeState census references these registry
// symbols on every platform; the POSIX files define them, the Windows stubs
// must too. Windows never populates the registries (all fd transports are
// unsupported), so they stay empty.
var (
	tcpFdListenerMu       sync.Mutex
	tcpFdListenerRegistry = map[int64]struct{}{}
)
"@
            $content = $content + $add
            Set-Content -LiteralPath $tcp -Value $content -NoNewline -Encoding ASCII
            $script:patched++
            Write-Host "Patched: $tcp"
        } else {
            Write-Host "WARN (tcp stub layout changed?): $tcp"
        }
    }

    # --- http_fd_unsupported.go: registry vars + Identity + transport cache ---
    $http = Join-Path $goDir 'http_fd_unsupported.go'
    if (Test-Path -LiteralPath $http) {
        $content = Get-Content -LiteralPath $http -Raw
        if ($content.Contains($marker)) {
            Write-Host "OK (already patched): $http"
        } elseif ($content.Contains('type HttpIncomingRequest struct')) {
            $content = $content.Replace(
                'import "fmt"',
                "import (`n`t`"fmt`"`n`t`"net/http`"`n`t`"sync`"`n)")
            $content = $content.Replace(
                "`tLocalPort      int`n}",
                "`tLocalPort      int`n`t// Identity is the resolved identity of the calling node, attached at`n`t// accept time. Never populated on Windows: HttpBind/HttpAccept are`n`t// unsupported.`n`tIdentity *nodeIdentity`n}")
            $add = @"

// MaidKit windows-build stub additions: node_gate.go's DebugNodeState census and lib.go's stopLocked
// reference these symbols on every platform; the POSIX files define them, the
// Windows stubs must too. Windows never creates HTTP bindings or a tailnet
// HTTP transport (HttpBind/HttpStart are unsupported), so both stay empty.
var (
	httpBindingMu       sync.Mutex
	httpBindingRegistry = map[int64]struct{}{}
)

// httpTransportCache mirrors the POSIX transport-cache shape so node_gate.go's
// census can read it; Windows never populates it.
type httpTransportCache struct {
	mu        sync.Mutex
	transport *http.Transport
}

var tailnetHTTPTransports httpTransportCache

func resetTailnetHTTPTransport() {
	tailnetHTTPTransports.mu.Lock()
	defer tailnetHTTPTransports.mu.Unlock()
	if tailnetHTTPTransports.transport != nil {
		tailnetHTTPTransports.transport.CloseIdleConnections()
	}
	tailnetHTTPTransports.transport = nil
}
"@
            $content = $content + $add
            Set-Content -LiteralPath $http -Value $content -NoNewline -Encoding ASCII
            $script:patched++
            Write-Host "Patched: $http"
        } else {
            Write-Host "WARN (http stub layout changed?): $http"
        }
    }

    # --- reactor_windows.go: the dylib exports DuneReactor* on every platform,
    #     but the reactor only exists on POSIX (reactor.go is !windows and
    #     reactor_unsupported.go excludes windows). Create a Windows stub. -----
    $reactor = Join-Path $goDir 'reactor_windows.go'
    if (Test-Path -LiteralPath $reactor) {
        Write-Host "OK (already patched): $reactor"
    } else {
        $reactorContent = @"
//go:build windows

package tailscale

import (
	"errors"
	"unsafe"
)

// MaidKit windows-build stub additions: cmd/dylib/main.go exports the DuneReactor* FFI surface on every
// platform, but the shared fd reactor only exists on POSIX (reactor.go is
// !windows). Windows has no fd transports to poll (all bind/dial APIs are
// unsupported), so every reactor call fails with "not supported". The Dart
// side treats a -1 reactor handle / non-zero return as an error and never
// drives fd transports on Windows.

func ReactorCreate() (int64, error) {
	return -1, errors.New("shared fd reactor is not supported on Windows")
}

func ReactorClose(id int64) error {
	return errors.New("shared fd reactor is not supported on Windows")
}

func ReactorWake(id int64) error {
	return errors.New("shared fd reactor is not supported on Windows")
}

func ReactorRegister(id int64, fd int, transportID int64, events int) error {
	return errors.New("shared fd reactor is not supported on Windows")
}

func ReactorUpdate(id int64, fd int, transportID int64, events int) error {
	return errors.New("shared fd reactor is not supported on Windows")
}

func ReactorUnregister(id int64, fd int) error {
	return errors.New("shared fd reactor is not supported on Windows")
}

func ReactorWait(id int64, out unsafe.Pointer, maxEvents int, timeoutMillis int) (int, error) {
	return -1, errors.New("shared fd reactor is not supported on Windows")
}
"@
        Set-Content -LiteralPath $reactor -Value $reactorContent -NoNewline -Encoding ASCII
        $script:patched++
        Write-Host "Created: $reactor"
    }
}

# 1. cargokit resolve_symlinks.ps1 - the exact file cmake executes, via the
#    plugin symlink Flutter created during `flutter pub get` (junction or copy).
$ephemeral = Join-Path $PWD 'windows\flutter\ephemeral\.plugin_symlinks\super_native_extensions\cargokit\cmake\resolve_symlinks.ps1'
if (Test-Path -LiteralPath $ephemeral) {
    Patch-CargokitScript $ephemeral
}

# 2. cargokit copies in the pub cache (custom PUB_CACHE locations).
if (Test-Path -LiteralPath $hostedDir) {
    Get-ChildItem -LiteralPath $hostedDir -Directory |
        Where-Object { $_.Name -like 'super_native_extensions-*' } |
        ForEach-Object {
            Patch-CargokitScript (Join-Path $_.FullName 'cargokit\cmake\resolve_symlinks.ps1')
        }
}

# 3. tailscale native build hook (go build needs GOCACHE in the stripped
#    hooks-runner environment) and Windows Go stubs (missing registry/identity/
#    reactor symbols since the 0.7.0 refactor).
if (Test-Path -LiteralPath $hostedDir) {
    Get-ChildItem -LiteralPath $hostedDir -Directory |
        Where-Object { $_.Name -like 'tailscale-*' } |
        ForEach-Object {
            Patch-TailscaleHook (Join-Path $_.FullName 'hook\build.dart')
            Patch-TailscaleGoStubs (Join-Path $_.FullName 'go')
        }
}

Write-Host "scripts checked: $script:found, patched: $script:patched"
if ($script:found -eq 0) {
    Write-Error "Could not find any cargokit/tailscale scripts to patch. The Windows build will likely fail."
    exit 1
}
