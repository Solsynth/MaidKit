/// Native side of the Tailscale facade.
///
/// `package:tailscale` embeds a Go runtime through `dart:ffi` and a
/// native-assets build, so it cannot be linked into a `dart2js` build.
/// `tailscale.dart` selects this file on native targets and `tailscale_web.dart`
/// on the web, so callers only ever import the facade.
library;

export 'package:tailscale/tailscale.dart'
    show
        NodeState,
        Tailscale,
        TailscaleClient,
        TailscaleConnection,
        TailscaleConnectionOutput,
        TailscaleEndpoint,
        TailscaleException,
        TailscaleLogLevel,
        TailscaleNode,
        TailscaleRuntimeError,
        TailscaleStatus,
        TailscaleTcpException,
        TailscaleUsageException;

/// Whether the embedded Tailscale runtime is available on this platform.
bool get tailscaleRuntimeSupported => true;
