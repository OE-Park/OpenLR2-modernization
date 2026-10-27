// OpenLR2 addition (not part of upstream DxLib 3.24f).
//
// GSYS.Screen.UseDisplayIndex indexes GSYS.Screen.DisplayInfo[], which is filled in EnumDisplayMonitors order.
// The Direct3D9 code used the same number as an adapter ordinal. Windows does not keep the two orders equal:
// on a 3-monitor machine EnumDisplayMonitors returned DISPLAY2, DISPLAY3, DISPLAY1 while Direct3D9 enumerated
// DISPLAY2, DISPLAY1, DISPLAY3, so fullscreen on DISPLAY3 asked the portrait DISPLAY1 adapter for 3840x2160 and
// device creation failed (OE-Park/OpenLR2-modernization#4). Matching by GDI device name is what the D3D11 path
// already does (Windows/DxGraphicsWin.cpp, OutputDesc.DeviceName vs DisplayInfo.Name).

#ifndef DX_D3D9ADAPTERMAP_H
#define DX_D3D9ADAPTERMAP_H

#include <wchar.h>

namespace DxLib
{

// Position of displayDeviceName (e.g. L"\\\\.\\DISPLAY3") in adapterDeviceNames, or -1 when it is empty or absent.
inline int FindD3D9AdapterForDisplay( const wchar_t *displayDeviceName, const wchar_t *const *adapterDeviceNames, int adapterCount )
{
	if( displayDeviceName == NULL || displayDeviceName[ 0 ] == L'\0' ) return -1 ;
	for( int i = 0 ; i < adapterCount ; i ++ )
	{
		if( adapterDeviceNames[ i ] != NULL && wcscmp( displayDeviceName, adapterDeviceNames[ i ] ) == 0 ) return i ;
	}
	return -1 ;
}

}

#endif // DX_D3D9ADAPTERMAP_H
