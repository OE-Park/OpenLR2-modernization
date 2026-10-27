// Prints EnumDisplayMonitors order (DxLib DisplayInfo order) and Direct3D9 adapter ordinals with their monitors.
#include <windows.h>
#include <d3d9.h>
#include <cstdio>
#pragma comment(lib, "d3d9.lib")
#pragma comment(lib, "user32.lib")
static FILE* out;
static int monIndex = 0;
static BOOL CALLBACK MonProc(HMONITOR h, HDC, LPRECT, LPARAM) {
    MONITORINFOEXA mi{}; mi.cbSize = sizeof(mi); GetMonitorInfoA(h, &mi);
    fprintf(out, "monitor[%d] %s primary=%d rect=(%ld,%ld)-(%ld,%ld) hmon=%p\n", monIndex++, mi.szDevice,
            (mi.dwFlags & MONITORINFOF_PRIMARY) ? 1 : 0, mi.rcMonitor.left, mi.rcMonitor.top, mi.rcMonitor.right, mi.rcMonitor.bottom, (void*)h);
    return TRUE;
}
int main(int argc, char** argv) {
    SetProcessDPIAware();
    out = argc > 1 ? fopen(argv[1], "w") : stdout;
    if (!out) return 2;
    EnumDisplayMonitors(nullptr, nullptr, MonProc, 0);
    IDirect3D9* d3d = Direct3DCreate9(D3D_SDK_VERSION);
    if (!d3d) { fprintf(out, "Direct3DCreate9 failed\n"); return 1; }
    for (UINT a = 0; a < d3d->GetAdapterCount(); a++) {
        D3DADAPTER_IDENTIFIER9 id{}; d3d->GetAdapterIdentifier(a, 0, &id);
        D3DDISPLAYMODE dm{}; d3d->GetAdapterDisplayMode(a, &dm);
        HMONITOR hm = d3d->GetAdapterMonitor(a);
        MONITORINFOEXA mi{}; mi.cbSize = sizeof(mi); GetMonitorInfoA(hm, &mi);
        UINT modes = d3d->GetAdapterModeCount(a, D3DFMT_X8R8G8B8);
        bool has3840x2160 = false;
        for (UINT m = 0; m < modes; m++) { D3DDISPLAYMODE x{}; d3d->EnumAdapterModes(a, D3DFMT_X8R8G8B8, m, &x); if (x.Width == 3840 && x.Height == 2160) has3840x2160 = true; }
        fprintf(out, "d3d9 adapter %u: %s (%s) monitor=%s rect=(%ld,%ld)-(%ld,%ld) mode=%ux%u@%u modes=%u has3840x2160=%d\n", a, id.DeviceName, id.Description,
                mi.szDevice, mi.rcMonitor.left, mi.rcMonitor.top, mi.rcMonitor.right, mi.rcMonitor.bottom, dm.Width, dm.Height, dm.RefreshRate, modes, has3840x2160 ? 1 : 0);
    }
    d3d->Release();
    if (out != stdout) fclose(out);
    return 0;
}
